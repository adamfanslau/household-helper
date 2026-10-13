#!/usr/bin/env python3
"""uiautomator XML helpers for android.sh: `tree` (one line per labelled node) and `center <tag>`."""
import re
import sys

xml = sys.stdin.read()
nodes = []
for m in re.finditer(r"<node ([^>]*?)/?>", xml):
    a = dict(re.findall(r'(\S+?)="([^"]*)"', m.group(1)))
    nodes.append(a)

cmd = sys.argv[1] if len(sys.argv) > 1 else "tree"
if cmd == "tree":
    for a in nodes:
        rid, txt, cd = a.get("resource-id", ""), a.get("text", ""), a.get("content-desc", "")
        if rid or txt or cd:
            print(f"{rid or '-'} | {txt or '-'} | {cd or '-'} | {a.get('class', '').split('.')[-1]} | {a.get('bounds', '')}")
elif cmd in ("center", "center-text", "center-desc"):
    key = {"center": "resource-id", "center-text": "text", "center-desc": "content-desc"}[cmd]
    tag = sys.argv[2]
    for a in nodes:
        if a.get(key) == tag:
            b = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", a.get("bounds", ""))
            if b:
                x1, y1, x2, y2 = map(int, b.groups())
                print((x1 + x2) // 2, (y1 + y2) // 2)
                break
