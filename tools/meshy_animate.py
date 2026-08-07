"""Generate the game's animation set for one rigged character.

⚠️ Maps the SIM'S OWN state vocabulary (spatial_sim.gd's `state` field) onto Meshy action ids, so
every state the simulation can emit has something to show. A state the sim can be in and the
animation cannot show is a state the player cannot read — the whole failure mode of a game you
only watch.
"""
import os, sys, json, time, struct, urllib.request, urllib.error

KEY = os.environ.get("MESHY_API_KEY")
API = "https://api.meshy.ai/openapi"

# state -> (action_id, why this one)
PLAN = [
    ("idle",     0,   "Idle — most of a fight is spent here"),
    ("advance",  112, "Monster_Walk — a creature gait, not a human one"),
    ("attack",   4,   "Attack"),
    ("cast",     125, "Charged_Spell_Cast — legibly not a swing"),
    ("stunned",  172, "Electrocution_Reaction — a stagger reads better than a knockdown for "
                      "'incapacitated but standing'"),
    ("dead",     8,   "Dead"),
    ("guard",    138, "Block1 — guard is a real mechanic and only started working today"),
    ("victory",  59,  "Victory_Cheer — this is a sport; the payoff shot"),
    ("hurt",     178, "Hit_Reaction — ⚠️ OVERLAY, not a state: the sim emits a shot, never a "
                      "'hurt' state, so this must additively blend over whatever is playing"),
]
# ⚠️ `retreat` is deliberately absent — it is `advance` played in REVERSE. Free, and correct:
# a creature backing off should move backwards, not turn and walk away.


def req(path, method="GET", body=None):
    d = json.dumps(body).encode() if body else None
    r = urllib.request.Request(API + path, data=d, method=method,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=90) as x:
            return x.status, json.loads(x.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]


def inspect(path):
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen).decode())
    out = []
    for a in js.get("animations", []):
        sm = a.get("samplers", [])
        keys = max(js["accessors"][s["input"]]["count"] for s in sm) if sm else 0
        dur = max(js["accessors"][s["input"]].get("max", [0])[0] for s in sm) if sm else 0
        out.append((a.get("name", "?"), keys, dur))
    return out


def main():
    rig = sys.argv[1] if len(sys.argv) > 1 else "019fcf6e-8180-720f-b146-ca3020efb2c5"
    name = sys.argv[2] if len(sys.argv) > 2 else "kongrath"
    outdir = "monster-tamer/assets/models/anim"
    os.makedirs(outdir, exist_ok=True)

    st, bal = req("/v1/balance")
    print("=== ANIMATION SET: %s ===\n  balance before: %s\n" % (name, bal.get("balance")))

    tasks = []
    for state, aid, why in PLAN:
        st, res = req("/v1/animations", "POST", {"rig_task_id": rig, "action_id": aid})
        if st not in (200, 201, 202):
            print("  %-9s id=%-4s POST FAILED %s %s" % (state, aid, st, res))
            continue
        tasks.append((state, aid, res["result"], why))
        print("  %-9s id=%-4s queued  (%s)" % (state, aid, why[:52]))

    print("\n  waiting...")
    results = []
    for state, aid, tid, why in tasks:
        for _ in range(40):
            st, t = req("/v1/animations/%s" % tid)
            if isinstance(t, dict) and t.get("status") in ("SUCCEEDED", "FAILED", "CANCELED"):
                break
            time.sleep(5)
        if not isinstance(t, dict) or t.get("status") != "SUCCEEDED":
            print("  %-9s FAILED: %s" % (state, t.get("task_error") if isinstance(t, dict) else t))
            continue
        path = "%s/%s_%s.glb" % (outdir, name, state)
        urllib.request.urlretrieve(t["result"]["animation_glb_url"], path)
        for clip, keys, dur in inspect(path):
            ok = "real motion" if keys > 2 else "*** BIND POSE ***"
            print("  %-9s %-34s %3d keys  %.2fs  %s" % (state, clip[:34], keys, dur, ok))
        results.append(state)

    st, bal2 = req("/v1/balance")
    print("\n  %d of %d generated.  balance now %s (spent %s)" % (
        len(results), len(PLAN), bal2.get("balance"), bal.get("balance") - bal2.get("balance")))


sys.exit(main())
