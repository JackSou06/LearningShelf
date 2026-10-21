/* AI connection controls only. The reader's context, Q&A and record lifecycle stay in reader.js. */
(function(){'use strict';
window.LearningAISettings={create({platform:P,getModel,setModel,getKey,setKey}){
 const $=s=>document.querySelector(s);let info={},loginPending=false,loadingModels=false;
 function options(select,items,value){select.replaceChildren(...items.map(([id,label])=>{const o=document.createElement('option');o.value=id;o.textContent=label;return o;}));select.value=value;}
 function render(next){
  info=next||{};const chat=info.provider==='chatgpt';
  $('#ai-provider').value=chat?'chatgpt':'api';$('#api-key-fields').hidden=chat;$('#chatgpt-fields').hidden=!chat;
  $('#api-key').placeholder=info.remembered?'已保存；留空沿用原金鑰':'貼上 API Key';
  options($('#chatgpt-profile'),[['','新增 ChatGPT 帳號'],...(info.profiles||[]).map(p=>[p.id,p.label])],info.selectedProfileID||'');
  options($('#chatgpt-model'),(info.models||[]).map(m=>[m.slug,m.display_name]),info.chatGPTModel||'');
  $('#chatgpt-model').disabled=!(info.models||[]).length;
  const profile=(info.profiles||[]).find(p=>p.id===info.selectedProfileID);
  $('#chatgpt-account-status').textContent=profile?.enabled?'已連線，已授權使用 ChatGPT 方案。':profile?.connected?'已登入，尚未授權使用 ChatGPT 方案。':'尚未登入 ChatGPT。';
  $('#chatgpt-login').disabled=loginPending||!!info.loggingIn;
  $('#chatgpt-cancel').hidden=!(loginPending||info.loggingIn);
  $('#chatgpt-logout').disabled=!profile?.connected||loginPending;
  $('#chatgpt-refresh-models').disabled=!profile?.enabled||loadingModels;
  if(info.notice)$('#api-status').textContent=info.notice;
 }
 async function refresh(){const next=await P.sessionInfo();render(next);return next;}
 async function models(){if(loadingModels)return;loadingModels=true;$('#chatgpt-refresh-models').disabled=true;try{render(await P.call('chatGPTModels'));}finally{loadingModels=false;$('#chatgpt-refresh-models').disabled=false;}}
 async function show(){
  $('#api-model').value=getModel();$('#api-key').value=P.native?'':getKey();$('#api-status').textContent='';
  if(P.remote){
   $('#api-form').hidden=true;
   try{const remote=await P.sessionInfo();const ready=remote.ready??remote.hasKey;$('#api-status').textContent=(ready?'使用電腦已設定的 '+(remote.provider==='chatgpt'?'ChatGPT 帳號':'API')+'；登入資料留在電腦。':'請先在電腦的 AI 設定完成連線。')+' 模型：'+(remote.model||getModel());}
   catch(e){$('#api-status').textContent='電腦未連線。';}
  }else if(P.native){
   $('#ai-provider-row').hidden=false;$('#remember-row').hidden=false;
   try{render(await P.sessionInfo());}catch(e){$('#api-status').textContent=e.message;}
  }
  $('#api-settings').showModal();
  if(P.native&&info.provider==='chatgpt'&&(info.profiles||[]).some(p=>p.id===info.selectedProfileID&&p.enabled)){
   try{await models();}catch(e){$('#api-status').textContent=e.message;}
  }
 }
 $('#ai-provider').addEventListener('change',async()=>{try{render(await P.call('setAIProvider',{provider:$('#ai-provider').value}));if(info.provider==='chatgpt'&&(info.profiles||[]).some(p=>p.id===info.selectedProfileID&&p.enabled))await models();}catch(e){$('#api-status').textContent=e.message;}});
 $('#chatgpt-profile').addEventListener('change',async()=>{const id=$('#chatgpt-profile').value;if(!id)return;try{render(await P.call('chatGPTSelect',{profileID:id}));if((info.profiles||[]).find(p=>p.id===id)?.enabled)await models();}catch(e){$('#api-status').textContent=e.message;}});
 $('#chatgpt-model').addEventListener('change',async()=>{try{render(await P.call('chatGPTModel',{model:$('#chatgpt-model').value}));}catch(e){$('#api-status').textContent=e.message;}});
 $('#chatgpt-login').addEventListener('click',async()=>{
  const profileID=$('#chatgpt-profile').value;loginPending=true;$('#api-status').textContent='請在瀏覽器登入並授權，完成後回到這裡。';render(info);
  try{await P.call('chatGPTLogin',profileID?{profileID}:{});await refresh();if((info.profiles||[]).find(p=>p.id===info.selectedProfileID)?.enabled)await models();}
  catch(e){$('#api-status').textContent=e.message;}
  finally{loginPending=false;try{const message=$('#api-status').textContent;await refresh();$('#api-status').textContent=message;}catch(e){$('#api-status').textContent=e.message;}}
 });
 $('#chatgpt-cancel').addEventListener('click',async()=>{try{await P.call('chatGPTCancelLogin');await refresh();$('#api-status').textContent='已取消登入。';}catch(e){$('#api-status').textContent=e.message;}});
 $('#chatgpt-logout').addEventListener('click',async()=>{const button=$('#chatgpt-logout');button.disabled=true;try{render(await P.call('chatGPTLogout'));}catch(e){$('#api-status').textContent=e.message;}finally{button.disabled=false;}});
 $('#chatgpt-refresh-models').addEventListener('click',async()=>{try{await models();}catch(e){$('#api-status').textContent=e.message;}});
 $('#forget-key').addEventListener('click',async()=>{try{if(P.native)render(await P.call('forgetKey'));setKey('');$('#api-key').value='';$('#api-status').textContent=P.native&&info.notice?info.notice:'已清除 API Key；ChatGPT 帳號設定仍保留。';}catch(e){$('#api-status').textContent=e.message;}});
 $('#api-form').addEventListener('submit',async e=>{
  e.preventDefault();if(P.remote)return;
  try{
   if(!P.native||$('#ai-provider').value==='api'){
    const model=$('#api-model').value.trim();if(!model)throw Error('請填寫模型名稱');
    const key=$('#api-key').value.trim();
    if(P.native){await P.call('setKey',{key,remember:$('#remember-key').checked});setKey('');$('#api-key').value='';}
    else setKey(key);
    setModel(model);
   }
   $('#api-settings').close();
  }catch(e){$('#api-status').textContent=e.message;}
 });
 return {show,ready:next=>{if(P.native)render(next);}};
}};
})();
