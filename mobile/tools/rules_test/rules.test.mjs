// Chạy: npm test (cần Java + firebase CLI; emulator Firestore, project demo, không đụng production).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-srs-rules',
    firestore: { rules: readFileSync('../../firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/sv1'), { role: 'student' });
    await setDoc(doc(db, 'users/sv2'), { role: 'Sinh viên' });
    await setDoc(doc(db, 'users/gv1'), { role: 'teacher' });
    await setDoc(doc(db, 'submissions/a'), {
      student_id: 'sv1', file_url: 'https://res.cloudinary.com/x/a.pdf', file_name: 'a.pdf',
    });
    await setDoc(doc(db, 'submissions/b'), {
      student_id: 'sv2', file_url: 'https://res.cloudinary.com/x/b.pdf', file_name: 'b.pdf',
    });
    await setDoc(doc(db, 'classes/c1'), { code: 'SE1' });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

test('sinh viên đọc được bài của mình, không đọc được bài người khác', async () => {
  await assertSucceeds(getDoc(doc(as('sv1'), 'submissions/a')));
  await assertFails(getDoc(doc(as('sv1'), 'submissions/b')));
});

test('sinh viên truy vấn phải lọc theo chính mình; truy vấn toàn bộ bị chặn', async () => {
  const db = as('sv1');
  const mine = await assertSucceeds(
    getDocs(query(collection(db, 'submissions'), where('student_id', '==', 'sv1'))),
  );
  if (mine.size !== 1) throw new Error(`mong 1 bài, nhận ${mine.size}`);
  await assertFails(getDocs(collection(db, 'submissions')));
});

test('role tiếng Việt "Sinh viên" cũng bị coi là sinh viên', async () => {
  await assertFails(getDoc(doc(as('sv2'), 'submissions/a')));
});

test('giảng viên (kể cả chưa có hồ sơ) đọc được mọi bài', async () => {
  await assertSucceeds(getDocs(collection(as('gv1'), 'submissions')));
  await assertSucceeds(getDocs(collection(as('gv-moi'), 'submissions')));
});

test('giảng viên chỉ ghi được trường trạng thái hợp lệ', async () => {
  const db = as('gv1');
  await assertSucceeds(updateDoc(doc(db, 'submissions/a'), {
    status: 'reviewed', decision: 'approved', decision_reason: 'Tốt', review_id: 'r1',
    decided_by: 'gv1',
  }));
  // Không được ghi quyết định đứng tên giảng viên khác.
  await assertFails(updateDoc(doc(db, 'submissions/a'), {
    status: 'reviewed', decision: 'approved', decided_by: 'gv-khac',
  }));
  await assertFails(updateDoc(doc(db, 'submissions/a'), { status: 'xyz' }));
  await assertFails(updateDoc(doc(db, 'submissions/a'), { status: 'reviewed', decision: 'hack' }));
  await assertFails(updateDoc(doc(db, 'submissions/a'), { status: 'queued', file_url: 'https://evil' }));
});

test('sinh viên không tự đổi trạng thái bài của mình', async () => {
  await assertFails(updateDoc(doc(as('sv1'), 'submissions/a'), { status: 'reviewed', decision: 'approved' }));
});

test('sinh viên đọc được lớp nhưng không ghi dữ liệu học vụ', async () => {
  await assertSucceeds(getDoc(doc(as('sv1'), 'classes/c1')));
  await assertFails(setDoc(doc(as('sv1'), 'classes/c1'), { code: 'HACK' }));
  await assertSucceeds(setDoc(doc(as('gv1'), 'classes/c1'), { code: 'SE2' }));
});

test('sinh viên vẫn tạo được bài nộp của chính mình', async () => {
  await assertSucceeds(setDoc(doc(as('sv1'), 'submissions/new'), {
    student_id: 'sv1', file_url: 'https://res.cloudinary.com/x/n.pdf', file_name: 'n.pdf',
  }));
  await assertFails(setDoc(doc(as('sv1'), 'submissions/new2'), {
    student_id: 'sv2', file_url: 'https://res.cloudinary.com/x/n.pdf', file_name: 'n.pdf',
  }));
});

const statusNote = (targetId) => ({
  title: 'Bài nộp đã có kết quả', body: 'a.pdf', type: 'submission_status',
  targetId, source: 'teacher', read: false,
});

test('giảng viên gửi thông báo trạng thái chỉ cho đúng chủ bài nộp', async () => {
  const db = as('gv1');
  await assertSucceeds(setDoc(doc(db, 'users/sv1/inbox/n1'), statusNote('a')));
  // Bài b là của sv2 → không được gửi vào hộp thư sv1.
  await assertFails(setDoc(doc(db, 'users/sv1/inbox/n2'), statusNote('b')));
});

test('sinh viên không gửi thông báo vào hộp thư người khác', async () => {
  await assertFails(setDoc(doc(as('sv2'), 'users/sv1/inbox/n3'), statusNote('a')));
});

test('sinh viên đọc hộp thư của mình', async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'users/sv1/inbox/x'), statusNote('a')));
  await assertSucceeds(getDoc(doc(as('sv1'), 'users/sv1/inbox/x')));
  await assertFails(getDoc(doc(as('sv2'), 'users/sv1/inbox/x')));
});
