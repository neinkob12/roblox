#!/usr/bin/env python3
"""Paste uploaded Roblox asset IDs into src/shared/Config/Sounds.luau.

Usage (from the repo root):
    python3 sound/fill_ids.py sound/ids.txt
    python3 sound/fill_ids.py            # reads from stdin, finish with Ctrl+D (Ctrl+Z Enter on Windows)

Each input line just needs a file name (with or without .mp3) and a number, in any order,
e.g. lines copied from the Studio Output window:
    12:01:33.123  sfx_moo_1 1234567890
    voice_tier_03  rbxassetid://1234567891
Unknown lines are ignored. Run it again any time; it only touches the IDs.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "src", "shared", "Config", "Sounds.luau")


def parse(text):
    ids = {}
    for line in text.splitlines():
        stem = re.search(r"\b((?:sfx|music|voice)_[a-z0-9_]+?)(?:\.mp3)?\b", line)
        num = re.findall(r"(?<![\w.:])(?:rbxassetid://)?(\d{5,})\b", line)
        if stem and num:
            ids[stem.group(1)] = num[-1]
    return ids


def main():
    text = open(sys.argv[1], encoding="utf-8").read() if len(sys.argv) > 1 else sys.stdin.read()
    ids = parse(text)
    src = open(CONFIG, encoding="utf-8").read()
    done = []
    for stem, num in ids.items():
        m = re.fullmatch(r"voice_tier_(\d+)", stem)
        if m:
            tier = int(m.group(1))
            pat = re.compile(r'"rbxassetid://\d+", -- ' + str(tier) + r"\n")
            src, n = pat.subn(f'"rbxassetid://{num}", -- {tier}\n', src, count=1)
        else:
            pat = re.compile(r'(id = "rbxassetid://)\d+(",\s*file = "sound/[a-z]+/' + re.escape(stem) + r'\.mp3")')
            src, n = pat.subn(r"\g<1>" + num + r"\g<2>", src, count=1)
        if n:
            done.append(stem)
        else:
            print(f"  no slot for {stem}", file=sys.stderr)
    open(CONFIG, "w", encoding="utf-8").write(src)
    print(f"filled {len(done)} ids in {os.path.relpath(CONFIG, ROOT)}")
    left = len(re.findall(r'"rbxassetid://0"', src))
    print(f"{left} sounds still have id 0")


if __name__ == "__main__":
    main()
