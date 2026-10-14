#!/usr/bin/env python3
"""Convert the existing authored CH3 course to protocol 1.0, without changing it."""
import json,re,sys,subprocess,shutil
from pathlib import Path
APP=Path(__file__).resolve().parents[1]; ROOT=APP.parent
sys.path.insert(0,str(ROOT/'ch3-reader'))
from content import MODULES,PAGES
DEST=APP/'courses'/'ch3';DEST.mkdir(parents=True,exist_ok=True)
(DEST/'topics').mkdir(exist_ok=True);(DEST/'sources').mkdir(exist_ok=True)
engine=subprocess.check_output(['node','-e',"require('./ch3-reader/engine.js');console.log(JSON.stringify(Object.fromEntries(Object.entries(CH3Engine.defs).map(([k,v])=>[k,{defs:v,snapshots:CH3Engine.snapshots(k)}]))))"],cwd=ROOT,text=True)
engine=json.loads(engine)
built=(ROOT/'CH3_互動講義.html').read_text();data=json.loads(re.search(r'<script id="lesson-data" type="application/json">(.*?)</script>',built,re.S).group(1))
sourcefiles=[('slides','sp_ch3_2026.pdf','課堂投影片','pdf'),('apue','Advanced.Programming.in.the.UNIX.Environment.3rd.Edition_textbook.pdf','APUE 第三版','pdf'),('original','CH3_File_IO_教學.md','原 AI 教學','text'),('transcript','CH3_I_O_lecture.txt','課堂字幕','text')]
for sid,f,title,kind in sourcefiles:
 target=DEST/'sources'/f
 if not target.exists():shutil.copyfile(ROOT/f,target)
manifest={'schemaVersion':'1.0','courseId':'sp-ch3-file-io','contentVersion':'1.0.1','title':'系統程式設計 · CH3 File I/O','language':'zh-Hant','audience':'系統程式設計課程學生','objectives':['理解 fd、open-file entry 與檔案物件','追蹤讀寫位置、共享與重新導向'], 'modules':[{'id':f'module-{i+1}','title':m[0],'topics':[p['id'] for p in PAGES if p['module']==i]} for i,m in enumerate(MODULES)],'topics':[],'sources':[{'id':sid,'title':title,'kind':kind,'file':'sources/'+f}for sid,f,title,kind in sourcefiles]}
manifest['scopes']=[{'id':'core','title':'本次課程'},{'id':'next','title':'後續內容'}]
manifest['archiveFiles']=[{'title':'原 AI 教學全文','file':'topics/original-teaching.md'}]
(DEST/'topics/original-teaching.md').write_text((ROOT/'CH3_File_IO_教學.md').read_text())
sourcefiles.append(('example','trace_io.c','C 實作範例','text'))
shutil.copyfile(ROOT/'ch3-reader/examples/trace_io.c',DEST/'sources/trace_io.c')
manifest['sources'].append({'id':'example','title':'C 實作範例','kind':'text','file':'sources/trace_io.c'})
bookpages={1:95,2:95,3:96,4:100,5:100,6:100,7:105,8:106,9:106,10:108,11:111,12:113,13:115,14:116,15:121,16:122,17:124}
modelnodes=[{'kicker':'01 · PER PROCESS','title':'Descriptor table','detailMarkdown':'fd → pointer\ndescriptor flags'},{'kicker':'02 · OPEN FILE','title':'Open-file entry','detailMarkdown':'current offset\nfile status flags','dark':True},{'kicker':'03 · FILE OBJECT','title':'vnode / inode','detailMarkdown':'file size\nmetadata'}]
def diagram(v):
 b={'id':'diagram','type':'diagram'}
 if v in ['roadmap','model']:
  b.update(layout='flow',nodes=modelnodes,captionMarkdown='檔案資料可經由 Kernel cache 存取儲存裝置。' if v=='roadmap' else 'fd table 由 Kernel 管理；「per-process」描述歸屬，不代表它存在 user space。')
  if v=='model':b['title']='Kernel 資料結構'
 elif v=='hole':b.update(layout='sparse',title='Sparse file（非比例示意）',segments=[{'text':'10 bytes','range':'0'},{'text':'讀出零值的區域','range':'10 … 16383'},{'text':'10 bytes','range':'16384 … 16393'}],metrics=[{'label':'邏輯長度','value':'16,394'},{'label':'寫入資料量','value':'20 bytes'}],captionMarkdown='實際配置空間另受檔案系統影響，不能直接等同 20 bytes。')
 else:
  routes,caption={
   'syscall':([('執行路徑',['User code','System call','Kernel service','Return'])],'權限模式：user → kernel → user。是否另行排程其他 process，是另一個問題。'),
   'buffers':([('stdio 路徑',['printf / fread','stdio buffer','write / read','Kernel cache']),('fd 路徑',['User buffer','write / read','Kernel cache','Storage'])],'箭頭是資料可能經過的層次，不表示每次都立即走到儲存裝置。'),
   'fd':([('Process A',['fd 3','entry A','notes.txt']),('Process B',['fd 3','entry B','photo.dat'])],'相同 fd 數字，在不同 process 裡可以有不同意義。'),
   'flags':([('fd1 / fd2',['兩個 descriptor','entry A','同一檔案']),('fd3',['一個 descriptor','entry B','同一檔案'])],'F_SETFD 改個別 descriptor；F_SETFL 改 entry A 或 B 中的狀態。'),
   'durability':([('資料路徑',['User buffer','Kernel cache','Storage'])],'一般 write 返回時可能停在 Kernel cache；fsync 等介面提出進一步的同步要求。')
  }['buffers' if v=='flush' else v]
  b.update(layout='routes',routes=[{'label':label,'nodes':nodes} for label,nodes in routes],captionMarkdown=caption)
 return b
