## VENUE ART PROBE — every league ground/backdrop and every dressing tile LOADS.
##
## ⚠️ AN .import FILE IS NOT PROOF THE TEXTURE LOADS. The editor writes one for anything it
## scanned; a truncated or wrongly-encoded JPEG still gets an .import and then returns null at
## runtime, where `Art.load_or_null`'s degrade-visibly contract turns it into a silently grey
## arena rather than an error. So this asks the engine for the actual Texture2D and checks its
## SIZE, which is the only answer that cannot be faked by the presence of a file.
extends SceneTree

const ARENA_LEAGUES := [
	"wood", "copper", "tin", "bronze", "iron", "silver",
	"gold", "platinum", "masters", "tamer-elite", "tamers-apex",
]

const DRESSING := [
	"barrel-wood.jpg", "crate-wood.jpg", "wall-timber.jpg", "wall-stone.jpg",
	"stands-crowd.jpg", "banner-guild.png",
	"planter-soil.jpg", "bench-wood.jpg", "fence-timber.jpg", "boulder-rock.jpg",
	"pillar-stone.jpg", "shrine-marble.jpg", "low-wall-brick.jpg",
	"sandbag-canvas.jpg", "stone-block.jpg", "timber-stack.jpg", "banner-cloth.jpg",
]

var _pass := 0
var _fail := 0


func _check(path: String, min_w: int) -> void:
	if not ResourceLoader.exists(path):
		print("FAIL  missing        %s" % path)
		_fail += 1
		return
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		print("FAIL  not a texture  %s" % path)
		_fail += 1
		return
	var s := tex.get_size()
	if int(s.x) < min_w or int(s.y) < 1:
		print("FAIL  bad size %s   %s" % [s, path])
		_fail += 1
		return
	print("ok    %4dx%-4d      %s" % [int(s.x), int(s.y), path])
	_pass += 1


func _init() -> void:
	for slug in ARENA_LEAGUES:
		_check("res://assets/arenas/%s-ground.jpg" % slug, 512)
		_check("res://assets/arenas/%s-backdrop.jpg" % slug, 1024)
	for f in DRESSING:
		_check("res://assets/arena/%s" % f, 256)
	print("\nvenue art: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
