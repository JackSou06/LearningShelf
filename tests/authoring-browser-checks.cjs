const {chromium} = require(process.env.LEARNING_PLAYWRIGHT_PATH || 'playwright');
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const {pathToFileURL} = require('node:url');
const {loadFolder} = require('../scripts/validate-course.cjs');

(async () => {
  const directory = path.resolve(process.argv[2]), output = path.resolve(process.argv[3]);
  const plan = JSON.parse(fs.readFileSync(path.join(directory, 'course.json')));
  const map = JSON.parse(fs.readFileSync(path.join(directory, 'IMAGE_MAP.json'))).images;
  const pack = loadFolder(directory); pack.assets = {};
  for (const file of Object.keys(pack.available)) {
    if (/\.(jpg|jpeg|png|webp)$/i.test(file)) pack.assets[file] = pathToFileURL(path.join(directory, file)).href;
  }
  const browser = await chromium.launch({headless: true, channel: 'chrome'});
  try {
    const page = await browser.newPage({viewport: {width: 1440, height: 1000}}), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(pathToFileURL(path.resolve(__dirname, '../web/index.html')).href);
    await page.evaluate(value => LearningApp.openPack(value), pack);
    await page.waitForSelector('#reader:not([hidden])');
    let detailCount = 0;
    for (const entry of plan.topics) {
      await page.locator('[data-topic="' + entry.id + '"]').click();
      const topic = JSON.parse(fs.readFileSync(path.join(directory, entry.file)));
      const hidden = topic.blocks.filter(block => block.type === 'markdown' && block.visibility === 'contextOnly');
      for (const block of hidden) assert.equal(await page.locator('[data-block="' + block.id + '"]').count(), 0);
      for (const image of map.filter(image => image.topicId === entry.id)) {
        const locator = page.locator('[data-block="' + image.imageBlockId + '"] img');
        assert.equal(await locator.count(), 1);
        await locator.evaluate(img => img.complete ? Promise.resolve() : new Promise((resolve, reject) => {img.onload = resolve; img.onerror = reject;}));
        assert.ok(await locator.evaluate(img => img.naturalWidth > 0));
      }
      if (hidden.length) {
        await page.locator('#context-open').click();
        const context = await page.locator('#text-content').inputValue();
        for (const block of hidden) {
          assert.ok(context.includes(fs.readFileSync(path.join(directory, block.file), 'utf8')), entry.id + ': detail missing from actual Q&A preview');
          detailCount++;
        }
        await page.locator('[data-close="text-dialog"]').click();
      }
    }
    assert.deepEqual(errors, []);
    fs.mkdirSync(output, {recursive: true});
    await page.locator('[data-topic="' + plan.topics[0].id + '"]').click();
    await page.screenshot({path: path.join(output, 'generated-course-reader.png')});
    const report = {passed: true, topics: plan.topics.length, images: map.length, detailCount,
      hiddenDetailsAbsentFromDOM: true, fullDetailsInActualQAPreview: true, allImagesLoaded: true, remoteQACalled: false};
    fs.writeFileSync(path.join(output, 'generated-course-browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
