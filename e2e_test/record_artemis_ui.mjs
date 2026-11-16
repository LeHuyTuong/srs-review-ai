// Quay trang Workspace của ARTEMIS tới khi có file STOP (hoặc 3 giờ). Mỗi 20 s bấm task mới nhất để theo kịp.
import { chromium } from '/Users/lehuytuong/.dsh/skills/flow-video-test/node_modules/playwright/index.mjs';
import { existsSync } from 'node:fs';
const out = process.argv[2];
const b = await chromium.launch({ channel: 'chrome', headless: true });
const ctx = await b.newContext({ viewport: { width: 1440, height: 900 }, recordVideo: { dir: out, size: { width: 1440, height: 900 } } });
const p = await ctx.newPage();
await p.goto('http://127.0.0.1:8020/workspace', { waitUntil: 'networkidle' });
const end = Date.now() + 3 * 3600e3;
let last = '';
while (Date.now() < end && !existsSync(out + '/STOP')) {
  try {
    const first = p.locator('text=/^ID: /').first();
    const id = await first.innerText({ timeout: 3000 });
    if (id !== last) { await first.click(); last = id; console.log(new Date().toISOString(), 'follow', id); }
  } catch {}
  await p.waitForTimeout(20000);
}
await ctx.close(); await b.close();
console.log('saved', out);
