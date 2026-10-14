"""Compare migrated teaching against the original authored HTML and simulation."""
import json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];COURSE=ROOT/'learning-app/courses/ch3'
old=json.loads(re.search(r'<script id="lesson-data" type="application/json">(.*?)</script>',(ROOT/'CH3_互動講義.html').read_text(),re.S).group(1))
engine=json.loads(subprocess.check_output(['node','-e',"require('./ch3-reader/engine.js');console.log(JSON.stringify(Object.fromEntries(Object.entries(CH3Engine.defs).map(([k,v])=>[k,{defs:v,snapshots:CH3Engine.snapshots(k)}]))))"],cwd=ROOT))
manifest=json.loads((COURSE/'course.json').read_text());visuals=labs=quizzes=0
for p in old['pages']:
 t=json.loads((COURSE/f"topics/{p['id']}.json").read_text());blocks=t['blocks'];by={b['id']:b for b in blocks}
 assert t['title']==p['title'] and t['lead']==p['lead'] and t['focus']==p['question'] and t['scope']==p['scope']
 assert (COURSE/by['body']['file']).read_text()==p['body']
 assert (COURSE/by['takeaway']['file']).read_text()==p['takeaway']
 assert [{'sourceId':'slides','locator':{'kind':'pdfPage','value':n}} for n in p['slides']]==[r for r in by['body']['references'] if r['sourceId']=='slides']
 assert {'sourceId':'original','locator':{'kind':'section','value':'§ '+'、'.join(map(str,p['original']))}} in by['body']['references']
 assert any(r['sourceId']=='apue' and r['locator']['kind']=='pdfPage' for r in by['body']['references'])
 assert any(r['sourceId']=='transcript' for r in by['body']['references'])
 if p.get('visual'):
  v=p['visual'];visuals+=v not in ['seek','efficiency']
  assert by[{'seek':'file-position','efficiency':'call-count'}.get(v,'diagram')]['type']=={'seek':'filePosition','efficiency':'callCount'}.get(v,'diagram')
 if p.get('code'):assert by['code']['code']==p['code']
 if p.get('table'):assert by['table']['columns']==p['table'][0] and by['table']['rows']==p['table'][1:]
 if p.get('lab'):
  labs+=1;lab=by['lab'];defs=engine[p['lab']]['defs']
  assert lab['presentation']=='program' and lab['initialState']
  assert [s['snapshot'] for s in lab['steps']]==engine[p['lab']]['snapshots']
  assert [s['code'] for s in lab['steps'][1:]]==[s['code'] for s in defs]
  assert [s['bodyMarkdown'] for s in lab['steps'][1:]]==[s['note'] for s in defs]
 oldq=p.get('exam',[p['quiz']] if 'quiz' in p else [])
 newq=[b for b in blocks if b['type']=='singleChoice'];assert len(oldq)==len(newq)
 for a,b in zip(oldq,newq):
  quizzes+=1;assert a['prompt']==b['question'] and a['options']==[o['text'] for o in b['options']] and b['answerId']==b['options'][a['correct']]['id'] and a['why']==b['explanation']
for a in manifest['archiveFiles']:assert (COURSE/a['file']).read_text()==(ROOT/'CH3_File_IO_教學.md').read_text()
assert visuals==9 and labs==7 and quizzes==42
print('Original HTML parity: 51 titles/leads/bodies/focus/scope/source mappings, code, tables, 9 diagrams, 7 complete labs, 42 quizzes and original AI appendix preserved.')
