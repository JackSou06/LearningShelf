const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {pathToFileURL}=require('node:url');
const root=path.resolve(__dirname,'..'),output=path.join(root,'dist/ai-connection-review');
fs.mkdirSync(output,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'}),errors=[];
 try{
  const page=await browser.newPage({viewport:{width:1180,height:900},reducedMotion:'reduce'});
  page.on('pageerror',e=>errors.push(e.message));
  await page.addInitScript(()=>{
   window.fixtureCalls=[];window.fixtureInfo={provider:'api',hasKey:true,remembered:true,profiles:[],models:[],selectedProfileID:'',chatGPTModel:''};
   let record,loginID;
   window.webkit={messageHandlers:{learning:{postMessage:({id,action,data})=>{window.fixtureCalls.push({action,data});setTimeout(async()=>{try{
    let value=null;const info=window.fixtureInfo;
    if(action==='ready'){const pack=BUNDLED_COURSES[0],course=CourseCore.validate(pack).course;record=LearningRecords.empty(course.courseId);await LearningApp.openPack(pack,record);value=info;}
    else if(action==='sessionInfo')value=info;
    else if(action==='setAIProvider'){info.provider=data.provider;value=info;}
    else if(action==='setKey'){info.remembered=data.remember;info.hasKey=true;value=info;}
    else if(action==='forgetKey'){info.remembered=false;info.hasKey=false;value=info;}
    else if(action==='chatGPTLogin'){loginID=id;window.fixtureLoginReady=true;return;}
    else if(action==='chatGPTCancelLogin'){if(loginID)nativeReply(loginID,null,'操作已取消');loginID=null;window.fixtureLoginReady=false;value=info;}
    else if(action==='chatGPTModels'){info.models=[{slug:'fixture-model',display_name:'Fixture model'}];info.chatGPTModel='fixture-model';value=info;}
    else if(action==='chatGPTModel'){info.chatGPTModel=data.model;value=info;}
    else if(action==='chatGPTLogout'){info.profiles[0].connected=false;info.profiles[0].enabled=false;info.notice='已登出 ChatGPT；API Key 設定仍保留。';value=info;}
    else if(action==='saveRecords'){record=data.record;value=record;}
    else if(action==='loadRecords')value=record;
    else if(['syncMD','mdStatus'].includes(action))value='test MD';
    else throw Error('Unexpected action '+action);
    nativeReply(id,value,null);
   }catch(e){nativeReply(id,null,e.message);}},0);}}}};
   window.completeFixtureLogin=()=>{const info=window.fixtureInfo;info.profiles=[{id:'oaiapp_browser_fixture',label:'fixture@example.invalid · fixture',enabled:true,connected:true}];info.selectedProfileID='oaiapp_browser_fixture';nativeReply(loginID,info,null);loginID=null;};
  });
  await page.goto(pathToFileURL(path.join(root,'web/index.html')).href);
  await page.locator('#reader').waitFor({state:'visible'});
  await page.locator('#api-open').click();await page.locator('#api-settings').waitFor({state:'visible'});
  assert.equal(await page.locator('#remember-key').isChecked(),true);
  assert.equal(await page.locator('#api-key').inputValue(),'');assert.match(await page.locator('#api-key').getAttribute('placeholder'),/已保存/);
  await page.locator('#api-model').fill('fixture-api-model');await page.locator('#api-form [type=submit]').click();
  const save=await page.evaluate(()=>fixtureCalls.find(x=>x.action==='setKey'));assert.deepEqual(save.data,{key:'',remember:true});
  await page.locator('#api-open').click();await page.screenshot({path:path.join(output,'api-settings.png')});
  await page.locator('#ai-provider').selectOption('chatgpt');await page.locator('#chatgpt-login').waitFor({state:'visible'});
  assert.equal(await page.locator('#api-key').isVisible(),false);
  await page.locator('#chatgpt-login').click();await page.locator('#chatgpt-cancel').waitFor({state:'visible'});await page.locator('#chatgpt-cancel').click();
  await page.waitForFunction(()=>!document.querySelector('#chatgpt-login').disabled);
  await page.locator('#chatgpt-login').click();await page.waitForFunction(()=>fixtureCalls.filter(x=>x.action==='chatGPTLogin').length===2&&fixtureLoginReady);
  await page.evaluate(()=>completeFixtureLogin());await page.waitForFunction(()=>document.querySelector('#chatgpt-model').value==='fixture-model');
  assert.match(await page.locator('#chatgpt-account-status').innerText(),/已授權/);
  await page.screenshot({path:path.join(output,'chatgpt-settings.png')});
  await page.locator('#api-form [type=submit]').click();await page.locator('#api-open').click();
  assert.equal(await page.locator('#ai-provider').inputValue(),'chatgpt');
  await page.locator('#chatgpt-logout').click();await page.waitForFunction(()=>document.querySelector('#api-status').textContent.includes('已登出'));
  await page.locator('#ai-provider').selectOption('api');assert.match(await page.locator('#api-key').getAttribute('placeholder'),/已保存/);
  await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(output,'mobile-settings.png')});
  const size=await page.locator('#api-settings').evaluate(e=>({width:e.getBoundingClientRect().width,scroll:e.scrollWidth,client:e.clientWidth}));
  assert.ok(size.width<=390&&size.scroll<=size.client+1,JSON.stringify(size));
  assert.deepEqual(errors,[]);console.log('AI settings browser checks passed: saved-key defaults, blank preserves key, explicit providers, login/cancel/account/model/logout, retained API settings and mobile layout.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
