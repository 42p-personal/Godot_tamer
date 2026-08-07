"""Strip embedded textures from an animation GLB, keeping mesh, skin and animation tracks.

⚠️ MEASURED: 98.5% of a Meshy animation GLB is TEXTURE, 1.0% is mesh/skin, and 0.5% is the
animation itself. Every clip re-embeds the SAME texture, so a 10-clip character ships the same
8.3 MB image ten times. At roster scale that is 1.65 GB instead of 0.17 GB.

The fix: one textured model carries the look; the animation clips carry only motion. Godot
retargets a clip onto the shared mesh by bone name, and Meshy's rigs use the standard humanoid
set (Hips/Spine/LeftArm/...), so the names line up.

⚠️ This edits the GLB container directly — no Blender, no trimesh, neither of which is installed.
"""
import json, struct, sys, os
sys.stdout.reconfigure(encoding="utf-8")


def read_glb(path):
    with open(path, "rb") as f:
        magic, ver, total = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, "not a GLB"
        jlen, jtype = struct.unpack("<II", f.read(8))
        js = json.loads(f.read(jlen).decode("utf-8"))
        blen, btype = struct.unpack("<II", f.read(8))
        buf = f.read(blen)
    return js, buf


def write_glb(path, js, buf):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)          # chunks must be 4-byte aligned
    buf += b"\x00" * ((4 - len(buf) % 4) % 4)
    total = 12 + 8 + len(jb) + 8 + len(buf)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A)); f.write(jb)
        f.write(struct.pack("<II", len(buf), 0x004E4942)); f.write(buf)


def strip(src, dst):
    js, buf = read_glb(src)
    before = os.path.getsize(src)

    # Which bufferViews do the images own? Those are the bytes we are dropping.
    drop = set()
    for img in js.get("images", []):
        if "bufferView" in img:
            drop.add(img["bufferView"])
    if not drop:
        print("  %s: no embedded images" % os.path.basename(src)); return

    bvs = js.get("bufferViews", [])
    keep = [i for i in range(len(bvs)) if i not in drop]
    remap = {old: new for new, old in enumerate(keep)}

    # Rebuild the binary blob from the surviving views only, and re-point their offsets.
    new_buf = bytearray()
    new_bvs = []
    for old in keep:
        bv = dict(bvs[old])
        off, ln = bv.get("byteOffset", 0), bv["byteLength"]
        # ⚠️ Accessors with a byteStride must stay 4-byte aligned or Godot reads garbage.
        while len(new_buf) % 4:
            new_buf.append(0)
        bv["byteOffset"] = len(new_buf)
        new_buf += buf[off:off + ln]
        new_bvs.append(bv)

    for acc in js.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
    for sk in js.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = sk["inverseBindMatrices"]   # accessor index, already fine

    js["bufferViews"] = new_bvs
    js.pop("images", None)
    js.pop("textures", None)
    js.pop("samplers", None)
    # Materials keep their colour but lose the texture reference they can no longer resolve.
    for m in js.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)
        pbr.setdefault("baseColorFactor", [0.8, 0.8, 0.8, 1.0])
        m.pop("normalTexture", None); m.pop("emissiveTexture", None)
        m.pop("occlusionTexture", None); m.pop("metallicRoughnessTexture", None)
    js["buffers"] = [{"byteLength": len(new_buf)}]

    write_glb(dst, js, bytes(new_buf))
    after = os.path.getsize(dst)
    print("  %-28s %7.2f MB -> %6.2f MB  (%.0f%% smaller)" % (
        os.path.basename(src), before / 1048576, after / 1048576, 100 * (1 - after / before)))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit("usage: glb_strip_textures.py <file.glb> [more.glb ...]")
    for a in args:
        out = a.replace(".glb", "_notex.glb")
        strip(a, out)
