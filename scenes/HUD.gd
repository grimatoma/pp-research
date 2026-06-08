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
var _military_panel: PanelContainer
var _military_body: VBoxContainer
var _deploy_camp: OrcCamp = null
var _deploy_spins: Dictionary = {}  ## unit_id -> SpinBox
var _world_panel: PanelContainer
var _world_body: VBoxContainer
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

const CAT_ORDER := ["house", "civic", "food", "raw", "production", "military", "naval", "storage"]
const CAT_TITLE := {
	"house": "Houses", "civic": "Services", "food": "Food",
	"raw": "Raw", "production": "Workshops", "military": "Military",
	"naval": "Naval", "storage": "Storage",
}

func _ready() -> void:
	layer = 10
	_build_top_bar()
	_build_stockpile_panel()
	_build_inspector()
	_build_menu()
	_build_research_panel()
	_build_military_panel()
	_build_world_panel()
	_build_toast()
	Game.sim.economy_ticked.connect(func(_d): _request_refresh())
	Game.sim.notify.connect(_on_notify)
	Game.sim.expedition_resolved.connect(func(_i, _c, _w): _refresh_military())
	Game.sim.expedition_launched.connect(func(_i, _c): _refresh_military())
	Game.sim.world_changed.connect(func(): _refresh_world())
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
	view.camp_selected.connect(_on_camp_selected)

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
	var world_btn := Button.new()
	world_btn.text = "World"
	world_btn.pressed.connect(func():
		_world_panel.visible = not _world_panel.visible
		if _world_panel.visible:
			_refresh_world())
	row.add_child(world_btn)
	var military_btn := Button.new()
	military_btn.text = "Military"
	military_btn.pressed.connect(func():
		_military_panel.visible = not _military_panel.visible
		if _military_panel.visible:
			_deploy_camp = null
			_refresh_military())
	row.add_child(military_btn)
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
		# Military units live in the garrison (Military panel), not the goods stockpile.
		if gd != null and gd.category == "unit":
			continue
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
	var isl := Game.sim.active_island()
	var region: String = isl.region if isl != null else "temperate"
	for cat in CAT_ORDER:
		var in_cat: Array = []
		for b in avail:
			# Region gate: climate-signature buildings only show on their region.
			if b.region != "" and b.region != region:
				continue
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

# ── military panel (garrison · expeditions · conquest) ───────────────────────────

func _build_military_panel() -> void:
	_military_panel = PanelContainer.new()
	_military_panel.anchor_left = 0.5
	_military_panel.anchor_right = 0.5
	_military_panel.anchor_top = 0.0
	_military_panel.offset_top = 56
	_military_panel.offset_left = -230
	_military_panel.offset_right = 230
	_military_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_military_panel.add_theme_stylebox_override("panel", _bg(Color(0.10, 0.10, 0.13, 0.97)))
	_military_panel.visible = false
	add_child(_military_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_military_body = VBoxContainer.new()
	_military_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_military_body)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 10)
	m.add_child(scroll)
	_military_panel.add_child(m)

func open_military() -> void:
	_military_panel.visible = true
	_deploy_camp = null
	_refresh_military()

## Hide all floating panels (used by the screenshot harness and panel toggles).
func close_panels() -> void:
	if _research_panel:
		_research_panel.visible = false
	if _military_panel:
		_military_panel.visible = false
	if _world_panel:
		_world_panel.visible = false

func _on_camp_selected(camp: OrcCamp) -> void:
	_military_panel.visible = true
	_deploy_camp = camp
	_clear_active_build_btn()
	_inspector.visible = false
	_refresh_military()

