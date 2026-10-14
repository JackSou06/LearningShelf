const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright'),{spawn}=require('node:child_process'),path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{
 const root=process.env.LEARNING_SHARE_PROJECT||path.resolve(__dirname,'..');
 const server=spawn(process.env.LEARNING_SHARE_TEST_BIN||'/tmp/learning-share-checks',[root,'--serve']);let browser;
 try{
  const base=await new Promise((resolve,reject)=>{let text='';server.stdout.on('data',d=>{text+=d;const m=text.match(/READY (http:\/\/[^\s]+)/);if(m)resolve(m[1]);});server.stderr.on('data',d=>process.stderr.write(d));server.on('exit',c=>reject(Error('Fixture exited '+c)));setTimeout(()=>reject(Error('Startup timeout')),10000).unref();});
  browser=await chromium.launch({headless:true,channel:'chrome'});
  const desktopContext=await browser.newContext({viewport:{width:1440,height:1000},reducedMotion:'reduce'}),tabletContext=await browser.newContext({viewport:{width:820,height:1180},reducedMotion:'reduce'});
  if(!process.argv.includes('--original'))for(const context of [desktopContext,tabletContext])for(const name of ['reader.js','record-sync.js'])await context.route('**/'+name+'*',route=>route.fulfill({path:path.resolve(__dirname,'../web/'+name),contentType:'text/javascript'}));
  await desktopContext.addInitScript(()=>{
   let flip=false;const reorder=value=>Array.isArray(value)?value.map(reorder):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).reverse().map(([k,v])=>[k,reorder(v)])):value;
   window.webkit={messageHandlers:{learning:{postMessage:async({id,action,data})=>{try{
    const get=async(route,body)=>{const response=await fetch(new URL('api/'+route,location.href),{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json'}:{},body:body?JSON.stringify(body):undefined});let value=await response.json();if(!response.ok)throw Error(value.error);if(value.format==='learning-records'){flip=!flip;if(flip)value=reorder(value);}return value;};let result;
    if(action==='ready'){await LearningApp.openPack(BUNDLED_COURSES[0],await get('records'));result={remembered:true};}
    else if(action==='loadRecords')result=await get('records');else if(action==='saveRecords')result=await get('records',data);else if(action==='syncMD')result=(await get('markdown',{})).status;else if(action==='mdStatus')result='MD on host';else throw Error('Unexpected action '+action);
    nativeReply(id,result);
   }catch(e){nativeReply(id,null,e.message);}}}}};
  });
  const desktop=await desktopContext.newPage(),tablet=await tabletContext.newPage(),errors=[];
  for(const p of [desktop,tablet])p.on('pageerror',e=>errors.push(e.message));
  const initial=await (await fetch(base+'api/records')).json();const seeded=JSON.parse(JSON.stringify(initial));seeded.last='linear-combination';seeded.answers={'linear-combination:check':{optionId:'length',version:'1.0.0'},'other:previous':{optionId:'old',version:'1.0.0'}};
  assert.ok((await fetch(base+'api/records',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({record:seeded,base:initial})})).ok);
  await Promise.all([desktop.goto(base+'#linear-combination'),tablet.goto(base+'#linear-combination')]);
  for(const p of [desktop,tablet]){await p.waitForFunction(()=>document.querySelector('.toc-item.active')?.dataset.topic==='linear-combination');await p.waitForFunction(()=>document.querySelector('#save-status').textContent==='已同步電腦');}
  await desktop.evaluate(()=>{window.quizReplacements=0;window.quizObserver=new MutationObserver(list=>{for(const m of list)for(const n of m.removedNodes)if(n.nodeType===1&&n.matches('.quiz'))window.quizReplacements++;});quizObserver.observe(document.querySelector('#lesson'),{childList:true});});
  await desktop.waitForTimeout(3300);
  const replacements=await desktop.evaluate(()=>quizReplacements);assert.equal(replacements,0,'unchanged host data must not keep replacing exercise controls');
  async function reveal(p,selector){for(let i=0;i<12;i++){const visible=await p.locator(selector).evaluate(e=>{const r=e.getBoundingClientRect(),hit=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2);return r.left>=0&&r.right<=innerWidth&&r.top>=0&&r.bottom<=innerHeight&&(hit===e||e.contains(hit));});if(visible)return;await p.locator('#next').click();await p.waitForTimeout(250);}throw Error('Could not reveal '+selector);}
  const choice='[data-question="check"][data-choice="scale-add"]',check='[data-check="check"]';
  await reveal(desktop,choice);await desktop.locator(choice).click();assert.equal(await desktop.locator(check).isEnabled(),true);await desktop.waitForTimeout(2300);assert.equal(await desktop.locator(choice).getAttribute('aria-pressed'),'true');assert.equal(await desktop.locator(check).isEnabled(),true);
  await desktop.locator(check).click();await desktop.waitForFunction(()=>document.querySelector('[data-block="check"] .quiz-feedback'));
  await tablet.waitForFunction(()=>document.querySelector('[data-block="check"] .quiz-feedback'));
  let records=await (await fetch(base+'api/records')).json();assert.equal(records.answers['linear-combination:check'].optionId,'scale-add');assert.equal(records.answers['linear-combination:check'].version,'1.0.1');
  await reveal(tablet,'[data-retry="check"]');await tablet.locator('[data-retry="check"]').click();await desktop.waitForFunction(()=>!document.querySelector('[data-block="check"] .quiz-feedback'));assert.equal(await desktop.locator(check).isDisabled(),true);
  await reveal(tablet,'[data-question="check"][data-choice="length"]');await tablet.locator('[data-question="check"][data-choice="length"]').click();await tablet.locator(check).click();await desktop.waitForFunction(()=>!!document.querySelector('[data-block="check"] .option.wrong'));
  await desktop.reload();await desktop.waitForFunction(()=>!!document.querySelector('[data-block="check"] .option.wrong'));records=await (await fetch(base+'api/records')).json();assert.equal(records.answers['linear-combination:check'].optionId,'length');assert.deepEqual(errors,[]);
  const result={unchangedAnswersNoRedraw:true,oldVersionCanReanswer:true,selectionSurvivesSync:true,submitAndExplanation:true,desktopTabletAnswerSync:true,remoteRetryClearsOldSelection:true,tabletWrongAnswerAndReload:true,errors};fs.writeFileSync(path.join(__dirname,'quiz-browser-results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
 }finally{if(browser)await browser.close();server.kill('SIGTERM');}
})().catch(e=>{console.error(e);process.exitCode=1;});
