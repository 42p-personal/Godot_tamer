"""The creature pipeline, one step at a time: preview -> refine -> rig -> animate.

⚠️ THIS REPLACES `meshy_lowpoly.py`, WHICH SHIPPED THE TWO TRAPS `docs/LOWPOLY_MODEL_SPEC.md`
DOCUMENTS AS ALREADY-BURNED-US:

  1. `model_type: "lowpoly"` does NOT produce low poly. It ignores `target_polycount` and
     measured 13,744 triangles — 5.5x the ceiling, with no way to constrain it. The setting that
     works is `"standard"` WITH an explicit target. meshy_lowpoly.py still had "lowpoly" on line
     73 while the spec recorded the fix, so the tool on disk contradicted the recipe that worked.
  2. The prompt limit is 600 characters and the API TRUNCATES SILENTLY at 202 Accepted. The first
     attempt was 755 characters and lost exactly the forbidden list ("NO weapons, NO armour...").
     `check()` below asserts before sending. meshy_lowpoly.py's own prompt was 755 characters.

⚠️ AND ONE THIS TOOL ADDS: `download()` writes to a temp name and only moves it into place after
the bytes are on disk, per-task. The old animation loop moved each file BEFORE fetching the next,
so every one of ten clips landed under the previous state's filename — `kongrath_dead.glb`
contained a BLOCK animation and nothing caught it for a day.

⚠️ THE KEY IS READ FROM THE ENVIRONMENT AND IS NEVER PRINTED, LOGGED OR WRITTEN TO A FILE. This
is a git repository; a key in a tracked file is one `git add -A` away from being published.

Usage:
    python tools/meshy_creature.py balance
    python tools/meshy_creature.py preview  <name>
    python tools/meshy_creature.py refine   <name>
    python tools/meshy_creature.py rig      <name>
    python tools/meshy_creature.py anim     <name> <state> <action_id>
"""
import os, sys, json, time, struct, shutil, urllib.request, urllib.error

KEY = os.environ.get("MESHY_API_KEY")
API = "https://api.meshy.ai/openapi"
MODELS = "monster-tamer/assets/models"
ANIMS = MODELS + "/anim"
STATE = "tools/.meshy"          # <name>.<step> -> task id, so steps can be run separately

# ⚠️ VALHEIM DIRECTION (studio owner, 2026-08-05): "we can go lower poly if its helpful, we are
# looking for an art style akin to valheim". Valheim's creatures sit at 500-900 triangles with
# deliberately LOW-RES, hand-painted, unlit textures — the atmosphere comes from the scene's
# lighting, not from detail baked into the asset. Both halves matter; the texture is arguably the
# bigger half of that look.
# ⚠️ 600 WAS TESTED AND REJECTED. At 600 the head merged into the shoulders and the feet tapered
# to points — the black-silhouette read that `ART_BIBLE_LOWPOLY.md` makes the acceptance test
# failed. And the saving buys nothing: ten units at 1,259 tris is 12,590 triangles on screen.
# The Valheim look comes from the TEXTURE and the shader, not from starving the mesh.
TARGET_TRIS = 1200
TEXTURE_SIZE = 1024             # down from Meshy's 2048 default

# ⚠️ THE BIND POSE IS THE ANIMATION BUDGET. This is the finding that explains why nine generated
# clips all looked wrong on a model that measured fine: Meshy's auto-rigger infers bone placement
# AND skin weights from the pose it is given, and its own guidance names three requirements —
# close to a T-pose or A-pose, a CLEAR GAP between limbs and body, and PALMS FACING THE BODY.
#
# Our first model failed two of the three. A gorilla's bulk closed the gap between arm and torso,
# and the hands came out splayed like claws with palms forward. Bad weights follow from that, and
# every clip inherits them — so no amount of picking better MOTIONS could have fixed it. We spent
# credits comparing three walks when the problem was upstream of all three.
#
# ⚠️ SO THE POSE CLAUSES COME FIRST AND THE ART DESCRIPTION SECOND. Previous versions of this
# prompt led with style and let the pose trail off at the end; the same ordering mistake as the
# texture prompt below, and with the same result — the leading clauses win.
CREATURES = {
    "kongrath": {
        "geometry": (
            "3D game character in a clean symmetrical A-POSE for auto-rigging, STANDING FULLY "
            "UPRIGHT. Legs COMPLETELY STRAIGHT, knees NOT bent, feet flat and parallel with a "
            "gap between them. BOTH ARMS STRAIGHT out from the body at 45 degrees, elbows NOT "
            "bent, with a WIDE GAP of empty space between each arm and the torso. PALMS FACING "
            "INWARD toward the thighs. Fingers TOGETHER and straight, hands flat, NOT spread. "
            "Head up, facing forward. Nothing touching the body. A muscular gorilla athlete in a "
            "white sleeveless singlet, charcoal-grey fur. Low-poly, flat shading, hard edges. "
            "NO weapons, NO base."
        ),
        # ⚠️ LEAD WITH THE UNIFORM. Geometry is fixed by refine time; the only open question is
        # whether the kit appears. And the sash must stay a SEPARATE flat colour region — it is
        # the team-colour carrier (`ART_BIBLE_GUILD_COLOURS.md`) and cannot be tinted at runtime
        # if it bakes into the singlet.
        # ⚠️ THE ORDER OF THIS PROMPT IS LOAD-BEARING AND I GOT IT WRONG ONCE. A version that
        # opened with "Flat hand-painted low-resolution game texture..." and put the kit at the
        # end came back with NO singlet and NO sash — a uniformly grey ape with a white patch at
        # the hips. The style words won and the wardrobe lost. `LOWPOLY_MODEL_SPEC.md` already
        # said so: geometry is fixed by refine time, so the ONLY open question at this step is
        # whether the kit appears — it goes first, and the style language follows it.
        "texture": (
            "A BRIGHT WHITE SLEEVELESS SPORTS SINGLET covering the chest and torso. White cloth "
            "wraps on both forearms. White cloth wraps on both ankles. ONE BOLD CRIMSON SASH worn "
            "diagonally across the chest, a single solid stripe in a colour clearly different "
            "from the white singlet. Muted desaturated charcoal-grey fur everywhere else. "
            "Flat hand-painted low-resolution style: large areas of solid colour, crisp hard "
            "edges between regions, matte finish, no gradients, no baked shadows, no highlights."
        ),
    },
}


