extends CanvasLayer
## The game UI: top resource bar, stockpile panel, categorized build menu, a building
## inspector (with tier-upgrade / demolish), and toast notifications. Reads Game.sim
## and drives placement through the IslandView (wired by Main).

var island_view: Node2D

var _coin_lbl: Label
var _favor_lbl: Label
var _carto_lbl: Label
var _creativity_lbl: Label
var _pop_lbl: Label
var _time_lbl: Label
var _research_panel: PanelContainer
var _research_body: VBoxContainer
var _stock_box: VBoxContainer
var _build_box: HBoxContainer
var _inspector: PanelContainer
var _inspector_body: VBoxContainer
var _toast: Label
var _toast_time := 0.0
var _selected: PlacedBuilding = null
var _active_build_btn: Button = null
var _build_buttons: Dictionary = {}  ## building_id -> Button
var _refresh_accum := 0.0

const CAT_ORDER := ["house", "civic", "food", "raw", "production", "storage"]
const CAT_TITLE := {
	"house": "Houses", "civic": "Services", "food": "Food",
	"raw": "Raw", "production": "Workshops", "storage": "Storage",
}

func _ready() -> void:
	layer = 10
	_build_top_bar()
	_build_stockpile_panel()
	_build_inspector()
	_build_menu()
	_build_research_panel()
	_build_toast()
	Game.sim.economy_ticked.connect(func(_d): _request_refresh())
	Game.sim.notify.connect(_on_notify)
	Game.sim.tier_unlocked.connect(func(_t):
		_rebuild_build_menu()
		_refresh_research())
	Game.sim.research_completed.connect(func(_p):
		_rebuild_build_menu()
		_refresh_research())
	Game.sim.population_changed.connect(func(_a, _b, _c): _request_refresh())
	_refresh()

func bind_island(view: Node2D) -> void:
	island_view = view
	view.building_selected.connect(_on_building_selected)
	view.build_selection_cleared.connect(_clear_active_build_btn)

# ── top bar ──────────────────────────────────────────────────────────────────

func _chip(parent: HBoxContainer, prefix: String) -> Label:
	var l := Label.new()
	l.text = prefix
	l.add_theme_font_size_override("font_size", 18)
	l.custom_minimum_size = Vector2(120, 0)
	parent.add_child(l)
	return l

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.add_theme_stylebox_override("panel", _bg(Color(0.08, 0.09, 0.12, 0.92)))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.add_child(row)
	panel.add_child(m)
	_coin_lbl = _chip(row, "Coin")
	_favor_lbl = _chip(row, "Favor")
	_carto_lbl = _chip(row, "Carto")
	_creativity_lbl = _chip(row, "Creativity")
	_pop_lbl = _chip(row, "Pop")
	_time_lbl = _chip(row, "Day")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var research_btn := Button.new()
	research_btn.text = "Research"
	research_btn.pressed.connect(func():
		_research_panel.visible = not _research_panel.visible
		if _research_panel.visible:
			_refresh_research())
	row.add_child(research_btn)
	var restart := Button.new()
	restart.text = "New Run"
	restart.pressed.connect(func():
		Game.restart()
		_full_reset())
	row.add_child(restart)

# ── stockpile ──────────────────────────────────────────────────────────────────

func _build_stockpile_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -210
	panel.offset_top = 56
	panel.offset_right = -8
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _bg(Color(0.10, 0.11, 0.15, 0.9)))
	add_child(panel)
	var v := VBoxContainer.new()
	var title := Label.new()
	title.text = "Stockpile"
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)
	_stock_box = VBoxContainer.new()
	v.add_child(_stock_box)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.add_child(v)
	panel.add_child(m)

func _refresh_stockpile() -> void:
	for c in _stock_box.get_children():
		c.queue_free()
	var isl := Game.sim.active_island()
	if isl == null:
		return
	var ids := isl.stockpile.keys()
	ids.sort()
	for id in ids:
		var amt: float = isl.qty(id)
		if amt < 0.05:
			continue
		var gd := Database.good(id)
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = gd.color if gd else Color.GRAY
		sw.custom_minimum_size = Vector2(12, 12)
		row.add_child(sw)
		var name_l := Label.new()
		name_l.text = "  " + (gd.display_name if gd else id)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var qty_l := Label.new()
		qty_l.text = str(int(amt))
		row.add_child(qty_l)
		_stock_box.add_child(row)

