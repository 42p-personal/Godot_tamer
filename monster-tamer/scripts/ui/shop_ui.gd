## THE RANCH SHOP — where gold turns back into capability.
##
## ⚠️ WITHOUT THIS THE ECONOMY HAS NO SINK BUT FOOD, so gold accumulates into meaninglessness and
## the barn stays at two forever. Every purchase here is permanent and changes what the player can
## DO, which is what makes winning a purse matter.
##
## ⚠️ THE LICENCE RANK GATE IS REAL, NOT COPY. `town.ts:22` records that the shop once *said*
## "Requires Silver league" while nothing checked it, so a Wood player with the gold walked
## straight into Draconics. **Reaching the league IS the cost; gold is only the receipt** — so
## both are enforced here, and a locked row states which of the two is missing.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Barn upgrades — price climbs steeply. ⚠️ PROPOSED, NOT BALANCED (`CLAUDE.md`: the baseline is
## suspended for the rebuild). The SHAPE is the intent: room 3 is affordable off a couple of
## purses, room 5 is a campaign goal.
## ⚠️ THE BARN USED TO STOP EXACTLY AT THE TEAM SIZE, AND THAT LOCKED OUT THE ENTIRE META-GAME.
## `TEAM_SIZE_BY_LEAGUE` reaches 5 at Platinum and stays there to Tamers Apex, and `MAX_BARN` was
## also 5 — so from Platinum onward every stall in the stable is a STARTER. There is no room to
## raise a foal, no room to bring a young monster on behind an ageing one, and no room to hold a
## bred child at all. Measured through `_probe_career_arc.tscn`: a full winning career bred ZERO
## times, and section 4 (THE GYM) shows why that is fatal rather than merely a shame — one
## perfectly-drilled monster RETIRES before filling the Platinum cap of 900. Above Gold the ladder
## is mathematically gated on the potential multiplier that only breeding provides, and the barn
## made breeding impossible in precisely those leagues. CLAUDE.md: "the ranch is not a frame
## around the battles — it is how you build the answer you will need."
##
## Two more stalls, priced steeply so a deep bench is a real investment rather than a default.
##
## ⚠️ THE CAP WAS RAISED TO 7 FOR THE REASON ABOVE AND THE PRICE WAS LEFT ALONE, WHICH MEANT THE
## ROOM EXISTED AND NOBODY COULD EVER BUY IT. Measured on the old table: housing a Platinum team
## (capacity 5) cost 320+700+1400+2600 = 5,020g cumulative and a bench on top 9,220g, against a
## career GROSS income of ~20,875g at 43g/week and a measured PEAK liquidity of 1,465g — a 3.4x
## shortfall. Two independent instruments caught it from opposite ends: `_probe_gold_wall.gd`'s
## succession row fired ZERO times on 5/5 seeds and its canary voided the row, and
## `_probe_breed.gd` §4's nursery hook ran 350-441 weeks per seed and bought nothing on 337-428
## of them for want of gold. That single price simultaneously disabled the bench, succession AND
## breeding — `_try_breed` refuses when `monsters.size() >= barn_capacity`, and the barn was only
## ever grown TO the fielded team size. 0 breeds in every arc ever run was the correct play.
##
## THE RULE THE NEW TABLE IS BUILT TO: slot N costs no more than ~1.5x the full purse of the
## league that first REQUIRES N bodies. Platinum first requires 5 and pays 220 + 140x7 = 1,200g,
## so slot 5 is 700g and slot 6 — the bench that makes succession and breeding possible at all —
## is 1,300g. Cumulative to 6 is 2,500g against the old 9,220g. The SHAPE is unchanged: still
## steeply climbing, still a campaign goal, now inside one career's means.
const BARN_PRICES := [0, 0, 150, 350, 700, 1300, 2200, 3200]
const MAX_BARN := 7