def check(name, text, limit=600):
    """⚠️ Assert BEFORE sending. The API accepts an over-length prompt with 202 and drops the
    tail, so an unchecked prompt fails invisibly and the loss lands on whatever you wrote last."""
    n = len(text)
    print("  %s prompt: %d chars (limit %d) %s" % (name, n, limit, "OK" if n <= limit else "*** TOO LONG ***"))
    if n > limit:
        raise SystemExit("refusing to send a prompt the API would silently truncate")


def req(path, method="GET", body=None, timeout=120):
    d = json.dumps(body).encode() if body else None
    r = urllib.request.Request(API + path, data=d, method=method,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=timeout) as x:
            return x.status, json.loads(x.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def poll(endpoint, tid, label, limit=150, every=8):
    for i in range(limit):
        st, t = req("%s/%s" % (endpoint, tid))
        if not isinstance(t, dict):
            print("  poll %s: %s" % (st, t)); return None
        s = t.get("status")
        if s in ("SUCCEEDED", "FAILED", "CANCELED"):
            print("  %s %s after %ds (%s credits)" % (label, s, (i + 1) * every, t.get("consumed_credits")))
            if s != "SUCCEEDED":
                print("  %s" % str(t.get("task_error") or t)[:300])
            return t if s == "SUCCEEDED" else None
        if i % 5 == 0:
            print("    %s %s%%" % (label, t.get("progress")))
        time.sleep(every)
    print("  %s TIMED OUT" % label)
    return None


def download(url, dest):
    """⚠️ Temp-then-move, per file. Writing straight to `dest` means a failed or slow fetch leaves
    a half file that later steps happily load; moving another task's file into place before its
    own download is what mislabelled all ten animation clips."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    urllib.request.urlretrieve(url, tmp)
    shutil.move(tmp, dest)
    return dest


def stats(path):
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen).decode())
    tris = sum(js["accessors"][p["indices"]]["count"] // 3
               for m in js.get("meshes", []) for p in m.get("primitives", []) if "indices" in p)
    clips = [a.get("name", "?") for a in js.get("animations", [])]
    return tris, len(js.get("materials", [])), len(js.get("images", [])), clips


def remember(name, step, tid):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    open("%s.%s.%s" % (STATE, name, step), "w").write(tid)


def recall(name, step):
    p = "%s.%s.%s" % (STATE, name, step)
    if not os.path.exists(p):
        raise SystemExit("no saved %s task for %s — run that step first" % (step, name))
    return open(p).read().strip()


# ═══════════════════════════════════════════════════════════════════════════════════════════════

def cmd_balance():
    st, bal = req("/v1/balance")
    print("balance: %s credits" % bal.get("balance"))


def cmd_preview(name):
    c = CREATURES[name]
    check("geometry", c["geometry"])
    body = {
        "mode": "preview",
        "prompt": c["geometry"],
        # ⚠️ "standard" + an explicit target. NOT "lowpoly" — see the module docstring.
        "model_type": "standard",
        "ai_model": "latest",
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": TARGET_TRIS,
        "pose_mode": "a-pose",          # the riggability lever
        "target_formats": ["glb"],
        "alpha_thumbnail": True,
    }
    st, res = req("/v2/text-to-3d", "POST", body)
    print("  POST preview -> %s" % st)
    if st not in (200, 201, 202):
        print("  %s" % res); return 1
    tid = res["result"]; remember(name, "preview", tid)
    t = poll("/v2/text-to-3d", tid, "preview")
    if t is None:
        return 1
    out = download(t["model_urls"]["glb"], "%s/%s_preview.glb" % (MODELS, name))
    tris, mats, imgs, _ = stats(out)
    print("\n  GEOMETRY: %d triangles (target %d), %d materials, %d textures" % (tris, TARGET_TRIS, mats, imgs))
    print("  %s" % ("IN BAND" if tris <= TARGET_TRIS * 1.6 else "*** OVER TARGET ***"))
    for k in ("thumbnail_url", "alpha_thumbnail_url"):
        if t.get(k):
            download(t[k], "%s/%s_%s.png" % (MODELS, name, k.replace("_url", "")))
    return 0


def cmd_refine(name):
    c = CREATURES[name]
    check("texture", c["texture"])
    body = {
        "mode": "refine",
        "preview_task_id": recall(name, "preview"),
        "prompt": c["texture"],
        "enable_pbr": False,             # flat art, not a PBR surface
        "texture_image_size": TEXTURE_SIZE,
    }
    st, res = req("/v2/text-to-3d", "POST", body)
    print("  POST refine -> %s" % st)
    if st not in (200, 201, 202):
        print("  %s" % res); return 1
    tid = res["result"]; remember(name, "refine", tid)
    t = poll("/v2/text-to-3d", tid, "refine")
    if t is None:
        return 1
    out = download(t["model_urls"]["glb"], "%s/%s_final.glb" % (MODELS, name))
    tris, mats, imgs, _ = stats(out)
    print("  FINAL: %d triangles, %d materials, %d textures, %.2f MB"
          % (tris, mats, imgs, os.path.getsize(out) / 1e6))
    return 0


def cmd_rig(name):
    st, res = req("/v1/rigging", "POST", {
        "input_task_id": recall(name, "refine"),
        "character_height": 1.7,
    })
    print("  POST rig -> %s" % st)
    if st not in (200, 201, 202):
        print("  %s" % res); return 1
    tid = res["result"] if isinstance(res, dict) else res
    remember(name, "rig", tid)
    t = poll("/v1/rigging", tid, "rig")
    if t is None:
        return 1
    urls = t.get("model_urls") or t.get("result", {}).get("model_urls", {})
    if urls.get("glb"):
        out = download(urls["glb"], "%s/%s_rigged.glb" % (MODELS, name))
        print("  rigged -> %s (%.2f MB)" % (out, os.path.getsize(out) / 1e6))
    print("  rig task id: %s" % tid)
    return 0


def cmd_anim(name, state, action_id, existing=None):
    """ONE animation. Deliberately one per invocation so each can be measured and judged before
    the next is paid for — `_probe_motion.gd` reports travel and end-pose, and a clip that scores
    like a statue is a clip to replace, not to ship.

    Pass `existing` (a task id) to re-download a clip already paid for without generating again."""
    if existing:
        tid = existing
        st, t = req("/v1/animations/%s" % tid)
        if st != 200:
            print("  %s" % t); return 1
    else:
        st, res = req("/v1/animations", "POST", {
            "rig_task_id": recall(name, "rig"),
            "action_id": int(action_id),
        })
        print("  POST anim %s (action %s) -> %s" % (state, action_id, st))
        if st not in (200, 201, 202):
            print("  %s" % res); return 1
        tid = res["result"] if isinstance(res, dict) else res
        t = poll("/v1/animations", tid, state)
        if t is None:
            return 1

    # ⚠️ The glb lives at result.animation_glb_url — NOT at model_urls.glb, which is where the
    # text-to-3d and rigging endpoints put theirs. Three endpoints, three response shapes.
    url = (t.get("result") or {}).get("animation_glb_url") or (t.get("model_urls") or {}).get("glb")
    if not url:
        print("  no glb in result: %s" % str(t)[:200]); return 1

    out = download(url, "%s/%s_%s.glb" % (ANIMS, name, state))
    tris, mats, imgs, clips = stats(out)
    # ⚠️ Report BOTH the clip's own internal name and the motion name Meshy put in the URL, and
    # compare them to what we asked for. All ten clips were once mislabelled and nothing noticed
    # for a day; the answer is to make every step state what it actually got.
    from urllib.parse import urlparse
    served = os.path.basename(urlparse(url).path)
    print("  task     %s" % tid)
    print("  served   %s" % served)
    print("  clip     %s" % clips)
    print("  saved    %s  (%.2f MB, %d tris)" % (out, os.path.getsize(out) / 1e6, tris))
    return 0


def main():
    if not KEY:
        raise SystemExit("MESHY_API_KEY is not set in the environment")
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cmd = sys.argv[1]
    a = sys.argv[2:]
    return {
        "balance": lambda: cmd_balance(),
        "preview": lambda: cmd_preview(a[0]),
        "refine":  lambda: cmd_refine(a[0]),
        "rig":     lambda: cmd_rig(a[0]),
        "anim":    lambda: cmd_anim(a[0], a[1], a[2], a[3] if len(a) > 3 else None),
    }[cmd]() or 0


sys.exit(main())
