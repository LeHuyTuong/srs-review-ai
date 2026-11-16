#!/usr/bin/env node
/**
 * uc-review.mjs — chế độ REVIEW cho Use Case Diagram người khác vẽ (khách gửi .drawio hoặc ảnh).
 *
 * Bên trong (khách không thấy): hình → bản chép model.json (cùng schema usecase-overview) → lint tầng 0
 *   + lỗi ký hiệu/vị trí đọc thẳng từ .drawio + nhận định của AI (ai.json) → danh sách phát hiện có `refs` tới phần tử.
 * Cho khách: KHÔNG lộ mã lint hay checklist. Hai kiểu output:
 *   --mode errors  "Chỉ ra lỗi": chính hình của khách, số tại chỗ sai + bảng chú thích; <base>.review.md lời thường
 *   --mode fix     "Vẽ lại":     sửa model (tự động + theo ai.json) rồi vẽ lại bằng renderer tầng 0; <base>.fixed.md cùng số
 * "Lỗi" chỉ dành cho điều máy kiểm chắc chắn. Điều AI suy luận và chỗ đọc ảnh chưa chắc là "Nên xem lại".
 *
 *   node uc-review.mjs parse  <in.drawio> [--out f.model.json] [--page N]
 *   node uc-review.mjs review <in.drawio | bản-chép.model.json> [--image ảnh-gốc.png] [--ai ai.json]
 *                             [--mode errors|fix|both] [--out-dir dir] [--lang vi|en] [--page N]
 * Quy trình đầy đủ (bước AI, schema ai.json, chép model từ ảnh): ../references/review-mode.md
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { lintModel, layout, toDrawio, toSvg, renderPng, EXTEND_DETAILS } from './usecase-overview.mjs';

const RED = '#D32F2F', AMBER = '#E08600';
const SEV_COLOR = { error: RED, review: AMBER };
const CIRCLED = '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳';
export const circled = (n) => (n >= 1 && n <= 20 ? CIRCLED[n - 1] : `(${n})`);
const uniq = (a) => [...new Set(a)];
const VI_CHARS = /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/i;

// ================================================================ XML tối giản (không phụ thuộc gói ngoài)
const ENT = { lt: '<', gt: '>', amp: '&', quot: '"', apos: "'", nbsp: ' ' };
export function decodeEntities(s) {
  return String(s ?? '').replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e) => {
    if (e[0] === '#') { const n = /^#x/i.test(e) ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10); return Number.isFinite(n) ? String.fromCodePoint(n) : all; }
    return ENT[e.toLowerCase()] ?? all;
  });
}
const escAttr = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/\n/g, '&#10;');
const escText = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function parseXml(xml) {
  const doc = { tag: '#doc', attrs: {}, children: [], text: '' };
  const stack = [doc];
  const re = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|<!DOCTYPE[^>]*>|<\/([^\s>]+)\s*>|<([^\s/>!?]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>|([^<]+)/g;
  let m;
  while ((m = re.exec(xml))) {
    const top = stack[stack.length - 1];
    if (m[2] !== undefined) { for (let i = stack.length - 1; i > 0; i--) if (stack[i].tag === m[2]) { stack.length = i; break; } }
    else if (m[3] !== undefined) {
      const node = { tag: m[3], attrs: {}, children: [], text: '' };
      for (const a of (m[4] || '').matchAll(/([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) node.attrs[a[1]] = decodeEntities(a[2] ?? a[3]);
      top.children.push(node);
      if (!m[5]) stack.push(node);
    } else if (m[1] !== undefined) top.text += m[1];
    else if (m[6] !== undefined) top.text += decodeEntities(m[6]);
  }
  return doc;
}
export function serializeXml(n) {
  if (n.tag === '#doc') return n.children.map(serializeXml).join('');
  const attrs = Object.entries(n.attrs).map(([k, v]) => ` ${k}="${escAttr(v)}"`).join('');
  const inner = (n.text && n.text.trim() ? escText(n.text) : '') + n.children.map(serializeXml).join('');
  return inner ? `<${n.tag}${attrs}>${inner}</${n.tag}>` : `<${n.tag}${attrs}/>`;
}
const findTag = (n, tag) => { if (n.tag === tag) return n; for (const c of n.children) { const r = findTag(c, tag); if (r) return r; } return null; };

/** draw.io nén trang: base64(deflateRaw(encodeURIComponent(xml))); bản cũ không encodeURIComponent. */
export function inflateDiagram(b64) {
  const buf = Buffer.from(b64.replace(/\s+/g, ''), 'base64');
  let out;
  try { out = zlib.inflateRawSync(buf); } catch { out = zlib.inflateSync(buf); }
  const raw = out.toString('utf8');
  return /^\s*%3C/i.test(raw) ? decodeURIComponent(raw) : raw;
}
export function drawioPages(xmlText) {
  const doc = parseXml(xmlText);
  const pages = [];
  const mxfile = findTag(doc, 'mxfile');
  const diagrams = mxfile ? mxfile.children.filter((c) => c.tag === 'diagram') : [];
  for (const d of diagrams) {
    let gm = d.children.find((c) => c.tag === 'mxGraphModel');
    if (!gm && d.text.trim()) { try { gm = findTag(parseXml(inflateDiagram(d.text.trim())), 'mxGraphModel'); } catch { gm = null; } }
    if (gm) pages.push({ name: d.attrs.name || `Trang ${pages.length + 1}`, model: gm, index: diagrams.indexOf(d) });
  }
  if (!diagrams.length) { const gm = findTag(doc, 'mxGraphModel'); if (gm) pages.push({ name: 'Trang 1', model: gm, index: 0 }); }
  return pages;
}
export function parseStyle(st) {
  const m = { _base: [] };
  for (const part of String(st || '').split(';')) {
    if (!part.trim()) continue;
    const i = part.indexOf('=');
    if (i < 0) m._base.push(part.trim()); else m[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return m;
}
/** Nhãn HTML của draw.io → chữ thường; <hr> (ngăn extension points) thành dòng "—". */
const HTML_TAG = /<\/?(br|div|span|p|b|i|u|s|font|hr|strong|em|sup|sub|li|ul|ol|table|tbody|tr|td|th|h\d|a|pre|code|blockquote)\b[^>]*>/i;
export function labelText(v) {
  // «include» gõ tay dạng <<include>> không phải thẻ HTML — đổi sang « » trước khi bóc thẻ
  const stereo = (x) => x.replace(/<<\s*([^<>]*?)\s*>>/g, '«$1»');
  let s = stereo(String(v || ''));
  if (HTML_TAG.test(s)) s = s.replace(/<br\s*\/?>/gi, '\n').replace(/<\/(div|p|li|tr|h\d)>/gi, '\n').replace(/<hr[^>]*>/gi, '\n—\n').replace(/<[^>]+>/g, '');
  s = stereo(decodeEntities(s));
  return s.replace(/ /g, ' ').split('\n').map((l) => l.replace(/\s+/g, ' ').trim()).filter(Boolean).join('\n');
}

function cellsOf(gm) {
  const root = gm.children.find((c) => c.tag === 'root');
  const out = [];
  for (const n of root ? root.children : []) {
    let cell, attrs, wrapper = null;
    if (n.tag === 'mxCell') { cell = n; attrs = n.attrs; }
    else if (n.tag === 'UserObject' || n.tag === 'object') {
      cell = n.children.find((c) => c.tag === 'mxCell'); if (!cell) continue;
      wrapper = n; attrs = { ...cell.attrs, id: n.attrs.id, value: n.attrs.label ?? n.attrs.value ?? cell.attrs.value ?? '' };
    } else continue;
    const g = cell.children.find((c) => c.tag === 'mxGeometry');
    const pt = (as) => { const p = g?.children.find((c) => c.tag === 'mxPoint' && c.attrs.as === as); return p ? [Number(p.attrs.x || 0), Number(p.attrs.y || 0)] : null; };
    const arr = g?.children.find((c) => c.tag === 'Array' && c.attrs.as === 'points');
    out.push({
      id: attrs.id, value: attrs.value || '', style: attrs.style || '', st: parseStyle(attrs.style), parent: attrs.parent, source: attrs.source, target: attrs.target,
      vertex: attrs.vertex === '1', edge: attrs.edge === '1', node: cell, wrapper,
      geo: g ? { x: Number(g.attrs.x || 0), y: Number(g.attrs.y || 0), w: Number(g.attrs.width || 0), h: Number(g.attrs.height || 0),
        points: (arr?.children || []).filter((p) => p.tag === 'mxPoint').map((p) => [Number(p.attrs.x || 0), Number(p.attrs.y || 0)]),
        sp: pt('sourcePoint'), tp: pt('targetPoint') } : null,
    });
  }
  return out;
}
/** Toạ độ tuyệt đối: hình trong nhóm/container có toạ độ tương đối với cha. */
function absolutize(cells) {
  const byId = new Map(cells.map((c) => [c.id, c]));
  const isLayer = (c) => c && !c.vertex && !c.edge;
  const originOf = (id, seen = new Set()) => {
    const p = byId.get(id);
    if (!p || isLayer(p) || p.edge || !p.geo || seen.has(id)) return [0, 0];
    seen.add(id);
    const [ox, oy] = originOf(p.parent, seen);
    return [ox + p.geo.x, oy + p.geo.y];
  };
  for (const c of cells) {
    if (!c.geo) continue;
    const [ox, oy] = originOf(c.parent);
    const sh = ([x, y]) => [x + ox, y + oy];
    if (c.vertex && !byId.get(c.parent)?.edge) c.box = { x: c.geo.x + ox, y: c.geo.y + oy, w: c.geo.w, h: c.geo.h };
    if (c.edge) { c.pts = c.geo.points.map(sh); c.sp = c.geo.sp && sh(c.geo.sp); c.tp = c.geo.tp && sh(c.geo.tp); }
  }
  return byId;
}

const isMark = (c) => c.st.vdReview === '1';
const UC_CODE = /^\s*((?:UC|U)[-_ ]?\d+[a-z]?|\d+(?:\.\d+)*)\s*[.:)\-–—]?\s+(?=\S)/i;
const isActorC = (c) => c.vertex && !isMark(c) && (c.st.shape === 'umlActor' || c.st._base.includes('umlActor') || c.st.shape === 'actor');
/** Hộp actor gồm cả tên bên dưới, để khung đánh dấu không cắt ngang chữ (bề rộng chữ ước ≈ 0,58 × cỡ chữ mỗi ký tự). */
const withLabel = (b, name, fs = 12) => {
  const ls = String(name || '').split('\n').filter((s) => s.trim());
  if (!ls.length) return b;
  const w = Math.max(b.w, Math.max(...ls.map((l) => l.length)) * fs * 0.58 + 4);
  return { x: b.x + b.w / 2 - w / 2, y: b.y, w, h: b.h + ls.length * fs * 1.25 + 4 };
};
const isEllipseC = (c) => c.vertex && !isMark(c) && !isActorC(c) && (c.st._base.includes('ellipse') || c.st.shape === 'ellipse');
const isNoteC = (c) => c.vertex && !isMark(c) && (c.st.shape === 'note' || c.st._base.includes('note'));
/** Tam giác vẽ rời làm đầu mũi tên kế thừa (sơ đồ vẽ tay). */
const isTriC = (c) => c.vertex && !isMark(c) && (c.st.shape === 'triangle' || c.st._base.includes('triangle'));
const isTextC = (c) => c.vertex && (c.st._base.includes('text') || c.st._base.includes('edgeLabel') || c.st._base.includes('label'));
// khung hệ thống ứng viên: hình chữ nhật/swimlane NHÌN THẤY được (nhóm "group" và hộp không viền không nền thì không phải khung)
const invisible = (c) => c.st._base.includes('group') || (c.st.strokeColor === 'none' && (!c.st.fillColor || c.st.fillColor === 'none'));
const isFrameC = (c) => c.vertex && !isMark(c) && c.box && !isActorC(c) && !isEllipseC(c) && !isNoteC(c) && !isTextC(c) && !invisible(c) && c.st.shape !== 'umlFrame' && c.box.w >= 80 && c.box.h >= 80;
const center = (b) => [b.x + b.w / 2, b.y + b.h / 2];
const inBox = (p, b, pad = 0) => p[0] >= b.x - pad && p[0] <= b.x + b.w + pad && p[1] >= b.y - pad && p[1] <= b.y + b.h + pad;
const distToBox = (p, b) => Math.hypot(Math.max(b.x - p[0], 0, p[0] - b.x - b.w), Math.max(b.y - p[1], 0, p[1] - b.y - b.h));
const segDist = (p, a, b) => { const dx = b[0] - a[0], dy = b[1] - a[1], L = dx * dx + dy * dy; const t = L ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L)) : 0; return Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy); };
const distToLine = (p, line) => { let d = Infinity; for (let i = 1; i < (line || []).length; i++) d = Math.min(d, segDist(p, line[i - 1], line[i])); return d; };
/** Điểm giữa đoạn dài nhất của đường gấp khúc (chỗ đặt số). */
const midOf = (line) => { let bi = 1, bl = -1; for (let i = 1; i < line.length; i++) { const l = Math.hypot(line[i][0] - line[i - 1][0], line[i][1] - line[i - 1][1]); if (l > bl) { bl = l; bi = i; } } const a = line[bi - 1], b = line[bi]; return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]; };
/** Đường p→q có đi XUYÊN ellipse không (co 3px để chạm mép không tính); trả điểm vào đầu tiên. */
function crossPoint(p, q, b) {
  const rx = b.w / 2 - 3, ry = b.h / 2 - 3, cx = b.x + b.w / 2, cy = b.y + b.h / 2;
  if (rx <= 0 || ry <= 0) return null;
  const n = Math.max(8, Math.ceil(Math.hypot(q[0] - p[0], q[1] - p[1]) / 3));
  for (let i = 1; i < n; i++) { const t = i / n, x = p[0] + (q[0] - p[0]) * t, y = p[1] + (q[1] - p[1]) * t; if (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 1) return [x, y]; }
  return null;
}
const arrowOf = (st, end) => { const v = st[end === 't' ? 'endArrow' : 'startArrow']; return v === undefined ? (end === 't' ? 'classic' : 'none') : (v || 'none'); };
const fillOf = (st, end) => { const v = st[end === 't' ? 'endFill' : 'startFill']; return v === undefined ? true : v !== '0'; };
const stereoOf = (lbl) => (/\binclude\b|bao gồm/i.test(lbl) ? 'include' : /\bextends?\b|mở rộng/i.test(lbl) ? 'extend' : /\buses?\b/i.test(lbl) ? 'uses' : null);
const condOf = (lbl) => {
  const rest = lbl.replace(/«[^»]*»|<<[^>]*>>/g, ' ').replace(/\b(include|extends?|uses)\b/gi, ' ');
  const m = rest.match(/\{([^}]+)\}|\[([^\]]+)\]|(?:condition|điều kiện)\s*:?\s*(.+)/i);
  const c = (m ? (m[1] || m[2] || m[3]) : rest).replace(/\s+/g, ' ').trim();
  return c || null;
};

/**
 * Ngưỡng đọc sơ đồ vẽ tay (đơn vị draw.io). Đo trên tệp thật 26/10/2026: đầu đường đặt lệch tới 48 so với actor
 * (hình người mảnh, đường dừng cạnh thân), tam giác đầu mũi tên 10×10 đặt sát mép use case.
 */
export const HAND = { snapNear: 24, snap: 50, snapGap: 15, onTri: 3, triOwner: 12, stub: 25, stubJoin: 20, labelNear: 40 };

/**
 * .drawio → bản chép model (schema usecase-overview) + chỉ mục phần tử → hình (_geom/_cells) + lỗi ký hiệu/vị trí.
 * id: actor A1… (trái → phải), UC UC1… (trên → dưới). refs: "uc:UC1", "actor:A1", "assoc:A1>UC1", "include:<base>><part>",
 * "extend:<extending>><base>", "ucgen:<child>><parent>", "actorgen:<child>><parent>", "edge:<cellId>" (đường không vào model).
 */
