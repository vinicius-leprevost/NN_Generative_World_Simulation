class_name UIManager extends CanvasLayer
const Animal = preload("res://scripts/agents/animal.gd")
const Building = preload("res://scripts/world/building.gd")
const BuildingDB = preload("res://scripts/data/building_db.gd")
const ConstructionSite = preload("res://scripts/world/construction_site.gd")
const Person = preload("res://scripts/agents/person.gd")
const SpeciesDB = preload("res://scripts/data/species_db.gd")

## UIManager: builds the whole interface in code — top HUD bar, God control
## panel (tabs auto-generated from Params), dashboard, event log, inspector.

var top_bar: PanelContainer
var pause_btn: Button
var speed_label: Label
var time_label: Label
var weather_label: Label
var god_panel: PanelContainer
var event_panel: PanelContainer
var event_list: ItemList
var event_filter: OptionButton
var inspector: PanelContainer
var inspector_title: Label
var inspector_text: RichTextLabel
var inspector_buttons: HFlowContainer
var dashboard_rtl: RichTextLabel
var dashboard_scroll: ScrollContainer
var government_rtl: RichTextLabel
var government_scroll: ScrollContainer
var hint_label: Label
var toast_label: Label
var perf_label: Label

var _param_rows: Dictionary = {}   # key -> {"slider": HSlider, "value": Label}
var _dash_timer := 0.0
var _insp_timer := 0.0
var _toast_timer := 0.0

func build() -> void:
	_build_top_bar()
	_build_god_panel()
	_build_event_panel()
	_build_inspector()
	_build_overlay_labels()
	Events.logged.connect(_on_event)
	Params.param_changed.connect(_on_param_changed)

# ---------------- Top bar ----------------

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)
	var box := HBoxContainer.new()
	top_bar.add_child(box)
	pause_btn = _btn(box, "Pause", func(): _toggle_pause())
	_btn(box, "Step", func(): G.clock.request_step())
	_btn(box, "  -  ", func(): Params.set_p("sim.speed", Params.get_p("sim.speed") * 0.5))
	speed_label = _lbl(box, "x1.0")
	_btn(box, "  +  ", func(): Params.set_p("sim.speed", Params.get_p("sim.speed") * 2.0))
	box.add_child(VSeparator.new())
	time_label = _lbl(box, "")
	weather_label = _lbl(box, "")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var preset := OptionButton.new()
	for p in ["Low", "Medium", "High", "Sim-heavy", "Visual-heavy"]:
		preset.add_item(p)
	preset.select(1)
	preset.item_selected.connect(func(i): G.main.apply_preset(preset.get_item_text(i)))
	box.add_child(preset)
	_btn(box, "God Panel (G)", func(): god_panel.visible = not god_panel.visible)
	_btn(box, "Events (L)", func(): event_panel.visible = not event_panel.visible)
	_btn(box, "Debug (F3)", func(): G.dbg.toggle())
	_btn(box, "Save (F5)", func(): _save(1))
	_btn(box, "Load (F9)", func(): _load(1))

func _toggle_pause() -> void:
	G.clock.paused = not G.clock.paused
	pause_btn.text = "Resume" if G.clock.paused else "Pause"

func _save(slot: int) -> void:
	if SaveMgr.save_slot(slot):
		toast("Saved to slot %d" % slot)
	else:
		toast("Save failed")

func _load(slot: int) -> void:
	if SaveMgr.load_slot(slot):
		toast("Loaded slot %d" % slot)
	else:
		toast("Load failed (no save in slot %d?)" % slot)

# ---------------- God panel ----------------

func _build_god_panel() -> void:
	god_panel = PanelContainer.new()
	god_panel.anchor_top = 0.0
	god_panel.anchor_bottom = 1.0
	god_panel.offset_top = 40.0
	god_panel.offset_bottom = 0.0
	god_panel.custom_minimum_size.x = 400.0
	add_child(god_panel)
	var vbox := VBoxContainer.new()
	god_panel.add_child(vbox)
	var title := Label.new()
	title.text = "  GOD CONTROL PANEL"
	vbox.add_child(title)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	tabs.add_child(_build_actions_tab())
	for tab_name in Params.tabs():
		tabs.add_child(_build_param_tab(tab_name))
	tabs.add_child(_build_government_tab())
	tabs.add_child(_build_dashboard_tab())

