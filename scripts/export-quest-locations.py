"""Export visible NPCs that advance a literal quest ID in enabled Renewal scripts."""
import argparse
import json
import re
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("server", type=Path)
args = parser.parse_args()
resources = Path(__file__).resolve().parents[1] / "Packages/RagnarokGame/Sources/RagnarokGame/Resources"
known = json.loads((resources / "QuestTitles.json").read_text())
locations = defaultdict(set)
visited = set()

def read_scripts(config):
    if config in visited:
        return
    visited.add(config)
    for kind, name in re.findall(r"(?m)^\s*(import|npc):[ \t]*([^\s/][^\s]*)", config.read_text(errors="replace")):
        source = args.server / name
        if kind == "import":
            read_scripts(source)
            continue
        code = re.sub(r"/\*.*?\*/|//[^\n]*", "", source.read_text(errors="replace"), flags=re.S)
        for npc in re.finditer(r"(?ms)^([\w@-]+),(\d+),(\d+),\d+\tscript\t([^\t\n]+)\t(\d+),[^\n]*?\{(.*?)^\}", code):
            map_name, x, y, full_name, sprite, body = npc.groups()
            label = full_name.split("::")[0].split("#")[0].strip()
            if not label or sprite in {"111","139"} or "@" in map_name:
                continue
            for quest in re.findall(r"\b(?:changequest|completequest)\s*\(?\s*(\d+)\b", body):
                if quest in known:
                    locations[quest].add(f"{label} · {map_name} ({x}, {y})")

read_scripts(args.server / "npc/re/scripts_main.conf")
output = {k: sorted(locations[k]) for k in sorted(locations, key=int)}
(resources / "QuestLocations.json").write_text(json.dumps(output, ensure_ascii=False, indent=1) + "\n")
print(f"{len(output)} quest IDs")
