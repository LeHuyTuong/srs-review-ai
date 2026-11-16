#!/usr/bin/env node
// usecase-overview.mjs — Overall Use Case Diagram (tầng 0) cho kickoff-uml, theo đúng dạng SRS capstone FPT:
// MỘT boundary, MỌI use case chi tiết, cụm theo actor, đủ <<include>> / <<extend>> / generalization UC
// và generalization actor về actor cha (Registered User) đặt dưới đáy.
//
// Vì sao có file này: engine `use-case-diagram` (tầng 1) lint `[path]` gắt và chỉ chịu ~12 UC/một hình, nên với hệ thật
// (20–40 UC) bản tổng bị "tách" rồi biến mất — trong khi SRS Report 3 của FPT (mục 2.2.1) chấm đúng cái hình tổng ấy.
// Tầng 0 không tìm đường tránh đè: bố cục cụm cố định (actor ngoài rìa, UC của actor nằm sát actor, UC con/part/extending
// xếp cột kế bên UC gốc) nên đọc được dù nhiều UC; đường dài chéo qua hình là chấp nhận được (mẫu FPT cũng vậy).
//
// Lệnh:
//   node usecase-overview.mjs merge <dir usecase/> [--out overview.model.json] [--primary A,B]   gộp mọi file tầng 1 thành model tầng 0 (+ ghi side chính/phụ)
//   node usecase-overview.mjs build <overview.model.json> [--out f.drawio] [--svg] [--png] [--primary A,B] [--parent bottom|tree]
//                                  [--detail full|parents] [--actor-tree inline|separate] [--sides balanced|affinity|left]
//   node usecase-overview.mjs check <overview.model.json | overview.drawio>
//
// Model = schema của use-case-diagram, không thêm khoá bắt buộc:
//   { "tier": "overview", "subject": {"name"}, "actors": [{id, name, external?}], "usecases": [{id, name, evidence?}],
//     "associations": [{actor, usecase}], "includes": [{base, part}], "extends": [{extending, base, point?, condition?}],
//     "generalizations": [{child, parent}], "actorParents": {child: parent} }
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const HERE = path.dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------- hằng layout (px, toạ độ draw.io)
const ACTOR_W = 30, ACTOR_H = 60, ACTOR_LABEL_H = 22;
const UC_W = 150, UC_H = 40, ROW = 62, COL = 190;      // ellipse; bước dòng; bước cột (gốc → con)
const CLUSTER_GAP = 36;                                 // giữa hai cụm actor cùng phía
const PAD = 30, TITLE_H = 34;                           // lề trong boundary; dải tên hệ thống
const MID_GAP = 140;                                    // khoảng trống giữa khối trái và khối phải
const ACTOR_GAP = 120;                                  // actor → boundary
const BOTTOM_ROW_PITCH = 172, BOTTOM_GAP = 30, PARENT_GAP = 90;
const GEN_BUS_STEP = 14;
const MARGIN = 30;
const NOTE_CH = 5.7, NOTE_LH = 13;                      // ghi chú (UML comment): bề rộng ký tự, chiều cao dòng ở cỡ chữ 10
const noteLines = (parts, maxChars) => parts.flatMap((t) => { const out = []; let cur = ''; for (const w of String(t).split(/\s+/)) { if (cur && (cur + ' ' + w).length > maxChars) { out.push(cur); cur = w; } else cur = cur ? cur + ' ' + w : w; } if (cur) out.push(cur); return out; });
const noteSize = (lines) => ({ w: Math.round(Math.min(240, Math.max(120, Math.max(...lines.map((l) => l.length)) * NOTE_CH + 24))), h: lines.length * NOTE_LH + 12 });
/** Chữ trên ghi chú/ngăn «extend» theo ngôn ngữ hình — cùng chữ với engine use-case-diagram (lang-uc.mjs LIT) để hình tổng và hình phân hệ khớp nhau. */
const EXT_LIT = { en: { cond: 'Condition:', point: 'extension point:', points: 'extension points' }, vi: { cond: 'Điều kiện:', point: 'điểm mở rộng:', points: 'điểm mở rộng' } };
const extLit = (model) => EXT_LIT[/^vi/i.test(String(model?.lang || '')) ? 'vi' : 'en'];
const EXT_HEAD_RE = /^(Condition:|extension point:|Điều kiện:|điểm mở rộng:)(.*)$/;
const extNoteLines = (x, lt = EXT_LIT.en) => noteLines([x.condition ? `${lt.cond} {${x.condition}}` : null, x.point ? `${lt.point} ${x.point}` : null].filter(Boolean), 36);
const labelW = (name) => Math.max(ACTOR_W, String(name || '').length * 5.8 + 4); // bề rộng nhãn actor ở cỡ 11 (Helvetica ≈ 5.8px/ký tự)
/** Đoạn p→q có xuyên vào trong ellipse của CHÍNH hình đầu mút không (vật cản đầu mút bị skip nên phải kiểm riêng). */
const throughOwn = (p, q, box) => {
  if (!box) return false;
  const rx = box.w / 2 - 2, ry = box.h / 2 - 2, cx = box.x + box.w / 2, cy = box.y + box.h / 2;
  for (let i = 1; i < 20; i++) { const t = 0.03 + (0.94 * i) / 20, x = p[0] + (q[0] - p[0]) * t, y = p[1] + (q[1] - p[1]) * t; if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1) return true; }
  return false;
};

// ---------------------------------------------------------------- tiện ích
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const norm = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
const uniq = (a) => [...new Set(a)];
const EXTERNAL_RE = /(gateway|service|api|provider|bank|server|mail|sms|payment|third[- ]?party|external)\b/i;

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    throw Object.assign(new Error(`model JSON hỏng: ${file}: ${e.message}`), { code: 2 });
  }
}

function parseArgs(argv) {
  const out = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      const v = argv[i + 1];
      if (v !== undefined && !v.startsWith('--')) { out.flags[k] = v; i++; } else out.flags[k] = true;
    } else out._.push(a);
  }
  return out;
}

/** Tách tên UC thành ≤ 2 dòng cân nhau (như engine viết `Manage Session<br>Journals`). */
export function wrapName(name, max = 18) {
  const s = String(name || '').trim();
  if (s.length <= max || !s.includes(' ')) return [s];
  const words = s.split(/\s+/);
  let best = null;
  for (let i = 1; i < words.length; i++) {
    const a = words.slice(0, i).join(' '), b = words.slice(i).join(' ');
    const score = Math.abs(a.length - b.length);
    if (!best || score < best.score) best = { score, lines: [a, b] };
  }
  return best.lines;
}

export function isOverviewModel(file, model) {
  if (model && model.tier === 'overview') return true;
  return /^overview([.-]|$)/i.test(path.basename(file).replace(/\.model\.json$/, '').replace(/\.json$/, ''));
}

const isExternal = (a) => !!(a.external || a.kind === 'external' || EXTERNAL_RE.test(a.name || ''));

// ---------------------------------------------------------------- merge: gộp tầng 1 → tầng 0
/**
 * Gộp mọi `<module>.model.json` cùng subject trong thư mục (bỏ role-*) + overview cũ (nếu có) thành một model tầng 0.
 * UC khớp theo TÊN (chuẩn hoá) chứ không theo id, vì các module hay đánh số riêng (UC19 ở finance ≠ UC19 ở system);
 * id lấy từ file đầu tiên gặp; đụng id khác tên → cấp id mới và ghi chú. Quan hệ (association/include/extend/generalization)
 * được ánh xạ lại theo từng file nguồn.
 */
export function mergeModels(dir, overviewFile) {
  const notes = [];
  const files = fs.readdirSync(dir).filter((n) => n.endsWith('.json') && !n.startsWith('.') && !/^role-/i.test(n)).sort();
  const ovName = overviewFile ? path.basename(overviewFile) : null;
  // overview cũ (đúng file đích) đọc sau cùng để tên/ID của module thắng; các biến thể khác (overview-v2, overview-parents…) KHÔNG gộp vào
  const ordered = [...files.filter((n) => n !== ovName && !/^overview/i.test(n)), ...files.filter((n) => n === ovName)];
  const out = { tier: 'overview', subject: null, actors: [], usecases: [], associations: [], includes: [], extends: [], generalizations: [], actorParents: {}, _merged_from: [] };
  const ucByKey = new Map(); // norm(name) → uc
  const usedIds = new Set();
  const actorById = new Map();
  const seenAssoc = new Set(), seenInc = new Set(), seenExt = new Set(), seenGen = new Set();
  let subjectKey = null;
  for (const n of ordered) {
    let m;
    try { m = readJson(path.join(dir, n)); } catch (e) { notes.push(`bỏ ${n}: ${e.message}`); continue; }
    if (!Array.isArray(m.usecases)) continue;
    const sk = norm(m.subject?.name);
    if (!subjectKey && sk) { subjectKey = sk; out.subject = m.subject; }
    else if (sk && subjectKey && sk !== subjectKey) { notes.push(`bỏ ${n}: subject "${m.subject?.name}" khác "${out.subject?.name}"`); continue; }
    out._merged_from.push(n);
    const idMap = new Map(); // id trong file → id tầng 0
    for (const u of m.usecases) {
      const key = norm(u.name);
      let hit = ucByKey.get(key);
      if (!hit) {
        let id = u.id;
        if (usedIds.has(id)) {
          const other = out.usecases.find((x) => x.id === id);
          const maxN = Math.max(0, ...[...usedIds].map((x) => parseInt(String(x).replace(/\D/g, ''), 10) || 0));
          id = `UC${String(maxN + 1).padStart(2, '0')}`;
          notes.push(`${n}: ${u.id} "${u.name}" trùng id với "${other.name}" (file khác) → đổi thành ${id}`);
        }
        hit = { id, name: u.name, ...(u.evidence ? { evidence: u.evidence } : {}) };
        ucByKey.set(key, hit); usedIds.add(id); out.usecases.push(hit);
      } else if (u.evidence && !hit.evidence) hit.evidence = u.evidence;
      idMap.set(u.id, hit.id);
    }
    for (const a of m.actors || []) {
      if (!actorById.has(a.id)) { actorById.set(a.id, { id: a.id, name: a.name, ...(a.external ? { external: true } : {}), ...(a.side === 'left' || a.side === 'right' ? { side: a.side } : {}) }); out.actors.push(actorById.get(a.id)); }
      else if (!actorById.get(a.id).side && (a.side === 'left' || a.side === 'right')) actorById.get(a.id).side = a.side;
    }
    const map = (id) => idMap.get(id);
    for (const x of m.associations || []) {
      const u = map(x.usecase);
      if (!u || !actorById.has(x.actor)) continue;
      const k = `${x.actor}|${u}`;
      if (!seenAssoc.has(k)) { seenAssoc.add(k); out.associations.push({ actor: x.actor, usecase: u }); }
    }
    for (const x of m.includes || []) {
      const b = map(x.base), p = map(x.part);
      if (b && p && !seenInc.has(`${b}|${p}`)) { seenInc.add(`${b}|${p}`); out.includes.push({ base: b, part: p }); }
    }
    for (const x of m.extends || []) {
      const e = map(x.extending), b = map(x.base);
      // giữ extension point + điều kiện + evidence/standalone của model tầng 1 (mất chúng thì note «extend» biến mất và [uml extend-cond]/[uml extend-evidence] báo oan);
      // extension point viết kiểu engine (extensionPoint, hoặc extensionPoints của base) cũng nhận
      const pt = x.point || x.extensionPoint || [].concat((m.usecases.find((u) => u.id === x.base) || {}).extensionPoints || []).join(', ');
      if (e && b && !seenExt.has(`${e}|${b}`)) { seenExt.add(`${e}|${b}`); out.extends.push({ extending: e, base: b, ...(pt ? { point: pt } : {}), ...(x.condition ? { condition: x.condition } : {}), ...(x.evidence ? { evidence: x.evidence } : {}), ...(x.standalone ? { standalone: x.standalone } : {}) }); }
    }
    if (m.extendDetails !== undefined && out.extendDetails === undefined) out.extendDetails = m.extendDetails;
    for (const x of m.generalizations || []) {
      const c = map(x.child), p = map(x.parent);
      if (c && p && !seenGen.has(`${c}|${p}`)) { seenGen.add(`${c}|${p}`); out.generalizations.push({ child: c, parent: p }); }
    }
    for (const [c, p] of Object.entries(m.actorParents || {})) if (actorById.has(c) && actorById.has(p)) out.actorParents[c] = p;
  }
  // actor cha đứng đầu danh sách (dễ đọc model), còn lại giữ thứ tự gặp
  const parents = new Set(Object.values(out.actorParents));
  out.actors.sort((a, b) => (parents.has(b.id) ? 1 : 0) - (parents.has(a.id) ? 1 : 0));
  out.usecases.sort((a, b) => a.id.localeCompare(b.id, undefined, { numeric: true }));
  return { model: out, notes };
}

// ---------------------------------------------------------------- «extend»: vẽ tới đâu
/**
 * Mức vẽ chi tiết «extend» — khoá `extendDetails` của model: `full` (mặc định) ghi chú điều kiện + ngăn extension points;
 * `condition` chỉ ghi chú điều kiện; `none` chỉ mũi tên «extend» (nhiều đề FPT không đòi). Chỉ đổi HÌNH và lint — condition/point/evidence
 * vẫn nằm trong model cho đặc tả use case.
 */
export const EXTEND_DETAILS = Object.freeze(['full', 'condition', 'none']);
/** `model.extendDetails` → `full` | `condition` | `none`; `true`/`false` = full/none; không khai hoặc giá trị lạ = full (lint báo `[ov extend-details]`). */
export function extendDetailsOf(model) {
  const v = model?.extendDetails;
  if (v === false) return 'none';
  const s = String(v ?? '').trim().toLowerCase();
  return EXTEND_DETAILS.includes(s) ? s : 'full';
}

// ---------------------------------------------------------------- phân tích quan hệ
export function analyze(model) {
  const actors = model.actors || [], ucs = model.usecases || [];
  const aid = new Set(actors.map((a) => a.id)), uid = new Set(ucs.map((u) => u.id));
  const assoc = (model.associations || []).filter((x) => aid.has(x.actor) && uid.has(x.usecase));
  const includes = (model.includes || []).filter((x) => uid.has(x.base) && uid.has(x.part));
  // extension point: `point` (kickoff-uml) hoặc `extensionPoint` / `usecases[].extensionPoints` của base (engine use-case-diagram) — một model, hai công cụ vẽ
  // như nhau. Mức extendDetails bỏ phần không vẽ khỏi bản phân tích (layout, ghi chú, lint đều đọc từ đây); model gốc không đổi.
  const lvl = extendDetailsOf(model);
  const ucById = new Map(ucs.map((u) => [u.id, u]));
  const extend = (model.extends || []).filter((x) => uid.has(x.extending) && uid.has(x.base)).map((x) => {
    const { point, extensionPoint, condition, ...rest } = x;
    const pt = lvl === 'full' ? String(point || extensionPoint || [].concat((ucById.get(x.base) || {}).extensionPoints || []).join(', ')).trim() : '';
    return { ...rest, ...(pt ? { point: pt } : {}), ...(lvl !== 'none' && condition ? { condition } : {}) };
  });
  const gens = (model.generalizations || []).filter((x) => uid.has(x.child) && uid.has(x.parent));
  const parents = Object.fromEntries(Object.entries(model.actorParents || {}).filter(([c, p]) => aid.has(c) && aid.has(p)));
  const parentActors = new Set(Object.values(parents));
  const directActors = (u) => uniq(assoc.filter((x) => x.usecase === u).map((x) => x.actor));
  // "host" của UC không có actor: cha (generalization) > base (include part) > base (extending)
  const hostOf = (u) => {
    const g = gens.find((x) => x.child === u); if (g) return { host: g.parent, via: 'gen' };
    const i = includes.find((x) => x.part === u); if (i) return { host: i.base, via: 'include' };
    const e = extend.find((x) => x.extending === u); if (e) return { host: e.base, via: 'extend' };
    return null;
  };
  return { actors, ucs, assoc, includes, extend, gens, parents, parentActors, directActors, hostOf };
}

// ---------------------------------------------------------------- định tuyến tránh vật cản (đường không được xuyên qua ellipse/actor)
const CELL = 8;

/** Đoạn thẳng có cắt ellipse/actor nào không (bỏ qua hai hình đầu mút). Ellipse kiểm đúng phương trình, nới 4px. */
export function segmentHits(a, b, obstacles, skip = new Set()) {
  const n = Math.max(2, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / 3));
  for (const o of obstacles) {
    if (skip.has(o.id)) continue;
    for (let i = 1; i < n; i++) {
      const t = i / n, x = a[0] + (b[0] - a[0]) * t, y = a[1] + (b[1] - a[1]) * t;
      if (o.ellipse) {
        const rx = o.w / 2 + 4, ry = o.h / 2 + 4, cx = o.x + o.w / 2, cy = o.y + o.h / 2;
        if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1) return o;
      } else if (x > o.x - 4 && x < o.x + o.w + 4 && y > o.y - 4 && y < o.y + o.h + 4) return o;
    }
  }
  return null;
}

/** A* trực giao trên lưới CELL px: chi phí = số ô + phạt rẽ; trả về danh sách điểm gấp khúc (toạ độ tuyệt đối) hoặc null. */
/** Hai đoạn thẳng có cắt nhau không (bỏ qua chạm đầu mút trong 6px). */
export function segIntersect(p1, p2, q1, q2) {
  const d = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  const near = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]) < 6;
  if (near(p1, q1) || near(p1, q2) || near(p2, q1) || near(p2, q2)) return false;
  const d1 = d(q1, q2, p1), d2 = d(q1, q2, p2), d3 = d(p1, p2, q1), d4 = d(p1, p2, q2);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

