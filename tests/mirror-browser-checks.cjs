const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const {spawn}=require('node:child_process'),path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const server=spawn(process.env.LEARNING_SHARE_TEST_BIN||'/tmp/learning-share-checks',[path.resolve(__dirname,'..'),'--serve']);let browser;
 try{
  const base=await new Promise((resolve,reject)=>{let out='';server.stdout.on('data',d=>{out+=d;const match=out.match(/READY (http:\/\/[^\s]+)/);if(match)resolve(match[1]);});server.stderr.on('data',d=>process.stderr.write(d));server.on('exit',c=>reject(Error('Fixture exited '+c)));setTimeout(()=>reject(Error('Fixture startup timeout')),10000).unref();});
  browser=await chromium.launch({headless:true,channel:'chrome'});
  const desktopContext=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),tabletContext=await browser.newContext({viewport:{width:820,height:1180},reducedMotion:'reduce'});
  // Native Platform exercised through a WK message adapter to the same real Swift host.
  await desktopContext.addInitScript(()=>{
   window.webkit={messageHandlers:{learning:{postMessage:async({id,action,data})=>{try{
    const get=async(route,payload)=>{const response=await fetch(new URL('api/'+route,location.href),{method:payload?'POST':'GET',headers:payload?{'Content-Type':'application/json'}:{},body:payload?JSON.stringify(payload):undefined});const value=await response.json();if(!response.ok)throw Error(value.error);return value;};let result=null;
    if(action==='ready'){await LearningApp.openPack(window.BUNDLED_COURSES[0],await get('records'));result={remembered:true};}
    else if(action==='loadRecords')result=await get('records');
    else if(action==='saveRecords')result=await get('records',data);
    else if(action==='sessionInfo')result=await get('session');
    else if(action==='ask')result=await get('ask',data);
    else if(action==='cancel')result=await get('cancel',data);
    else if(action==='syncMD')result=(await get('markdown',{})).status;
    else if(action==='mdStatus')result='電腦 MD';
    else if(action!=='setKey')throw Error('Unimplemented test action '+action);
    window.nativeReply(id,result);
   }catch(e){window.nativeReply(id,null,e.message);}}}}};
  });
  const desktop=await desktopContext.newPage(),tablet=await tabletContext.newPage(),errors=[],outside=[];
  for(const p of [desktop,tablet]){p.on('pageerror',e=>errors.push(e.message));p.on('request',r=>{if(!r.url().startsWith(base)&&!r.url().startsWith('data:'))outside.push(r.url());});}
  await Promise.all([desktop.goto(base),tablet.goto(base)]);
  for(const p of [desktop,tablet])await p.waitForFunction(()=>!document.querySelector('#reader').hidden);
  assert.equal(await desktop.evaluate(()=>Platform.native),true);assert.equal(await tablet.evaluate(()=>Platform.remote),true);
  for(const p of [desktop,tablet]){await p.locator('#page-options').click();assert.equal(await p.locator('#note').inputValue(),'電腦既有筆記');assert.ok((await p.locator('#qa-thread').innerText()).includes('電腦既有問題'));}
  await tablet.locator('#note').fill('平板筆記');await tablet.locator('#note').pressSequentially('：M1 黃色 highlight',{delay:10});
  await desktop.waitForFunction(text=>document.querySelector('#note').value===text,'平板筆記：M1 黃色 highlight');
  assert.ok(!(await tablet.locator('#note').inputValue()).includes('同時編輯'));
  await desktop.locator('#note').fill('電腦再次更新筆記');await tablet.waitForFunction(()=>document.querySelector('#note').value==='電腦再次更新筆記');
  let failSave=true;await tablet.route('**/api/records',async route=>{if(failSave&&route.request().method()==='POST'){await route.abort('failed');return;}await route.continue();});
  await tablet.locator('#note').fill('斷線時尚未同步的筆記');await tablet.waitForFunction(()=>document.querySelector('#save-status').textContent.includes('未連線'));
  assert.equal(await tablet.locator('#note').inputValue(),'斷線時尚未同步的筆記');
  await desktop.locator('#note').fill('電腦在斷線期間的新筆記');failSave=false;
  await tablet.waitForFunction(()=>document.querySelector('#note').value.includes('斷線時尚未同步的筆記')&&document.querySelector('#note').value.includes('電腦在斷線期間的新筆記'));
  await desktop.waitForFunction(()=>document.querySelector('#note').value.includes('斷線時尚未同步的筆記'));await tablet.unroute('**/api/records');
  for(const p of [desktop,tablet])await p.locator('[data-close="page-details"]').click();
  await tablet.locator('#api-open').click();await tablet.locator('#api-settings').waitFor({state:'visible'});assert.equal(await tablet.locator('#api-form').isVisible(),false);assert.ok((await tablet.locator('#api-status').innerText()).includes('使用電腦已設定'));await tablet.locator('[data-close="api-settings"]').click();
  const question='右上黃色 highlight 的字是什麼意思？';await tablet.locator('.qa-input').fill(question);await tablet.locator('.qa-send').click();
  await tablet.waitForFunction(()=>document.querySelector('#qa-thread').textContent.includes('回答中'));
  await desktop.waitForFunction(q=>document.querySelector('#qa-thread').textContent.includes(q),question);
  await tablet.reload();await tablet.waitForFunction(()=>!document.querySelector('#reader').hidden);
  for(const p of [desktop,tablet])await p.waitForFunction(()=>document.querySelector('#qa-thread').textContent.includes('電腦模擬回答：右上黃色 highlight'));
  const record=await tablet.evaluate(async()=>await Platform.loadRecords(window.HOSTED_SESSION.courseId));assert.equal(record.qa.filter(q=>q.question===question).length,1);assert.equal(record.qa.find(q=>q.question===question).status,'done');
  await desktop.locator('#context-open').click();assert.ok((await desktop.locator('#text-content').inputValue()).includes('電腦模擬回答：右上黃色 highlight'));await desktop.locator('[data-close="text-dialog"]').click();
  await tablet.locator('.qa-row').filter({hasText:question}).locator('[data-qa-delete]').click();await desktop.waitForFunction(q=>!document.querySelector('#qa-thread').textContent.includes(q),question);
  await tablet.locator('.qa-input').fill('這筆要從另一端取消');await tablet.locator('.qa-send').click();await desktop.waitForFunction(()=>document.querySelector('#qa-thread').textContent.includes('這筆要從另一端取消'));
  await desktop.locator('#qa-cancel').click();await tablet.waitForFunction(()=>document.querySelector('#qa-thread').textContent.includes('已取消'));
  await new Promise(r=>setTimeout(r,2200));assert.ok(!(await tablet.locator('#qa-thread').innerText()).includes('電腦模擬回答：這筆要從另一端取消'));
  for(const p of [desktop,tablet])assert.equal(await p.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('learning-records:')||k.startsWith('learning-md:')).length),0);
  assert.deepEqual(errors,[]);assert.deepEqual(outside,[]);
  await tablet.screenshot({path:path.join(__dirname,'mirror-tablet.png')});await desktop.screenshot({path:path.join(__dirname,'mirror-desktop.png')});
  const result={realSwiftShareServer:true,nativePlatformMessageAdapter:true,desktopAndTabletNotes:true,sequentialTypingNoFalseConflict:true,offlineRetryPreservesBothEdits:true,existingQA:true,hostAPIWithoutClientKey:true,tabletReloadDuringAnswer:true,QAWriteBackAndContext:true,crossDeviceDeleteAndCancel:true,noLocalRecordOrMDStorage:true,noBrowserOpenAIRequests:true,errors};
  fs.writeFileSync(path.join(__dirname,'mirror-browser-results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }finally{if(browser)await browser.close();server.kill('SIGTERM');}
})().catch(e=>{console.error(e);process.exitCode=1;});
