// Xuất đúng hình học icon đang cài trong source React, giữ thông tin giấy phép.
import { writeFile, copyFile, mkdir } from 'node:fs/promises';
const icons = ['files','layout-dashboard','folder','file-check-2','inbox','user-round','file-text','chevron-right','chevron-down','circle-alert','search','rotate-cw','book-open','plus','school','save','calendar','users','sliders-horizontal','ellipsis','arrow-left','pencil','archive','trash-2','qr-code','upload','copy','check','x','settings','user-plus','info','calendar-clock','circle-check','play','lock','user-minus','folder-plus','maximize','chevron-left','circle-dot','circle-dashed','chevron-up'];
await mkdir('assets/icons',{recursive:true});
for (const name of icons) {
  const sourceName = ({'file-check-2':'file-check-corner','trash-2':'trash'})[name] ?? name;
  const { __iconData } = await import(`file:///D:/UI%20AI%20Review/node_modules/lucide-react/dist/esm/icons/${sourceName}.mjs`);
  const content=__iconData.node.map(([tag,attrs])=>`<${tag} ${Object.entries(attrs).filter(([key])=>key!=='key').map(([key,value])=>`${key}="${value}"`).join(' ')}/>`).join('');
  const stroke = ['files','layout-dashboard','folder','file-check-2','inbox','user-round'].includes(name) ? 1.75 : 2;
  await writeFile(`assets/icons/${name}.svg`,`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round">${content}</svg>`);
}
await copyFile('D:/UI AI Review/node_modules/lucide-react/LICENSE','assets/icons/LICENSE');
console.log(`Exported ${icons.length} Lucide icons`);