export function routeOrtho(from, to, obstacles, bounds, skip = new Set(), lines = []) {
  const x0 = Math.floor(bounds.x0 / CELL), y0 = Math.floor(bounds.y0 / CELL);
  const W = Math.ceil((bounds.x1 - bounds.x0) / CELL) + 1, H = Math.ceil((bounds.y1 - bounds.y0) / CELL) + 1;
  if (W * H > 400000) return null;
  const blocked = new Uint8Array(W * H);
  for (const o of obstacles) {
    if (skip.has(o.id)) continue;
    const pad = o.ellipse ? 6 : 10;
    const cx0 = Math.max(0, Math.floor((o.x - pad) / CELL) - x0), cx1 = Math.min(W - 1, Math.ceil((o.x + o.w + pad) / CELL) - x0);
    const cy0 = Math.max(0, Math.floor((o.y - pad) / CELL) - y0), cy1 = Math.min(H - 1, Math.ceil((o.y + o.h + pad) / CELL) - y0);
    for (let cy = cy0; cy <= cy1; cy++) for (let cx = cx0; cx <= cx1; cx++) blocked[cy * W + cx] = 1;
  }
  const toCell = (p) => [Math.round(p[0] / CELL) - x0, Math.round(p[1] / CELL) - y0];
  // đường association đã vẽ: chặn ô dọc đoạn (±1 ô) để đường UC–UC không chém qua quạt đường của actor
  for (const ln of lines) {
    const a = toCell(ln[0]), b = toCell(ln[1]);
    const n = Math.max(1, Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1])));
    for (let i = 0; i <= n; i++) {
      const cx = Math.round(a[0] + (b[0] - a[0]) * i / n), cy = Math.round(a[1] + (b[1] - a[1]) * i / n);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const xx = cx + dx, yy = cy + dy; if (xx >= 0 && yy >= 0 && xx < W && yy < H) blocked[yy * W + xx] = 1; }
    }
  }
  const S = toCell(from), T = toCell(to);
  const inb = (c) => c[0] >= 0 && c[0] < W && c[1] >= 0 && c[1] < H;
  if (!inb(S) || !inb(T)) return null;
  blocked[S[1] * W + S[0]] = 0; blocked[T[1] * W + T[0]] = 0;
  const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  const BEND = 8;
  // state = cell*4 + dir
  const g = new Float64Array(W * H * 4).fill(Infinity);
  const prev = new Int32Array(W * H * 4).fill(-1);
  const heap = []; // [f, state]
  const push = (f, st) => { heap.push([f, st]); let i = heap.length - 1; while (i > 0) { const p = (i - 1) >> 1; if (heap[p][0] <= heap[i][0]) break; [heap[p], heap[i]] = [heap[i], heap[p]]; i = p; } };
  const pop = () => { const top = heap[0]; const last = heap.pop(); if (heap.length) { heap[0] = last; let i = 0; for (;;) { const l = 2 * i + 1, r = l + 1; let m = i; if (l < heap.length && heap[l][0] < heap[m][0]) m = l; if (r < heap.length && heap[r][0] < heap[m][0]) m = r; if (m === i) break; [heap[m], heap[i]] = [heap[i], heap[m]]; i = m; } } return top; };
  const h = (cx, cy) => Math.abs(cx - T[0]) + Math.abs(cy - T[1]);
  for (let d = 0; d < 4; d++) { const st = (S[1] * W + S[0]) * 4 + d; g[st] = 0; push(h(S[0], S[1]), st); }
  let found = -1, expanded = 0;
  while (heap.length) {
    const [f, st] = pop();
    const cell = st >> 2, d = st & 3, cx = cell % W, cy = (cell / W) | 0;
    if (f > g[st] + h(cx, cy) + 1e-9) continue;
    if (cx === T[0] && cy === T[1]) { found = st; break; }
    if (++expanded > 600000) break;
    for (let nd = 0; nd < 4; nd++) {
      const nx = cx + DIRS[nd][0], ny = cy + DIRS[nd][1];
      if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
      const ncell = ny * W + nx;
      if (blocked[ncell]) continue;
      const cost = g[st] + 1 + (nd === d ? 0 : BEND);
      const nst = ncell * 4 + nd;
      if (cost < g[nst]) { g[nst] = cost; prev[nst] = st; push(cost + h(nx, ny), nst); }
    }
  }
  if (found < 0) return null;
  const cells = [];
  for (let st = found; st >= 0; st = prev[st]) { const cell = st >> 2; cells.push([cell % W, (cell / W) | 0]); if (g[st] === 0) break; }
  cells.reverse();
  // giữ điểm gấp khúc; nối thẳng với cổng đầu/cuối
  const pts = [];
  for (let i = 1; i < cells.length - 1; i++) {
    const a = cells[i - 1], b = cells[i], c = cells[i + 1];
    if ((b[0] - a[0]) !== (c[0] - b[0]) || (b[1] - a[1]) !== (c[1] - b[1])) pts.push([(b[0] + x0) * CELL, (b[1] + y0) * CELL]);
  }
  if (pts.length) {
    // đoạn đầu/cuối đi thẳng từ cổng: ép toạ độ gấp khúc đầu/cuối trùng trục với cổng
    const first = pts[0]; if (Math.abs(first[0] - from[0]) < CELL) first[0] = from[0]; else first[1] = from[1];
    const last = pts[pts.length - 1]; if (Math.abs(last[0] - to[0]) < CELL) last[0] = to[0]; else last[1] = to[1];
  }
  return pts;
}

// ---------------------------------------------------------------- layout (cụm theo actor, theo 7 luật rút từ mẫu SRS FPT / sách UML)
// 1. Hai bên = chính/phụ: trái là actor hệ thống phục vụ (`side: left` trong model hoặc --primary), phải là actor vận hành + hệ ngoài.
// 2. Độ sâu = include: UC actor bấm sát actor; UC được include/extend/con nằm sâu hơn một cột; UC được nhiều base dùng ở điểm hội tụ.
// 3. extend = ngoại lệ cạnh base.  4. is-a UC: actor nối cha, con cạnh cha.  5. is-a actor: cha giữ phần chung (đáy hoặc cây).
// 6. UC dùng chung bởi actor hai phía đặt cột giữa.  7. Đường thẳng, không có gì chắn; chắn thì mới đi vòng.
/** Bề rộng chừa cho nhãn «extend» trên đường (ô nền 60px trong SVG + lề 2px mỗi bên). */
const EXT_LABEL_W = 64;
/** Khoảng cách mong muốn (px, đo thẳng) giữa hai đầu mũi tên generalization cùng vào một UC cha. */
const GEN_HEAD_GAP = 22;
/**
 * Khoảng cách tối thiểu (px, đo thẳng) giữa hai đầu mũi tên kề nhau, như `GEN_HEAD_MIN` của use-case-diagram (trunks.mjs);
 * `[layout arrowhead]` của use-case-diagram báo ERROR dưới 15. Quanh đầu nhọn của ellipse dẹt dây cung ngắn hơn cung nhiều,
 * nên rải theo khoảng cách thẳng chứ không theo cung.
 */
const GEN_HEAD_MIN = 19;

/**
 * Generalization UC cùng một cha: MỖI con một đầu mũi tên riêng trên viền ellipse cha. Trước đây cổng gần nhất của cha là một điểm
 * (giữa cạnh) nên N tam giác chồng lên đúng một chỗ — trông như một mũi tên bị N đường đâm vào, đọc sai (vmc-core 26/10/2026:
 * "Xem nội dung công khai" ← 8 con). Rải các điểm vào dọc nửa ellipse phía các con (±90° quanh hướng của phía đó), hai điểm kề nhau
 * cách nhau {@link GEN_HEAD_GAP} px đo thẳng (không đủ chỗ thì giảm dần, không dưới {@link GEN_HEAD_MIN} nếu nửa ellipse đủ dài),
 * theo thứ tự góc của con (con trên vào điểm trên) để các đường không chéo nhau. Chỉ đổi đoạn cuối; điểm ra ở con và các điểm gãy giữ nguyên.
 * @param {object[]} edges cạnh đã vẽ (sửa tại chỗ những cạnh `ucgen`)
 * @param {Map<string,{x:number,y:number,w:number,h:number}>} ucBox hộp các UC
 */
export function spreadGenHeads(edges, ucBox) {
  const groups = new Map();
  for (const e of edges) {
    if (e.kind !== 'ucgen' || !e.entry) continue;
    const [fx, fy] = e.entry;
    const side = fx === 0 ? 'left' : fx === 1 ? 'right' : fy === 0 ? 'top' : fy === 1 ? 'bottom' : null;
    if (!side) continue;
    const k = `${e.target}|${side}`;
    if (!groups.has(k)) groups.set(k, { target: e.target.replace(/^uc_/, ''), side, edges: [] });
    groups.get(k).edges.push(e);
  }
  const mid = { right: 0, bottom: Math.PI / 2, left: Math.PI, top: -Math.PI / 2 };
  for (const g of groups.values()) {
    if (g.edges.length < 2) continue;
    const T = ucBox.get(g.target);
    if (!T) continue;
    const cx = T.x + T.w / 2, cy = T.y + T.h / 2, a = T.w / 2, b = T.h / 2;
    const at = (t) => [cx + a * Math.cos(t), cy + b * Math.sin(t)];
    // bảng cung (độ dài theo viền) của nửa ellipse phía các con, từ mid−90° tới mid+90°
    const t0 = mid[g.side] - Math.PI / 2, t1 = mid[g.side] + Math.PI / 2, N = 720;
    const ts = [], arc = [0];
    for (let i = 0; i <= N; i++) ts.push(t0 + ((t1 - t0) * i) / N);
    for (let i = 1; i <= N; i++) { const p = at(ts[i - 1]), q = at(ts[i]); arc.push(arc[i - 1] + Math.hypot(q[0] - p[0], q[1] - p[1])); }
    const total = arc[N], center = arc[N / 2];
    const n = g.edges.length;
    const tAt = (s) => { let i = 1; while (i < N && arc[i] < s) i++; const f = (s - arc[i - 1]) / Math.max(1e-9, arc[i] - arc[i - 1]); return ts[i - 1] + (ts[i] - ts[i - 1]) * f; };
    const pAt = (s) => at(tAt(Math.max(0, Math.min(total, s))));
    // đi dọc viền từ `start`, mỗi bước tới điểm cách điểm trước ≥ d (đo thẳng); null nếu vượt hết nửa ellipse
    const walk = (start, d) => {
      const out = [start];
      for (let k = 1; k < n; k++) {
        const p = pAt(out[k - 1]);
        let s = out[k - 1];
        while (s <= total && Math.hypot(pAt(s)[0] - p[0], pAt(s)[1] - p[1]) < d) s += 0.25;
        if (s > total) return null;
        out.push(s);
      }
      return out;
    };
    // giữa cụm đặt ở giữa nửa ellipse (hướng của phía); lặp vài lần vì độ dài cụm đổi theo chỗ đặt
    const centred = (d) => {
      let pos = walk(0, d);
      if (!pos) return null;
      for (let it = 0; it < 4; it++) {
        const span = pos[n - 1] - pos[0];
        const start = Math.max(0, Math.min(total - span, center - span / 2));
        const next = walk(start, d);
        if (!next) break;
        pos = next;
      }
      return pos;
    };
    let pos = null;
    for (let d = GEN_HEAD_GAP; d >= 12 && !pos; d -= 1) pos = centred(d);
    if (!pos) { const gap = total / (n + 1); pos = Array.from({ length: n }, (_, i) => center + (i - (n - 1) / 2) * gap); }
    // thứ tự theo góc nhìn từ tâm cha tới điểm cuối trước đoạn cuối (điểm gãy cuối, không có thì điểm ra ở con)
    const angleOf = (e) => { const p = e.points && e.points.length ? e.points[e.points.length - 1] : e.from; let t = Math.atan2(p[1] - cy, p[0] - cx) - mid[g.side]; while (t > Math.PI) t -= 2 * Math.PI; while (t < -Math.PI) t += 2 * Math.PI; return t; };
    const sorted = [...g.edges].sort((x, y) => angleOf(x) - angleOf(y));
    sorted.forEach((e, i) => {
      const p = pAt(pos[i]);
      e.to = p;
      e.entry = [+((p[0] - T.x) / T.w).toFixed(4), +((p[1] - T.y) / T.h).toFixed(4)];
    });
  }
}

