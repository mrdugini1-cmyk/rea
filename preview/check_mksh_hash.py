"""Reproduce Android mksh hash alias shadowing and check the production helper."""
from pathlib import Path
import subprocess,tempfile,hashlib,json
r=Path(__file__).resolve().parent;mksh=r.parent/'tools/mksh/usr/bin/mksh';source=(r/'runtime-body.sh').read_text();helper=next(l for l in source.splitlines() if l.startswith('z9x_file_sha256()'))
with tempfile.TemporaryDirectory(prefix='z9x-mksh-',dir='/tmp') as tmp:
 p=Path(tmp)/'APK with spaces.bin';p.write_bytes(b'APK regression fixture\0\xff');expected=hashlib.sha256(p.read_bytes()).hexdigest()
 old='''hash() { sha256sum "$1" | awk '{print $1}'; }\nhash "$1"\n'''
 a=subprocess.run([str(mksh),'-c',old,'regression',str(p)],text=True,capture_output=True);assert a.stdout.strip()!=expected,(a.stdout,a.stderr)
 b=subprocess.run([str(mksh),'-c',helper+'\nz9x_file_sha256 "$1"\n','regression',str(p)],text=True,capture_output=True);assert b.returncode==0 and b.stdout.strip()==expected,(b.stdout,b.stderr)
 assert '$(hash ' not in source and '\nhash()' not in source
 subprocess.run([str(mksh),'-n',str(r/'runtime-body.sh')],check=True)
 result=dict(shell=subprocess.check_output([str(mksh),'-c','print -r -- "$KSH_VERSION"'],text=True).strip(),original_alias_conflict_reproduced=True,production_prefixed_helper_returns_expected_sha256=True,path_with_spaces_checked=True,production_script_mksh_parse_passed=True,device_alias_conflict_reported_by_user=True,preview_not_yet_applied=True)
 (r/'mksh-verification.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
