/* UI behavior checks. Run with LEARNING_PLAYWRIGHT_PATH pointing to Playwright. */
const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {pathToFileURL}=require('node:url');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const errors=[],root=path.resolve(__dirname,'..'),shots=process.env.LEARNING_UI_SHOTS;
 const context=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));
 const settle=()=>page.waitForTimeout(100);
 async function shot(name){if(shots){fs.mkdirSync(shots,{recursive:true});await page.screenshot({path:path.join(shots,name+'.png')});}}
 async function topic(id){await page.evaluate(id=>document.querySelector('[data-topic="'+id+'"]').click(),id);await settle();}
 async function reveal(selector){for(let i=0;i<15;i++){if(await page.locator(selector).first().evaluate(e=>{const r=e.getBoundingClientRect(),v=document.querySelector('#book-viewport').getBoundingClientRect();return r.left>=v.left-1&&r.right<=v.right+1&&r.top>=v.top-1&&r.bottom<=v.bottom+1;}))return;await page.locator('#next').click();await settle();}throw Error('Cannot reveal '+selector);}
 try{
  await page.goto(pathToFileURL(path.join(root,'web/index.html')).href);await shot('home');
  await page.locator('#course-search').fill('no-matching-course');assert.match(await page.locator('#course-list').innerText(),/找不到符合/);await page.locator('#course-search').fill('');
  await page.locator('[data-course-index="0"]').click();await settle();
  assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'true');
  assert.equal(await page.locator('.qa-send').isDisabled(),true);await page.locator('.qa-input').fill('Draft only');assert.equal(await page.locator('.qa-send').isEnabled(),true);await page.locator('.qa-input').fill('');
  const sidebar=await page.locator('#sidebar').boundingBox(),book=await page.locator('#book-viewport').boundingBox();assert.ok(book.x>=sidebar.x+sidebar.width,'pinned TOC must not cover the book');
  assert.equal(await page.locator('#backdrop').isVisible(),false);
  await page.locator('#quick-bookmark').click();assert.equal(await page.locator('#quick-bookmark').getAttribute('aria-pressed'),'true');
  await page.locator('#page-options').click();assert.equal(await page.locator('#page-details').evaluate(e=>e.matches(':modal')),false);
  await page.waitForFunction(()=>document.querySelector('#lesson').clientWidth===document.querySelector('#book-viewport').clientWidth);await page.locator('#note').fill('UI check: notes remain attached to this topic.');await page.locator('#save-status').filter({hasText:'已保存'}).waitFor();
  const note=await page.locator('#page-details').boundingBox(),narrowBook=await page.locator('#book-viewport').boundingBox();assert.ok(narrowBook.x+narrowBook.width<=note.x,'notes must not cover the reading area');await shot('reader-with-notes');
  await topic('dup');assert.equal(await page.locator('#note').inputValue(),'');assert.match(await page.locator('#note-topic').innerText(),/dup/);assert.equal(await page.locator('#page-details').isVisible(),true);
  await topic('start');assert.match(await page.locator('#note').inputValue(),/UI check/);
  await page.locator('#note').press('Escape');await page.locator('#page-details').waitFor({state:'hidden'});assert.equal(await page.locator('#page-options').getAttribute('aria-expanded'),'false');
  await page.locator('#record-open').click();assert.match(await page.locator('#record-summary').innerText(),/主題筆記/);assert.equal(await page.locator('#backup-preview').isVisible(),false);await shot('records');await page.locator('[data-close="records-dialog"]').click();
  await topic('model-check');await reveal('.option');await page.locator('.option').first().click();await page.locator('[data-check]').first().click();await settle();
  assert.equal(await page.locator('.quiz-feedback.wrong').count(),1);assert.match(await page.locator('.option.wrong').innerText(),/你的選擇/);assert.match(await page.locator('.option.correct').innerText(),/正確答案/);await shot('quiz-feedback');
  const retry=page.locator('[data-retry]').first();await reveal('[data-retry]');await retry.click();await reveal('.option');await page.locator('.option').nth(1).click();await page.locator('[data-check]').first().click();await settle();assert.match(await page.locator('.quiz-feedback.right').innerText(),/答對/);
  await page.setViewportSize({width:820,height:1180});await settle();assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'false');
  await page.locator('#menu-toggle').click();assert.equal(await page.locator('#search').evaluate(e=>e===document.activeElement),true);await page.locator('#search').press('Escape');assert.equal(await page.locator('#menu-toggle').getAttribute('aria-expanded'),'false');
  await page.locator('#page-options').click();assert.equal(await page.locator('#page-details').evaluate(e=>e.matches(':modal')),true);await page.locator('[data-close="page-details"]').click();
  await topic('dup');await page.locator('#next').click();await settle();await shot('tablet-lab');
  const all=await page.evaluate(()=>CourseCore.validate(BUNDLED_COURSES[0]).course.topics.map(t=>t.id));
  for(const [width,height] of [[1440,1000],[1100,820],[820,1180],[390,844]]){
   await page.setViewportSize({width,height});await settle();
   for(const id of all){await topic(id);const layout=await page.evaluate(()=>{const book=document.querySelector('#book-viewport').getBoundingClientRect(),bar=document.querySelector('.topbar'),main=document.querySelector('main');return {bookWidth:book.width,bookHeight:book.height,overflow:bar.scrollWidth-bar.clientWidth,mainOverflow:main.scrollHeight-main.clientHeight};});assert.ok(layout.bookWidth>240&&layout.bookHeight>150,JSON.stringify({width,id,layout}));assert.ok(layout.overflow<=1,JSON.stringify({width,id,layout}));assert.ok(layout.mainOverflow<=1,JSON.stringify({width,id,layout}));}
   if(width===390){await topic('dup');await shot('mobile');await page.locator('#record-open').click();assert.equal(await page.locator('#record-summary').isVisible(),true);await page.locator('[data-close="records-dialog"]').click();}
  }
  assert.deepEqual(errors,[]);await page.goto(pathToFileURL(path.join(root,'dist/LearningShelf.html')).href);await page.locator('[data-course-index="0"]').click();await settle();assert.equal(await page.locator('#quick-bookmark').isVisible(),false);assert.equal(await page.locator('#current-topic').isVisible(),true);
  console.log(JSON.stringify({pinnedTOC:true,dockedAndModalNotes:true,notesPersistPerTopic:true,keyboardDismissal:true,quickBookmark:true,recordSummary:true,quizWrongRightAndRetry:true,responsiveTopics:all.length*4,portableReader:true,errors},null,2));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