export function parseUseCaseDrawio(xmlText, opts = {}) {
  const pages = drawioPages(xmlText);
  if (!pages.length) throw Object.assign(new Error('không thấy sơ đồ (mxGraphModel) trong file .drawio'), { code: 2 });
  const scored = pages.map((p) => { const cs = cellsOf(p.model); return { p, cs, n: cs.filter((c) => isActorC(c) || isEllipseC(c)).length }; });
  const pick = opts.page ? scored[Number(opts.page) - 1] : [...scored].sort((a, b) => b.n - a.n)[0];
  if (!pick) throw Object.assign(new Error(`không có trang ${opts.page}`), { code: 2 });
  const cells = pick.cs;
  const byId = absolutize(cells);
  const texts = cells.filter((c) => isTextC(c) && c.box);
  const actorC = cells.filter((c) => isActorC(c) && c.box).sort((a, b) => a.box.x - b.box.x || a.box.y - b.box.y);
  const ucC = cells.filter((c) => isEllipseC(c) && c.box).sort((a, b) => center(a.box)[1] - center(b.box)[1] || a.box.x - b.box.x);
  const notes = cells.filter((c) => isNoteC(c) && c.box);
  const frames = cells.filter(isFrameC);
  const ref = new Map();
  actorC.forEach((c, i) => ref.set(c.id, `A${i + 1}`));
  ucC.forEach((c, i) => ref.set(c.id, `UC${i + 1}`));
  const idOf = (c) => ref.get(c.id);
  const nameOf = (c, kind) => {
    let t = labelText(c.value);
    if (!t && kind === 'uc') t = texts.filter((x) => inBox(center(x.box), c.box)).map((x) => labelText(x.value)).join(' ');
    if (!t && kind === 'actor') t = texts.filter((x) => { const p = center(x.box); return p[0] > c.box.x - 40 && p[0] < c.box.x + c.box.w + 40 && p[1] > c.box.y + c.box.h - 5 && p[1] < c.box.y + c.box.h + 45; }).map((x) => labelText(x.value)).join(' ');
    return t;
  };
  // khung hệ thống: chứa nhiều UC nhất → ít actor nhất (khung trang bao cả actor thì thua) → nhỏ nhất
  const fr = frames.map((f) => ({ f, n: ucC.filter((u) => inBox(center(u.box), f.box)).length, a: actorC.filter((a) => inBox(center(a.box), f.box)).length }))
    .filter((x) => x.n > 0).sort((p, q) => q.n - p.n || p.a - q.a || p.f.box.w * p.f.box.h - q.f.box.w * q.f.box.h);
  const frame = fr[0]?.f || null;
  let subjectName = '';
  if (frame) {
    subjectName = labelText(frame.value).replace(/\n/g, ' ');
    // ô chữ «include»/«extend» rời (sơ đồ vẽ tay) nằm gần đỉnh khung không phải tên hệ thống
    if (!subjectName) subjectName = texts.filter((x) => inBox(center(x.box), frame.box) && center(x.box)[1] < frame.box.y + Math.max(50, frame.box.h * 0.12) && !stereoOf(labelText(x.value))).map((x) => labelText(x.value)).join(' ').trim();
  }
  const geom = {}, cellOf = {}, notation = [];
  const actors = actorC.map((c) => {
    const id = idOf(c), nm = nameOf(c, 'actor');
    geom[`actor:${id}`] = { box: c.box, full: withLabel(c.box, nm, Number(c.st.fontSize || 12)) }; cellOf[`actor:${id}`] = c.id;
    return { id, name: nm.replace(/\n/g, ' ') };
  });
  const usecases = ucC.map((c) => {
    const id = idOf(c); geom[`uc:${id}`] = { box: c.box }; cellOf[`uc:${id}`] = c.id;
    const [nm, ...rest] = nameOf(c, 'uc').split(/\n?—\n?/);
    const pts = rest.join('\n').split('\n').map((s) => s.trim()).filter((s) => s && !/^(?:extension points?|điểm mở rộng):?$/iu.test(s));
    // mã đứng trước tên ("U1 Log In", "UC01 - Đăng nhập", "UC-3: …", "1. …") giữ riêng ở `code`, tên chỉ còn phần việc
    const full = (nm || '').replace(/\n/g, ' ').trim(), cm = full.match(UC_CODE);
    return { id, name: cm ? full.slice(cm[0].length).trim() : full, ...(cm ? { code: cm[1], prefix: cm[0] } : {}), ...(pts.length ? { extensionPoints: pts } : {}) };
  });
  // ---- đường nối
  const elemOf = (id) => { let c = byId.get(id); const seen = new Set(); while (c && !seen.has(c.id)) { seen.add(c.id); if (isActorC(c) || isEllipseC(c) || isNoteC(c) || frames.includes(c)) return c; c = byId.get(c.parent); } return null; };
  const elems = [...actorC, ...ucC];
  // ---- sơ đồ vẽ tay (Tường 26/10/2026: "có quan hệ rồi mà vẫn kêu lỗi"): sinh viên hay để đầu đường đặt SÁT hình
  // (không gắn), vẽ đầu mũi tên bằng tam giác / đoạn ngắn rời, gõ «include» thành ô chữ rời. Đọc như người nhìn,
  // đếm lại (read) để báo khách — tệp thật 26/10/2026: 74 đường, 68 lỗi báo nhầm → 2 lỗi thật.
  const tris = cells.filter((c) => isTriC(c) && c.box);
  const triOwner = new Map();                                     // tam giác → actor/UC mà nó nằm sát mép
  for (const tr of tris) {
    const half = Math.max(tr.box.w, tr.box.h) / 2;
    let best = null, bd = HAND.triOwner;
    for (const c of elems) { const d = distToBox(center(tr.box), c.box) - half; if (d <= bd) { bd = d; best = c; } }
    if (best) triOwner.set(tr.id, best);
  }
  // đầu đường lỏng: nằm trên tam giác → hình của tam giác; ≤ 24 → hình gần nhất (như cũ); ≤ 50 → chỉ khi gần hẳn một hình
  const snap = (p) => {
    if (!p) return null;
    for (const tr of tris) if (triOwner.has(tr.id) && distToBox(p, tr.box) <= HAND.onTri) return { el: triOwner.get(tr.id), tri: tr };
    const ranked = elems.map((c) => [distToBox(p, c.box), c]).sort((a, b) => a[0] - b[0]);
    const [d0, c0] = ranked[0] || [Infinity, null];
    if (d0 >= HAND.snapNear && (d0 > HAND.snap || (ranked[1] && ranked[1][0] - d0 < HAND.snapGap))) return null;
    return c0 ? { el: c0, tri: null } : null;
  };
  const childLabels = new Map();
  for (const c of cells) { const p = byId.get(c.parent); if (c.vertex && p?.edge) { if (!childLabels.has(p.id)) childLabels.set(p.id, []); childLabels.get(p.id).push(labelText(c.value)); } }
  const looseLabel = new Map();                                   // đường → chữ «include»/«extend» đặt rời cạnh nó
  const ownLabel = (e) => [labelText(e.value), ...(childLabels.get(e.id) || [])].filter(Boolean).join('\n');
  const edgeLabel = (e) => [ownLabel(e), looseLabel.get(e.id)].filter(Boolean).join('\n');
  const perim = (c, toward) => {
    const b = c.box, [cx, cy] = center(b), dx = toward[0] - cx, dy = toward[1] - cy;
    if (!dx && !dy) return [cx, cy];
    if (isEllipseC(c)) { const t = 1 / Math.sqrt((dx / (b.w / 2)) ** 2 + (dy / (b.h / 2)) ** 2); return [cx + dx * t, cy + dy * t]; }
    const t = Math.min(Math.abs(b.w / 2 / (dx || 1e-9)), Math.abs(b.h / 2 / (dy || 1e-9)));
    return [cx + dx * t, cy + dy * t];
  };
  const fixedPt = (c, st, pre) => (st[`${pre}X`] !== undefined && st[`${pre}Y`] !== undefined
    ? [c.box.x + Number(st[`${pre}X`]) * c.box.w + Number(st[`${pre}Dx`] || 0), c.box.y + Number(st[`${pre}Y`]) * c.box.h + Number(st[`${pre}Dy`] || 0)] : null);
  const lineOf = (e, s, t) => {
    const mid = e.pts || [];
    const sC = s ? center(s.box) : e.sp, tC = t ? center(t.box) : e.tp;
    if (!sC || !tC) return null;
    const a = s ? fixedPt(s, e.st, 'exit') || perim(s, mid[0] || tC) : e.sp;
    const b = t ? fixedPt(t, e.st, 'entry') || perim(t, mid[mid.length - 1] || sC) : e.tp;
    return [a, ...mid, b];
  };
  const associations = [], includes = [], extendsL = [], generalizations = [], actorParents = {};
  const seenRel = new Set(), noteLinks = [], assocArrows = [];
  const allLines = new Map();
  let links = 0;
  const read = { snapped: 0, arrowheads: 0, labels: 0 };
  const edgeCells = cells.filter((c) => c.edge && !isMark(c));
  const isEl = (c) => !!c && (isActorC(c) || isEllipseC(c));
  // hai đầu của mỗi đường: gắn vào tam giác có chủ → hình chủ (+ mũi tên kế thừa); gắn → hình chứa; lỏng → snap
  const endOf = (e, w) => {
    const id = w === 's' ? e.source : e.target;
    if (id) { const raw = byId.get(id); return raw && triOwner.has(raw.id) ? { el: triOwner.get(raw.id), tri: raw, snapped: false } : { el: elemOf(id), tri: null, snapped: false }; }
    const sn = snap(w === 's' ? e.sp : e.tp);
    return sn ? { ...sn, snapped: true } : { el: null, tri: null, snapped: false };
  };
  const ends = new Map(edgeCells.map((e) => [e.id, { s: endOf(e, 's'), t: endOf(e, 't') }]));
  const clampTo = (b, p) => [Math.max(b.x, Math.min(b.x + b.w, p[0])), Math.max(b.y, Math.min(b.y + b.h, p[1]))];
  /** Vị trí một đầu đường: điểm neo (exit/entry) nếu gắn, không thì điểm lưu trong tệp (draw.io giữ cả khi đã gắn). */
  const endPt = (e, w) => {
    const x = ends.get(e.id)[w], on = x.tri || x.el, glued = w === 's' ? e.source : e.target;
    const f = glued && on?.box ? fixedPt(on, e.st, w === 's' ? 'exit' : 'entry') : null;
    return f || (w === 's' ? e.sp : e.tp) || (on?.box ? center(on.box) : null);
  };
  // đoạn có mũi tên rất ngắn (hoặc hai đầu cùng chạm một hình) nằm ở đầu một đường khác = đầu mũi tên vẽ rời của đường đó
  const stubs = new Set(), stubArrow = new Map();
  for (const e of edgeCells) {
    const head = arrowOf(e.st, 't');
    if (head === 'none') continue;
    const en = ends.get(e.id);
    let a = e.sp, b = e.tp;
    if (!a && b && en.s.el?.box) a = clampTo(en.s.el.box, b);
    if (!b && a && en.t.el?.box) b = clampTo(en.t.el.box, a);
    if (!a || !b) continue;
    const ta = isEl(en.s.el) ? en.s.el : snap(a)?.el || null, tb = isEl(en.t.el) ? en.t.el : snap(b)?.el || null;
    const at = tb || ta;
    if (!at || (ta && tb && ta !== tb)) continue;
    if (Math.hypot(a[0] - b[0], a[1] - b[1]) > HAND.stub && !(ta && tb)) continue;
    let best = null, bd = HAND.stubJoin;
    for (const h of edgeCells) {
      if (h === e || stubs.has(h.id)) continue;
      const hn = ends.get(h.id);
      for (const w of ['s', 't']) {
        if (hn[w].el !== at || hn[w === 's' ? 't' : 's'].el === at) continue;
        const p = endPt(h, w);
        const d = p ? Math.min(Math.hypot(p[0] - a[0], p[1] - a[1]), Math.hypot(p[0] - b[0], p[1] - b[1])) : Infinity;
        if (d <= bd) { bd = d; best = { h, w }; }
      }
    }
    if (!best) continue;
    stubs.add(e.id);
    stubArrow.set(best.h.id, { w: best.w, arrow: head, fill: e.st.endFill });
  }
  // ô chữ rời chỉ ghi «include»/«extend» (± điều kiện) đặt sát một đường giữa hai use case chưa có chữ → chữ của đường đó
  for (const x of texts) {
    if (byId.get(x.parent)?.edge) continue;
    const txt = labelText(x.value), kind = stereoOf(txt);
    if ((kind !== 'include' && kind !== 'extend') || txt.length > 80 || ucC.some((u) => inBox(center(x.box), u.box))) continue;
    let best = null, bd = HAND.labelNear;
    for (const e of edgeCells) {
      if (stubs.has(e.id) || looseLabel.has(e.id) || ownLabel(e)) continue;
      const en = ends.get(e.id), s = en.s.el, t = en.t.el;
      if (!s || !t || s === t || !isEllipseC(s) || !isEllipseC(t)) continue;
      const d = distToLine(center(x.box), lineOf(e, en.s.tri || s, en.t.tri || t));
      if (d < bd) { bd = d; best = e; }
    }
    if (best) { looseLabel.set(best.id, txt); read.labels++; }
  }
  for (const e of edgeCells) {
    if (stubs.has(e.id)) continue;
    const en = ends.get(e.id);
    const sRaw = e.source ? en.s.el : null, tRaw = e.target ? en.t.el : null;
    if ((sRaw && isNoteC(sRaw)) || (tRaw && isNoteC(tRaw))) {
      const note = sRaw && isNoteC(sRaw) ? sRaw : tRaw, other = note === sRaw ? tRaw : sRaw;
      noteLinks.push({ note, point: other ? center(other.box) : note === sRaw ? e.tp : e.sp });
      allLines.set(e.id, lineOf(e, sRaw, tRaw));
      continue;
    }
    const s = sRaw || (en.s.snapped ? en.s.el : null), t = tRaw || (en.t.snapped ? en.t.el : null);
    // đường đến tam giác: vẽ tới tam giác, đọc như mũi tên kế thừa ở đầu đó; đoạn mũi tên rời: ghép vào đầu tương ứng
    let st = e.st;
    if (en.s.tri) st = { ...st, startArrow: 'block', startFill: '0' };
    if (en.t.tri) st = { ...st, endArrow: 'block', endFill: '0' };
    const sa = stubArrow.get(e.id);
    if (sa) { const k = sa.w === 's' ? 'start' : 'end'; st = { ...st, [`${k}Arrow`]: sa.arrow, ...(sa.fill !== undefined ? { [`${k}Fill`]: sa.fill } : {}) }; }
    const line = lineOf(e, en.s.tri || s, en.t.tri || t);
    allLines.set(e.id, line);
    if ((s && frames.includes(s)) || (t && frames.includes(t))) continue;
    if (!s || !t) { if (line) { const r = `edge:${e.id}`; geom[r] = { line }; cellOf[r] = e.id; notation.push({ code: 'dangling', sev: 'error', refs: [r] }); } continue; }
    // đường gắn hai đầu vào CÙNG một hình: draw.io tạo khi lỡ kéo mũi tên xanh rồi thả lại lên chính hình đó
    if (s === t && isEl(s)) {
      const r = `edge:${e.id}`; geom[r] = { line: line || [center(s.box), center(s.box)] }; cellOf[r] = e.id;
      notation.push({ code: 'self-loop', sev: 'error', refs: [r], data: { names: [idOf(s)] } });
      continue;
    }
    links++;
    read.snapped += Number(en.s.snapped) + Number(en.t.snapped);
    read.arrowheads += Number(!!en.s.tri) + Number(!!en.t.tri) + Number(!!sa);
    const lbl = edgeLabel(e);
    const aT = arrowOf(st, 't'), aS = arrowOf(st, 's'), headT = aT !== 'none', headS = aS !== 'none';
    const rev = headS && !headT;                                  // mũi tên vẽ ở đầu source → chiều ngược
    const [tail, head] = rev ? [t, s] : [s, t];
    const lineTH = rev ? [...line].reverse() : line;
    const headKind = rev ? aS : aT, headFilled = rev ? fillOf(st, 's') : fillOf(st, 't');
    const tri = /block|triangle/.test(headKind);
    const stereo = stereoOf(lbl);
    const A = isActorC, U = isEllipseC;
    const put = (r, list, item, l = lineTH) => { if (!seenRel.has(r)) { seenRel.add(r); list?.push(item); } geom[r] = { line: l, ...(lbl ? { label: lbl.length } : {}) }; cellOf[r] = e.id; };
    if ((A(s) && U(t)) || (U(s) && A(t))) {
      const a = A(s) ? s : t, u = U(s) ? s : t, r = `assoc:${idOf(a)}>${idOf(u)}`;
      put(r, associations, { actor: idOf(a), usecase: idOf(u) }, line);
      if (stereo === 'include' || stereo === 'extend') notation.push({ code: 'rel-on-actor', sev: 'error', refs: [r], data: { kind: stereo } });
      else if (headT || headS) assocArrows.push(r);
    } else if (U(s) && U(t)) {
      if (stereo === 'include' || stereo === 'uses') {
        const r = `include:${idOf(tail)}>${idOf(head)}`;
        put(r, includes, { base: idOf(tail), part: idOf(head) });
        if (stereo === 'uses') notation.push({ code: 'uses', sev: 'review', refs: [r] });
        if (st.dashed !== '1') notation.push({ code: 'rel-style-solid', sev: 'error', refs: [r], data: { kind: 'include' } });
        if (!headT && !headS) notation.push({ code: 'rel-no-arrow', sev: 'error', refs: [r], data: { kind: 'include' } });
      } else if (stereo === 'extend') {
        const r = `extend:${idOf(tail)}>${idOf(head)}`, cond = condOf(lbl);
        put(r, extendsL, { extending: idOf(tail), base: idOf(head), ...(cond ? { condition: cond } : {}) });
        if (st.dashed !== '1') notation.push({ code: 'rel-style-solid', sev: 'error', refs: [r], data: { kind: 'extend' } });
        if (!headT && !headS) notation.push({ code: 'rel-no-arrow', sev: 'error', refs: [r], data: { kind: 'extend' } });
      } else if (tri) {
        const r = `ucgen:${idOf(tail)}>${idOf(head)}`;
        put(r, generalizations, { child: idOf(tail), parent: idOf(head) });
        if (headFilled) notation.push({ code: 'gen-filled', sev: 'review', refs: [r] });
      } else {
        const r = `edge:${e.id}`; geom[r] = { line }; cellOf[r] = e.id;
        notation.push({ code: 'rel-unknown', sev: 'error', refs: [r], data: { names: [idOf(s), idOf(t)] } });
      }
    } else if (A(s) && A(t)) {
      if (tri) {
        const r = `actorgen:${idOf(tail)}>${idOf(head)}`;
        put(r, null, null); actorParents[idOf(tail)] = idOf(head);
        if (headFilled) notation.push({ code: 'gen-filled', sev: 'review', refs: [r] });
      } else { const r = `edge:${e.id}`; geom[r] = { line }; cellOf[r] = e.id; notation.push({ code: 'actor-link', sev: 'error', refs: [r], data: { names: [idOf(s), idOf(t)] } }); }
    }
  }
  if (assocArrows.length) notation.push({ code: 'assoc-arrow', sev: 'review', refs: assocArrows, data: { n: assocArrows.length } });
  // ---- note điều kiện «extend» (UML 2.5: ghi chú gắn vào đường extend)
  for (const n of notes) {
    const txt = labelText(n.value);
    const cm = txt.match(/(?:condition|điều kiện)\s*:?\s*\{?([^}\n]+)\}?/iu), pm = txt.match(/(?:extension points?|điểm mở rộng)\s*:?\s*([^\n]+)/iu);
    if (!cm && !pm) continue;
    const link = noteLinks.find((l) => l.note === n);
    const anchor = link?.point || center(n.box);
    let best = null, bd = link ? 60 : 180;
    for (const x of extendsL) { const d = distToLine(anchor, geom[`extend:${x.extending}>${x.base}`]?.line); if (d < bd) { bd = d; best = x; } }
    if (best) { if (cm && !best.condition) best.condition = cm[1].trim(); if (pm && !best.point) best.point = pm[1].trim(); }
  }
  for (const x of extendsL) if (!x.point) { const b = usecases.find((u) => u.id === x.base); if (b?.extensionPoints?.length === 1) x.point = b.extensionPoints[0]; }
  // ---- vị trí: khung, actor trong khung, UC ngoài khung, tên trống
  if (!frame) notation.push({ code: 'no-subject', sev: 'error', refs: [] });
  else {
    geom.subject = { box: frame.box }; cellOf.subject = frame.id;
    if (!subjectName) notation.push({ code: 'subject-name', sev: 'error', refs: ['subject'] });
    for (const c of actorC) if (inBox(center(c.box), frame.box)) notation.push({ code: 'actor-inside', sev: 'error', refs: [`actor:${idOf(c)}`] });
    for (const c of ucC) if (!frames.some((f) => inBox(center(c.box), f.box))) notation.push({ code: 'uc-outside', sev: 'error', refs: [`uc:${idOf(c)}`] });
  }
  for (const a of actors) if (!a.name) notation.push({ code: 'empty-name', sev: 'error', refs: [`actor:${a.id}`], data: { kind: 'actor' } });
  for (const u of usecases) if (!u.name) notation.push({ code: 'empty-name', sev: 'error', refs: [`uc:${u.id}`], data: { kind: 'uc' } });
  // ---- đường xuyên qua use case khác; hai use case chồng nhau
  const crossPts = [];
  for (const [r, g] of Object.entries(geom)) {
    if (!g.line || r.startsWith('edge:')) continue;
    const ends = new Set(r.split(':')[1].split('>').map((x) => cellOf[`uc:${x}`] || cellOf[`actor:${x}`]));
    for (let i = 1; i < g.line.length; i++) for (const c of ucC) {
      if (ends.has(c.id)) continue;
      const p = crossPoint(g.line[i - 1], g.line[i], c.box);
      if (p) crossPts.push({ p, r, uc: `uc:${idOf(c)}` });
    }
  }
  if (crossPts.length) { geom.cross = { points: crossPts.map((x) => x.p) }; notation.push({ code: 'crossing', sev: 'review', refs: ['cross', ...uniq(crossPts.map((x) => x.r))], data: { n: crossPts.length } }); }
  for (let i = 0; i < ucC.length; i++) for (let j = i + 1; j < ucC.length; j++) {
    const A = ucC[i].box, B = ucC[j].box, [ax, ay] = center(A), [bx, by] = center(B);
    if (((ax - bx) / ((A.w + B.w) / 2)) ** 2 + ((ay - by) / ((A.h + B.h) / 2)) ** 2 < 0.8) notation.push({ code: 'overlap', sev: 'review', refs: [`uc:${idOf(ucC[i])}`, `uc:${idOf(ucC[j])}`] });
  }
  // ---- phía actor (vẽ lại giữ cách khách xếp) + ngôn ngữ
  const midX = frame ? center(frame.box)[0] : ucC.length ? ucC.reduce((s, c) => s + center(c.box)[0], 0) / ucC.length : 0;
  actors.forEach((a, i) => { a.side = center(actorC[i].box)[0] < midX ? 'left' : 'right'; });
  const lang = VI_CHARS.test([subjectName, ...actors.map((a) => a.name), ...usecases.map((u) => u.name)].join(' ')) ? 'vi' : 'en';
  const model = {
    subject: { name: subjectName }, lang, actors, usecases, associations, includes, extends: extendsL, generalizations, actorParents,
    _source: { kind: 'drawio', page: pick.p.name, pages: pages.length }, _geom: geom, _cells: cellOf,
  };
  return { model, notation, page: pick.p, pageNo: scored.indexOf(pick) + 1, source: xmlText, cells, byId, frame, allLines, stats: { actors: actors.length, usecases: usecases.length, links }, read };
}

// ================================================================ lời cho khách (không mã lint, không checklist)
const T = {
  vi: {
    sev: { error: 'Lỗi', review: 'Nên xem lại' },
    title: (s) => `Kiểm tra sơ đồ use case${s ? ` — ${s}` : ''}`,
    fixedTitle: (s) => `Sơ đồ đã sửa${s ? ` — ${s}` : ''}`,
    read: (k, s) => `Đọc được ${k === 'image' ? 'từ ảnh' : 'từ file .drawio'}: ${s.usecases} use case, ${s.actors} actor, ${s.links} đường nối.`,
    handDrawn: (r) => {
      const parts = [r.snapped && `${r.snapped} đầu đường đặt sát hình nhưng chưa gắn vào hình`, r.arrowheads && `${r.arrowheads} mũi tên vẽ rời`, r.labels && `${r.labels} chữ «include»/«extend» đặt rời cạnh đường`].filter(Boolean);
      return parts.length ? `Máy đã đọc theo hình bạn vẽ: ${parts.join(', ')} — không tính là lỗi. Nên gắn hẳn vào hình: kéo hình đi thì các đường chưa gắn không chạy theo.` : '';
    },
    result: (e, r) => (e + r ? `**Kết quả: ${e} lỗi, ${r} chỗ nên xem lại.** Số thứ tự khớp với số trên hình.` : '**Không thấy lỗi nào.**'),
    legendTitle: (e, r) => (e + r ? `Kết quả kiểm tra: ${e} lỗi, ${r} chỗ nên xem lại` : 'Kết quả kiểm tra: không thấy lỗi'),
    uncertain: 'Chỗ đọc từ ảnh chưa chắc — nhờ bạn xác nhận',
    uncertainTag: ' (đọc từ ảnh chưa chắc)',
    fixedDone: (n) => `Đã sửa ${n} chỗ, số theo bản kiểm tra.`,
    fixedSure: 'Đã sửa:',
    fixedProposed: 'Đã sửa theo đề xuất — bạn xem lại giúp:',
    fixedNone: 'Không có gì cần sửa.',
    pending: 'Chưa sửa — cần bạn quyết:',
    left: 'Sau khi sửa vẫn còn:',
    pageName: 'Kết quả kiểm tra',
    defaultSubject: 'Hệ thống',
    renamed: (a, b) => `Đổi "${a}" thành "${b}".`,
    condSet: (a, b, c) => `Thêm điều kiện cho «extend» "${a}" → "${b}": {${c}}.`,
    redrawn: (what) => `${what} → đã vẽ lại đúng.`,
    removedAssoc: (a, u) => `Bỏ đường "${a}" – "${u}".`,
    removedActor: (a) => `Bỏ actor "${a}".`,
    removedUc: (u) => `Bỏ use case "${u}".`,
    merged: (u) => `Gộp các use case trùng tên "${u}".`,
    retyped: (a, b, k) => `Đổi quan hệ "${a}" – "${b}" thành ${k === 'generalization' ? 'kế thừa' : `«${k}»`}.`,
    flipped: (a, b) => `Đảo chiều quan hệ "${a}" – "${b}".`,
    connected: (a, u) => `Nối actor "${a}" với "${u}".`,
    subjectNamed: (s) => `Ghi tên hệ thống: "${s}".`,
    handledWith: (k) => `Đã xử lý cùng ${k}.`,
    fixedHere: (what) => `${what} → đã sửa.`,
    removedDangling: 'Bỏ đường nối lơ lửng.',
    removedLoop: 'Bỏ đường nối quay về chính nó.',
    moveByHand: 'Những chỗ cần dời hình: dời tay trong draw.io, hoặc dùng bản vẽ lại.',
    aiDone: (t) => t,
    msg: {
      'no-subject': () => ['Thiếu khung hệ thống.', 'Vẽ một hình chữ nhật bao quanh mọi use case, ghi tên hệ thống ở cạnh trên; actor đứng ngoài khung.'],
      'subject-name': () => ['Khung hệ thống chưa ghi tên.', 'Ghi tên hệ thống ở cạnh trên của khung.'],
      'actor-inside': ({ n }) => [`Actor "${n[0]}" nằm trong khung hệ thống.`, 'Đưa actor ra ngoài khung — actor là người hoặc hệ thống bên ngoài.'],
      'uc-outside': ({ n }) => [`Use case "${n[0]}" nằm ngoài khung hệ thống.`, 'Đưa use case vào trong khung.'],
      'rel-style-solid': ({ n, d }) => [`Đường «${d.kind}» giữa "${n[0]}" và "${n[1]}" đang vẽ nét liền.`, '«include» và «extend» vẽ nét đứt, đầu mũi tên mở.'],
      'rel-no-arrow': ({ n, d }) => [`Đường «${d.kind}» giữa "${n[0]}" và "${n[1]}" thiếu mũi tên.`, d.kind === 'include' ? 'Mũi tên đi từ use case chính tới phần nó luôn gồm.' : 'Mũi tên đi từ phần mở rộng về use case gốc.'],
      'rel-on-actor': ({ n, d }) => [`«${d.kind}» đang nối actor "${n[0]}" với use case "${n[1]}".`, '«include»/«extend» chỉ dùng giữa hai use case; actor nối use case bằng đường thẳng.'],
      // Tường 26/10/2026: có môn khuyên KHÔNG dùng «include»/«extend» khi chưa hiểu rõ ⇒ lời sửa không đẩy khách dùng chúng
      'rel-unknown': ({ n }) => [`Đường nối "${n[0]}" – "${n[1]}" không ghi là quan hệ gì.`, 'Ghi rõ đường này là quan hệ gì; không chắc thì bỏ đường này và nối actor thẳng tới từng use case.'],
      'actor-link': ({ n }) => [`Hai actor "${n[0]}" và "${n[1]}" nối bằng đường thường.`, 'Actor chỉ nối với nhau bằng kế thừa: tam giác rỗng, từ actor con về actor cha.'],
      'assoc-arrow': ({ d }) => [`${d.n} đường nối actor – use case có đầu mũi tên.`, 'Đường nối actor với use case là đường thẳng, không có mũi tên.'],
      'gen-filled': ({ n }) => [`Kế thừa "${n[0]}" → "${n[1]}" dùng tam giác tô đặc.`, 'Kế thừa dùng tam giác rỗng.'],
      uses: ({ n }) => [`Đường giữa "${n[0]}" và "${n[1]}" ghi «uses» — ký hiệu UML cũ.`, 'Đổi thành «include».'],
      crossing: ({ d }) => [`${d.n} chỗ đường nối cắt ngang qua use case khác.`, 'Dời use case để đường không đi xuyên qua hình, tránh đọc nhầm quan hệ.'],
      overlap: ({ n }) => [`"${n[0]}" và "${n[1]}" chồng lên nhau.`, 'Tách hai hình ra.'],
      'empty-name': ({ d }) => [`Có ${d.kind === 'actor' ? 'actor' : 'use case'} chưa đặt tên.`, 'Đặt tên hoặc xoá nếu thừa.'],
      dangling: () => ['Có đường nối không gắn vào hình nào.', 'Kéo hai đầu đường vào đúng hình, hoặc xoá đường.'],
      'self-loop': ({ n }) => [`Có đường nối "${n[0]}" quay về chính nó.`, 'Thường do lỡ tay kéo trong draw.io — xoá đường này.'],
      'uc-lonely': ({ n }) => [`Use case "${n[0]}" không nối với actor hay use case nào.`, 'Nối actor dùng nó vào use case này. Không ai dùng thì bỏ.'],
      'actor-lonely': ({ n }) => [`Actor "${n[0]}" không nối với use case nào.`, 'Nối actor với việc họ làm, hoặc bỏ actor này.'],
      'actor-system': ({ n }) => [`"${n[0]}" là chính hệ thống, không phải actor.`, 'Bỏ actor này; tên hệ thống ghi trên khung.'],
      'actor-case': ({ n, s }) => [`Tên actor "${n[0]}" chưa viết hoa chữ đầu.`, s ? `Đổi thành "${s}".` : 'Viết hoa chữ cái đầu.'],
      'uc-is-system': ({ n }) => [`Use case "${n[0]}" trùng tên hệ thống.`, 'Use case là một việc cụ thể actor làm trong hệ thống, không phải cả hệ thống — đổi thành việc cụ thể hoặc bỏ.'],
      'actor-store': ({ n }) => [`Actor "${n[0]}" có vẻ là cơ sở dữ liệu hoặc máy chủ của chính hệ thống.`, 'Cơ sở dữ liệu của hệ thống nằm bên trong khung, không vẽ làm actor. Nếu đó là hệ thống của bên khác thì đặt tên theo hệ thống đó.'],
      'name-noun': ({ n, s }) => [`"${n[0]}" là danh từ — use case phải là việc actor làm (Động từ + Danh từ).`, s ? `Đổi thành "${s}".` : 'Đặt lại dạng Động từ + Danh từ, ví dụ "Xem …", "Quản lý …".'],
      'name-case': ({ n, s }) => [`"${n[0]}" chưa viết hoa chữ đầu.`, s ? `Đổi thành "${s}".` : 'Viết hoa chữ cái đầu.'],
      'name-short': ({ n, s, dl }) => [`"${n[0]}" chỉ có một từ.`, s ? `Đổi thành "${s}".` : `Đặt dạng Động từ + Danh từ, ví dụ "${dl === 'en' ? 'Pay Order' : 'Thanh toán đơn hàng'}".`],
      'dup-name': ({ n }) => [`Có ${n.length} use case cùng tên "${n[0]}".`, 'Gộp thành một, hoặc đổi tên cho khác nhau.'],
      'include-cycle': ({ n }) => [`"${n[0]}" và "${n[1]}" «include» lẫn nhau.`, 'Giữ một chiều: từ use case chính tới phần nó luôn gồm.'],
      'gen-cycle': ({ n }) => [`"${n[0]}" và "${n[1]}" kế thừa lẫn nhau.`, 'Giữ một chiều: từ use case con về use case cha.'],
      'extend-cond': ({ n, s }) => [`«extend» "${n[0]}" → "${n[1]}" chưa ghi điều kiện.`, s ? `Thêm ghi chú gắn vào đường extend: {${s}}.` : 'Thêm ghi chú (note) gắn vào đường extend, ghi khi nào phần mở rộng xảy ra, dạng {điều kiện}.'],
      'extend-actor': ({ n }) => [`Actor "${n[0]}" nối cả "${n[2]}" lẫn phần mở rộng "${n[1]}" của nó.`, `Phần mở rộng chạy bên trong "${n[2]}", không cần đường riêng tới actor — bỏ đường "${n[0]}" – "${n[1]}". Nếu "${n[1]}" là một cách làm khác hẳn thì dùng kế thừa.`],
      superuser: ({ n, d }) => [`Actor "${n[0]}" nối ${d.k}/${d.N} use case.`, 'Sơ đồ vẽ việc actor thật sự làm, không phải mọi việc họ có quyền làm — chỉ giữ việc quản trị cho vai này.'],
      uneven: ({ n }) => [`Mức chi tiết chưa đều: ${n.map((x) => `"${x}"`).join(', ')} chưa tách việc thêm/sửa/xoá như các mục "Quản lý" khác.`, 'Tách đều cho mọi mục "Quản lý …", hoặc bỏ hết use case con.'],
      'same-object': ({ n }) => [`"${n[0]}" và "${n[1]}" cùng nói về một đối tượng nhưng không có quan hệ nào.`, `Cùng một việc thì gộp lại; khác việc thì đặt tên cho rõ khác nhau.`],
      'too-big': ({ d }) => [`Sơ đồ có ${d.N} use case — nhiều cho một hình.`, 'Hình tổng nên khoảng 20 use case trở xuống: gom việc thêm/sửa/xoá vào "Quản lý …", hoặc tách theo phân hệ.'],
    },
  },
  en: {
    sev: { error: 'Error', review: 'Worth a look' },
    title: (s) => `Use case diagram review${s ? ` — ${s}` : ''}`,
    fixedTitle: (s) => `Corrected diagram${s ? ` — ${s}` : ''}`,
    read: (k, s) => `Read ${k === 'image' ? 'from the image' : 'from the .drawio file'}: ${s.usecases} use cases, ${s.actors} actors, ${s.links} links.`,
    handDrawn: (r) => {
      const parts = [r.snapped && `${r.snapped} line ends placed next to a shape but not attached`, r.arrowheads && `${r.arrowheads} arrowheads drawn as separate shapes`, r.labels && `${r.labels} «include»/«extend» labels placed beside a line`].filter(Boolean);
      return parts.length ? `Read as drawn: ${parts.join(', ')} — not counted as errors. Better attach them: unattached lines do not follow when a shape is moved.` : '';
    },
    result: (e, r) => (e + r ? `**Result: ${e} errors, ${r} things worth a look.** Numbers match the numbers on the diagram.` : '**No problems found.**'),
    legendTitle: (e, r) => (e + r ? `Review: ${e} errors, ${r} worth a look` : 'Review: no problems found'),
    uncertain: 'Parts of the image we could not read for sure — please confirm',
    uncertainTag: ' (unclear in the image)',
    fixedDone: (n) => `Fixed ${n} things; numbers match the review.`,
    fixedSure: 'Fixed:',
    fixedProposed: 'Fixed as suggested — please check:',
    fixedNone: 'Nothing needed fixing.',
    pending: 'Not fixed — your call:',
    left: 'Still open after the fix:',
    pageName: 'Review',
    defaultSubject: 'System',
    renamed: (a, b) => `Renamed "${a}" to "${b}".`,
    condSet: (a, b, c) => `Added the condition to «extend» "${a}" → "${b}": {${c}}.`,
    redrawn: (what) => `${what} → redrawn correctly.`,
    removedAssoc: (a, u) => `Removed the line "${a}" – "${u}".`,
    removedActor: (a) => `Removed actor "${a}".`,
    removedUc: (u) => `Removed use case "${u}".`,
    merged: (u) => `Merged the use cases named "${u}".`,
    retyped: (a, b, k) => `Changed "${a}" – "${b}" to ${k === 'generalization' ? 'generalization' : `«${k}»`}.`,
    flipped: (a, b) => `Reversed "${a}" – "${b}".`,
    connected: (a, u) => `Connected actor "${a}" to "${u}".`,
    subjectNamed: (s) => `Named the system "${s}".`,
    handledWith: (k) => `Handled with ${k}.`,
    fixedHere: (what) => `${what} → fixed.`,
    removedDangling: 'Removed the dangling line.',
    removedLoop: 'Removed the line that loops back to its own shape.',
    moveByHand: 'Shapes that need moving: move them in draw.io, or use the redrawn version.',
    aiDone: (t) => t,
    msg: {
      'no-subject': () => ['No system boundary.', 'Draw a rectangle around all use cases with the system name on top; actors stay outside.'],
      'subject-name': () => ['The system boundary has no name.', 'Write the system name at the top of the boundary.'],
      'actor-inside': ({ n }) => [`Actor "${n[0]}" is inside the system boundary.`, 'Move the actor outside — actors are people or systems outside the system.'],
      'uc-outside': ({ n }) => [`Use case "${n[0]}" is outside the system boundary.`, 'Move it inside the boundary.'],
      'rel-style-solid': ({ n, d }) => [`The «${d.kind}» line between "${n[0]}" and "${n[1]}" is solid.`, '«include» and «extend» are dashed lines with an open arrowhead.'],
      'rel-no-arrow': ({ n, d }) => [`The «${d.kind}» line between "${n[0]}" and "${n[1]}" has no arrowhead.`, d.kind === 'include' ? 'The arrow points from the base use case to the part it always includes.' : 'The arrow points from the extension to the base use case.'],
      'rel-on-actor': ({ n, d }) => [`«${d.kind}» connects actor "${n[0]}" to use case "${n[1]}".`, '«include»/«extend» only connect two use cases; an actor connects to a use case with a plain line.'],
      'rel-unknown': ({ n }) => [`The line "${n[0]}" – "${n[1]}" does not say what relationship it is.`, 'Say what relationship it is; if unsure, remove it and connect the actor directly to each use case.'],
      'actor-link': ({ n }) => [`Actors "${n[0]}" and "${n[1]}" are joined by a plain line.`, 'Actors only connect through generalization: hollow triangle from child to parent.'],
      'assoc-arrow': ({ d }) => [`${d.n} actor – use case lines have arrowheads.`, 'An actor connects to a use case with a plain line, no arrowhead.'],
      'gen-filled': ({ n }) => [`Generalization "${n[0]}" → "${n[1]}" uses a filled triangle.`, 'Use a hollow triangle.'],
      uses: ({ n }) => [`The line between "${n[0]}" and "${n[1]}" says «uses» — old UML notation.`, 'Use «include».'],
      crossing: ({ d }) => [`${d.n} places where a line runs through another use case.`, 'Move the use cases so no line passes through a shape.'],
      overlap: ({ n }) => [`"${n[0]}" and "${n[1]}" overlap.`, 'Move them apart.'],
      'empty-name': ({ d }) => [`A ${d.kind === 'actor' ? 'actor' : 'use case'} has no name.`, 'Name it or delete it.'],
      dangling: () => ['A line is not attached to any shape.', 'Attach both ends or delete the line.'],
      'self-loop': ({ n }) => [`A line loops from "${n[0]}" back to itself.`, 'Usually a slip while dragging in draw.io — delete it.'],
      'uc-lonely': ({ n }) => [`Use case "${n[0]}" is not connected to any actor or use case.`, 'Connect the actor who uses it. Remove it if nobody does.'],
      'actor-lonely': ({ n }) => [`Actor "${n[0]}" is not connected to any use case.`, 'Connect the actor to what they do, or remove it.'],
      'actor-system': ({ n }) => [`"${n[0]}" is the system itself, not an actor.`, 'Remove it; the system name goes on the boundary.'],
      'actor-case': ({ n, s }) => [`Actor name "${n[0]}" does not start with a capital letter.`, s ? `Rename to "${s}".` : 'Capitalise the first letter.'],
      'uc-is-system': ({ n }) => [`Use case "${n[0]}" has the same name as the system.`, 'A use case is one task inside the system, not the whole system — name the task or remove it.'],
      'actor-store': ({ n }) => [`Actor "${n[0]}" looks like the system's own database or server.`, "The system's database is inside the boundary, not an actor. If it belongs to another organisation, name it after that system."],
      'name-noun': ({ n, s }) => [`"${n[0]}" is a noun — a use case is something the actor does (verb + noun).`, s ? `Rename to "${s}".` : 'Rename as verb + noun, e.g. "View …", "Manage …".'],
      'name-case': ({ n, s }) => [`"${n[0]}" does not start with a capital letter.`, s ? `Rename to "${s}".` : 'Capitalise the first letter.'],
      'name-short': ({ n, s, dl }) => [`"${n[0]}" is a single word.`, s ? `Rename to "${s}".` : `Use verb + noun, e.g. "${dl === 'vi' ? 'Thanh toán đơn hàng' : 'Pay Order'}".`],
      'dup-name': ({ n }) => [`${n.length} use cases are named "${n[0]}".`, 'Merge them, or give them different names.'],
      'include-cycle': ({ n }) => [`"${n[0]}" and "${n[1]}" include each other.`, 'Keep one direction: from the base use case to the part it includes.'],
      'gen-cycle': ({ n }) => [`"${n[0]}" and "${n[1]}" specialise each other.`, 'Keep one direction: from child to parent.'],
      'extend-cond': ({ n, s }) => [`«extend» "${n[0]}" → "${n[1]}" has no condition.`, s ? `Add a note on the extend line: {${s}}.` : 'Add a note on the extend line saying when the extension happens, as {condition}.'],
      'extend-actor': ({ n }) => [`Actor "${n[0]}" connects to both "${n[2]}" and its extension "${n[1]}".`, `The extension runs inside "${n[2]}" and needs no line of its own — remove "${n[0]}" – "${n[1]}". If "${n[1]}" is a different way of doing it, use generalization.`],
      superuser: ({ n, d }) => [`Actor "${n[0]}" connects to ${d.k}/${d.N} use cases.`, 'A use case diagram shows what an actor actually does, not everything they are allowed to do — keep only their admin tasks.'],
      uneven: ({ n }) => [`Uneven detail: ${n.map((x) => `"${x}"`).join(', ')} are not split into add/edit/delete like the other "Manage" use cases.`, 'Split every "Manage …" the same way, or drop the child use cases.'],
      'same-object': ({ n }) => [`"${n[0]}" and "${n[1]}" are about the same thing but not related.`, 'Merge them if they are the same task; otherwise name them so the difference is clear.'],
      'too-big': ({ d }) => [`The diagram has ${d.N} use cases — a lot for one diagram.`, 'Keep an overview to about 20 use cases: group add/edit/delete under "Manage …", or split by subsystem.'],
    },
  },
};
export const TEXT = T;

/** Lint tầng 0 → mã cho khách + mức. null = chỉ dùng nội bộ (nguồn, tầng 1, ngôn ngữ model…). */
function mapLint(f, model) {
  switch (f.rule) {
    case 'ov uc-lonely': return { code: 'uc-lonely', sev: 'error' };
    case 'ov actor-lonely': return { code: 'actor-lonely', sev: 'error' };
    case 'ov actor-system': return f.level === 'ERROR' ? { code: 'actor-system', sev: 'error' } : { code: 'actor-store', sev: 'review' };
    case 'ov actor-name': return { code: 'actor-case', sev: 'review' };
    case 'ov uc-subject': return { code: 'uc-is-system', sev: 'error' };
    case 'ov usecase-name': return /danh từ/.test(f.msg) ? { code: 'name-noun', sev: 'error' } : /viết hoa/.test(f.msg) ? { code: 'name-case', sev: 'review' } : { code: 'name-short', sev: 'review' };
    case 'ov dup-name': return { code: 'dup-name', sev: 'error' };
    case 'ov include': return /vòng/.test(f.msg) ? { code: 'include-cycle', sev: 'error' } : null;
    case 'ov ucgen': return /vòng/.test(f.msg) ? { code: 'gen-cycle', sev: 'error' } : null;
    case 'uml extend-cond': return { code: 'extend-cond', sev: 'review' };
    case 'biz extend-actor': return { code: 'extend-actor', sev: 'review' };
    case 'biz superuser': { const m = f.msg.match(/nối (\d+)\/(\d+)/); return { code: 'superuser', sev: 'review', data: { k: m?.[1], N: m?.[2] } }; }
    case 'biz uneven': return { code: 'uneven', sev: 'review' };
    case 'biz same-object': return { code: 'same-object', sev: 'review' };
    case 'uml overview-size': return (model.usecases || []).length > 20 ? { code: 'too-big', sev: 'review', data: { N: model.usecases.length } } : null;
    // 'ov relations' (không có include/extend/kế thừa) KHÔNG báo khách — Tường 26/10/2026: có môn khuyên chưa hiểu rõ thì
    // đừng dùng «include»/«extend»; luật vẫn chạy cho hình tổng FPT do usecase-overview vẽ (tầng 0).
    case 'ov relations': return null;
    default: return null;
  }
}

/** Gợi ý đổi tên chắc chắn (còn lại để AI đề xuất qua ai.json suggest). */
const SMALL_WORD = /^(a|an|the|and|or|nor|of|for|to|at|by|with|from|via|per)$/i;
/** "log in" → "Log In"; từ nối nhỏ (of, to, …) giữ chữ thường trừ từ đầu. */
const titleCase = (s) => { let first = true; return s.split(/(\s+)/).map((w) => { if (!w.trim()) return w; const keep = !first && SMALL_WORD.test(w); first = false; return keep ? w.toLowerCase() : w[0].toUpperCase() + w.slice(1); }).join(''); };
/** Tên use case tiếng Anh của sơ đồ viết kiểu Title Case ("Register Account") → gợi ý viết hoa theo đúng kiểu đó. */
const titleStyled = (model) => {
  const ms = (model.usecases || []).map((u) => String(u.name || '').trim()).filter((s) => /\s/.test(s) && /^\p{Lu}/u.test(s));
  return ms.length > 0 && ms.filter((s) => s.split(/\s+/).every((w, i) => (i > 0 && SMALL_WORD.test(w)) || /^[\p{Lu}\d]/u.test(w))).length * 2 > ms.length;
};

export function suggestName(name, code, lang, opt = {}) {
  const s = String(name || '').trim();
  if (!s) return null;
  if (code === 'name-case') return opt.title && lang !== 'vi' ? titleCase(s) : s[0].toLocaleUpperCase('vi') + s.slice(1);
  if (code === 'actor-case') return lang === 'vi' ? s[0].toLocaleUpperCase('vi') + s.slice(1) : s.replace(/(^|\s)(\p{Ll})/gu, (m, a, b) => a + b.toUpperCase());
  if (code !== 'name-noun') return null;
  const low = s[0].toLocaleLowerCase('vi') + s.slice(1);
  if (lang === 'vi') {
    if (/^(thông tin|danh sách|chi tiết|lịch sử|hồ sơ)\s/i.test(s)) return `Xem ${low}`;
    const m = s.match(/^hệ thống\s+(quản lý|đặt|bán|thanh toán)\s+(.+)$/i);
    if (m) return `${m[1][0].toLocaleUpperCase('vi')}${m[1].slice(1)} ${m[2]}`;
    return null;
  }
  let m = s.match(/^(.+?)\s+management$/i); if (m) return `Manage ${m[1]}`;
  m = s.match(/^(.+?)\s+registration$/i); if (m) return `Register ${m[1]}`;
  if (/^user\s+log ?in$/i.test(s)) return 'Log In';
  if (/\s(information|info|details|history|list|statistics)$/i.test(s) || /^(information|details|history|statistics)\b/i.test(s)) return `View ${s}`;
  return null;
}

const relName = (model) => {
  const uc = new Map((model.usecases || []).map((u) => [u.id, u.name])), ac = new Map((model.actors || []).map((a) => [a.id, a.name]));
  const nm = (id) => uc.get(id) ?? ac.get(id) ?? id;
  return (r) => {
    if (!r || r === 'subject' || r === 'cross') return [];
    const [kind, rest] = r.split(/:(.+)/);
    if (kind === 'uc' || kind === 'actor') return [nm(rest)];
    if (kind === 'edge') return [];
    return rest.split('>').map(nm);
  };
};

/**
 * Gom phát hiện: ký hiệu/vị trí (parse) + lint tầng 0 + AI (ai.json) → mục cho khách đã đánh số.
 * Mục chạm phần tử "đọc chưa chắc" (ảnh) hạ từ Lỗi xuống Nên xem lại.
 */
export function collectFindings(model, notation = [], ai = null, opts = {}) {
  const lang = opts.lang || 'vi';                       // ngôn ngữ báo cáo cho khách
  const dlang = model.lang === 'vi' ? 'vi' : 'en';      // ngôn ngữ nhãn trên hình (gợi ý đổi tên theo nó)
  const L = T[lang] || T.vi;
  const names = relName(model);
  const suggest = { ...(ai?.suggest || {}) };
  const items = [];
  for (const n of notation) items.push({ source: 'drawing', code: n.code, sev: n.sev, refs: n.refs || [], data: n.data || {} });
  const emptyUc = new Set((model.usecases || []).filter((u) => !String(u.name || '').trim()).map((u) => `uc:${u.id}`));
  // opts.extendDetails (--extend-details): đề của khách không đòi điều kiện «extend» → không nhắc; hình của khách giữ nguyên
  for (const f of lintModel(opts.extendDetails ? { ...model, extendDetails: opts.extendDetails } : model)) {
    const m = mapLint(f, model);
    if (!m) continue;
    if (m.code.startsWith('name-') && (f.refs || []).some((r) => emptyUc.has(r))) continue;
    if (m.code === 'uc-lonely' && (f.refs || []).some((r) => emptyUc.has(r))) continue;
    items.push({ source: 'check', code: m.code, sev: m.sev, refs: f.refs || [], data: m.data || {} });
  }
  for (const a of ai?.findings || []) {
    items.push({ source: 'ai', code: 'ai', sev: a.severity === 'error' && a.basis === 'notation' ? 'error' : 'review', refs: a.refs || [], data: { what: a.what, fix: a.fix }, action: a.action || null });
  }
  // AI viết lại lời cho một mục máy (cùng phần tử): "replaces": "actor-store" | ["name-short", …] → bỏ mục máy đó
  for (const a of ai?.findings || []) {
    const rep = [].concat(a.replaces || []);
    if (!rep.length) continue;
    for (let i = items.length - 1; i >= 0; i--) if (items[i].source !== 'ai' && rep.includes(items[i].code) && items[i].refs.some((r) => (a.refs || []).includes(r))) items.splice(i, 1);
  }
  // gộp trùng (cùng mã + cùng phần tử)
  const seen = new Set();
  const out = items.filter((it) => { const k = `${it.code}|${[...it.refs].sort().join(',')}|${it.data?.what || ''}`; if (seen.has(k)) return false; seen.add(k); return true; });
  const uncertain = new Set([...(model._uncertain || []), ...(ai?.uncertain || [])]);
  const touches = (r) => uncertain.has(r) || (r.includes(':') && r.split(/:(.+)/)[1]?.split('>').some((id) => uncertain.has(`uc:${id}`) || uncertain.has(`actor:${id}`)));
  for (const it of out) if (it.refs.some(touches)) { it.uncertain = true; if (it.sev === 'error') it.sev = 'review'; }
  // lời cho khách
  const title = dlang === 'en' && titleStyled(model);
  for (const it of out) {
    const n = it.code === 'extend-actor' ? [...names(it.refs[0]).slice(0, 1), ...names(it.refs[it.refs.length - 1])] : it.refs.flatMap(names);
    if (it.code === 'rel-unknown' || it.code === 'actor-link' || it.code === 'self-loop') n.push(...(it.data.names || []).map((id) => names(`uc:${id}`)[0]));
    const firstRef = it.refs[0];
    const s = suggest[firstRef]?.rename || suggest[firstRef]?.condition || (it.code.startsWith('name-') || it.code === 'actor-case' ? suggestName(n[0], it.code, dlang, { title }) : null);
    if (it.code === 'ai') { it.what = it.data.what || ''; it.fix = it.data.fix || ''; }
    else { const fn = L.msg[it.code]; if (!fn) continue; [it.what, it.fix] = fn({ n, d: it.data, s, dl: dlang }); }
    if (it.uncertain) it.what += L.uncertainTag;
    it.suggestion = s || null;
  }
  // thứ tự: Lỗi trước, trong mỗi nhóm theo vị trí trên hình (trên → dưới, trái → phải)
  const geom = model._geom || {};
  const posOf = (it) => { for (const r of it.refs) { const g = geom[r]; if (g?.box) return [g.box.y, g.box.x]; if (g?.line) { const p = midOf(g.line); return [p[1], p[0]]; } if (g?.points?.length) return [g.points[0][1], g.points[0][0]]; } return [-1, -1]; };
  const sorted = out.filter((it) => it.what).sort((a, b) => (a.sev === b.sev ? 0 : a.sev === 'error' ? -1 : 1) || posOf(a)[0] - posOf(b)[0] || posOf(a)[1] - posOf(b)[1]);
  sorted.forEach((it, i) => { it.num = i + 1; });
  return sorted;
}

// ================================================================ đánh dấu trên hình của khách
/** Ref dùng để đặt số / tô màu đường / đóng khung hình. Cắt hình: số ở chỗ cắt, tô đường. Nhánh extend có dây actor: chỉ dây cần bỏ. */
const badgeRefs = (it) => (it.code === 'crossing' ? ['cross'] : it.code === 'extend-actor' ? it.refs.filter((r) => r.startsWith('assoc:')) : it.refs);
const colorRefs = (it) => (it.code === 'crossing' ? it.refs.filter((r) => r !== 'cross') : badgeRefs(it));
/** Số cho đường: lệch vuông góc khỏi điểm giữa đoạn dài nhất (không đè nhãn «include»/«extend» nằm trên đường). */
function edgeSpot(line, label = 0) {
  let bi = 1, bl = -1;
  for (let i = 1; i < line.length; i++) { const l = Math.hypot(line[i][0] - line[i - 1][0], line[i][1] - line[i - 1][1]); if (l > bl) { bl = l; bi = i; } }
  const a = line[bi - 1], b = line[bi], dx = b[0] - a[0], dy = b[1] - a[1], len = Math.hypot(dx, dy) || 1;
  let nx = -dy / len, ny = dx / len;
  if (ny > 0 || (Math.abs(ny) < 1e-6 && nx > 0)) { nx = -nx; ny = -ny; }
  // đường đứng có nhãn: nhãn nằm ngang trên đường → đẩy số ra xa hơn nửa bề rộng nhãn
  const off = 20 + (label ? (Math.abs(dy) > Math.abs(dx) ? label * 3 : 4) : 0);
  return [(a[0] + b[0]) / 2 + nx * off, (a[1] + b[1]) / 2 + ny * off];
}
/** Toạ độ đặt số cho từng mục: hình → góc trên phải; đường → lệch khỏi giữa đoạn dài nhất; mục chung → hàng trên khung. */
export function placeMarkers(items, geom, bounds) {
  const spots = [], placed = [];
  const free = (x, y) => !placed.some((p) => Math.hypot(p[0] - x, p[1] - y) < 23);
  const put = (it, x, y) => { let k = 0; while (!free(x, y) && k++ < 10) x += 24; placed.push([x, y]); spots.push({ num: it.num, sev: it.sev, x, y }); };
  const globals = [];
  for (const it of items) {
    let any = false;
    for (const r of badgeRefs(it)) {
      const g = geom[r];
      if (!g) continue;
      if (r === 'subject' && g.box) put(it, g.box.x + 14, g.box.y + 14);
      else if (g.box) { const b = g.full || g.box; put(it, b.x + b.w - 2, b.y - 2); }
      else if (g.line) { const p = edgeSpot(g.line, g.label); put(it, p[0], p[1]); }
      else if (g.points) for (const p of g.points.slice(0, 8)) put(it, p[0] + 10, p[1] - 10);
      any = true;
      if (it.code === 'assoc-arrow') break;
    }
    if (!any) globals.push(it);
  }
  globals.forEach((it, i) => put(it, bounds.x + 12 + i * 26, bounds.y - 16));
  return spots;
}
// khung hệ thống thiếu tên: chỉ đặt số ở góc, không viền cả khung
const boxesOfItem = (it, geom) => badgeRefs(it).filter((r) => r !== 'cross' && r !== 'subject').map((r) => geom[r]).filter((g) => g?.box).map((g) => g.full || g.box);

function contentBounds(cells) {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const add = (x, y) => { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); };
  for (const c of cells) {
    if (c.box) { add(c.box.x, c.box.y); add(c.box.x + c.box.w, c.box.y + c.box.h + (isActorC(c) ? 20 : 0)); }
    for (const p of [...(c.pts || []), c.sp, c.tp].filter(Boolean)) add(p[0], p[1]);
  }
  if (!Number.isFinite(x0)) return { x: 0, y: 0, w: 400, h: 300 };
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}
const wrapWords = (s, max) => { const out = []; let cur = ''; for (const w of String(s).split(/\s+/)) { if (cur && (cur + ' ' + w).length > max) { out.push(cur); cur = w; } else cur = cur ? `${cur} ${w}` : w; } if (cur) out.push(cur); return out; };
const LEGEND_W = 430;
function legendLines(items, L) {
  const rows = [];
  for (const it of items) rows.push({ it, what: wrapWords(`${L.sev[it.sev]}: ${it.what}`, 62), fix: wrapWords(it.fix, 66) });
  return rows;
}
const legendHeight = (rows) => 44 + rows.reduce((h, r) => h + r.what.length * 15 + r.fix.length * 13 + 10, 0);

/** Bản .drawio của khách + khung màu quanh phần tử sai + số + bảng chú thích bên phải. Hình gốc không bị sửa. */
export function annotateDrawio(parsed, items, lang = 'vi') {
  const L = T[lang] || T.vi;
  const gm = JSON.parse(JSON.stringify(parsed.page.model));
  const root = gm.children.find((c) => c.tag === 'root');
  const layer = root.children.find((c) => c.tag === 'mxCell' && c.attrs.parent === '0')?.attrs.id || '1';
  const geom = parsed.model._geom, cellOf = parsed.model._cells;
  const bounds = contentBounds(parsed.cells);
  let k = 0;
  const add = (value, style, x, y, w, h) => root.children.push({ tag: 'mxCell', attrs: { id: `vd_${++k}`, value, style: `${style}vdReview=1;`, vertex: '1', parent: layer }, text: '',
    children: [{ tag: 'mxGeometry', attrs: { x: String(Math.round(x)), y: String(Math.round(y)), width: String(Math.round(w)), height: String(Math.round(h)), as: 'geometry' }, children: [], text: '' }] });
  const nodeOf = (cellId) => { for (const n of root.children) { if (n.tag === 'mxCell' && n.attrs.id === cellId) return n; if ((n.tag === 'UserObject' || n.tag === 'object') && n.attrs.id === cellId) return n.children.find((c) => c.tag === 'mxCell'); } return null; };
  for (const it of items) {
    const color = SEV_COLOR[it.sev];
    for (const b of boxesOfItem(it, geom)) add('', `rounded=1;arcSize=12;fillColor=none;strokeColor=${color};strokeWidth=2.5;`, b.x - 6, b.y - 6, b.w + 12, b.h + 12);
    for (const r of colorRefs(it)) { if (!geom[r]?.line || !cellOf[r]) continue; const n = nodeOf(cellOf[r]); if (n) n.attrs.style = `${n.attrs.style || ''};strokeColor=${color};strokeWidth=2.5;fontColor=${color};`.replace(/;;+/g, ';'); }
  }
  for (const s of placeMarkers(items, geom, bounds)) add(String(s.num), `ellipse;html=1;fillColor=${SEV_COLOR[s.sev]};strokeColor=#FFFFFF;strokeWidth=1.5;fontColor=#FFFFFF;fontStyle=1;fontSize=12;align=center;verticalAlign=middle;`, s.x - 11, s.y - 11, 22, 22);
  const e = items.filter((i) => i.sev === 'error').length, rv = items.length - e;
  const rows = legendLines(items, L);
  const html = `<b style="font-size:14px">${escText(L.legendTitle(e, rv))}</b><br><br>${rows.map((r) => `<font color="${SEV_COLOR[r.it.sev]}"><b>${r.it.num}. ${escText(L.sev[r.it.sev])}:</b></font> ${escText(r.it.what)}<br><font color="#555555">→ ${escText(r.it.fix)}</font>`).join('<br><br>')}`;
  add(html, 'text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;spacing=10;fillColor=#FFFFFF;strokeColor=#BBBBBB;rounded=1;arcSize=3;fontSize=12;', bounds.x + bounds.w + 50, bounds.y - 20, LEGEND_W, legendHeight(rows));
  return `<mxfile host="kickoff-uml uc-review" agent="kickoff-uml uc-review"><diagram id="review" name="${escAttr(L.pageName)}">${serializeXml(gm)}</diagram></mxfile>\n`;
}

// ---------------------------------------------------------------- SVG dự phòng (máy không có draw.io): vẽ lại hình của khách từ toạ độ đã đọc
const FONT = 'Helvetica, Arial, sans-serif';
const markerDefs = () => `<defs>
<marker id="m-classic" markerWidth="12" markerHeight="12" refX="11" refY="6" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L12,6 L0,12 L3,6 Z" fill="context-stroke"/></marker>
<marker id="m-open" markerWidth="12" markerHeight="12" refX="11" refY="6" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L12,6 L0,12" fill="none" stroke="context-stroke"/></marker>
<marker id="m-block" markerWidth="14" markerHeight="14" refX="13" refY="7" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L14,7 L0,14 Z" fill="#fff" stroke="context-stroke"/></marker>
<marker id="m-blockf" markerWidth="14" markerHeight="14" refX="13" refY="7" orient="auto" markerUnits="userSpaceOnUse"><path d="M0,0 L14,7 L0,14 Z" fill="context-stroke"/></marker>
<marker id="m-classic-s" markerWidth="12" markerHeight="12" refX="1" refY="6" orient="auto" markerUnits="userSpaceOnUse"><path d="M12,0 L0,6 L12,12 L9,6 Z" fill="context-stroke"/></marker>
<marker id="m-open-s" markerWidth="12" markerHeight="12" refX="1" refY="6" orient="auto" markerUnits="userSpaceOnUse"><path d="M12,0 L0,6 L12,12" fill="none" stroke="context-stroke"/></marker>
<marker id="m-block-s" markerWidth="14" markerHeight="14" refX="1" refY="7" orient="auto" markerUnits="userSpaceOnUse"><path d="M14,0 L0,7 L14,14 Z" fill="#fff" stroke="context-stroke"/></marker>
</defs>`;
const markerOf = (kind, fill, start) => {
  if (!kind || kind === 'none') return '';
  const base = /block|triangle/.test(kind) ? (fill && !start ? 'm-blockf' : 'm-block') : kind === 'open' ? 'm-open' : 'm-classic';
  return start ? `marker-start="url(#${base.replace('f', '')}-s)"` : `marker-end="url(#${base})"`;
};
function svgText(o, x, y, s, opt = {}) {
  const lines = Array.isArray(s) ? s : [s];
  const fs = opt.size || 12, lh = fs * 1.25;
  lines.forEach((ln, i) => o.push(`<text x="${x}" y="${y + i * lh}" text-anchor="${opt.anchor || 'middle'}" font-family="${FONT}" font-size="${fs}"${opt.bold ? ' font-weight="bold"' : ''} fill="${opt.color || '#000'}">${escText(ln)}</text>`));
}
const wrapToWidth = (s, w, fs = 12) => String(s).split('\n').flatMap((l) => wrapWords(l, Math.max(4, Math.floor((w * 0.9) / (fs * 0.55)))));

export function renderCustomerSvg(parsed, items, lang = 'vi', opts = {}) {
  const L = T[lang] || T.vi;
  const geom = parsed.model._geom, cellOf = parsed.model._cells;
  const red = new Map();
  for (const it of items) for (const r of colorRefs(it)) if (geom[r]?.line && cellOf[r] && !red.has(cellOf[r])) red.set(cellOf[r], SEV_COLOR[it.sev]);
  const B = opts.bounds || contentBounds(parsed.cells);
  const rows = legendLines(items, L);
  const legend = opts.legend !== false;
  const pad = 40, W = B.w + pad * 2 + (legend ? LEGEND_W + 50 : 0), H = Math.max(B.h + pad * 2 + 20, legend ? legendHeight(rows) + pad * 2 : 0);
  const ox = pad - B.x, oy = pad + 20 - B.y;
  const o = [];
  const vtx = parsed.cells.filter((c) => c.vertex && c.box && !parsed.byId.get(c.parent)?.edge);
  const frames = vtx.filter((c) => !isActorC(c) && !isEllipseC(c) && !isNoteC(c) && !isTextC(c)).sort((a, b) => b.box.w * b.box.h - a.box.w * a.box.h);
  for (const c of frames) {
    const b = c.box, x = b.x + ox, y = b.y + oy, fs = Number(c.st.fontSize || 12);
    const fill = c.st.fillColor && c.st.fillColor !== 'none' ? c.st.fillColor : 'none', stroke = c.st.strokeColor === 'none' ? 'none' : c.st.strokeColor || '#000';
    o.push(`<rect x="${x}" y="${y}" width="${b.w}" height="${b.h}" rx="${c.st.rounded === '1' ? Math.min(b.w, b.h) * 0.1 : 0}" fill="${fill}" stroke="${stroke}"/>`);
    const t = labelText(c.value);
    if (t) { const top = c.st.verticalAlign === 'top' || c.st._base.includes('swimlane'); const ls = wrapToWidth(t, b.w, fs); svgText(o, x + b.w / 2, top ? y + fs + 6 : y + b.h / 2 - ((ls.length - 1) * fs * 1.25) / 2 + fs * 0.35, ls, { size: fs, bold: (Number(c.st.fontStyle) & 1) === 1 }); }
  }
  for (const c of parsed.cells.filter((x) => x.edge && !isMark(x))) {
    const line = parsed.allLines.get(c.id);
    if (!line) continue;
    const color = red.get(c.id) || (c.st.strokeColor && c.st.strokeColor !== 'none' ? c.st.strokeColor : '#000');
    const dash = c.st.dashed === '1' ? 'stroke-dasharray="6 4"' : '';
    o.push(`<polyline points="${line.map((p) => `${p[0] + ox},${p[1] + oy}`).join(' ')}" fill="none" stroke="${color}" stroke-width="${red.has(c.id) ? 2.5 : 1.2}" ${dash} ${markerOf(arrowOf(c.st, 't'), fillOf(c.st, 't'), false)} ${markerOf(arrowOf(c.st, 's'), fillOf(c.st, 's'), true)}/>`);
    const lbl = [labelText(c.value), ...parsed.cells.filter((x) => x.parent === c.id && x.vertex).map((x) => labelText(x.value))].filter(Boolean).join('\n');
    if (lbl) { const [mx, my] = midOf(line); const ls = lbl.split('\n'), tw = Math.max(...ls.map((l) => l.length)) * 5.6 + 6; o.push(`<rect x="${mx + ox - tw / 2}" y="${my + oy - 9}" width="${tw}" height="${ls.length * 13 + 2}" fill="#fff" opacity="0.85"/>`); svgText(o, mx + ox, my + oy + 2, ls, { size: 10, color }); }
  }
  for (const c of vtx) {
    const b = c.box, x = b.x + ox, y = b.y + oy, fs = Number(c.st.fontSize || 12), t = labelText(c.value);
    const stroke = c.st.strokeColor && c.st.strokeColor !== 'none' ? c.st.strokeColor : '#000', fill = c.st.fillColor && c.st.fillColor !== 'none' ? c.st.fillColor : '#fff';
    if (isEllipseC(c)) {
      o.push(`<ellipse cx="${x + b.w / 2}" cy="${y + b.h / 2}" rx="${b.w / 2}" ry="${b.h / 2}" fill="${fill}" stroke="${stroke}"/>`);
      const [nm, ...rest] = t.split(/\n?—\n?/);
      const ls = wrapToWidth(nm || '', b.w * 0.92, fs);
      svgText(o, x + b.w / 2, y + b.h / 2 - ((ls.length - 1) * fs * 1.25) / 2 + fs * 0.35 - (rest.length ? b.h * 0.18 : 0), ls, { size: fs });
      if (rest.length) svgText(o, x + b.w / 2, y + b.h * 0.68, rest.join('\n').split('\n').slice(0, 3), { size: 9 });
    } else if (isActorC(c)) {
      const cx = x + b.w / 2;
      o.push(`<circle cx="${cx}" cy="${y + b.h / 8}" r="${Math.min(b.w / 4, b.h / 8)}" fill="${fill}" stroke="${stroke}"/>`,
        `<line x1="${cx}" y1="${y + b.h / 4}" x2="${cx}" y2="${y + (2 * b.h) / 3}" stroke="${stroke}"/>`, `<line x1="${x}" y1="${y + b.h / 3}" x2="${x + b.w}" y2="${y + b.h / 3}" stroke="${stroke}"/>`,
        `<line x1="${cx}" y1="${y + (2 * b.h) / 3}" x2="${x}" y2="${y + b.h}" stroke="${stroke}"/>`, `<line x1="${cx}" y1="${y + (2 * b.h) / 3}" x2="${x + b.w}" y2="${y + b.h}" stroke="${stroke}"/>`);
      svgText(o, cx, y + b.h + fs + 3, t.split('\n'), { size: fs });
    } else if (isNoteC(c)) {
      const f = 10;
      o.push(`<path d="M${x},${y} L${x + b.w - f},${y} L${x + b.w},${y + f} L${x + b.w},${y + b.h} L${x},${y + b.h} Z" fill="${fill}" stroke="${stroke}"/>`);
      svgText(o, x + 6, y + fs + 3, wrapToWidth(t, b.w - 10, fs - 1), { size: fs - 1, anchor: 'start' });
    } else if (isTextC(c) && t) {
      const ls = wrapToWidth(t, Math.max(b.w, 60), fs);
      svgText(o, x + b.w / 2, y + b.h / 2 - ((ls.length - 1) * fs * 1.25) / 2 + fs * 0.35, ls, { size: fs, bold: (Number(c.st.fontStyle) & 1) === 1 });
    }
  }
  for (const it of items) for (const b of boxesOfItem(it, geom)) o.push(`<rect x="${b.x + ox - 6}" y="${b.y + oy - 6}" width="${b.w + 12}" height="${b.h + 12}" rx="8" fill="none" stroke="${SEV_COLOR[it.sev]}" stroke-width="2.5"/>`);
  for (const s of placeMarkers(items, geom, B)) badgeSvg(o, s.x + ox, s.y + oy, s.num, s.sev);
  if (legend) legendSvg(o, items, L, B.x + B.w + ox + 50, pad);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${Math.ceil(W)}" height="${Math.ceil(H)}" viewBox="0 0 ${Math.ceil(W)} ${Math.ceil(H)}">\n${markerDefs()}\n<rect width="100%" height="100%" fill="#fff"/>\n${o.join('\n')}\n</svg>\n`;
}
/**
 * Lớp đánh dấu theo toạ độ của renderCustomerSvg (cùng opts.bounds, không chú thích) — để web/animation tự vẽ số, khung, đường tô màu
 * lên hình .before.svg thay vì dùng ảnh PNG đã vẽ sẵn. Toạ độ: tâm số (markers), khung bo (boxes), đường gấp khúc (lines).
 */
export function overlayOf(parsed, items, opts = {}) {
  const geom = parsed.model._geom, B = opts.bounds || contentBounds(parsed.cells);
  const pad = 40, ox = pad - B.x, oy = pad + 20 - B.y, r1 = (v) => Math.round(v * 10) / 10;
  const spots = placeMarkers(items, geom, B);
  return {
    width: Math.ceil(B.w + pad * 2), height: Math.ceil(B.h + pad * 2 + 20),
    items: items.map((it) => ({
      num: it.num, sev: it.sev, what: it.what, fix: it.fix, ...(it.suggestion ? { suggestion: it.suggestion } : {}), ...(it.uncertain ? { uncertain: true } : {}),
      markers: spots.filter((s) => s.num === it.num).map((s) => ({ x: r1(s.x + ox), y: r1(s.y + oy) })),
      boxes: boxesOfItem(it, geom).map((b) => ({ x: r1(b.x + ox - 6), y: r1(b.y + oy - 6), w: r1(b.w + 12), h: r1(b.h + 12) })),
      lines: colorRefs(it).filter((r) => geom[r]?.line).map((r) => geom[r].line.map((p) => [r1(p[0] + ox), r1(p[1] + oy)])),
    })),
  };
}
const unionBox = (...bs) => { const x = Math.min(...bs.map((b) => b.x)), y = Math.min(...bs.map((b) => b.y)); return { x, y, w: Math.max(...bs.map((b) => b.x + b.w)) - x, h: Math.max(...bs.map((b) => b.y + b.h)) - y }; };

function badgeSvg(o, x, y, num, sev) {
  o.push(`<circle cx="${x}" cy="${y}" r="11" fill="${SEV_COLOR[sev]}" stroke="#fff" stroke-width="1.5"/>`);
  o.push(`<text x="${x}" y="${y + 4.3}" text-anchor="middle" font-family="${FONT}" font-size="12" font-weight="bold" fill="#fff">${num}</text>`);
}
function legendSvg(o, items, L, x, y) {
  const rows = legendLines(items, L), h = legendHeight(rows);
  const e = items.filter((i) => i.sev === 'error').length;
  o.push(`<rect x="${x}" y="${y}" width="${LEGEND_W}" height="${h}" rx="6" fill="#fff" stroke="#bbb"/>`);
  svgText(o, x + 14, y + 24, L.legendTitle(e, items.length - e), { size: 14, bold: true, anchor: 'start' });
  let yy = y + 50;
  for (const r of rows) {
    badgeSvg(o, x + 24, yy - 4, r.it.num, r.it.sev);
    r.what.forEach((ln, i) => o.push(`<text x="${x + 42}" y="${yy + i * 15}" font-family="${FONT}" font-size="12" fill="${SEV_COLOR[r.it.sev]}" font-weight="bold">${escText(ln)}</text>`));
    yy += r.what.length * 15;
    r.fix.forEach((ln, i) => o.push(`<text x="${x + 42}" y="${yy + i * 13}" font-family="${FONT}" font-size="11" fill="#555">${escText(i === 0 ? `→ ${ln}` : ln)}</text>`));
    yy += r.fix.length * 13 + 10;
  }
}

/** Ảnh gốc của khách + khung/số theo toạ độ trong bản chép (_geom, đơn vị pixel ảnh) + chú thích bên phải. */
export function renderImageSvg(imageFile, model, items, lang = 'vi') {
  const L = T[lang] || T.vi;
  const buf = fs.readFileSync(imageFile);
  const size = imageSize(buf) || { w: model._source?.width || 1200, h: model._source?.height || 800 };
  const mime = buf[0] === 0x89 ? 'image/png' : buf[0] === 0xff ? 'image/jpeg' : 'image/png';
  const rows = legendLines(items, L);
  const pad = 30, W = size.w + pad * 2 + LEGEND_W + 30, H = Math.max(size.h + pad * 2 + 20, legendHeight(rows) + pad * 2);
  const ox = pad, oy = pad + 20, geom = model._geom || {};
  const o = [`<image href="data:${mime};base64,${buf.toString('base64')}" x="${ox}" y="${oy}" width="${size.w}" height="${size.h}"/>`, `<rect x="${ox}" y="${oy}" width="${size.w}" height="${size.h}" fill="none" stroke="#ddd"/>`];
  for (const it of items) for (const b of boxesOfItem(it, geom)) o.push(`<rect x="${b.x + ox - 6}" y="${b.y + oy - 6}" width="${b.w + 12}" height="${b.h + 12}" rx="8" fill="none" stroke="${SEV_COLOR[it.sev]}" stroke-width="3"${it.uncertain ? ' stroke-dasharray="6 4"' : ''}/>`);
  // đường tự nối (synth) chỉ để đặt số — không tô lên ảnh vì có thể lệch khỏi nét thật
  for (const it of items) for (const r of colorRefs(it)) { const g = geom[r]; if (g?.line && !g.synth) o.push(`<polyline points="${g.line.map((p) => `${p[0] + ox},${p[1] + oy}`).join(' ')}" fill="none" stroke="${SEV_COLOR[it.sev]}" stroke-width="3" opacity="0.75"/>`); }
  for (const s of placeMarkers(items, geom, { x: 0, y: 0, w: size.w, h: size.h })) badgeSvg(o, s.x + ox, s.y + oy, s.num, s.sev);
  legendSvg(o, items, L, size.w + ox + 30, pad);
  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${Math.ceil(W)}" height="${Math.ceil(H)}" viewBox="0 0 ${Math.ceil(W)} ${Math.ceil(H)}">\n<rect width="100%" height="100%" fill="#fff"/>\n${o.join('\n')}\n</svg>\n`;
}
export function imageSize(buf) {
  if (buf.length > 24 && buf[0] === 0x89 && buf.toString('ascii', 12, 16) === 'IHDR') return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
  if (buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i < buf.length - 9) {
      if (buf[i] !== 0xff) { i++; continue; }
      const mk = buf[i + 1], len = buf.readUInt16BE(i + 2);
      if (mk >= 0xc0 && mk <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(mk)) return { h: buf.readUInt16BE(i + 5), w: buf.readUInt16BE(i + 7) };
      i += 2 + len;
    }
  }
  return null;
}

// ================================================================ "Vẽ lại": sửa model rồi vẽ bằng renderer tầng 0
const stripPrivate = (m) => Object.fromEntries(Object.entries(JSON.parse(JSON.stringify(m))).filter(([k]) => !k.startsWith('_')));
/**
 * Áp sửa: (1) chắc chắn & máy tự làm (đổi tên có gợi ý, bỏ dây actor tới nhánh extend, bỏ actor "System"/actor lẻ, gộp trùng tên);
 * (2) theo ai.json (actions, suggest.rename/condition, suggest.subject); (3) lỗi ký hiệu/vị trí thì vẽ lại là hết.
 * Mục không tự sửa được nằm ở `pending` để hỏi khách.
 */
export function fixModel(model, items, ai = {}, lang = 'vi', opts = {}) {
  const L = T[lang] || T.vi;
  const m = stripPrivate(model);
  m.extends = m.extends || []; m.includes = m.includes || []; m.generalizations = m.generalizations || []; m.associations = m.associations || []; m.actorParents = m.actorParents || {};
  const names = relName(model);
  const ucN = (id) => m.usecases.find((u) => u.id === id)?.name ?? id, acN = (id) => m.actors.find((a) => a.id === id)?.name ?? id;
  const sugg = ai.suggest || {};
  const changes = [], pending = [], linkedBy = new Map();   // linkedBy: "actor:A1"/"uc:UC2" → số mục đã nối nó
  // sure: máy sửa theo luật cố định (ký hiệu, vị trí, actor "System"); còn lại là đề xuất (đổi tên, điều kiện, quyết định của AI) — khách xem lại
  const note = (it, text, sure = false) => changes.push({ num: it?.num ?? null, text, sure });
  const removeUc = (id) => { m.usecases = m.usecases.filter((u) => u.id !== id); m.associations = m.associations.filter((x) => x.usecase !== id); m.includes = m.includes.filter((x) => x.base !== id && x.part !== id); m.extends = m.extends.filter((x) => x.extending !== id && x.base !== id); m.generalizations = m.generalizations.filter((x) => x.child !== id && x.parent !== id); };
  const removeActor = (id) => { m.actors = m.actors.filter((a) => a.id !== id); m.associations = m.associations.filter((x) => x.actor !== id); for (const [c, p] of Object.entries(m.actorParents)) if (c === id || p === id) delete m.actorParents[c]; };
  const relParts = (r) => { const [kind, rest] = r.split(/:(.+)/); const [a, b] = (rest || '').split('>'); return { kind, a, b }; };
  const removeRel = (r) => {
    const { kind, a, b } = relParts(r);
    if (kind === 'assoc') m.associations = m.associations.filter((x) => !(x.actor === a && x.usecase === b));
    if (kind === 'include') m.includes = m.includes.filter((x) => !(x.base === a && x.part === b));
    if (kind === 'extend') m.extends = m.extends.filter((x) => !(x.extending === a && x.base === b));
    if (kind === 'ucgen') m.generalizations = m.generalizations.filter((x) => !(x.child === a && x.parent === b));
    if (kind === 'actorgen' && m.actorParents[a] === b) delete m.actorParents[a];
    if (kind === 'uc') removeUc(a);
    if (kind === 'actor') removeActor(a);
  };
  const applyAction = (act, it) => {
    if (!act?.type) return false;
    const { kind, a, b } = relParts(act.ref || '');
    if (act.type === 'rename') { const u = m.usecases.find((x) => `uc:${x.id}` === act.ref) || m.actors.find((x) => `actor:${x.id}` === act.ref); if (!u) return false; const old = u.name; u.name = act.to; note(it, L.renamed(old, act.to)); return true; }
    if (act.type === 'remove') { const nm = names(act.ref); removeRel(act.ref); note(it, kind === 'uc' ? L.removedUc(nm[0]) : kind === 'actor' ? L.removedActor(nm[0]) : kind === 'assoc' ? L.removedAssoc(nm[0], nm[1]) : `${L.removedAssoc(nm[0], nm[1] ?? '')}`); return true; }
    if (act.type === 'retype') {
      removeRel(act.ref);
      if (act.to === 'extend') m.extends.push({ extending: kind === 'include' ? b : a, base: kind === 'include' ? a : b, ...(act.condition ? { condition: act.condition } : {}) });
      else if (act.to === 'include') m.includes.push({ base: kind === 'extend' ? b : a, part: kind === 'extend' ? a : b });
      else if (act.to === 'generalization') m.generalizations.push({ child: a, parent: b });
      note(it, L.retyped(ucN(a), ucN(b), act.to)); return true;
    }
    if (act.type === 'flip') {
      const list = kind === 'include' ? m.includes : kind === 'extend' ? m.extends : kind === 'ucgen' ? m.generalizations : null;
      const x = list?.find((y) => Object.values(y).includes(a) && Object.values(y).includes(b));
      if (!x) return false;
      if (kind === 'include') [x.base, x.part] = [x.part, x.base]; else if (kind === 'extend') [x.extending, x.base] = [x.base, x.extending]; else [x.child, x.parent] = [x.parent, x.child];
      note(it, L.flipped(ucN(a), ucN(b))); return true;
    }
    if (act.type === 'connect') {
      // hai đầu phải còn trên sơ đồ (không để dây treo vào actor/UC đã bỏ)
      if (!m.actors.some((x) => x.id === act.actor) || !m.usecases.some((u) => u.id === act.usecase)) return false;
      if (!m.associations.some((x) => x.actor === act.actor && x.usecase === act.usecase)) m.associations.push({ actor: act.actor, usecase: act.usecase });
      if (it?.num) { linkedBy.set(`actor:${act.actor}`, it.num); linkedBy.set(`uc:${act.usecase}`, it.num); }
      note(it, L.connected(acN(act.actor), ucN(act.usecase))); return true;
    }
    if (act.type === 'condition') { const x = m.extends.find((y) => y.extending === a && y.base === b); if (!x) return false; x.condition = act.text; if (act.point) x.point = act.point; note(it, L.condSet(ucN(a), ucN(b), act.text)); return true; }
    if (act.type === 'side') { const x = m.actors.find((y) => y.id === act.actor); if (x) x.side = act.side; return !!x; }
    if (act.type === 'add') {
      if (act.rel === 'extend' && !m.extends.some((y) => y.extending === act.extending && y.base === act.base)) { m.extends.push({ extending: act.extending, base: act.base, ...(act.condition ? { condition: act.condition } : {}) }); note(it, L.retyped(ucN(act.extending), ucN(act.base), 'extend')); return true; }
      if (act.rel === 'include' && !m.includes.some((y) => y.base === act.base && y.part === act.part)) { m.includes.push({ base: act.base, part: act.part }); note(it, L.retyped(ucN(act.base), ucN(act.part), 'include')); return true; }
      if (act.rel === 'generalization' && !m.generalizations.some((y) => y.child === act.child && y.parent === act.parent)) { m.generalizations.push({ child: act.child, parent: act.parent }); note(it, L.retyped(ucN(act.child), ucN(act.parent), 'generalization')); return true; }
      return false;
    }
    return false;
  };
  const usedActs = new Set(), touched = new Map();   // ref → số mục đã đổi/bỏ nó
  const actsFor = (it) => [...(it.action ? [it.action] : []), ...(ai.actions || []).filter((x) => it.refs.includes(x.ref) || it.refs.includes(x.for))].filter((x) => !usedActs.has(x));
  // phần tử của mục đã bị action khác bỏ/đổi (vd extend được nối lại sang UC khác) → mục tự hết, không treo "chưa sửa"
  const gone = (r) => {
    const { kind, a, b } = relParts(r);
    if (kind === 'uc') return !m.usecases.some((u) => u.id === a);
    if (kind === 'actor') return !m.actors.some((x) => x.id === a);
    if (kind === 'assoc') return !m.associations.some((x) => x.actor === a && x.usecase === b);
    if (kind === 'include') return !m.includes.some((x) => x.base === a && x.part === b);
    if (kind === 'extend') return !m.extends.some((x) => x.extending === a && x.base === b);
    if (kind === 'ucgen') return !m.generalizations.some((x) => x.child === a && x.parent === b);
    return false;
  };
  const applySuggestFor = (it) => {
    for (const r of it.refs) {
      const sg = sugg[r]; if (!sg) continue;
      const { kind, a, b } = relParts(r);
      if (sg.rename && (kind === 'uc' || kind === 'actor')) { const x = (kind === 'uc' ? m.usecases : m.actors).find((y) => y.id === a); if (x && x.name !== sg.rename) { const old = x.name; x.name = sg.rename; note(it, L.renamed(old, sg.rename)); return true; } }
      if (sg.condition && kind === 'extend') { const x = m.extends.find((y) => y.extending === a && y.base === b); if (x && x.condition !== sg.condition) { x.condition = sg.condition; if (sg.point) x.point = sg.point; note(it, L.condSet(ucN(a), ucN(b), sg.condition)); return true; } }
    }
    return false;
  };
  const REDRAW = new Set(['actor-inside', 'uc-outside', 'rel-style-solid', 'rel-no-arrow', 'assoc-arrow', 'gen-filled', 'uses', 'crossing', 'overlap', 'rel-on-actor']);
  // mục của AI nhận action của nó trước, rồi mới tới mục máy
  for (const it of [...items.filter((x) => x.source === 'ai'), ...items.filter((x) => x.source !== 'ai')]) {
    if (it.source !== 'ai' && it.refs.length && it.refs.every(gone)) { const by = it.refs.map((r) => touched.get(r)).find(Boolean); if (by) note(it, L.handledWith(circled(by))); continue; }
    const acts = actsFor(it);
    if (acts.length) { let ok = false; for (const a of acts) { usedActs.add(a); const done = applyAction(a, it); if (done && a.ref && it.num) touched.set(a.ref, it.num); ok = done || ok; } if (ok) continue; }
    const r0 = it.refs[0];
    switch (it.code) {
      case 'name-noun': case 'name-case': case 'name-short': case 'actor-case': {
        const id = r0?.split(':')[1], u = (it.code === 'actor-case' ? m.actors : m.usecases).find((x) => x.id === id);
        const to = sugg[r0]?.rename || it.suggestion;
        if (u && to) { const old = u.name; u.name = to; note(it, L.renamed(old, to)); } else pending.push(it);
        break;
      }
      case 'extend-cond': {
        const { a, b } = relParts(r0); const x = m.extends.find((y) => y.extending === a && y.base === b);
        const c = sugg[r0]?.condition;
        if (x && c) { x.condition = c; if (sugg[r0]?.point) x.point = sugg[r0].point; note(it, L.condSet(ucN(a), ucN(b), c)); } else pending.push(it);
        break;
      }
      case 'extend-actor': { for (const r of it.refs.filter((x) => x.startsWith('assoc:'))) { const nm = names(r); removeRel(r); note(it, L.removedAssoc(nm[0], nm[1])); } break; }
      case 'actor-system': { const id = r0?.split(':')[1]; if (id) { note(it, L.removedActor(acN(id)), true); removeActor(id); } break; }
      // actor đứng riêng: thường là quên dây nối chứ không phải actor thừa → không đoán bỏ; khách quyết, hoặc bước AI nối (câu O)
      case 'dup-name': {
        const ids = it.refs.map((r) => r.split(':')[1]), keep = ids[0];
        for (const d of ids.slice(1)) {
          const re = (x) => (x === d ? keep : x);
          m.associations = m.associations.map((x) => ({ ...x, usecase: re(x.usecase) })); m.includes = m.includes.map((x) => ({ base: re(x.base), part: re(x.part) }));
          m.extends = m.extends.map((x) => ({ ...x, extending: re(x.extending), base: re(x.base) })); m.generalizations = m.generalizations.map((x) => ({ child: re(x.child), parent: re(x.parent) }));
          m.usecases = m.usecases.filter((u) => u.id !== d);
        }
        const dd = (arr, key) => { const s = new Set(); return arr.filter((x) => { const k = key(x); if (s.has(k)) return false; s.add(k); return true; }); };
        m.associations = dd(m.associations, (x) => `${x.actor}|${x.usecase}`); m.includes = dd(m.includes, (x) => `${x.base}|${x.part}`).filter((x) => x.base !== x.part);
        m.extends = dd(m.extends, (x) => `${x.extending}|${x.base}`).filter((x) => x.extending !== x.base); m.generalizations = dd(m.generalizations, (x) => `${x.child}|${x.parent}`).filter((x) => x.child !== x.parent);
        note(it, L.merged(ucN(keep)));
        break;
      }
      // đường lơ lửng / quay về chính nó: bản vẽ lại không có đường đó; sửa tại chỗ thì applyInPlace xoá đường và tự ghi dòng "Bỏ …"
      case 'dangling': case 'self-loop':
        if (!opts.inplace) note(it, L.redrawn(it.what.replace(/\.$/, '')), true);
        break;
      case 'no-subject': case 'subject-name': {
        const s = sugg.subject?.name;
        if (s) { m.subject = { name: s }; note(it, L.subjectNamed(s)); }
        else { m.subject = { name: m.subject?.name || L.defaultSubject }; pending.push(it); }
        break;
      }
      default:
        if (applySuggestFor(it)) break;
        if (REDRAW.has(it.code) && !(opts.inplace && INPLACE_SKIP.has(it.code))) note(it, (opts.inplace ? L.fixedHere : L.redrawn)(it.what.replace(/\.$/, '')), true);
        else pending.push(it);
    }
  }
  // gợi ý còn lại của AI (đổi tên/điều kiện cho phần tử không có mục riêng, kể cả extend mới sinh từ retype)
  for (const [r, s] of Object.entries(sugg)) {
    if (r === 'subject') continue;
    const { kind, a, b } = relParts(r);
    if (kind === 'extend' && s.condition) { const x = m.extends.find((y) => y.extending === a && y.base === b); if (x && x.condition !== s.condition) { x.condition = s.condition; if (s.point) x.point = s.point; note(null, L.condSet(ucN(a), ucN(b), s.condition)); } }
    if (kind === 'uc' && s.rename) { const u = m.usecases.find((y) => y.id === a); if (u && u.name !== s.rename) { const old = u.name; u.name = s.rename; note(null, L.renamed(old, s.rename)); } }
  }
  for (const act of ai.actions || []) if (!usedActs.has(act)) { usedActs.add(act); applyAction(act, null); }
  // mục "đứng riêng" đã được mục khác nối (vd AI nối Guest với Register Account ở mục UC) → không treo "chưa sửa"
  const linked = (r) => {
    const { kind, a } = relParts(r);
    if (kind === 'actor') return m.associations.some((x) => x.actor === a);
    if (kind === 'uc') return m.associations.some((x) => x.usecase === a) || m.includes.some((x) => x.base === a || x.part === a) || m.extends.some((x) => x.extending === a || x.base === a) || m.generalizations.some((x) => x.child === a || x.parent === a);
    return false;
  };
  for (let i = pending.length - 1; i >= 0; i--) {
    const it = pending[i];
    if (!['actor-lonely', 'uc-lonely'].includes(it.code) || !it.refs.length) continue;
    const isGone = it.refs.every(gone);
    if (!isGone && !it.refs.every(linked)) continue;
    pending.splice(i, 1);
    const by = it.refs.map((r) => (isGone ? touched : linkedBy).get(r)).find((k) => k && k !== it.num);
    if (by) note(it, L.handledWith(circled(by)));
  }
  if (!m.subject?.name) m.subject = { name: L.defaultSubject };
  changes.sort((p, q) => (p.num ?? 1e9) - (q.num ?? 1e9));
  pending.sort((p, q) => p.num - q.num);
  return { model: m, changes, pending };
}

export async function renderFixed(model, outBase, opts = {}) {
  const L = layout(model, {});
  fs.writeFileSync(`${outBase}.drawio`, toDrawio(model, L, { model: path.basename(`${outBase}.model.json`) }));
  fs.writeFileSync(`${outBase}.svg`, toSvg(model, L));
  if (opts.png === false) return { png: null, via: null, stats: L.stats };
  const r = await renderPng(`${outBase}.drawio`, `${outBase}.svg`);
  return { png: r.png, via: r.via, stats: L.stats };
}

async function svgToPng(svgFile, pngFile) {
  try {
    const { chromium } = createRequire(path.join(process.cwd(), 'x.js'))('playwright');
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 1200, height: 800 }, deviceScaleFactor: 2 });
    await page.goto(pathToFileURL(svgFile).href);
    await (await page.$('svg')).screenshot({ path: pngFile });
    await browser.close();
    return 'playwright';
  } catch (e) {
    const { spawnSync } = await import('node:child_process');
    const r = spawnSync('rsvg-convert', ['-o', pngFile, svgFile], { encoding: 'utf8' });
    return r.status === 0 ? 'rsvg-convert' : null;
  }
}

// ================================================================ bước AI bằng CÂU HỎI ĐÓNG
// Model nhỏ (DeepSeek V4.1 Flash qua `cmd -p` của Command Code, `claude -p`, dsh headless…) chỉ trả lời có/không + vài chữ.
// Script tự đổi câu trả lời thành lời cho khách theo mẫu và thành lệnh sửa: model không viết báo cáo, không đụng XML,
// không bịa được phần tử (id lạ bị loại). Không chắc thì model được dặn trả "đúng" — thà sót còn hơn báo nhầm.
const QCAP = 30;
export function buildQuestions(model, items = [], lang = 'vi') {
  const U = new Map((model.usecases || []).map((u) => [u.id, u.name])), A = new Map((model.actors || []).map((a) => [a.id, a.name]));
  const q = [];
  (model.includes || []).slice(0, QCAP).forEach((x, i) => q.push({ id: `I${i + 1}`, kind: 'include', ref: `include:${x.base}>${x.part}`, x,
    text: `"${U.get(x.base)}" «include» "${U.get(x.part)}": mỗi lần làm "${U.get(x.base)}" có LUÔN LUÔN phải làm "${U.get(x.part)}" không? Nếu không thì nên là gì?` }));
  (model.extends || []).slice(0, QCAP).forEach((x, i) => q.push({ id: `E${i + 1}`, kind: 'extend', ref: `extend:${x.extending}>${x.base}`, x,
    text: `"${U.get(x.extending)}" «extend» "${U.get(x.base)}": đây có phải phần TUỲ CHỌN, chỉ xảy ra khi có điều kiện, bên trong "${U.get(x.base)}" không? Điều kiện là gì? Nếu nó thuộc use case khác thì là id nào?` }));
  (model.generalizations || []).slice(0, QCAP).forEach((x, i) => q.push({ id: `G${i + 1}`, kind: 'ucgen', ref: `ucgen:${x.child}>${x.parent}`, x,
    text: `"${U.get(x.child)}" có phải MỘT KIỂU (một cách làm cụ thể) của "${U.get(x.parent)}" không?` }));
  Object.entries(model.actorParents || {}).slice(0, 10).forEach(([c, p], i) => q.push({ id: `AG${i + 1}`, kind: 'actorgen', ref: `actorgen:${c}>${p}`, x: { child: c, parent: p },
    text: `Actor "${A.get(c)}" có làm được MỌI việc của "${A.get(p)}" và thêm việc riêng không?` }));
  (model.actors || []).slice(0, 15).forEach((a, i) => q.push({ id: `A${i + 1}`, kind: 'actor', ref: `actor:${a.id}`, x: a,
    text: `Actor "${a.name}" có phải người hoặc hệ thống BÊN NGOÀI tự dùng/tham gia hệ thống không (không phải chính hệ thống, cơ sở dữ liệu hay màn hình của nó)?` }));
  const nameItems = items.filter((i) => ['name-noun', 'name-short', 'name-case', 'actor-case'].includes(i.code));
  const orphans = items.filter((i) => i.code === 'uc-lonely').map((i) => i.refs[0].split(':')[1]);
  const needSubject = items.some((i) => i.code === 'subject-name' || i.code === 'no-subject');
  const nameOf = (r) => { const [k, id] = r.split(':'); return k === 'uc' ? U.get(id) : A.get(id); };
  const lines = [];
  lines.push('Bạn là người chấm sơ đồ use case UML. Trả lời các câu hỏi về sơ đồ dưới đây.');
  lines.push('Chỉ trả về MỘT object JSON đúng khuôn mẫu ở cuối, không giải thích ngoài JSON, không dùng tool, không đọc file.');
  lines.push('Chỉ báo SAI khi rõ ràng; không chắc thì trả lời theo hướng đúng (always/optional/ok/external = true).');
  lines.push(`"why" viết ${lang === 'en' ? 'tiếng Anh' : 'tiếng Việt'}, tối đa 15 từ. Tên và điều kiện viết bằng ngôn ngữ của sơ đồ.`, '', 'SƠ ĐỒ');
  lines.push(`Hệ thống: ${model.subject?.name ? `"${model.subject.name}"` : '(chưa ghi tên)'}`);
  lines.push(`Actor: ${(model.actors || []).map((a) => `${a.id} "${a.name}"`).join('; ') || '(không có)'}`);
  lines.push(`Use case: ${(model.usecases || []).map((u) => `${u.id} "${u.name}"`).join('; ') || '(không có)'}`);
  lines.push(`Actor nối use case: ${(model.associations || []).map((x) => `${x.actor}–${x.usecase}`).join(', ') || '(không có)'}`);
  lines.push(`«include» (gốc → phần luôn gồm): ${(model.includes || []).map((x) => `${x.base}→${x.part}`).join(', ') || '(không có)'}`);
  lines.push(`«extend» (phần mở rộng → gốc): ${(model.extends || []).map((x) => `${x.extending}→${x.base}${x.condition ? ` {${x.condition}}` : ''}`).join(', ') || '(không có)'}`);
  lines.push(`Kế thừa use case (con → cha): ${(model.generalizations || []).map((x) => `${x.child}→${x.parent}`).join(', ') || '(không có)'}`);
  lines.push(`Kế thừa actor (con → cha): ${Object.entries(model.actorParents || {}).map(([c, p]) => `${c}→${p}`).join(', ') || '(không có)'}`, '', 'CÂU HỎI');
  for (const x of q) lines.push(`${x.id}: ${x.text}`);
  lines.push('U: Use case nào là BƯỚC THAO TÁC trên màn hình (điền form, bấm nút, chọn mục, mở trang) chứ không phải mục tiêu của actor? Trả danh sách id, không có thì [].');
  lines.push('N: Tên use case/actor nào sai chính tả? Trả [{"id","to"}] với "to" là tên đúng, giữ ngôn ngữ và cách viết của sơ đồ. Không có thì [].');
  if (nameItems.length) lines.push(`R: Đặt lại tên dạng Động từ + Danh từ, giữ ngôn ngữ của sơ đồ, cho: ${nameItems.map((i) => `${i.refs[0].split(':')[1]} "${nameOf(i.refs[0])}"`).join('; ')}. Trả [{"id","to"}].`);
  if (orphans.length) lines.push(`O: Use case không nối với gì: ${orphans.map((id) => `${id} "${U.get(id)}"`).join('; ')}. Actor nào dùng nó (id), hoặc null nếu nên bỏ? Trả [{"id","actor"}].`);
  if (needSubject) lines.push('S: Sơ đồ chưa ghi tên hệ thống. Tên hệ thống nên là gì? Trả một chuỗi.');
  const tpl = {};
  for (const x of q) {
    if (x.kind === 'include') tpl[x.id] = { always: true, better: 'keep | extend | generalization | remove', condition: 'điều kiện nếu đổi thành extend, không thì ""', why: '' };
    if (x.kind === 'extend') tpl[x.id] = { optional: true, condition: '', base: 'id use case gốc đúng hoặc null', why: '' };
    if (x.kind === 'ucgen' || x.kind === 'actorgen') tpl[x.id] = { ok: true, why: '' };
    if (x.kind === 'actor') tpl[x.id] = { external: true, rename: 'tên đúng hoặc null', why: '' };
  }
  tpl.U = []; tpl.N = [];
  if (nameItems.length) tpl.R = [{ id: 'UCx', to: '' }];
  if (orphans.length) tpl.O = [{ id: 'UCx', actor: 'Ax hoặc null' }];
  if (needSubject) tpl.S = '';
  lines.push('', 'KHUÔN MẪU TRẢ LỜI', JSON.stringify(tpl, null, 1));
  return { prompt: lines.join('\n'), qs: q, nameIds: nameItems.map((i) => i.refs[0]), orphans, needSubject };
}

/** Lấy object JSON từ chữ model trả về (bỏ ```json, chữ thừa trước/sau). Đầu ra JSON của `cmd -p`/`claude -p` ({result}) cũng nhận. */
export function parseAnswerText(text) {
  let s = String(text || '').trim();
  for (const line of s.split('\n').reverse()) { try { const o = JSON.parse(line); if (o && typeof o === 'object' && typeof o.result === 'string') { if (o.subtype && o.subtype !== 'success') throw Object.assign(new Error(`model trả lỗi: ${o.subtype}`), { code: 2 }); s = o.result.trim(); break; } } catch (e) { if (e.code === 2) throw e; } }
  try { const o = JSON.parse(s); if (o && typeof o === 'object' && typeof o.result === 'string') s = o.result.trim(); else if (o && typeof o === 'object') return o; } catch { /* chữ thường */ }
  s = s.replace(/```(?:json)?/gi, '');
  const a = s.indexOf('{'), b = s.lastIndexOf('}');
  if (a < 0 || b <= a) throw Object.assign(new Error('câu trả lời không có object JSON'), { code: 2 });
  return JSON.parse(s.slice(a, b + 1));
}

/** Kiểm câu trả lời: id phải có trên sơ đồ, đúng kiểu, chữ không quá dài. Trả bản đã lọc + danh sách lỗi (để hỏi lại). */
export function validateAnswers(ans, Q, model) {
  const errs = [], out = {};
  const ucIds = new Set((model.usecases || []).map((u) => u.id)), acIds = new Set((model.actors || []).map((a) => a.id));
  const str = (v, n) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim().slice(0, n) : '');
  const bool = (v) => (typeof v === 'boolean' ? v : v === 'true' ? true : v === 'false' ? false : null);
  const nul = (v) => v === null || v === undefined || v === '' || /^(null|none|không)$/i.test(String(v));
  for (const x of Q.qs) {
    const a = ans?.[x.id];
    if (a === undefined) continue;
    if (!a || typeof a !== 'object') { errs.push(`${x.id}: phải là object`); continue; }
    if (x.kind === 'include') {
      const always = bool(a.always), better = String(a.better || 'keep').toLowerCase();
      if (always === null) { errs.push(`${x.id}.always phải là true/false`); continue; }
      if (!['keep', 'extend', 'generalization', 'remove'].includes(better)) { errs.push(`${x.id}.better phải là keep|extend|generalization|remove`); continue; }
      out[x.id] = { always, better, condition: better === 'extend' && !/^điều kiện nếu/i.test(String(a.condition || '')) ? str(a.condition, 90) : '', why: str(a.why, 140) };
    } else if (x.kind === 'extend') {
      const optional = bool(a.optional);
      if (optional === null) { errs.push(`${x.id}.optional phải là true/false`); continue; }
      const base = nul(a.base) ? null : String(a.base).trim();
      if (base && !ucIds.has(base)) { errs.push(`${x.id}.base "${base}" không có trên sơ đồ`); continue; }
      out[x.id] = { optional, condition: str(a.condition, 90), base: base && base !== x.x.base && base !== x.x.extending ? base : null, why: str(a.why, 140) };
    } else if (x.kind === 'ucgen' || x.kind === 'actorgen') {
      const ok = bool(a.ok); if (ok === null) { errs.push(`${x.id}.ok phải là true/false`); continue; }
      out[x.id] = { ok, why: str(a.why, 140) };
    } else if (x.kind === 'actor') {
      const external = bool(a.external); if (external === null) { errs.push(`${x.id}.external phải là true/false`); continue; }
      out[x.id] = { external, rename: nul(a.rename) ? null : str(a.rename, 60), why: str(a.why, 140) };
    }
  }
  const list = (v, k) => (Array.isArray(v) ? v : v === undefined ? [] : (errs.push(`${k} phải là mảng`), []));
  out.U = list(ans?.U, 'U').map(String).filter((id) => { if (ucIds.has(id)) return true; errs.push(`U: "${id}" không có trên sơ đồ`); return false; });
  for (const k of ['N', 'R']) out[k] = list(ans?.[k], k).filter((r) => { const id = String(r?.id || ''); const to = str(r?.to, 80); if ((ucIds.has(id) || acIds.has(id)) && to) return true; errs.push(`${k}: id "${id}" không có trên sơ đồ hoặc thiếu "to"`); return false; }).map((r) => ({ id: String(r.id), to: str(r.to, 80) }));
  out.O = list(ans?.O, 'O').filter((r) => { const id = String(r?.id || ''); const a = nul(r?.actor) ? null : String(r.actor); if (Q.orphans.includes(id) && (a === null || acIds.has(a))) return true; errs.push(`O: "${id}"/"${r?.actor}" không hợp lệ`); return false; }).map((r) => ({ id: String(r.id), actor: nul(r.actor) ? null : String(r.actor) }));
  out.S = Q.needSubject ? str(ans?.S, 80) : '';
  return { answers: out, errors: errs };
}

const QT = {
  vi: {
    incNot: (b, p, why) => `"${b}" «include» "${p}": không phải lần nào "${b}" cũng cần "${p}"${why ? ` — ${why}` : ''}.`,
    incKind: (b, p, why) => `"${b}" «include» "${p}": nên đổi loại quan hệ${why ? ` — ${why}` : ''}.`,
    incExtend: (b, p) => `Đổi thành «extend»: mũi tên từ "${p}" về "${b}", kèm điều kiện.`,
    incGen: (b, p) => `Dùng kế thừa (tam giác rỗng) từ "${b}" về "${p}".`,
    incRemove: () => 'Bỏ quan hệ này.',
    incLook: () => 'Xem lại loại quan hệ này.',
    extWrongBase: (e, b, nb, why) => `"${e}" đang mở rộng "${b}", nhưng thuộc về "${nb}"${why ? ` — ${why}` : ''}.`,
    extWrongBaseFix: (e, nb) => `Nối «extend» từ "${e}" về "${nb}".`,
    extNotOpt: (e, b, why) => `"${e}" «extend» "${b}": phần này xảy ra mọi lần chứ không tuỳ chọn${why ? ` — ${why}` : ''}.`,
    extNotOptFix: (e, b) => `Đổi thành «include»: mũi tên từ "${b}" tới "${e}".`,
    genNot: (c, p, why) => `"${c}" không phải một kiểu "${p}"${why ? ` — ${why}` : ''}.`,
    genNotFix: () => 'Bỏ kế thừa này; nếu hai việc liên quan thì dùng «include»/«extend».',
    agNot: (c, p, why) => `Actor "${c}" không làm được mọi việc của "${p}"${why ? ` — ${why}` : ''}.`,
    agNotFix: () => 'Bỏ kế thừa actor này, nối thẳng các use case chung.',
    actorNot: (a, why) => `"${a}" có vẻ không phải người hay hệ thống bên ngoài dùng hệ thống${why ? ` — ${why}` : ''}.`,
    actorRename: (to) => `Đổi actor thành "${to}".`,
    actorRemove: () => 'Bỏ actor này.',
    uiStep: (names) => `${names} là bước thao tác trên màn hình, không phải mục tiêu của actor.`,
    uiStepFix: () => 'Bỏ; ghi bước đó trong đặc tả của use case chính.',
    typo: (old) => `Tên "${old}" sai chính tả.`,
    typoFix: (to) => `Sửa thành "${to}".`,
  },
  en: {
    incNot: (b, p, why) => `"${b}" «include» "${p}": "${b}" does not always need "${p}"${why ? ` — ${why}` : ''}.`,
    incKind: (b, p, why) => `"${b}" «include» "${p}": this should be a different relationship${why ? ` — ${why}` : ''}.`,
    incExtend: (b, p) => `Make it «extend»: arrow from "${p}" to "${b}", with a condition.`,
    incGen: (b, p) => `Use generalization (hollow triangle) from "${b}" to "${p}".`,
    incRemove: () => 'Remove this relationship.',
    incLook: () => 'Check what kind of relationship this is.',
    extWrongBase: (e, b, nb, why) => `"${e}" extends "${b}", but it belongs to "${nb}"${why ? ` — ${why}` : ''}.`,
    extWrongBaseFix: (e, nb) => `Connect «extend» from "${e}" to "${nb}".`,
    extNotOpt: (e, b, why) => `"${e}" «extend» "${b}": this happens every time, it is not optional${why ? ` — ${why}` : ''}.`,
    extNotOptFix: (e, b) => `Make it «include»: arrow from "${b}" to "${e}".`,
    genNot: (c, p, why) => `"${c}" is not a kind of "${p}"${why ? ` — ${why}` : ''}.`,
    genNotFix: () => 'Remove this generalization; use «include»/«extend» if they are related.',
    agNot: (c, p, why) => `Actor "${c}" cannot do everything "${p}" does${why ? ` — ${why}` : ''}.`,
    agNotFix: () => 'Remove this actor generalization and connect the shared use cases directly.',
    actorNot: (a, why) => `"${a}" does not look like an outside person or system using the system${why ? ` — ${why}` : ''}.`,
    actorRename: (to) => `Rename the actor to "${to}".`,
    actorRemove: () => 'Remove this actor.',
    uiStep: (names) => `${names} are screen steps, not goals of an actor.`,
    uiStepFix: () => 'Remove them; describe the step in the main use case specification.',
    typo: (old) => `"${old}" is misspelled.`,
    typoFix: (to) => `Correct it to "${to}".`,
  },
};

/** Câu trả lời đã kiểm → ai.json (findings lời mẫu + suggest + actions) cho collectFindings/fixModel. */
export function answersToAi(model, Q, ans, lang = 'vi') {
  const L = QT[lang] || QT.vi;
  const U = new Map((model.usecases || []).map((u) => [u.id, u.name])), A = new Map((model.actors || []).map((a) => [a.id, a.name]));
  const findings = [], suggest = {}, actions = [];
  const dot = (s) => String(s || '').replace(/[.。]+$/, '');
  for (const x of Q.qs) {
    const a = ans[x.id];
    if (!a) continue;
    if (x.kind === 'include' && (!a.always || a.better !== 'keep')) {
      const b = U.get(x.x.base), p = U.get(x.x.part);
      // "luôn luôn" nhưng vẫn đề xuất loại khác (vd Thêm/Sửa/Xoá «include» Cập nhật → kế thừa): lời nói "nên đổi loại", không nói "không luôn cần"
      const f = { refs: [x.ref], what: a.always ? L.incKind(b, p, dot(a.why)) : L.incNot(b, p, dot(a.why)),
        fix: a.better === 'extend' ? L.incExtend(b, p) : a.better === 'generalization' ? L.incGen(b, p) : a.better === 'remove' ? L.incRemove() : L.incLook() };
      if (a.better === 'extend' || a.better === 'generalization') f.action = { type: 'retype', ref: x.ref, to: a.better };
      if (a.better === 'extend' && a.condition) suggest[`extend:${x.x.part}>${x.x.base}`] = { condition: a.condition };
      if (a.better === 'remove') f.action = { type: 'remove', ref: x.ref };
      findings.push(f);
    }
    if (x.kind === 'extend') {
      const e = U.get(x.x.extending), b = U.get(x.x.base);
      if (a.base) {
        findings.push({ refs: [x.ref], replaces: 'extend-cond', what: L.extWrongBase(e, b, U.get(a.base), dot(a.why)), fix: L.extWrongBaseFix(e, U.get(a.base)) });
        actions.push({ type: 'remove', ref: x.ref }, { type: 'add', for: x.ref, rel: 'extend', extending: x.x.extending, base: a.base });
        if (a.condition) suggest[`extend:${x.x.extending}>${a.base}`] = { condition: a.condition };
      } else if (!a.optional) {
        findings.push({ refs: [x.ref], replaces: 'extend-cond', what: L.extNotOpt(e, b, dot(a.why)), fix: L.extNotOptFix(e, b), action: { type: 'retype', ref: x.ref, to: 'include' } });
      } else if (a.condition) suggest[x.ref] = { condition: a.condition };
    }
    if (x.kind === 'ucgen' && !a.ok) findings.push({ refs: [x.ref], what: L.genNot(U.get(x.x.child), U.get(x.x.parent), dot(a.why)), fix: L.genNotFix(), action: { type: 'remove', ref: x.ref } });
    if (x.kind === 'actorgen' && !a.ok) findings.push({ refs: [x.ref], what: L.agNot(A.get(x.x.child), A.get(x.x.parent), dot(a.why)), fix: L.agNotFix(), action: { type: 'remove', ref: x.ref } });
    if (x.kind === 'actor' && !a.external) {
      findings.push({ refs: [x.ref], replaces: ['actor-store', 'actor-system'], what: L.actorNot(x.x.name, dot(a.why)), fix: a.rename ? L.actorRename(a.rename) : L.actorRemove(),
        action: a.rename ? { type: 'rename', ref: x.ref, to: a.rename } : { type: 'remove', ref: x.ref } });
    }
  }
  if (ans.U?.length) {
    findings.push({ refs: ans.U.map((id) => `uc:${id}`), what: L.uiStep(ans.U.map((id) => `"${U.get(id)}"`).join(', ')), fix: L.uiStepFix() });
    for (const id of ans.U) actions.push({ type: 'remove', ref: `uc:${id}` });
  }
  for (const r of ans.N || []) {
    const ref = U.has(r.id) ? `uc:${r.id}` : `actor:${r.id}`, old = U.get(r.id) ?? A.get(r.id);
    if (!old || old === r.to) continue;
    findings.push({ refs: [ref], what: L.typo(old), fix: L.typoFix(r.to) });
    suggest[ref] = { rename: r.to };
  }
  for (const r of ans.R || []) { const ref = U.has(r.id) ? `uc:${r.id}` : `actor:${r.id}`; if (!suggest[ref]) suggest[ref] = { rename: r.to }; }
  for (const r of ans.O || []) actions.push(r.actor ? { type: 'connect', for: `uc:${r.id}`, actor: r.actor, usecase: r.id } : { type: 'remove', ref: `uc:${r.id}` });
  if (ans.S) suggest.subject = { name: ans.S };
  return { findings, suggest, actions, _from: 'answers' };
}

/**
 * Lệnh hỏi model. `cmd` trần (Command Code) → tự tìm id bằng `cmd --list-models`: khớp UC_REVIEW_MODEL (mặc định DeepSeek V4.1 Flash),
 * rồi thành `cmd -p --output-format json -m <id>`. Lệnh còn chỗ trống kiểu <…> thì báo rõ thay vì để shell báo lỗi cú pháp.
 */
export async function resolveAskCmd(askCmd) {
  const c = String(askCmd || '').trim();
  if (!c) return null;
  if (/<[^>]*>/.test(c)) throw Object.assign(new Error(`lệnh hỏi model còn chỗ trống "${c.match(/<[^>]*>/)[0]}" — thay bằng id thật, hoặc đặt UC_REVIEW_ASK=cmd để tự tìm id`), { code: 2 });
  if (c !== 'cmd') return c;
  const { spawnSync } = await import('node:child_process');
  const r = spawnSync('cmd', ['--list-models'], { encoding: 'utf8', timeout: 90000, maxBuffer: 20 * 1024 * 1024 });
  if (r.error || r.status !== 0) throw Object.assign(new Error(`không chạy được "cmd --list-models": ${r.error?.message || String(r.stderr || r.stdout).trim().split('\n').slice(-2).join(' | ')}`), { code: 2 });
  const want = new RegExp(process.env.UC_REVIEW_MODEL || 'deepseek[\\w./:-]*v4\\.1[\\w./:-]*flash', 'i');
  const tokens = uniq([...String(r.stdout).matchAll(/[\w./:@-]+/g)].map((m) => m[0]));
  const ids = tokens.filter((t) => want.test(t));
  if (!ids.length) {
    const ds = tokens.filter((t) => /deepseek/i.test(t)).slice(0, 12);
    throw Object.assign(new Error(`"cmd --list-models" không có model khớp /${want.source}/${ds.length ? ` — id DeepSeek đang có: ${ds.join(', ')} (đặt UC_REVIEW_MODEL hoặc UC_REVIEW_ASK="cmd -p --output-format json -m <id>")` : ''}`), { code: 2 });
  }
  return `cmd -p --output-format json -m ${ids[0]}`;
}

/** Gọi model qua một lệnh CLI nhận prompt ở stdin (vd `cmd -p --output-format json -m <id>`); kiểm, hỏi lại một lần kèm lỗi. */
export async function askModel(cmdline, Q, model, opts = {}) {
  const { spawnSync } = await import('node:child_process');
  const run = (prompt) => {
    const r = spawnSync(cmdline, { shell: true, input: prompt, encoding: 'utf8', timeout: (opts.timeout || 240) * 1000, maxBuffer: 20 * 1024 * 1024 });
    if (r.error) throw Object.assign(new Error(`không chạy được "${cmdline}": ${r.error.message}`), { code: 2 });
    if (r.status !== 0) throw Object.assign(new Error(`"${cmdline}" thoát ${r.status}: ${String(r.stderr || r.stdout).trim().split('\n').slice(-3).join(' | ')}`), { code: 2 });
    return r.stdout;
  };
  const log = [];
  let raw = run(Q.prompt), parsed;
  try { parsed = parseAnswerText(raw); } catch (e) { parsed = null; log.push(`lần 1: ${e.message}`); }
  let v = parsed ? validateAnswers(parsed, Q, model) : { answers: {}, errors: ['không đọc được JSON'] };
  if (v.errors.length) {
    log.push(`lần 1: ${v.errors.length} lỗi — hỏi lại`);
    raw = run(`${Q.prompt}\n\nLẦN TRƯỚC JSON CỦA BẠN SAI Ở CÁC CHỖ SAU. SỬA VÀ TRẢ LẠI TOÀN BỘ JSON:\n- ${v.errors.join('\n- ')}`);
    try {
      const v2 = validateAnswers(parseAnswerText(raw), Q, model);
      if (v2.errors.length <= v.errors.length) v = v2;
      if (v2.errors.length) log.push(`lần 2: còn ${v2.errors.length} lỗi — bỏ các ý sai, giữ ý hợp lệ`);
    } catch (e) { log.push(`lần 2: ${e.message} — dùng ý hợp lệ của lần 1`); }
  }
  return { answers: v.answers, errors: v.errors, log };
}

// ================================================================ "Sửa tại chỗ": áp khác biệt (model gốc → model đã sửa) vào CHÍNH file .drawio của khách
// Giữ bố cục, màu, chữ, các trang khác của khách; chỉ đụng phần sai. Việc phải dời hình (đường xuyên use case, hình chồng nhau,
// use case nằm ngoài khung) không tự làm — để ở "chưa sửa".
export const INPLACE_SKIP = new Set(['crossing', 'overlap', 'uc-outside']);
const styleStr = (st) => [...st._base, ...Object.entries(st).filter(([k]) => k !== '_base').map(([k, v]) => `${k}=${v}`)].join(';') + ';';
const REL_STYLE = { assoc: 'endArrow=none;html=1;', include: 'endArrow=open;endSize=12;dashed=1;html=1;', extend: 'endArrow=open;endSize=12;dashed=1;html=1;', ucgen: 'endArrow=block;endSize=14;endFill=0;html=1;', actorgen: 'endArrow=block;endSize=14;endFill=0;html=1;' };
export function applyInPlace(parsed, fixed, items, lang = 'vi') {
  const L = T[lang] || T.vi;
  const gm = JSON.parse(JSON.stringify(parsed.page.model));
  const root = gm.children.find((c) => c.tag === 'root');
  const layer = root.children.find((c) => c.tag === 'mxCell' && c.attrs.parent === '0')?.attrs.id || '1';
  const orig = parsed.model, fm = fixed.model, cellOf = orig._cells, geom = orig._geom;
  const extra = [];
  const cellNode = (n) => (n.tag === 'mxCell' ? n : (n.children || []).find((c) => c.tag === 'mxCell'));
  const find = (id) => { if (!id) return null; for (const n of root.children) if (n.attrs?.id === id && (n.tag === 'mxCell' || n.tag === 'UserObject' || n.tag === 'object')) return { holder: n, cell: cellNode(n) }; return null; };
  const removeCell = (id) => {
    if (!find(id)) return false;
    const kill = new Set([id]);
    for (let grew = true; grew;) { grew = false; for (const n of root.children) { const c = cellNode(n); if (!c || kill.has(n.attrs?.id)) continue; if (kill.has(c.attrs.source) || kill.has(c.attrs.target) || kill.has(c.attrs.parent)) { kill.add(n.attrs.id); grew = true; } } }
    root.children = root.children.filter((n) => !kill.has(n.attrs?.id));
    return true;
  };
  const setStyle = (id, kv) => { const f = find(id); if (!f) return; const st = parseStyle(f.cell.attrs.style); Object.assign(st, kv); f.cell.attrs.style = styleStr(st); };
  const setLabel = (id, o, name) => {
    const f = find(id); if (!f) return;
    const isWrap = f.holder !== f.cell, raw = (isWrap ? f.holder.attrs.label : f.cell.attrs.value) ?? '';
    const html = /(^|;)html=1(;|$)/.test(f.cell.attrs.style || '');
    const safe = html ? escText(name) : name;
    const next = o.name && raw.includes(o.name) ? raw.replace(o.name, safe) : `${o.prefix || ''}${safe}`;
    if (isWrap) f.holder.attrs.label = next; else f.cell.attrs.value = next;
  };
  let k = 0; const nid = () => `vdfix_${++k}`;
  const geo = (x, y, w, h) => ({ tag: 'mxGeometry', attrs: { x: String(Math.round(x)), y: String(Math.round(y)), width: String(Math.round(w)), height: String(Math.round(h)), as: 'geometry' }, children: [], text: '' });
  const addEdge = (s, t, kind, label = '') => { if (!s || !t || !find(s) || !find(t)) return null; const id = nid(); root.children.push({ tag: 'mxCell', attrs: { id, value: label, style: REL_STYLE[kind], edge: '1', parent: layer, source: s, target: t }, text: '', children: [{ tag: 'mxGeometry', attrs: { relative: '1', as: 'geometry' }, children: [], text: '' }] }); return id; };
  const ucC = (id) => cellOf[`uc:${id}`], acC = (id) => cellOf[`actor:${id}`];
  const boxOf = (id) => geom[`uc:${id}`]?.box || geom[`actor:${id}`]?.box;
  // chỗ đã có hình (trừ khung hệ thống): note mới không được đè lên
  const taken = parsed.cells.filter((c) => c.box && c.vertex && c !== parsed.frame && !parsed.byId.get(c.parent)?.edge).map((c) => ({ ...c.box, h: c.box.h + (isActorC(c) ? 22 : 0) }));
  const hits = (r) => taken.some((b) => r.x < b.x + b.w + 8 && r.x + r.w + 8 > b.x && r.y < b.y + b.h + 8 && r.y + r.h + 8 > b.y);
  const addNote = (x, text) => {
    const A = boxOf(x.extending), B = boxOf(x.base); if (!A || !B) return;
    const mid = [(A.x + A.w / 2 + B.x + B.w / 2) / 2, (A.y + A.h / 2 + B.y + B.h / 2) / 2];
    // note hẹp, chữ dài thì xuống dòng (≈ 6px/ký tự ở cỡ 10)
    const label = `Condition: {${text}}`, w = Math.max(110, Math.min(180, label.length * 6 + 20)), perLine = Math.floor((w - 20) / 6);
    const h = Math.ceil(label.length / perLine) * 13 + 14, id = nid();
    // dò lưới 10px quanh điểm giữa đường extend, gần trước xa sau: không đè hình nào, không che điểm giữa;
    // ưu tiên nằm trọn trong khung hệ thống (note là của use case), hết chỗ mới cho ra ngoài
    const F = parsed.frame?.box, inside = (r) => !F || (r.x >= F.x + 10 && r.y >= F.y + 30 && r.x + r.w <= F.x + F.w - 10 && r.y + r.h <= F.y + F.h - 10);
    const cands = [];
    for (let dx = -340; dx <= 340; dx += 10) for (let dy = -260; dy <= 260; dy += 10) cands.push([mid[0] + dx - w / 2, mid[1] + dy - h / 2, Math.hypot(dx, dy)]);
    cands.sort((p, q) => p[2] - q[2]);
    // dây nối (tâm note → điểm giữa) không được cắt use case/actor nào; không đường nối nào của khách đi xuyên note
    const segBox = (p, q, b, pad = 2) => { const n = Math.max(2, Math.ceil(Math.hypot(q[0] - p[0], q[1] - p[1]) / 4)); for (let i = 1; i < n; i++) { const t = i / n; if (inBox([p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t], b, pad)) return true; } return false; };
    const lines = [...parsed.allLines.values()].filter(Boolean);
    const linkClear = (r) => { const c = [r.x + r.w / 2, r.y + r.h / 2]; return !taken.some((b) => segBox(c, mid, b, -2)); };
    const noEdgeThrough = (r) => !lines.some((l) => l.some((p, i) => i > 0 && segBox(l[i - 1], p, r, 2)));
    let pos = null;
    for (const pass of [['inside', 'link', 'edges'], ['inside', 'link'], ['inside'], []]) {
      for (const [px, py] of cands) {
        const r = { x: px, y: py, w, h };
        if (inBox(mid, r, 14) || hits(r)) continue;
        if (pass.includes('inside') && !inside(r)) continue;
        if (pass.includes('link') && !linkClear(r)) continue;
        if (pass.includes('edges') && !noEdgeThrough(r)) continue;
        pos = [px, py]; break;
      }
      if (pos) break;
    }
    pos = pos || [mid[0] + 24, mid[1] - h - 26];
    taken.push({ x: pos[0], y: pos[1], w, h });
    root.children.push({ tag: 'mxCell', attrs: { id, value: `<b>Condition:</b> {${escText(text)}}`, style: 'shape=note;whiteSpace=wrap;html=1;size=10;align=left;spacingLeft=6;fontSize=10;', vertex: '1', parent: layer }, text: '', children: [geo(pos[0], pos[1], w, h)] });
    root.children.push({ tag: 'mxCell', attrs: { id: nid(), value: '', style: 'endArrow=none;dashed=1;html=1;', edge: '1', parent: layer, source: id }, text: '',
      children: [{ tag: 'mxGeometry', attrs: { relative: '1', as: 'geometry' }, text: '', children: [{ tag: 'mxPoint', attrs: { x: String(Math.round(mid[0])), y: String(Math.round(mid[1])), as: 'targetPoint' }, children: [], text: '' }] }] });
  };
  // 1) phần tử bị bỏ (kéo theo mọi đường nối vào nó)
  for (const u of orig.usecases || []) if (!fm.usecases.some((x) => x.id === u.id)) removeCell(ucC(u.id));
  for (const a of orig.actors || []) if (!fm.actors.some((x) => x.id === a.id)) removeCell(acC(a.id));
  // 2) đổi tên (giữ mã "UC01 -" và định dạng của khách)
  for (const u of fm.usecases) { const o = (orig.usecases || []).find((x) => x.id === u.id); if (o && o.name !== u.name) setLabel(ucC(u.id), o, u.name); }
  for (const a of fm.actors) { const o = (orig.actors || []).find((x) => x.id === a.id); if (o && o.name !== a.name) setLabel(acC(a.id), o, a.name); }
  // 3) quan hệ: bỏ cái không còn, thêm cái mới; đường còn giữ mà sai ký hiệu thì thay bằng đường đúng kiểu (cùng hai đầu)
  const restyle = new Set(items.filter((i) => ['rel-style-solid', 'rel-no-arrow', 'uses', 'gen-filled', 'rel-on-actor'].includes(i.code)).flatMap((i) => i.refs));
  const plainAssoc = new Set(items.filter((i) => i.code === 'assoc-arrow').flatMap((i) => i.refs));
  const kinds = [
    ['assoc', (m) => m.associations || [], (x) => `assoc:${x.actor}>${x.usecase}`, (x) => [acC(x.actor), ucC(x.usecase)], ''],
    ['include', (m) => m.includes || [], (x) => `include:${x.base}>${x.part}`, (x) => [ucC(x.base), ucC(x.part)], '«include»'],
    ['extend', (m) => m.extends || [], (x) => `extend:${x.extending}>${x.base}`, (x) => [ucC(x.extending), ucC(x.base)], '«extend»'],
    ['ucgen', (m) => m.generalizations || [], (x) => `ucgen:${x.child}>${x.parent}`, (x) => [ucC(x.child), ucC(x.parent)], ''],
    ['actorgen', (m) => Object.entries(m.actorParents || {}).map(([child, parent]) => ({ child, parent })), (x) => `actorgen:${x.child}>${x.parent}`, (x) => [acC(x.child), acC(x.parent)], ''],
  ];
  for (const [kind, get, keyOf, ends, label] of kinds) {
    const before = new Map(get(orig).map((x) => [keyOf(x), x])), after = new Map(get(fm).map((x) => [keyOf(x), x]));
    for (const [r] of before) if (!after.has(r) || restyle.has(r)) removeCell(cellOf[r]);
    for (const [r, x] of after) {
      if (before.has(r) && !restyle.has(r)) { if (plainAssoc.has(r)) setStyle(cellOf[r], { endArrow: 'none', startArrow: 'none' }); continue; }
      const [s, t] = ends(x);
      addEdge(s, t, kind, label);
    }
  }
  // 4) điều kiện «extend» mới hoặc đổi → note gắn vào đường (UML 2.5)
  for (const x of fm.extends || []) { const o = (orig.extends || []).find((y) => y.extending === x.extending && y.base === x.base); if (x.condition && (!o || o.condition !== x.condition)) addNote(x, x.condition); }
  // 5) actor nằm trong khung → đưa ra ngoài, về phía gần nhất
  const frame = parsed.frame;
  for (const it of items.filter((i) => i.code === 'actor-inside')) {
    const aid = it.refs[0].split(':')[1], f = find(acC(aid)), b = geom[`actor:${aid}`]?.box;
    if (!f || !b || !frame || !fm.actors.some((a) => a.id === aid)) continue;
    const left = b.x + b.w / 2 < frame.box.x + frame.box.w / 2, g = f.cell.children.find((c) => c.tag === 'mxGeometry');
    g.attrs.x = String(Math.round(left ? frame.box.x - b.w - 70 : frame.box.x + frame.box.w + 70)); g.attrs.y = String(Math.round(b.y));
    f.cell.attrs.parent = layer;
  }
  // 6) tên hệ thống; chưa có khung thì vẽ khung bao các use case (nằm dưới cùng)
  const sname = fm.subject?.name;
  if (frame && sname && sname !== orig.subject?.name) { const f = find(frame.id); if (f) { if (f.holder !== f.cell) f.holder.attrs.label = sname; else f.cell.attrs.value = sname; } }
  if (!frame && sname && items.some((i) => i.code === 'no-subject')) {
    const bs = (orig.usecases || []).map((u) => geom[`uc:${u.id}`]?.box).filter(Boolean);
    if (bs.length) {
      const x0 = Math.min(...bs.map((b) => b.x)) - 40, y0 = Math.min(...bs.map((b) => b.y)) - 60, x1 = Math.max(...bs.map((b) => b.x + b.w)) + 40, y1 = Math.max(...bs.map((b) => b.y + b.h)) + 30;
      const at = root.children.findIndex((n) => n.tag === 'mxCell' && n.attrs.id === layer) + 1;
      root.children.splice(at, 0, { tag: 'mxCell', attrs: { id: nid(), value: sname, style: 'rounded=0;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fillColor=none;', vertex: '1', parent: layer }, text: '', children: [geo(x0, y0, x1 - x0, y1 - y0)] });
    }
  }
  // 7) đường lơ lửng → bỏ
  for (const it of items.filter((i) => i.code === 'dangling')) for (const r of it.refs) if (removeCell(cellOf[r])) extra.push({ num: it.num, text: L.removedDangling, sure: true });
  for (const it of items.filter((i) => i.code === 'self-loop')) for (const r of it.refs) if (removeCell(cellOf[r])) extra.push({ num: it.num, text: L.removedLoop, sure: true });
  // ghép lại vào file gốc: trang được sửa thay bằng bản không nén, các trang khác giữ nguyên
  const doc = parseXml(parsed.source || '');
  const mxfile = findTag(doc, 'mxfile');
  let xml;
  if (mxfile) {
    const d = mxfile.children.filter((c) => c.tag === 'diagram')[parsed.page.index ?? 0];
    if (d) { d.text = ''; d.children = [gm]; }
    xml = serializeXml(doc);
  } else xml = `<mxfile host="kickoff-uml uc-review"><diagram id="fixed" name="${escAttr(parsed.page.name)}">${serializeXml(gm)}</diagram></mxfile>`;
  return { xml: `${xml}\n`, extra };
}

// ================================================================ báo cáo chữ cho khách
export function reviewMd(model, items, meta, lang = 'vi') {
  const L = T[lang] || T.vi;
  const e = items.filter((i) => i.sev === 'error'), r = items.filter((i) => i.sev === 'review');
  const hand = meta.read ? L.handDrawn(meta.read) : '';
  const out = [`# ${L.title(model.subject?.name)}`, '', L.read(meta.kind, meta.stats), ...(hand ? [hand] : []), L.result(e.length, r.length), ''];
  const sec = (title, list) => { if (!list.length) return; out.push(`## ${title}`, ''); for (const it of list) out.push(`${circled(it.num)} **${it.what}** ${it.fix}`, ''); };
  sec(L.sev.error, e); sec(L.sev.review, r);
  const unc = (model._uncertain || []).length ? model._uncertain : null;
  if (unc && meta.kind === 'image') { out.push(`## ${L.uncertain}`, ''); for (const u of unc) out.push(`- ${relName(model)(u).join(' – ') || u}`); out.push(''); }
  return out.join('\n');
}
export function fixedMd(model, fixed, items, lang = 'vi', opts = {}) {
  const L = T[lang] || T.vi;
  const out = [`# ${L.fixedTitle(fixed.model.subject?.name || model.subject?.name)}`, ''];
  if (!fixed.changes.length && !fixed.pending.length) out.push(L.fixedNone, '');
  if (fixed.changes.length) {
    out.push(L.fixedDone(fixed.changes.length), '');
    // một dòng cho mỗi số (nhiều thay đổi cùng mục nối bằng "; "); thay đổi không số (gợi ý thêm) mỗi cái một dòng
    const group = (list) => { const out2 = [], at = new Map(); for (const c of list) { if (c.num && at.has(c.num)) { out2[at.get(c.num)].text += ` ${c.text}`; continue; } if (c.num) at.set(c.num, out2.length); out2.push({ ...c }); } return out2; };
    const line = (c) => `- ${c.num ? `${circled(c.num)} ` : ''}${c.text}`;
    const sure = group(fixed.changes.filter((c) => c.sure)), prop = group(fixed.changes.filter((c) => !c.sure));
    if (sure.length) out.push(`**${L.fixedSure}**`, '', ...sure.map(line), '');
    if (prop.length) out.push(`**${L.fixedProposed}**`, '', ...prop.map(line), '');
  }
  if (fixed.pending.length) { out.push(`**${L.pending}**`, ''); for (const it of fixed.pending) out.push(`- ${circled(it.num)} ${it.what} ${it.fix}`); out.push(''); }
  if (opts.inplace && fixed.pending.some((it) => INPLACE_SKIP.has(it.code))) out.push(`_${L.moveByHand}_`, '');
  // lỗi còn lại mà đã nằm trong "cần bạn quyết" thì không nhắc lần hai
  const asked = new Set(fixed.pending.map((it) => it.what));
  const left = (opts.left || collectFindings(fixed.model, [], null, { lang }).filter((i) => i.sev === 'error')).filter((it) => !asked.has(it.what));
  if (left.length) { out.push(`**${L.left}**`, ''); for (const it of left) out.push(`- ${it.what} ${it.fix}`); out.push(''); }
  return out.join('\n');
}

// ================================================================ lệnh
function parseArgs(argv) {
  const out = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) { const k = a.slice(2), v = argv[i + 1]; if (v !== undefined && !v.startsWith('--')) { out.flags[k] = v; i++; } else out.flags[k] = true; }
    else out._.push(a);
  }
  return out;
}
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
/** Bản chép (nhất là từ ảnh) chỉ có hộp phần tử: quan hệ nào chưa có đường thì nối tâm–tâm, cắt ở mép hộp, để đặt số và tô màu. */
export function fillLines(model) {
  const g = (model._geom = model._geom || {});
  const boxOf = (id) => g[`uc:${id}`]?.box || g[`actor:${id}`]?.box;
  const clip = (b, p) => { const [cx, cy] = center(b), dx = p[0] - cx, dy = p[1] - cy; if (!dx && !dy) return [cx, cy]; const t = Math.min(1, 1 / Math.sqrt((dx / (b.w / 2)) ** 2 + (dy / (b.h / 2)) ** 2)); return [cx + dx * t, cy + dy * t]; };
  const link = (r, a, b) => { if (g[r]?.line) return; const A = boxOf(a), B = boxOf(b); if (!A || !B) return; g[r] = { ...(g[r] || {}), line: [clip(A, center(B)), clip(B, center(A))], synth: true }; };
  for (const x of model.associations || []) link(`assoc:${x.actor}>${x.usecase}`, x.actor, x.usecase);
  for (const x of model.includes || []) link(`include:${x.base}>${x.part}`, x.base, x.part);
  for (const x of model.extends || []) link(`extend:${x.extending}>${x.base}`, x.extending, x.base);
  for (const x of model.generalizations || []) link(`ucgen:${x.child}>${x.parent}`, x.child, x.parent);
  for (const [c, p] of Object.entries(model.actorParents || {})) link(`actorgen:${c}>${p}`, c, p);
  return model;
}

