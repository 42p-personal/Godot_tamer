"""Text-to-3D low-poly generation, two-step: preview (geometry) then refine (texture).

Judge the SILHOUETTE before paying to texture it. `ART_BIBLE_LOWPOLY.md`: "judge every model at
40px in flat black first. If two species are not tellable apart as black shapes, the model has
failed regardless of how it looks in the viewport." Texturing a bad mesh only buys an expensive
bad mesh.
"""
import os, sys, json, time, struct, urllib.request, urllib.error

KEY = os.environ.get("MESHY_API_KEY")
API = "https://api.meshy.ai/openapi"

PROMPT = (
    "Low-poly 3D game character: a powerfully built gorilla athlete standing in a neutral A-pose, "
    "arms relaxed and slightly out from the body, facing forward. Dressed as a competitor in a "
    "sporting league: a clean white sleeveless singlet, white cloth hand wraps on both forearms, "
    "white cloth wraps on both ankles, and a single plain fabric sash worn diagonally across the "
    "chest. Natural desaturated charcoal-grey fur. Faceted low-poly geometry with flat shading, "
    "crisp hard edges, chunky simplified forms, and a strong readable silhouette. Neutral even "
    "lighting, no cast shadows. Full body, feet flat on the ground, nothing cropped. No weapons, "
    "no armour plating, no helmet, no blood, no skulls, no fantasy ornament. Clean solid colours, "
    "no surface patterning."
)


def req(path, method="GET", body=None):
    d = json.dumps(body).encode() if body else None
    r = urllib.request.Request(API + path, data=d, method=method,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=120) as x:
            return x.status, json.loads(x.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def poll(tid, label, limit=90):
    for i in range(limit):
        st, t = req("/v2/text-to-3d/%s" % tid)
        if not isinstance(t, dict):
            print("  poll %s: %s" % (st, t)); return None
        if t.get("status") in ("SUCCEEDED", "FAILED", "CANCELED"):
            print("  %s %s after %ds (%s credits)" % (
                label, t["status"], (i + 1) * 8, t.get("consumed_credits")))
            return t if t["status"] == "SUCCEEDED" else None
        if i % 4 == 0:
            print("    %s %s%%" % (label, t.get("progress")))
        time.sleep(8)
    return None


def stats(path):
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen).decode())
    tris = sum(js["accessors"][p["indices"]]["count"] // 3
               for m in js.get("meshes", []) for p in m.get("primitives", []) if "indices" in p)
    return tris, len(js.get("materials", [])), len(js.get("images", []))


def main():
    print("=== LOW-POLY PREVIEW: kongrath ===")
    print("  prompt: %d chars (limit 600)\n" % len(PROMPT))
    st, bal = req("/v1/balance")
    print("  balance: %s\n" % bal.get("balance"))

    body = {
        "mode": "preview",
        "prompt": PROMPT,
        # ⚠️ The dedicated low-poly path. With this set, target_polycount / topology /
        # should_remesh are IGNORED — we get Meshy's low-poly interpretation, not a chosen number.
        "model_type": "lowpoly",
        # ⚠️ A-pose is what humanoid pose estimation wants. Our existing portraits are in natural
        # poses, which is the likeliest reason the avian rig was refused.
        "pose_mode": "a-pose",
        "target_formats": ["glb"],
        "alpha_thumbnail": True,
    }
    st, res = req("/v2/text-to-3d", "POST", body)
    print("  POST preview -> %s" % st)
    if st not in (200, 201, 202):
        print("  %s" % res); return 1
    tid = res["result"]
    open("tools/.meshy_preview", "w").write(tid)
    print("  task %s\n" % tid)

    t = poll(tid, "preview")
    if t is None:
        return 1
    os.makedirs("monster-tamer/assets/models", exist_ok=True)
    out = "monster-tamer/assets/models/kongrath_lowpoly_preview.glb"
    urllib.request.urlretrieve(t["model_urls"]["glb"], out)
    tris, mats, imgs = stats(out)
    print("\n  GEOMETRY: %d triangles, %d materials, %d textures" % (tris, mats, imgs))
    print("  budget check: ART_BIBLE_LOWPOLY.md wants 700-1,500 (ceiling 2,500) -> %s" % (
        "IN BAND" if 700 <= tris <= 1500 else
        "under ceiling" if tris <= 2500 else "*** OVER CEILING ***"))
    for k in ("thumbnail_url", "alpha_thumbnail_url"):
        if t.get(k):
            p = "monster-tamer/assets/models/kongrath_lowpoly_%s.png" % k.replace("_url", "")
            urllib.request.urlretrieve(t[k], p)
            print("  saved %s" % p)
    print("\n  preview task id kept in tools/.meshy_preview for the refine step")
    return 0


sys.exit(main())
