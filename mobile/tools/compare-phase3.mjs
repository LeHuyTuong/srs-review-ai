// Ảnh gốc giữ nguyên; chỉ crop system inset/chuẩn hóa dp ở bản so sánh.
import {createRequire} from 'node:module';
import {readFile,writeFile,readdir} from 'node:fs/promises';
const sharp=createRequire(import.meta.url)('C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const root='docs/evidence/phase3';const files=await readdir(root);let pairs=0;
for(const width of [360,390,412]){
  let meta;try{meta=JSON.parse(await readFile(`${root}/flutter-${width}.json`,'utf8'));}catch{meta=JSON.parse(await readFile(`docs/evidence/phase2/flutter-${width}.json`,'utf8'));}
  for(const file of files.filter(f=>f.startsWith(`react-${width}-`)&&f.endsWith('.png'))){
    const name=file.slice(`react-${width}-`.length,-4);if(!files.includes(`flutter-${width}-${name}.png`))continue;
    const source=`${root}/flutter-${width}-${name}.png`;const m=await sharp(source).metadata();
    const top=Math.round(meta.topInset*meta.pixelRatio),bottom=Math.round(meta.bottomInset*meta.pixelRatio);
    const native=await sharp(source).extract({left:0,top,width:m.width,height:m.height-top-bottom}).resize({width}).png().toBuffer();
    await writeFile(`${root}/normalized-${width}-${name}.png`,native);
    const a=await sharp(`${root}/${file}`).metadata(),b=await sharp(native).metadata();const height=Math.min(a.height,b.height);
    await sharp({create:{width:width*2,height,channels:4,background:'white'}}).composite([
      {input:await sharp(`${root}/${file}`).extract({left:0,top:0,width,height}).png().toBuffer(),left:0,top:0},
      {input:await sharp(native).extract({left:0,top:0,width,height}).png().toBuffer(),left:width,top:0}]).png().toFile(`${root}/comparison-${width}-${name}.png`);pairs++;
  }
}
await writeFile(`${root}/comparison-summary.json`,JSON.stringify({pairs,widths:[360,390,412],order:['React','Flutter'],note:'So sánh hình học bằng mắt; không tuyên bố pixel parity.'},null,2));console.log(`${pairs} cặp React trái / Flutter phải.`);
