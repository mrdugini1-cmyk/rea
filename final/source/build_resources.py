from pathlib import Path
import sys,json,zipfile,struct,re,hashlib
r=Path(__file__).resolve().parent;sys.path.insert(0,str(r.parent/'translation-v1'));import resource_patch as p
source=r.parent/'translation-v1/translated-resources.zip';z=zipfile.ZipFile(source);b=z.read('resources.arsc');po,_,_,pn=next(v for v in p.chunks(b,p.U16(b,2),len(b)) if v[1]==1);ss=p.pool_strings(b[po:po+pn]);ed=dict(l.split('\t',1) for l in (r/'editorial.tsv').read_text().splitlines());changes=[];added=[];out=bytearray(b);seen=set()
labels={'автоматический':'Авто','середина':'Средний','мощный':'Высокий','слабый':'Низкий','закрытие':'Выкл.','закрывать':'Выкл.','открыть':'Вкл.','Открыть':'Вкл.','подтверждать':'Подтвердить','соединять':'Подключить','начинать':'Начать','включать':'Включить','Заканчивать':'Завершить','Более':'Ещё','сохранять':'Сохранить','возобновлять':'Возобновить','никто':'Нет','классный цвет':'Холодный','Руководство':'Вручную','ХОРОШО':'OK','низкая задержка':'Низкая задержка','верно':'Правый'}
fragments={'custom_equipment_devices','share_audio_action_desc_share_2','share_audio_action_desc_share_1'}
fmt=lambda x:sorted(re.findall(r'%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?[a-zA-Z%]',x))
for e in p.entries(b):
 if e['type']!='string' or e['value_type']!=3 or not e['default']:continue
 k=e['name'];old=ss[e['value']];new=old;reason=[]
 if k in ed:new=ed[k].replace('\\n','\n');seen.add(k);reason.append('editorial')
 elif k not in fragments and re.search('[А-Яа-яЁё]',old) and not old.lstrip().startswith(('{','[')):
  if old in labels:new=labels[old];reason.append('label')
  new=new.replace('\u200b','').replace('экстремальной скорости','минимальной задержки').replace('Экстремальная скорость','Минимальная задержка');
  if new and re.match('[а-яё]',new):new=new[0].upper()+new[1:];reason.append('initial_capital')
 if new==old:continue
 assert fmt(old)==fmt(new),(k,fmt(old),fmt(new))
 assert all(new.count(t)==old.count(t) for t in ['@','$']) if ('@' in old or '$' in old) else True,k
 struct.pack_into('<I',out,e['position'],len(ss)+len(added));added.append(new);changes.append(dict(name=k,resource_id=hex(e['id']),before=old,after=new,reason=reason or ['terminology']))
assert seen==set(ed),(set(ed)-seen)
newpool=p.repool(b[po:po+pn],added);out=out[:po]+newpool+out[po+pn:];struct.pack_into('<I',out,4,len(out));
# Correct a mistranslated display label in a string-array, leaving every item index intact.
b2=bytes(out);po2,_,_,pn2=next(v for v in p.chunks(b2,p.U16(b2,2),len(b2)) if v[1]==1);ss2=p.pool_strings(b2[po2:po2+pn2]);arrayadd=[];arraychanges=[]
for e in p.entries(b2):
 if e['type']=='array' and e['name']=='color_mode9' and e['default'] and e['value_type']==3:
  old=ss2[e['value']];new={'стандартный':'Стандартный','классный цвет':'Холодный','Настроить':'Пользовательский'}.get(old,old)
  if old!=new:
   struct.pack_into('<I',out,e['position'],len(ss2)+len(arrayadd));arrayadd.append(new);arraychanges.append(dict(name=e['name'],item=e['bag'],before=old,after=new))
np=p.repool(b2[po2:po2+pn2],arrayadd);out=out[:po2]+np+out[po2+pn2:];struct.pack_into('<I',out,4,len(out))
with zipfile.ZipFile(r/'translated-resources-v2.zip','w',zipfile.ZIP_DEFLATED) as w:
 for i in z.infolist():w.writestr(i,bytes(out) if i.filename=='resources.arsc' else z.read(i))
(r/'resource-edits.json').write_text(json.dumps(dict(base_v1_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),strings=changes,arrays=arraychanges,hardware_tested=False),ensure_ascii=False,indent=2));print('strings',len(changes),'explicit_editorial',sum('editorial' in x['reason'] for x in changes),'array items',len(arraychanges))
