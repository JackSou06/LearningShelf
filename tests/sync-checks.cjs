const assert=require('node:assert/strict'),R=require('../web/records.js'),S=require('../web/record-sync.js');
const copy=x=>JSON.parse(JSON.stringify(x));
let base=R.empty('test');base.notes.a='original';base.notes.b='other';base.qa=[{id:'q',topic:'a',question:'old',answer:'',status:'pending'}];
let desktop=copy(base),tablet=copy(base);desktop.notes.a='desktop';tablet.notes.b='tablet';desktop.qa[0].answer='host answer';desktop.qa[0].status='done';
let merged=S.reconcile(base,tablet,desktop);assert.equal(merged.notes.a,'desktop');assert.equal(merged.notes.b,'tablet');assert.equal(merged.qa[0].answer,'host answer');assert.equal(merged.qa[0].status,'done');
tablet.notes.a='tablet same topic';merged=S.reconcile(base,tablet,desktop);assert.ok(merged.notes.a.includes('desktop')&&merged.notes.a.includes('tablet same topic'));
const typed=copy(base);typed.notes.a='typed 1';const typedNext=copy(typed);typedNext.notes.a='typed 12';merged=S.reconcile(typed,typedNext,S.reconcile(base,typed,base));assert.equal(merged.notes.a,'typed 12','sequential keystrokes do not become conflicts');
const cleared=copy(base);cleared.notes.a='';merged=S.reconcile(base,cleared,desktop);assert.equal(merged.notes.a,'desktop','a stale clear must not erase concurrent text');
R.deleteQA(desktop,'q');merged=S.reconcile(base,tablet,desktop);assert.equal(merged.qa.length,0,'tombstones beat stale clients');
base.bookmarks=['a'];desktop=copy(base);desktop.bookmarks.push('b');tablet=copy(base);tablet.bookmarks=[];assert.deepEqual(S.reconcile(base,tablet,desktop).bookmarks,['b']);
assert.equal(R.valid(base,'test').qa[0].status,'cancelled');assert.equal(R.valid(base,'test',true).qa[0].status,'pending');
console.log('Sync checks: independent edits, same-note conflicts, sequential typing, stale clears, answered questions, deletions and live pending status passed.');

const original=R.empty('test');original.answers.x={optionId:'old',version:'1.0.1'};
const reordered=copy(original);reordered.answers.x={version:'1.0.1',optionId:'old'};
const latest=copy(original);latest.answers.x={optionId:'new',version:'1.0.1'};
assert.ok(S.equal(original,reordered));assert.equal(S.reconcile(original,reordered,latest).answers.x.optionId,'new','key order alone cannot overwrite a newer answer');
assert.ok(!S.equal({x:1},{x:2}));assert.ok(!S.equal(['a','b'],['b','a']));
console.log('Dictionary-order checks: unchanged snapshots compare equal; real edits and array order still differ; stale reordered answers cannot overwrite newer responses.');
