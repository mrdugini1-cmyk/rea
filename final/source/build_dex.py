"""Only explicit UI string constants are edited. All other instructions retained."""
from pathlib import Path
import json,re,shutil,subprocess,concurrent.futures,hashlib
r=Path(__file__).resolve().parent;src=r/'smali-original';dst=r/'smali-patched';mapping=json.loads((r/'dex-ui-map.json').read_text());shutil.copytree(src,dst,dirs_exist_ok=True)
pattern=re.compile(r'^(\s*const-string(?:/jumbo)?\s+[vp]\d+,\s*)(".*")$');edits=[]
# UI classes and direct display helpers only. No SDK transport, identifiers or log replacement.
allowed=['com/xgimi/signal/SignalRepository.smali','com/xgimi/battery/ui/','com/xgimi/bluetooth/dialog/','com/xgimi/bluetooth/receiver/BluPairRequestReceiver.smali','com/xgimi/bluetooth/BluetoothViewModel.smali','com/xgimi/brightness/BrightnessManager.smali','com/xgimi/calibration/','com/xgimi/common/dialog/','com/xgimi/common/widget/','com/xgimi/dialog/DialogCellFactory.smali','com/xgimi/keystone/view/','com/xgimi/law/LawRepository.smali','com/xgimi/misckey/util/DateUtil.smali','com/xgimi/misckey/cell/TopInfoAndFuncCell.smali','com/xgimi/more/batchsetting/','com/xgimi/musicsdk/Simple','com/xgimi/newsettings/misckeyui/','com/xgimi/newsettings/ui/PictureFactory','com/xgimi/newsettings/ui/SerialPortControlFactory.smali','com/xgimi/picture/PictureRepository.smali','com/xgimi/picture/PictureViewModel.smali','com/xgimi/stylefilter/ui/','com/xgimi/widget/launcher/component/NoNetworkCell','com/xgimi/widget/launcher/search/','com/xgimi/xbase/page/DefaultErrorPageCell2']
for f in dst.rglob('*.smali'):
 rel=f.relative_to(dst);name='/'.join(rel.parts[1:])
 if not any(name.startswith(x) for x in allowed):continue
 lines=f.read_text().splitlines(keepends=True);changed=False;method=''
 for i,line in enumerate(lines):
  if line.strip().startswith('.method'):method=line.strip()
  m=pattern.match(line.rstrip('\n'))
  if not m:continue
  s=json.loads(m[2].replace("\\'", "'"))
  if s not in mapping:continue
  new=mapping[s]
  assert s.count('nnn')==new.count('nnn')
  lines[i]=m[1]+json.dumps(new,ensure_ascii=True)+'\n';edits.append(dict(file=str(rel),method=method,line=i+1,before=s,after=new));changed=True
 if changed:f.write_text(''.join(lines))
assert len(edits)>100
(r/'dex-edits.json').write_text(json.dumps(edits,ensure_ascii=False,indent=2));print('const-string edits',len(edits),'classes',len(set(x['file'] for x in edits)),flush=True)
out=r/'patched-dex';out.mkdir(exist_ok=True);sources=json.loads((r/'dex-sources.json').read_text());changed_dex={x['file'].split('/')[0] for x in edits}
def build(item):
 name,path=item;stem=name[:-4]
 if stem not in changed_dex:shutil.copy2(path,out/name);print(name,'unchanged',flush=True);return
 t=subprocess.run(['java','-Xmx1g','-cp',str(r.parent/'tools/smali/*'),'org.jf.smali.Main','a','--api','33','-j','2',str(dst/stem),'-o',str(out/name)],capture_output=True,text=True);print(name,t.returncode,t.stderr[-2000:],flush=True);assert t.returncode==0
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:list(ex.map(build,sources.items()))
(r/'dex-hashes.json').write_text(json.dumps({n:dict(original=hashlib.sha256(Path(p).read_bytes()).hexdigest(),patched=hashlib.sha256((out/n).read_bytes()).hexdigest()) for n,p in sources.items()},indent=2))