export function layout(model, opts = {}) {
  const mode = opts.sides || 'balanced';       // balanced | affinity | left (chỉ dùng khi model không ghi side)
  const parentMode = opts.parent || 'bottom';  // bottom (mẫu FPT) | tree (mẫu Library: cha trên, con dưới cùng phía)
  const drawGen = opts.actorTree !== 'separate'; // separate: giữ actor cha + UC chung ở đáy nhưng KHÔNG vẽ dây kế thừa (cây actor xuất hình riêng)
  const primary = opts.primary && opts.primary.length ? new Set(opts.primary) : null;
  const footNotes = [...(opts.footNotes || []), ...((model.notes || []).map((n) => (typeof n === 'string' ? n : n.text)).filter(Boolean))];
  const A = analyze(model);
  const LT = extLit(model);
  const { actors, ucs, assoc, parents, parentActors, directActors } = A;
  const count = (id) => assoc.filter((x) => x.actor === id).length;
  const ucsOf = (id) => new Set(assoc.filter((x) => x.actor === id).map((x) => x.usecase));
  const shared = (a, b) => { const sa = ucsOf(a), sb = ucsOf(b); let n = 0; for (const u of sa) if (sb.has(u)) n++; return n; };
  const humans = actors.filter((a) => !parentActors.has(a.id) && !isExternal(a));
  const externals = actors.filter((a) => !parentActors.has(a.id) && isExternal(a));
  const parentList = actors.filter((a) => parentActors.has(a.id));
  const childrenActors = (pid) => Object.entries(parents).filter(([, p]) => p === pid).map(([c]) => c);

  // ---- luật 1: phía của actor
  const explicitSide = (a) => (primary ? (primary.has(a.id) ? 'left' : 'right') : (a.side === 'left' || a.side === 'right' ? a.side : null));
  const side = new Map();
  const load = { left: 0, right: 0 };
  for (const a of [...humans].sort((x, y) => count(y.id) - count(x.id))) {
    let s = explicitSide(a);
    if (!s) {
      const sL = [...side].filter(([, v]) => v === 'left').reduce((n, [id]) => n + shared(a.id, id), 0);
      const sR = [...side].filter(([, v]) => v === 'right').reduce((n, [id]) => n + shared(a.id, id), 0);
      if (mode === 'left') s = 'left';
      else if (mode === 'affinity') s = sL > sR ? 'left' : sR > sL ? 'right' : load.left <= load.right ? 'left' : 'right';
      else s = load.left <= load.right ? 'left' : 'right';
    }
    side.set(a.id, s); load[s] += Math.max(1, count(a.id));
  }
  for (const a of externals) side.set(a.id, explicitSide(a) || 'right');
  // cha kiểu cây: đứng phía có nhiều con hơn (hoà → trái), là một actor thường trên phía đó
  const treeParents = new Set();
  // actor cha có `side` khai trong model (hoặc trong --primary) và có UC riêng là actor THẬT (Khách, Người dùng…), không phải
  // "Registered User" chỉ giữ Login/Logout: đứng ở phía đã khai như actor thường; chỉ cha không khai phía mới xuống đáy (mẫu FPT)
  if (parentMode === 'bottom') {
    for (const p of parentList) {
      // chỉ phía KHAI cho chính actor cha (model `side` hoặc có tên trong --primary); --primary không đẩy cha sang phải mặc định
      const s0 = primary && primary.has(p.id) ? 'left' : (p.side === 'left' || p.side === 'right' ? p.side : null);
      if (s0 && count(p.id) > 0) { side.set(p.id, s0); treeParents.add(p.id); }
    }
  }
  if (parentMode === 'tree') {
    for (const p of parentList) {
      const kids = childrenActors(p.id);
      const l = kids.filter((k) => side.get(k) === 'left').length;
      side.set(p.id, explicitSide(p) || (l >= kids.length - l ? 'left' : 'right'));
      treeParents.add(p.id);
    }
  }
  // con is-a không có UC riêng (mẫu Library: Student/Staff) không chiếm chỗ trong cột cụm — xếp ngay dưới cha (kiểu cây) hoặc bỏ qua chỗ (kiểu đáy)
  const treeKids = new Set(parentMode === 'tree' ? Object.keys(parents).filter((c) => !assoc.some((x) => x.actor === c)) : []);
  const sideActors = (sn) => [...parentList.filter((p) => treeParents.has(p.id)), ...humans, ...externals].filter((a) => side.get(a.id) === sn && !treeKids.has(a.id));
  // thứ tự dọc: actor nhiều UC nhất trên cùng, kế tiếp là actor dùng chung nhiều nhất với actor vừa đặt; cha kiểu cây lên đầu
  const orderSide = (list) => {
    const rest = [...list].sort((x, y) => (treeParents.has(y.id) ? 1 : 0) - (treeParents.has(x.id) ? 1 : 0) || count(y.id) - count(x.id)), out = [];
    while (rest.length) {
      const last = out[out.length - 1];
      let pick = 0;
      if (last && !treeParents.has(rest[0].id)) { let best = -1; rest.forEach((a, i) => { const sc = shared(last.id, a.id) * 1000 + count(a.id); if (sc > best) { best = sc; pick = i; } }); }
      out.push(rest.splice(pick, 1)[0]);
    }
    return out;
  };
  const leftActors = orderSide(sideActors('left')), rightActors = orderSide(sideActors('right'));
  const indexOnSide = new Map([...leftActors.map((a, i) => [a.id, i]), ...rightActors.map((a, i) => [a.id, i])]);

  // ---- extension points (UML 2.5): extends[].point khai trên UC gốc → ellipse gốc có ngăn "extension points", cao thêm EXT_H
  const EXT_H = 26;
  const extPointsOf = (u) => uniq(A.extend.filter((x) => x.base === u && x.point).map((x) => String(x.point)));
  const hOf = (u) => UC_H + (extPointsOf(u).length ? EXT_H : 0);

  // ---- quan hệ UC–UC
  const hostsOf = (u) => uniq([...A.gens.filter((g) => g.child === u).map((g) => g.parent), ...A.includes.filter((x) => x.part === u).map((x) => x.base), ...A.extend.filter((x) => x.extending === u).map((x) => x.base)]);
  const dependentsOf = (h) => uniq([...A.gens.filter((g) => g.parent === h).map((g) => g.child), ...A.includes.filter((x) => x.base === h).map((x) => x.part), ...A.extend.filter((x) => x.base === h).map((x) => x.extending)]);

  // ---- xếp (lặp: actor nào mà khe trong khối riêng phải quá rộng thì chuyển UC riêng của nó ra cột giữa)
  const forceCenter = new Set();
  let R = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    R = place(forceCenter);
    if (!R.needForce.size) break;
    for (const a of R.needForce) forceCenter.add(a);
  }

  function place(forceCenter) {
    const needForce = new Set();
    // --- chủ của từng UC
    const owner = new Map();      // ucId → actorId | '__center__' | '__bottom__'
    const attached = new Map();   // ucId → {host} (UC không actor, một host)
    const hubs = new Map();       // ucId → [hosts] (UC không actor, ≥ 2 host — đặt ở điểm hội tụ)
    for (const u of ucs) {
      const direct = directActors(u.id);
      const nonParent = direct.filter((a) => !parentActors.has(a) || treeParents.has(a));
      if (nonParent.length) {
        const l = nonParent.filter((a) => side.get(a) === 'left'), r = nonParent.filter((a) => side.get(a) === 'right');
        if (l.length && r.length && mode !== 'left') owner.set(u.id, '__center__');
        else owner.set(u.id, [...nonParent].sort((a, b) => count(a) - count(b) || actors.findIndex((x) => x.id === a) - actors.findIndex((x) => x.id === b))[0]);
      } else if (direct.length) owner.set(u.id, '__bottom__');
      else {
        const hs = hostsOf(u.id);
        if (hs.length >= 2) hubs.set(u.id, hs); else if (hs.length === 1) attached.set(u.id, { host: hs[0] }); else owner.set(u.id, humans[0]?.id || '__bottom__'); // lint báo ERROR
      }
    }
    // hub mà các host không cùng một "chỗ" (cụm/cột giữa) → gắn vào host đầu như UC một host
    const placeOf = (u) => owner.get(u) ?? (attached.has(u) ? placeOf(attached.get(u).host) : hubs.has(u) ? placeOf(hubs.get(u)[0]) : null);
    for (const [u, hs] of [...hubs]) if (new Set(hs.map(placeOf)).size > 1) { hubs.delete(u); attached.set(u, { host: hs[0] }); }
    // actor có UC ở cột giữa nhiều hơn UC riêng (hoặc bị ép) → UC riêng cũng ra cột giữa, đứng ngang actor
    if (mode !== 'left') {
      for (const a of [...humans, ...externals]) {
        const cb = assoc.filter((x) => x.actor === a.id && owner.get(x.usecase) === '__center__').length;
        const excl = ucs.filter((u) => owner.get(u.id) === a.id).length;
        if (cb && (forceCenter.has(a.id) || cb >= excl)) for (const u of ucs) if (owner.get(u.id) === a.id) owner.set(u.id, '__center__');
      }
    }
    const childrenOf = (u) => [...attached.entries()].filter(([, h]) => h.host === u).map(([c]) => c);
    // UC có ngăn "extension points" (UML 2.5, mẫu Back-End) cao hơn → chiếm số dòng lẻ
    const rowsOf = (u) => (hOf(u) + (ROW - UC_H)) / ROW;
    const leafRows = (u) => { const ch = childrenOf(u); return ch.length ? Math.max(rowsOf(u), ch.reduce((s_, c) => s_ + leafRows(c), 0)) : rowsOf(u); };
    const treeCols = (u) => 1 + Math.max(0, ...childrenOf(u).map(treeCols));
    const treeSize = (u) => rowsOf(u) + childrenOf(u).reduce((s_, c) => s_ + treeSize(c), 0);
    // --- thứ tự UC gốc trong một cụm: nhóm (host + dependent có actor cùng cụm + các host cùng chia hub) đi liền; nhóm nào dùng chung với actor
    //     phía trên lên đầu, phía dưới xuống cuối
    const orderRoots = (ownerId, ids) => {
      const me = indexOnSide.get(ownerId) ?? 0;
      const pull = (u) => {
        const others = directActors(u).filter((a) => a !== ownerId && side.get(a) === side.get(ownerId));
        if (!others.length) return 0;
        return others.reduce((s_, a) => s_ + Math.sign((indexOnSide.get(a) ?? me) - me), 0) / others.length;
      };
      const set = new Set(ids), seen = new Set(), groups = [];
      const collect = (u, acc) => {
        if (seen.has(u) || !set.has(u)) return;
        seen.add(u); acc.push(u);
        for (const d of dependentsOf(u)) collect(d, acc);
        for (const [h, hs] of hubs) if (hs.includes(u)) for (const other of hs) collect(other, acc); // các host cùng chia hub đứng liền nhau
      };
      const isDep = (u) => ids.some((h) => h !== u && dependentsOf(h).includes(u));
      for (const u of ids) if (!isDep(u)) { const g = []; collect(u, g); if (g.length) groups.push(g); }
      for (const u of ids) if (!seen.has(u)) { const g = []; collect(u, g); if (g.length) groups.push(g); }
      const gp = (g) => g.reduce((s_, u) => s_ + pull(u), 0) / g.length;
      groups.sort((a, b) => gp(a) - gp(b) || ids.indexOf(a[0]) - ids.indexOf(b[0]));
      return groups.flat();
    };
    const clusterOf = new Map();
    for (const a of [...humans, ...externals, ...parentList.filter((p) => treeParents.has(p.id))]) {
      const roots = orderRoots(a.id, ucs.filter((u) => owner.get(u.id) === a.id).map((u) => u.id));
      const hubList = [...hubs].filter(([, hs]) => hs.every((h) => roots.includes(h) || roots.some((r) => dependentsOf(r).includes(h)))).map(([u]) => u);
      clusterOf.set(a.id, { roots, hubList, rows: roots.reduce((s_, r) => s_ + leafRows(r), 0), cols: Math.max(1, ...roots.map(treeCols)) + (hubList.length ? 1 : 0) });
    }
    const bottomRoots = ucs.filter((u) => owner.get(u.id) === '__bottom__').map((u) => u.id);
    const centerRoots = orderRoots('__center__', ucs.filter((u) => owner.get(u.id) === '__center__').map((u) => u.id));
    const centerHubs = [...hubs].filter(([, hs]) => hs.every((h) => centerRoots.includes(h) || centerRoots.some((r) => dependentsOf(r).includes(h)))).map(([u]) => u);
    const centerRows = centerRoots.reduce((s_, r) => s_ + treeSize(r), 0);
    // hub của cột giữa đứng ở cột phụ phía XA các actor của host (mẫu Library: Update catalog nằm bên trái các UC của Librarian)
    const hubSideOf = (u) => {
      const as = uniq(hubs.get(u).flatMap((h) => directActors(h)));
      const l = as.filter((a) => side.get(a) === 'left').length, r = as.filter((a) => side.get(a) === 'right').length;
      return l > r ? 'right' : r > l ? 'left' : 'below';
    };
    const centerHubSides = new Set(centerHubs.map(hubSideOf));

    // --- kích thước boundary
    const blockW = (list) => Math.max(0, ...list.map((a) => clusterOf.get(a.id).cols)) * COL - (COL - UC_W);
    const leftW = leftActors.length ? blockW(leftActors) : 0, rightW = rightActors.length ? blockW(rightActors) : 0;
    const centerW = centerRoots.length ? UC_W + (centerHubSides.has('left') ? COL : 0) + (centerHubSides.has('right') ? COL : 0) : 0;
    // chừa chỗ cho note điều kiện «extend» (UML 2.5) ở khoảng giữa — không có chỗ thì note rơi về nhãn trên đường
    const extNoteW = Math.max(0, ...A.extend.filter((x) => x.condition || x.point).map((x) => noteSize(extNoteLines(x, LT)).w));
    const noteRoom = extNoteW ? extNoteW + 48 : 0;
    const midGap = centerW ? centerW + 2 * 110 + Math.max(0, noteRoom - 110) : (leftW && rightW ? Math.max(MID_GAP, noteRoom) : noteRoom);
    const GAP_ROWS = 1.4, GAP_CAP = Math.round(ROW * 3);
    const gapOf = (a) => (assoc.some((x) => x.actor === a.id && owner.get(x.usecase) === '__center__') && clusterOf.get(a.id).rows >= 1 ? Math.round(ROW * GAP_ROWS) : 0);
    const stackH = (list) => list.reduce((s_, a) => s_ + Math.max(1, clusterOf.get(a.id).rows) * ROW + gapOf(a), 0) + Math.max(0, list.length - 1) * CLUSTER_GAP;
    const bottomCols = Math.min(bottomRoots.length, 6);
    const bottomRows = bottomRoots.length ? Math.ceil(bottomRoots.length / bottomCols) : 0;
    const bottomW = bottomCols ? bottomCols * BOTTOM_ROW_PITCH - (BOTTOM_ROW_PITCH - UC_W) : 0;
    const innerW = Math.max(leftW + midGap + rightW, bottomW, 3 * UC_W);
    const innerH = Math.max(stackH(leftActors), stackH(rightActors), centerRows * ROW + centerHubs.length * 0, ROW) + (bottomRows ? BOTTOM_GAP + bottomRows * ROW : 0);
    const B = { x: MARGIN + ACTOR_W + ACTOR_GAP, y: MARGIN, w: innerW + 2 * PAD, h: TITLE_H + innerH + 2 * PAD, name: model.subject?.name || 'System' };
    const cx0Center = B.x + PAD + leftW + 110 + (centerHubSides.has('left') ? COL : 0);

    // --- đặt hình
    const ucBox = new Map();
    const actorBox = new Map();
    /** y = mép trên của khối dòng; hộp UC căn giữa khối của nó; trả về số dòng (có thể lẻ) khối chiếm. */
    const placeTree = (u, x, y, dir) => {
      const ch = childrenOf(u);
      if (!ch.length) { ucBox.set(u, { x, y: y + (rowsOf(u) * ROW - hOf(u)) / 2, w: UC_W, h: hOf(u) }); return rowsOf(u); }
      let cy = y, rows = 0;
      for (const c of ch) { const r = placeTree(c, x + dir * COL, cy, dir); cy += r * ROW; rows += r; }
      rows = Math.max(rows, rowsOf(u));
      ucBox.set(u, { x, y: y + (rows * ROW - hOf(u)) / 2, w: UC_W, h: hOf(u) });
      return rows;
    };
    const placeTreeDown = (u, x, y) => {
      const ch = childrenOf(u);
      ucBox.set(u, { x, y: y + (rowsOf(u) * ROW - hOf(u)) / 2, w: UC_W, h: hOf(u) });
      let rows = rowsOf(u);
      for (const c of ch) rows += placeTreeDown(c, x, y + rows * ROW);
      return rows;
    };
    /** Hub (điểm hội tụ): cột sâu hơn một bậc so với host sâu nhất, hàng trung vị của các host; bị chiếm thì dịch xuống/lên tới ô trống. */
    const placeHub = (u, dirX, colX, lo, hi) => {
      const hs = hubs.get(u).map((h) => ucBox.get(h)).filter(Boolean);
      if (!hs.length) return 0;
      const ys = hs.map((b) => b.y).sort((a, b) => a - b);
      let y = ys[Math.floor((ys.length - 1) / 2)];
      if (ys.length % 2 === 0) y = (ys[ys.length / 2 - 1] + ys[ys.length / 2]) / 2;
      const taken = [...ucBox.values()].filter((b) => Math.abs(b.x - colX) < 1);
      const free = (yy) => !taken.some((b) => yy < b.y + b.h + 8 && yy + hOf(u) + 8 > b.y);
      for (let k = 0; k < 40 && !free(y); k++) y = y + (k % 2 ? -1 : 1) * ROW * Math.ceil((k + 1) / 2);
      y = Math.max(lo, y);
      ucBox.set(u, { x: colX, y, w: UC_W, h: hOf(u) });
      return Math.max(0, y + hOf(u) + (ROW - UC_H) / 2 - hi);
    };
    /** Lượt 2 biết y của UC cột giữa: UC riêng xếp HẾT lên trên actor nếu các đường ra giữa đi xuống, xuống dưới nếu đi lên, chia đôi quanh khe nếu hai chiều;
     *  khe cần rộng hơn GAP_CAP → đánh dấu actor để lần lặp sau chuyển UC riêng ra cột giữa. */
    const placeSide = (list, sideName, centerY = null) => {
      let y = B.y + TITLE_H + PAD;
      for (const a of list) {
        const c = clusterOf.get(a.id);
        const x0 = sideName === 'left' ? B.x + PAD : B.x + B.w - PAD - UC_W;
        const dir = sideName === 'left' ? 1 : -1;
        const cb = assoc.filter((x) => x.actor === a.id && owner.get(x.usecase) === '__center__').map((x) => x.usecase);
        let gap = gapOf(a);
        let topRoots = c.roots, bottomRoots_ = [];
        let arrangement = 'split';
        if (gap && centerY) {
          const myMid = y + (c.rows * ROW + gap) / 2;
          const ys = cb.map((u) => centerY.get(u)).filter((v) => v !== undefined);
          const up = ys.filter((v) => v < myMid - ROW), down = ys.filter((v) => v > myMid + ROW);
          if (down.length && !up.length) arrangement = 'above';
          else if (up.length && !down.length) arrangement = 'below';
          else if (ys.length) {
            const dxCol = ACTOR_GAP + (sideName === 'left' ? leftW : rightW) + 20;
            const dxTot = Math.max(dxCol + 60, sideName === 'left' ? cx0Center - MARGIN : B.x + B.w + ACTOR_GAP - (cx0Center + UC_W));
            const dropUp = Math.max(0, ...up.map((v) => (myMid - v) * dxCol / dxTot)), dropDown = Math.max(0, ...down.map((v) => (v - myMid) * dxCol / dxTot));
            const need = Math.round(dropUp + dropDown + UC_H + 24);
            if (need > GAP_CAP) needForce.add(a.id);
            gap = Math.min(GAP_CAP, Math.max(gap, need));
          }
        }
        if (gap) {
          if (arrangement === 'above') { topRoots = c.roots; bottomRoots_ = []; gap = Math.round(ROW * 0.9); }
          else if (arrangement === 'below') { topRoots = []; bottomRoots_ = c.roots; gap = Math.round(ROW * 0.9); }
          else {
            const half = c.rows / 2; let acc = 0; const cut = c.roots.findIndex((r) => { acc += leafRows(r); return acc >= half; });
            topRoots = c.roots.slice(0, cut + 1); bottomRoots_ = c.roots.slice(cut + 1);
            if (c.rows === 1) { topRoots = c.roots; bottomRoots_ = []; }
          }
        }
        let h = Math.max(1, c.rows) * ROW + gap;
        let cy = y;
        for (const r of topRoots) cy += placeTree(r, x0, cy, dir) * ROW;
        const gapMid = cy + gap / 2;
        cy += gap;
        for (const r of bottomRoots_) cy += placeTree(r, x0, cy, dir) * ROW;
        // hub của cụm: cột sâu nhất của cụm (sau cột con), hàng trung vị các host
        if (c.hubList.length) {
          const depth = Math.max(1, ...c.roots.map(treeCols));
          const hubX = x0 + dir * COL * depth;
          for (const u of c.hubList) h += placeHub(u, dir, hubX, y, y + h);
        }
        const ax = sideName === 'left' ? MARGIN : B.x + B.w + ACTOR_GAP;
        actorBox.set(a.id, { x: ax, y: (gap ? gapMid : y + h / 2) - (ACTOR_H + ACTOR_LABEL_H) / 2, w: ACTOR_W, h: ACTOR_H, side: sideName, name: a.name, external: isExternal(a) });
        y += h + CLUSTER_GAP;
      }
    };
    const placeCenter = () => {
      if (!centerRoots.length) return;
      const cx0 = cx0Center;
      const actorMid = (id) => { const b = actorBox.get(id); return b ? b.y + b.h / 2 : B.y + B.h / 2; };
      const desired = (u) => { const as = directActors(u).filter((a) => actorBox.has(a) && actorBox.get(a).side !== 'bottom'); return as.length ? as.reduce((s_, a) => s_ + actorMid(a), 0) / as.length : B.y + B.h / 2; };
      // nhóm host + dependent có actor (orderRoots đã gom) → mỗi nhóm một khối dọc; y mong muốn = trung bình trọng tâm actor của nhóm
      const groups = [];
      { const seen = new Set();
        const isDep = (u) => centerRoots.some((h) => h !== u && dependentsOf(h).includes(u));
        const collect = (u, acc) => { if (seen.has(u) || !centerRoots.includes(u)) return; seen.add(u); acc.push(u); for (const d of dependentsOf(u)) collect(d, acc); for (const [, hs] of hubs) if (hs.includes(u)) for (const o of hs) collect(o, acc); };
        for (const u of centerRoots) if (!isDep(u)) { const g = []; collect(u, g); if (g.length) groups.push(g); }
        for (const u of centerRoots) if (!seen.has(u)) { const g = []; collect(u, g); if (g.length) groups.push(g); } }
      const want = groups.map((g) => ({ g, y: g.reduce((s_, u) => s_ + desired(u), 0) / g.length, rows: g.reduce((s_, u) => s_ + treeSize(u), 0) }));
      want.sort((a, b) => a.y - b.y || centerRoots.indexOf(a.g[0]) - centerRoots.indexOf(b.g[0]));
      const top = B.y + TITLE_H + PAD, bottom = B.y + B.h - PAD - (bottomRows ? BOTTOM_GAP + bottomRows * ROW : 0);
      const ys = []; let cur = top;
      for (const w of want) { const yy = Math.max(cur, w.y - (w.rows * ROW) / 2); ys.push(yy); cur = yy + w.rows * ROW; }
      if (cur > bottom) for (let i = ys.length - 1, floor = bottom; i >= 0; i--) { ys[i] = Math.min(ys[i], floor - want[i].rows * ROW); floor = ys[i]; }
      want.forEach((w, i) => { let yy = Math.max(top, ys[i]); for (const u of w.g) yy += placeTreeDown(u, cx0, yy) * ROW; });
      // hub của cột giữa: cột phụ phía xa actor của các host (hoặc ngay dưới nhóm nếu actor hai phía)
      for (const u of centerHubs) {
        const sd = hubSideOf(u);
        if (sd === 'below') { const hs = hubs.get(u).map((h) => ucBox.get(h)).filter(Boolean); const yy = Math.max(...hs.map((b) => b.y)) + ROW; ucBox.set(u, { x: cx0, y: yy, w: UC_W, h: hOf(u) }); for (const [id, b] of ucBox) if (id !== u && Math.abs(b.x - cx0) < 1 && b.y >= yy) b.y += ROW; }
        else placeHub(u, 1, sd === 'left' ? cx0 - COL : cx0 + COL, top, bottom);
      }
      // actor không có UC riêng (mọi UC đều ở cột giữa): đứng ngang trọng tâm UC của mình, không chồng actor khác cùng phía
      for (const sideName of ['left', 'right']) {
        const list = sideName === 'left' ? leftActors : rightActors;
        const fixed = list.filter((a) => clusterOf.get(a.id).rows > 0).map((a) => actorBox.get(a.id).y + ACTOR_H / 2);
        for (const a of list) {
          if (clusterOf.get(a.id).rows > 0) continue;
          const pts = assoc.filter((x) => x.actor === a.id).map((x) => ucBox.get(x.usecase)).filter(Boolean).map((b) => b.y + b.h / 2);
          if (!pts.length) continue;
          let yy = pts.reduce((s_, v) => s_ + v, 0) / pts.length;
          const lo = B.y + TITLE_H + PAD + ACTOR_H / 2, hi = B.y + B.h - PAD - ACTOR_H / 2 - ACTOR_LABEL_H;
          yy = Math.min(hi, Math.max(lo, yy));
          for (let pass = 0; pass < 20; pass++) { const clash = fixed.find((f) => Math.abs(f - yy) < ACTOR_H + ACTOR_LABEL_H + 20); if (!clash) break; yy = clash + (yy >= clash ? 1 : -1) * (ACTOR_H + ACTOR_LABEL_H + 20); yy = Math.min(hi, Math.max(lo, yy)); }
          fixed.push(yy);
          actorBox.get(a.id).y = yy - ACTOR_H / 2;
        }
      }
    };
    placeSide(leftActors, 'left'); placeSide(rightActors, 'right'); placeCenter();
    for (let pass = 0; pass < 2 && centerRoots.length; pass++) {
      const centerY = new Map(centerRoots.map((u) => [u, ucBox.get(u).y + UC_H / 2]));
      for (const u of [...ucBox.keys()]) ucBox.delete(u);
      for (const a of [...actorBox.keys()]) actorBox.delete(a);
      placeSide(leftActors, 'left', centerY); placeSide(rightActors, 'right', centerY); placeCenter();
    }
    // dòng đáy + actor cha (kiểu FPT)
    if (bottomRoots.length) {
      const y0 = B.y + B.h - PAD - bottomRows * ROW + (ROW - UC_H) / 2;
      const x0 = B.x + (B.w - bottomW) / 2;
      bottomRoots.forEach((u, i) => ucBox.set(u, { x: x0 + (i % bottomCols) * BOTTOM_ROW_PITCH, y: y0 + Math.floor(i / bottomCols) * ROW, w: UC_W, h: hOf(u) }));
    }
    parentList.filter((p) => !treeParents.has(p.id)).forEach((p, i, arr) => {
      const px = B.x + B.w / 2 - ACTOR_W / 2 + (i - (arr.length - 1) / 2) * 160;
      actorBox.set(p.id, { x: px, y: B.y + B.h + PARENT_GAP, w: ACTOR_W, h: ACTOR_H, side: 'bottom', name: p.name, external: false });
    });
    // cha kiểu cây (mẫu Library): con không có UC riêng xếp NGANG thành hàng dưới cha, nối bằng thanh chung và một tam giác dưới nhãn cha
    for (const p of parentList.filter((x) => treeParents.has(x.id))) {
      const P = actorBox.get(p.id);
      if (!P) continue;
      const kids = childrenActors(p.id).filter((k) => treeKids.has(k));
      if (!kids.length) continue;
      const perRow = 3, pitch = 100;
      let y0 = P.y + ACTOR_H + ACTOR_LABEL_H + 48;
      const others = [...actorBox.values()].filter((b) => b.side === P.side);
      const rowsN = Math.ceil(kids.length / perRow);
      const blockH = rowsN * (ACTOR_H + ACTOR_LABEL_H + 30);
      for (let k = 0; k < 40 && others.some((b) => b.y < y0 + blockH && b.y + ACTOR_H + ACTOR_LABEL_H > y0); k++) y0 += 20;
      kids.forEach((c, i) => {
        const row = Math.floor(i / perRow), col = i % perRow, nIn = Math.min(perRow, kids.length - row * perRow);
        const cx = P.x + P.w / 2 + (col - (nIn - 1) / 2) * pitch;
        const a = actors.find((x) => x.id === c);
        actorBox.set(c, { x: cx - ACTOR_W / 2, y: y0 + row * (ACTOR_H + ACTOR_LABEL_H + 30), w: ACTOR_W, h: ACTOR_H, side: P.side, name: a.name, external: false, treeChild: true, barY: y0 - 20 - row * 0 });
      });
    }
    return { needForce, owner, attached, hubs, B, ucBox, actorBox, bottomRows, centerRoots };
  }

  const { owner, attached, B, ucBox, actorBox } = R;

  // ---- vật cản & định tuyến
  const obstacles = [
    ...[...ucBox.entries()].map(([id, b]) => ({ id: `uc_${id}`, ...b, ellipse: true })),
    ...[...actorBox.entries()].map(([id, b]) => ({ id: `actor_${id}`, x: b.x, y: b.y, w: b.w, h: b.h + ACTOR_LABEL_H, ellipse: false })),
    // nhãn actor rộng hơn hình người: đường của CHÍNH actor đó cũng không được chém qua tên (vật cản riêng, không bị skip)
    ...[...actorBox.entries()].map(([id, b]) => { const w = labelW(b.name); return { id: `label_${id}`, x: b.x + b.w / 2 - w / 2, y: b.y + b.h + 3, w, h: ACTOR_LABEL_H - 9, ellipse: false }; }),
    { id: 'title', x: B.x, y: B.y, w: B.w, h: TITLE_H, ellipse: false },
  ];
  const bounds = { x0: -40, y0: 0, x1: Math.max(B.x + B.w, ...[...actorBox.values()].map((b) => b.x + b.w)) + 80, y1: Math.max(B.y + B.h, ...[...actorBox.values()].map((b) => b.y + b.h + ACTOR_LABEL_H)) + 60 };
  const portsOf = (box, kind) => {
    const cx = box.x + box.w / 2, cy = box.y + box.h / 2;
    if (kind === 'actor') {
      if (box.side === 'left') return [{ p: [box.x + box.w, box.y + box.h * 0.33], f: [1, 0.33] }, { p: [cx, box.y + box.h + ACTOR_LABEL_H], f: [0.5, 1] }, { p: [cx, box.y], f: [0.5, 0] }];
      if (box.side === 'right') return [{ p: [box.x, box.y + box.h * 0.33], f: [0, 0.33] }, { p: [cx, box.y + box.h + ACTOR_LABEL_H], f: [0.5, 1] }, { p: [cx, box.y], f: [0.5, 0] }];
      return [{ p: [cx, box.y], f: [0.5, 0] }, { p: [box.x, box.y + box.h * 0.33], f: [0, 0.33] }, { p: [box.x + box.w, box.y + box.h * 0.33], f: [1, 0.33] }];
    }
    return [{ p: [box.x, cy], f: [0, 0.5] }, { p: [box.x + box.w, cy], f: [1, 0.5] }, { p: [cx, box.y], f: [0.5, 0] }, { p: [cx, box.y + box.h], f: [0.5, 1] }];
  };
  const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const connect = (srcId, srcBox, srcKind, dstId, dstBox, dstKind) => {
    const skip = new Set([srcId, dstId]);
    const combos = [];
    const sp = portsOf(srcBox, srcKind);
    for (const s_ of sp) for (const d of portsOf(dstBox, dstKind)) combos.push({ s: s_, d, len: dist(s_.p, d.p), hand: srcKind === 'actor' && srcBox.side !== 'bottom' && s_ === sp[0] });
    // mẫu sách: mọi association của một actor toả ra từ MỘT điểm (bàn tay phía boundary); chỉ khi chém hình/nhãn mới ra chân hoặc đỉnh
    combos.sort((a, b) => (b.hand - a.hand) || a.len - b.len);
    const nHand = combos.filter((c) => c.hand).length;
    const ownOk = (c) => !(dstKind === 'uc' && throughOwn(c.s.p, c.d.p, dstBox)) && !(srcKind === 'uc' && throughOwn(c.s.p, c.d.p, srcBox));
    for (const c of combos.slice(0, nHand + 8)) if (ownOk(c) && !segmentHits(c.s.p, c.d.p, obstacles, skip)) return { from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: [], routed: false };
    combos.sort((a, b) => a.len - b.len);
    let best = null;
    for (const c of combos.slice(0, 6)) {
      const pts = routeOrtho(c.s.p, c.d.p, obstacles, bounds, skip);
      if (!pts) continue;
      const path = [c.s.p, ...pts, c.d.p];
      const len = path.reduce((acc, p, i) => (i ? acc + dist(path[i - 1], p) : 0), 0) + pts.length * 40;
      if (!best || len < best.len) best = { len, from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: pts };
    }
    if (best) return { ...best, routed: true };
    const c = combos[0];
    return { from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: [], routed: false, blocked: true };
  };

  // ---- cạnh
  const edges = [];
  let routedCount = 0, blockedCount = 0;
  assoc.forEach((x, i) => {
    const Ab = actorBox.get(x.actor), U = ucBox.get(x.usecase);
    if (!Ab || !U) return;
    const r = connect(`actor_${x.actor}`, Ab, 'actor', `uc_${x.usecase}`, U, 'uc');
    if (r.routed) routedCount++; if (r.blocked) blockedCount++;
    edges.push({ id: `assoc${i + 1}`, kind: 'assoc', source: `actor_${x.actor}`, target: `uc_${x.usecase}`, ...r });
  });
  // đoạn association đã vẽ (để đường UC–UC không chém qua quạt đường của actor); bỏ các đoạn kết thúc ở chính F/T
  const assocSegs = () => edges.filter((e) => e.kind === 'assoc').flatMap((e) => { const pts = [e.from, ...e.points, e.to]; return pts.slice(1).map((q, i) => ({ a: pts[i], b: q, target: e.target })); });
  const crossesLines = (p, q, segs) => segs.filter((sg) => segIntersect(p, q, sg.a, sg.b)).length;
  const redrawAssoc = (ucId) => {
    for (let i = 0; i < edges.length; i++) {
      const e = edges[i];
      if (e.kind !== 'assoc' || e.target !== `uc_${ucId}`) continue;
      const Ab = actorBox.get(e.source.replace('actor_', '')), U = ucBox.get(ucId);
      edges[i] = { id: e.id, kind: 'assoc', source: e.source, target: e.target, ...connect(e.source, Ab, 'actor', e.target, U, 'uc') };
    }
  };
  const overlapsAny = (box, exceptId) => [...ucBox.entries()].some(([id, b]) => id !== exceptId && box.x < b.x + b.w + 12 && box.x + box.w + 12 > b.x && box.y < b.y + b.h + 8 && box.y + box.h + 8 > b.y);
  const sideOfUc = (u) => { const b = ucBox.get(u); return b.x + b.w / 2 < B.x + B.w / 2 ? 'left' : 'right'; };
  const actorLinesOn = (u, sideName) => assoc.filter((x) => x.usecase === u && actorBox.get(x.actor)?.side === sideName).length;
  const ucEdge = (id, kind, fromId, toId, label) => {
    let F = ucBox.get(fromId), T = ucBox.get(toId);
    const skip = new Set([`uc_${fromId}`, `uc_${toId}`]);
    const segs = assocSegs().filter((sg) => sg.target !== `uc_${fromId}` && sg.target !== `uc_${toId}`);
    const push = (r) => edges.push({ id, kind, source: `uc_${fromId}`, target: `uc_${toId}`, label, ...r });
    const vgap = F.y < T.y ? T.y - (F.y + F.h) : F.y - (T.y + T.h);
    if (Math.abs(F.x - T.x) < 1 && vgap <= (ROW - UC_H) + 4) {
      const down = F.y < T.y;
      return push({ from: [F.x + F.w / 2, F.y + (down ? F.h : 0)], to: [T.x + T.w / 2, T.y + (down ? 0 : T.h)], exit: [0.5, down ? 1 : 0], entry: [0.5, down ? 0 : 1], points: [], labelOffset: [38, 0] });
    }
    // (1) kẻ thẳng: cặp cổng gần nhất không cắt hình và không cắt đường association
    const straight = (Fb, Tb) => {
      const combos = [];
      for (const s_ of portsOf(Fb, 'uc')) for (const d of portsOf(Tb, 'uc')) combos.push({ s: s_, d, len: dist(s_.p, d.p) });
      combos.sort((a, b) => a.len - b.len);
      for (const c of combos) if (!throughOwn(c.s.p, c.d.p, Fb) && !throughOwn(c.s.p, c.d.p, Tb) && !segmentHits(c.s.p, c.d.p, obstacles, skip) && !crossesLines(c.s.p, c.d.p, segs)) return { from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: [], labelOffset: [0, -8] };
      return null;
    };
    let r = straight(F, T);
    if (r) return push(r);
    // (2) mẫu Hospital: dịch một trong hai UC 60px về phía trong (xa actor) rồi kẻ chéo
    const innerDir = (u) => { const sd = sideOfUc(u); const l = actorLinesOn(u, 'left'), rr = actorLinesOn(u, 'right'); return l > rr ? 1 : rr > l ? -1 : sd === 'left' ? 1 : -1; };
    for (const [uid, box] of [[toId, T], [fromId, F]]) {
      const shifted = { ...box, x: box.x + 60 * innerDir(uid) };
      if (shifted.x < B.x + 8 || shifted.x + shifted.w > B.x + B.w - 8 || overlapsAny(shifted, uid)) continue;
      ucBox.set(uid, shifted);
      const Fb = ucBox.get(fromId), Tb = ucBox.get(toId);
      const obsIdx = obstacles.findIndex((o) => o.id === `uc_${uid}`); const oldObs = obstacles[obsIdx]; obstacles[obsIdx] = { ...oldObs, x: shifted.x };
      redrawAssoc(uid);
      r = straight(Fb, Tb);
      if (r) return push(r);
      ucBox.set(uid, box); obstacles[obsIdx] = oldObs; redrawAssoc(uid);
    }
    // (3) rẽ dọc phía TRONG (xa actor), chọn bên cắt ít đường nhất; không bao giờ rẽ phía có quạt đường của actor
    if (Math.abs(F.x - T.x) < 1) {
      const cands = [];
      for (const dir of [1, -1]) {
        const jx = dir > 0 ? F.x + F.w + 24 : F.x - 24;
        const from = [dir > 0 ? F.x + F.w : F.x, F.y + F.h / 2], to = [dir > 0 ? T.x + T.w : T.x, T.y + T.h / 2];
        const pts = [[jx, from[1]], [jx, to[1]]];
        const path = [from, ...pts, to];
        let bad = 0;
        for (let i = 1; i < path.length; i++) { if (segmentHits(path[i - 1], path[i], obstacles, skip)) bad += 100; bad += crossesLines(path[i - 1], path[i], segs); }
        cands.push({ bad, r: { from, to, exit: [dir > 0 ? 1 : 0, 0.5], entry: [dir > 0 ? 1 : 0, 0.5], points: pts, labelOffset: [dir > 0 ? 34 : -34, 0], routed: true } });
      }
      cands.sort((a, b) => a.bad - b.bad);
      if (cands[0].bad === 0) { routedCount++; return push(cands[0].r); }
    }
    // (4) router trực giao, tránh cả hình lẫn đường association
    let best = null;
    const combos = [];
    for (const s_ of portsOf(F, 'uc')) for (const d of portsOf(T, 'uc')) combos.push({ s: s_, d, len: dist(s_.p, d.p) });
    combos.sort((a, b) => a.len - b.len);
    for (const c of combos.slice(0, 6)) {
      const pts = routeOrtho(c.s.p, c.d.p, obstacles, bounds, skip, segs.map((sg) => [sg.a, sg.b]));
      if (!pts) continue;
      const path = [c.s.p, ...pts, c.d.p];
      const len = path.reduce((acc, pt, i) => (i ? acc + dist(path[i - 1], pt) : 0), 0) + pts.length * 40;
      if (!best || len < best.len) best = { len, from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: pts, labelOffset: [0, -8] };
    }
    if (best) { routedCount++; return push({ ...best, routed: true }); }
    blockedCount++;
    const c = combos[0];
    push({ from: c.s.p, to: c.d.p, exit: c.s.f, entry: c.d.f, points: [], labelOffset: [0, -8], blocked: true });
  };
  A.gens.forEach((g, i) => ucEdge(`ucgen${i + 1}`, 'ucgen', g.child, g.parent, ''));
  spreadGenHeads(edges, ucBox);
  A.includes.forEach((x, i) => ucEdge(`inc${i + 1}`, 'include', x.base, x.part, '«include»'));
  A.extend.forEach((x, i) => ucEdge(`ext${i + 1}`, 'extend', x.extending, x.base, '«extend»'));
  // generalization actor
  let k = 0;
  const genByParentSide = new Map();
  const rightEdgeX = Math.max(B.x + B.w, ...[...actorBox.values()].filter((b) => b.side === 'right').map((b) => b.x + b.w));
  for (const [child, parent] of (drawGen ? Object.entries(parents) : [])) {
    const C = actorBox.get(child), P = actorBox.get(parent);
    if (!C || !P) continue;
    k++;
    const key = `${parent}|${C.side}`;
    const nth = genByParentSide.get(key) || 0; genByParentSide.set(key, nth + 1);
    const busY = B.y + B.h + 24 + GEN_BUS_STEP * (k - 1);
    const cx = C.x + C.w / 2;
    if (C.treeChild && C.side === P.side) {
      // mẫu Library: con đi lên thanh chung rồi vào đáy cha (dưới nhãn) — nhiều con, một tam giác
      const barY = C.barY, pcx = P.x + P.w / 2, endY = P.y + P.h + ACTOR_LABEL_H + 2;
      edges.push({ id: `gen${k}`, kind: 'gen', source: `actor_${child}`, target: `actor_${parent}`, from: [cx, C.y], to: [pcx, endY], exit: [0.5, 0], entry: [0.5, 1], entryDy: ACTOR_LABEL_H + 2,
        points: Math.abs(cx - pcx) < 1 ? [] : [[cx, barY], [pcx, barY]] });
    } else if (P.side === 'bottom') {
      // mẫu FPT: cha ở đáy — ra sườn ngoài con → bus dọc ngoài rìa → xuống dưới boundary → vào sườn cha
      const entryY = Math.min(0.85, 0.35 + 0.12 * nth);
      const ex = C.side === 'left' ? 0 : 1;
      const outer = C.side === 'left' ? MARGIN - 14 - GEN_BUS_STEP * nth : rightEdgeX + 14 + GEN_BUS_STEP * nth;
      const to = [ex ? P.x + P.w : P.x, P.y + P.h * entryY];
      const nearX = ex ? to[0] + 40 + GEN_BUS_STEP * nth : to[0] - 40 - GEN_BUS_STEP * nth;
      edges.push({ id: `gen${k}`, kind: 'gen', source: `actor_${child}`, target: `actor_${parent}`, from: [ex ? C.x + C.w : C.x, C.y + C.h * 0.33], to, exit: [ex, 0.33], entry: [ex, entryY],
        points: [[outer, C.y + C.h * 0.33], [outer, busY], [nearX, busY], [nearX, to[1]]] });
    } else {
      const outer = P.side === 'left' ? MARGIN - 16 - GEN_BUS_STEP * (k - 1) : P.x + P.w + 16 + GEN_BUS_STEP * (k - 1);
      const ex = P.side === 'left' ? 0 : 1;
      const to = [ex ? P.x + P.w : P.x, P.y + P.h * 0.6];
      if (C.side === P.side) edges.push({ id: `gen${k}`, kind: 'gen', source: `actor_${child}`, target: `actor_${parent}`, from: [ex ? C.x + C.w : C.x, C.y + C.h * 0.33], to, exit: [ex, 0.33], entry: [ex, 0.6], points: [[outer, C.y + C.h * 0.33], [outer, to[1]]] });
      else edges.push({ id: `gen${k}`, kind: 'gen', source: `actor_${child}`, target: `actor_${parent}`, from: [cx, C.y + C.h + ACTOR_LABEL_H], to, exit: [0.5, 1], entry: [ex, 0.6], points: [[cx, busY], [outer, busY], [outer, to[1]]] });
    }
  }
  // ---- ghi chú (UML 2.5 §18.1.4: điều kiện + extension point của «extend» viết trong comment gắn vào đường extend)
  const notes = [];
  const boxesOverlap = (a, b, m = 0) => a.x < b.x + b.w + m && a.x + a.w + m > b.x && a.y < b.y + b.h + m && a.y + a.h + m > b.y;
  const rectHitsSeg = (r, p, q) => {
    const inside = (pt) => pt[0] > r.x && pt[0] < r.x + r.w && pt[1] > r.y && pt[1] < r.y + r.h;
    if (inside(p) || inside(q)) return true;
    const c = [[r.x, r.y], [r.x + r.w, r.y], [r.x + r.w, r.y + r.h], [r.x, r.y + r.h]];
    return c.some((a, i) => segIntersect(p, q, a, c[(i + 1) % 4]));
  };
  const segsOf = (list) => list.flatMap((e) => { const pts = [e.from, ...e.points, e.to]; return pts.slice(1).map((q, i) => [pts[i], q]); });
  const midOf = (e) => {
    const pts = [e.from, ...e.points, e.to];
    const ls = pts.slice(1).map((q, i) => dist(pts[i], q)), total = ls.reduce((a, b) => a + b, 0);
    let acc = 0;
    for (let i = 0; i < ls.length; i++) { if (acc + ls[i] >= total / 2) { const t = (total / 2 - acc) / (ls[i] || 1); return [pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t]; } acc += ls[i]; }
    return pts[0];
  };
  const solidsNow = () => [...ucBox.values()]
    .concat([...actorBox.values()].map((b) => { const lw = labelW(b.name); return { x: Math.min(b.x, b.x + b.w / 2 - lw / 2), y: b.y, w: Math.max(b.w, lw), h: b.h + ACTOR_LABEL_H }; }))
    .concat(notes, [{ x: B.x, y: B.y, w: B.w, h: TITLE_H }]);
  const placeNote = (anchor, w, h, ownId) => {
    const solids = solidsNow();
    const all = segsOf(edges), others = segsOf(edges.filter((e) => e.id !== ownId));
    let best = null;
    for (let dy = -260; dy <= 260; dy += 10) for (let dx = -360; dx <= 360; dx += 10) {
      const d = Math.hypot(dx, dy);
      if ((best && d >= best.d) || d < Math.max(w, h) / 2 + 14) continue;
      const r = { x: anchor[0] + dx - w / 2, y: anchor[1] + dy - h / 2, w, h };
      if (r.x < B.x + 8 || r.x + r.w > B.x + B.w - 8 || r.y < B.y + TITLE_H + 4 || r.y + r.h > B.y + B.h - 8) continue;
      if (solids.some((b) => boxesOverlap(r, b, 10))) continue;
      const pad = { x: r.x - 6, y: r.y - 6, w: r.w + 12, h: r.h + 12 };
      if (all.some(([p, q]) => rectHitsSeg(pad, p, q))) continue;
      const cp = [Math.max(r.x, Math.min(anchor[0], r.x + r.w)), Math.max(r.y, Math.min(anchor[1], r.y + r.h))];
      if (segmentHits(cp, anchor, obstacles) || others.some(([p, q]) => segIntersect(cp, anchor, p, q))) continue;
      best = { d, r, cp };
    }
    return best;
  };
  A.extend.forEach((x, i) => {
    if (!x.condition && !x.point) return;
    const e = edges.find((ed) => ed.id === `ext${i + 1}`);
    if (!e) return;
    const lines = extNoteLines(x, LT);
    const { w, h } = noteSize(lines);
    const anchor = midOf(e);
    const got = placeNote(anchor, w, h, e.id);
    if (got) {
      notes.push({ id: `note_ext${i + 1}`, kind: 'ext', ...got.r, lines, anchor, cp: got.cp, edge: e.id });
      // nhãn «extend» sang phía đối diện note để dây note không chạy xuyên chữ — nhưng không trượt ra khỏi đoạn đường: hai UC sát nhau
      // (khe ~55px) mà đẩy 34px thì nhãn đè lên tên UC gốc (vmc-core 26/10/2026: "«extend» uản lý phản hồi") → đẩy ít lại, nâng nhãn lên
      const noteRight = got.r.x + got.r.w / 2 > anchor[0];
      if (e.labelOffset && e.labelOffset[1] === 0) e.labelOffset = [noteRight ? -Math.abs(e.labelOffset[0]) : Math.abs(e.labelOffset[0]), 0];
      else {
        const pts = [e.from, ...(e.points || []), e.to];
        let seg = 0;
        for (let k = 1; k < pts.length; k++) seg = Math.max(seg, Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]));
        const sx = Math.min(34, Math.max(0, (seg - EXT_LABEL_W) / 2));
        // note nằm TRÊN đường thì dây note đi xuống giữa đường — nhãn đặt dưới đường, không thì dây cắt ngang chữ «extend»
        // (vmc-core 26/10/2026, extendDetails "condition": không còn ngăn extension points, note lên trên, khe hai UC ~60px nên sx = 0)
        const noteAbove = got.r.y + got.r.h / 2 < anchor[1];
        const dy = sx < 34 ? 12 : 8;
        e.labelOffset = [noteRight ? -sx : sx, noteAbove ? dy : -dy];
      }
    }
    else if (x.condition) e.label = `«extend»\n{${x.condition}}`; // không còn chỗ trống trong boundary: điều kiện quay về nhãn
  });
  // ghi chú chân hình (UC mọi actor dùng — `--common note` — hoặc model.notes): dưới mọi thứ, canh trái boundary
  let footY = Math.max(B.y + B.h, ...[...actorBox.values()].map((b) => b.y + b.h + ACTOR_LABEL_H), ...edges.flatMap((e) => e.points.map((p) => p[1]))) + 26;
  footNotes.forEach((t, i) => {
    const maxChars = Math.max(40, Math.floor((B.w - 24) / NOTE_CH));
    const lines = noteLines([t], maxChars);
    const w = Math.round(Math.min(B.w, Math.max(...lines.map((l) => l.length)) * NOTE_CH + 30)), h = lines.length * NOTE_LH + 14;
    notes.push({ id: `note_foot${i + 1}`, kind: 'foot', x: B.x, y: footY, w, h, lines });
    footY += h + 10;
  });
  // nhãn actor rộng hơn hình người: khổ hình phải chứa trọn tên (không cắt "Quản trị viên cấp cao" ở mép)
  const allX = [...actorBox.values()].map((b) => Math.max(b.x + b.w, b.x + b.w / 2 + labelW(b.name) / 2)).concat(B.x + B.w, ...edges.flatMap((e) => e.points.map((p) => p[0])), ...notes.map((n) => n.x + n.w));
  const allY = [...actorBox.values()].map((b) => b.y + b.h + ACTOR_LABEL_H).concat(B.y + B.h, ...edges.flatMap((e) => e.points.map((p) => p[1])), ...notes.map((n) => n.y + n.h));
  const minX = Math.min(0, ...edges.flatMap((e) => e.points.map((p) => p[0])), ...[...actorBox.values()].map((b) => Math.min(b.x, b.x + b.w / 2 - labelW(b.name) / 2) - 8));
  return { subject: B, ucs: ucBox, actors: actorBox, edges, notes, owner, attached, sides: side, extPointsOf, stats: { routed: routedCount, blocked: blockedCount, straight: edges.filter((e) => !e.points.length).length }, width: Math.max(...allX) + MARGIN - minX, height: Math.max(...allY) + MARGIN, offsetX: -minX };
}

