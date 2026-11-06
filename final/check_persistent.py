from pathlib import Path
import tempfile,subprocess,json,os,hashlib
r=Path(__file__).resolve().parent;k=r/'build-kit';pwsh=str(r.parent/'tools/powershell/pwsh');env=dict(os.environ,XDG_CACHE_HOME=str(r.parent/'tools/ps-cache'),XDG_CONFIG_HOME=str(r.parent/'tools/ps-config'),XDG_DATA_HOME=str(r.parent/'tools/ps-data'))
with tempfile.TemporaryDirectory(dir='/tmp',prefix='z9x-persist-') as tmp:
 d=Path(tmp);session=d/'с пробелами';session.mkdir();before=session/'before.apk';before.write_bytes(b'baseline');after=session/'new.apk';after.write_bytes(b'candidate');sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();adb=d/'adb.exe'
 (d/'state.json').write_text(json.dumps({'phase':'','live':sha(before)}))
 adb.write_text('''#!/usr/bin/python3
import json,pathlib,sys
r=pathlib.Path(__file__).parent;s=json.loads((r/'state.json').read_text());a=sys.argv[1:]
with (r/'calls.jsonl').open('a') as f:f.write(json.dumps(a)+'\\n')
if a==['get-state']:print('device')
elif a and a[0]=='push':print('1 file pushed',file=sys.stderr)
elif a and a[0]=='shell':
 c=' '.join(a[1:])
 if c=='cat /proc/sys/kernel/random/boot_id':print(s.get('boot','11111111-1111-1111-1111-111111111111'))
 elif c=='cat /data/z9x-ru-persistent/boot.id':print(s.get('boot','11111111-1111-1111-1111-111111111111'))
 elif c=='getprop ro.build.fingerprint':print('XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys')
 elif c=='getprop xgimi.remoteDebug.on':print('true')
 elif c.startswith('sha256sum '):print(s['live']+'  target')
 elif c.startswith('stat '):print('0:600:0')
 elif 'host.ready' in c:s['phase']='PERSISTENT_ACTIVE'
 elif '/rollback.request' in c:s['phase']='ROLLED_BACK'
 elif '/phase' in c:print(s['phase'])
 elif '/arm.sh' in c:print('ROOT_STAGE_STARTED')
 elif '/session.log' in c:print('mock worker log')
 (r/'state.json').write_text(json.dumps(s))
''');adb.chmod(0o755)
 meta=dict(fingerprint='XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys',adb=str(adb),serial=None,before_apk=str(before),candidate_apk=str(after),before_sha256=sha(before),candidate_sha256=sha(after));(session/'session.json').write_text(json.dumps(meta,ensure_ascii=False))
 cmd=[pwsh,'-NoProfile','-File',str(k/'install-persistent.ps1'),'-SessionPath',str(session)]
 a=subprocess.run(cmd,env=env,text=True,capture_output=True);assert a.returncode==0,(a.stdout,a.stderr);assert 'ACTIVE_WITHOUT_TIMEOUT' in a.stdout
 calls=[json.loads(l) for l in (d/'calls.jsonl').read_text().splitlines()];assert len([c for c in calls if c[0]=='push'])==8
 # Repeated installs preserve the active receipt and cannot restart the SSH worker.
 (d/'calls.jsonl').write_text('');a=subprocess.run(cmd,env=env,text=True,capture_output=True);assert a.returncode!=0 and 'already recorded' in a.stderr
 calls=[json.loads(l) for l in (d/'calls.jsonl').read_text().splitlines()];assert not any('ctl.restart' in ' '.join(c) for c in calls)
 verify=[pwsh,'-NoProfile','-File',str(k/'verify-persistent.ps1'),'-SessionPath',str(session)]
 a=subprocess.run(verify,env=env,text=True,capture_output=True);assert a.returncode!=0 and 'Same device boot' in a.stderr
 (d/'state.json').write_text(json.dumps({'phase':'PERSISTENT_ACTIVE','live':sha(after),'boot':'22222222-2222-2222-2222-222222222222'}))
 a=subprocess.run(verify,env=env,text=True,capture_output=True);assert a.returncode==0 and 'BOOT_PERSISTENCE_VERIFIED' in a.stdout,(a.stdout,a.stderr)
 (d/'state.json').write_text(json.dumps({'phase':'PERSISTENT_ACTIVE','live':sha(before)}))
 a=subprocess.run(cmd+['-Rollback'],env=env,text=True,capture_output=True);assert a.returncode==0 and 'boot hook removed' in a.stdout,(a.stdout,a.stderr)
 (session/'persistent.json').unlink();(d/'state.json').write_text(json.dumps({'phase':'','live':'0'*64}));(d/'calls.jsonl').write_text('');a=subprocess.run(cmd,env=env,text=True,capture_output=True);assert a.returncode!=0 and 'live APK' in a.stderr
 assert not any(json.loads(l)[0]=='push' for l in (d/'calls.jsonl').read_text().splitlines())
result=dict(host_simulation_passed=True,unicode_paths=True,stderr_success_handled=True,active_receipt_prevents_restart=True,foreign_baseline_rejected_before_upload=True,uninstall_checks_original_hash_and_params=True,same_boot_verification_refused=True,new_boot_hash_and_worker_verified=True,real_device_installation=False,real_device_reboot=False)
(r/'persistent-host-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
