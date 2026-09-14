"""Portable recovery records. No server, model client or order publisher."""
from __future__ import annotations
import contextlib, hashlib, json, os, pathlib, re, uuid
from datetime import datetime, timezone, timedelta
import operations_io as control
from operations_health import checker_health, read_state

MAX_JSON = 2_000_000
MAX_REPORT = 2_000_000
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$")
TERMINAL = {"blocked", "needs_attention"}

def now(): return datetime.now(timezone.utc).isoformat()
def digest(data): return hashlib.sha256(data).hexdigest()

def safe_file(root, relative):
    if not isinstance(relative, str) or "\\" in relative or ":" in relative:
        raise ValueError("Invalid relative path")
    parts = pathlib.PurePosixPath(relative)
    if parts.is_absolute() or ".." in parts.parts:
        raise ValueError("Path escapes workspace")
    path = root.joinpath(*parts.parts)
    control.reject_redirects(root, path, "desk file")
    return control.ensure_within(root, path, "desk file", strict=True)

def read_bytes(root, relative, limit=MAX_JSON):
    path = safe_file(root, relative)
    if path.stat().st_size > limit: raise ValueError("File exceeds display limit")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit: raise ValueError("File exceeds display limit")
    return data

def read_json(root, relative):
    result = json.loads(read_bytes(root, relative).decode("utf-8-sig"))
    if not isinstance(result, dict): raise ValueError("Expected a JSON object")
    return result

@contextlib.contextmanager
def local_lock(folder):
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / "desk.lock").open("a+b") as stream:
        if stream.tell() == 0: stream.write(b"0"); stream.flush()
        stream.seek(0)
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        try: yield
        finally:
            stream.seek(0)
            if os.name == "nt": msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else: fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

