## IS THE DENSITY LAW STILL SANE ON THE NEW BOARD? Three numbers that matter, none of which is
## the piece COUNT on its own:
##   cover fraction — total obstacle footprint as a share of the floor. Scale-free.
##   piece vs body  — a piece's width in BODY DIAMETERS. Cover you are wider than is not cover.
##   count          — reported last, because it is the least meaningful of the three.
extends Node
const Sp = preload("res://scripts/spatial.gd")
const Layout = preload("res://scripts/arena_layout.gd")

func _ready() -> void:
	var body_d: float = Sp.BODY_RADIUS * 2.0
	print("body diameter: %.2f   GEOMETRY_SCALE: %.2f" % [body_d, Sp.GEOMETRY_SCALE])
	print("AREA_PER_PIECE: %.0f\n" % Layout.AREA_PER_PIECE)
	print("%-5s %-13s %7s %7s %9s %9s" % ["team", "ground", "pieces", "ceiling", "cover %", "widest/body"])
	for n in [1, 3, 5]:
		var g: Vector2 = Sp.ground_size(n)
		var rng := RandomNumberGenerator.new(); rng.seed = 20260804
		var lay: Dictionary = Layout.generate(n, "Platinum", rng)
		var obs: Array = lay.get("obstacles", [])
		var area := 0.0
		var widest := 0.0
		for o in obs:
			var r: Rect2 = o["rect"]
			area += r.size.x * r.size.y
			widest = maxf(widest, maxf(r.size.x, r.size.y))
		print("%-5d %-13s %7d %7d %8.2f%% %9.2f" % [n, "%dx%d" % [int(g.x), int(g.y)],
			obs.size(), int((g.x * g.y) / Layout.AREA_PER_PIECE),
			100.0 * area / (g.x * g.y), widest / body_d])
	print("\nkind footprints, in BODY DIAMETERS (cover narrower than 1.0 hides nobody):")
	for k in Layout.KIND_TABLE:
		var sz: Vector2 = k["size"]
		print("  %-10s %-9s %5.1f x %-5.1f  ->  %.2f x %.2f bodies" % [
			k["kind"], k["grade"], sz.x, sz.y, sz.x / body_d, sz.y / body_d])
	get_tree().quit()
