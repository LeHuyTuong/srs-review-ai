// Đo riêng PageHeading; không suy rộng số đo này thành pixel parity toàn màn hình.
import {readFile,writeFile} from 'node:fs/promises';
const root='docs/evidence/phase2';const result=[];
const prefixes={courses:'QUẢN LÝ HỌC VỤ',course:'SWP391',offering:'HỌC KỲ FALL 2026',classes:'QUẢN LÝ LỚP HỌC',class:'FALL 2026 · SWP391 · SE1701',rules:'Bộ quy tắc'};
for(const width of [360,390,412]){
 const native=JSON.parse(await readFile(`${root}/flutter-${width}.json`,'utf8'));
 for(const [name,prefix] of Object.entries(prefixes)){
   const reference=JSON.parse(await readFile(`${root}/react-${width}-${name}.json`,'utf8'));
   const row=reference.find(r=>r.kind==='pageHeading'&&r.text.startsWith(prefix));
   if(!row)throw Error(`Không tìm thấy PageHeading React ${width}/${name}`);
   const box=native.screens[name].heading;
   result.push({width,screen:name,react:row.box,flutter:box,deltaY:box.y-native.topInset-row.box.y,deltaHeight:box.height-row.box.height});
 }
}
await writeFile(`${root}/heading-geometry.json`,JSON.stringify(result,null,2));
console.log(JSON.stringify({measurements:result.length,maxAbsoluteDeltaY:Math.max(...result.map(r=>Math.abs(r.deltaY))),maxAbsoluteDeltaHeight:Math.max(...result.map(r=>Math.abs(r.deltaHeight)))}));