// ---------------------------------------------------------------- draw.io
const EDGE_STYLE = {
  assoc: 'endArrow=none;html=1;rounded=0;',
  gen: 'endArrow=block;endSize=14;endFill=0;html=1;rounded=0;',
  ucgen: 'endArrow=block;endSize=14;endFill=0;html=1;rounded=0;',
  include: 'endArrow=open;endSize=12;endFill=0;dashed=1;html=1;rounded=0;',
  extend: 'endArrow=open;endSize=12;endFill=0;dashed=1;html=1;rounded=0;',
};

export function toDrawio(model, L, meta = null) {
  const ox = L.offsetX;
  // ghi lại tuỳ chọn build để `check <file.drawio>` biết model gốc và biến thể (parents / actor-tree separate)
  const metaAttr = meta ? ` kickoff="${esc(Object.entries(meta).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => `${k}=${v}`).join(';'))}"` : '';
  const cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>'];
  const S = L.subject;
  cells.push(`<mxCell id="subject" value="${esc(S.name)}" style="rounded=0;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fontSize=14;spacingTop=6;fillColor=none;" vertex="1" parent="1"><mxGeometry x="${S.x + ox}" y="${S.y}" width="${S.w}" height="${S.h}" as="geometry"/></mxCell>`);
  for (const u of model.usecases) {
    const b = L.ucs.get(u.id);
    if (!b) continue;
    const pts = L.extPointsOf ? L.extPointsOf(u.id) : [];
    const label = pts.length ? `${wrapName(u.name).join('<br>')}<hr size="1"><font style="font-size:8px">${esc(extLit(model).points)}</font><br><font style="font-size:9px">${pts.map(esc).join('<br>')}</font>` : wrapName(u.name).join('<br>');
    cells.push(`<mxCell id="uc_${u.id}" value="${esc(label)}" style="ellipse;whiteSpace=wrap;html=1;fontSize=11;${pts.length ? 'verticalAlign=top;spacingTop=4;' : ''}" vertex="1" parent="1"><mxGeometry x="${b.x + ox}" y="${b.y}" width="${b.w}" height="${b.h}" as="geometry"/></mxCell>`);
  }
  for (const [id, a] of L.actors) {
    cells.push(`<mxCell id="actor_${id}" value="${esc(a.name)}" style="shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;fontSize=11;" vertex="1" parent="1"><mxGeometry x="${a.x + ox}" y="${a.y}" width="${a.w}" height="${a.h}" as="geometry"/></mxCell>`);
  }
  for (const e of L.edges) {
    const ee = e.exit ? `exitX=${e.exit[0]};exitY=${e.exit[1]};exitDx=0;exitDy=0;` : '';
    const en = e.entry ? `entryX=${e.entry[0]};entryY=${e.entry[1]};entryDx=0;entryDy=${e.entryDy || 0};${e.entryDy ? 'entryPerimeter=0;' : ''}` : '';
    const pts = e.points.length ? `<Array as="points">${e.points.map((p) => `<mxPoint x="${p[0] + ox}" y="${p[1]}"/>`).join('')}</Array>` : '';
    const off = e.label && e.labelOffset ? `<mxPoint as="offset" x="${e.labelOffset[0]}" y="${e.labelOffset[1]}"/>` : '';
    cells.push(`<mxCell id="${e.id}" value="${esc(String(e.label || '').replace(/\n/g, '<br>'))}" style="${EDGE_STYLE[e.kind]}${ee}${en}fontSize=10;" edge="1" parent="1" source="${e.source}" target="${e.target}"><mxGeometry relative="1" as="geometry">${off}${pts}</mxGeometry></mxCell>`);
  }
  for (const n of L.notes || []) {
    const html = n.lines.map((l) => { const m = l.match(EXT_HEAD_RE); return m ? `<b>${esc(m[1])}</b>${esc(m[2])}` : esc(l); }).join('<br>');
    cells.push(`<mxCell id="${n.id}" value="${esc(html)}" style="shape=note;whiteSpace=wrap;html=1;size=12;align=left;verticalAlign=top;spacingLeft=6;spacingTop=1;fontSize=10;" vertex="1" parent="1"><mxGeometry x="${n.x + ox}" y="${n.y}" width="${n.w}" height="${n.h}" as="geometry"/></mxCell>`);
    if (n.anchor) cells.push(`<mxCell id="${n.id}_link" value="" style="endArrow=none;dashed=1;html=1;rounded=0;" edge="1" parent="1" source="${n.id}"><mxGeometry relative="1" as="geometry"><mxPoint x="${n.anchor[0] + ox}" y="${n.anchor[1]}" as="targetPoint"/></mxGeometry></mxCell>`);
  }
  return `<mxfile host="drawio" agent="kickoff-uml usecase-overview (tier 0)" version="31.4.5"${metaAttr}>
  <diagram id="Use-case-overview" name="Overall use case diagram (tier 0)">
    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${Math.ceil(L.width)}" pageHeight="${Math.ceil(L.height)}" math="0" shadow="0">
      <root>
        ${cells.join('\n        ')}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
`;
}

