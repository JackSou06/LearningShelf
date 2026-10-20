const assert=require('node:assert/strict'),path=require('node:path'),C=require('../web/course-core.js'),{loadFolder}=require('../scripts/validate-course.cjs');
const original=loadFolder(path.join(__dirname,'../courses/linear-algebra'));
assert.equal(C.validate(original).valid,true);
const p=structuredClone(original),m=JSON.parse(p.files['course.json']);m.schemaVersion='1.1';p.files['course.json']=JSON.stringify(m);
const f=m.topics[0].file,t=JSON.parse(p.files[f]);t.blocks.push({id:'hidden-fixture',type:'markdown',file:'hidden.md',visibility:'contextOnly'});p.files[f]=JSON.stringify(t);p.files['hidden.md']='HIDDEN_FULL_TEXT 標記清單 原文：A[3]→A[1]';
let v=C.validate(p);assert.equal(v.valid,true);const topic=v.course.topics.find(x=>x.id===t.id);
assert.ok(!C.readingBlocks(topic).some(b=>b.id==='hidden-fixture'));
assert.ok(C.context(v.course,topic,{notes:{},qa:[]}).includes(p.files['hidden.md']));assert.ok(C.topicText(v.course,topic).includes(p.files['hidden.md']));
for(const value of ['hidden',false,null]){const q=structuredClone(p),x=JSON.parse(q.files[f]);x.blocks.at(-1).visibility=value;q.files[f]=JSON.stringify(x);assert.equal(C.validate(q).valid,false);}
const downgrade=structuredClone(p);m.schemaVersion='1.0';downgrade.files['course.json']=JSON.stringify(m);assert.ok(C.validate(downgrade).errors.some(e=>e.code==='UNSUPPORTED_VERSION'));
const missing=structuredClone(p);delete missing.files['hidden.md'];delete missing.available['hidden.md'];assert.ok(C.validate(missing).errors.some(e=>e.code==='MISSING_FILE'));
const wrongType=structuredClone(p),wt=JSON.parse(wrongType.files[f]);wt.blocks.push({id:'not-markdown',type:'image',file:'x.png',alt:'x',description:'x',visibility:'contextOnly'});wrongType.files[f]=JSON.stringify(wt);assert.equal(C.validate(wrongType).valid,false);
const visible=structuredClone(p),vt=JSON.parse(visible.files[f]);vt.blocks.at(-1).visibility='visible';visible.files[f]=JSON.stringify(vt);v=C.validate(visible);assert.equal(v.valid,true);assert.ok(C.readingBlocks(v.course.topics[0]).some(b=>b.id==='hidden-fixture'));
console.log('contextOnly: visible defaults, hidden reading, complete Q&A/export, old-course compatibility, invalid enum/type, missing file and downgrade checks passed.');