class Desk:
    def __init__(self, root, registry):
        for value in (root, registry):
            absolute=pathlib.Path(os.path.abspath(value))
            control.reject_redirects(pathlib.Path(absolute.anchor),absolute,'operations location')
        self.root = pathlib.Path(root).resolve(strict=True)
        self.registry = pathlib.Path(registry).resolve()
        if self.registry == self.root or self.root in self.registry.parents or self.registry in self.root.parents:
            raise ValueError("Desk journal must be outside the synchronized root")
        self.registry.mkdir(parents=True, exist_ok=True)

    def journal(self):
        path = self.registry / "journal.json"
        if not path.exists(): return {"schema": 1, "revision": 0, "recoveries": {}, "seen": {}, "events": []}
        if path.stat().st_size > 8_000_000: raise ValueError("Desk journal exceeds bound; operator archival required")
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("schema") != 1 or not isinstance(data.get("recoveries"), dict): raise ValueError("Invalid desk journal")
        return data

    def save(self, journal, event):
        if len(journal["events"]) >= 1000:
            events=journal["events"]
            encoded=json.dumps(events,sort_keys=True).encode()
            archive=self.registry/'history'/('events-'+digest(encoded)+'.json')
            archive.parent.mkdir(exist_ok=True)
            if not archive.exists(): control.atomic_json(archive,{'schema':1,'events':events})
            elif json.loads(archive.read_text(encoding='utf-8'))['events'] != events: raise ValueError('Archive collision')
            refs=journal.setdefault('event_archives',[])
            if archive.name not in refs: refs.append(archive.name)
            journal['events']=[]
        journal["revision"] += 1
        journal["events"].append({"revision": journal["revision"], "at": now(), **event})
        control.atomic_json(self.registry / "journal.json", journal)

    def attempt(self, job):
        if not SAFE_ID.fullmatch(job): raise ValueError("Invalid attempt id")
        order_path = f"work/inbox/{job}.json"
        status_path = f"work/status/{job}.json"
        order_bytes=read_bytes(self.root, order_path)
        order=json.loads(order_bytes.decode('utf-8-sig'))
        if not isinstance(order,dict): raise ValueError('Order must be an object')
        snapshots={order_path:digest(order_bytes)}
        try:
            status_bytes=read_bytes(self.root,status_path)
            status=json.loads(status_bytes.decode('utf-8-sig')); snapshots[status_path]=digest(status_bytes)
            if not isinstance(status,dict): raise ValueError('Status must be an object')
        except FileNotFoundError:
            status={"state":"queued"}; snapshots[status_path]=None
        runtime = {}
        stage = status.get("stage", "execute")
        if stage not in ("execute", "review"): stage = "execute"
        runtime_path = f"work/results/{job}/{stage}-runtime.json"
        if (self.root / runtime_path).exists():
            runtime_bytes=read_bytes(self.root, runtime_path)
            runtime=json.loads(runtime_bytes.decode('utf-8-sig')); snapshots[runtime_path]=digest(runtime_bytes)
        fingerprint = digest(json.dumps(snapshots, sort_keys=True).encode())
        report_path = f"work/results/{job}/implementation-report.md"
        explanation = status.get("note", "No explanation recorded")
        route = "inspect_existing_output"
        if (self.root / report_path).exists():
            report = read_bytes(self.root, report_path, MAX_REPORT).decode("utf-8-sig", "replace")
            if "ordinary execution envelope" in report.lower() and "maintenance" in report.lower():
                explanation = "Runner maintenance was assigned to an ordinary worker. A direct host maintenance session is required."
                route = "direct_maintenance"
        host = runtime.get("host") or {}
        wrapper = runtime.get("wrapper") or {}
        if host.get("timed_out") or host.get("cleanup_status") == "unconfirmed" or wrapper.get("children_retired") is False:
            route = "reconcile_unknown_outcome"
        stalled=False
        if status.get('state') in ('running','pending'):
            try:
                cfg=read_json(self.root,'runners/dispatcher.json')
                elapsed=(datetime.now(timezone.utc)-datetime.fromisoformat(status['updated_at'].replace('Z','+00:00'))).total_seconds()
                stalled=elapsed > max(300,2*float(cfg['timeout_minutes'])*60+120)
            except (KeyError,ValueError,TypeError):
                stalled=True
            if stalled:
                explanation='Attempt has no timely completion evidence. Inspect the runner lock, processes and ledger before another attempt.'
                route='reconcile_unknown_outcome'
        return {"id": job, "state": status.get("state", "unknown"), "stage": stage,
                "objective": order.get("objective", job), "project": order.get("project_id"),
                "task": order.get("task_id"), "is_recovery_followup":bool(order.get('recovery_request_id')), "updated_at": status.get("updated_at"),
                "explanation": explanation, "route": route, "fingerprint": fingerprint, "snapshots": snapshots,"stalled":stalled}

    def request(self, job, fingerprint, source="local_dashboard"):
        with local_lock(self.registry):
            attempt = self.attempt(job)
            if attempt["fingerprint"] != fingerprint: raise ValueError("Attempt changed; refresh before requesting recovery")
            if attempt["state"] not in TERMINAL and not attempt['stalled']: raise ValueError("Only failed or demonstrably stalled attempts can request recovery")
            journal = self.journal()
            key = job + ":" + fingerprint
            if key in journal["recoveries"]: return journal["recoveries"][key]
            record = {"request_id": "recover-" + uuid.uuid4().hex, "attempt_id": job,
                      "fingerprint": fingerprint, "revision": 1, "state": "requested", "route": attempt["route"],
                      "requested_at": now(), "updated_at": now(), "source": source,
                      "note": "Queued for coordinator inspection; original attempt will not be replayed.",
                      "snapshots": attempt["snapshots"], "evidence": [], "linked_task": None}
            brief=f"work/recovery/{record['request_id']}/assignment.md"
            target=self.root/brief
            control.reject_redirects(self.root,target,'recovery brief')
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_text('# Recovery assignment\n\nThis case is owned by the IAF Protocol system checker. Any compatible authorized worker may claim it; no chat app owns its lifecycle.\n\n'
                f"Source attempt: {job}\n\nSuggested route: {attempt['route']}\n\nObserved blocker: {attempt['explanation']}\n\n"
                'Inspect original order, protected ledger, runtime and existing output before taking action. Preserve original status and do not repeat an unknown external action. Ordinary workers cannot perform host maintenance.\n\n'
                'Use the standalone operations_service.py CLI --snapshot to obtain this recovery fingerprint and current revision, then --claim <attempt> --fingerprint <fingerprint> --expected-revision <revision> --owner <worker> --lease-seconds 1800. Keep the returned lease token and use it for active updates. See extensions/operations/README.md for the full protocol.\n\n'
                'Acceptance: establish a concrete recovery result with independent evidence, or record the exact unresolved condition and next owner. A claimed case, queued follow-up or a generated plan is not completion.\n',encoding='utf-8')
            record['brief']=brief
            record['brief_sha256']=digest(target.read_bytes())
            journal["recoveries"][key] = record
            self.save(journal, {"action": "recovery_requested", "request_id": record["request_id"], "source": source})
            return record

    def update(self, job, fingerprint, revision, state, note, evidence, linked_task=None, lease_token=None):
        if state not in {"active", "needs_decision", "needs_maintenance", "resolved"}: raise ValueError("Invalid recovery state")
        if not note or len(note) > 4000: raise ValueError("A concise recovery note is required")
        captured = [{"path": p, "sha256": digest(read_bytes(self.root, p, MAX_REPORT))} for p in evidence]
        if state == "resolved" and not captured: raise ValueError("Resolution requires concrete evidence")
        if linked_task and not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_-]+", linked_task): raise ValueError("Invalid linked project/task")
        with local_lock(self.registry):
            journal = self.journal(); key = job + ":" + fingerprint
            record = journal["recoveries"][key]
            if record["revision"] != revision: raise ValueError("Stale recovery revision")
            lease=record.get('lease') or {}
            if lease_token and (lease.get('token') != lease_token or lease.get('expires_at','') <= now()): raise ValueError('Expired or stale worker claim; claim again')
            if lease.get('expires_at','') > now() and lease.get('token') != lease_token: raise ValueError('Active worker lease token required')
            if self.attempt(job)["fingerprint"] != fingerprint: raise ValueError("Source attempt changed; reconcile before updating")
            record.update(state=state, note=note, evidence=captured, updated_at=now(), revision=revision+1)
            if linked_task: record["linked_task"] = linked_task
            self.save(journal, {"action": "recovery_" + state, "request_id": record["request_id"], "note": note, "evidence": captured})
            return record

    def reopen(self, attempt):
        with local_lock(self.registry):
            journal=self.journal();record=journal['recoveries'][attempt['id']+':'+attempt['fingerprint']]
            if record['state']!='resolved' or self.valid_resolution(record): return record
            if self.attempt(attempt['id'])['fingerprint']!=attempt['fingerprint']: raise ValueError('Source changed while reopening')
            prior={'note':record['note'],'evidence':record['evidence']}
            record.update(state='needs_decision',revision=record['revision']+1,updated_at=now(),note='Resolution evidence changed or is missing. Inspect and claim this reopened case.',prior_resolution=prior,evidence=[])
            record.pop('lease',None)
            self.save(journal,{'action':'resolution_invalidated','request_id':record['request_id'],'prior_resolution':prior})
            return record

    def claim(self, job, fingerprint, revision, owner, seconds=1800):
        if not SAFE_ID.fullmatch(owner or '') or not 30 <= seconds <= 3600: raise ValueError('Valid owner and finite lease required')
        with local_lock(self.registry):
            journal=self.journal();record=journal['recoveries'][job+':'+fingerprint]
            if record['revision'] != revision or self.attempt(job)['fingerprint'] != fingerprint: raise ValueError('Stale recovery claim')
            lease=record.get('lease') or {}
            if lease.get('expires_at','') > now() and lease.get('owner') != owner: raise ValueError('Recovery already owned by another worker')
            if record['state'] == 'resolved': raise ValueError('Resolved recovery cannot be claimed')
            record.update(state='active',revision=revision+1,updated_at=now(),note='Claimed by '+owner,
                          lease={'owner':owner,'token':uuid.uuid4().hex,'expires_at':(datetime.now(timezone.utc)+timedelta(seconds=seconds)).isoformat()})
            self.save(journal,{'action':'recovery_claimed','request_id':record['request_id'],'owner':owner})
            return record

    def reconcile_attempt(self, attempt):
        record=attempt.get('recovery')
        if attempt.get('resolution_invalid'): record=self.reopen(attempt)
        if not record: record=self.request(attempt['id'],attempt['fingerprint'],'system_checker')
        if record['state'] == 'requested':
            route=attempt['route']
            state='needs_maintenance' if route == 'direct_maintenance' else 'needs_decision'
            note={'direct_maintenance':'Direct host maintenance is required. Any compatible worker can claim this recovery; the ordinary dispatcher envelope cannot perform it.',
                  'reconcile_unknown_outcome':'The previous outcome or cleanup is uncertain. Inspect owned processes, ledger and existing output before another attempt.',
                  'inspect_existing_output':'Inspect the existing result and runtime. Claim this recovery to preserve valid work and prepare a linked follow-up; do not replay blindly.'}[route]
            self.update(attempt['id'],attempt['fingerprint'],record['revision'],state,note,[])
        elif record['state'] == 'active' and record.get('lease',{}).get('expires_at','9999') < now():
            self.update(attempt['id'],attempt['fingerprint'],record['revision'],'needs_decision','Worker lease expired. Reconcile its partial output; the system has not replayed the task.',[])

    def reconcile(self):
        snapshot=self.snapshot();pass_errors=list(snapshot['issues'])
        for attempt in snapshot['unresolved']:
            try: self.reconcile_attempt(attempt)
            except Exception as exc: pass_errors.append(attempt['id']+': '+str(exc))
        snapshot=self.snapshot()
        pass_errors.extend(snapshot['issues'])
        report_hashes={r['path']:r['sha256'] for r in snapshot['reports']}
        current={}
        for a in snapshot['unresolved']:
            record=a.get('recovery') or {}
            key='recovery:'+a['id']
            current[key]={'kind':'recovery','title':'Task needs attention: '+a['id'], 'detail':record.get('note',a['explanation']),
                          'fingerprint':digest(json.dumps([a['fingerprint'],record.get('state'),record.get('revision'),a['resolution_invalid']]).encode()),'target':a['id']}
        for case in snapshot['project_attention']:
            current['project:'+case['key']]={'kind':'project','title':'Project task needs attention: '+case['key'],'detail':case['note'],'fingerprint':digest(json.dumps([case['source_revision'],case['reason']]).encode()),'target':case['key']}
        for error in sorted(set(pass_errors)):
            key='error:'+digest(error.encode())
            current[key]={'kind':'error','title':'Operations record needs inspection','detail':error,'fingerprint':key,'target':'checker'}
        if not snapshot['monitor_fresh'] or snapshot['stop_requested'] or snapshot['quarantined']:
            flags=[snapshot['monitor_fresh'],snapshot['stop_requested'],snapshot['quarantined']]
            current['monitor']={'kind':'monitor','title':'IAF Protocol monitor needs attention','detail':'Check heartbeat, maintenance stop and quarantine in the operations desk.','fingerprint':digest(json.dumps(flags).encode()),'target':'monitor'}
        for r in snapshot['reports']:
            if r['name'] in ('report.md','implementation-report.md','maintenance-completion.md','execute.txt'):
                current['report:'+r['path']]={'kind':'report','title':'Report available: '+r['task'],'detail':r['name'],'fingerprint':r['sha256'],'target':r['path']}
        # One local writer; atomic snapshots keep tray and browser readers safe.
        with local_lock(self.registry):
            path=self.registry/'notifications.json'
            old=json.loads(path.read_text(encoding='utf-8')) if path.exists() else None
            known=(old or {}).get('known',{})
            alerts=(old or {}).get('alerts',[])
            for key,value in current.items():
                # Historical reports appear unread in the desk; do not fire a burst
                # of desktop balloons for every old report at first installation.
                if old is None and value['kind']=='report': continue
                if known.get(key) != value['fingerprint']:
                    alerts.append({'id':uuid.uuid4().hex,'created_at':now(),**value})
            for key in known.keys()-current.keys():
                if key.startswith(('recovery:','project:')):
                    alerts.append({'id':uuid.uuid4().hex,'created_at':now(),'kind':'recovery','title':'Recovery state changed','detail':key.split(':',1)[1]+' no longer has its previous attention condition. Check its evidence; this does not imply project completion.','target':key.split(':',1)[1]})
            payload={'schema':1,'owner':'agentos-system-checker','last_checked_at':now(),'known':{k:v['fingerprint'] for k,v in current.items()},'report_baseline':report_hashes,'alerts':alerts[-500:]}
            control.atomic_json(path,payload)
        return {'unresolved':len(snapshot['unresolved']),'reports':len(snapshot['reports']),'last_checked_at':payload['last_checked_at'],'errors':sorted(set(pass_errors))}

    def run_check(self):
        previous=read_state(self.registry/'checker-health.json')
        errors=[]
        try: errors=self.reconcile().get('errors',[])
        except Exception as exc: errors=[str(exc)]
        stamp=now()
        health={'schema':1,'owner':'agentos-system-checker','pid':os.getpid(),'last_attempt_at':stamp,'last_success_at':previous.get('last_success_at') if errors else stamp,'error':'; '.join(errors[:10]) if errors else None}
        # If this write fails, the independent watchdog still observes stale/missing health.
        control.atomic_json(self.registry/'checker-health.json',health)
        if not errors and (self.registry/'checker-error.json').exists(): (self.registry/'checker-error.json').unlink()
        return health

    def valid_resolution(self, record):
        if not record or record.get("state") != "resolved" or not record.get("evidence"): return False
        try: return all(digest(read_bytes(self.root, e["path"], MAX_REPORT)) == e["sha256"] for e in record["evidence"])
        except (OSError, ValueError): return False

    def report(self, relative):
        parts = pathlib.PurePosixPath(relative).parts
        if len(parts) < 4 or parts[:2] not in (("work", "results"),("work","recovery")): raise ValueError("Only result reports and recovery briefs are available")
        if pathlib.Path(relative).suffix.lower() not in {".md", ".txt", ".json", ".csv", ".pdf", ".docx", ".xlsx", ".pptx"}: raise ValueError("Unsupported report type")
        return read_bytes(self.root, relative, MAX_REPORT)

    def mark_seen(self, relative, fingerprint):
        if digest(self.report(relative)) != fingerprint: raise ValueError("Report changed; reopen it first")
        with local_lock(self.registry):
            journal = self.journal()
            if journal["seen"].get(relative) == fingerprint: return {"seen": True}
            journal["seen"][relative] = fingerprint
            self.save(journal, {"action": "report_seen", "path": relative, "sha256": fingerprint})
        return {"seen": True}

    def snapshot(self):
        issues=[]; attempts=[]; reports=[]; projects=[]
        try: journal=self.journal()
        except Exception as exc:
            journal={'recoveries':{},'seen':{},'project_cases':{}};issues.append('Recovery journal unavailable: '+str(exc))
        try:
            heartbeat = read_json(self.root, "state/monitor-heartbeat.json")
            age = (datetime.now(timezone.utc) - datetime.fromisoformat(heartbeat["utc"].replace("Z", "+00:00"))).total_seconds()
        except (OSError, ValueError, KeyError) as exc: heartbeat={};age=None;issues.append(str(exc))
        for path in sorted((self.root / "work/inbox").glob("*.json")):
            try:
                attempt = self.attempt(path.stem)
                record = journal["recoveries"].get(attempt["id"] + ":" + attempt["fingerprint"])
                attempt["recovery"] = record
                attempt["resolved_later"] = self.valid_resolution(record)
                attempt["resolution_invalid"] = bool(record and record.get("state") == "resolved" and not attempt["resolved_later"])
                attempts.append(attempt)
            except (OSError, ValueError, KeyError) as exc: issues.append(f"{path.stem}: {exc}")
        for directory in sorted((self.root / "work/results").iterdir()):
            if not directory.is_dir() or directory.is_symlink(): continue
            for path in sorted(directory.iterdir()):
                if not path.is_file(): continue
                if path.suffix.lower() not in {".md", ".txt", ".pdf", ".docx", ".xlsx", ".pptx"}: continue
                if any(token in path.name for token in ("-prompt", "-stderr", "-stdout", "backup")): continue
                if path.name in {"execute.txt", "review.txt"} and any(directory.glob("*.md")): continue
                relative = path.relative_to(self.root).as_posix()
                try:
                    data = self.report(relative); fingerprint=digest(data)
                    reports.append({"path": relative, "name": path.name, "task": directory.name, "sha256": fingerprint,
                                    "unread": journal["seen"].get(relative) != fingerprint, "modified": path.stat().st_mtime})
                except (OSError, ValueError) as exc: issues.append(f"{relative}: {exc}")
        # File-protocol tasks are coordinated manually. No project-event adapter is installed.
        unresolved=[a for a in attempts if (a["state"] in TERMINAL or a['stalled']) and not a["resolved_later"]]
        notice_path=self.registry/'notifications.json'
        notices=read_state(notice_path)
        if notices.get('read_error'): issues.append('Alerts unavailable: '+notices['read_error'])
        watchdog=read_state(self.registry/'watchdog.json')
        health=checker_health(self.registry)
        project_attention=[]
        for project in projects:
            if project.get('attention_reason'):
                key=project['project_id']+'/'+project['task_id']
                case=journal.get('project_cases',{}).get(key)
                if not case or case.get('source_revision')!=project['revision'] or case.get('state')!='needs_decision':
                    case={'key':key,'source_revision':project['revision'],'reason':project['attention_reason'],'note':project['attention_reason']+'. Awaiting checker reconciliation.','state':'needs_decision'}
                project_attention.append(case)
        return {"observed_at": now(), "heartbeat": heartbeat, "heartbeat_age": age,
                "monitor_fresh": age is not None and -5 <= age <= 30, "stop_requested": (self.root/"state/monitor.stop").exists(),
                "quarantined": (self.root/"state/runtime-quarantine.json").exists(), "attempts": attempts,
                "unresolved": unresolved, "reports": sorted(reports, key=lambda r:r["modified"], reverse=True),
                "projects": projects, "project_attention":project_attention, "coverage":{"complete":not issues,"attempts":len(attempts),"reports":len(reports),"projects":len(projects)}, "issues": issues, "recoveries": list(journal["recoveries"].values()),
                "checker":{**health,'owner':'agentos-system-checker','last_checked_at':health.get('last_success_at')},'watchdog':watchdog,'alerts':notices.get('alerts',[])+watchdog.get('alerts',[])}