// ---------------------------------------------------------------- SVG (xem nhanh / fallback PNG không cần draw.io)
export function toSvg(model, L) {
  const ox = L.offsetX;
  const o = [];
  const text = (x, y, s, opts = {}) => {
    const attrs = { 'font-size': 11, ...opts };
    o.push(`<text x="${x}" y="${y}" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" ${Object.entries(attrs).map(([k, v]) => `${k}="${v}"`).join(' ')}>${esc(s)}</text>`);
  };
  const S = L.subject;
  o.push(`<rect x="${S.x + ox}" y="${S.y}" width="${S.w}" height="${S.h}" fill="none" stroke="#000"/>`);
  text(S.x + ox + S.w / 2, S.y + 22, S.name, { 'font-weight': 'bold', 'font-size': 14 });
  for (const u of model.usecases) {
    const b = L.ucs.get(u.id);
    if (!b) continue;
    o.push(`<ellipse cx="${b.x + ox + b.w / 2}" cy="${b.y + b.h / 2}" rx="${b.w / 2}" ry="${b.h / 2}" fill="#fff" stroke="#000"/>`);
    const lines = wrapName(u.name);
    const pts = L.extPointsOf ? L.extPointsOf(u.id) : [];
    if (!pts.length) lines.forEach((ln, i) => text(b.x + ox + b.w / 2, b.y + b.h / 2 + 4 + (i - (lines.length - 1) / 2) * 13, ln));
    else {
      // ngăn extension points (UML 2.5): tên ở nửa trên, vạch ngang, "extension points" + tên điểm ở nửa dưới
      const cx = b.x + ox + b.w / 2, cy = b.y + b.h / 2, ry = b.h / 2, rx = b.w / 2;
      const lineY = b.y + 40 - 2, dy = lineY - cy, half = rx * Math.sqrt(Math.max(0, 1 - (dy / ry) ** 2));
      lines.forEach((ln, i) => text(cx, b.y + 20 + 4 + (i - (lines.length - 1) / 2) * 12, ln));
      o.push(`<line x1="${cx - half}" y1="${lineY}" x2="${cx + half}" y2="${lineY}" stroke="#000"/>`);
      text(cx, lineY + 9, extLit(model).points, { 'font-size': 8 });
      pts.forEach((pt, i) => text(cx, lineY + 19 + i * 10, pt, { 'font-size': 9 }));
    }
  }
  for (const [, a] of L.actors) {
    const cx = a.x + ox + a.w / 2, top = a.y;
    o.push(`<circle cx="${cx}" cy="${top + 8}" r="8" fill="#fff" stroke="#000"/>`);
    o.push(`<line x1="${cx}" y1="${top + 16}" x2="${cx}" y2="${top + 38}" stroke="#000"/>`);
    o.push(`<line x1="${cx - 15}" y1="${top + 20}" x2="${cx + 15}" y2="${top + 20}" stroke="#000"/>`);
    o.push(`<line x1="${cx}" y1="${top + 38}" x2="${cx - 12}" y2="${top + 60}" stroke="#000"/>`);
    o.push(`<line x1="${cx}" y1="${top + 38}" x2="${cx + 12}" y2="${top + 60}" stroke="#000"/>`);
    text(cx, top + 76, a.name);
  }
  for (const e of L.edges) {
    const pts = [e.from, ...e.points, e.to];
    const marker = e.kind === 'gen' || e.kind === 'ucgen' ? 'marker-end="url(#tri)"' : e.kind === 'include' || e.kind === 'extend' ? 'marker-end="url(#open)"' : '';
    const dash = e.kind === 'include' || e.kind === 'extend' ? 'stroke-dasharray="6 4"' : '';
    o.push(`<polyline points="${pts.map((p) => `${p[0] + ox},${p[1]}`).join(' ')}" fill="none" stroke="#000" ${dash} ${marker}/>`);
    if (e.label) {
      let bi = 0, bl = -1;
      for (let i = 1; i < pts.length; i++) { const l = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); if (l > bl) { bl = l; bi = i; } }
      const a = pts[bi - 1], b = pts[bi];
      const [dx, dy] = e.labelOffset || [0, -8];
      const mx = (a[0] + b[0]) / 2 + ox + dx, my = (a[1] + b[1]) / 2 + dy + 4;
      const ls = String(e.label).split('\n');
      // dòng 1 («extend»/«include») phía trên đường, dòng 2 (điều kiện {…}) phía dưới đường — như draw.io canh giữa nhãn nhiều dòng
      o.push(`<rect x="${mx - 30}" y="${my - 10}" width="60" height="13" fill="#fff" stroke="none"/>`);
      ls.forEach((ln, i) => text(mx, i === 0 ? my : my + 18 + (i - 1) * 12, ln, { 'font-size': 10 }));
    }
  }
  for (const n of L.notes || []) {
    const x = n.x + ox, y = n.y, f = 10;
    if (n.anchor) o.push(`<line x1="${n.cp[0] + ox}" y1="${n.cp[1]}" x2="${n.anchor[0] + ox}" y2="${n.anchor[1]}" stroke="#000" stroke-dasharray="4 3"/>`);
    o.push(`<path d="M${x},${y} L${x + n.w - f},${y} L${x + n.w},${y + f} L${x + n.w},${y + n.h} L${x},${y + n.h} Z" fill="#fff" stroke="#000"/>`, `<path d="M${x + n.w - f},${y} L${x + n.w - f},${y + f} L${x + n.w},${y + f}" fill="none" stroke="#000"/>`);
    n.lines.forEach((l, i) => {
      const m = l.match(EXT_HEAD_RE);
      const body = m ? `<tspan font-weight="bold">${esc(m[1])}</tspan>${esc(m[2])}` : esc(l);
      o.push(`<text x="${x + 7}" y="${y + 15 + i * NOTE_LH}" font-family="Helvetica, Arial, sans-serif" font-size="10">${body}</text>`);
    });
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${Math.ceil(L.width)}" height="${Math.ceil(L.height)}" viewBox="0 0 ${Math.ceil(L.width)} ${Math.ceil(L.height)}">
<defs>
<marker id="tri" markerWidth="14" markerHeight="14" refX="13" refY="7" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L14,7 L0,14 Z" fill="#fff" stroke="#000"/></marker>
<marker id="open" markerWidth="12" markerHeight="12" refX="11" refY="6" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L12,6 L0,12" fill="none" stroke="#000"/></marker>
</defs>
<rect width="100%" height="100%" fill="#fff"/>
${o.join('\n')}
</svg>
`;
}

// ---------------------------------------------------------------- PNG: draw.io (diagram-builder) → rsvg → qlmanage (macOS) → playwright
export async function renderPng(drawioFile, svgFile) {
  const png = drawioFile.replace(/\.drawio$/, '.png');
  const tries = [];
  const builder = path.resolve(HERE, '../../diagram-builder/scripts/drawio.mjs');
  if (fs.existsSync(builder)) {
    try {
      const mod = await import(pathToFileURL(builder).href);
      const out = mod.exportDrawio(drawioFile, { format: 'png' });
      return { png: out, via: 'draw.io (diagram-builder)' };
    } catch (e) { tries.push(`draw.io: ${e.message}`); }
  }
  if (svgFile && fs.existsSync(svgFile)) {
    let r = spawnSync('rsvg-convert', ['-o', png, svgFile], { encoding: 'utf8' });
    if (r.status === 0) return { png, via: 'rsvg-convert' };
    tries.push(`rsvg-convert: ${r.error?.message || r.stderr || 'exit ' + r.status}`);
    if (process.platform === 'darwin') {
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ucov-'));
      r = spawnSync('qlmanage', ['-t', '-s', '2400', '-o', tmp, svgFile], { encoding: 'utf8' });
      const made = path.join(tmp, path.basename(svgFile) + '.png');
      if (fs.existsSync(made)) { fs.copyFileSync(made, png); return { png, via: 'qlmanage' }; }
      tries.push(`qlmanage: ${r.error?.message || r.stderr || 'không ra file'}`);
    }
    try {
      const { chromium } = createRequire(path.join(process.cwd(), 'x.js'))('playwright'); // require tôn trọng NODE_PATH, import() thì không
      const browser = await chromium.launch();
      const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 2 });
      await page.goto(pathToFileURL(svgFile).href);
      const el = await page.$('svg');
      await el.screenshot({ path: png });
      await browser.close();
      return { png, via: 'playwright' };
    } catch (e) { tries.push(`playwright: ${e.message.split('\n')[0]}`); }
  }
  return { png: null, via: null, tries };
}

// ---------------------------------------------------------------- lint tầng 0
export function lintModel(model) {
  const F = [];
  // refs (tuỳ chọn): phần tử bị nêu — "uc:<id>", "actor:<id>", "assoc:<actor>><uc>", "include:<base>><part>", "extend:<extending>><base>",
  // "ucgen:<child>><parent>" — để công cụ review (uc-review.mjs) đánh dấu đúng chỗ trên hình của khách
  const push = (level, rule, msg, refs) => F.push(refs && refs.length ? { level, rule, msg, refs } : { level, rule, msg });
  const err = (rule, msg, refs) => push('ERROR', rule, msg, refs);
  const warn = (rule, msg, refs) => push('WARN', rule, msg, refs);
  const actors = model.actors || [], ucs = model.usecases || [];
  const isVi = /^vi/i.test(String(model.lang || ''));
  if (!model.subject?.name) err('ov subject', 'thiếu subject.name (tên hệ thống trên boundary)');
  if (!actors.length) err('ov actor', 'không có actor');
  if (!ucs.length) err('ov usecase', 'không có use case');
  const aid = new Set(actors.map((a) => a.id)), uid = new Set(ucs.map((u) => u.id));
  for (const d of uniq(ucs.map((u) => u.id).filter((x, i, arr) => arr.indexOf(x) !== i))) err('ov dup', `id use case trùng: ${d}`);
  // so tên giữ dấu tiếng Việt ("Thêm" ≠ "Thâm"), bỏ hoa/thường, khoảng trắng, dấu câu
  const normU = (s) => String(s || '').normalize('NFC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
  for (const d of uniq(ucs.map((u) => normU(u.name)).filter((x, i, arr) => x && arr.indexOf(x) !== i))) warn('ov dup-name', `hai use case cùng tên "${ucs.find((u) => normU(u.name) === d).name}" — gộp hoặc đổi tên`, ucs.filter((u) => normU(u.name) === d).map((u) => `uc:${u.id}`));
  for (const x of model.associations || []) {
    if (!aid.has(x.actor)) err('ov assoc', `association trỏ actor không có: ${x.actor}`);
    if (!uid.has(x.usecase)) err('ov assoc', `association trỏ use case không có: ${x.usecase}`);
  }
  for (const x of model.includes || []) for (const k of ['base', 'part']) if (!uid.has(x[k])) err('ov include', `include.${k} trỏ use case không có: ${x[k]}`);
  for (const x of model.extends || []) for (const k of ['extending', 'base']) if (!uid.has(x[k])) err('ov extend', `extends.${k} trỏ use case không có: ${x[k]}`);
  // kế thừa ACTOR ghi nhầm vào generalizations (chỉ dành cho use case) — lỗi hay gặp của model sinh tự động (LMSERP oneworld 24/10/2026)
  for (const x of model.generalizations || []) for (const k of ['child', 'parent']) if (!uid.has(x[k])) err('ov ucgen', aid.has(x[k])
    ? `generalizations.${k} "${x[k]}" là ACTOR — kế thừa actor ghi ở actorParents {"${x.child}": "${x.parent}"}; generalizations chỉ dành cho use case`
    : `generalizations.${k} trỏ use case không có: ${x[k]}`);
  for (const [c, p] of Object.entries(model.actorParents || {})) {
    if (!aid.has(c)) err('ov actor-gen', `actorParents: con "${c}" không có trong actors`);
    if (!aid.has(p)) err('ov actor-gen', `actorParents: cha "${p}" không có trong actors`);
  }
  // subsystemGoals: khoá = tên phân hệ có thật (usecases[].subsystem/package). Phân hệ đổi tên/gộp mà khoá không đổi theo thì tên mục tiêu
  // không bao giờ được dùng, hình tóm tắt lặng lẽ ra "Quản lý <phân hệ>" (vmc-core 26/10/2026: "Trợ lý AI", "Báo cáo quản trị" ↔ "Báo cáo và AI")
  const subsAll = uniq(ucs.map((u) => u.subsystem || u.package).filter(Boolean));
  const wordsOf = (s) => new Set(String(s).normalize('NFC').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 1 && !['và', 'and', 'the', 'of', 'của'].includes(w)));
  for (const [k, v] of Object.entries(model.subsystemGoals || {})) {
    if (subsAll.includes(k)) continue;
    const kw = wordsOf(k), near = subsAll.filter((x) => [...wordsOf(x)].some((w) => kw.has(w)));
    warn('ov subsystem-goal', `subsystemGoals["${k}"] = "${v}" không khớp phân hệ nào nên không bao giờ được dùng — phân hệ có: ${subsAll.map((x) => `"${x}"`).join(', ') || '(chưa UC nào khai subsystem)'}${near.length ? `; gần nhất: ${near.map((x) => `"${x}"`).join(', ')}` : ''}. Đổi khoá cho trùng đúng tên phân hệ`);
  }
  const A = analyze(model);
  // CSDL/máy chủ của CHÍNH hệ thống nằm trong ranh giới, không phải actor (cùng luật [own-store] của context diagram).
  // "Database Administrator" / "Quản trị CSDL" là vai người → không báo.
  const OWN_STORE = /(^|\s)(database|db|cơ sở dữ liệu|csdl)(\s|$)|^(the\s+)?(server|máy chủ|backend|back-end|back end)$/i;
  const HUMAN_ROLE = /(admin|administrator|manager|operator|engineer|officer|quản trị|nhân viên|kỹ sư)/i;
  for (const a of actors) {
    const n = A.assoc.filter((x) => x.actor === a.id).length;
    const an = String(a.name || '').normalize('NFC');
    if (!n && !A.parentActors.has(a.id) && !(a.id in A.parents)) err('ov actor-lonely', `actor "${a.name}" không nối use case nào và không là cha/con trong actorParents`, [`actor:${a.id}`]);
    if (an && !/^\p{Lu}/u.test(an) && !/^\p{Ll}+\p{Lu}/u.test(an)) warn('ov actor-name', `actor "${a.name}": viết hoa chữ đầu (tên vai)`, [`actor:${a.id}`]);
    if (/^(system|hệ thống)$/i.test(an)) err('ov actor-system', `"${a.name}" là subject, không phải actor`, [`actor:${a.id}`]);
    else if (OWN_STORE.test(an) && !HUMAN_ROLE.test(an)) warn('ov actor-system', `"${a.name}": CSDL/máy chủ của chính hệ thống nằm TRONG ranh giới, không phải actor — chỉ giữ nếu là kho của hệ khác, khi đó đặt tên theo hệ sở hữu (vd "Hệ thống kế toán")`, [`actor:${a.id}`]);
  }
  // Tên mở đầu bằng DANH TỪ ("Thông tin sản phẩm", "Product Information", "Hệ thống quản lý…"): UC là việc actor làm → Động từ + Danh từ.
  // Chỉ liệt kê từ chắc chắn là danh từ; từ vừa là động từ (Báo cáo, Thống kê, Thông báo, Cài đặt, Report, List, Order, Screen, Form) không báo.
  const NOUN_START = new RegExp('^(the\\s+)?(' + [
    'thông tin', 'danh sách', 'trang(?!\\s+(trí|bị|điểm|hoàng))', 'màn hình', 'giao diện', 'hệ thống(?!\\s+h(oá|óa))', 'biểu mẫu', 'bảng điều khiển',
    'dữ liệu', 'chi tiết(?!\\s+h(oá|óa))', 'lịch sử', 'hồ sơ', 'tài khoản', 'sản phẩm', 'đơn hàng', 'người dùng', 'phân hệ', 'chức năng', 'module',
    'system', 'management', 'information', 'info', 'details?', 'data', 'page', 'dashboard', 'registration', 'authentication', 'authorization',
    'configuration', 'notification', 'administration', 'user', 'product', 'account', 'settings', 'homepage', 'history', 'statistics', 'analytics',
  ].join('|') + ')(\\s|$)', 'i');
  const subjN = normU(model.subject?.name);
  for (const u of ucs) {
    // UC đặt đúng tên hệ thống ("Academy", "Library Management System") là cả hệ thống, không phải một việc
    if (subjN && normU(u.name) === subjN) err('ov uc-subject', `${u.id} "${u.name}" trùng tên hệ thống (subject) — UC là một việc cụ thể`, [`uc:${u.id}`]);
    const direct = A.directActors(u.id).length;
    if (!direct && !A.hostOf(u.id)) err('ov uc-lonely', `use case ${u.id} "${u.name}" không có actor và không là con/part/extending của UC nào — mồ côi trên hình`, [`uc:${u.id}`]);
    const w = String(u.name || '').trim().split(/\s+/);
    if (w.length < 2 && !/^(log ?in|log ?out|register|sign ?up|sign ?in|authenticate)$/i.test(u.name || '')) warn('ov usecase-name', `${u.id} "${u.name}": tên UC nên là Động từ + Danh từ (≥ 2 từ)`, [`uc:${u.id}`]);
    else if (!/^\p{Lu}/u.test(w[0])) warn('ov usecase-name', `${u.id} "${u.name}": viết hoa chữ đầu`, [`uc:${u.id}`]);
    else if (NOUN_START.test(String(u.name).normalize('NFC'))) warn('ov usecase-name', `${u.id} "${u.name}": mở đầu bằng danh từ — UC là việc actor làm, đặt Động từ + Danh từ (vd "Xem thông tin sản phẩm", "View Product Details")`, [`uc:${u.id}`]);
    // ngôn ngữ nhãn theo model (`lang`, như engine use-case-diagram): mặc định en; `lang: "vi"` cho phép tiếng Việt
    if (!isVi && /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/i.test(u.name || '')) err('lang', `${u.id} "${u.name}": model không khai \`"lang": "vi"\` nên tên trên diagram phải tiếng Anh`, [`uc:${u.id}`]);
  }
  for (const g of A.gens) if (A.gens.some((h) => h.child === g.parent && h.parent === g.child)) err('ov ucgen', `generalization vòng ${g.child} ↔ ${g.parent}`, [`ucgen:${g.child}>${g.parent}`]);
  for (const x of A.includes) if (A.includes.some((y) => y.base === x.part && y.part === x.base)) err('ov include', `include vòng ${x.base} ↔ ${x.part}`, [`include:${x.base}>${x.part}`]);
  // --- lint theo review UML 2.5 / nghiệp vụ (WARN — sửa ở model tầng 1)
  if (ucs.length > 12) warn('uml overview-size', `${ucs.length} UC trong một hình tổng — hình mẫu dễ đọc có 7–12; chạy \`build --detail parents\` để ẩn UC con/part/extending không actor, và dùng hình tầng 1 theo phân hệ trong SRS`);
  // «extend» lấy từ code: điều kiện = câu if gọi phần mở rộng (file:dòng ghi vào evidence), viết bằng lời nghiệp vụ; nhánh còn lối vào riêng
  // (màn/nút riêng) thì giữ association và ghi standalone. Bài mẫu: references/worked-examples.md (LMSERP: Record Deposit «extend» Collect Payment).
  const hasVal = (v) => (Array.isArray(v) ? v.length > 0 : !!String(v || '').trim());
  const fromCode = ucs.some((u) => hasVal(u.evidence) || hasVal(u.routes));
  const CODE_COND = /==|!=|&&|\|\||->|\$\w|\w\(\)|\b[a-z]+_[a-z0-9_]+\b|\b[a-z]+[A-Z]\w*\b|\b(true|false|null|nil|undefined)\b/;
  // extendDetails (full | condition | none): đề không đòi phần nào thì không vẽ và không nhắc phần đó (A.extend đã bỏ sẵn theo mức)
  const xd = extendDetailsOf(model);
  if (model.extendDetails !== undefined && model.extendDetails !== true && model.extendDetails !== false && !EXTEND_DETAILS.includes(String(model.extendDetails).trim().toLowerCase())) warn('ov extend-details', `extendDetails "${model.extendDetails}" không hợp lệ — dùng "full" (mặc định: điều kiện + extension point), "condition" (chỉ điều kiện) hoặc "none" (chỉ mũi tên «extend»); đang vẽ như "full"`);
  const ucName = new Map(ucs.map((u) => [u.id, u.name]));
  for (const x of A.extend) {
    const ref = `extend:${x.extending}>${x.base}`;
    if (xd === 'full' && !x.point) warn('uml extend-point', `«extend» ${x.extending} → ${x.base}: chưa khai extension point (extends[].point — hoặc extensionPoint như engine use-case-diagram; UML 2.5): BƯỚC trong luồng của UC gốc nơi nhánh chen vào (vd "After Sign-in") — ellipse gốc sẽ không có ngăn "extension points". Đề không đòi extension point thì ghi "extendDetails": "condition" trong model`, [ref]);
    else if (xd === 'full' && normU(x.point) === normU(ucName.get(x.extending))) warn('uml extend-point', `«extend» ${x.extending} → ${x.base}: extension point "${x.point}" trùng tên UC mở rộng — extension point là BƯỚC trong luồng của UC gốc nơi nhánh chen vào (vd "After Sign-in"), không phải tên UC mở rộng`, [ref]);
    // UML 2.5 cho phép extend không điều kiện (luôn chạy khi tới extension point), nhưng người chấm SRS hay coi là lỗi → WARN (trừ khi model khai đề không đòi)
    if (xd !== 'none' && !x.condition) warn('uml extend-cond', `«extend» ${x.extending} → ${x.base}: chưa ghi điều kiện (extends[].condition) — UML cho phép bỏ nhưng người chấm hay trừ điểm; ghi khi nào nhánh chạy, vd {khách nhập mã giảm giá hợp lệ}. Chỉ khi đề/giảng viên không đòi điều kiện mới ghi "extendDetails": "none" (hình chỉ còn mũi tên «extend»)`, [ref]);
    else if (x.condition && CODE_COND.test(String(x.condition))) warn('uml extend-cond-code', `«extend» ${x.extending} → ${x.base}: điều kiện "${x.condition}" viết kiểu code — viết lời nghiệp vụ người đọc SRS hiểu (vd {mật khẩu do quản trị viên đặt}); tên trường/biến ghi vào extends[].evidence`, [ref]);
    if (x.condition && fromCode && !hasVal(x.evidence)) warn('uml extend-evidence', `«extend» ${x.extending} → ${x.base} {${x.condition}}: chưa có evidence — model lấy từ code thì điều kiện phải là câu if gọi phần mở rộng; ghi extends[].evidence = "file:dòng …", đừng đoán`, [ref]);
    const same = A.directActors(x.extending).filter((a) => A.directActors(x.base).includes(a));
    if (same.length && !hasVal(x.standalone)) warn('biz extend-actor', `${x.extending} «extend» ${x.base} nhưng ${same.join(', ')} nối thẳng cả gốc lẫn nhánh mở rộng — nếu là biến thể thì dùng generalization, nếu là bước tuỳ chọn thì bỏ association của nhánh; nếu code có lối vào riêng cho nhánh (màn/nút riêng) thì giữ association và ghi extends[].standalone = "file:dòng …"`, [...same.map((a) => `assoc:${a}>${x.extending}`), ref]);
  }
  const VI_VERB = /^(quản lý|cập nhật|đặt lại|kiểm tra|từ chối|sắp xếp|đăng nhập|đăng xuất|đăng ký|khôi phục|phê duyệt|phát hành|tạo|xem|xóa|xoá|sửa|gửi|duyệt|gán|đổi|thêm|in|xuất|nhập|thu|ghi|lập|huỷ|hủy)\s+/i;
  const objectOf = (name) => {
    const s0 = String(name || '').trim();
    if (isVi) { const m = s0.match(VI_VERB); return m ? s0.slice(m[0].length).toLowerCase() : ''; }
    return s0.split(/\s+/).slice(1).filter((w) => !/^(a|an|the)$/i.test(w)).join(' ').toLowerCase().replace(/s$/, '');
  };
  // chỉ báo khi một bên là "Manage X" (ô CRUD) và bên kia là động từ cụ thể trên cùng X — hai mức trừu tượng chồng nhau
  // (Manage Payments vs Collect Payment). Hai động từ khác nhau (Take/View Attendance, Reserve/Renew a book) là hai mục tiêu riêng → không báo.
  const isManage = (u) => /^(manage\b|quản lý\s)/i.test(u.name || '');
  const manage = ucs.filter((u) => /^(manage\b|quản lý\s)/i.test(u.name));
  // "có CRUD bên trong" = có UC con generalization HOẶC tự gom ≥ 2 route (Quản lý SEO bài viết: GET/POST/DELETE ngay trên UC)
  const withKids = manage.filter((u) => A.gens.some((g) => g.parent === u.id) || (Array.isArray(u.routes) && u.routes.length >= 2));
  if (withKids.length && withKids.length < manage.length) warn('biz uneven', `mức trừu tượng không đều: ${withKids.map((u) => `"${u.name}"`).join(', ')} có UC con (generalization) còn ${manage.filter((u) => !withKids.includes(u)).map((u) => `"${u.name}"`).join(', ')} thì không — gom CRUD dưới UC cha cho đồng nhất hoặc bỏ con`, manage.filter((u) => !withKids.includes(u)).map((u) => `uc:${u.id}`));
  // "có quan hệ" = nối trực tiếp HOẶC là anh em cùng cha / cùng base (Create/Edit Student dưới Manage Students; Add/Update/Delete item cùng được Session include)
  const hostsOfL = (u) => [...A.gens.filter((g) => g.child === u).map((g) => g.parent), ...A.includes.filter((x) => x.part === u).map((x) => x.base), ...A.extend.filter((x) => x.extending === u).map((x) => x.base)];
  const depsOfL = (u) => [...A.gens.filter((g) => g.parent === u).map((g) => g.child), ...A.includes.filter((x) => x.base === u).map((x) => x.part), ...A.extend.filter((x) => x.base === u).map((x) => x.extending)];
  const related = (a, b) => A.includes.some((x) => (x.base === a && x.part === b) || (x.base === b && x.part === a)) || A.extend.some((x) => (x.extending === a && x.base === b) || (x.extending === b && x.base === a)) || A.gens.some((g) => (g.child === a && g.parent === b) || (g.child === b && g.parent === a))
    || hostsOfL(a).some((h) => hostsOfL(b).includes(h)) || depsOfL(a).some((d) => depsOfL(b).includes(d));
  for (let i = 0; i < ucs.length; i++) for (let j = i + 1; j < ucs.length; j++) {
    const oa = objectOf(ucs[i].name), ob = objectOf(ucs[j].name);
    // cùng actor mới là chồng mức trừu tượng; khác actor (Khách gửi phản hồi / Quản trị quản lý phản hồi) là hai mục tiêu riêng
    const shareActor = A.directActors(ucs[i].id).some((a) => A.directActors(ucs[j].id).includes(a));
    if (oa && oa.length > 3 && oa === ob && isManage(ucs[i]) !== isManage(ucs[j]) && shareActor && !related(ucs[i].id, ucs[j].id)) warn('biz same-object', `"${ucs[i].name}" và "${ucs[j].name}" cùng đối tượng "${oa}" nhưng không có quan hệ — nếu một cái là bước/biến thể của cái kia thì nối include/extend/generalization, không thì cân nhắc gộp`, [`uc:${ucs[i].id}`, `uc:${ucs[j].id}`]);
  }
  // "được phép" ≠ "làm": Policy before()/super-admin cho qua mọi quyền không có nghĩa actor đó theo đuổi mọi mục tiêu
  for (const a of actors) {
    if (A.parentActors.has(a.id)) continue;
    const n = A.assoc.filter((x) => x.actor === a.id).length;
    if (n >= 8 && n / Math.max(1, ucs.length) > 0.5) warn('biz superuser', `"${a.name}" nối ${n}/${ucs.length} UC — thường là quyền siêu quản trị (Policy before(), super-admin) bị vẽ thành trách nhiệm; UC diagram vẽ việc actor THỰC SỰ làm: giữ UC quản trị, bỏ association tới việc của vai khác`, [`actor:${a.id}`]);
  }
  // checklist review sơ đồ AI, mục 5 (chi tiết bịa): UC phải truy được về nguồn (file:dòng, biên bản, yêu cầu)
  // nguồn = evidence hoặc routes (engine ghi route "GET /api/…"); UC cha gom con (generalization) có nguồn khi MỌI con có nguồn
  const own = (u) => [u.evidence, u.routes].some((v) => (Array.isArray(v) ? v.length > 0 : !!String(v || '').trim()));
  const byIdEv = new Map(ucs.map((u) => [u.id, u]));
  const hasEv = (u, seen = new Set()) => {
    if (own(u)) return true;
    if (seen.has(u.id)) return false; seen.add(u.id);
    const kids = A.gens.filter((g) => g.parent === u.id).map((g) => byIdEv.get(g.child)).filter(Boolean);
    return kids.length > 0 && kids.every((k) => hasEv(k, seen));
  };
  const noEv = ucs.filter((u) => !hasEv(u));
  if (ucs.length && noEv.length === ucs.length && ucs.length >= 5) warn('ai evidence', `không UC nào có evidence — model có thể do AI đoán; ghi usecases[].evidence (file:dòng hoặc nguồn yêu cầu) trước khi đưa hình vào SRS`);
  else if (noEv.length && noEv.length < ucs.length) warn('ai evidence', `${noEv.length}/${ucs.length} UC không có evidence (có thể do AI thêm): ${noEv.slice(0, 12).map((u) => `${u.id} "${u.name}"`).join(', ')}${noEv.length > 12 ? ', …' : ''}`);
  if (!A.includes.length && !A.extend.length && !A.gens.length && ucs.length >= 8) warn('ov relations', `${ucs.length} UC mà không có include/extend/generalization nào — hình tổng FPT thường có; soát lại tầng 1 (merge sẽ gom quan hệ từ các file module)`);
  if (ucs.length > 60) warn('ov size', `${ucs.length} UC — hình rất lớn; vẫn vẽ đủ, SRS kèm hình tầng 1 theo module để đọc chi tiết`);
  return F;
}

