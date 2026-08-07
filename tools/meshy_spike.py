"""Meshy image-to-3D spike — ONE creature, end to end.

Answers the four questions ART_BIBLE_LOWPOLY.md §4 asks before any roster work:
  1. rigged output, or does rigging have to be authored?
  2. does it honour a poly budget, or is decimation a post-step?
  3. consistent enough across runs that N creatures look like one roster?
  4. can one skeleton retarget across Avian / Aquatic / Insectoid / Draconic?

⚠️ Reads MESHY_API_KEY from the environment and NEVER prints it.
"""
import os, sys, json, time, base64, urllib.request, urllib.error

API = "https://api.meshy.ai/openapi"
KEY = os.environ.get("MESHY_API_KEY")
if not KEY:
    sys.exit("MESHY_API_KEY not set")


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:600]


def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def main():
    species = sys.argv[1] if len(sys.argv) > 1 else "kongrath"
    img = "monster-tamer/assets/creatures/%s.png" % species
    print("=== MESHY SPIKE: %s ===" % species)
    print("  source: %s" % img)

    st, bal = call("GET", "/v1/balance")
    print("  balance before: %s" % (bal.get("balance") if isinstance(bal, dict) else bal))

    body = {
        "image_url": data_uri(img),
        "should_remesh": True,
        "should_texture": True,
        # ⚠️ ART_BIBLE_LOWPOLY.md: creature budget 700-1,500 tris, ceiling 2,500.
        "target_polycount": 1200,
        "topology": "triangle",
        "symmetry_mode": "auto",
    }
    st, res = call("POST", "/v1/image-to-3d", body)
    print("  POST image-to-3d -> HTTP %s" % st)
    if st not in (200, 201, 202):
        print("  BODY: %s" % res)
        return 1
    task_id = res.get("result") if isinstance(res, dict) else None
    print("  task: %s" % task_id)
    if not task_id:
        print("  unexpected response: %s" % json.dumps(res)[:400])
        return 1

    open("tools/.meshy_task", "w").write(task_id)
    for i in range(120):
        time.sleep(10)
        st, t = call("GET", "/v1/image-to-3d/%s" % task_id)
        if not isinstance(t, dict):
            print("  poll HTTP %s: %s" % (st, t)); return 1
        status = t.get("status")
        print("  [%3ds] %s  progress=%s" % ((i + 1) * 10, status, t.get("progress")))
        if status in ("SUCCEEDED", "FAILED", "CANCELED"):
            open("tools/.meshy_result.json", "w").write(json.dumps(t, indent=2))
            print("  wrote tools/.meshy_result.json")
            if status == "SUCCEEDED":
                print("  model urls: %s" % json.dumps(t.get("model_urls", {}))[:300])
            else:
                print("  error: %s" % t.get("task_error"))
            return 0 if status == "SUCCEEDED" else 1
    print("  timed out waiting")
    return 1


sys.exit(main())
