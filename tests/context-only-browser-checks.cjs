const {chromium}=require(process.env.LEARNING_PLAYWRIGHT_PATH||'playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const {loadFolder}=require('../scripts/validate-course.cjs');
(async()=>{const browser=await chromium.launch({headless:true,channel:'chrome'});const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
try{const root=path.resolve(__dirname,'..'),dir=path.resolve(process.env.LEARNING_TEST_COURSE),pack=loadFolder(dir);pack.assets={};for(const p of Object.keys(pack.available)){if(/\.(jpg|png)$/.test(p))pack.assets[p]=pathToFileURL(path.join(dir,p)).href;}
await page.goto(pathToFileURL(path.join(root,'web/index.html')).href);await page.evaluate(p=>LearningApp.openPack(p),pack);await page.waitForSelector('#reader:not([hidden])');
const map=JSON.parse(fs.readFileSync(path.join(dir,'IMAGE_MAP.json'))),plan=JSON.parse(fs.readFileSync(path.join(dir,'course.json'))),checked=[];
for(const e of plan.topics){await page.evaluate(id=>document.querySelector('[data-topic="'+id+'"]').click(),e.id);await page.waitForTimeout(80);
const entries=map.filter(x=>x.topic===e.id);for(const x of entries){assert.equal(await page.locator('[data-block="'+x.detailBlock+'"]').count(),0);assert.equal(await page.locator('[data-block="'+x.readingBlock+'"]').count(),1);assert.equal(await page.locator('[data-block="'+x.imageBlock+'"] img').count(),1);}
const text=await page.locator('#lesson').textContent();for(const h of ['圖中可見事實','標記清單','推論限制與待核對','內容解釋與圖中關係'])assert.ok(!text.includes(h),e.id+' contains '+h);
if(entries.length){await page.locator('#context-open').click();const actual=await page.locator('#text-content').inputValue();for(const x of entries)assert.ok(actual.includes(fs.readFileSync(path.join(dir,x.detail),'utf8')),e.id+' missing full detail');await page.locator('[data-close="text-dialog"]').click();}
checked.push({topic:e.id,hiddenDetails:entries.length,passed:true});}
await page.locator('#search').fill('推論限制與待核對');assert.equal(await page.locator('[data-topic]').count(),0);await page.locator('#search').fill('');
await page.evaluate(id=>document.querySelector('[data-topic="'+id+'"]').click(),'heap-property');await page.waitForTimeout(200);if(process.env.LEARNING_UI_SHOTS){fs.mkdirSync(process.env.LEARNING_UI_SHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.LEARNING_UI_SHOTS,'hidden-detail-reader.png')});}
assert.deepEqual(errors,[]);const report={passed:true,topics:checked.length,imagePlacements:map.length,hiddenDetailsAbsentFromDOM:true,completeDetailsInActualContextPreview:true,hiddenHeadingsAbsentFromSearch:true,remoteAICalled:false,errors,checked};if(process.env.LEARNING_BROWSER_REPORT)fs.writeFileSync(process.env.LEARNING_BROWSER_REPORT,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({...report,checked:undefined}));
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1});