func _refresh_military() -> void:
	if _military_panel == null or not _military_panel.visible:
		return
	for c in _military_body.get_children():
		c.queue_free()
	var isl := Game.sim.active_island()
	if isl == null:
		return
	_add_label(_military_body, "Military — %s" % isl.island_name, 16)

	# Garrison roster.
	_add_label(_military_body, "Garrison", 13, Color(0.7, 0.78, 0.9))
	var gar := Game.sim.garrison(isl)
	if gar.is_empty():
		_add_label(_military_body, "No troops. Satisfied houses muster Militia over time.",
			11, Color(0.6, 0.65, 0.72))
	else:
		for uid in gar:
			_add_label(_military_body, _unit_line(uid, int(gar[uid])), 12)

	# In-flight expeditions.
	var mine: Array = []
	for e in Game.sim.expeditions:
		if int(e.island_index) == Game.sim.active_index:
			mine.append(e)
	if not mine.is_empty():
		_add_label(_military_body, "Expeditions in progress", 13, Color(0.7, 0.78, 0.9))
		for e in mine:
			var remaining: float = maxf(0.0, float(e.total) - float(e.elapsed))
			var cname := "a camp"
			for c in isl.camps:
				if c.id == int(e.camp_id):
					cname = c.display_name
			_add_label(_military_body, "⚔ %s — %s remaining" % [cname, _fmt_time(remaining)],
				12, Color("e0c060"))

	# Camps to conquer.
	var camps := isl.active_camps()
	_add_label(_military_body, "Orc forts (%d)" % camps.size(), 13, Color(0.7, 0.78, 0.9))
	if camps.is_empty():
		_add_label(_military_body, "This island is pacified.", 11, Color(0.6, 0.8, 0.65))
	for camp in camps:
		_military_body.add_child(_make_camp_row(camp))

	# Deploy interface for the focused camp.
	if _deploy_camp != null and not _deploy_camp.cleared \
			and Game.sim.expedition_for(Game.sim.active_index, _deploy_camp.id).is_empty():
		_military_body.add_child(HSeparator.new())
		_build_deploy_section(_deploy_camp, isl)

func _make_camp_row(camp: OrcCamp) -> Control:
	var box := VBoxContainer.new()
	var title := camp.display_name + (" ☠" if camp.boss != "" else "")
	_add_label(box, title, 13, Color("e08a8a"))
	_add_label(box, "Defenders: " + _army_summary(camp.full_army()), 11, Color(0.8, 0.82, 0.86))
	var busy := not Game.sim.expedition_for(Game.sim.active_index, camp.id).is_empty()
	var btn := Button.new()
	btn.text = "Under attack…" if busy else "Plan attack"
	btn.disabled = busy
	btn.pressed.connect(func():
		_deploy_camp = camp
		_refresh_military())
	box.add_child(btn)
	return box

func _build_deploy_section(camp: OrcCamp, isl: Island) -> void:
	_deploy_spins.clear()
	_add_label(_military_body, "Deploy to %s" % camp.display_name, 14, Color("ffd34a"))
	_add_label(_military_body, "Defenders: " + _army_summary(camp.full_army()), 11,
		Color(0.8, 0.82, 0.86))
	var gar := Game.sim.garrison(isl)
	if gar.is_empty():
		_add_label(_military_body, "No troops to send.", 12, Color("e0913a"))
		return
	for uid in gar:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (have %d)" % [Database.good_name(uid), int(gar[uid])]
		lbl.custom_minimum_size = Vector2(180, 0)
		row.add_child(lbl)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = int(gar[uid])
		spin.value = int(gar[uid])
		spin.custom_minimum_size = Vector2(90, 0)
		row.add_child(spin)
		_deploy_spins[uid] = spin
		_military_body.add_child(row)
	var attack := Button.new()
	attack.text = "⚔ Launch attack (cap %d)" % Game.sim.army_cap()
	attack.pressed.connect(func(): _launch_attack(camp))
	_military_body.add_child(attack)

func _launch_attack(camp: OrcCamp) -> void:
	var army: Dictionary = {}
	for uid in _deploy_spins:
		var n := int((_deploy_spins[uid] as SpinBox).value)
		if n > 0:
			army[uid] = n
	var res := Game.sim.send_expedition(Game.sim.active_index, camp.id, army)
	if not res.ok:
		Game.sim.notify.emit(res.reason, "warn")
	else:
		_deploy_camp = null
		if island_view:
			island_view.queue_redraw()
	_refresh_military()

func _unit_line(uid: String, count: int) -> String:
	var u := Database.unit(uid)
	if u == null:
		return "%s ×%d" % [Database.good_name(uid), count]
	var ab := (" [" + ", ".join(u.abilities) + "]") if not u.abilities.is_empty() else ""
	return "%s ×%d — %d hp / %d atk%s" % [u.display_name, count, u.hp, u.atk, ab]

func _army_summary(army: Dictionary) -> String:
	var parts: Array = []
	for uid in army:
		parts.append("%d %s" % [int(army[uid]), Database.good_name(uid)])
	return ", ".join(parts) if not parts.is_empty() else "—"

