"""Build an UNSIGNED review candidate from the owner's original complete APK.
Does not install, sign, connect to a device or overwrite an existing file.
Python 3.9+; standard library only.
"""
import argparse,hashlib,json,pathlib,re,zipfile,copy

def build(original,payload,output):
 original,payload,output=map(pathlib.Path,(original,payload,output))
 if output.exists():raise ValueError('Output already exists; choose a new path')
 if output.resolve() in (original.resolve(),payload.resolve()):raise ValueError('Output must be a new file')
 with zipfile.ZipFile(original) as src,zipfile.ZipFile(payload) as patch:
  spec=json.loads(patch.read('_patch/manifest.json'));names=src.namelist()
  if len(set(names))!=len(names):raise ValueError('Duplicate ZIP entry names in original APK')
  dex={n for n in names if re.fullmatch(r'classes(?:[2-9]|[1-9][0-9]+)?\.dex',n)}
  if dex!=set(spec['source_dex_sha256']):raise ValueError('DEX set differs from the reviewed APK')
  for name,digest in spec['source_sha256'].items():
   if name not in names or hashlib.sha256(src.read(name)).hexdigest()!=digest:raise ValueError('Original differs from reviewed input: '+name)
  replacements=spec['replacement_sha256']
  for name,digest in replacements.items():
   if name not in names or hashlib.sha256(patch.read(name)).hexdigest()!=digest:raise ValueError('Patch integrity failure: '+name)
  # A new ZIP cannot preserve APK v2/v3 signing blocks. Also remove stale v1 signatures.
  stale=lambda n: bool(re.fullmatch(r'META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))',n,re.I))
  try:
   with output.open('xb') as handle:
    with zipfile.ZipFile(handle,'w') as dst:
     for info in src.infolist():
      if not stale(info.filename):dst.writestr(copy.copy(info),patch.read(info.filename) if info.filename in replacements else src.read(info.filename))
   with zipfile.ZipFile(output) as dst:
    assert dst.testzip() is None
    for name in dst.namelist():
     expected=patch.read(name) if name in replacements else src.read(name)
     if dst.read(name)!=expected:raise ValueError('Output verification failure: '+name)
  except BaseException:
   if output.exists():output.unlink()
   raise
 report=dict(source_apk_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),candidate_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),replacement_entries=len(replacements),unsigned=True,aligned=False,installable_system_update=False,hardware_tested=False)
 output.with_name(output.name+'.json').write_text(json.dumps(report,indent=2)+'\n');return report

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('original');p.add_argument('payload');p.add_argument('--out',default='projector-settings-ru-v2.UNSIGNED.apk');a=p.parse_args()
 try:report=build(a.original,a.payload,a.out)
 except (ValueError,KeyError,zipfile.BadZipFile) as e:raise SystemExit(str(e))
 print(json.dumps(report,indent=2));print('UNSIGNED REVIEW CANDIDATE ONLY. Do not install as an ordinary APK. System-signature/privileged deployment is unresolved.')
