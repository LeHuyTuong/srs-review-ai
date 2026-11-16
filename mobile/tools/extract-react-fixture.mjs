// Chạy từ thư mục React; loader và modules chỉ được đọc, dữ liệu xuất về Flutter.
import { register } from 'node:module';
import { writeFile } from 'node:fs/promises';
register('file:///D:/UI%20AI%20Review/tests/ts-loader.mjs', import.meta.url);
const saved = new Map();
globalThis.localStorage = {
  getItem: key => saved.get(key) ?? null,
  setItem: (key, value) => saved.set(key, value),
  removeItem: key => saved.delete(key),
};
globalThis.window = { dispatchEvent() {}, addEventListener() {}, removeEventListener() {} };
const { getManagementState } = await import('file:///D:/UI%20AI%20Review/src/data/managementStore.ts');
const { getReviewState } = await import('file:///D:/UI%20AI%20Review/src/data/reviewStore.ts');
const { attentionItems, currentUser } = await import('file:///D:/UI%20AI%20Review/src/data/mockData.ts');
const { requestRecords } = await import('file:///D:/UI%20AI%20Review/src/data/filterRecords.ts');
const { reviewAI } = await import('file:///D:/UI%20AI%20Review/src/lib/reviewPresentation.ts');
const { fmtRelative, NOW } = await import('file:///D:/UI%20AI%20Review/src/lib/time.ts');
const mgmt = getManagementState();
const review = getReviewState();
const records = requestRecords(review.requests, mgmt.classes, mgmt.offerings, review.evaluations);
const data = {
  source: 'React initial stores, no saved user data; fixture for UI only',
  now: NOW,
  user: currentUser,
  semesters: mgmt.semesters,
  classes: mgmt.classes.map(c => ({id:c.id,semesterId:c.semesterId,courseId:c.courseId,state:c.state})),
  groups: mgmt.groups.map(g => ({id:g.id,classId:g.classId})),
  projects: mgmt.projects.map(p => ({id:p.id,groupId:p.groupId,state:p.state})),
  registrations: mgmt.registrations ?? [],
  requests: records.map(record => ({
    id:record.item.id, projectId:record.item.projectId,
    documentTitle:record.item.documentTitle,version:record.item.version,
    projectName:record.item.projectName,classCode:record.item.classCode,
    groupName:record.item.groupName,supervisorStatus:record.item.supervisorStatus,
    semesterId:record.semester, courseId:record.course, classId:record.class,
    ai:reviewAI(record.item,review.evaluations), relativeTime:fmtRelative(record.item.requestedTs),
  })),
  attention: attentionItems,
  academic: {courses:mgmt.courses.length, students:mgmt.students.length, ruleSets:mgmt.ruleSets.length},
};
await writeFile('D:/SRS-Review-AI-Mobile/assets/fixtures/dashboard.json', JSON.stringify(data,null,2));
console.log(JSON.stringify({semesters:data.semesters.length,requests:data.requests.length,first:data.requests[0]}));