/** Đối chiếu .drawio đã sinh với model: đủ actor/UC/quan hệ, không thừa. */
export function lintDrawio(drawioXml, model, expect = {}) {
  const F = [];
  const ids = (re) => [...drawioXml.matchAll(re)].map((m) => m[1]);
  const ucIds = new Set(ids(/<mxCell id="uc_([^"]+)"/g)), acIds = new Set(ids(/<mxCell id="actor_([^"]+)"/g));
  for (const u of model.usecases || []) if (!ucIds.has(u.id)) F.push({ level: 'ERROR', rule: 'ov drawio', msg: `use case ${u.id} không có trong .drawio` });
  for (const a of model.actors || []) if (!acIds.has(a.id)) F.push({ level: 'ERROR', rule: 'ov drawio', msg: `actor ${a.id} không có trong .drawio` });
  for (const id of ucIds) if (!(model.usecases || []).some((u) => u.id === id)) F.push({ level: 'ERROR', rule: 'ov drawio', msg: `.drawio có uc_${id} không có trong model` });
  const A = analyze(model);
  const n = (re) => ids(re).length;
  const pairs = [[n(/<mxCell id="(assoc\d+)"/g), A.assoc.length, 'association'], [n(/<mxCell id="(inc\d+)"/g), A.includes.length, 'include'], [n(/<mxCell id="(ext\d+)"/g), A.extend.length, 'extend'], [n(/<mxCell id="(ucgen\d+)"/g), A.gens.length, 'generalization UC'], [n(/<mxCell id="(gen\d+)"/g), expect.genActor ?? Object.keys(A.parents).length, 'generalization actor']];
  for (const [have, want, label] of pairs) if (have !== want) F.push({ level: 'ERROR', rule: 'ov drawio', msg: `.drawio có ${have} ${label}, model có ${want}` });
  return F;
}

function printFindings(F, label) {
  for (const f of F) console.log(`${f.level} [${f.rule}] ${f.msg}`);
  const e = F.filter((f) => f.level === 'ERROR').length, w = F.length - e;
  console.log(`${e ? 'FAIL' : 'OK'}: ${label} — ${e} error, ${w} warning`);
  return e ? 1 : 0;
}

