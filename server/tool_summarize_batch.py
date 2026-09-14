#!/usr/bin/env python3
"""Summarize vision batch run JSONs into the verdict table.

Reads /tmp/vision_batch_run1.json (and run2 for cache proof):
rows = per audited page: kind, #elements, #relations, #findings by
severity, #unreadable, latency. Prints a compact pipe table.
"""
import json, sys

def table(path):
    with open(path) as f:
        runs = json.load(f)
    print(f"== {path} ({len(runs)} audits)")
    print("page|kind|elements|relations|unread|findings|R/A|elapsed_ms|cached")
    for r in runs:
        red = sum(1 for x in r['findings'] if x['severity'] == 'red')
        amber = sum(1 for x in r['findings'] if x['severity'] != 'red')
        print(f"{r['page']}|{r['kind']}|{len(r['elements'])}|{len(r['relations'])}"
              f"|{len(r['unreadable'])}|{len(r['findings'])}|{red}/{amber}"
              f"|{r['elapsedMs']}|{r['cached']}")
    total_ms = sum(r['elapsedMs'] for r in runs)
    print(f"TOTAL elapsed {total_ms/1000:.1f}s | mean {total_ms/max(1,len(runs))/1000:.1f}s/audit")

for path in sys.argv[1:]:
    table(path)
