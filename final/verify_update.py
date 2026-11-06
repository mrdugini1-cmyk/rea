from pathlib import Path
import sys,json,zipfile,hashlib
r=Path(__file__).resolve().parent;sys.path.insert(0,str(r.parent/'translation-v1'));import resource_patch as p
expected={'head_picture_correction_text':'Проекция','head_screen_setting_text':'Проекция','head_image_setting_text':'Изображение','head_network_setting_text':'Сеть','head_signal_source_setting_text':'Источник','head_bluetooth_setting_text':'Bluetooth','head_sound_setting_text':'Звук','head_general_setting_text':'Общие'}
a=zipfile.ZipFile(r.parent/'translation-v2/translated-resources-v2.zip');b=zipfile.ZipFile(r/'translated-resources-v2.zip')
def get(z):
 data=z.read('resources.arsc');off,_,_,n=next(v for v in p.chunks(data,p.U16(data,2),len(data)) if v[1]==1);pool=p.pool_strings(data[off:off+n]);return data,pool,list(p.entries(data))
x,sx,ex=get(a);y,sy,ey=get(b);assert len(ex)==len(ey);changes=[]
for u,v in zip(ex,ey):
 assert {k:i for k,i in u.items() if k not in ('position','value')}=={k:i for k,i in v.items() if k not in ('position','value')}
 if u['value_type']==3 and sx[u['value']]!=sy[v['value']]:
  assert u['default'] and u['name'] in expected and sy[v['value']]==expected[u['name']];changes.append(dict(name=u['name'],before=sx[u['value']],after=sy[v['value']]))
for e in ey:
 if e['default'] and e['name'] in expected and e['value_type']==3:assert sy[e['value']]==expected[e['name']]
for n in a.namelist():
 if n!='resources.arsc':assert a.read(n)==b.read(n)
old=json.loads((r.parent/'translation-v2/dex-edits.json').read_text());new=json.loads((r/'dex-edits.json').read_text());extra=[v for v in new if v not in old];assert len(extra)==1 and extra[0]['before']==' 设置' and extra[0]['after']==' — настройки' and extra[0]['file'].endswith('com/xgimi/signal/SignalRepository.smali')
result=dict(menu_labels=expected,changed_from_v2=changes,all_resource_ids_preserved=True,other_resources_unchanged=True,one_additional_dex_ui_string=extra[0],v3_hardware_tested=False,v2_preview_user_reported_success=True,package_installer_not_in_settings_apk=True,persistence_not_yet_verified=True)
(r/'update-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False,indent=2))