# ── build menu ──────────────────────────────────────────────────────────────────

func _build_menu() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_right = 1.0
	panel.offset_top = -96
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_theme_stylebox_override("panel", _bg(Color(0.08, 0.09, 0.12, 0.94)))
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_box = HBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_build_box)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 6)
	m.add_child(scroll)
	panel.add_child(m)
	_rebuild_build_menu()

func _rebuild_build_menu() -> void:
	for c in _build_box.get_children():
		c.queue_free()
	_build_buttons.clear()
	var avail := Database.unlocked_buildings(Game.sim.unlocked_tiers)
	for cat in CAT_ORDER:
		var in_cat: Array = []
		for b in avail:
			if b.category == cat:
				in_cat.append(b)
		if in_cat.is_empty():
			continue
		var col := VBoxContainer.new()
		var title := Label.new()
		title.text = CAT_TITLE.get(cat, cat)
		title.add_theme_font_size_override("font_size", 12)
		title.modulate = Color(0.7, 0.75, 0.85)
		col.add_child(title)
		var flow := HBoxContainer.new()
		flow.add_theme_constant_override("separation", 4)
		in_cat.sort_custom(func(a, b): return a.display_name < b.display_name)
		for b in in_cat:
			flow.add_child(_make_build_button(b))
		col.add_child(flow)
		_build_box.add_child(col)
		var sep := VSeparator.new()
		_build_box.add_child(sep)

func _make_build_button(def: BuildingDef) -> Button:
	var btn := Button.new()
	btn.text = def.display_name
	btn.tooltip_text = _build_tooltip(def)
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 30)
	btn.pressed.connect(func(): _arm_build(def, btn))
	_build_buttons[def.id] = btn
	return btn

func _build_tooltip(def: BuildingDef) -> String:
	var s := def.display_name + "\n"
	if not def.cost.is_empty():
		var parts: Array = []
		for g in def.cost:
			parts.append("%d %s" % [int(def.cost[g]), Database.good_name(g)])
		s += "Cost: " + ", ".join(parts) + "\n"
	if def.recipe != null and def.recipe.output != "":
		var r := def.recipe
		var ins: Array = []
		for g in r.inputs:
			ins.append("%s %s" % [_num(r.inputs[g]), Database.good_name(g)])
		var in_s := (", ".join(ins) + " → ") if not ins.is_empty() else ""
		s += "%s%s %s / %ss\n" % [in_s, _num(r.output_qty), Database.good_name(r.output),
			_num(r.iteration_time)]
	if def.is_house:
		var t := Database.tier(def.house_tier)
		if t:
			s += "Holds %d %s\n" % [t.max_residents, t.display_name]
	if def.terrain_req == Constants.Terrain.RIVER:
		s += "Needs a river spot\n"
	elif def.terrain_req == Constants.Terrain.FOREST:
		s += "Build on forest\n"
	elif def.terrain_req == Constants.Terrain.MOUNTAIN:
		s += "Build on a mountain\n"
	elif def.needs_coast:
		s += "Build on the coast\n"
	return s.strip_edges()

func _arm_build(def: BuildingDef, btn: Button) -> void:
	if _active_build_btn != null and _active_build_btn != btn:
		_active_build_btn.button_pressed = false
	_active_build_btn = btn if btn.button_pressed else null
	if island_view:
		island_view.set_build_selection(def.id if btn.button_pressed else "")
	_selected = null
	_inspector.visible = false

func _clear_active_build_btn() -> void:
	if _active_build_btn:
		_active_build_btn.button_pressed = false
		_active_build_btn = null

# ── inspector ──────────────────────────────────────────────────────────────────

