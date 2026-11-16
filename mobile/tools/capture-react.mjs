// Kiểm thử giao diện ứng dụng do người dùng cung cấp trên bản sao chỉ dùng đối chiếu.
import { chromium } from 'file:///C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import { writeFile, readFile } from 'node:fs/promises';
const aligned = process.argv.includes('--aligned');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
page.on('pageerror', e => console.error(e.message));
await page.addInitScript(() => localStorage.setItem('project-review:session', JSON.stringify({role:'supervisor'})));
for (const [width,referenceHeight] of [[360,800],[390,844],[412,892]]) {
  const native = aligned ? JSON.parse(await readFile(`docs/evidence/phase1/flutter-${width}.json`,'utf8')) : null;
  const height = native ? Math.round(native.height - native.topInset - native.bottomInset) : referenceHeight;
  const suffix = aligned ? `aligned-${width}` : `${width}`;
  await page.setViewportSize({width,height});
  await page.goto('http://127.0.0.1:4173/dashboard');
  await page.getByRole('heading',{name:'Tổng quan',exact:true}).waitFor();
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({path:`docs/evidence/phase1/react-${suffix}.png`});
  const measure = await page.evaluate(() => [...document.querySelectorAll('.mobile-header, .mobile-header-inner, .phase-one > header, .phase-one > section, .phase-one > a, nav[aria-label="Điều hướng chính"]')].map(e=>({text:e.innerText,rect:e.getBoundingClientRect().toJSON(),font:getComputedStyle(e).fontSize})));
  await writeFile(`docs/evidence/phase1/react-${suffix}.json`, JSON.stringify(measure,null,2));
  if (width===390) await writeFile('docs/evidence/phase1/react-storage.json', JSON.stringify(await page.evaluate(()=>Object.fromEntries(Object.entries(localStorage))),null,2));
}
console.log('Captured React at 360/390/412');
await browser.close();
