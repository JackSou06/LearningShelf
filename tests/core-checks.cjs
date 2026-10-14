const assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),C=require('../web/course-core.js'),R=require('../web/records.js'),{loadFolder}=require('../scripts/validate-course.cjs');
const clone=x=>JSON.parse(JSON.stringify(x));const pack=loadFolder(path.resolve(__dirname,'../courses/ch3')),ok=C.validate(pack);assert.ok(ok.valid);assert.equal(ok.course.topics.length,51);assert.equal(ok.course.topics.flatMap(t=>t.blocks).filter(b=>b.type==='singleChoice').length,42);assert.equal(ok.course.topics.flatMap(t=>t.blocks).filter(b=>b.type==='steps').length,7);
const other=C.validate(loadFolder(path.resolve(__dirname,'../courses/linear-algebra')));assert.ok(other.valid);assert.equal(other.course.topics.length,2);
function bad(change,code){const p=clone(pack);change(p);const r=C.validate(p);assert.equal(r.valid,false);if(code)assert.ok(r.errors.some(e=>e.code===code));}
bad(p=>{delete p.files['topics/dup.md'];delete p.available['topics/dup.md'];},'MISSING_FILE'); // Also remove existence metadata to simulate missing file.

bad(p=>{const m=JSON.parse(p.files['course.json']);m.topics[0].file='../outside.json';p.files['course.json']=JSON.stringify(m);},'UNSAFE_PATH');
bad(p=>{const t=JSON.parse(p.files['topics/dup.json']);t.blocks[0].type='script';p.files['topics/dup.json']=JSON.stringify(t);},'UNSUPPORTED_COMPONENT');
bad(p=>{const t=JSON.parse(p.files['topics/access.json']);t.blocks.find(b=>b.type==='singleChoice').answerId='missing';p.files['topics/access.json']=JSON.stringify(t);});
bad(p=>{const t=JSON.parse(p.files['topics/access.json']);t.blocks='not an array';p.files['topics/access.json']=JSON.stringify(t);});
bad(p=>{const t=JSON.parse(p.files['topics/access.json']);t.prerequisites=['access'];p.files['topics/access.json']=JSON.stringify(t);});
bad(p=>{const m=JSON.parse(p.files['course.json']);m.modules[0].topics.push('access');p.files['course.json']=JSON.stringify(m);});
bad(p=>{const t=JSON.parse(p.files['topics/access.json']);t.blocks[0].references[0].locator.value=0;p.files['topics/access.json']=JSON.stringify(t);});
bad(p=>{const t=JSON.parse(p.files['topics/dup.json']);t.blocks.find(b=>b.type==='steps').steps[0].snapshot.files={'x':123};p.files['topics/dup.json']=JSON.stringify(t);});
const state=R.empty(ok.course.courseId);state.notes.access='current note';state.notes.dup='private other note';state.qa=[{id:'q1',topic:'access',question:'current question',answer:'current answer'},{id:'q2',topic:'dup',question:'other question',answer:'other answer'}];const access=ok.course.topics.find(t=>t.id==='access'),context=C.context(ok.course,access,state);assert.ok(context.includes('current note')&&context.includes('current question')&&context.includes('current answer'));assert.ok(!context.includes('private other note')&&!context.includes('other question'));
const incoming=R.empty(state.courseId);incoming.notes.access='conflicting imported note';incoming.qa=[...state.qa,{id:'q3',topic:'access',question:'new',answer:'answer'}];R.merge(state,incoming);assert.equal(state.qa.length,3);assert.ok(state.notes.access.includes('current note')&&state.notes.access.includes('conflicting imported note'));
assert.throws(()=>R.valid({...incoming,courseId:'unrelated'},state.courseId));
const migrated=R.legacy({version:1,last:'access',notes:{access:'legacy'},answers:{'access:0':1},qa:[{id:'old',topic:'access',question:'legacy Q',answer:'legacy A',status:'done'}]},ok.course);assert.equal(migrated.notes.access,'legacy');assert.equal(migrated.qa[0].question,'legacy Q');assert.equal(migrated.answers['access:quiz-0'].optionId,'option-1');
console.log('Course checks passed: both courses, content coverage, invalid types/paths/references/cycles, topic-only context, backup conflict preservation and CH3 migration.');