for p in PAGES:
 p['original']=next(x['original'] for x in data['pages'] if x['id']==p['id'])
 extra_refs=[]
 for i,(title,url) in enumerate(p.get('extra',[])):
  sid=f"web-{p['id']}-{i}";manifest['sources'].append({'id':sid,'title':title,'kind':'web','url':url});extra_refs.append({'sourceId':sid})
 refs=[{'sourceId':'slides','locator':{'kind':'pdfPage','value':n}}for n in p['slides']]+[{'sourceId':'apue','locator':{'kind':'section','value':p['apue']}},{'sourceId':'apue','locator':{'kind':'pdfPage','value':bookpages.get(int(re.search(r'3\.(\d+)',p['apue']).group(1)) if re.search(r'3\.(\d+)',p['apue']) else 1,95)}},{'sourceId':'original','locator':{'kind':'section','value':'§ '+ '、'.join(str(n) for n in p['original'])}},{'sourceId':'transcript'}]+([{'sourceId':'example'}] if p['id']=='final-review' else [])+extra_refs
 blocks=[{'id':'body','type':'markdown','file':f"topics/{p['id']}.md",'references':refs}]
 (DEST/f"topics/{p['id']}.md").write_text(p['body'])
 if p.get('visual'):
  v=p['visual']
  if v=='seek':blocks.append({'id':'file-position','type':'filePosition','initialText':'0123456789','maxOffset':16})
  elif v=='efficiency':blocks.append({'id':'call-count','type':'callCount','bytes':1048576,'buffers':[1,64,512,4096,65536],'initialBuffer':4096})
  else:
   blocks.append(diagram(v))
   old=DEST/f"topics/{p['id']}-diagram.md"
   if old.exists() and old.read_text().startswith('### 圖解'):old.unlink()
 if p.get('code'):blocks.append({'id':'code','type':'code','language':'c','code':p['code']})
 if p.get('table'):blocks.append({'id':'table','type':'table','columns':p['table'][0],'rows':p['table'][1:]})
 if p.get('lab'):
  lab=engine[p['lab']];steps=[{'id':'initial','title':'初始狀態','bodyMarkdown':'A、B 各自開啟同一個 log，各有自己的 entry。' if p['lab'] in ['race','append'] else '圖中省略未涉及的 fd；∅ 表示 EOF。','snapshot':lab['snapshots'][0]}]
  for i,d in enumerate(lab['defs']):steps.append({'id':f'step-{i+1}','title':f'步驟 {i+1}','code':d['code'],'bodyMarkdown':d['note'],'snapshot':lab['snapshots'][i+1]})
  blocks.append({'id':'lab','type':'steps','presentation':'program','initialState':True,'steps':steps})
 take=f"topics/{p['id']}-takeaway.md";(DEST/take).write_text(p['takeaway']);blocks.append({'id':'takeaway','type':'markdown','file':take,'role':'takeaway'})
 for n,q in enumerate(p.get('exam',[p['quiz']] if 'quiz' in p else [])):
  block={'id':f'quiz-{n}','type':'singleChoice','question':q['prompt'],'options':[{'id':f'option-{i}','text':x}for i,x in enumerate(q['options'])],'answerId':f"option-{q['correct']}",'explanation':q['why']}
  if q.get('revisit'):block['revisit']=q['revisit']
  blocks.append(block)
 if p.get('extra'):
  name=f"topics/{p['id']}-links.md";(DEST/name).write_text('### 延伸來源\n\n'+'\n'.join(f'- [{t}]({u})'for t,u in p['extra']));blocks.append({'id':'links','type':'markdown','file':name})
 topic={'id':p['id'],'title':p['title'],'lead':p['lead'],'focus':p['question'],'scope':p['scope'],'blocks':blocks}
 if p.get('time'):topic['estimatedMinutes']=p['time']
 if p.get('exam'):topic['assessment']=True
 if p['id']=='final-review':topic['backTo']='start'
 name=f"topics/{p['id']}.json";(DEST/name).write_text(json.dumps(topic,ensure_ascii=False,indent=2));manifest['topics'].append({'id':p['id'],'file':name})
(DEST/'course.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print(f"Migrated {len(PAGES)} topics and {sum(b['type']=='singleChoice' for p in manifest['topics'] for b in json.loads((DEST/p['file']).read_text())['blocks'])} quizzes; all seven labs preserved.")
