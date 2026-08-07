"""⚠️ THE QUESTION THAT DECIDES THE ROSTER PLAN.

Meshy's auto-rig refused an avian with `422 Pose estimation failed` (docs/MESHY_SPIKE_RESULT.md).
That model came from image-to-3D of a portrait in a NATURAL pose. The hypothesis: pose estimation
wants an A-pose, and generating one explicitly may rescue the non-humanoid bodies.

If an A-posed bird rigs, skeletal animation covers all 65 species and the whole roster plan
changes. If it does not, procedural stays the floor for most of the bestiary. Either answer is
worth ~35 credits.

⚠️ NOTE THE PROMPT HAS NO SASH CLAUSE. Team colour now lives entirely in the in-engine ring and
health bar (scripts/ui/team_marker.gd), which frees the character budget and removes the failure
mode that produced a white-on-white sash last time.
"""
import os, sys, json, time, struct, urllib.request, urllib.error
sys.stdout.reconfigure(encoding="utf-8")

KEY = os.environ.get("MESHY_API_KEY")
API = "https://api.meshy.ai/openapi"

PROMPT = (
    "Low-poly faceted 3D game character. Flat shading, hard edges, chunky simplified forms, "
    "strong readable silhouette. A tall crested songbird ATHLETE standing upright on two legs in "
    "a neutral A-pose: wings held out and away from the body like arms, feet flat, full body "
    "visible, facing forward. Wearing a plain white sports vest and white cloth wraps on both "
    "legs. Desaturated tan and grey-brown plumage. Clean solid colours, no patterns. Even neutral "
    "lighting, no baked shadows. NO weapons, NO armour, NO blood, NO ornament, NO base or scenery."
)
assert len(PROMPT) <= 600, "prompt is %d chars, limit is 600" % len(PROMPT)


def req(path, method="GET", body=None):
    d = json.dumps(body).encode() if body else None
    r = urllib.request.Request(API + path, data=d, method=method,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=120) as x:
            return x.status, json.loads(x.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def wait(path, tid, label, limit=90):
    for i in range(limit):
        st, t = req("%s/%s" % (path, tid))
        if isinstance(t, dict) and t.get("status") in ("SUCCEEDED", "FAILED", "CANCELED"):
            print("  %-9s %s after %ds (%s credits)" % (
                label, t["status"], (i + 1) * 8, t.get("consumed_credits")))
            return t
        time.sleep(8)
    return None


print("=== A-POSE RIGGABILITY TEST: avian ===")
print("  prompt %d/600 chars\n" % len(PROMPT))

st, res = req("/v2/text-to-3d", "POST", {
    "mode": "preview", "prompt": PROMPT, "model_type": "standard", "ai_model": "latest",
    "should_remesh": True, "topology": "triangle", "target_polycount": 1200,
    "pose_mode": "a-pose", "target_formats": ["glb"], "alpha_thumbnail": True,
})
if st not in (200, 201, 202):
    sys.exit("preview POST failed: %s %s" % (st, res))
prev = res["result"]
print("  preview task %s" % prev)
t = wait("/v2/text-to-3d", prev, "preview")
if t is None or t.get("status") != "SUCCEEDED":
    sys.exit(1)

out = "monster-tamer/assets/models/larkessa_apose_preview.glb"
urllib.request.urlretrieve(t["model_urls"]["glb"], out)
with open(out, "rb") as f:
    f.read(12); clen, _ = struct.unpack("<II", f.read(8)); js = json.loads(f.read(clen).decode())
tris = sum(js["accessors"][p["indices"]]["count"] // 3
           for m in js.get("meshes", []) for p in m.get("primitives", []) if "indices" in p)
print("  geometry: %d tris" % tris)
if t.get("thumbnail_url"):
    urllib.request.urlretrieve(t["thumbnail_url"], "monster-tamer/assets/models/larkessa_apose.png")
    print("  thumbnail saved")

# refine so the rig has a finished model to work from, matching the kongrath recipe
st, res = req("/v2/text-to-3d", "POST", {
    "mode": "refine", "preview_task_id": prev, "enable_pbr": False, "target_formats": ["glb"],
    "prompt": ("Plain white sports vest, white cloth wraps on both legs, desaturated tan and "
               "grey-brown plumage. Flat solid colours, crisp edges, no gradients, no patterns, "
               "no logos, no baked shadows."),
})
if st in (200, 201, 202):
    fin = wait("/v2/text-to-3d", res["result"], "refine")
    if fin and fin.get("status") == "SUCCEEDED":
        urllib.request.urlretrieve(fin["model_urls"]["glb"],
            "monster-tamer/assets/models/larkessa_apose_final.glb")

# ⚠️ THE ACTUAL TEST
print("\n  --- rigging an A-posed avian ---")
st, res = req("/v1/rigging", "POST", {"input_task_id": prev})
print("  POST /v1/rigging -> %s" % st)
if st not in (200, 201, 202):
    print("  RESULT: *** STILL REFUSED *** %s" % res)
    print("  -> A-pose does NOT rescue non-humanoid bodies. Procedural stays the floor.")
    sys.exit(0)
rt = wait("/v1/rigging", res["result"], "rig")
if rt and rt.get("status") == "SUCCEEDED":
    print("\n  RESULT: *** A-POSED AVIAN RIGGED SUCCESSFULLY ***")
    print("  -> skeletal animation can cover non-humanoid bodies after all.")
    urllib.request.urlretrieve(rt["result"]["rigged_character_glb_url"],
        "monster-tamer/assets/models/larkessa_apose_rigged.glb")
else:
    print("\n  RESULT: rig task failed: %s" % (rt.get("task_error") if rt else "timeout"))
