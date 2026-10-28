import sys
sys.path.insert(0,"/Volumes/SSD/Dev/active/PRM392_FlutterMobile/srs-review-ai/app/tool")
from playwright.sync_api import sync_playwright
URL="http://127.0.0.1:8443/?smoke=semantics"
with sync_playwright() as p:
    b=p.chromium.launch(headless=True)
    res=[]
    for i in range(4):
        ctx=b.new_context(viewport={"width":393,"height":852},device_scale_factor=2,
                          is_mobile=True,has_touch=True,service_workers="block")
        pg=ctx.new_page()
        ext=[]
        pg.on("request", lambda r: ext.append(r.url) if "gstatic" in r.url else None)
        pg.goto(URL,wait_until="networkidle",timeout=90000); pg.wait_for_timeout(5000)
        fp=pg.evaluate("()=>{const e=performance.getEntriesByType('paint')[0];return e?Math.round(e.startTime):null}")
        sem=pg.evaluate("()=>document.querySelectorAll('flt-semantics').length")
        res.append((fp,len(ext),sem)); ctx.close()
    b.close()
print("DIAG first-paint(ms) | ext reqs | semantic nodes")
for fp,ex,sm in res: print(f"DIAG   {fp}  {ex}  {sm}")
print("DIAG median first-paint:", sorted(r[0] for r in res)[len(res)//2])
