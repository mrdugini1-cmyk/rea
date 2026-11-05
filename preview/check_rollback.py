"""Bounded rollback tests with mocked platform operations, not Android/mount emulation."""
from pathlib import Path
import subprocess,tempfile,json
r=Path(__file__).resolve().parent;s=(r/'runtime-body.sh').read_text();functions=s[s.index('phase() {'):s.index('\nmain() {')]
cases=[('owned','42','42','7:99','7:99','abc','abc','ROLLED_BACK',True),('foreign_mount','43','42','7:99','7:99','abc','abc','ROLLBACK_REFUSED_FOREIGN_MOUNT',False),('foreign_inode','42','42','7:100','7:99','abc','abc','ROLLBACK_REFUSED_FOREIGN_MOUNT',False),('baseline_changed','42','42','7:99','7:99','changed','abc','ROLLBACK_BASELINE_CHANGED',True),('record_interrupted','42','','7:99','7:99','abc','abc','ROLLED_BACK',True)]
results=[]
for name,current,own,inode,expected_inode,actual_hash,before,phase,unmount in cases:
 with tempfile.TemporaryDirectory(prefix='z9x-rollback-',dir='/tmp') as tmp:
  script=functions+f'''\nD='{tmp}'\nS=$D/private\nTARGET=target\nPKG=testpkg\nMAINT=testmaint\nMOUNTED=1\nSCRATCH_MOUNTED=0\nSTOPPED_SETTINGS=1\nMAINT_STOPPED=1\nCLEANED=0\nOWN_MOUNT='{own}'\nBEFORE_HASH='{before}'\nphase() {{ printf '%s\\n' "$1" > "$D/phase"; }}\nmount_id() {{ echo '{current}'; }}\nstat() {{ case "$*" in *candidate.apk*) echo '{expected_inode}' ;; *) echo '{inode}' ;; esac; }}\nhash() {{ echo '{actual_hash}'; }}\nbounded() {{ [ "$1" = am ] || return 127; "$@"; }}\nam() {{ echo "$*" >> "$D/am"; return 0; }}\numount() {{ echo "$*" >> "$D/umount"; return 0; }}\nstart_settings() {{ echo started > "$D/settings"; }}\nwait_loaded() {{ return 0; }}\nrollback\nFIRST=$?\nrollback\necho FIRST=$FIRST\n'''
  p=subprocess.run(['sh'],input=script,text=True,capture_output=True);d=Path(tmp);assert (d/'phase').read_text().strip()==phase,(name,p.stdout,p.stderr);assert (d/'umount').exists()==unmount,name
  am=(d/'am').read_text();assert am.count('start-foreground-service')==1,(name,am)
  if unmount:assert len((d/'umount').read_text().splitlines())==1
  else:assert 'force-stop' not in am
  results.append(dict(case=name,phase=phase,unmount_called=unmount,own_service_state_restored=True,idempotent_cleanup=True))
(r/'rollback-verification.json').write_text(json.dumps(dict(scope=__doc__,cases=results,hardware_tested=False),indent=2));print('rollback ownership/failure cases passed:',len(results))
