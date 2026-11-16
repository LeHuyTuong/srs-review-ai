import { chromium } from 'file:///C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
const browser = await chromium.launch({channel:'chrome',headless:true});
const page = await browser.newPage({viewport:{width:390,height:771}});
page.on('requestfailed',r=>console.log(r.url(),r.failure()?.errorText));
await page.addInitScript(()=>localStorage.setItem('project-review:session',JSON.stringify({role:'supervisor'})));
await page.goto('http://127.0.0.1:4173/dashboard');
await page.evaluate(()=>document.fonts.ready);
console.log(JSON.stringify(await page.evaluate(()=>({
  fonts:[...document.fonts].map(f=>({family:f.family,status:f.status,weight:f.weight})),
  label:getComputedStyle(document.querySelector('nav[aria-label="Điều hướng chính"] span')).font,
  width:document.querySelector('nav[aria-label="Điều hướng chính"] span').getBoundingClientRect().width,
})),null,2));
await browser.close();