// ---------------------------------------------------------------- lệnh
/**
 * --common note: UC mà MỌI actor dùng (Login, Logout, Change Password…) gom thành một ghi chú dưới boundary thay cho actor cha
 * + dây kế thừa. (a) actor cha gốc mà ≥ 2 actor lá kế thừa và chỉ giữ UC không quan hệ; (b) UC không quan hệ mà mọi actor lá (≥ 3) nối thẳng.
 * Model không đổi — đây chỉ là cách vẽ; actor cha vẫn nằm trong model và trong hình cây (--actor-tree separate).
 */
export function commonAsNote(model) {
  const actors = model.actors || [], assoc = model.associations || [], ucs = model.usecases || [];
  const par = model.actorParents || {};
  const parentIds = new Set(Object.values(par));
  const leaves = actors.filter((a) => !parentIds.has(a.id));
  const rootOf = (id) => { let x = id; const seen = new Set(); while (par[x] && !seen.has(x)) { seen.add(x); x = par[x]; } return x; };
  const rel = new Set([...(model.includes || []).flatMap((x) => [x.base, x.part]), ...(model.extends || []).flatMap((x) => [x.extending, x.base]), ...(model.generalizations || []).flatMap((x) => [x.child, x.parent])]);
  const nameOf = (id) => (ucs.find((u) => u.id === id) || {}).name || id;
  const drop = new Set(), dropActors = new Set(), notes = [];
  for (const p of actors.filter((a) => parentIds.has(a.id) && !par[a.id])) {
    const kids = leaves.filter((a) => rootOf(a.id) === p.id);
    const own = assoc.filter((x) => x.actor === p.id).map((x) => x.usecase);
    if (kids.length < 2 || !own.length) continue;
    if (!own.every((u) => !rel.has(u) && assoc.every((x) => x.usecase !== u || x.actor === p.id))) continue; // cha còn UC có quan hệ → giữ kiểu FPT
    own.forEach((u) => drop.add(u)); dropActors.add(p.id);
    const vi = /^vi/i.test(String(model.lang || ''));
    const who = kids.length === leaves.length ? (vi ? 'Mọi actor' : 'every actor') : `${kids.map((k) => k.name).join(', ')} (is-a ${p.name})`;
    notes.push(vi ? `${who} đều dùng: ${own.map(nameOf).join(', ')}` : `Used by ${who}: ${own.map(nameOf).join(', ')}`);
  }
  if (leaves.length >= 3) {
    const every = ucs.filter((u) => !drop.has(u.id) && !rel.has(u.id) && leaves.every((a) => assoc.some((x) => x.actor === a.id && x.usecase === u.id)));
    if (every.length) { every.forEach((u) => drop.add(u.id)); notes.push(/^vi/i.test(String(model.lang || '')) ? `Mọi actor đều dùng: ${every.map((u) => u.name).join(', ')}` : `Used by every actor: ${every.map((u) => u.name).join(', ')}`); }
  }
  return {
    model: { ...model, actors: actors.filter((a) => !dropActors.has(a.id)), usecases: ucs.filter((u) => !drop.has(u.id)),
      associations: assoc.filter((x) => !drop.has(x.usecase) && !dropActors.has(x.actor)),
      actorParents: Object.fromEntries(Object.entries(par).filter(([c, q]) => !dropActors.has(c) && !dropActors.has(q))) },
    notes, hidden: [...drop].map((u) => `${u} ${nameOf(u)}`),
  };
}

/**
 * --detail summary (mức tóm tắt, Cockburn "summary goal"): actor nối > threshold UC (thường là siêu quản trị) thì các UC riêng
 * của nó gom theo `usecases[].subsystem` (hoặc `package`) thành MỘT UC tóm tắt mỗi phân hệ ("Quản lý <phân hệ>" /
 * "Manage <subsystem>", đổi tên bằng `subsystemGoals`). UC dùng chung với actor khác giữ nguyên. Chạy sau parentsOnly.
 */
export function summaryView(model, opts = {}) {
  const T = opts.threshold ?? 12;
  const isVi = /^vi/i.test(String(model.lang || ''));
  const A = analyze(model);
  const ucs = model.usecases || [];
  const byId = new Map(ucs.map((u) => [u.id, u]));
  const subOf = (u) => (u && (u.subsystem || u.package)) || null;
  const heavy = (model.actors || []).filter((a) => A.assoc.filter((x) => x.actor === a.id).length > T).map((a) => a.id);
  const groups = new Map(); // sub → {members:Set, actors:Set}
  for (const a of heavy) for (const x of A.assoc.filter((y) => y.actor === a)) {
    const sub = subOf(byId.get(x.usecase));
    if (!sub || A.directActors(x.usecase).some((o) => !heavy.includes(o))) continue;
    if (!groups.has(sub)) groups.set(sub, { members: new Set(), actors: new Set() });
    groups.get(sub).members.add(x.usecase); groups.get(sub).actors.add(a);
  }
  for (const [sub, g] of [...groups]) if (g.members.size < 2) groups.delete(sub); // một UC thì giữ nguyên, không cần tóm tắt
  if (!groups.size) return { model, summaries: [], note: null, defaults: [] };
  const lc = (t) => t.charAt(0).toLowerCase() + t.slice(1);
  const slug = (t) => String(t).normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/gi, 'd').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const collapsed = new Map(), summaries = [], defaults = [];
  for (const [sub, g] of groups) {
    const id = `SUM-${slug(sub)}`;
    const goal = (model.subsystemGoals || {})[sub];
    const name = goal || (isVi ? `Quản lý ${lc(sub)}` : `Manage ${sub}`);
    if (!goal) defaults.push({ sub, name, n: g.members.size });
    const members = [...g.members];
    members.forEach((u) => collapsed.set(u, id));
    summaries.push({ id, name, subsystem: sub, summary: true, members, evidence: members.flatMap((u) => [].concat(byId.get(u).evidence || [])).slice(0, 20), _actors: [...g.actors] });
  }
  const keep = (u) => !collapsed.has(u);
  const out = { ...model,
    usecases: [...ucs.filter((u) => keep(u.id)), ...summaries.map(({ _actors, ...u }) => u)],
    associations: [...(model.associations || []).filter((x) => keep(x.usecase)), ...summaries.flatMap((u) => u._actors.map((a) => ({ actor: a, usecase: u.id })))],
    includes: (model.includes || []).filter((x) => keep(x.base) && keep(x.part)),
    extends: (model.extends || []).filter((x) => keep(x.extending) && keep(x.base)),
    generalizations: (model.generalizations || []).filter((x) => keep(x.child) && keep(x.parent)) };
  // tên mục tiêu (subsystemGoals) khác tên phân hệ → ghi rõ UC nào ứng với hình phân hệ nào, người đọc mới tìm được hình chi tiết
  const total = [...collapsed.keys()].length;
  const map = summaries.map((u) => `"${u.name}" → ${u.subsystem}`).join('; ');
  const note = defaults.length === summaries.length
    ? (isVi
      ? `UC tóm tắt (${summaries.length}): mỗi UC "Quản lý …" gom các UC của một phân hệ (tổng ${total} UC) — chi tiết ở hình phân hệ cùng tên.`
      : `Summary use cases (${summaries.length}): each "Manage …" groups ${total} use cases by subsystem — see the subsystem diagram of the same name.`)
    : (isVi
      ? `UC tóm tắt (${summaries.length}) gom ${total} UC theo phân hệ — chi tiết ở hình phân hệ: ${map}.`
      : `Summary use cases (${summaries.length}) group ${total} use cases by subsystem — details in the subsystem diagrams: ${map}.`);
  return { model: out, summaries: summaries.map((u) => `${u.name} (${u.members.length})`), note, defaults };
}

/**
 * --detail goals (mức mục tiêu người dùng — Larman "Manage <X>", Cockburn sea level): chỉ ẩn UC con CRUD của UC cha "Manage/Quản lý X"
 * (Tạo/Thêm/Cập nhật/Sửa/Xoá/Xem/Liệt kê… không có actor riêng). Nhánh is-a không phải CRUD (Xem nội dung công khai ◁ Xem tin tức) GIỮ.
 * «include»/«extend» chạm UC con bị ẩn được NÂNG lên UC cha (kể cả extension point/điều kiện), bỏ vòng tự trỏ và trùng.
 */
const CRUD_VERB = /^(create|add|new|insert|update|edit|modify|delete|remove|view|list|read|show|get|tạo|thêm|cập nhật|sửa|chỉnh sửa|xóa|xoá|xem|liệt kê)(\s|$)/i;
const MANAGE_RE = /^(manage|quản lý)(\s|$)/i;
export function goalsView(model) {
  const A = analyze(model);
  const ucs = model.usecases || [];
  const byId = new Map(ucs.map((u) => [u.id, u]));
  const up = new Map();
  for (const g of model.generalizations || []) {
    const c = byId.get(g.child), p = byId.get(g.parent);
    if (c && p && MANAGE_RE.test(p.name || '') && CRUD_VERB.test(c.name || '') && !A.directActors(c.id).length) up.set(c.id, p.id);
  }
  const to = (id) => up.get(id) || id;
  const seen = new Set(), dedupe = (k) => (seen.has(k) ? false : (seen.add(k), true));
  const includes = (model.includes || []).map((x) => ({ ...x, base: to(x.base), part: to(x.part) })).filter((x) => x.base !== x.part && dedupe(`i|${x.base}|${x.part}`));
  const extendsL = (model.extends || []).map((x) => ({ ...x, extending: to(x.extending), base: to(x.base) })).filter((x) => x.extending !== x.base && dedupe(`e|${x.extending}|${x.base}`));
  return { model: { ...model, usecases: ucs.filter((u) => !up.has(u.id)), associations: (model.associations || []).filter((x) => !up.has(x.usecase)),
    includes, extends: extendsL, generalizations: (model.generalizations || []).filter((g) => !up.has(g.child)) },
    hidden: [...up.keys()].map((u) => `${u} ${byId.get(u).name}`), remapped: (model.includes || []).length + (model.extends || []).length - includes.length - extendsL.length };
}

/**
 * Actor nối > heavy UC (siêu quản trị) vẽ thành NHIỀU ký hiệu cùng tên, mỗi ký hiệu một cụm UC theo `subsystem` (UML cho phép một actor
 * xuất hiện nhiều lần trên hình; Thinhnotes 3.5) — thay một chùm 40 đường bằng 3–4 quạt ~10 đường. Cụm đầu ở phía của actor; cụm sau
 * sang phía đang nhẹ hơn để hình cân. Kế thừa actor chỉ vẽ từ ký hiệu đầu.
 */
export function splitHeavyActors(model, opts = {}) {
  const heavy = opts.heavy ?? 15, cap = opts.cap ?? 12;
  const A = analyze(model);
  const ucs = model.usecases || [];
  const byId = new Map(ucs.map((u) => [u.id, u]));
  const weight = (u) => 1 + A.gens.filter((g) => g.parent === u).length; // con không actor nằm cột trong → cùng số hàng
  const load = { left: 0, right: 0 };
  for (const a of model.actors || []) if (a.side === 'left' || a.side === 'right') load[a.side] += A.assoc.filter((x) => x.actor === a.id).reduce((s_, x) => s_ + weight(x.usecase), 0);
  const actors = [...(model.actors || [])], assoc = (model.associations || []).map((x) => ({ ...x }));
  const copies = [];
  for (const a of model.actors || []) {
    const mine = A.assoc.filter((x) => x.actor === a.id).map((x) => x.usecase);
    if (mine.length <= heavy) continue;
    const groups = new Map();
    for (const u of mine) { const k = (byId.get(u) || {}).subsystem || (byId.get(u) || {}).package || '·'; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(u); }
    const bins = [];
    for (const g of [...groups.values()].sort((x, y) => y.reduce((s_, u) => s_ + weight(u), 0) - x.reduce((s_, u) => s_ + weight(u), 0))) {
      const w = g.reduce((s_, u) => s_ + weight(u), 0);
      const fit = bins.find((b) => b.w + w <= cap);
      if (fit) { fit.us.push(...g); fit.w += w; } else bins.push({ us: [...g], w });
    }
    if (bins.length < 2) continue;
    const own = a.side === 'left' || a.side === 'right' ? a.side : 'right';
    if (a.side === 'left' || a.side === 'right') load[own] -= bins.reduce((s_, b) => s_ + b.w, 0);
    bins.forEach((b, i) => { b.side = i === 0 ? own : (load.left <= load.right ? 'left' : 'right'); load[b.side] += b.w; });
    // ký hiệu GỐC (giữ id + dây kế thừa actor) là cụm nằm cùng phía actor cha — dây is-a ngắn, không vòng quanh khung
    const parentId = (model.actorParents || {})[a.id];
    const pSide = parentId ? ((model.actors || []).find((x) => x.id === parentId) || {}).side : null;
    const keep = Math.max(0, bins.findIndex((b) => b.side === pSide));
    let n = 1;
    bins.forEach((b, i) => {
      if (i === keep) { const k = actors.findIndex((x) => x.id === a.id); actors[k] = { ...a, side: b.side }; return; }
      const id = `${a.id}~${++n}`;
      actors.push({ ...a, id, side: b.side, copyOf: a.id });
      for (const x of assoc) if (x.actor === a.id && b.us.includes(x.usecase)) x.actor = id;
      copies.push(`${a.name} #${n}: ${b.us.length} UC (${b.side === 'left' ? 'trái' : 'phải'})`);
    });
  }
  return { model: { ...model, actors, associations: assoc }, copies };
}

/** Kiểm chéo tầng 0 ↔ tầng 1 (checklist: tên khớp giữa các hình): UC hình tổng không có ở module nào, và ngược lại. */
export function crossTier(modelFile, model) {
  const dir = path.dirname(path.resolve(modelFile));
  const F = [];
  if (!isOverviewModel(modelFile, model)) return F;
  const files = fs.readdirSync(dir).filter((n) => n.endsWith('.model.json') && !/^role-/i.test(n)).map((n) => path.join(dir, n));
  const tier1 = [];
  for (const f of files) { let j; try { j = JSON.parse(fs.readFileSync(f, 'utf8')); } catch { continue; } if (!isOverviewModel(f, j) && Array.isArray(j.usecases)) tier1.push([f, j]); }
  if (!tier1.length) return F;
  const names1 = new Map();
  for (const [f, j] of tier1) for (const u of j.usecases) names1.set(norm(u.name), path.basename(f));
  const names0 = new Set((model.usecases || []).map((u) => norm(u.name)));
  const only0 = (model.usecases || []).filter((u) => !names1.has(norm(u.name)));
  const only1 = [...names1.keys()].filter((n) => !names0.has(n));
  if (only0.length) F.push({ level: 'WARN', rule: 'xc tier1', msg: `${only0.length} UC trên hình tổng không có ở model tầng 1 nào (${tier1.map(([f]) => path.basename(f)).join(', ')}): ${only0.map((u) => `"${u.name}"`).join(', ')} — thêm vào module kèm evidence, hoặc bỏ khỏi hình tổng` });
  if (only1.length) F.push({ level: 'WARN', rule: 'xc tier1', msg: `${only1.length} UC ở tầng 1 không có trên hình tổng: ${only1.slice(0, 15).map((n) => `"${n}" (${names1.get(n)})`).join(', ')}${only1.length > 15 ? ', …' : ''} — chạy lại \`merge\` hoặc ghi lý do bỏ` });
  return F;
}

/** --detail parents: hình tổng chỉ giữ UC có actor (ẩn con/part/extending không actor — chúng thuộc hình tầng 1). */
export function parentsOnly(model) {
  const A = analyze(model);
  const keep = new Set((model.usecases || []).filter((u) => A.directActors(u.id).length).map((u) => u.id));
  const hidden = (model.usecases || []).filter((u) => !keep.has(u.id)).map((u) => `${u.id} ${u.name}`);
  return { model: { ...model, usecases: model.usecases.filter((u) => keep.has(u.id)), associations: (model.associations || []).filter((x) => keep.has(x.usecase)),
    includes: (model.includes || []).filter((x) => keep.has(x.base) && keep.has(x.part)), extends: (model.extends || []).filter((x) => keep.has(x.extending) && keep.has(x.base)),
    generalizations: (model.generalizations || []).filter((x) => keep.has(x.child) && keep.has(x.parent)) }, hidden };
}

