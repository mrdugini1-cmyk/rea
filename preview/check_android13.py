from pathlib import Path
import subprocess,tempfile,json
r=Path(__file__).resolve().parent
source=(r/'runtime-body.sh').read_text();helper=source[source.index('mount_id() {'):source.index('\nbounded()')]
block=source[source.index(' if maintenance_running; then',source.index('main()')):source.index(' # Let an already dispatched')]
with tempfile.TemporaryDirectory(dir='/tmp') as t:
 p=Path(t)/'target';p.write_text('fixture')
 for shell in ['/bin/sh',str(r.parent/'tools/mksh/usr/bin/mksh')]:
  script=helper+'\nTARGET=$1\nmount_id\nID=$(mount_id)\n[ -n "$ID" ]\nprintf "%s\\n" "$ID"\n'
  a=subprocess.run([shell,'-c',script,'test',str(p)],capture_output=True,text=True)
  assert a.returncode==0 and len(a.stdout.splitlines())==2 and a.stdout.splitlines()[0]==a.stdout.splitlines()[1] and a.stdout.splitlines()[0].isdigit(),(a.stdout,a.stderr)
  pre='set -eu\nMAINT=test\nMAINT_STOPPED=0\nmaintenance_running() { [ "$MAINT_STOPPED" = 0 ]; }\nbounded() { echo "Service stopped"; return 255; }\n'
  a=subprocess.run([shell,'-c',pre+block+'\necho STATE_VERIFIED\n'],capture_output=True,text=True)
  assert a.returncode==0 and 'STATE_VERIFIED' in a.stdout,(a.stdout,a.stderr)
  a=subprocess.run([shell,'-c',pre.replace('[ "$MAINT_STOPPED" = 0 ]','return 2')+block],capture_output=True,text=True)
  assert a.returncode==44,(a.stdout,a.stderr)
result=dict(android13_stopservice_255_does_not_abort=True,unknown_service_state_refused=True,mount_id_direct_and_substitution_passed=True,shells=['sh','mksh'],device_preview_pending=True)
(r/'android13-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
