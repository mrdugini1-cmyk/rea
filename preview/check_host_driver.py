"""PowerShell driver checks with fake ADB. No device/root/mount execution."""
from pathlib import Path
import tempfile,json,hashlib,subprocess,os
r=Path(__file__).resolve().parent;pwsh=str(r.parent/'tools/powershell/pwsh');env=dict(os.environ,XDG_CACHE_HOME=str(r.parent/'tools/ps-cache'),XDG_CONFIG_HOME=str(r.parent/'tools/ps-config'),XDG_DATA_HOME=str(r.parent/'tools/ps-data'))
with tempfile.TemporaryDirectory(prefix='z9x-host-',dir='/tmp') as tmp:
 d=Path(tmp);session=d/'тест с пробелами';session.mkdir();before=session/'before.apk';before.write_bytes(b'fake baseline');candidate=session/'candidate.UNSIGNED.apk';candidate.write_bytes(b'fake candidate');h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();beforehash=h(before);state=d/'state.json';log=d/'calls.jsonl';adb=d/'adb.exe'
 state.write_text(json.dumps({'phase':'APPLIED_5_MINUTES'}))
 adb.write_text('''#!/usr/bin/python3
import sys,json,pathlib
args=sys.argv[1:];root=pathlib.Path(__file__).parent
with (root/'calls.jsonl').open('a') as f:f.write(json.dumps(args,ensure_ascii=False)+'\\n')
s=json.loads((root/'state.json').read_text())
if args==['get-state']:print('device')
elif args[:3]==['shell','getprop','ro.build.fingerprint']:print('XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys')
elif args[:2]==['shell','sha256sum']:print('''+repr(beforehash)+'''+'  target')
elif args and args[0]=='push':
 if s.get('push_failure'):print('transfer failed',file=sys.stderr);sys.exit(1)
 print('1 file pushed',file=sys.stderr)
elif args and args[0]=='shell':
 cmd=' '.join(args[1:])
 if 'TRANSFER_NEVER_ARMED' in cmd:print('TRANSFER_NEVER_ARMED' if s.get('resume_safe',True) else 'PRIOR_STAGE_MAY_HAVE_STARTED')
 elif '/phase' in cmd:print(s['phase'])
 elif '/arm.sh' in cmd:
  if s.get('diagnose'):s['phase']='DIAGNOSTIC_DONE';s['exit_code']='0';(root/'state.json').write_text(json.dumps(s))
  print('ROOT_STAGE_STARTED')
 elif '/rollback.request' in cmd:s['phase']='ROLLED_BACK';(root/'state.json').write_text(json.dumps(s))
 elif '/session.log' in cmd:print('fake diagnostic log')
 elif '/exit-code' in cmd:print(s.get('exit_code',''))
''');adb.chmod(0o755)
 meta=dict(adb=str(adb),serial=None,before_apk=str(before),before_sha256=beforehash,candidate_apk=str(candidate),candidate_sha256=h(candidate));(session/'session.json').write_text(json.dumps(meta,ensure_ascii=False))
 (session/'runtime.json').write_text(json.dumps(dict(remote_stage='/data/ssh/z9x-ru-preview-'+'a'*32,before_sha256=beforehash,candidate_sha256=h(candidate))))
 cmd=[pwsh,'-NoProfile','-File',str(r/'run-preview.ps1'),'-SessionPath',str(session)];p=subprocess.run(cmd,env=env,text=True,capture_output=True);assert p.returncode==0,(p.stdout,p.stderr);assert 'APPLIED_5_MINUTES' in p.stdout
 assert len(list(session.glob('runtime.failed-transfer-*.json')))==1
 receipt=json.loads((session/'runtime.json').read_text());assert receipt['remote_stage'].startswith('/data/ssh/z9x-ru-preview-');assert receipt['before_sha256']==beforehash
 calls=[json.loads(l) for l in log.read_text().splitlines()];pushed=[a for a in calls if a and a[0]=='push'];assert len(pushed)==6,pushed
 # Two scripts, candidate, both hash files, and arm script. Every local upload exists.
 for _,local,remote in pushed:assert Path(local).exists() and remote.startswith(receipt['remote_stage']+'/')
 a=subprocess.run(cmd+['-Rollback'],env=env,text=True,capture_output=True);assert a.returncode==0,(a.stdout,a.stderr);assert 'ROLLED_BACK' in a.stdout
 auto=d/'z9x-hb-build'/'preview-test';auto.mkdir(parents=True);(auto/'session.json').write_text(json.dumps(meta,ensure_ascii=False));state.write_text(json.dumps({'phase':'APPLIED_5_MINUTES'}))
 auto_cmd=[pwsh,'-NoProfile','-File',str(r/'run-preview.ps1')]
 auto_run=subprocess.run(auto_cmd,cwd=d,env=env,text=True,capture_output=True);assert auto_run.returncode==0,(auto_run.stdout,auto_run.stderr);assert str(auto) in auto_run.stdout
 auto_rollback=subprocess.run(auto_cmd+['-Rollback'],cwd=d,env=env,text=True,capture_output=True);assert auto_rollback.returncode==0,(auto_rollback.stdout,auto_rollback.stderr)
 # Refuse resuming any stage whose remote evidence indicates it could have armed.
 state.write_text(json.dumps({'phase':'APPLIED_5_MINUTES','resume_safe':False}));log.write_text('')
 refused=subprocess.run(cmd,env=env,text=True,capture_output=True);assert refused.returncode!=0;assert 'cannot be resumed automatically' in refused.stderr
 assert not any(json.loads(l)[0]=='push' for l in log.read_text().splitlines())
 # Namespace diagnosis may replace a receipt only after the prior helper has exited.
 state.write_text(json.dumps({'phase':'ROLLBACK_BASELINE_CHANGED','exit_code':'28','diagnose':True}));log.write_text('')
 diagnostic=subprocess.run(cmd+['-Diagnose'],env=env,text=True,capture_output=True);assert diagnostic.returncode==0,(diagnostic.stdout,diagnostic.stderr);assert 'DIAGNOSTIC_DONE' in diagnostic.stdout
 diagnostic_calls=[json.loads(l) for l in log.read_text().splitlines()]
 assert not any(a[0]=='push' and a[-1].endswith('/upload.apk') for a in diagnostic_calls)
 assert not any(a[:2]==['shell','input'] for a in diagnostic_calls)
 assert any(a[0]=='push' and a[1].endswith('diagnose-body.sh') for a in diagnostic_calls)
 diag_rollback=subprocess.run(cmd+['-Rollback'],env=env,text=True,capture_output=True);assert diag_rollback.returncode==0,(diag_rollback.stdout,diag_rollback.stderr);assert 'no APK overlay' in diag_rollback.stdout
 state.write_text(json.dumps({'phase':'APPLIED_5_MINUTES','resume_safe':False}));log.write_text('')
 active=subprocess.run(cmd+['-Diagnose'],env=env,text=True,capture_output=True);assert active.returncode!=0;assert not any(json.loads(l)[0]=='push' for l in log.read_text().splitlines())
 # A native nonzero exit remains a failure even with stderr capture made non-terminating.
 (session/'runtime.json').unlink();state.write_text(json.dumps({'phase':'APPLIED_5_MINUTES','push_failure':True}));log.write_text('')
 failed=subprocess.run(cmd,env=env,text=True,capture_output=True);assert failed.returncode!=0;assert 'ADB failed: transfer failed' in failed.stderr
 assert not any('/arm.sh' in ' '.join(json.loads(l)) for l in log.read_text().splitlines())
 candidate.write_bytes(b'tampered candidate')
 (session/'runtime.json').unlink();log.write_text('')
 bad=subprocess.run(cmd,env=env,text=True,capture_output=True);assert bad.returncode!=0;assert 'Local candidate differs' in bad.stderr
 assert not any(json.loads(l)[0]=='push' for l in log.read_text().splitlines())
 result=dict(scope=__doc__,powershell_runtime='7.4.6 Linux',unicode_paths_preserved=True,latest_prepared_session_selection_passed=True,normal_apply_driver_path_passed=True,rollback_driver_path_passed=True,tampered_candidate_refused_before_upload=True,native_stderr_success_accepted=True,nonzero_native_exit_rejected=True,interrupted_prearm_transfer_resumed_with_receipt_preserved=True,possibly_armed_stage_not_resumed=True,namespace_diagnostic_after_confirmed_exit_passed=True,diagnostic_uploads_no_apk=True,diagnostic_does_not_send_home=True,diagnostic_rollback_reports_no_overlay=True,active_preview_not_interrupted_by_diagnostic=True,real_android_execution=False)
 (r/'host-driver-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