func _build_inspector() -> void:
	_inspector = PanelContainer.new()
	_inspector.anchor_top = 0.0
	_inspector.offset_left = 8
	_inspector.offset_top = 56
	_inspector.custom_minimum_size = Vector2(240, 0)
	_inspector.add_theme_stylebox_override("panel", _bg(Color(0.10, 0.11, 0.15, 0.95)))
	_inspector.visible = false
	add_child(_inspector)
	_inspector_body = VBoxContainer.new()
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.add_child(_inspector_body)
	_inspector.add_child(m)

func _on_building_selected(pb: PlacedBuilding) -> void:
	_selected = pb
	if pb == null:
		_inspector.visible = false
		return
	_clear_active_build_btn()
	if island_view:
		island_view.set_build_selection("")
	_inspector.visible = true
	_refresh_inspector()

func _refresh_inspector() -> void:
	if _selected == null or not _inspector.visible:
		return
	for c in _inspector_body.get_children():
		c.queue_free()
	var pb := _selected
	var def := Database.building(pb.building_id)
	if def == null:
		_inspector.visible = false
		return
	_add_label(_inspector_body, def.display_name, 18)
	if not pb.connected and not def.is_storage:
		_add_label(_inspector_body, "⚠ No storage in range", 13, Color("e0593f"))
	if def.is_house:
		var t := Database.tier(pb.tier_id)
		if t == null:
			# House with unknown/empty tier (old or corrupt save) — don't crash; the
			# Demolish button below still lets the player recover the tile.
			_add_label(_inspector_body, "Unknown population tier", 13, Color("e0593f"))
		else:
			_add_label(_inspector_body, "%s — %d / %d residents"
				% [t.display_name, pb.residents, t.max_residents], 14)
			_add_label(_inspector_body, _needs_summary(t), 12, Color(0.8, 0.85, 0.9))
			if Game.sim.can_upgrade(pb):
				var up := Button.new()
				up.text = "Ascend to " + Database.tier(Database.next_tier_id(pb.tier_id)).display_name
				up.pressed.connect(func():
					Game.sim.upgrade_house(pb)
					_refresh_inspector())
				_inspector_body.add_child(up)
			elif Database.next_tier_id(pb.tier_id) != "":
				_add_label(_inspector_body, "Fill all needs at max pop to ascend.", 11,
					Color(0.6, 0.65, 0.72))
	elif def.recipe != null and def.recipe.output != "":
		var r := def.recipe
		_add_label(_inspector_body, "Makes %s" % Database.good_name(r.output), 14)
		var pct := int(clampf(pb.progress / r.iteration_time, 0, 1) * 100)
		_add_label(_inspector_body, "Progress: %d%%   %s" % [pct,
			("active" if pb.active else "idle")], 12, Color(0.8, 0.85, 0.9))
	var demo := Button.new()
	demo.text = "Demolish"
	demo.pressed.connect(func():
		if island_view:
			Game.sim.demolish(pb.origin)
			island_view._rebake()
		_selected = null
		_inspector.visible = false)
	_inspector_body.add_child(demo)

func _needs_summary(tier: PopTierDef) -> String:
	var isl := Game.sim.active_island()
	var parts: Array = []
	for g in tier.all_need_goods():
		var ok := isl.qty(g) > 0.5
		parts.append(("✓" if ok else "✗") + Database.good_name(g))
	return ", ".join(parts)

# ── research panel ──────────────────────────────────────────────────────────────

func _build_research_panel() -> void:
	_research_panel = PanelContainer.new()
	_research_panel.anchor_left = 0.5
	_research_panel.anchor_right = 0.5
	_research_panel.anchor_top = 0.0
	_research_panel.offset_top = 56
	_research_panel.offset_left = -200
	_research_panel.offset_right = 200
	_research_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_research_panel.add_theme_stylebox_override("panel", _bg(Color(0.10, 0.11, 0.15, 0.97)))
	_research_panel.visible = false
	add_child(_research_panel)
	var v := VBoxContainer.new()
	_add_label(v, "Research — spend Creativity on perks", 16)
	_research_body = VBoxContainer.new()
	v.add_child(_research_body)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 10)
	m.add_child(v)
	_research_panel.add_child(m)