/** Hình nhỏ riêng cho cây kế thừa actor (--actor-tree separate): cha trên, con hàng ngang dưới, thanh chung, một tam giác. */
export function actorTreeDiagram(model) {
  const A = analyze(model);
  const parents = [...A.parentActors];
  if (!parents.length) return null;
  const name = (id) => (A.actors.find((a) => a.id === id) || { name: id }).name;
  const boxes = new Map(); const edges = [];
  // cây nhiều tầng (Khách ◁ Người dùng ◁ Quản trị viên): gốc trên cùng, mỗi tầng một hàng, cha canh giữa trên các con.
  // Chuỗi thuần (≥ 3 tầng, mỗi tầng 1 actor) vẽ BẬC THANG (mỗi tầng lùi sang phải): dọc thẳng thì cao/rộng ≈ 3, ngang thì rộng/cao ≈ 5 —
  // cả hai trượt luật docs-fit (ảnh cắt sát nội dung); bậc thang cho khung gần vuông, dây kế thừa vẫn đi lên vào đáy cha.
  const kidsOf = (p) => Object.entries(A.parents).filter(([, pp]) => pp === p).map(([c]) => c);
  const roots = parents.filter((p) => !(p in A.parents));
  const depthOf = (n) => { let d = 0, x0 = n; const seen = new Set(); while (A.parents[x0] && !seen.has(x0)) { seen.add(x0); x0 = A.parents[x0]; d++; } return d; };
  const all = uniq([...parents, ...Object.keys(A.parents)]);
  const maxDepth = Math.max(0, ...all.map(depthOf));
  const breadth = Math.max(...Array.from({ length: maxDepth + 1 }, (_, d) => all.filter((n) => depthOf(n) === d).length));
  const stair = maxDepth >= 2 && breadth === 1, horizontal = false, stepX = 120;
  const pitch = 140, levelH = ACTOR_H + ACTOR_LABEL_H + 70;
  const levelW = Math.max(170, ...all.map((n) => labelW(name(n)) + 70)), slotH = ACTOR_H + ACTOR_LABEL_H + 40;
  const spanOf = (n) => { const k = kidsOf(n); return k.length ? k.reduce((s_, c) => s_ + spanOf(c), 0) : (horizontal ? slotH : Math.max(pitch, labelW(name(n)) + 30)); };
  const placeNode = (n, o0, depth) => {
    const k = kidsOf(n);
    let c = o0 + spanOf(n) / 2;
    if (k.length) { let oo = o0; const cs = k.map((ch) => { const r = placeNode(ch, oo, depth + 1); oo += spanOf(ch); return r; }); c = (cs[0] + cs[cs.length - 1]) / 2; }
    if (horizontal) boxes.set(n, { x: 40 + depth * levelW + (levelW - ACTOR_W) / 2, y: c - ACTOR_H / 2, w: ACTOR_W, h: ACTOR_H, name: name(n) });
    else boxes.set(n, { x: (stair ? 40 + labelW(name(roots[0])) / 2 + depth * stepX : c - ACTOR_W / 2), y: 30 + depth * levelH, w: ACTOR_W, h: ACTOR_H, name: name(n) });
    return c;
  };
  let x = horizontal ? 30 : 40;
  for (const r of roots) { placeNode(r, x, 0); x += spanOf(r) + 60; }
  for (const [c, p] of Object.entries(A.parents)) {
    const C = boxes.get(c), P = boxes.get(p);
    if (!C || !P) continue;
    if (horizontal) {
      // con bên phải → cạnh trái con đi sang trái, gặp thanh dọc chung rồi vào sườn phải cha (một tam giác ở cha)
      const cy = C.y + C.h / 2, py = P.y + P.h / 2, midX = P.x + P.w + (C.x - (P.x + P.w)) / 2;
      edges.push({ id: `gen_${c}`, kind: 'gen', source: `actor_${c}`, target: `actor_${p}`, from: [C.x - 6, cy], to: [P.x + P.w + 6, py], exit: [0, 0.5], entry: [1, 0.5], entryDy: 0, points: Math.abs(cy - py) < 1 ? [] : [[midX, cy], [midX, py]] });
      continue;
    }
    const cx = C.x + C.w / 2, pcx = P.x + P.w / 2, pBottom = P.y + ACTOR_H + ACTOR_LABEL_H + 2, barY = P.y + ACTOR_H + ACTOR_LABEL_H + 22;
    edges.push({ id: `gen_${c}`, kind: 'gen', source: `actor_${c}`, target: `actor_${p}`, from: [cx, C.y], to: [pcx, pBottom], exit: [0.5, 0], entry: [0.5, 1], entryDy: ACTOR_LABEL_H + 2, points: Math.abs(cx - pcx) < 1 ? [] : [[cx, barY], [pcx, barY]] });
  }
  let W = horizontal ? 40 + (maxDepth + 1) * levelW + 30 : stair ? Math.max(...[...boxes.values()].map((b) => b.x + b.w / 2 + labelW(b.name) / 2)) + 40 : x, H = Math.max(...[...boxes.values()].map((b) => b.y)) + ACTOR_H + ACTOR_LABEL_H + 40;
  // khổ vừa trang tài liệu (luật docs-fit của kickoff-uml: cao/rộng ≤ 2.2, rộng/cao ≤ 3): nới cạnh ngắn và canh giữa nội dung
  const shift = (dx, dy) => {
    for (const b of boxes.values()) { b.x += dx; b.y += dy; }
    for (const e of edges) { e.from = [e.from[0] + dx, e.from[1] + dy]; e.to = [e.to[0] + dx, e.to[1] + dy]; e.points = e.points.map((q) => [q[0] + dx, q[1] + dy]); }
  };
  if (W / H > 2.8) { const H2 = Math.ceil(W / 2.8); shift(0, (H2 - H) / 2); H = H2; }
  if (H / W > 2.0) { const W2 = Math.ceil(H / 2.0); shift((W2 - W) / 2, 0); W = W2; }
  W = Math.ceil(W); H = Math.ceil(H);
  const cells = ['<mxCell id="0"/>', '<mxCell id="1" parent="0"/>'];
  for (const [id, b] of boxes) cells.push(`<mxCell id="actor_${id}" value="${esc(b.name)}" style="shape=umlActor;verticalLabelPosition=bottom;verticalAlign=top;html=1;outlineConnect=0;fontSize=11;" vertex="1" parent="1"><mxGeometry x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" as="geometry"/></mxCell>`);
  for (const e of edges) {
    const pts = e.points.length ? `<Array as="points">${e.points.map((p) => `<mxPoint x="${p[0]}" y="${p[1]}"/>`).join('')}</Array>` : '';
    cells.push(`<mxCell id="${e.id}" value="" style="${EDGE_STYLE.gen}exitX=${e.exit[0]};exitY=${e.exit[1]};exitDx=0;exitDy=0;entryX=${e.entry[0]};entryY=${e.entry[1]};entryDx=0;entryDy=${e.entryDy};${e.entryDy ? 'entryPerimeter=0;' : ''}" edge="1" parent="1" source="${e.source}" target="${e.target}"><mxGeometry relative="1" as="geometry">${pts}</mxGeometry></mxCell>`);
  }
  const drawio = `<mxfile host="drawio" agent="kickoff-uml usecase-overview (actor tree)" version="31.4.5">\n  <diagram id="Actor-tree" name="Actor generalization">\n    <mxGraphModel dx="800" dy="400" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${W}" pageHeight="${H}" math="0" shadow="0">\n      <root>\n        ${cells.join('\n        ')}\n      </root>\n    </mxGraphModel>\n  </diagram>\n</mxfile>\n`;
  const o = [];
  for (const [, a] of boxes) {
    const cx = a.x + a.w / 2, top = a.y;
    o.push(`<circle cx="${cx}" cy="${top + 8}" r="8" fill="#fff" stroke="#000"/>`, `<line x1="${cx}" y1="${top + 16}" x2="${cx}" y2="${top + 38}" stroke="#000"/>`, `<line x1="${cx - 15}" y1="${top + 20}" x2="${cx + 15}" y2="${top + 20}" stroke="#000"/>`, `<line x1="${cx}" y1="${top + 38}" x2="${cx - 12}" y2="${top + 60}" stroke="#000"/>`, `<line x1="${cx}" y1="${top + 38}" x2="${cx + 12}" y2="${top + 60}" stroke="#000"/>`, `<text x="${cx}" y="${top + 76}" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="11">${esc(a.name)}</text>`);
  }
  for (const e of edges) o.push(`<polyline points="${[e.from, ...e.points, e.to].map((p) => `${p[0]},${p[1]}`).join(' ')}" fill="none" stroke="#000" marker-end="url(#tri)"/>`);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs><marker id="tri" markerWidth="14" markerHeight="14" refX="13" refY="7" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L14,7 L0,14 Z" fill="#fff" stroke="#000"/></marker></defs><rect width="100%" height="100%" fill="#fff"/>\n${o.join('\n')}\n</svg>\n`;
  return { drawio, svg };
}

async function cmdBuild(file, flags) {
  const full = readJson(file);
  let F = [...lintModel(full), ...crossTier(file, full)];
  let model = full, hidden = [], footNotes = [];
  if (flags.common === 'note') { const c = commonAsNote(full); model = c.model; footNotes = c.notes; if (c.hidden.length) console.log(`--common note: ${c.hidden.length} UC chung → ghi chú dưới hình: ${c.hidden.join('; ')}`); else console.log('--common note: không có UC nào mọi actor cùng dùng — hình giữ nguyên'); }
  if (flags.detail === 'goals') {
    const gv = goalsView(model);
    model = gv.model; hidden = gv.hidden;
    console.log(`--detail goals: ẩn ${hidden.length} UC con CRUD của "Manage/Quản lý X"${gv.remapped ? `, nâng ${gv.remapped} include/extend trùng lên UC cha` : ''}; giữ ${model.usecases.length} UC (nhánh is-a không phải CRUD vẫn vẽ)`);
    if (!flags['no-split']) {
      const sp = splitHeavyActors(model);
      model = sp.model;
      if (sp.copies.length) console.log(`tách actor nặng thành nhiều ký hiệu theo phân hệ: ${sp.copies.join('; ')}`);
    }
    F = F.filter((f) => f.rule !== 'uml overview-size');
    if (model.usecases.length > 40) F.push({ level: 'WARN', rule: 'uml overview-size', msg: `${model.usecases.length} UC ở mức mục tiêu — hình khổ lớn (A2–A1); bản một trang: --detail summary` });
  }
  if (flags.detail === 'parents' || flags.detail === 'summary') {
    ({ model, hidden } = parentsOnly(model));
    // đã ẩn UC con rồi thì cảnh báo kích thước phải nói về hình thật sự được vẽ
    F = F.filter((f) => f.rule !== 'uml overview-size');
    if (flags.detail === 'summary') {
      const sv = summaryView(model, { threshold: flags['summary-threshold'] ? Number(flags['summary-threshold']) : undefined });
      model = sv.model;
      if (sv.summaries.length) { footNotes.push(sv.note); console.log(`--detail summary: ${sv.summaries.length} UC tóm tắt — ${sv.summaries.join('; ')}`); }
      if (sv.defaults.length) {
        console.log(`--detail summary: ${sv.defaults.length} UC tóm tắt dùng tên mặc định (chưa có subsystemGoals): ${sv.defaults.map((d) => `"${d.name}" ← "${d.sub}"`).join('; ')}`);
        // phân hệ nhiều chủ đề ("Báo cáo và AI") → "Quản lý báo cáo và AI" không nói actor đạt được gì
        for (const d of sv.defaults.filter((x) => /\s(và|and)\s|[&,/]/i.test(x.sub))) F.push({ level: 'WARN', rule: 'ov subsystem-goal', msg: `UC tóm tắt "${d.name}" gom ${d.n} UC của phân hệ nhiều chủ đề "${d.sub}" — đặt subsystemGoals["${d.sub}"] (Động từ + Danh từ: actor đạt được gì), hoặc tách phân hệ nếu là hai mục tiêu khác nhau` });
      }
      else console.log('--detail summary: không actor nào quá ngưỡng (hoặc UC thiếu subsystem) — giữ mức parents');
      F = F.filter((f) => !['biz superuser', 'ai evidence'].includes(f.rule) || true);
    }
    if (model.usecases.length > 12) F.push({ level: 'WARN', rule: 'uml overview-size', msg: `còn ${model.usecases.length} UC sau --detail ${flags.detail} (ẩn ${hidden.length}) — hình tổng vẫn dày; ${flags.detail === 'parents' ? 'thử --detail summary (gom theo phân hệ cho actor > 12 UC), ' : ''}hoặc gom thêm CRUD dưới UC cha (luật 4)` });
  }
  const primary = flags.primary ? String(flags.primary).split(',').map((x) => x.trim()).filter(Boolean) : null;
  const L = layout(model, { sides: flags.sides, parent: flags.parent, primary, actorTree: flags['actor-tree'], footNotes });
  const out = flags.out || file.replace(/\.model\.json$/, '').replace(/\.json$/, '') + '.drawio';
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const meta = { model: path.relative(path.dirname(out), file) || path.basename(file), detail: flags.detail, 'actor-tree': flags['actor-tree'], common: flags.common };
  fs.writeFileSync(out, toDrawio(model, L, meta));
  let svg = null;
  if (flags.svg || flags.png) { svg = out.replace(/\.drawio$/, '.svg'); fs.writeFileSync(svg, toSvg(model, L)); }
  F.push(...lintDrawio(fs.readFileSync(out, 'utf8'), model, { genActor: flags['actor-tree'] === 'separate' ? 0 : undefined }));
  const A = analyze(model);
  console.log(`overview: ${model.usecases.length} UC, ${model.actors.length} actor, ${A.assoc.length} association, ${A.includes.length} include, ${A.extend.length} extend, ${A.gens.length} gen UC, ${Object.keys(A.parents).length} gen actor → ${out}${svg ? ` + ${path.basename(svg)}` : ''}`);
  if (hidden.length && flags.detail !== 'goals') console.log(`--detail ${flags.detail}: ẩn ${hidden.length} UC không actor (xem hình tầng 1): ${hidden.join('; ')}`);
  if (flags['actor-tree'] === 'separate') {
    const t = actorTreeDiagram({ ...full });
    if (t) { const tOut = out.replace(/\.drawio$/, '.actors.drawio'); fs.writeFileSync(tOut, t.drawio); if (svg) fs.writeFileSync(tOut.replace(/\.drawio$/, '.svg'), t.svg); console.log(`actor tree → ${tOut} (hình chính không vẽ generalization actor)`); }
  }
  const exNotes = (L.notes || []).filter((n) => n.kind === 'ext').length;
  if (exNotes) console.log(`ghi chú: ${exNotes} điều kiện «extend» viết trong note gắn vào đường extend (UML 2.5)`);
  const xdl = extendDetailsOf(model);
  if (xdl !== 'full' && A.extend.length) console.log(`extendDetails "${xdl}": «extend» vẽ ${xdl === 'none' ? 'chỉ mũi tên' : 'kèm điều kiện, không ngăn extension points'} — condition/point vẫn giữ trong model`);
  console.log(`đường: ${L.stats.straight} thẳng (không cắt hình), ${L.stats.routed} đi vòng tránh ellipse${L.stats.blocked ? `, ${L.stats.blocked} không tìm được đường — vẽ thẳng` : ''}`);
  if (L.stats.blocked) F.push({ level: 'WARN', rule: 'ov route', msg: `${L.stats.blocked} đường không định tuyến được (bị vây kín) — vẽ thẳng, có thể cắt ellipse` });
  if (flags.png) {
    const r = await renderPng(out, svg);
    if (r.png) console.log(`png: ${r.png} (${r.via})`);
    else console.log(`WARN [ov png] không render được PNG: ${r.tries.join(' | ')} — dùng \`uml.mjs run\` (draw.io) hoặc mở .svg`);
  }
  return printFindings(F, path.basename(out));
}

export function drawioMeta(xml) {
  const m = xml.match(/<mxfile[^>]*\skickoff="([^"]*)"/);
  const meta = {};
  if (m) for (const kv of m[1].split(';')) { const i = kv.indexOf('='); if (i > 0) meta[kv.slice(0, i)] = kv.slice(i + 1).replace(/&amp;/g, '&'); }
  return meta;
}

function cmdCheck(file, flags = {}) {
  let modelFile = file, drawio = null, meta = {};
  if (file.endsWith('.drawio')) {
    if (/\.actors\.drawio$/.test(file)) { console.log(`OK: ${path.basename(file)} — hình phụ (cây kế thừa actor), kiểm qua hình chính ${path.basename(file).replace(/\.actors\.drawio$/, '.drawio')}`); return 0; }
    drawio = file;
    const xml = fs.readFileSync(drawio, 'utf8');
    meta = drawioMeta(xml);
    const dir = path.dirname(file), stem = path.basename(file, '.drawio');
    const cands = [];
    if (flags.model) cands.push(String(flags.model));
    if (meta.model) cands.push(path.resolve(dir, meta.model));
    // biến thể `overview-parents.drawio` → bóc dần hậu tố "-x" để tìm overview.model.json
    for (let s2 = stem; s2; s2 = s2.includes('-') ? s2.slice(0, s2.lastIndexOf('-')) : '') cands.push(path.join(dir, `${s2}.model.json`), path.join(dir, `${s2}.json`));
    modelFile = cands.find((c) => fs.existsSync(c));
    if (!modelFile) { console.log(`ERROR [ov check] không thấy model cho ${path.basename(file)} (thử: ${[...new Set(cands.map((c) => path.basename(c)))].join(' / ')}) — chỉ bằng --model <file>`); console.log(`FAIL: ${path.basename(file)} — 1 error, 0 warning`); return 1; }
  }
  const full = readJson(modelFile);
  const F = [...lintModel(full), ...crossTier(modelFile, full)];
  if (drawio) {
    const detail = flags.detail || meta.detail, tree = flags['actor-tree'] || meta['actor-tree'], common = flags.common || meta.common;
    let model = common === 'note' ? commonAsNote(full).model : full;
    if (detail === 'goals') { model = goalsView(model).model; if (!flags['no-split']) model = splitHeavyActors(model).model; }
    if (detail === 'parents' || detail === 'summary') model = parentsOnly(model).model;
    if (detail === 'summary') model = summaryView(model).model;
    if (detail || tree || common) console.log(`check: ${path.basename(drawio)} là biến thể${common ? ` --common ${common}` : ''}${detail ? ` --detail ${detail}` : ''}${tree ? ` --actor-tree ${tree}` : ''} của ${path.basename(modelFile)}`);
    F.push(...lintDrawio(fs.readFileSync(drawio, 'utf8'), model, { genActor: tree === 'separate' ? 0 : undefined }));
  }
  return printFindings(F, path.basename(drawio || modelFile));
}

function cmdMerge(dir, flags) {
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) { console.log(`ERROR [ov merge] không phải thư mục: ${dir}`); return 2; }
  const out = flags.out || path.join(dir, 'overview.model.json');
  const { model, notes } = mergeModels(dir, fs.existsSync(out) ? out : null);
  if (!model.usecases.length) { console.log(`ERROR [ov merge] ${dir}: không có *.model.json nào có usecases`); return 1; }
  if (flags.primary) {
    // luật 1: trái = actor hệ thống phục vụ (quyết định nghiệp vụ của Tường), phải = actor vận hành + hệ ngoài
    const prim = new Set(String(flags.primary).split(',').map((x) => x.trim()).filter(Boolean));
    const parentsSet = new Set(Object.values(model.actorParents || {}));
    for (const a of model.actors) if (!parentsSet.has(a.id)) a.side = prim.has(a.id) ? 'left' : 'right';
    const unknown = [...prim].filter((x) => !model.actors.some((a) => a.id === x));
    if (unknown.length) notes.push(`--primary có actor không tồn tại: ${unknown.join(', ')}`);
  }
  fs.writeFileSync(out, JSON.stringify(model, null, 2) + '\n');
  console.log(`merge: ${model._merged_from.join(', ')} → ${out}: ${model.usecases.length} UC, ${model.actors.length} actor, ${model.associations.length} association, ${model.includes.length} include, ${model.extends.length} extend, ${model.generalizations.length} gen UC`);
  for (const n of notes) console.log(`WARN [ov merge] ${n}`);
  return printFindings(lintModel(model), path.basename(out));
}

const HELP = `usecase-overview.mjs — Overall Use Case Diagram (tầng 0) cho kickoff-uml
  merge <usecase/> [--out overview.model.json] [--primary A,B]   gộp mọi file tầng 1 (bỏ role-*) thành model tầng 0, khớp UC theo tên; --primary ghi side
  build <overview.model.json> [--out f.drawio] [--svg] [--png] [--primary A,B] [--parent bottom|tree] [--sides balanced|affinity|left]
        --primary: actor CHÍNH (hệ phục vụ) → trái, còn lại → phải (ghi đè "side" trong model); không có thì dùng "side" của model, rồi mới cân
        --parent: cha is-a ở đáy (mẫu FPT, mặc định) hoặc cây trên con cùng phía (mẫu Library)
        --detail parents: ẩn UC con/part/extending không có actor (hình tổng 7–12 UC; chi tiết để hình tầng 1)
        --detail goals [--no-split]: mức mục tiêu (Larman): chỉ ẩn UC con CRUD của "Manage/Quản lý X", giữ nhánh is-a khác, nâng include/extend lên cha; actor > 15 UC tách thành nhiều ký hiệu theo phân hệ
        --detail summary [--summary-threshold 12]: như parents, rồi actor nối > ngưỡng UC thì gom UC riêng theo usecases[].subsystem thành một UC tóm tắt mỗi phân hệ;
        tên = subsystemGoals["<phân hệ>"] (khoá trùng đúng usecases[].subsystem — lệch thì [ov subsystem-goal]), không có thì "Quản lý <phân hệ>"
        --actor-tree separate: hình chính bỏ dây kế thừa actor, xuất thêm <out>.actors.drawio là cây kế thừa riêng
        --common note: UC mọi actor dùng (Login/Logout/Change Password qua actor cha) thành một ghi chú dưới boundary, bỏ actor cha + dây kế thừa
        extends[].condition/point → note gắn vào đường «extend» (UML 2.5); model.notes: ["…"] → ghi chú dưới hình
        model.extendDetails: "full" (mặc định: điều kiện + ngăn extension points) | "condition" (chỉ điều kiện) | "none" (chỉ mũi tên «extend»)
        — đề không đòi thì tắt; chỉ đổi hình + lint, dữ liệu trong model giữ nguyên
  check <overview.model.json | overview.drawio> [--model f.json] [--detail parents] [--actor-tree separate]
        .drawio do build sinh ra tự nhớ model và biến thể (thuộc tính kickoff trên <mxfile>); file đã sửa tay trong draw.io thì chỉ bằng cờ
Tầng 0: một boundary, mọi UC chi tiết cụm theo actor, đủ include/extend/generalization, actor cha ở đáy.`;

export async function main(argv) {
  const args = parseArgs(argv);
  const [cmd, target] = args._;
  if (!cmd || args.flags.help || !target) { console.log(HELP); return cmd ? 2 : 0; }
  try {
    if (cmd === 'build') return await cmdBuild(target, args.flags);
    if (cmd === 'check') return cmdCheck(target, args.flags);
    if (cmd === 'merge') return cmdMerge(target, args.flags);
    console.log(HELP); return 2;
  } catch (e) {
    console.error(`ERROR [ov] ${e.message}`);
    return e.code || 2;
  }
}

if (process.argv[1] && fs.existsSync(process.argv[1]) && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