const beforeDelete=JSON.parse(JSON.stringify(state));const removed=R.deleteQA(state,'q1');assert.ok(removed);assert.ok(!C.context(ok.course,access,state).includes('current question'));assert.ok(!C.context(ok.course,access,state).includes('current answer'));assert.ok(state.qa.some(q=>q.id==='q2'),'deleting one question preserves other topics');
const reopened=R.valid(JSON.parse(JSON.stringify(state)),state.courseId);assert.ok(!reopened.qa.some(q=>q.id==='q1'));R.merge(reopened,beforeDelete);assert.ok(!reopened.qa.some(q=>q.id==='q1'),'older backups cannot resurrect a deleted Q&A');
assert.equal(removed,true);assert.equal(R.restoreQA,undefined);
console.log('Q&A deletion checks: context exclusion, save/reopen, old-backup protection and no restore API passed.');
const V=require('../web/lesson-visuals.js');
assert.equal(R.empty('test').model,'gpt-6.1-sol');
assert.equal(R.valid({...R.empty('test'),model:'gpt-4.1-mini',modelEpoch:undefined},'test').model,'gpt-6.1-sol');
assert.equal(R.valid({...R.empty('test'),model:'user-future-model'},'test').model,'user-future-model');
assert.ok(!context.includes('# 0.')); // The original AI appendix never joins topic requests.
assert.ok(!context.includes('原教學與字幕中的全部'));assert.ok(ok.course.archiveFiles[0].text.includes('# 0.'));
assert.ok(V.bytes('log',{A:3,B:4}).includes('↑ A'));assert.ok(V.bytes('log',{A:3,B:4}).includes('∅'));assert.ok(V.bytes('a\0X',{offset:2}).includes('·'));
assert.ok(V.snapshot({processes:{P:{3:'A'}},entries:{A:{offset:3,refs:1,flags:'O_RDONLY',file:'x'}},files:{x:'log'},output:'test'}).includes('↑ A'));
bad(p=>{const m=JSON.parse(p.files['course.json']);m.archiveFiles[0].file='../outside.md';p.files['course.json']=JSON.stringify(m);},'UNSAFE_PATH');
bad(p=>{const t=JSON.parse(p.files['topics/start.json']);t.scope='missing';p.files['topics/start.json']=JSON.stringify(t);});
bad(p=>{const t=JSON.parse(p.files['topics/start.json']);t.blocks.find(b=>b.type==='diagram').nodes[0].detailMarkdown='';p.files['topics/start.json']=JSON.stringify(t);});
console.log('Restoration checks: model migration and future preferences, appendix isolation, byte/EOF/offset rendering, diagram and scope validation passed.');

// Requests omit appended source metadata; archives and actual lesson words stay intact.
const fixture={...ok.course,sources:[{id:'context-source',title:'Metadata-only source title',kind:'web',url:'https://example.invalid/metadata-only'}]};
const fixtureTopic={id:'access',title:'Image context',lead:'Teaching lead',blocks:[
 {id:'detail',type:'markdown',text:'原圖第40頁，M1黃色格：67。\n來源：這是教材中的原文，需保留。',references:[{sourceId:'context-source',locator:{kind:'pdfPage',value:40}}]},
 {id:'image',type:'image',alt:'Byte order image',description:'Yellow cell is 67',references:[{sourceId:'context-source',locator:{kind:'pdfPage',value:40}}]}
]};
const fixtureContext=C.context(fixture,fixtureTopic,{notes:{access:'Keep notes'},qa:[{topic:'access',question:'Keep question',answer:'Keep answer'}]});
assert.ok(!fixtureContext.includes('Metadata-only source title')&&!fixtureContext.includes('https://example.invalid/metadata-only'));
assert.ok(!fixtureContext.includes('"sourceId"')&&!fixtureContext.includes('"locator"')&&!fixtureContext.includes('\n定位：'));
for(const content of ['Teaching lead','M1黃色格：67','來源：這是教材中的原文，需保留。','Byte order image','Yellow cell is 67','Keep notes','Keep question','Keep answer'])assert.ok(fixtureContext.includes(content));
assert.ok(C.topicText(fixture,fixtureTopic).includes('Metadata-only source title'));
assert.ok(C.topicText(fixture,fixtureTopic).includes('"locator"'));
assert.deepEqual(fixtureTopic.blocks[0].references,[{sourceId:'context-source',locator:{kind:'pdfPage',value:40}}]);
globalThis.CourseCore=C;const S=require('../web/record-sync.js');
assert.ok(S.archive({...fixture,topics:[fixtureTopic]},R.empty(fixture.courseId)).includes('Metadata-only source title'));
console.log('Source metadata omitted from requests; full lesson/image details, notes, Q&A, references and MD archive preserved.');
