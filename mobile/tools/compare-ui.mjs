// Chỉ chuẩn hóa ảnh kiểm thử theo logical pixels; không thay đổi UI hoặc ảnh gốc.
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const sharp = require('C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const width = Number(process.argv[2] ?? 390);
const root = 'docs/evidence/phase1';
const native = `${root}/flutter-${width}.png`;
const meta = JSON.parse(await readFile(`${root}/flutter-${width}.json`, 'utf8'));
const dimensions = await sharp(native).metadata();
const top = Math.round(meta.topInset * meta.pixelRatio);
const normalized = await sharp(native).extract({left:0,top,width:dimensions.width,height:dimensions.height-top})
  .resize({width}).png().toBuffer();
await writeFile(`${root}/flutter-${width}-content.png`, normalized);
const reactPath = `${root}/react-aligned-${width}.png`;
const reactMeta = await sharp(reactPath).metadata();
const flutterMeta = await sharp(normalized).metadata();
const height = Math.min(reactMeta.height, flutterMeta.height);
const react = await sharp(reactPath).extract({left:0,top:0,width,height}).png().toBuffer();
const flutter = await sharp(normalized).extract({left:0,top:0,width,height}).png().toBuffer();
await sharp({create:{width:width*2,height,channels:4,background:'white'}})
  .composite([{input:react,left:0,top:0},{input:flutter,left:width,top:0}])
  .png().toFile(`${root}/comparison-${width}.png`);
console.log(JSON.stringify({width,topInset:meta.topInset,native:dimensions.width+'x'+dimensions.height,boxes:meta.boxes}));
const baseline = JSON.parse(await readFile(`${root}/react-aligned-${width}.json`,'utf8'));
const lookup = {
  heading: baseline.find(x=>x.text.startsWith('Xin chào')),
  stats: baseline.find(x=>x.text.includes('Môn học quản lý')),
  cta: baseline.find(x=>x.text==='Mở đánh giá'),
  tasks: baseline.find(x=>x.text.startsWith('Việc cần làm')),
};
const geometry = Object.fromEntries(Object.entries(lookup).map(([key,value])=>[key,{
  flutterY:meta.boxes[key].y-meta.topInset,reactY:value.rect.y,
  deltaY:meta.boxes[key].y-meta.topInset-value.rect.y,
  flutterHeight:meta.boxes[key].height,reactHeight:value.rect.height,
  deltaHeight:meta.boxes[key].height-value.rect.height,
}]));
await writeFile(`${root}/geometry-${width}.json`,JSON.stringify(geometry,null,2));