func _scroll_vbox(tab_title: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = tab_title
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return [sc, vb]

func _build_param_tab(tab_name: String) -> Control:
	var pair := _scroll_vbox(tab_name)
	var vb: VBoxContainer = pair[1]
	for def in Params.defs_for_tab(tab_name):
		var row := HBoxContainer.new()
		vb.add_child(row)
		var lbl := Label.new()
		lbl.text = def["label"]
		lbl.custom_minimum_size.x = 175.0
		lbl.clip_text = true
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = def["min"]
		slider.max_value = def["max"]
		slider.step = def["step"]
		slider.value = Params.get_p(def["key"])
		slider.custom_minimum_size.x = 130.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var val := Label.new()
		val.text = _fmt(Params.get_p(def["key"]))
		val.custom_minimum_size.x = 46.0
		row.add_child(val)
		var key: String = def["key"]
		slider.value_changed.connect(func(v): Params.set_p(key, v))
		_param_rows[key] = {"slider": slider, "value": val}
	return pair[0]

func _fmt(v: float) -> String:
	if absf(v - roundf(v)) < 0.001 and absf(v) >= 10.0:
		return str(int(v))
	return "%.2f" % v

func _on_param_changed(key: String, value: float) -> void:
	var row = _param_rows.get(key)
	if row == null:
		return
	if absf(row["slider"].value - value) > 0.0001:
		row["slider"].set_value_no_signal(value)
	row["value"].text = _fmt(value)

func _build_actions_tab() -> Control:
	var pair := _scroll_vbox("Actions")
	var vb: VBoxContainer = pair[1]

	_section(vb, "Simulation")
	var g1 := _grid(vb)
	_btn(g1, "New World", func(): G.main.new_world(); toast("A new world begins"))
	_btn(g1, "Reset Params", func(): Params.reset_defaults(); toast("Parameters reset"))
	var g1b := _grid(vb)
	for i in [1, 2, 3]:
		var slot: int = i
		_btn(g1b, "Save %d" % i, func(): _save(slot))
		_btn(g1b, "Load %d" % i, func(): _load(slot))
	_btn(g1b, "Load Autosave", func(): _load(0))

	_section(vb, "Spawn People")
	var g2 := _grid(vb)
	_btn(g2, "Spawn Person", func(): G.god.begin("spawn_person"))
	_btn(g2, "Remove Tool", func(): G.god.begin("remove"))

	_section(vb, "Spawn Animals")
	var species_opt := OptionButton.new()
	for s in SpeciesDB.species_list():
		species_opt.add_item(s)
	vb.add_child(species_opt)
	var g3 := _grid(vb)
	_btn(g3, "Spawn Animal", func(): G.god.begin("spawn_animal", species_opt.get_item_text(species_opt.selected)))

	_section(vb, "Buildings")
	var btype_opt := OptionButton.new()
	for t in BuildingDB.types():
		btype_opt.add_item(t)
	vb.add_child(btype_opt)
	var g4 := _grid(vb)
	_btn(g4, "Place Instantly", func(): G.god.begin("building", btype_opt.get_item_text(btype_opt.selected)))
	_btn(g4, "Construction Site", func(): G.god.begin("site", btype_opt.get_item_text(btype_opt.selected)))

	_section(vb, "Infrastructure & Nature")
	var g5 := _grid(vb)
	_btn(g5, "Road (2 clicks)", func(): G.god.begin("road"))
	_btn(g5, "River (2 clicks)", func(): G.god.begin("river"))
	_btn(g5, "Lake", func(): G.god.begin("lake"))
	_btn(g5, "Food Resource", func(): G.god.begin("resource"))

	_section(vb, "Zones")
	var zone_opt := OptionButton.new()
	for z in ["predator", "livestock", "hunting", "restricted", "crime", "community"]:
		zone_opt.add_item(z)
	vb.add_child(zone_opt)
	var g6 := _grid(vb)
	_btn(g6, "Place Zone", func(): G.god.begin("zone", zone_opt.get_item_text(zone_opt.selected)))
	_btn(g6, "Remove Zone", func(): G.god.begin("remove"))

	_section(vb, "Time")
	var g7 := _grid(vb)
	_btn(g7, "Dawn", func(): G.god.god_set_hour(6.0))
	_btn(g7, "Noon", func(): G.god.god_set_hour(12.0))
	_btn(g7, "Dusk", func(): G.god.god_set_hour(20.0))
	_btn(g7, "Midnight", func(): G.god.god_set_hour(0.0))

	_section(vb, "Weather & Disasters")
	var g8 := _grid(vb)
	_btn(g8, "Clear", func(): G.god.god_weather("clear"))
	_btn(g8, "Rain", func(): G.god.god_weather("rain"))
	_btn(g8, "Storm", func(): G.god.god_weather("storm"))
	_btn(g8, "Drought", func(): G.weather.start_disaster("drought"))
	_btn(g8, "Flood", func(): G.weather.start_disaster("flood"))
	_btn(g8, "Stop Disaster", func(): G.weather.stop_disaster())
	return pair[0]

func _build_dashboard_tab() -> Control:
	var pair := _scroll_vbox("Dashboard")
	dashboard_scroll = pair[0]
	dashboard_rtl = RichTextLabel.new()
	dashboard_rtl.bbcode_enabled = true
	dashboard_rtl.fit_content = true
	dashboard_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dashboard_rtl.custom_minimum_size = Vector2(370, 400)
	pair[1].add_child(dashboard_rtl)
	return pair[0]

func _build_government_tab() -> Control:
	var pair := _scroll_vbox("Government")
	government_scroll = pair[0]
	government_rtl = RichTextLabel.new()
	government_rtl.bbcode_enabled = true
	government_rtl.fit_content = true
	government_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	government_rtl.custom_minimum_size = Vector2(370, 400)
	pair[1].add_child(government_rtl)
	return pair[0]

func _refresh_dashboard() -> void:
	var snap: Dictionary = G.stats.snapshot()
	var txt := ""
	for section in snap.keys():
		txt += "[b][color=#ffd870]%s[/color][/b]\n" % section.to_upper()
		var data: Dictionary = snap[section]
		for k in data.keys():
			txt += "  %s: [color=#bfe3ff]%s[/color]\n" % [k, str(data[k])]
		txt += "\n"
	dashboard_rtl.text = txt

func _refresh_government() -> void:
	var report: Dictionary = G.politics.government_report()
	var txt := ""
	txt += "[b][color=#ffd870]GOVERNMENT REPORT[/color][/b]\n"
	for k in report.keys():
		txt += "  %s: [color=#bfe3ff]%s[/color]\n" % [k, str(report[k])]
	government_rtl.text = txt

# ---------------- Event log ----------------

func _build_event_panel() -> void:
	event_panel = PanelContainer.new()
	event_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	event_panel.offset_left = -460.0
	event_panel.offset_top = -300.0
	event_panel.offset_right = -4.0
	event_panel.offset_bottom = -4.0
	add_child(event_panel)
	var vb := VBoxContainer.new()
	event_panel.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	_lbl(head, "Event Log  ")
	event_filter = OptionButton.new()
	event_filter.add_item("all")
	for t in Events.TYPES:
		event_filter.add_item(t)
	event_filter.item_selected.connect(func(_i): _rebuild_events())
	head.add_child(event_filter)
	event_list = ItemList.new()
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_list.custom_minimum_size = Vector2(440, 240)
	vb.add_child(event_list)
	# events arriving while hidden are skipped — refresh when shown again
	event_panel.visibility_changed.connect(_on_event_panel_visibility)

func _on_event_panel_visibility() -> void:
	if event_panel.visible:
		_rebuild_events()

func _current_filter() -> String:
	return event_filter.get_item_text(event_filter.selected)

func _on_event(evt: Dictionary) -> void:
	if not event_panel.visible:
		return
	var f := _current_filter()
	if f != "all" and evt["type"] != f:
		return
	event_list.add_item("[D%d %s] (%s) %s" % [evt["day"], evt["time"], evt["type"], evt["text"]])
	if event_list.item_count > 200:
		event_list.remove_item(0)
	event_list.ensure_current_is_visible()

func _rebuild_events() -> void:
	event_list.clear()
	var f := _current_filter()
	var shown := 0
	for i in range(Events.entries.size() - 1, -1, -1):
		var evt: Dictionary = Events.entries[i]
		if f != "all" and evt["type"] != f:
			continue
		event_list.add_item("[D%d %s] (%s) %s" % [evt["day"], evt["time"], evt["type"], evt["text"]])
		event_list.move_item(event_list.item_count - 1, 0)
		shown += 1
		if shown >= 200:
			break

# ---------------- Inspector ----------------

func _build_inspector() -> void:
	inspector = PanelContainer.new()
	inspector.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inspector.offset_left = -340.0
	inspector.offset_top = 44.0
	inspector.offset_right = -4.0
	inspector.offset_bottom = 520.0
	inspector.visible = false
	add_child(inspector)
	var vb := VBoxContainer.new()
	inspector.add_child(vb)
	inspector_title = Label.new()
	vb.add_child(inspector_title)
	inspector_text = RichTextLabel.new()
	inspector_text.bbcode_enabled = true
	inspector_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_text.custom_minimum_size = Vector2(320, 330)
	vb.add_child(inspector_text)
	inspector_buttons = HFlowContainer.new()
	vb.add_child(inspector_buttons)

func show_inspector(obj) -> void:
	inspector.visible = obj != null
	for c in inspector_buttons.get_children():
		c.queue_free()
	if obj == null:
		return
	_refresh_inspector()
	if obj is Person:
		var p: Person = obj
		_btn(inspector_buttons, "Kill", func(): G.god.god_kill(p); _refresh_inspector())
		_btn(inspector_buttons, "Revive", func(): G.god.god_revive(p); _refresh_inspector())
		_btn(inspector_buttons, "Heal", func(): G.god.god_heal(p); _refresh_inspector())
		_btn(inspector_buttons, "Sicken", func(): G.god.god_sicken(p); _refresh_inspector())
		_btn(inspector_buttons, "+$100", func(): G.god.god_money(p, 100.0); _refresh_inspector())
		_btn(inspector_buttons, "-$100", func(): G.god.god_money(p, -100.0); _refresh_inspector())
		_btn(inspector_buttons, "+Aggr", func(): G.god.god_set_trait(p, "aggression", p.traits["aggression"] + 0.2); _refresh_inspector())
		_btn(inspector_buttons, "+Empathy", func(): G.god.god_set_trait(p, "empathy", p.traits["empathy"] + 0.2); _refresh_inspector())
	elif obj is Animal:
		var a: Animal = obj
		_btn(inspector_buttons, "Kill", func(): G.animals.kill(a.id, "god"); _refresh_inspector())
		_btn(inspector_buttons, "Tame", func(): G.god.god_tame(a); _refresh_inspector())
		_btn(inspector_buttons, "Make Wild", func(): G.god.god_wild(a); _refresh_inspector())
		_btn(inspector_buttons, "Feed", func(): G.god.god_feed_animal(a); _refresh_inspector())
		_btn(inspector_buttons, "+Aggr", func(): a.aggression = clampf(a.aggression + 0.2, 0.0, 1.0); _refresh_inspector())
	elif obj is Building:
		var b: Building = obj
		_btn(inspector_buttons, "Demolish", func(): G.buildings.demolish(b.id); G.main.select(null))
		_btn(inspector_buttons, "+10 Food", func(): b.stock["food"] += 10.0; _refresh_inspector())
	elif obj is ConstructionSite:
		var s: ConstructionSite = obj
		_btn(inspector_buttons, "+50% Progress", func(): s.progress += s.work_required * 0.5; _refresh_inspector())
		_btn(inspector_buttons, "Cancel", func(): G.buildings.cancel_site(s.id); G.main.select(null))
	_btn(inspector_buttons, "Close", func(): G.main.select(null))

func _refresh_inspector() -> void:
	var obj = G.main.selected
	if obj == null or not is_instance_valid(obj):
		inspector.visible = false
		return
	if obj is Person:
		var p: Person = obj
		inspector_title.text = "PERSON — %s (#%d)" % [p.pname, p.id]
		var t := ""
		t += "[b]%s[/b], %s, age %.1f (%s)\n" % [p.pname, "female" if p.sex == "f" else "male", p.age, p.stage()]
		t += "status: %s%s\n" % ["ALIVE" if p.alive else "DEAD (%s)" % p.cause_of_death, " · IN PRISON" if p.prison_until >= 0.0 else ""]
		t += "action: [color=#ffd870]%s[/color]  emotion: %s\n" % [p.action, p.emotion]
		t += "health %.0f · hunger %.0f · thirst %.0f · energy %.0f\n" % [p.health, p.hunger, p.thirst, p.energy]
		t += "money %.1f · education %.0f · crimes %d\n" % [p.money, p.education, p.crimes_committed]
		t += "pocket: food %.0f/%.0f · water %.0f/%.0f\n" % [p.pocket_food, p.pocket_food_max(),
			p.pocket_water, p.pocket_water_max()]
		t += "job: %s · home: %s · car: %s\n" % [p.job_type if p.job_type != "" else "none",
			str(p.home_id) if p.home_id >= 0 else "none", "yes" if p.car_id >= 0 else "no"]
		t += "partner: %s · children: %d · family: %s\n" % [_pname(p.partner_id), p.child_ids.size(),
			str(p.family_id) if p.family_id >= 0 else "none"]
		t += "\n[b]Traits[/b]\n"
		for k in p.traits.keys():
			t += "  %s: %.2f\n" % [k, p.traits[k]]
		t += "\n[b]Top skills[/b]\n"
		var skill_keys: Array = p.skills.keys()
		skill_keys.sort_custom(func(a, b): return p.skills[a] > p.skills[b])
		for k in skill_keys.slice(0, 4):
			t += "  %s: %.2f\n" % [k, p.skills[k]]
		t += "\n[b]Memory[/b]: %d food, %d water, %d danger spots\n" % [
			p.memory["food"].size(), p.memory["water"].size(), p.memory["danger"].size()]
		t += "[b]Language[/b]: %d known sounds (dialect %d)\n" % [p.lexicon.size(), G.language.dialect_of(p)]
		var shown := 0
		for sym in p.lexicon.keys():
			t += "  '%s' = %s (%.0f%%)\n" % [sym, p.lexicon[sym]["m"], p.lexicon[sym]["c"] * 100.0]
			shown += 1
			if shown >= 6:
				break
		t += "\n[b]Brain[/b] (generation %d)\n" % p.brain.generation
		var wk: Array = p.brain.w.keys()
		wk.sort_custom(func(a, b): return p.brain.w[a] > p.brain.w[b])
		t += "top habits:\n"
		for k in wk.slice(0, 5):
			t += "  %s: %.2f\n" % [k, p.brain.w[k]]
		t += "net bias (current):\n"
		var hb: PackedFloat32Array = p.brain._last_h
		if hb.size() > 0:
			var nk: Array = p.brain.w_out.keys()
			nk.sort_custom(func(a, b): return p.brain._net_out(a, hb) > p.brain._net_out(b, hb))
			for k in nk.slice(0, 3):
				t += "  %s: %+.2f\n" % [k, p.brain._net_out(k, hb)]
		else:
			t += "  (no decision yet)\n"
		inspector_text.text = t
	elif obj is Animal:
		var a: Animal = obj
		inspector_title.text = "ANIMAL — %s (#%d)" % [a.species, a.id]
		var t2 := ""
		t2 += "[b]%s[/b]%s, age %.1f / %.1f\n" % [a.species, " (PREDATOR)" if a.is_predator() else "", a.age, a.max_age]
		t2 += "status: %s\n" % ("ALIVE" if a.alive else "DEAD (%s)" % a.cause_of_death)
		t2 += "behavior: [color=#ffd870]%s[/color]\n" % a.behavior
		t2 += "health %.0f · hunger %.0f · thirst %.0f\n" % [a.health, a.hunger, a.thirst]
		t2 += "aggression %.2f · fear %.2f\n" % [a.aggression, a.fear]
		t2 += "domestication %.0f%% · loyalty %.0f%%\n" % [a.domestication * 100.0, a.loyalty * 100.0]
		t2 += "owner: %s · herd: %s\n" % [_pname(a.owner_id), str(a.herd_id) if a.herd_id >= 0 else "none"]
		t2 += "produces: %s\n" % (a.def["produces"] if a.def["produces"] != "" else "meat only")
		t2 += "food value if hunted: %.0f\n" % a.def["food"]
		inspector_text.text = t2
	elif obj is Building:
		var b: Building = obj
		inspector_title.text = "BUILDING — %s (#%d)" % [b.def["name"], b.id]
		var t3 := ""
		t3 += "[b]%s[/b]\n" % b.def["name"]
		t3 += "hp %.0f · powered: %s\n" % [b.hp, "yes" if b.powered else "no"]
		t3 += "food stock: %.1f\n" % b.stock.get("food", 0.0)
		t3 += "workers: %d\n" % b.workers.size()
		for pid in b.workers.keys():
			t3 += "  %s (%s)\n" % [_pname(pid), b.workers[pid]]
		t3 += "residents: %d / %d\n" % [b.residents.size(), int(b.def["capacity"])]
		for pid in b.residents:
			t3 += "  %s\n" % _pname(pid)
		inspector_text.text = t3
	elif obj is ConstructionSite:
		var s: ConstructionSite = obj
		inspector_title.text = "CONSTRUCTION — %s" % s.def["name"]
		var t4 := ""
		t4 += "[b]%s[/b] (by %s)\n" % [s.def["name"], s.sponsor]
		t4 += "progress: %.0f%%\n" % (s.progress / s.work_required * 100.0)
		t4 += "workers assigned: %d (need ~%d)\n" % [s.workers.size(), s.required_workers]
		inspector_text.text = t4

func _pname(pid: int) -> String:
	if pid < 0:
		return "none"
	var p = G.people.get_person(pid)
	return p.pname if p != null else "#%d" % pid

# ---------------- Overlay labels ----------------

func _build_overlay_labels() -> void:
	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_top = -60.0
	hint_label.offset_left = -300.0
	hint_label.offset_right = 300.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_top = 50.0
	toast_label.offset_left = -300.0
	toast_label.offset_right = 300.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	perf_label = Label.new()
	perf_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	perf_label.offset_top = 44.0
	perf_label.offset_left = 410.0
	perf_label.visible = false
	add_child(perf_label)

func set_hint(text: String) -> void:
	hint_label.text = text

func toast(text: String) -> void:
	toast_label.text = text
	_toast_timer = 3.0

# ---------------- Frame update ----------------

func frame_update(delta: float) -> void:
	speed_label.text = "x%.1f" % Params.get_p("sim.speed")
	time_label.text = "  %s" % G.clock.time_string()
	weather_label.text = "  [%s]" % G.weather.state
	pause_btn.text = "Resume" if G.clock.paused else "Pause"
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.text = ""
	var dashboard_live := dashboard_rtl != null and dashboard_rtl.is_visible_in_tree()
	var government_live := government_rtl != null and government_rtl.is_visible_in_tree()
	if god_panel.visible and (dashboard_live or government_live):
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_dash_timer = 1.0 / maxf(G.perf["dashboard_hz"], 0.1)
			if dashboard_live:
				_refresh_dashboard()
			if government_live:
				_refresh_government()
	if inspector.visible:
		_insp_timer -= delta
		if _insp_timer <= 0.0:
			_insp_timer = 0.5
			_refresh_inspector()
	perf_label.visible = G.dbg.enabled
	if G.dbg.enabled:
		perf_label.text = "FPS %d | people %d | animals %d | buildings %d | sounds/window %d | AI %.0f/s" % [
			Engine.get_frames_per_second(), G.people.alive_count(), G.animals.alive_count(),
			G.buildings.buildings.size(), G.language.recent.size(), G.people.decisions_per_sec]

# ---------------- Helpers ----------------

func _btn(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _lbl(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	parent.add_child(l)
	return l

func _section(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var l := Label.new()
	l.text = "[ %s ]" % text
	parent.add_child(l)

func _grid(parent: Control) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	parent.add_child(g)
	return g