func _fmt_time(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %ds" % [s / 60, s % 60]
	return "%ds" % s

# ── world panel (regions · discovery · islands · trade routes) ────────────────────

var _disc_labels: Array = []  ## [{label:Label, disc:Dictionary}] for live countdowns

func _build_world_panel() -> void:
	_world_panel = PanelContainer.new()
	_world_panel.anchor_left = 0.5
	_world_panel.anchor_right = 0.5
	_world_panel.anchor_top = 0.0
	_world_panel.offset_top = 56
	_world_panel.offset_left = -250
	_world_panel.offset_right = 250
	_world_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_world_panel.add_theme_stylebox_override("panel", _bg(Color(0.09, 0.11, 0.13, 0.98)))
	_world_panel.visible = false
	add_child(_world_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_world_body = VBoxContainer.new()
	_world_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_world_body)
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 10)
	m.add_child(scroll)
	_world_panel.add_child(m)

func open_world() -> void:
	_world_panel.visible = true
	_refresh_world()

func _refresh_world() -> void:
	if _world_panel == null or not _world_panel.visible:
		return
	_disc_labels.clear()
	for c in _world_body.get_children():
		c.queue_free()
	var sim := Game.sim
	_add_label(_world_body, "World — %d / %d islands settled" %
		[sim.settled_island_count(), sim.island_limit()], 16)
	_add_label(_world_body, "Regions: " + ", ".join(sim.unlocked_regions), 11,
		Color(0.7, 0.78, 0.9))

	# ── discovery ──
	_add_label(_world_body, "Charter a new island", 13, Color(0.7, 0.78, 0.9))
	var disc_row := HBoxContainer.new()
	var region_opt := OptionButton.new()
	for r in sim.unlocked_regions:
		region_opt.add_item(String(r).capitalize())
		region_opt.set_item_metadata(region_opt.item_count - 1, r)
	disc_row.add_child(region_opt)
	var pts := SpinBox.new()
	pts.min_value = 0
	pts.max_value = max(0, int(sim.currencies.get("cartography", 0.0)))
	pts.prefix = "Carto "
	pts.custom_minimum_size = Vector2(90, 0)
	disc_row.add_child(pts)
	var disc_btn := Button.new()
	disc_btn.text = "Discover"
	disc_btn.pressed.connect(func():
		var region := String(region_opt.get_selected_metadata()) if region_opt.item_count > 0 else "temperate"
		var res := sim.start_discovery(region, int(pts.value))
		if not res.ok:
			sim.notify.emit(res.reason, "warn")
		_refresh_world())
	disc_row.add_child(disc_btn)
	_world_body.add_child(disc_row)
	_add_label(_world_body, "More Cartography → bigger island, longer voyage (+10 min/point).",
		10, Color(0.6, 0.65, 0.72))
	for d in sim.discoveries:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color("e0c060"))
		_world_body.add_child(l)
		_disc_labels.append({"label": l, "disc": d})
	_update_disc_labels()

	# ── islands ──
	_world_body.add_child(HSeparator.new())
	_add_label(_world_body, "Islands", 13, Color(0.7, 0.78, 0.9))
	for i in sim.islands.size():
		_world_body.add_child(_make_island_row(i))

	# ── trade routes ──
	_world_body.add_child(HSeparator.new())
	_add_label(_world_body, "Trade routes (ships move goods, never people)", 13,
		Color(0.7, 0.78, 0.9))
	for ri in sim.trade_routes.size():
		_world_body.add_child(_make_route_row(ri))
	if sim.islands.size() >= 2:
		_world_body.add_child(_make_add_route_row())

func _make_island_row(i: int) -> Control:
	var sim := Game.sim
	var isl: Island = sim.islands[i]
	var box := VBoxContainer.new()
	var status := "home" if i == 0 else ("settled" if isl.settled else "unsettled")
	var hdr := "%s — %s · %s" % [isl.island_name, String(isl.region).capitalize(), status]
	if i == sim.active_index:
		hdr = "▶ " + hdr
	_add_label(box, hdr, 13, Color("d7e0ea") if isl.settled else Color("e0c89a"))
	var forts := isl.active_camps().size()
	if forts > 0:
		_add_label(box, "%d Orc fort(s) to clear" % forts, 11, Color("e08a8a"))
	var btns := HBoxContainer.new()
	if isl.settled or i == 0:
		var view := Button.new()
		view.text = "View"
		view.disabled = (i == sim.active_index)
		view.pressed.connect(func(): _switch_island(i))
		btns.add_child(view)
	if not isl.settled and i != 0:
		if forts == 0:
			var settle := Button.new()
			settle.text = "Settle"
			settle.pressed.connect(func():
				var r := sim.settle_island(i)
				if not r.ok: sim.notify.emit(r.reason, "warn")
				_refresh_world())
			btns.add_child(settle)
			var hand := Button.new()
			var sz: int = maxi(isl.width - 8, 12)
			hand.text = "Hand over (+%d Favor)" % int(Database.favor_for_size(sz))
			hand.pressed.connect(func():
				sim.handover_to_paragons(i)
				_refresh_world())
			btns.add_child(hand)
			var turn := Button.new()
			turn.text = "Turn in (+Coin)"
			turn.pressed.connect(func():
				sim.turn_in_for_coins(i)
				_refresh_world())
			btns.add_child(turn)
		else:
			var go := Button.new()
			go.text = "View & conquer"
			go.pressed.connect(func(): _switch_island(i))
			btns.add_child(go)
	box.add_child(btns)
	return box

