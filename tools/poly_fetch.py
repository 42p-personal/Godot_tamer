"""Fetch CC0 rigged+animated creatures from Poly Pizza into the Godot project.

⚠️ WHY THIS EXISTS, AND WHAT IT REPLACES. We spent a day generating one creature through Meshy:
~62 credits (30 model + 5 rig + 3 x 9 animations), an 8.4 MB-per-clip download that needed a
stripping pass, ten mislabelled clips, and a bind pose so poor that every animation deformed —
which no choice of MOTION could have fixed. These arrive already rigged, already animated, with
correct clip names, in ONE file of 0.07-0.98 MB, hand-authored rather than auto-retargeted.

⚠️ CC0 ONLY, AND THE FILTER IS NOT OPTIONAL. Poly Pizza is MIXED: most of its catalogue is
CC-BY 3.0, which requires attribution plumbing we do not have. `docs/FREE_3D_ASSET_SOURCES.md`
already flagged this — "CC0 *or* CC-BY, per model" — and the two bundles that prompted this work
were 61-of-64 and 25-of-25 CC-BY respectively. This tool refuses anything that is not CC0 and
writes the licence into the manifest so a later audit can prove it.

⚠️ AND IT REQUIRES A COMPLETE CLIP SET. A creature missing `Death` cannot die on screen. Of 85
CC0 animated models, 43 carry idle + locomotion + attack + death + hit; the rest are logged as
rejected WITH the reason, because a silent filter looks identical to a source that had nothing.

The CDN 403s a bare urllib request — it wants a browser User-Agent. That is not a workaround for
a paywall; the assets are public and free, it is ordinary hotlink protection.
"""
import os, sys, json, struct, urllib.request, urllib.error, time

KEY = os.environ.get("POLY_PIZZA_API")
API = "https://api.poly.pizza/v1"
OUT = "monster-tamer/assets/models/creatures"
MANIFEST = "monster-tamer/assets/models/creatures/MANIFEST.json"

HDRS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)", "Referer": "https://poly.pizza/"}

# Search terms swept to enumerate the catalogue. The API has no "list everything animated"
# endpoint, so coverage comes from breadth of terms — recorded here so the next person can see
# exactly how wide the net was, rather than assuming it was exhaustive.
TERMS = ["animal", "monster", "creature", "dog", "cat", "bear", "wolf", "fox", "lizard", "dragon",
         "bird", "fish", "shark", "horse", "deer", "frog", "penguin", "rabbit", "cow", "sheep",
         "spider", "insect", "crocodile", "gorilla", "ape", "tiger", "lion", "snake", "turtle",
         "bat", "rat", "goat", "demon", "goblin", "orc", "skeleton", "slime", "blob", "crab"]

# What the sim needs, and every clip name seen in the wild that satisfies it. ⚠️ Quaternius uses
# several conventions across packs (`HitReact` vs `HitRecieve` — their typo, kept as shipped;
# `Punch` vs `Attack` vs `Headbutt` vs `Bite_Front`), so this matches on a SET, never one name.
REQUIRED = {
    "idle":   {"idle", "flying_idle"},
    "move":   {"walk", "run", "fast_flying", "flying", "swim"},
    "attack": {"attack", "attack2", "punch", "headbutt", "bite_front", "spellcast", "weapon"},
    "death":  {"death", "die"},
    "hit":    {"hitreact", "hitrecieve", "hit", "damage"},
}


def api(path):
    r = urllib.request.Request(API + path, headers={"x-auth-token": KEY})
    with urllib.request.urlopen(r, timeout=45) as x:
        return json.loads(x.read().decode())


def fetch(url, dest):
    d = urllib.request.urlopen(urllib.request.Request(url, headers=HDRS), timeout=120).read()
    tmp = dest + ".part"
    open(tmp, "wb").write(d)
    os.replace(tmp, dest)
    return len(d)


def glb_info(path):
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen).decode())
    clips = [a.get("name", "?").split("|")[-1] for a in js.get("animations", [])]
    tris = sum(js["accessors"][p["indices"]]["count"] // 3
               for m in js.get("meshes", []) for p in m.get("primitives", []) if "indices" in p)
    return clips, tris, len(js.get("skins", []))


def slug(title):
    return "".join(c.lower() if c.isalnum() else "_" for c in title).strip("_")


def main():
    if not KEY:
        raise SystemExit("POLY_PIZZA_API is not set in the environment")
    os.makedirs(OUT, exist_ok=True)

    found = {}
    for t in TERMS:
        try:
            for m in api("/search/%s?limit=100" % t).get("results", []):
                found[m["ID"]] = m
        except Exception as e:
            print("  search '%s' failed: %s" % (t, type(e).__name__))
        time.sleep(0.12)
    print("catalogue swept: %d unique models over %d terms" % (len(found), len(TERMS)))

    animated = [m for m in found.values() if m.get("Animated")]
    cc0 = [m for m in animated if "CC0" in str(m.get("Licence", ""))]
    print("  animated: %d   of those CC0: %d   (CC-BY skipped: %d)"
          % (len(animated), len(cc0), len(animated) - len(cc0)))

    kept, rejected = [], []
    for m in sorted(cc0, key=lambda m: m["Title"]):
        name = slug(m["Title"])
        dest = "%s/%s.glb" % (OUT, name)
        try:
            size = os.path.getsize(dest) if os.path.exists(dest) else fetch(m["Download"], dest)
        except Exception as e:
            rejected.append((m["Title"], "download failed: %s" % type(e).__name__)); continue
        try:
            clips, tris, skins = glb_info(dest)
        except Exception as e:
            rejected.append((m["Title"], "unreadable glb")); os.remove(dest); continue

        low = {c.lower() for c in clips}
        missing = [k for k, v in REQUIRED.items() if not (low & v)]
        if missing:
            rejected.append((m["Title"], "no " + "/".join(missing)))
            os.remove(dest)
            continue
        kept.append({
            "id": name, "title": m["Title"], "polyId": m["ID"],
            "licence": m["Licence"], "creator": m["Creator"]["Username"],
            "attribution": m.get("Attribution", ""),
            "tris": tris, "clips": sorted(clips), "bytes": size,
        })

    json.dump({"source": "poly.pizza", "licence": "CC0 1.0 only", "creatures": kept},
              open(MANIFEST, "w"), indent=1)

    print("\nKEPT %d (complete clip set: %s)" % (kept and len(kept) or 0, "+".join(REQUIRED)))
    for k in kept:
        print("  %-24s %6d tris %2d clips  %.2f MB  %s" % (k["id"], k["tris"], len(k["clips"]),
                                                           k["bytes"] / 1e6, k["creator"]))
    print("\nREJECTED %d — reason given so a silent filter cannot look like an empty source:" % len(rejected))
    for t, why in rejected:
        print("  %-24s %s" % (t, why))
    print("\nmanifest -> %s" % MANIFEST)
    return 0


sys.exit(main())