var _box: VBoxContainer
var _header: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var backdrop := TextureRect.new()
	var tex: Texture2D = Art.area_texture("shop")
	if tex != null:
		backdrop.texture = tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # ⚠️ default KEEP_SIZE ignores `size`
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.anchor_right = 1; backdrop.anchor_bottom = 1
		backdrop.modulate = Color(1, 1, 1, 0.30)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(page)

	page.add_child(UiTheme.heading("The Ranch Shop", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)
	page.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	page.add_child(back)


func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()
	_header.text = "%d gold · barn holds %d · %s league" % [
		Career.gold, Career.barn_capacity, Career.current_league_name()]

	_box.add_child(_barn_card())
	_box.add_child(_barn_ladder())
	_box.add_child(_licence_card("Special License", 800, 4,
		"Draconic and Abyssal bloodlines appear at the Market."))
	_box.add_child(_licence_card("Elite License", 2000, 6,
		"Mythical bloodlines appear at the Market."))
	_box.add_child(_sinks_card())


func _barn_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("Barn extension", 3))
	col.add_child(UiTheme.body_text(
		"Room for one more monster. ⚠️ Team leagues need bodies — Bronze fields 3, Platinum fields 5, and a cup you cannot field a team for is a cup you cannot enter.",
		"secondary"))

	var cur: int = Career.barn_capacity
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL

	if cur >= MAX_BARN:
		btn.disabled = true
		btn.text = "Barn is at its largest (%d)" % MAX_BARN
	else:
		var price: int = BARN_PRICES[cur + 1] if cur + 1 < BARN_PRICES.size() else 9999
		if Career.gold < price:
			btn.disabled = true
			btn.text = "Extend to %d — %dg (need %d more)" % [cur + 1, price, price - Career.gold]
		else:
			btn.text = "Extend to %d — %dg" % [cur + 1, price]
			btn.pressed.connect(func():
				if Career.spend_gold(price):
					Career.barn_capacity += 1
					_refresh())
	col.add_child(btn)
	return panel


## ── WHAT GOLD IS FOR, ACROSS THE WHOLE CLIMB ──────────────────────────────────────────────────
## ⚠️ THE ONLY OUTLET THE ECONOMY HAS READ AS A SETTINGS PAGE: three rows, then 55% empty screen
## (measured, round 18's before-capture). The player could see the one purchase they can afford
## this week and had no way to learn what 2,200g or 9,000g eventually buys — so gold had no
## destination, and a purse won at Bronze meant nothing beyond the next barn slot.
##
## ⚠️ EVERY NUMBER IS READ, NOT RESTATED. Prices come from this file's own `BARN_PRICES`, the team
## requirement from `Career.team_size_for_league()`, and the two off-screen sinks from the const
## that actually charges them (`breeding_ui.gd:BREED_COST`, `lab_ui.gd:FUSION_COST`,
## `week_plan.gd:RENTAL_PER_FROZEN`). A shop that quotes a price the paying screen disagrees with
## is exactly the failure this project has already shipped twice.
const BreedingLib = preload("res://scripts/ui/breeding_ui.gd")
const LabLib = preload("res://scripts/ui/lab_ui.gd")


## ⚠️ A TABLE CELL MUST NOT WORD-WRAP, AND THIS IS THE SECOND TIME IT BIT THIS ROUND.
## `UiTheme.body_text` sets `AUTOWRAP_WORD_SMART`, which is right for a paragraph and catastrophic
## in a `GridContainer`: a wrapping label's minimum width is one character, so every column
## collapsed to a few pixels and the table rendered as four overlapping vertical strips of single
## words. Every mechanical check passed on that frame — the probe counts controls, not legibility —
## and it was caught only by reading the capture back. Wrap off, explicit floor, always.
func _cell(text: String, tier: String, width: int) -> Control:
	var l := UiTheme.body_text(text, tier)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(width, 0)
	return l


## The first league that FIELDS `n` bodies — so a barn rung can name what it is for, rather than
## being a number that climbs for its own sake.
func _first_league_needing(n: int) -> String:
	for i in range(Career.leagues.size()):
		if Career.team_size_for_league(i) >= n:
			return str(Career.league_at(i).get("name", "?"))
	return ""


