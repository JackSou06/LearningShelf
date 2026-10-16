/* Existing Q&A records exercise the real renderer without an AI request. */
const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..');
const byteRows=['| `0x100` | `01` | `67` |','| `0x101` | `23` | `45` |','| `0x102` | `45` | `23` |','| `0x103` | `67` | `01` |'];
const standard=['比較位元組順序：','| 位址 | Big endian | Little endian |','| --- | --- | --- |',...byteRows,'','表格後的說明。'].join('\n');
const pasted=['| Big endian | Little endian |\\','\\|---|---|---|\\',...byteRows.map(line=>line+'\\')].join('\n');
const fixtures=[
 ['standard',standard],['pasted',pasted],
 ['alignment','欄位 | 中間 | 數值\n:--- | :---: | ---:\n**粗體** | `code` | 123\n[來源](https://example.com) | 空欄 |'],
 ['pipes','| 運算 | 說明 |\n| --- | --- |\n| `a | b` | left\\|right |\n| ``x | y`` | end |'],
 ['safe','| 文字 | 程式碼 |\n| --- | --- |\n| <img src=x onerror="window.tableInjected=true"> | `<script>alert(1)</script>` |'],
 ['fenced','```text\n'+standard+'\n```'],
 ['plain','a | b\n不是分隔線\n\n- 清單\n- **重點**\n\n### 標題\n`code`'],
 ['wide','| 第一欄 | 第二欄 | 第三欄 | 第四欄 | 第五欄 | 第六欄 |\n| --- | --- | --- | --- | --- | --- |\n| A | B | C | D | E | F |'],
 ['adjacent','| A | B |\n| --- | --- |\n| 1 | 2 |\n\n| C | D |\n| --- | --- |\n| 3 | 4 |'],
 ['partial','| A | B |\n| --- | --- |\n| answer |'],
 ['crlf',standard.replace(/\n/g,'\r\n')]
];
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[];
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000},reducedMotion:'reduce'});
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(process.env.LEARNING_QA_HTML||path.join(root,'web/index.html')).href);
  await page.evaluate(async fixtures=>{
   const pack=BUNDLED_COURSES[0],course=CourseCore.validate(pack).course,record=LearningRecords.empty(course.courseId);
   record.qa=fixtures.map(([id,answer])=>({id,topic:course.topics[0].id,question:id,answer,status:'done',time:new Date().toISOString(),version:course.contentVersion,model:'fixture',error:''}));
   await LearningApp.openPack(pack,record);
  },fixtures);
  const answer=id=>page.locator('[data-qa-id="'+id+'"] .qa-answer');
  await page.locator('.qa-exchange').evaluateAll(els=>els.forEach(el=>el.open=true));
  for(const id of ['standard','pasted','crlf']){
   const el=answer(id);assert.equal(await el.locator('table').count(),1);
   assert.deepEqual(await el.locator('th').allTextContents(),[id==='pasted'?'':'位址','Big endian','Little endian']);
   assert.deepEqual(await el.locator('tbody tr').evaluateAll(rows=>rows.map(row=>[...row.cells].map(cell=>cell.textContent))),[
    ['0x100','01','67'],['0x101','23','45'],['0x102','45','23'],['0x103','67','01']
   ]);
   assert.equal(await el.locator('tbody code').count(),12);
  }
  assert.match(await answer('standard').innerText(),/比較位元組順序：[\s\S]*表格後的說明。/);
  assert.deepEqual(await answer('alignment').locator('th').evaluateAll(cells=>cells.map(cell=>getComputedStyle(cell).textAlign)),['left','center','right']);
  assert.equal(await answer('alignment').locator('strong').textContent(),'粗體');
  assert.equal(await answer('alignment').locator('a').getAttribute('href'),'https://example.com');
  assert.equal(await answer('alignment').locator('tbody tr').nth(1).locator('td').nth(2).textContent(),'');
  assert.deepEqual(await answer('pipes').locator('tbody tr').evaluateAll(rows=>rows.map(row=>[...row.cells].map(cell=>cell.textContent))),[['a | b','left|right'],['x | y','end']]);
  assert.equal(await answer('safe').locator('img,script').count(),0);assert.equal(await page.evaluate(()=>window.tableInjected),undefined);
  assert.match(await answer('safe').innerText(),/<img src=x/);
  assert.equal(await answer('fenced').locator('table').count(),0);assert.equal(await answer('fenced').locator('pre code').textContent(),standard);
  assert.equal(await answer('plain').locator('table').count(),0);assert.equal(await answer('plain').locator('li').count(),2);assert.equal(await answer('plain').locator('h3').textContent(),'標題');
  assert.equal(await answer('adjacent').locator('table').count(),2);
  assert.equal(await answer('partial').locator('tbody td').count(),2);assert.equal(await answer('partial').locator('tbody td').last().textContent(),'');
  for(const [width,height] of [[1440,1000],[820,1180],[390,844]]){
   await page.setViewportSize({width,height});
   await page.waitForTimeout(150);
   const layout=await answer('wide').locator('.markdown-table').evaluate(el=>{
    const answer=el.closest('.qa-answer'),qa=document.querySelector('.qa-panel');
    el.scrollLeft=50;
    return {width:el.clientWidth,content:el.scrollWidth,scroll:el.scrollLeft,answer:answer.clientWidth,qaOverflow:qa.scrollWidth-qa.clientWidth,pageOverflow:document.documentElement.scrollWidth-innerWidth};
   });
   assert.ok(layout.width<=layout.answer,JSON.stringify(layout));assert.ok(layout.qaOverflow<=1&&layout.pageOverflow<=1,JSON.stringify(layout));
   if(width===390)assert.ok(layout.content>layout.width&&layout.scroll>0,'wide tables must scroll inside the answer');
  }
  await page.waitForFunction(()=>document.querySelector('#save-status').textContent==='已保存');
  await page.reload();await page.locator('[data-course-index="0"]').click();
  await page.locator('[data-qa-id="pasted"]').evaluate(el=>el.open=true);
  assert.equal(await answer('pasted').locator('tbody tr').count(),4,'saved answers render tables after reopening');
  if(process.env.LEARNING_QA_SHOTS){
   fs.mkdirSync(process.env.LEARNING_QA_SHOTS,{recursive:true});
   await page.setViewportSize({width:1000,height:1000});
   await page.locator('[data-qa-id="pasted"] table').scrollIntoViewIfNeeded();
   await page.screenshot({path:path.join(process.env.LEARNING_QA_SHOTS,'qa-byte-order-table.png')});
  }
  assert.deepEqual(errors,[]);
  console.log('Q&A table checks passed: byte-order example, pasted escapes/missing header, alignment, inline formatting, escaped/code pipes, safe HTML, code fences, existing Markdown, multiple/partial tables, CRLF, desktop/tablet/mobile scrolling and saved answers. No AI requests.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