func _switch_island(i: int) -> void:
	if i < 0 or i >= Game.sim.islands.size():
		return
	Game.sim.active_index = i
	if island_view:
		island_view._rebake()
	var main := get_parent()
	if main and main.has_method("center_on_active_island"):
		main.center_on_active_island()
	_rebuild_build_menu()
	_refresh_world()
	_refresh()

func _make_route_row(ri: int) -> Control:
	var sim := Game.sim
	var r: Dictionary = sim.trade_routes[ri]
	var row := HBoxContainer.new()
	var fi := int(r.from)
	var ti := int(r.to)
	var fname: String = sim.islands[fi].island_name if fi < sim.islands.size() else "?"
	var tname: String = sim.islands[ti].island_name if ti < sim.islands.size() else "?"
	var lbl := Label.new()
	lbl.text = "%s → %s: %s (%s)" % [fname, tname, Database.good_name(String(r.good)),
		Database.ship(String(r.ship)).display_name if Database.ship(String(r.ship)) else r.ship]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var rm := Button.new()
	rm.text = "✕"
	rm.pressed.connect(func():
		sim.remove_trade_route(ri)
		_refresh_world())
	row.add_child(rm)
	return row

func _make_add_route_row() -> Control:
	var sim := Game.sim
	var box := VBoxContainer.new()
	_add_label(box, "New route", 11, Color(0.7, 0.75, 0.85))
	var row := HBoxContainer.new()
	var from_opt := OptionButton.new()
	var to_opt := OptionButton.new()
	for i in sim.islands.size():
		from_opt.add_item(sim.islands[i].island_name)
		to_opt.add_item(sim.islands[i].island_name)
	if sim.islands.size() >= 2:
		to_opt.select(1)
	row.add_child(from_opt)
	var arrow := Label.new()
	arrow.text = " → "
	row.add_child(arrow)
	row.add_child(to_opt)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	var good_opt := OptionButton.new()
	for g in _tradeable_goods():
		good_opt.add_item(Database.good_name(g))
		good_opt.set_item_metadata(good_opt.item_count - 1, g)
	row2.add_child(good_opt)
	var ship_opt := OptionButton.new()
	for sid in Database.all_ships():
		var s := Database.ship(sid)
		var x := "✚" if s.cross_region else "·"
		ship_opt.add_item("%s %s (%dc)" % [x, s.display_name, s.coin_cost])
		ship_opt.set_item_metadata(ship_opt.item_count - 1, sid)
	row2.add_child(ship_opt)
	var create := Button.new()
	create.text = "Create"
	create.pressed.connect(func():
		var good := String(good_opt.get_selected_metadata())
		var ship := String(ship_opt.get_selected_metadata())
		var res := sim.add_trade_route(from_opt.selected, to_opt.selected, good, ship)
		if not res.ok: sim.notify.emit(res.reason, "warn")
		_refresh_world())
	row2.add_child(create)
	box.add_child(row2)
	return box

## Goods worth shipping: raws, materials, foods, luxuries, tools (not currencies/services/units).
func _tradeable_goods() -> Array:
	var out: Array = []
	for gid in Database.goods:
		var g: GoodDef = Database.goods[gid]
		if g.category in ["currency", "service", "unit"]:
			continue
		out.append(gid)
	out.sort_custom(func(a, b): return Database.good_name(a) < Database.good_name(b))
	return out

func _update_disc_labels() -> void:
	for e in _disc_labels:
		var d: Dictionary = e.disc
		var remaining: float = maxf(0.0, float(d.total) - float(d.elapsed))
		(e.label as Label).text = "⛵ Charting %s — %s remaining" % [
			String(d.region).capitalize(), _fmt_time(remaining)]

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
	if _world_panel and _world_panel.visible:
		_update_disc_labels()
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
	# Skip the periodic military rebuild while the player is setting up a deployment —
	# rebuilding would reset the SpinBoxes mid-interaction. Overview refreshes freely.
	if _deploy_camp == null:
		_refresh_military()

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