func _barn_ladder() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	col.add_child(UiTheme.heading("The barn, all the way up", 3))
	col.add_child(UiTheme.body_text(
		"Every stall you will ever buy, and what each one is for. A stall is not only a body — a foal, a fusion and a bought recruit all need somewhere to land, so the barn is what gates the whole generational half of the game.",
		"secondary"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_XL)
	grid.add_theme_constant_override("v_separation", 2)
	var widths := [90, 90, 110, 420]
	var heads := ["stall", "price", "cumulative", "what it unlocks"]
	for i in range(heads.size()):
		grid.add_child(_cell(heads[i], "muted", widths[i]))

	var cum := 0
	for n in range(3, MAX_BARN + 1):
		var price: int = BARN_PRICES[n] if n < BARN_PRICES.size() else 0
		cum += price
		var have: bool = Career.barn_capacity >= n
		var tier := "muted" if have else ("primary" if n == Career.barn_capacity + 1 else "secondary")
		var mark := "✓ " if have else ""
		grid.add_child(_cell("%s%d" % [mark, n], tier, widths[0]))
		grid.add_child(_cell("%dg" % price, tier, widths[1]))
		grid.add_child(_cell("%dg" % cum, tier, widths[2]))
		var need: String = _first_league_needing(n)
		var what: String = ("fields a %s team" % need) if need != "" else "bench — a foal, a fusion, or a successor behind an ageing champion"
		grid.add_child(_cell(what, tier, widths[3]))
	col.add_child(grid)
	return panel


func _sinks_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	col.add_child(UiTheme.heading("Gold also goes here — and not at this counter", 3))
	col.add_child(UiTheme.body_text(
		"The Shop is not the only thing competing for a purse. These are priced elsewhere and are listed here because a player budgeting for a barn slot is budgeting against them.",
		"secondary"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_XL)
	grid.add_theme_constant_override("v_separation", 2)
	var widths := [220, 380, 150]
	var heads := ["", "price", "where"]
	for i in range(heads.size()):
		grid.add_child(_cell(heads[i], "muted", widths[i]))
	var rows := [
		["Breed a foal", "%dg once" % BreedingLib.BREED_COST, "Breeding Ranch"],
		["Forge a fusion", "%dg once, both parents consumed" % LabLib.FUSION_COST, "Lab"],
		["Keep a body thawable", "%dg every week, forever" % int(WeekPlan.RENTAL_PER_FROZEN), "Lab"],
		["Feed the stable", "10g plain, 75–500g for the training and premium foods", "Stable"],
	]
	for r in rows:
		grid.add_child(_cell(str(r[0]), "primary", widths[0]))
		grid.add_child(_cell(str(r[1]), "secondary", widths[1]))
		grid.add_child(_cell(str(r[2]), "muted", widths[2]))
	col.add_child(grid)
	return panel


## ⚠️ TWO gates, and the button must name the one that is actually blocking. Saying "requires
## Silver" to a player who HAS Silver but lacks the gold is the same failure as not checking at all.
func _licence_card(label: String, price: int, league_req: int, effect: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading(label, 3))
	col.add_child(UiTheme.body_text(effect, "secondary"))

	var req_name: String = Career.league_at(league_req).get("name", "?")
	# ⚠️ NOT `Career.get_meta(label)`. Godot refuses a metadata identifier containing a space, so
	# `set_meta("Special License", true)` failed silently: the licence never registered, the button
	# never flipped to "✓ Held", and the player could buy the same licence repeatedly, losing 800g
	# (or 2000g) each time. `Career.licences` is a real field — see `career.gd:holds_licence()`.
	var owned: bool = Career.holds_licence(label)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL

	if owned:
		btn.disabled = true
		btn.text = "✓ Held"
	elif Career.league_index < league_req:
		btn.disabled = true
		btn.text = "Locked — reach %s league (you are %s)" % [req_name, Career.current_league_name()]
		var note := UiTheme.body_text(
			"Reaching the league IS the cost. The gold is only the receipt.", "muted")
		col.add_child(note)
	elif Career.gold < price:
		btn.disabled = true
		btn.text = "%dg — need %d more" % [price, price - Career.gold]
	else:
		btn.text = "Buy — %dg" % price
		btn.pressed.connect(func():
			if Career.spend_gold(price):
				Career.grant_licence(label)
				_refresh())
	col.add_child(btn)
	return panel
