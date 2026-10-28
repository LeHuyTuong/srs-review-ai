// Cắt system inset và chuẩn hóa ảnh về dp để so sánh UI, giữ nguyên ảnh gốc.
import {createRequire} from 'node:module';
import {readFile,writeFile} from 'node:fs/promises';
const sharp=createRequire(import.meta.url)('C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root='docs/evidence/phase2';const widths=process.argv[2]?[Number(process.argv[2])]:[360,390,412];
for(const width of widths){
  const meta=JSON.parse(await readFile(`${root}/flutter-${width}.json`,'utf8'));
  for(const name of ['courses','course','offering','classes','class','rules','course-form','labs','offering-classes','rule-editor','rule-assignment','class-overview','class-projects','class-reviews']){
    const file=`${root}/flutter-${width}-${name}.png`;const m=await sharp(file).metadata();const top=Math.round(meta.topInset*meta.pixelRatio);const bottom=Math.round(meta.bottomInset*meta.pixelRatio);
    const native=await sharp(file).extract({left:0,top,width:m.width,height:m.height-top-bottom}).resize({width}).png().toBuffer();await writeFile(`${root}/normalized-${width}-${name}.png`,native);
    const ref=await sharp(`${root}/react-${width}-${name}.png`).metadata();const nm=await sharp(native).metadata();const height=Math.min(ref.height,nm.height);
    const left=await sharp(`${root}/react-${width}-${name}.png`).extract({left:0,top:0,width,height}).png().toBuffer();const right=await sharp(native).extract({left:0,top:0,width,height}).png().toBuffer();
    await sharp({create:{width:width*2,height,channels:4,background:'white'}}).composite([{input:left,left:0,top:0},{input:right,left:width,top:0}]).png().toFile(`${root}/comparison-${width}-${name}.png`);
  }
}
console.log('Đã tạo ảnh React trái / Flutter phải.');