## Open the research panel (used by the screenshot harness and could back a hotkey).
func open_research() -> void:
	_research_panel.visible = true
	_refresh_research()

func _refresh_research() -> void:
	if _research_panel == null or not _research_panel.visible:
		return
	for c in _research_body.get_children():
		c.queue_free()
	var by_tree: Dictionary = {}
	for pid in Database.all_research():
		var perk: ResearchDef = Database.research_perk(pid)
		if not Game.sim.research_available(perk):
			continue
		by_tree.get_or_add(perk.tree, []).append(perk)
	var order: Array = []
	order.append_array(Database.all_tiers())
	order.append("infinite")
	for tree in order:
		if not by_tree.has(tree):
			continue
		var title := (Database.tier(tree).display_name if Database.tier(tree) else "Infinite") + " tree"
		_add_label(_research_body, title, 13, Color(0.7, 0.78, 0.9))
		for perk in by_tree[tree]:
			_research_body.add_child(_make_research_row(perk))

func _make_research_row(perk: ResearchDef) -> Control:
	var row := HBoxContainer.new()
	var info := Label.new()
	var rank := Game.sim.research_rank(perk.id)
	var rank_s := (" (rank %d)" % rank) if perk.repeatable and rank > 0 else ""
	info.text = "%s%s — %s" % [perk.display_name, rank_s, perk.description]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var btn := Button.new()
	var cost := Game.sim.research_cost(perk)
	btn.text = "%d ◆" % cost
	btn.disabled = not Game.sim.can_research(perk)
	btn.pressed.connect(func():
		if Game.sim.research(perk):
			_refresh_research()
			_refresh())
	row.add_child(btn)
	return row

# ── toast / refresh / helpers ───────────────────────────────────────────────────

func _build_toast() -> void:
	_toast = Label.new()
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.0
	_toast.offset_top = 64
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.modulate.a = 0.0
	add_child(_toast)

func _on_notify(text: String, level: String) -> void:
	_toast.text = text
	match level:
		"good": _toast.add_theme_color_override("font_color", Color("7bd88f"))
		"warn": _toast.add_theme_color_override("font_color", Color("e0913a"))
		_: _toast.add_theme_color_override("font_color", Color("e8e8e8"))
	_toast.modulate.a = 1.0
	_toast_time = 4.0

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.6:
			_toast.modulate.a = maxf(0.0, _toast_time / 0.6)
	_refresh_accum += delta
	if _refresh_accum >= 0.25:
		_refresh_accum = 0.0
		_refresh()

func _request_refresh() -> void:
	pass  # actual refresh paced in _process

func _refresh() -> void:
	_coin_lbl.text = "Coin %d" % int(Game.sim.coin())
	_favor_lbl.text = "Favor %d" % int(Game.sim.currencies.get("favor", 0))
	_carto_lbl.text = "Carto %d" % int(Game.sim.currencies.get("cartography", 0))
	_creativity_lbl.text = "Creativity %d" % int(Game.sim.creativity)
	_pop_lbl.text = "Pop %d" % Game.sim.total_population()
	_time_lbl.text = "Day %d" % (int(Game.sim.elapsed / 120.0) + 1)
	_refresh_stockpile()
	_refresh_build_affordability()
	_refresh_inspector()
	_refresh_research()

func _refresh_build_affordability() -> void:
	for id in _build_buttons:
		var def := Database.building(id)
		var btn: Button = _build_buttons[id]
		btn.disabled = not Game.sim.can_afford(def)

func _full_reset() -> void:
	if island_view and island_view.has_method("_rebake"):
		island_view._rebake()
	_clear_active_build_btn()
	_selected = null
	_inspector.visible = false
	_rebuild_build_menu()
	_refresh()

func _add_label(parent: Control, text: String, size: int, col := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(224, 0)
	if col != Color.WHITE:
		l.add_theme_color_override("font_color", col)
	parent.add_child(l)

## Format a quantity without trailing zeros (Godot's % has no %g).
func _num(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, floor(x)) else ("%.1f" % x)

func _bg(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb
