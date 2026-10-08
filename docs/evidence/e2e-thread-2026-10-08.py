"""Luot E2E that cho luong trao doi giang vien <-> sinh vien, 2026-10-08.

Chay tren server SONG (uvicorn) qua HTTP that, khong phai `TestClient`. Do la
diem quan trong nhat cua file nay: mot loi that (`None or ""` bien "khong co
lop" thanh "lop rong") da lam MOI test pytest xanh trong khi loi con nguyen.

Dung:
    cd server
    rm -rf /tmp/e2e-cache && mkdir -p /tmp/e2e-cache
    SRS_CACHE_DIR=/tmp/e2e-cache SRS_MOCK_MODE=true \
      SRS_TEACHER_INVITE_CODE=ma-e2e-that SRS_APP_TOKEN=e2e-token \
      .venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8780 &
    python3 docs/evidence/e2e-thread-2026-10-08.py    # exit 0 = 8/8

Phai XOA SRS_CACHE_DIR truoc moi lan chay: tai khoan da ton tai thi dang ky tra
409 va luot chay dung ngay o buoc 2. Da tung mat mot vong vi dung lai cache cu.

Ba dieu luot nay NOI RA ma no KHONG lam duoc (xem AGENTS.md):
  * `develop` khong co route HTTP nao gan nhom cho sinh vien (ADR-0022 mo ta
    `/roster` nhung file nam trong working tree chua commit), nen sinh vien moi
    dang ky thay danh sach RONG mai mai;
  * giao vien dang ky khong kem lop thi moi thao tac ghi la 409 (dung thiet ke,
    khong co man gan lop) — vi vay buoc 1 phai tao lop TRUOC;
  * tai khoan chua gan nhom nhan 200 + danh sach rong, KHONG phai 403.
"""

import http.cookiejar
import json
import pathlib
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SERVER = pathlib.Path(__file__).resolve().parents[2] / "server"
B = "http://127.0.0.1:8780"

def client():
    jar = http.cookiejar.CookieJar()
    return urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar)), jar

def call(op, method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(B + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with op.open(req) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        return e.code, (json.loads(raw) if raw else None)

tc, _ = client()
gv, _ = client()
sv, _ = client()
ok = []

# 1. Tao lop TRUOC (route lop can app token, chua can tai khoan).
s, cls = call(tc, "POST", "/classes", {"name": "Lop E2E"}, headers={"X-App-Token": "e2e-token"})
print("1 tao lop:", s, cls.get("id"))
assert s == 201, cls
KEY = cls["write_key"]

# 2. Giao vien dang ky VA duoc gan lop. Khong co buoc gan lop nay thi phien
#    khong noi ho lop nao, va moi thao tac ghi deu 409 class_missing — dung
#    thiet ke (ADR-0020 §Consequences: khong co man gan lop), va no la ly do
#    buoc nay ton tai trong E2E chu khong phai mot tien nghi.
s, r = call(tc, "POST", "/auth/register", {"username": "gv-e2e", "password": "matkhau-du-dai",
                                           "role": "teacher", "invite_code": "ma-e2e-that",
                                           "class_id": cls["id"]})
print("2 dang ky giao vien (gan lop):", s, r.get("detail", "ok"))
assert s == 201, r
s, r = call(gv, "POST", "/auth/login", {"username": "gv-e2e", "password": "matkhau-du-dai"})
print("3 dang nhap giao vien:", s, "role=", r.get("role"), "classId=", r.get("classId"))
assert r.get("classId") == cls["id"], r

# 3. Nop bai vao lop
s, sub = call(tc, "POST", "/submissions", {"group": "Nhom E2E", "project": "OTES", "class_id": cls["id"]},
               headers={"X-App-Token": "e2e-token"})
print("4 nop bai:", s, sub["id"])
assert s == 201, sub

# 5. sinh vien dang ky (khong tu khai nhom) roi dang nhap
s, r = call(sv, "POST", "/auth/register", {"username": "sv-e2e", "password": "matkhau-du-dai", "role": "student"})
print("5 dang ky sinh vien:", s, r.get("detail", "ok"))
s, r = call(sv, "POST", "/auth/login", {"username": "sv-e2e", "password": "matkhau-du-dai"})
print("6 dang nhap sinh vien:", s, "group=", r.get("group"))

# 6. danh sach cua sinh vien: chua co nhom -> rong, KHONG loi
s, r = call(sv, "GET", "/submissions")
print("7 danh sach sinh vien (chua gan nhom):", s, "rows=", len(r["submissions"]), "group=", r.get("group"))
assert s == 200 and r["submissions"] == []

# 7. GAN NHOM CHO SINH VIEN — KHONG LAM DUOC QUA HTTP, VA DO LA SU THAT.
#    `develop` khong co route nao gan nhom cho sinh vien. ADR-0022 mo ta
#    `/roster`, nhung no la working tree CHUA COMMIT cua mot phien khac.
#    He qua do duoc: khong co no, mot sinh vien moi dang ky KHONG THE tu lam
#    cho minh co bai nao hien ra; danh sach cua ho la rong mai mai, va chi
#    duong con lai la duoc giao mot ma bai nop. Ghi ra, khong gia vo da xong.
print("7  KHONG co route gan nhom tren develop -> bo qua buoc gan nhom")
print("   => danh sach cua sinh vien se la RONG, va do la ket qua dung de kiem")

# 8. dang nhap lai de lay nhom moi
s, r = call(sv, "POST", "/auth/login", {"username": "sv-e2e", "password": "matkhau-du-dai"})
print("10 dang nhap lai sinh vien:", s, "group=", r.get("group"))
s, r = call(sv, "GET", "/submissions")
print("11 DANH SACH THAT CUA SINH VIEN:", s, "rows=", len(r["submissions"]))
for row in r["submissions"]:
    print("    -", row["id"], row["group"], row["status"], "comments=", row["commentCount"])
print("    (0 hang la DUNG: tai khoan chua duoc gan nhom, va ADR-0020 noi ro do la")
print("     danh sach RONG chu khong phai loi)")
ok.append(("tai khoan chua gan nhom tra danh sach rong chu khong 403", s == 200 and r["submissions"] == []))

# 9. giang vien viet nhan xet BANG PHIEN, khong co class key
s, c = call(gv, "POST", f"/submissions/{sub['id']}/comments",
            {"author": "teacher", "body": "Sua muc 3.2 nhe"})
print("12 giao vien nhan xet bang phien (khong key):", s, c.get("id") if s == 201 else c)
ok.append(("giang vien ghi bang phien", s == 201))

# 10. sinh vien tra loi — qua submission-id, dung deep link (ADR-0019 con song)
s, rep = call(sv, "POST", f"/submissions/{sub['id']}/comments/{c['id']}/replies",
              {"author": "student", "body": "Da em sua roi"})
print("13 sinh vien tra loi:", s)
ok.append(("sinh vien tra loi", s == 201))

# 11. sinh vien khong the quyet dinh
s, r = call(sv, "POST", f"/submissions/{sub['id']}/decision", {"decision": "approved", "note": ""})
print("14 sinh vien tu duyet (phai bi tu choi):", s, r)
ok.append(("sinh vien khong tu duyet", s == 403))

# 12. giao vien quyet dinh bang phien
s, r = call(gv, "POST", f"/submissions/{sub['id']}/decision",
            {"decision": "changes_requested", "note": "Sua muc 3.2"})
print("15 giao vien quyet dinh bang phien:", s, r.get("status") if s == 200 else r)
ok.append(("giang vien quyet dinh bang phien", s == 200))

# 13. sinh vien doc lai thay ca thread
s, r = call(sv, "GET", f"/submissions/{sub['id']}")
print("16 sinh vien doc lai thread:", s, "comments=", len(r.get("comments") or []),
      "status=", r.get("status"))
ok.append(("sinh vien doc lai thay thread", s == 200 and len(r.get("comments") or []) == 1))

# 14. sinh vien khong duoc mao danh giao vien du co class key
s, r = call(sv, "POST", f"/submissions/{sub['id']}/comments",
            {"author": "teacher", "body": "toi la giao vien"}, headers={"X-Class-Key": KEY})
print("17 sinh vien mao danh giao vien (co ca class key!):", s, r)
ok.append(("khong mao danh duoc", s == 403))

# 15. sinh vien khong doc duoc danh sach lop khac
s, r = call(sv, "GET", "/submissions?class_id=nope")
print("18 thu mo rong pham vi bang query:", s, "rows=", len(r["submissions"]))
# Khang dinh dung: tham so la PHAI bi bo qua, va ket qua phai Y HET khi khong co
# tham so. Doi chieu voi "s == 1 hang" la sai — tai khoan nay khong co nhom, nen
# "dung" o day la 0 hang trong CA HAI lan goi. Kiem bang cach so hai lan.
s2, baseline = call(sv, "GET", "/submissions")
ok.append(("tham so la bi bo qua, khong mo rong pham vi",
           s == 200 and len(r["submissions"]) == len(baseline["submissions"])))

print()
for name, passed in ok:
    print(("  OK  " if passed else " FAIL ") + name)
print()
print("TONG:", sum(1 for _, p in ok if p), "/", len(ok))
sys.exit(0 if all(p for _, p in ok) else 1)
