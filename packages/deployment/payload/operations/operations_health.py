"""Independent Windows health observer. No checker imports, HTTP or model calls."""
import argparse, contextlib, json, os, pathlib, sys, time, uuid
from datetime import datetime, timezone
import operations_io as control

def now(): return datetime.now(timezone.utc).isoformat()

def read_state(path):
    try:
        if not path.exists(): return {}
        if path.stat().st_size>8_000_000: raise ValueError('Health state exceeds bound')
        data=json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(data,dict): raise ValueError('Expected object')
        return data
    except (OSError,ValueError) as exc: return {'read_error':str(exc)}

def age(stamp):
    try: return (datetime.now(timezone.utc)-datetime.fromisoformat(stamp.replace('Z','+00:00'))).total_seconds()
    except (ValueError,TypeError,AttributeError): return None

def checker_health(registry, max_age=360):
    raw=read_state(pathlib.Path(registry)/'checker-health.json')
    elapsed=age(raw.get('last_success_at'))
    error=raw.get('read_error') or raw.get('error')
    healthy=not error and elapsed is not None and -5<=elapsed<=max_age
    return {**raw,'healthy':healthy,'age_seconds':elapsed,'error':error,'status':'healthy' if healthy else 'error' if error else 'stale'}

def observe(root, registry, max_age=360):
    root=pathlib.Path(root);registry=pathlib.Path(registry);registry.mkdir(parents=True,exist_ok=True)
    checker=checker_health(registry,max_age);heartbeat=read_state(root/'state/monitor-heartbeat.json')
    elapsed=age(heartbeat.get('utc'));reasons=[]
    if not checker['healthy']: reasons.append('Checker '+checker['status']+(': '+checker['error'] if checker.get('error') else ': no recent successful check'))
    if elapsed is None or elapsed < -5 or elapsed>30: reasons.append('Dispatcher monitor heartbeat is missing or stale')
    if (root/'state/monitor.stop').exists(): reasons.append('Maintenance stop is active')
    if (root/'state/runtime-quarantine.json').exists(): reasons.append('Execution quarantine requires inspection')
    key=json.dumps(reasons,sort_keys=True);old=read_state(registry/'watchdog.json');alerts=old.get('alerts',[])
    if old.get('condition')!=key and (reasons or old.get('condition')):
        alerts.append({'id':uuid.uuid4().hex,'created_at':now(),'kind':'health','title':'Operations health needs attention' if reasons else 'Operations health recovered','detail':'; '.join(reasons) if reasons else 'Checker and monitor are responding again. Prior incidents remain in history.','target':'checker'})
    state={'schema':1,'owner':'agentos-windows-watchdog','pid':os.getpid(),'observed_at':now(),'condition':key,'healthy':not reasons,'reasons':reasons,'alerts':alerts[-200:]}
    control.atomic_json(registry/'watchdog.json',state)
    return state

@contextlib.contextmanager
def singleton(registry):
    registry.mkdir(parents=True,exist_ok=True)
    with (registry/'watchdog.lock').open('a+b') as stream:
        if not stream.tell():stream.write(b'0');stream.flush()
        stream.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        yield

def record_error(registry, exc):
    message=now()+' '+type(exc).__name__+': '+str(exc)[:2000]
    try:print(message,file=sys.stderr,flush=True)
    except (OSError,ValueError,AttributeError):pass
    try:
        path=pathlib.Path(registry)/'watchdog-errors.log'
        if path.exists() and path.stat().st_size>65536:
            with path.open('rb') as stream:stream.seek(-32768,2);tail=stream.read()
            path.write_bytes(tail)
        with path.open('a',encoding='utf-8') as stream:stream.write(message+'\n')
    except OSError:pass

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--registry',required=True);p.add_argument('--once',action='store_true');p.add_argument('--interval',type=float,default=10);p.add_argument('--max-age',type=float,default=360);p.add_argument('--stop-after',type=float,default=0)
    a=p.parse_args()
    with singleton(pathlib.Path(a.registry)):
        deadline=time.monotonic()+a.stop_after if a.stop_after else float('inf')
        while time.monotonic()<deadline:
            try:observe(a.root,a.registry,a.max_age)
            except Exception as exc:
                # A temporarily locked health file must not retire the observer.
                # Leave last observed_at unchanged so stale health remains visible.
                record_error(a.registry,exc)
                if a.once:raise SystemExit(1)
            if a.once:return
            time.sleep(max(.1,a.interval))

if __name__=='__main__':main()
