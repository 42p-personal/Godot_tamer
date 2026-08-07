"""Rename animation clips from the clip's OWN internal name, never from download order.

⚠️ THE BUG THIS FIXES. `tools/meshy_animate.py`'s download loop moved the temp file to its
destination and only THEN re-downloaded the next task, so every clip landed under the previous
state's filename — the whole set shifted by one. `kongrath_dead.glb` was carrying `Block1`.
Silent, and invisible until someone parsed the keyframe counts and noticed they did not match.

A GLB carries its clip name inside (`Armature|<ActionName>|baselayer`), so the file can always be
named from its own contents. That makes the mistake impossible rather than merely fixed.
"""
import json, struct, sys, os, glob, shutil
sys.stdout.reconfigure(encoding="utf-8")

# Meshy action name -> the sim state it serves (spatial_sim.gd's `state` field)
ACTION_TO_STATE = {
    "Idle": "idle",
    "Monster_Walk": "advance",
    "Attack": "attack",
    "Charged_Spell_Cast": "cast",
    "Electrocution_Reaction": "stunned",
    "Dead": "dead",
    "Block1": "guard",
    "Victory_Cheer": "victory",
    "Hit_Reaction": "hurt",
    "Double_Combo_Attack": "attack_alt",
}


def clip_name(path):
    with open(path, "rb") as f:
        f.read(12)
        clen, _ = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(clen).decode())
    anims = js.get("animations", [])
    if not anims:
        return None
    return anims[0].get("name", "").replace("Armature|", "").replace("|baselayer", "")


def main(species, folder):
    files = [p for p in glob.glob(os.path.join(folder, "%s_*.glb" % species))
             if "_notex" not in p]
    if not files:
        print("no clips found for %s in %s" % (species, folder)); return 1

    print("  current filename        clip inside                   correct name")
    plan = []
    for p in sorted(files):
        nm = clip_name(p)
        if nm is None:
            print("  %-22s (no animation)  -- skipped" % os.path.basename(p)); continue
        state = ACTION_TO_STATE.get(nm)
        if state is None:
            print("  %-22s %-28s ?? unmapped action" % (os.path.basename(p), nm)); continue
        want = "%s_%s.glb" % (species, state)
        mark = "ok" if os.path.basename(p) == want else "-> " + want
        print("  %-22s %-28s %s" % (os.path.basename(p), nm, mark))
        plan.append((p, os.path.join(folder, want)))

    wrong = [(a, b) for a, b in plan if os.path.basename(a) != os.path.basename(b)]
    if not wrong:
        print("\n  all %d already correct" % len(plan)); return 0

    # ⚠️ Two-phase via temp names — renaming in place would clobber a file that is itself about to
    # be renamed, which is exactly how the original bug destroyed the mapping.
    tmp = []
    for i, (src, dst) in enumerate(plan):
        t = os.path.join(folder, ".__fix%d.glb" % i)
        shutil.move(src, t)
        tmp.append((t, dst))
    for t, dst in tmp:
        shutil.move(t, dst)
    print("\n  renamed %d of %d clips" % (len(wrong), len(plan)))
    return 0


if __name__ == "__main__":
    sp = sys.argv[1] if len(sys.argv) > 1 else "kongrath"
    fd = sys.argv[2] if len(sys.argv) > 2 else "monster-tamer/assets/models/anim"
    sys.exit(main(sp, fd))
