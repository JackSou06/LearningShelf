/* Three-way reconciliation for the computer-owned learning session. */
(function(){'use strict';
const clone=x=>JSON.parse(JSON.stringify(x));
function equal(a,b){
 if(a===b)return true;
 if(a===null||b===null||typeof a!=='object'||typeof b!=='object')return false;
 if(Array.isArray(a)||Array.isArray(b))return Array.isArray(a)&&Array.isArray(b)&&a.length===b.length&&a.every((value,i)=>equal(value,b[i]));
 const keys=Object.keys(a);return keys.length===Object.keys(b).length&&keys.every(key=>Object.hasOwn(b,key)&&equal(a[key],b[key]));
}
const maps=['notes','qaDrafts','answers'];
const sets=['bookmarks','seen'];
const scalars=['last','block','sheet','large','model','modelEpoch'];
function reconcile(base,next,current){
 const out=clone(current);
 for(const field of maps){
  const before=base[field]||{},after=next[field]||{},now=out[field]||{};out[field]=now;
  for(const key of new Set([...Object.keys(before),...Object.keys(after)])){
   if(equal(before[key],after[key]))continue;
   if(field==='notes'&&!equal(before[key],now[key])&&!equal(after[key],now[key])){
    const local=after[key]||'',host=now[key]||'';
    if(local&&host&&!host.includes(local))now[key]=host+'\n\n── 同時編輯的筆記（請核對）──\n'+local;
    else if(local&&!host)now[key]=local;
    // A concurrent clear cannot silently erase the other editor's new text.
   }else if(Object.hasOwn(after,key))now[key]=clone(after[key]);else delete now[key];
  }
 }
 for(const field of sets){const before=new Set(base[field]||[]),after=new Set(next[field]||[]),now=new Set(out[field]||[]);for(const x of before)if(!after.has(x))now.delete(x);for(const x of after)if(!before.has(x))now.add(x);out[field]=[...now];}
 for(const field of scalars)if(!equal(base[field],next[field]))out[field]=next[field];
 out.qaDeleted=[...new Set([...(current.qaDeleted||[]),...(next.qaDeleted||[])])];
 const deleted=new Set(out.qaDeleted),before=new Map((base.qa||[]).map(q=>[q.id,q])),now=new Map((out.qa||[]).map(q=>[q.id,q]));
 for(const q of next.qa||[]){if(deleted.has(q.id))continue;const old=before.get(q.id),present=now.get(q.id);if(!old){if(!present)now.set(q.id,clone(q));continue;}if(!present)continue;for(const k of new Set([...Object.keys(old),...Object.keys(q)]))if(!equal(old[k],q[k])){if(Object.hasOwn(q,k))present[k]=clone(q[k]);else delete present[k];}}
 out.qa=[...now.values()].filter(q=>!deleted.has(q.id));
 return out;
}
function archive(c,r){
 const C=CourseCore,topics=c.topics,byId=id=>topics.find(t=>t.id===id),qs=topics.flatMap(t=>t.blocks.filter(b=>b.type==='singleChoice').map(b=>({key:t.id+':'+b.id,b}))),answered=qs.filter(q=>r.answers[q.key]?.version===c.contentVersion),correct=answered.filter(q=>r.answers[q.key].optionId===q.b.answerId).length;
 return '# '+c.title+' 學習紀錄\n\n課程 ID：'+c.courseId+'\n教材版本：'+c.contentVersion+'\n目前主題：'+(byId(r.last)?.title||'')+' · 頁 '+((r.sheet||0)+1)+'\n答對 '+correct+' / '+qs.length+' 題 · 已作答 '+answered.length+' 題\n\n# 完整教學\n\n'+topics.map(t=>C.topicText(c,t)).join('\n\n')+'\n\n# 我的筆記\n'+Object.entries(r.notes).map(([id,n])=>'## '+(byId(id)?.title||id)+'\n'+n).join('\n\n')+'\n\n# Q&A\n'+r.qa.map(q=>'## '+(byId(q.topic)?.title||q.topic)+'\n時間：'+q.time+' · 模型：'+q.model+' · 狀態：'+q.status+'\nQ：'+q.question+'\nA：'+q.answer+(q.error?'\n狀態說明：'+q.error:'')+(q.usage?'\nInput '+q.usage.input_tokens+' · Output '+q.usage.output_tokens:'')).join('\n\n')+(c.archiveFiles||[]).map(a=>'\n\n# 附錄：'+a.title+'\n\n'+a.text).join('');
}
const api={equal,reconcile,archive};globalThis.RecordSync=api;if(typeof module!=='undefined')module.exports=api;
})();
