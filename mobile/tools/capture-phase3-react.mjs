// Chạy trên bản sao với localStorage độc lập, không truy cập dữ liệu trình duyệt người dùng.
import {chromium} from 'file:///C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright/index.mjs';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
const root='docs/evidence/phase3';await mkdir(root,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
const routes={groups:'/groups',group:'/groups/se1701-group-01',projects:'/projects',project:'/projects/smart-campus-management',
  'project-documents':'/projects/smart-campus-management/documents',registrations:'/project-registrations',documents:'/documents',reviews:'/reviews',workspace:'/reviews/review-001',
  'ai-result':'/reviews/review-001/ai-result','ai-completed':'/reviews/demo-ready-persona/ai-result','workspace-ai-completed':'/reviews/demo-ready-persona',versions:'/reviews/review-001/versions','review-history':'/reviews/review-001/history',history:'/review-history',
  courses:'/courses',offering:'/course-offerings/off-f26-swp391',class:'/classes/se1701',rules:'/rule-sets',dashboard:'/dashboard'};
try{
for(const width of [360,390,412]){
  let meta;try{meta=JSON.parse(await readFile(`${root}/flutter-${width}.json`,'utf8'));}catch{meta=JSON.parse(await readFile(`docs/evidence/phase2/flutter-${width}.json`,'utf8'));}
  const page=await browser.newPage({viewport:{width,height:Math.round(meta.height-meta.topInset-meta.bottomInset)}});
  await page.addInitScript(()=>localStorage.setItem('project-review:session',JSON.stringify({role:'supervisor'})));
  async function capture(name){await page.waitForTimeout(250);await page.screenshot({path:`${root}/react-${width}-${name}.png`});
    const metrics=await page.evaluate(()=>[...document.querySelectorAll('.mobile-content h1,.mobile-content button,.mobile-content [role="tablist"],.mobile-content section')]
      .filter(e=>e.getBoundingClientRect().height>0).map(e=>({text:e.innerText.slice(0,160),box:e.getBoundingClientRect().toJSON()})));
    await writeFile(`${root}/react-${width}-${name}.json`,JSON.stringify(metrics,null,2));}
  for(const [name,route] of Object.entries(routes)){
    await page.goto('http://127.0.0.1:4173'+route);await page.locator('.mobile-header').waitFor();await page.evaluate(()=>document.fonts.ready);await capture(name);
    if(name==='group'){
      await page.getByRole('button',{name:'Thêm thành viên',exact:true}).click();await capture('group-member');await page.getByRole('button',{name:'Hủy',exact:true}).click();
      await page.getByRole('button',{name:'Thêm thao tác',exact:true}).click();await page.getByRole('menuitem',{name:'Đổi tên nhóm',exact:true}).click();await capture('group-rename');await page.getByRole('button',{name:'Hủy',exact:true}).click();
    }
    if(name==='projects'){await page.getByRole('button',{name:'Tạo dự án',exact:true}).click();await capture('project-form');await page.getByRole('button',{name:'Hủy',exact:true}).click();}
    if(name==='project')for(const [i,label] of ['Tài liệu','Thành viên','Lịch sử đánh giá','Thông tin'].entries()){
      await page.getByRole('tab',{name:label,exact:true}).click();await capture(`project-${i+1}`);
    }
    if(name==='workspace'){
      for(const [i,label] of ['AI','Phản hồi','Lịch sử'].entries()){
        await page.getByRole('tab',{name:label,exact:true}).click();await capture(`workspace-${i+1}`);
      }
      await page.getByRole('button',{name:'Thông tin',exact:true}).click();await capture('review-context');await page.getByRole('button',{name:'Đóng',exact:true}).click();
    }
    if(name==='workspace-ai-completed'){
      await page.getByRole('tab',{name:'AI',exact:true}).click();
      const criterion=page.getByRole('button',{name:/P02 ·/}).first();await criterion.click();await criterion.evaluate(el=>el.scrollIntoView({block:'start'}));await capture('criteria');
    }
  }
  await page.goto('http://127.0.0.1:4173/reviews/review-001');await page.getByRole('tab',{name:'Phản hồi',exact:true}).click();
  await page.getByPlaceholder('Quan hệ giữa sinh viên và tác vụ nộp tài liệu chưa đúng.').fill('Phản hồi Android cần làm rõ ngoại lệ');
  await page.getByRole('button',{name:'Thêm phản hồi',exact:true}).click();await page.getByRole('button',{name:'Phê duyệt',exact:true}).click();await capture('decision');
  await page.close();
}
}finally{await browser.close();}
console.log('Đã chụp React 360/390/412dp cùng fixture baseline.');
