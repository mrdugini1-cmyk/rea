from pathlib import Path
import json,zipfile,hashlib
r=Path(__file__).resolve().parent
orig=zipfile.ZipFile('/workspace/attachments/4aeb67a1-511f-468c-ad86-7167e2fbd9b8/projector-settings.zip');new=zipfile.ZipFile(r/'translated-resources-v2.zip');sources=json.loads((r/'dex-sources.json').read_text());data={n:new.read(n) for n in orig.namelist() if new.read(n)!=orig.read(n)};hashes={n:hashlib.sha256(orig.read(n)).hexdigest() for n in data};hashes['AndroidManifest.xml']=hashlib.sha256(orig.read('AndroidManifest.xml')).hexdigest();dexhashes={n:hashlib.sha256(Path(p).read_bytes()).hexdigest() for n,p in sources.items()};hashes.update(dexhashes)
for n,p in sources.items():
 b=(r/'patched-dex'/n).read_bytes()
 if b!=Path(p).read_bytes():data[n]=b
spec=dict(profile='XGIMI Z9X HB com.android.newsettings 6.03.03.14 ru v3',source_sha256=hashes,source_dex_sha256=dexhashes,replacement_sha256={n:hashlib.sha256(b).hexdigest() for n,b in data.items()},hardware_tested=False,installable_apk=False)
with zipfile.ZipFile(r/'z9x-hb-ru-v3-payload.zip','w',zipfile.ZIP_DEFLATED) as z:
 z.writestr('_patch/manifest.json',json.dumps(spec,indent=2))
 for n,b in data.items():z.writestr(n,b)
(r/'payload-manifest.json').write_text(json.dumps(spec,indent=2));print('replacements',len(data),'payload bytes',(r/'z9x-hb-ru-v3-payload.zip').stat().st_size)
