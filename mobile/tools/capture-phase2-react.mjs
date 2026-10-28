// Chụp ứng dụng tham khảo trên bản sao, không thay đổi source React Lab 2.
import { chromium } from 'file:///C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import { mkdir,readFile,writeFile } from 'node:fs/promises';
const root='docs/evidence/phase2';await mkdir(root,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
const routes={courses:'/courses',course:'/courses/swp391',offering:'/course-offerings/off-f26-swp391',classes:'/classes',class:'/classes/se1701',rules:'/rule-sets'};
for(const width of [360,390,412]){
  let height=844;
  try{const meta=JSON.parse(await readFile(`${root}/flutter-${width}.json`,'utf8'));height=Math.round(meta.height-meta.topInset-meta.bottomInset);}catch{}
  const page=await browser.newPage({viewport:{width,height}});await page.addInitScript(()=>localStorage.setItem('project-review:session',JSON.stringify({role:'supervisor'})));
  for(const [name,route] of Object.entries(routes)){
    await page.goto('http://127.0.0.1:4173'+route);await page.locator('.mobile-header').waitFor();await page.evaluate(()=>document.fonts.ready);
    await page.screenshot({path:`${root}/react-${width}-${name}.png`});
    const metrics=await page.evaluate(()=>{
      const heading=document.querySelector('.mobile-content h1')?.parentElement?.parentElement;
      return [...(heading?[{kind:'pageHeading',text:heading.innerText,box:heading.getBoundingClientRect().toJSON()}]:[]),...[...document.querySelectorAll('.mobile-content h1,.mobile-content button,.mobile-content .phase-tabs, .mobile-content section,.mobile-content > div > div')].filter(e=>e.getBoundingClientRect().height>0).map(e=>({text:e.innerText.slice(0,130),box:e.getBoundingClientRect().toJSON()}))];
    });
    await writeFile(`${root}/react-${width}-${name}.json`,JSON.stringify(metrics,null,2));
    if(name==='courses'){await page.getByRole('button',{name:'Thêm môn học',exact:true}).click();await page.screenshot({path:`${root}/react-${width}-course-form.png`});}
    if(name==='course'){
      await page.getByRole('button',{name:'Cấu hình nộp bài',exact:true}).first().click();await page.screenshot({path:`${root}/react-${width}-rule-editor.png`});await page.getByRole('button',{name:'Đóng',exact:true}).click();
      await page.getByRole('button',{name:/^Thao tác /}).first().click();await page.getByRole('menuitem',{name:'Áp dụng',exact:true}).click();await page.screenshot({path:`${root}/react-${width}-rule-assignment.png`});
    }
    if(name==='offering'){await page.getByRole('tab',{name:'Lab',exact:true}).click();await page.screenshot({path:`${root}/react-${width}-labs.png`});await page.getByRole('tab',{name:'Lớp',exact:true}).click();await page.screenshot({path:`${root}/react-${width}-offering-classes.png`});}
    if(name==='class'){for(const [key,label]of Object.entries({'class-overview':'Tổng quan','class-projects':'Dự án','class-reviews':'Yêu cầu đánh giá'})){await page.getByRole('tab',{name:label,exact:true}).click();await page.waitForTimeout(200);await page.screenshot({path:`${root}/react-${width}-${key}.png`});}}
  }
  await page.close();
}
await browser.close();console.log('Ảnh React Phase 2 đã lưu: 360/390/412dp');
