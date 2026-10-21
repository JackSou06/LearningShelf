const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const C=require('../web/course-core.js'),{loadFolder}=require('../scripts/validate-course.cjs');
assert.equal(C.MAX_CONTENT_BYTES,100000000);
const folder=path.resolve(process.argv[2]);
const pack=loadFolder(folder);assert.equal(C.validate(pack).valid,true,'Actual >20 MB native fixture also loads through CLI');
const body=path.join(folder,'topics/body.md'),original=fs.readFileSync(body);
try{
 fs.truncateSync(body,100000001);
 assert.throws(()=>loadFolder(folder),/100 MB/);
}finally{fs.writeFileSync(body,original);}
const context={window:{},CourseCore:C,URL:{createObjectURL:()=> 'blob:test'},FileReader:class{readAsDataURL(){this.result='data:image/png;base64,AAAA';this.onload();}}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../web/platform.js'),'utf8'),context);
const file=(name,size,text='{}')=>({webkitRelativePath:'course/'+name,size,text:async()=>text});
(async()=>{
 const p=context.window.Platform;
 assert.ok((await p.readFolder([file('course.json',2),file('body.md',21000000,'# Content')])).files['body.md']);
 assert.ok((await p.readFolder([file('course.json',2),file('page.png',21000000)])).assets['page.png']);
 await p.readFolder([file('course.json',2),file('body.md',99999998)]);
 await assert.rejects(()=>p.readFolder([file('course.json',2),file('body.md',99999999)]),/100 MB/);
 await assert.rejects(()=>p.readFolder([file('course.json',2),file('page.png',99999999)]),/100 MB/);
 console.log('Content limits passed: CLI real >20 MB fixture; browser text/image and 100 MB boundary; >100 MB rejected.');
})().catch(e=>{console.error(e);process.exitCode=1;});
