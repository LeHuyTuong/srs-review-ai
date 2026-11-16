// Chỉ đọc source React; export initial stores về dự án Flutter để kiểm thử UI.
import { register } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
register('file:///D:/UI%20AI%20Review/tests/ts-loader.mjs', import.meta.url);
const saved = new Map();
globalThis.localStorage = {getItem:k=>saved.get(k)??null,setItem:(k,v)=>saved.set(k,v),removeItem:k=>saved.delete(k)};
globalThis.window = {dispatchEvent(){},addEventListener(){},removeEventListener(){}};
const {getManagementState}=await import('file:///D:/UI%20AI%20Review/src/data/managementStore.ts');
const {getReviewState}=await import('file:///D:/UI%20AI%20Review/src/data/reviewStore.ts');
const {currentUser,directoryStudents,groupHealthMeta,statusMeta,emailOf,documents,feedbackCategories,projects:sampleProjects}=await import('file:///D:/UI%20AI%20Review/src/data/mockData.ts');
const {documentSample}=await import('file:///D:/UI%20AI%20Review/src/data/documentSamples.ts');
const {NOW,fmtRelative,fmtDateTime,parseISO,fmtDate}=await import('file:///D:/UI%20AI%20Review/src/lib/time.ts');
const {reviewAI}=await import('file:///D:/UI%20AI%20Review/src/lib/reviewPresentation.ts');
const {activityText,contentText,shortCriterion}=await import('file:///D:/UI%20AI%20Review/src/components/ui/contentText.ts');
const {projectStateMeta}=await import('file:///D:/UI%20AI%20Review/src/data/projectStatuses.ts');
const {currentSemester}=await import('file:///D:/UI%20AI%20Review/src/lib/academic.ts');
const snapshot=getManagementState();
const presentation={reviews:Object.fromEntries(getReviewState().requests.map(r=>{
const ai=reviewAI(r,getReviewState().evaluations);const c=ai?.counts;const parts=c?[['errors','lỗi'],['warnings','cảnh báo'],['suggestions','gợi ý']].filter(([k])=>c[k]>0).map(([k,l])=>`${c[k]} ${l}`):[];
return [r.id,{aiLabel:c?`AI đề xuất: ${parts.length?parts.join(' · '):'Không phát hiện lỗi'}`:ai?.status==='loading'?'AI đang xử lý':ai?.status==='error'?'AI chưa hoàn tất · Cần thử lại':'AI chưa có kết quả',relativeTime:fmtRelative(r.requestedTs),note:contentText(r.note)}];
})),activities:Object.fromEntries(snapshot.groups.map(g=>[g.id,activityText(g.lastActivity)])),projectStateMeta};
const modalSource=await readFile('D:/UI AI Review/src/components/project/AddStudentsModal.tsx','utf8');
const sampleExpression=modalSource.match(/const sampleRows[\s\S]*?=> (\[[\s\S]*?\n\])/)[1];
const studentImportSample=Function('directoryStudents','emailOf','inClass',`return ${sampleExpression}`)(directoryStudents,emailOf,[]);
const titles=new Set([...getReviewState().requests.map(r=>r.documentTitle),...snapshot.offerings.flatMap(o=>o.labs.flatMap(l=>l.items.map(i=>i.title))),...snapshot.classes.flatMap(c=>(c.labOverride??[]).flatMap(l=>l.items.map(i=>i.title)))]);
const documentSamples=Object.fromEntries([...titles].map(title=>{const s=documentSample(title);return [title,{...s,checks:s.checks.map(c=>({...c,match:c.match.source}))}]}));
presentation.shortCriteria=Object.fromEntries([...snapshot.ruleSets.flatMap(r=>(r.criteria??[])),...getReviewState().evaluations.flatMap(e=>e.ruleSnapshot.criteria??[])].map(c=>[c.name,shortCriterion(c.name)]));
presentation.projectNextSteps=Object.fromEntries(sampleProjects.map(p=>[p.id,p.nextStep]));
const data={...snapshot,currentUser,directoryStudents,groupHealthMeta,statusMeta,studentImportSample,presentation,documentSeeds:documents,documentSamples,feedbackCategories,reviewState:getReviewState(),now:NOW,currentSemesterId:currentSemester(snapshot.semesters).id,
dashboard:JSON.parse(await readFile('D:/SRS-Review-AI-Mobile/assets/fixtures/dashboard.json','utf8'))};
await writeFile('D:/SRS-Review-AI-Mobile/assets/fixtures/academic.json',JSON.stringify(data,null,2));
console.log(JSON.stringify({courses:snapshot.courses.map(c=>[c.id,c.code]),offerings:snapshot.offerings.map(o=>o.id),classes:snapshot.classes.map(c=>c.id),rules:snapshot.ruleSets.length}));
