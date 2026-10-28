import hashlib, json, pathlib, re
root=pathlib.Path.cwd()
out=root/'docs/evidence/pre-firebase-fixes'
before=json.loads((out/'source-before.json').read_text(encoding='utf-8-sig'))
changed=[]
for name,digest in before.items():
 p=root/name
 if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest().upper()!=digest.upper(): changed.append(name)
added=[str(p.relative_to(root)) for d in ['lib','test','integration_test','assets'] for p in (root/d).rglob('*') if p.is_file() and str(p.relative_to(root)) not in before]
(out/'source-changes.json').write_text(json.dumps({'baselineFiles':len(before),'changed':changed,'added':added,'deleted':[n for n in before if not (root/n).exists()],'fixturesChanged':[n for n in changed if n.startswith('assets') or 'fixtures' in n]},indent=2),encoding='utf-8')
files=list((root/'lib').rglob('*.dart')); graph={p.resolve():[] for p in files}
for p in graph:
 for imp in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)",p.read_text(encoding='utf-8-sig')):
  q=(root/'lib'/imp.split('/',1)[1]).resolve() if imp.startswith('package:srs_review_ai_mobile/') else (p.parent/imp).resolve()
  if q in graph: graph[p].append(q)
index={}; low={}; stack=[]; active=set(); cycles=[]
def visit(v):
 index[v]=low[v]=len(index); stack.append(v); active.add(v)
 for w in graph[v]:
  if w not in index: visit(w); low[v]=min(low[v],low[w])
  elif w in active: low[v]=min(low[v],index[w])
 if low[v]==index[v]:
  group=[]
  while True:
   w=stack.pop(); active.remove(w); group.append(str(w.relative_to(root)).replace('\\','/'))
   if w==v: break
  if len(group)>1: cycles.append(sorted(group))
for p in graph:
 if p not in index: visit(p)
baseline=json.loads((root/'docs/evidence/final-audit/dependency-audit.json').read_text(encoding='utf-8-sig'))['cyclesSCC']
old={tuple(sorted(x)) for x in baseline}
result={'dartFiles':len(files),'cycles':cycles,'newCycles':[c for c in cycles if tuple(c) not in old], 'viewModelViewImports':[str(p.relative_to(root)) for p in files if 'viewmodels' in p.parts and re.search(r"import[^\n]*(?:screens/|widgets/)",p.read_text(encoding='utf-8-sig'))]}
(out/'dependency-check.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'changed':len(changed),'added':len(added),'fixturesChanged':[] if not any(n.startswith('assets') for n in changed) else 'CHECK','newCycles':result['newCycles'],'viewModelViewImports':result['viewModelViewImports']}))
