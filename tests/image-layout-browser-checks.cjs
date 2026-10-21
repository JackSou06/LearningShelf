const {chromium} = require(process.env.LEARNING_PLAYWRIGHT_PATH || 'playwright');
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const {pathToFileURL} = require('node:url');
const {loadFolder} = require('../scripts/validate-course.cjs');
const C = require('../web/course-core.js');

(async () => {
  const directory = path.resolve(process.argv[2]), out = path.resolve(process.argv[3]);
  const pack = loadFolder(directory); pack.assets = {};
  const manifest = JSON.parse(pack.files['course.json']), ref = manifest.topics[0];
  const topic = JSON.parse(pack.files[ref.file]), crop = topic.blocks.find(b => b.id === 'crop');
  assert.ok(crop, 'Use the native optimization fixture with a crop');
  for (const invalid of [{widthPercent:0},{widthPercent:101},{maxHeight:0},{maxHeight:801},{align:'float'},{position:'absolute'},'large']) {
    const copy = JSON.parse(JSON.stringify(pack)), t = JSON.parse(copy.files[ref.file]);
    t.blocks.find(b=>b.id==='crop').display=invalid; copy.files[ref.file]=JSON.stringify(t);
    assert.equal(C.validate(copy).valid,false,JSON.stringify(invalid));
  }
  for (const file of Object.keys(pack.available)) if (/\.(png|jpe?g|webp)$/i.test(file)) pack.assets[file]=pathToFileURL(path.join(directory,file)).href;
  fs.mkdirSync(out,{recursive:true});
  const browser=await chromium.launch({headless:true,channel:'chrome'}), results=[];
  try {
    for (const viewport of [{width:1440,height:1000},{width:900,height:820},{width:600,height:900}]) {
      const page=await browser.newPage({viewport}), errors=[];
      page.on('pageerror',e=>errors.push(e.message));
      await page.goto(pathToFileURL(path.resolve(__dirname,'../web/index.html')).href);
      await page.evaluate(value=>LearningApp.openPack(value),pack);
      await page.waitForSelector('#reader:not([hidden])');
      await page.locator('#lesson img').evaluateAll(images=>Promise.all(images.map(img=>img.complete?Promise.resolve():new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;}))));
      await page.waitForTimeout(150);
      const onSheet=async()=>page.evaluate(()=>{
        const img=document.querySelector('[data-block="crop"] img').getBoundingClientRect(),v=document.querySelector('#book-viewport').getBoundingClientRect();
        return img.left>=v.left-2 && img.right<=v.right+2 && img.top>=v.top-2 && img.bottom<=v.bottom+2;
      });
      for(let n=0;n<30&&!await onSheet();n++){await page.locator('#next').click();await page.waitForTimeout(240);}
      assert.ok(await onSheet(),'Crop reachable and fits inside reading sheet');
      const measure=await page.evaluate(()=>{
        const img=document.querySelector('[data-block="crop"] img'),r=img.getBoundingClientRect(),reading=document.querySelector('[data-block="crop-reading"]').getBoundingClientRect(),v=document.querySelector('#book-viewport').getBoundingClientRect();
        return {height:r.height,width:r.width,sheetHeight:v.height,readingOnSameSheet:reading.left>=v.left-2&&reading.right<=v.right+2,description:img.alt,naturalWidth:img.naturalWidth};
      });
      assert.ok(measure.height<=260.5 && measure.height<=measure.sheetHeight*.48+.5,'Crop reserves page space for text');
      assert.ok(measure.readingOnSameSheet,'Short adjacent crop explanation fits on the same sheet');
      const details=topic.blocks.filter(b=>b.visibility==='contextOnly');
      for(const b of details)assert.equal(await page.locator('[data-block="'+b.id+'"]').count(),0);
      await page.locator('#context-open').click();
      const context=await page.locator('#text-content').inputValue();
      for(const b of details)assert.ok(context.includes(pack.files[b.file]));
      await page.locator('[data-close="text-dialog"]').click();
      await page.locator('[data-block="crop"] [data-enlarge-image]').click();
      await page.waitForSelector('#image-preview[open]');
      const full=await page.locator('#image-preview img').evaluate(img=>({width:img.width,naturalWidth:img.naturalWidth,height:img.height,naturalHeight:img.naturalHeight}));
      assert.equal(full.width,full.naturalWidth);assert.equal(full.height,full.naturalHeight);
      await page.keyboard.press('Escape');assert.equal(await page.locator('#image-preview').evaluate(d=>d.open),false);
      await page.screenshot({path:path.join(out,'image-layout-'+viewport.width+'.png')});
      // The same field supports all three alignments, without changing image pixels.
      for(const align of ['left','center','right']){
        const copy=JSON.parse(JSON.stringify(pack)), t=JSON.parse(copy.files[ref.file]);
        t.blocks.find(b=>b.id==='crop').display={widthPercent:40,maxHeight:180,align};copy.files[ref.file]=JSON.stringify(t);
        assert.ok(C.validate(copy).valid);
        await page.evaluate(value=>LearningApp.openPack(value),copy);
        const figure=page.locator('[data-block="crop"] figure');
        assert.ok(await figure.evaluate((el,a)=>el.classList.contains('image-align-'+a),align));
      }
      assert.deepEqual(errors,[]);results.push({viewport,...measure,originalSizePreview:true,hiddenDetailsComplete:true});await page.close();
    }
    fs.writeFileSync(path.join(out,'image-layout-results.json'),JSON.stringify({passed:true,results,remoteQACalled:false},null,2)+'\n');
    console.log(JSON.stringify({passed:true,viewports:results.length,fullSizePreview:true,sameSheetExplanations:true,hiddenQAContext:true}));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
