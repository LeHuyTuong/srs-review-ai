import sys
import fitz

d = fitz.open(sys.argv[1])
for p in [int(x) for x in sys.argv[2].split(",")]:
    print(f"=== page {p} ===")
    print(d[p].get_text("text")[:1800])