/** Đọc đầu vào (.drawio → bản chép; .json → bản chép có sẵn, vd từ ảnh). */
function loadInput(input, flags) {
  const isDrawio = /\.(drawio|xml)$/i.test(input);
  if (isDrawio) { const parsed = parseUseCaseDrawio(fs.readFileSync(input, 'utf8'), { page: flags.page }); return { isDrawio, parsed, model: parsed.model, notation: parsed.notation }; }
  const model = readJson(input);
  return { isDrawio, parsed: null, model, notation: model._notation || [] };
}

/**
 * Đề không đòi điều kiện «extend» (`--extend-details none`): bỏ điều kiện/extension point mà bước AI đề xuất (suggest, actions, findings[].action)
 * để sửa tại chỗ/vẽ lại không thêm ghi chú điều kiện vào hình của khách. Điều kiện khách đã vẽ thì giữ.
 * @param {object|null} ai ai.json
 * @returns {object|null}
 */
export function withoutConditions(ai) {
  if (!ai) return ai;
  const strip = (o) => { if (!o || typeof o !== 'object') return o; const { condition, point, ...rest } = o; return rest; };
  const act = (a) => (!a ? a : a.type === 'condition' ? null : strip(a));
  const suggest = Object.fromEntries(Object.entries(ai.suggest || {}).map(([k, v]) => [k, strip(v)]).filter(([, v]) => v && Object.keys(v).length));
  return { ...ai, suggest, ...(ai.actions ? { actions: ai.actions.map(act).filter(Boolean) } : {}), ...(ai.findings ? { findings: ai.findings.map((f) => (f.action ? { ...f, action: act(f.action) } : f)) } : {}) };
}

export async function review(input, flags = {}) {
  const xd = flags['extend-details'] === undefined ? null : String(flags['extend-details']).trim().toLowerCase();
  if (xd !== null && !EXTEND_DETAILS.includes(xd)) throw Object.assign(new Error(`--extend-details lạ: ${flags['extend-details']} (full | condition | none)`), { code: 2 });
  const { isDrawio, parsed, model, notation } = loadInput(input, flags);
  const base = path.basename(input).replace(/\.model\.json$/i, '').replace(/\.(drawio|xml|json)$/i, '');
  const outDir = flags['out-dir'] || path.join(path.dirname(input), `${base}-review`);
  fs.mkdirSync(outDir, { recursive: true });
  if (isDrawio) fs.writeFileSync(path.join(outDir, `${base}.model.json`), JSON.stringify(model, null, 2) + '\n');
  const lang = flags.lang || 'vi';
  fillLines(model);
  const res = { outDir, files: [] };
  // bước AI: ai.json viết sẵn, HOẶC câu hỏi đóng trả lời bằng file (--answers) / bằng CLI model (--ask-cmd, env UC_REVIEW_ASK)
  let ai = flags.ai ? readJson(flags.ai) : null;
  const askCmd = await resolveAskCmd(flags['ask-cmd'] || process.env.UC_REVIEW_ASK || null);
  if (askCmd) res.askCmd = askCmd;
  if (!ai && (askCmd || flags.answers)) {
    const Q = buildQuestions(model, collectFindings(model, notation, null, { lang, extendDetails: xd }), lang);
    fs.writeFileSync(path.join(outDir, `${base}.questions.txt`), `${Q.prompt}\n`);
    let got;
    if (flags.answers) { const v = validateAnswers(readJson(flags.answers), Q, model); got = { answers: v.answers, errors: v.errors, log: [] }; }
    else got = await askModel(askCmd, Q, model, { timeout: Number(flags['ask-timeout'] || 240) });
    fs.writeFileSync(path.join(outDir, `${base}.answers.json`), JSON.stringify(got, null, 2) + '\n');
    ai = answersToAi(model, Q, got.answers, lang);
    fs.writeFileSync(path.join(outDir, `${base}.ai.json`), JSON.stringify(ai, null, 2) + '\n');
    res.ask = got;
  }
  if (xd === 'none') ai = withoutConditions(ai);
  if (ai?.uncertain) model._uncertain = uniq([...(model._uncertain || []), ...ai.uncertain]);
  const items = collectFindings(model, notation, ai, { lang, extendDetails: xd });
  res.items = items;
  const kind = isDrawio ? 'drawio' : model._source?.kind || (flags.image ? 'image' : 'model');
  const stats = parsed?.stats || { actors: (model.actors || []).length, usecases: (model.usecases || []).length, links: (model.associations || []).length + (model.includes || []).length + (model.extends || []).length + (model.generalizations || []).length + Object.keys(model.actorParents || {}).length };
  fs.writeFileSync(path.join(outDir, `${base}.findings.json`), JSON.stringify(items.map(({ num, sev, code, source, refs, what, fix, uncertain }) => ({ num, sev, code, source, refs, what, fix, ...(uncertain ? { uncertain } : {}) })), null, 2) + '\n');
  const modes = new Set(String(flags.mode || 'errors').split(',').flatMap((m) => (m.trim() === 'both' ? ['errors', 'fix'] : [m.trim()])));
  for (const m of modes) if (!['errors', 'fix', 'inplace'].includes(m)) throw Object.assign(new Error(`--mode lạ: ${m} (errors | fix | inplace | both, ghép bằng dấu phẩy)`), { code: 2 });
  if (modes.has('errors')) {
    const md = path.join(outDir, `${base}.review.md`);
    fs.writeFileSync(md, reviewMd(model, items, { kind, stats, read: parsed?.read || null }, lang));
    res.files.push(md);
    if (parsed) {
      const dr = path.join(outDir, `${base}.review.drawio`), sv = path.join(outDir, `${base}.review.svg`);
      fs.writeFileSync(dr, annotateDrawio(parsed, items, lang));
      fs.writeFileSync(sv, renderCustomerSvg(parsed, items, lang));
      const r = flags['no-png'] ? { png: null } : await renderPng(dr, sv);
      res.files.push(dr, ...(r.png ? [r.png] : [sv])); res.pngVia = r.via;
    } else if (flags.image) {
      const sv = path.join(outDir, `${base}.review.svg`), png = path.join(outDir, `${base}.review.png`);
      fs.writeFileSync(sv, renderImageSvg(flags.image, model, items, lang));
      const via = flags['no-png'] ? null : await svgToPng(sv, png);
      res.files.push(via ? png : sv); res.pngVia = via;
    }
  }
  if (modes.has('fix')) {
    const fixed = fixModel(model, items, ai || {}, lang);
    const fb = path.join(outDir, `${base}.fixed`);
    fs.writeFileSync(`${fb}.model.json`, JSON.stringify(fixed.model, null, 2) + '\n');
    const r = await renderFixed(fixed.model, fb, { png: !flags['no-png'] });
    fs.writeFileSync(`${fb}.md`, fixedMd(model, fixed, items, lang));
    res.files.push(`${fb}.md`, `${fb}.drawio`, ...(r.png ? [r.png] : [`${fb}.svg`]));
    res.fixed = fixed;
  }
  let again = null;
  if (modes.has('inplace')) {
    if (!parsed) throw Object.assign(new Error('--mode inplace cần đầu vào .drawio (ảnh thì dùng --mode fix để vẽ lại)'), { code: 2 });
    const fixed = fixModel(model, items, ai || {}, lang, { inplace: true });
    const ip = applyInPlace(parsed, fixed, items, lang);
    const fb = path.join(outDir, `${base}.inplace`);
    fs.writeFileSync(`${fb}.drawio`, ip.xml);
    again = parseUseCaseDrawio(ip.xml, { page: parsed.pageNo });
    const left = collectFindings(again.model, again.notation, null, { lang }).filter((i) => i.sev === 'error');
    fs.writeFileSync(`${fb}.svg`, renderCustomerSvg(again, [], lang, { legend: false }));
    const r = flags['no-png'] ? { png: null } : await renderPng(`${fb}.drawio`, `${fb}.svg`);
    const done = { ...fixed, changes: [...fixed.changes, ...ip.extra].sort((p, q) => (p.num ?? 1e9) - (q.num ?? 1e9)) };
    fs.writeFileSync(`${fb}.md`, fixedMd(model, done, items, lang, { left, inplace: true }));
    res.files.push(`${fb}.md`, `${fb}.drawio`, ...(r.png ? [r.png] : [`${fb}.svg`]));
    res.inplace = { ...done, left };
  }
  // --web: dữ liệu cho trang web/animation — hình trước (và sau, nếu có inplace) chung một khung toạ độ + vị trí số/khung từng mục
  if (flags.web && parsed) {
    const L = T[lang] || T.vi;
    const U = unionBox(contentBounds(parsed.cells), ...(again ? [contentBounds(again.cells)] : []));
    const ov = overlayOf(parsed, items, { bounds: U });
    const wb = path.join(outDir, base);
    fs.writeFileSync(`${wb}.before.svg`, renderCustomerSvg(parsed, [], lang, { legend: false, bounds: U }));
    if (again) fs.writeFileSync(`${wb}.after.svg`, renderCustomerSvg(again, [], lang, { legend: false, bounds: U }));
    const e = items.filter((i) => i.sev === 'error').length, rv = items.length - e;
    const web = {
      kind: 'drawio', lang, subject: model.subject?.name || null, title: L.legendTitle(e, rv), counts: { error: e, review: rv },
      sevLabel: { error: L.sev.error, review: L.sev.review }, colors: SEV_COLOR,
      read: parsed.read, readNote: L.handDrawn(parsed.read) || null,
      canvas: { width: ov.width, height: ov.height },
      images: { before: `${base}.before.svg`, after: again ? `${base}.after.svg` : null },
      items: ov.items,
      after: res.inplace ? {
        changes: res.inplace.changes.map(({ num, text, sure }) => ({ num, text, sure: !!sure })),
        pending: res.inplace.pending.map(({ num, what, fix }) => ({ num, what, fix })),
        left: res.inplace.left.filter((it) => !res.inplace.pending.some((p) => p.what === it.what)).map(({ what, fix }) => ({ what, fix })),
      } : null,
    };
    fs.writeFileSync(`${wb}.web.json`, JSON.stringify(web, null, 2) + '\n');
    res.files.push(`${wb}.web.json`, `${wb}.before.svg`, ...(again ? [`${wb}.after.svg`] : []));
  }
  return res;
}

const HELP = `uc-review.mjs — review Use Case Diagram người khác vẽ, trả kết quả cho khách (kickoff-uml)
  parse  <in.drawio> [--out f.model.json] [--page N]      bản chép model + vị trí phần tử + lỗi ký hiệu (JSON)
  ask    <in.drawio | bản-chép.model.json> [--out q.txt]  in bộ câu hỏi đóng cho model (dán vào chat/CLI nào cũng được)
  review <in.drawio | bản-chép.model.json> [--image ảnh.png] [--ai ai.json | --answers a.json | --ask-cmd "<lệnh>"]
         [--mode errors|fix|inplace|both] [--out-dir d] [--lang vi|en] [--no-png] [--web] [--ask-timeout 240]
         --ask-cmd: lệnh nhận câu hỏi ở stdin, in câu trả lời — "cmd" trần = Command Code, tự tìm id DeepSeek V4.1 Flash
                    (đổi bằng UC_REVIEW_MODEL); hoặc lệnh đầy đủ "cmd -p --output-format json -m <id>", "claude -p".
                    Đặt sẵn bằng biến môi trường UC_REVIEW_ASK. Câu trả lời bị kiểm, sai thì hỏi lại 1 lần.
         --lang: ngôn ngữ báo cáo cho khách (mặc định vi), không phụ thuộc chữ trên hình
         --extend-details none: đề không đòi điều kiện «extend» → không nhắc "chưa ghi điều kiện", không thêm ghi chú điều kiện
                    (điều kiện khách đã vẽ giữ nguyên); full | condition = mặc định
         errors:  <base>.review.md + .review.png (+ .review.drawio nếu đầu vào là .drawio) — số trên hình khớp danh sách
         fix:     <base>.fixed.drawio/.svg/.png + .fixed.md — vẽ lại toàn bộ bằng bộ vẽ của skill
         inplace: <base>.inplace.drawio/.png + .inplace.md — sửa ngay trên file .drawio của khách, giữ bố cục
         --web:   thêm <base>.web.json + .before.svg (+ .after.svg khi có inplace), chung một khung toạ độ — web/animation
                  tự vẽ số, khung, đường tô màu từ JSON (cờ đặt sau tên file vào)
  Ảnh: AI chép ảnh thành <base>.model.json (_source.kind "image", _geom pixel, _uncertain) rồi chạy review với --image.
  Quy trình + schema ai.json: references/review-mode.md`;

export async function main(argv) {
  const { _: [cmd, target], flags } = parseArgs(argv);
  if (!cmd || !target || flags.help) { console.log(HELP); return cmd ? 2 : 0; }
  try {
    if (cmd === 'parse') {
      const p = parseUseCaseDrawio(fs.readFileSync(target, 'utf8'), { page: flags.page });
      const out = { ...p.model, _notation: p.notation };
      if (flags.out) fs.writeFileSync(flags.out, JSON.stringify(out, null, 2) + '\n'); else console.log(JSON.stringify(out, null, 2));
      console.error(`parse: ${p.stats.usecases} UC, ${p.stats.actors} actor, ${p.stats.links} đường; khung "${p.model.subject.name}"; ${p.notation.length} lỗi ký hiệu/vị trí; trang "${p.page.name}"`);
      return 0;
    }
    if (cmd === 'ask') {
      const { model, notation } = loadInput(target, flags);
      const Q = buildQuestions(model, collectFindings(model, notation, null, { lang: flags.lang || 'vi' }), flags.lang || 'vi');
      if (flags.out) fs.writeFileSync(flags.out, `${Q.prompt}\n`); else console.log(Q.prompt);
      console.error(`ask: ${Q.qs.length} câu hỏi theo phần tử + U/N${Q.nameIds.length ? '/R' : ''}${Q.orphans.length ? '/O' : ''}${Q.needSubject ? '/S' : ''} — lưu câu trả lời thành .json rồi chạy review --answers`);
      return 0;
    }
    if (cmd === 'review') {
      const r = await review(target, flags);
      const e = r.items.filter((i) => i.sev === 'error').length;
      console.log(`review: ${e} lỗi, ${r.items.length - e} nên xem lại → ${r.outDir}`);
      for (const f of r.files) console.log(`  ${path.relative(process.cwd(), f)}`);
      if (r.pngVia) console.log(`  png qua ${r.pngVia}`);
      if (r.fixed) console.log(`  vẽ lại: sửa ${r.fixed.changes.length}, chờ khách quyết ${r.fixed.pending.length}`);
      if (r.inplace) console.log(`  sửa tại chỗ: sửa ${r.inplace.changes.length}, chờ khách quyết ${r.inplace.pending.length}, còn ${r.inplace.left.length} lỗi`);
      if (r.ask) console.log(`  model (${r.askCmd || '--answers'}): ${r.ask.log.length ? r.ask.log.join('; ') : 'trả lời hợp lệ'}${r.ask.errors.length ? ` — bỏ ${r.ask.errors.length} ý sai` : ''}`);
      return 0;
    }
    console.log(HELP); return 2;
  } catch (e) {
    console.error(`ERROR [review] ${e.message}`);
    return e.code || 2;
  }
}

if (process.argv[1] && fs.existsSync(process.argv[1]) && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
