/* Exercise persisted AI answers without network or AI requests. */
const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {pathToFileURL}=require('node:url'),root=path.resolve(__dirname,'..');
const inverse=String.raw`\[
a\,a^{-1}=a^{-1}a=1.
\]`;
const fixtures=[
 ['inverse','乘法反元素：\n\n'+inverse+'\n\n左右相乘皆為單位元素。'],
 ['inline',String.raw`若 \(a\ne0\)，則 $a^{-1}=\frac{1}{a}$。`],
 ['dollars',String.raw`計算：$$\frac{1}{2}+\frac{1}{2}=1$$，完成。`],
 ['multiline',String.raw`\[
\begin{aligned}
x+y &= 2 \\

x-y &= 0
\end{aligned}
\]`],
 ['table',String.raw`| 名稱 | 定義 |
| --- | --- |
| 反元素 | \(a^{-1}\) |
| 絕對值 | $|a|$ |`],
 ['code','原樣顯示 `'+String.raw`\[a^{-1}\]`+'`，以及 ``$x$``'],
 ['fenced','```latex\n'+inverse+'\n\n$x$\n```'],
 ['unfinished-code','```latex\n'+inverse],
 ['invalid',String.raw`\[\unknownMathCommand{x}\]`],
 ['unfinished',String.raw`尚未完成：\[a^{-1}=1`],
 ['escaped',String.raw`文字：\\[a\\]，費用 \$5、\$10，以及 $5 and $10。`],
 ['safe',String.raw`\[\href{javascript:alert(1)}{x}\]
\[\includegraphics{https://example.invalid/private.png}\]
\[\text{<img src=x onerror=alert(1)>}\]`],
 ['wide',String.raw`\[\underbrace{a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a+a}_{30\text{ terms}}\]`],
 ['list',String.raw`- 反元素為 \(a^{-1}\)
- 單位元素為 $1$

### **公式**
普通第一行
普通第二行`]
];
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[],network=[];
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
  page.on('pageerror',error=>errors.push(error.message));page.on('request',req=>{if(/^https?:/.test(req.url()))network.push(req.url());});
  await page.goto(pathToFileURL(process.env.LEARNING_QA_HTML||path.join(root,'web/index.html')).href);
  await page.evaluate(async fixtures=>{
   const pack=BUNDLED_COURSES[0],course=CourseCore.validate(pack).course,record=LearningRecords.empty(course.courseId);
   record.qa=fixtures.map(([id,answer])=>({id,topic:course.topics[0].id,question:id==='inverse'?'如何理解反元素？':id,answer,status:'done',time:new Date().toISOString(),version:course.contentVersion,model:'fixture',error:''}));
   await LearningApp.openPack(pack,record);
  },fixtures);
  const answer=id=>page.locator('[data-qa-id="'+id+'"] .qa-answer');
  await page.locator('.qa-exchange').evaluateAll(els=>els.forEach(el=>el.open=true));
  const exact=answer('inverse');assert.equal(await exact.locator('math[display="block"]').count(),1);
  assert.equal((await exact.locator('annotation').textContent()).trim(),String.raw`a\,a^{-1}=a^{-1}a=1.`);
  assert.equal(await exact.locator('msup').count(),2);assert.equal(await exact.locator('math br').count(),0);
  assert.match(await exact.innerText(),/左右相乘皆為單位元素/);
  assert.equal(await answer('inline').locator('math').count(),2);assert.equal(await answer('inline').locator('.markdown-math-display').count(),0);
  assert.equal(await answer('inline').locator('mfrac').count(),1);
  assert.equal(await answer('dollars').locator('math[display="block"]').count(),1);
  assert.equal(await answer('multiline').locator('mtable').count(),1);assert.equal(await answer('multiline').locator('math br').count(),0);
  assert.equal(await answer('table').locator('table').count(),1);assert.equal(await answer('table').locator('tbody td').count(),4);assert.equal(await answer('table').locator('math').count(),2);
  assert.equal(await answer('code').locator('math').count(),0);assert.equal(await answer('code').locator('code').count(),2);
  for(const id of ['fenced','unfinished-code','unfinished','escaped'])assert.equal(await answer(id).locator('math').count(),0,id);
  assert.equal(await answer('fenced').locator('pre code').textContent(),inverse+'\n\n$x$');
  assert.equal(await answer('invalid').locator('.markdown-math-fallback code').textContent(),String.raw`\[\unknownMathCommand{x}\]`);
  assert.equal(await answer('safe').locator('a,img,script,iframe').count(),0);assert.equal(await answer('safe').locator('math').count(),3);
  assert.equal(await answer('list').locator('li math').count(),2);assert.equal(await answer('list').locator('h3 strong').textContent(),'公式');assert.match(await answer('list').innerHTML(),/普通第一行<br>普通第二行/);
  for(const [width,height] of [[1440,1000],[820,1180],[390,844]]){
   await page.setViewportSize({width,height});await page.waitForTimeout(100);
   const box=await answer('wide').locator('.markdown-math-display').evaluate(el=>{el.scrollLeft=80;return {width:el.clientWidth,content:el.scrollWidth,scroll:el.scrollLeft,parent:el.closest('.qa-answer').clientWidth,page:document.documentElement.scrollWidth-innerWidth};});
   assert.ok(box.width<=box.parent&&box.page<=1,JSON.stringify(box));if(width===390)assert.ok(box.content>box.width&&box.scroll>0,JSON.stringify(box));
  }
  await page.waitForFunction(()=>document.querySelector('#save-status').textContent==='已保存');
  await page.waitForFunction(()=>localStorage.getItem('learning-md:'+CourseCore.validate(BUNDLED_COURSES[0]).course.courseId)?.includes('a\\,a^{-1}'));
  const record=await page.evaluate(()=>JSON.parse(localStorage.getItem('learning-records:'+CourseCore.validate(BUNDLED_COURSES[0]).course.courseId)));
  assert.equal(record.qa.find(q=>q.id==='inverse').answer,fixtures[0][1]);
  await page.reload();await page.locator('[data-course-index="0"]').click();await page.locator('[data-qa-id="inverse"]').evaluate(el=>el.open=true);
  assert.equal(await answer('inverse').locator('math').count(),1,'saved answers render formulas after reopening');
  if(process.env.LEARNING_QA_SHOTS){
   fs.mkdirSync(process.env.LEARNING_QA_SHOTS,{recursive:true});await page.setViewportSize({width:1000,height:1000});await answer('inverse').locator('math').scrollIntoViewIfNeeded();
   await page.screenshot({path:path.join(process.env.LEARNING_QA_SHOTS,'qa-inverse-formula.png')});
  }
  assert.deepEqual(errors,[]);assert.deepEqual(network,[]);
  console.log('Q&A math checks passed: exact inverse formula, four delimiters, multiline alignment, fractions, formula tables/lists, literal code, malformed/incomplete input, escaped currency, untrusted commands, narrow-screen scrolling, unchanged saved/MD text and reopening. No network/AI requests.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
