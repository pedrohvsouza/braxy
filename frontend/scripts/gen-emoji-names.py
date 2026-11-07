"""Builds src/components/chat/emojiNames.ts (pt-BR names for the picker emoji) from
emojibase-data's CLDR pt annotations:

    npm pack emojibase-data@15.3.2 && tar xzf emojibase-data-15.3.2.tgz
    python3 -I scripts/gen-emoji-names.py package/pt/data.json \\
        src/components/chat/EmojiPicker.tsx src/components/chat/emojiNames.ts
"""
import json
import re
import sys

data_path, picker_path, out_path = sys.argv[1:4]

def norm(e: str) -> str:
    return e.replace("️", "")

entries = {}
for item in json.load(open(data_path, encoding="utf-8")):
    words = [item.get("label", "")] + item.get("tags", [])
    entries[norm(item["emoji"])] = words

picker = open(picker_path, encoding="utf-8").read()
emojis = []
for block in re.findall(r'emojis:\s*\n?\s*"([^"]+)"', picker):
    emojis += block.split(" ")

lines, missing = [], []
for e in emojis:
    words = entries.get(norm(e))
    if not words:
        missing.append(e)
        continue
    seen, uniq = set(), []
    for w in words:
        w = w.strip().lower()
        if w and w not in seen:
            seen.add(w)
            uniq.append(w)
    label, rest = uniq[0], " ".join(uniq[1:])
    lines.append(f'  {json.dumps(e, ensure_ascii=False)}: [{json.dumps(label, ensure_ascii=False)}, {json.dumps(rest, ensure_ascii=False)}],')

header = (
    "// Generated from emojibase-data 15.3.2 (Unicode CLDR, pt): the words each\n"
    "// picker emoji answers to: [name, other search words]. Regenerate with\n"
    "// scripts/gen-emoji-names.py when the picker's lists change.\n"
    "export const EMOJI_NAMES: Record<string, [string, string]> = {\n"
)
open(out_path, "w", encoding="utf-8").write(header + "\n".join(lines) + "\n};\n")
print(f"{len(lines)} named, missing: {' '.join(missing) or 'none'}")
