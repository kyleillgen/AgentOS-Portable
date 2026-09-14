"""Behavioral tests for the portable checker/desk boundary; no model calls."""
import importlib.util
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timezone, timedelta

PACKAGE=pathlib.Path(__file__).resolve().parents[1]
OPS=PACKAGE/'payload/operations'
WEB=PACKAGE/'payload/desk'
sys.path[:0]=[str(OPS),str(WEB)]
from operations_core import Desk, digest, now
from operations_desk import DeskServer
from operations_health import observe, checker_health


class OperationsTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='agentos-profiles-')
        self.base=pathlib.Path(self.temp.name)
        self.root=self.base/'workspace';self.registry=self.base/'local/operations'
        for path in ('work/inbox','work/status','work/results/job','state','runners'):
            (self.root/path).mkdir(parents=True,exist_ok=True)
        self.write('runners/dispatcher.json',{'timeout_minutes':1})
        self.write('work/inbox/job.json',{'id':'job','owner':'codex','objective':'Example','acceptance':'Reviewed evidence'})
        self.write('work/status/job.json',{'state':'needs_attention','stage':'execute','note':'Blocked','updated_at':now()})
        self.write('state/monitor-heartbeat.json',{'utc':now()})
        (self.root/'work/results/job/report.md').write_text('Evidence',encoding='utf-8')
        self.desk=Desk(self.root,self.registry)

    def tearDown(self):self.temp.cleanup()

    def write(self,path,value):
        target=self.root/path;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(json.dumps(value),encoding='utf-8')

    def reconcile(self):
        result=self.desk.run_check();self.assertIsNone(result['error'])
        return self.desk.snapshot()['unresolved'][0]['recovery']

    def test_headless_recovery_does_not_replay_or_rewrite_runner_evidence(self):
        before={p:p.read_bytes() for p in (self.root/'work').rglob('*') if p.is_file()}
        record=self.reconcile();self.assertEqual(record['state'],'needs_decision')
        again=self.reconcile();self.assertEqual(record['revision'],again['revision'])
        self.assertEqual(before,{p:p.read_bytes() for p in before})
        self.assertEqual(len(list((self.root/'work/inbox').glob('*.json'))),1)
        self.assertTrue((self.registry/'notifications.json').exists())

    def test_claim_revision_fencing_expiry_and_evidence_reopening(self):
        record=self.reconcile();fingerprint=record['fingerprint']
        claimed=self.desk.claim('job',fingerprint,record['revision'],'worker-one',30)
        with self.assertRaises(ValueError):self.desk.claim('job',fingerprint,record['revision'],'worker-two',30)
        with self.assertRaises(ValueError):self.desk.update('job',fingerprint,claimed['revision'],'resolved','reviewed',['work/results/job/report.md'])
        completed=self.desk.update('job',fingerprint,claimed['revision'],'resolved','reviewed',['work/results/job/report.md'],lease_token=claimed['lease']['token'])
        self.assertTrue(self.desk.valid_resolution(completed))
        (self.root/'work/results/job/report.md').write_text('changed',encoding='utf-8')
        reopened=self.reconcile();self.assertEqual(reopened['state'],'needs_decision')
        self.assertGreater(reopened['revision'],completed['revision']);self.assertNotIn('lease',reopened)
        claimed=self.desk.claim('job',fingerprint,reopened['revision'],'worker-two',30)
        journal=self.desk.journal();journal['recoveries']['job:'+fingerprint]['lease']['expires_at']='2000-01-01T00:00:00+00:00'
        self.desk.save(journal,{'action':'test_expired_lease'})
        with self.assertRaises(ValueError):self.desk.update('job',fingerprint,claimed['revision'],'resolved','expired worker',['work/results/job/report.md'],lease_token=claimed['lease']['token'])
        expired=self.reconcile();self.assertEqual(expired['state'],'needs_decision')
        self.assertIn('expired',expired['note'])

    def test_uncertain_outcome_and_review_limit_only_create_cases(self):
        for stage,note,runtime in [('execute','timeout',{'host':{'timed_out':True}}),('review','error_max_turns',{'host':{'exit_code':0}})]:
            self.write('work/status/job.json',{'state':'needs_attention','stage':stage,'note':note})
            self.write('work/results/job/'+stage+'-runtime.json',runtime)
            record=self.reconcile();self.assertEqual(record['state'],'needs_decision')
            self.assertEqual(len(list((self.root/'work/inbox').glob('*'))),1)

    def test_stalled_running_attempt_is_visible_without_mutation(self):
        self.write('work/status/job.json',{'state':'running','stage':'execute','updated_at':'2000-01-01T00:00:00Z'})
        record=self.reconcile();self.assertEqual(record['route'],'reconcile_unknown_outcome')
        self.assertEqual(json.loads((self.root/'work/status/job.json').read_text())['state'],'running')
        self.write('work/status/job.json',{'state':'running','stage':'execute','updated_at':now()})
        self.assertEqual(self.desk.snapshot()['unresolved'],[])

    def test_corrupt_record_does_not_hide_other_attempts(self):
        self.write('work/inbox/bad.json',[])
        health=self.desk.run_check();self.assertIn('bad',health['error'])
        self.assertFalse(self.desk.snapshot()['coverage']['complete'])
        self.assertEqual(self.desk.snapshot()['unresolved'][0]['recovery']['state'],'needs_decision')

    def test_complete_scan_above_old_cutoffs(self):
        for number in range(505):
            self.write(f'work/inbox/order-{number}.json',{'id':f'order-{number}'})
            (self.root/f'work/results/job/report-{number}.md').write_text('report',encoding='utf-8')
        snap=self.desk.snapshot();self.assertEqual(len(snap['attempts']),506)
        self.assertEqual(len(snap['reports']),506);self.assertTrue(snap['coverage']['complete'])

    def test_journal_archival_retains_history(self):
        record=self.reconcile();journal=self.desk.journal()
        journal['events']=[{'revision':i,'action':'fixture'} for i in range(1000)]
        self.desk.save(journal,{'action':'after_limit'})
        journal=self.desk.journal();self.assertEqual(len(journal['event_archives']),1)
        archived=json.loads((self.registry/'history'/journal['event_archives'][0]).read_text())
        self.assertEqual(len(archived['events']),1000)
        self.assertEqual(journal['events'][0]['action'],'after_limit')

    def test_report_read_is_not_resolution(self):
        self.reconcile();report=self.desk.snapshot()['reports'][0]
        self.desk.mark_seen(report['path'],report['sha256'])
        self.assertFalse(self.desk.snapshot()['reports'][0]['unread'])
        self.assertEqual(len(self.desk.snapshot()['unresolved']),1)
        with self.assertRaises(ValueError):self.desk.report('../outside.txt')
        with self.assertRaises(ValueError):self.desk.report('state/monitor-heartbeat.json')

    def test_registry_cannot_contain_workspace(self):
        with self.assertRaises(ValueError):Desk(self.root,self.base)

    def test_http_healthy_does_not_mask_dead_checker(self):
        self.reconcile()
        server=DeskServer(('127.0.0.1',0),self.desk,WEB/'assets')
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            request=urllib.request.Request(server.origin+'/api/snapshot')
            with urllib.request.urlopen(request) as response:self.assertEqual(response.status,200)
            (self.registry/'journal.json').write_text('{corrupt',encoding='utf-8')
            self.assertTrue(self.desk.run_check()['error'])
            health=observe(self.root,self.registry);self.assertFalse(health['healthy'])
            with urllib.request.urlopen(request) as response:
                snapshot=json.load(response);self.assertFalse(snapshot['checker']['healthy'])
            post=urllib.request.Request(server.origin+'/api/recover',data=b'{}',headers={'Content-Type':'application/json'},method='POST')
            with self.assertRaises(urllib.error.HTTPError) as error:urllib.request.urlopen(post)
            self.assertEqual(error.exception.code,403)
        finally:server.shutdown();thread.join(3);server.server_close()

    def test_checker_runs_as_separate_process_without_desk(self):
        command=[sys.executable,'-E','-s',str(OPS/'operations_service.py'),'--root',str(self.root),'--registry',str(self.registry),'--stop-after','5']
        process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        try:
            deadline=time.monotonic()+10
            while time.monotonic()<deadline and not (self.registry/'checker-health.json').exists():time.sleep(.1)
            self.assertTrue(checker_health(self.registry)['healthy'])
            self.assertEqual(len(self.desk.snapshot()['unresolved']),1)
            result=subprocess.run([sys.executable,'-E','-s',str(OPS/'operations_service.py'),'--root',str(self.root),'--registry',str(self.registry),'--once'],capture_output=True,timeout=10)
            self.assertNotEqual(result.returncode,0,'second checker must not acquire the singleton')
            process.communicate(timeout=10);self.assertEqual(process.returncode,0)
            state=json.loads((self.registry/'checker-health.json').read_text());state['last_success_at']='2000-01-01T00:00:00Z'
            (self.registry/'checker-health.json').write_text(json.dumps(state))
            result=subprocess.run([sys.executable,'-E','-s',str(OPS/'operations_health.py'),'--root',str(self.root),'--registry',str(self.registry),'--once'],capture_output=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stderr.decode())
            self.assertFalse(json.loads((self.registry/'watchdog.json').read_text())['healthy'])
        finally:
            if process.poll() is None:process.kill();process.communicate()

    def test_interface_can_retire_without_stopping_checker(self):
        checker=subprocess.Popen([sys.executable,'-E','-s',str(OPS/'operations_service.py'),'--root',str(self.root),'--registry',str(self.registry),'--stop-after','12'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        interface=subprocess.Popen([sys.executable,'-E','-s',str(WEB/'operations_desk.py'),'--root',str(self.root),'--registry',str(self.registry),'--port','0'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        try:
            deadline=time.monotonic()+8
            while time.monotonic()<deadline and not (self.registry/'interface.lock').exists():time.sleep(.1)
            self.assertTrue((self.registry/'interface.lock').exists())
            time.sleep(.3)
            (self.registry/'interface.stop').write_text('remove interface')
            interface.communicate(timeout=8);self.assertEqual(interface.returncode,0)
            self.assertIsNone(checker.poll(),'interface exit stopped checker')
            self.assertTrue(checker_health(self.registry)['healthy'])
        finally:
            for process in (interface,checker):
                if process.poll() is None:process.kill()
                process.communicate()

    def test_unattended_monitor_wrapper_retires_gracefully(self):
        self.write('runners/dispatcher.json',{'host':os.environ['COMPUTERNAME'],'settle_seconds':30,'timeout_minutes':1})
        shutil.copyfile(PACKAGE.parent/'portable/template/runners/monitor.ps1',self.root/'runners/monitor.ps1')
        (self.root/'state/monitor-heartbeat.json').unlink()
        engine=pathlib.Path(os.environ['SystemRoot'])/'System32/WindowsPowerShell/v1.0/powershell.exe'
        process=subprocess.Popen([str(engine),'-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',str(OPS/'run-monitor.ps1'),'-Root',str(self.root)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        try:
            deadline=time.monotonic()+15
            while time.monotonic()<deadline and process.poll() is None and not (self.root/'state/monitor-heartbeat.json').exists():time.sleep(.1)
            self.assertTrue((self.root/'state/monitor-heartbeat.json').exists(),'keep-awake wrapper failed to start monitor')
            (self.root/'state/monitor.stop').write_text('test graceful retirement')
            out,err=process.communicate(timeout=15)
            self.assertEqual(process.returncode,0,err.decode(errors='replace'))
        finally:
            if process.poll() is None:process.kill();process.communicate()

    def test_watchdog_survives_locked_output_and_recovers(self):
        import ctypes
        self.reconcile();observe(self.root,self.registry)
        path=self.registry/'watchdog.json';before=path.read_bytes()
        kernel=ctypes.WinDLL('kernel32',use_last_error=True)
        kernel.CreateFileW.argtypes=[ctypes.c_wchar_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_void_p]
        kernel.CreateFileW.restype=ctypes.c_void_p
        kernel.CloseHandle.argtypes=[ctypes.c_void_p]
        lock=kernel.CreateFileW(str(path),0x80000000,0,None,3,0,None)
        self.assertNotIn(lock,(None,ctypes.c_void_p(-1).value))
        process=subprocess.Popen([sys.executable,'-E','-s',str(OPS/'operations_health.py'),'--root',str(self.root),'--registry',str(self.registry),'--interval','.1','--stop-after','3'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        try:
            time.sleep(.7)
            self.assertIsNone(process.poll(),'temporary sharing conflict terminated watchdog')
            self.assertTrue((self.registry/'watchdog-errors.log').exists(),'failure was not recorded')
            kernel.CloseHandle(lock);lock=None
            out,err=process.communicate(timeout=10)
            self.assertEqual(process.returncode,0,err.decode(errors='replace'))
            self.assertNotEqual(path.read_bytes(),before)
            self.assertTrue(json.loads(path.read_text())['healthy'])
        finally:
            if lock:kernel.CloseHandle(lock)
            if process.poll() is None:process.kill();process.communicate()


if __name__=='__main__':unittest.main(verbosity=2)
