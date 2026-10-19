#!/usr/bin/env python3
"""Pet soul data for the overlay's pets panel and farm widget.

Downloads A2Tools' Pet Soul Tracker plugin (GPL-3.0, github.com/taengu/A2Tools-Plugins)
from its CDN, checks each file against the catalog's SHA-256, and writes the
English names and soul sources to overlay/data/pets.json. Run it again after
a game patch, when the plugin has a new version:

    scripts/update-pet-data.py
"""
import hashlib
import json
import re
import sys
import urllib.request
from pathlib import Path

CDN = "https://cdn.a2tools.app/plugins"
OUT = Path(__file__).resolve().parent.parent / "overlay" / "data" / "pets.json"


def get(url):
    # The CDN refuses Python's default user agent.
    req = urllib.request.Request(url, headers={"User-Agent": "daevalog-update-pet-data"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def literal(js, name):
    """The object literal assigned to `const <name> = {...};`, as JSON."""
    m = re.search(rf"^const {name} = (\{{.*?^\}});", js, re.S | re.M)
    if not m:
        sys.exit(f"{name} not found: the plugin's format changed")
    body = re.sub(r"^(\s*)([0-9A-Za-z_]+):", r'\1"\2":', m.group(1), flags=re.M)
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", body))


def main():
    index = json.loads(get(f"{CDN}/index.json"))
    plugin = next((p for p in index["plugins"] if p["id"] == "pet-souls"), None)
    if not plugin:
        sys.exit("pet-souls is not in the catalog")
    files = {}
    for name in ("pets.js", "sources.js"):
        data = get(f"{CDN}/pet-souls/{plugin['version']}/{name}")
        if hashlib.sha256(data).hexdigest() != plugin["files"][name]:
            sys.exit(f"{name}: SHA-256 does not match the catalog")
        files[name] = data.decode()

    names = literal(files["pets.js"], "PET_NAMES")
    genus = literal(files["pets.js"], "PET_GENUS")
    sources = literal(files["sources.js"], "PET_SOURCES")
    texts = literal(files["sources.js"], "SOURCE_TEXT")
    en = lambda key: texts.get(key, {}).get("en", key) if key else ""

    def kibelisk(k):
        return {"name": en(k["name"]), "m": k.get("m", 0), "teleport": k.get("teleport", 0)}

    pets = {}
    for pid in sorted(set(names) | set(sources), key=int):
        src = sources.get(pid, {})
        drops = []
        for d in src.get("drops", []):
            drop = {
                "npc": en(d.get("npc")),
                "level": d.get("level", 0),
                "chance": d.get("chance", ""),
                "region": d.get("region", ""),
                "zones": [en(z) for z in d.get("zones", [])],
                "spawns": d.get("spawns", 0),
            }
            if "kibelisk" in d:
                drop["kibelisk"] = kibelisk(d["kibelisk"])
            if "bySide" in d:
                drop["bySide"] = {side: kibelisk(k) for side, k in d["bySide"].items()}
            drops.append(drop)
        pets[pid] = {
            "name": names.get(pid, {}).get("en", f"Pet #{pid}"),
            "genus": genus.get(pid, ""),
            # Only on maps not open yet: counted in the collection, not farmable.
            "unreleased": bool(src.get("unreleased")),
            "drops": drops,
            "chests": [{"name": en(c.get("name")), "chance": c.get("chance", "")} for c in src.get("chests", [])],
        }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out = {
        "source": f"A2Tools Pet Soul Tracker {plugin['version']} (GPL-3.0), {plugin['source']}",
        "pets": pets,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1, sort_keys=True) + "\n")
    print(f"{OUT}: {len(pets)} pets from pet-souls {plugin['version']}")


if __name__ == "__main__":
    main()
