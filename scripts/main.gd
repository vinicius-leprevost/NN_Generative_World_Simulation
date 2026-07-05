extends Node3D
## Main: root orchestrator. Builds the world, all simulation systems and the
## UI in code, drives the tick pipeline, handles global input, selection,
## performance presets, autosave, and full save/load state assembly.

const WorldManager = preload("res://scripts/systems/world_manager.gd")
const TimeSystem = preload("res://scripts/systems/time_system.gd")
const WeatherSystem = preload("res://scripts/systems/weather_system.gd")
const LanguageSystem = preload("res://scripts/systems/language_system.gd")
const PersonManager = preload("res://scripts/systems/person_manager.gd")
const AnimalManager = preload("res://scripts/systems/animal_manager.gd")
const BuildingManager = preload("res://scripts/systems/building_manager.gd")
const VehicleSystem = preload("res://scripts/systems/vehicle_system.gd")
const EconomySystem = preload("res://scripts/systems/economy_system.gd")
const GroupSystem = preload("res://scripts/systems/group_system.gd")
const CrimeSystem = preload("res://scripts/systems/crime_system.gd")
const PoliticsSystem = preload("res://scripts/systems/politics_system.gd")
const StatsSystem = preload("res://scripts/systems/stats_system.gd")
const GodTools = preload("res://scripts/world/god_tools.gd")
const CameraRig = preload("res://scripts/world/camera_rig.gd")
const DebugOverlay = preload("res://scripts/world/debug_overlay.gd")
const UIManager = preload("res://scripts/ui/ui_manager.gd")
const Vis = preload("res://scripts/core/visuals.gd")

var world
var clock
var weather
var language
var people
var animals
var buildings
var vehicles
var economy
var groups
var crime
var politics
var stats
var god
var cam
var dbg
var ui

var selected = null
var sel_ring: MeshInstance3D
var _autosave_timer := 0.0
var _last_autosave_msec := 0
var _smoke := false          # headless CI mode: `godot --headless -- --smoke`
var _smoke_frames := 0
var _smoke_quit_delay := -1

func _ready() -> void:
	G.main = self
	world = WorldManager.new()
	add_child(world)
	world.build()
	G.world = world
	clock = TimeSystem.new()
	add_child(clock)
	G.clock = clock
	weather = WeatherSystem.new()
	add_child(weather)
	G.weather = weather
	language = LanguageSystem.new()
	add_child(language)
	G.language = language
	people = PersonManager.new()
	add_child(people)
	G.people = people
	animals = AnimalManager.new()
	add_child(animals)
	G.animals = animals
	buildings = BuildingManager.new()
	add_child(buildings)
	buildings.build()
	G.buildings = buildings
	vehicles = VehicleSystem.new()
	add_child(vehicles)
	G.vehicles = vehicles
	economy = EconomySystem.new()
	add_child(economy)
	G.economy = economy
	groups = GroupSystem.new()
	add_child(groups)
	G.groups = groups
	crime = CrimeSystem.new()
	add_child(crime)
	G.crime = crime
	politics = PoliticsSystem.new()
	add_child(politics)
	G.politics = politics
	stats = StatsSystem.new()
	add_child(stats)
	G.stats = stats
	god = GodTools.new()
	add_child(god)
	G.god = god
	cam = CameraRig.new()
	add_child(cam)
	G.cam = cam
	dbg = DebugOverlay.new()
	add_child(dbg)
	G.dbg = dbg
	ui = UIManager.new()
	add_child(ui)
	G.ui = ui
	ui.build()
	clock.day_passed.connect(func(_d): economy.day_tick())
	clock.year_passed.connect(func(y): Events.add("system", "Year %d begins" % y))
	_build_sel_ring()
	apply_preset("Medium")
	new_world()
	_smoke = OS.get_cmdline_user_args().has("--smoke")
	if _smoke:
		Rng.set_world_seed(133742)  # deterministic smoke runs
		new_world(false)
		Params.set_p("sim.speed", 20.0)
		print("SMOKE: started, pop=%d animals=%d" % [people.alive_count(), animals.alive_count()])

func _build_sel_ring() -> void:
	sel_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.2
	sel_ring.mesh = torus
	sel_ring.material_override = Vis.mat(Color(1.0, 0.9, 0.2), true)
	sel_ring.visible = false
	add_child(sel_ring)

func _process(delta: float) -> void:
	if _smoke_quit_delay >= 0:
		_smoke_quit_delay -= 1
		if _smoke_quit_delay <= 0:
			get_tree().quit()
		return
	var dt: float = clock.advance(delta)
	if dt > 0.0:
		weather.tick(dt)
		world.tick(dt)
		people.tick(dt)
		animals.tick(dt)
		buildings.tick(dt)
		vehicles.tick(dt)
		groups.tick(dt)
		language.tick(dt)
		crime.tick(dt)
		politics.tick(dt)
		_autosave_timer += dt
		# sim-time cadence with a real-time floor, so 20x speed doesn't
		# hammer the disk with an autosave every few real seconds
		if _autosave_timer > clock.day_length() * 3.0 \
				and Time.get_ticks_msec() - _last_autosave_msec > 60_000:
			_autosave_timer = 0.0
			_last_autosave_msec = Time.get_ticks_msec()
			if SaveMgr.save_slot(0):
				ui.toast("Autosaved (slot 0)")
	world._update_sun()  # keep lighting live even while paused (god time control)
	ui.frame_update(delta)
	_update_sel_ring()
	if _smoke:
		_smoke_frames += 1
		if _smoke_frames == 2000:
			print("SMOKE: saving… ", "OK" if SaveMgr.save_slot(5) else "FAILED")
		elif _smoke_frames == 2200:
			print("SMOKE: loading… ", "OK" if SaveMgr.load_slot(5) else "FAILED")
		elif _smoke_frames % 2600 == 0:
			var snap: Dictionary = stats.snapshot()
			print("SMOKE: f=%d pop=%d animals=%d buildings=%d sites=%d sounds=%d dialects=%d day=%d" % [
				_smoke_frames, people.alive_count(), animals.alive_count(), buildings.buildings.size(),
				buildings.sites.size(), language.stats["sounds"], language.dialects.size(), clock.day])
			print("SMOKE: dashboard sections=%d events=%d crimes=%d jobs=%s" % [snap.size(),
				Events.entries.size(), crime.stats["total"], str(snap["economy"]["Jobs"])])
			print("SMOKE: deaths=%s births=%d groups=%d" % [str(people.deaths_by_cause), people.births, groups.groups.size()])
			print("SMOKE: animal_deaths=%s" % str(animals.deaths_by_cause))
			var hs := 0.0
			var ts := 0.0
			var es := 0.0
			var hps := 0.0
			var alive_n := maxi(people.alive_count(), 1)
			for pp in people.alive_list():
				hs += pp.hunger
				ts += pp.thirst
				es += pp.energy
				hps += pp.health
			print("SMOKE: avg hunger=%.0f thirst=%.0f energy=%.0f health=%.0f" % [
				hs / alive_n, ts / alive_n, es / alive_n, hps / alive_n])
			language.shutdown_audio()
			_smoke_quit_delay = 4

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				clock.paused = not clock.paused
			KEY_N:
				clock.request_step()
			KEY_EQUAL:
				Params.set_p("sim.speed", Params.get_p("sim.speed") * 2.0)
			KEY_MINUS:
				Params.set_p("sim.speed", Params.get_p("sim.speed") * 0.5)
			KEY_G:
				ui.god_panel.visible = not ui.god_panel.visible
			KEY_L:
				ui.event_panel.visible = not ui.event_panel.visible
			KEY_F3:
				dbg.toggle()
			KEY_F5:
				ui._save(1)
			KEY_F9:
				ui._load(1)
			KEY_T:
				cam.toggle_mode()
			KEY_ESCAPE:
				if god.active():
					god.cancel()
				else:
					select(null)

# ---------------- Selection ----------------

func select(obj) -> void:
	selected = obj
	ui.show_inspector(obj)

func select_at(pos: Vector3) -> void:
	# people (including recent corpses)
	var best = null
	var best_d := 2.6
	for p in people.persons.values():
		var d: float = p.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	if best != null:
		select(best)
		return
	best_d = 2.8
	for a in animals.animals.values():
		var d2: float = a.position.distance_to(pos)
		if d2 < best_d:
			best_d = d2
			best = a
	if best != null:
		select(best)
		return
	for s in buildings.sites.values():
		if s.position.distance_to(pos) < 5.0:
			select(s)
			return
	for b in buildings.buildings.values():
		var sz: Vector2 = b.def["size"]
		if absf(pos.x - b.position.x) < sz.x * 0.5 + 0.8 and absf(pos.z - b.position.z) < sz.y * 0.5 + 0.8:
			select(b)
			return
	select(null)

func _update_sel_ring() -> void:
	if selected == null or not is_instance_valid(selected):
		if selected != null:
			select(null)
		sel_ring.visible = false
		return
	sel_ring.visible = true
	sel_ring.position = selected.position + Vector3(0, 0.25, 0)

# ---------------- World lifecycle ----------------

func new_world(reseed := true) -> void:
	clear_world()
	if reseed:
		Rng.randomize_seed()
	language.setup_base()
	# starting terrain features
	world.add_lake(Vector3(32, 0, 26), 12.0)
	world.add_river(Vector3(-WorldManager.HALF, 0, -60), Vector3(WorldManager.HALF, 0, 30))
	for i in range(10):
		# guaranteed food near the founding settlement
		var near := Vector3(Rng.randf_range(-35, 35), 0, Rng.randf_range(-35, 35))
		world.add_resource(near, Rng.randf_range(60.0, 90.0))
	for i in range(24):
		var pos := Vector3(Rng.randf_range(-110, 110), 0, Rng.randf_range(-110, 110))
		world.add_resource(pos, Rng.randf_range(40.0, 80.0))
	world.add_zone("predator", Vector3(-130, 0, -130), 35.0)
	# founding population
	var n := int(Params.get_p("pop.start_population"))
	for i in range(n):
		var ang := TAU * float(i) / maxf(n, 1.0)
		people.spawn(Vector3(cos(ang) * Rng.randf_range(4.0, 18.0), 0, sin(ang) * Rng.randf_range(4.0, 18.0)))
	# founding fauna
	for i in range(6):
		animals.spawn("chicken", Vector3(Rng.randf_range(5, 20), 0, Rng.randf_range(-20, -5)))
	for i in range(4):
		animals.spawn("cow", Vector3(Rng.randf_range(18, 32), 0, Rng.randf_range(-30, -15)))
	for i in range(3):
		animals.spawn("sheep", Vector3(Rng.randf_range(-30, -15), 0, Rng.randf_range(10, 25)))
	for i in range(5):
		animals.spawn("deer", Vector3(Rng.randf_range(50, 80), 0, Rng.randf_range(30, 60)))
	for i in range(2):
		animals.spawn("dog", Vector3(Rng.randf_range(-8, 8), 0, Rng.randf_range(-8, 8)))
	for i in range(3):
		animals.spawn("wolf", Vector3(Rng.randf_range(-140, -115), 0, Rng.randf_range(-140, -115)))
	animals.spawn("bear", Vector3(-125, 0, -110))
	weather.set_weather("clear", 2.0)
	Events.add("system", "GENESIS — a new world begins with %d people" % n)

func clear_world() -> void:
	select(null)
	people.clear_all()
	animals.clear_all()
	buildings.clear_all()
	vehicles.clear_all()
	world.clear_all()
	groups.clear_all()
	crime.clear_all()
	politics.clear_all()
	language.clear_all()
	Events.clear()
	economy.treasury = 0.0
	economy.tax_collected = 0.0
	economy.public_debt = 0.0
	economy.debt_issued = 0.0
	clock.from_dict({})
	_autosave_timer = 0.0

# ---------------- Persistence ----------------

func collect_state() -> Dictionary:
	return {
		"params": Params.to_dict(), "rng": Rng.to_dict(),
		"clock": clock.to_dict(), "weather": weather.to_dict(),
		"world": world.to_dict(), "language": language.to_dict(),
		"buildings": buildings.to_dict(), "groups": groups.to_dict(),
		"people": people.to_dict(), "animals": animals.to_dict(),
		"vehicles": vehicles.to_dict(), "economy": economy.to_dict(),
		"crime": crime.to_dict(), "politics": politics.to_dict(),
		"events": Events.to_dict(),
	}

func apply_state(d: Dictionary) -> void:
	clear_world()
	Params.from_dict(d.get("params", {}))
	Rng.from_dict(d.get("rng", {}))
	clock.from_dict(d.get("clock", {}))
	weather.from_dict(d.get("weather", {}))
	world.from_dict(d.get("world", {}))
	language.from_dict(d.get("language", {}))
	buildings.from_dict(d.get("buildings", {}))
	groups.from_dict(d.get("groups", {}))
	people.from_dict(d.get("people", {}))
	animals.from_dict(d.get("animals", {}))
	vehicles.from_dict(d.get("vehicles", {}))
	economy.from_dict(d.get("economy", {}))
	crime.from_dict(d.get("crime", {}))
	politics.from_dict(d.get("politics", {}))
	Events.from_dict(d.get("events", {}))

# ---------------- Performance presets ----------------

func apply_preset(preset_name: String) -> void:
	G.perf["name"] = preset_name
	var vp := get_viewport()
	match preset_name:
		"Low":
			vp.scaling_3d_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			world.sun.shadow_enabled = false
			G.perf["max_lights"] = 4
			G.perf["label_dist"] = 40.0
			G.perf["ai_mult"] = 1.25
			G.perf["dashboard_hz"] = 0.5
		"Medium":
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			world.sun.shadow_enabled = true
			G.perf["max_lights"] = 12
			G.perf["label_dist"] = 70.0
			G.perf["ai_mult"] = 1.0
			G.perf["dashboard_hz"] = 1.0
		"High":
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			world.sun.shadow_enabled = true
			G.perf["max_lights"] = 24
			G.perf["label_dist"] = 110.0
			G.perf["ai_mult"] = 1.0
			G.perf["dashboard_hz"] = 2.0
		"Sim-heavy":
			vp.scaling_3d_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			world.sun.shadow_enabled = false
			G.perf["max_lights"] = 4
			G.perf["label_dist"] = 40.0
			G.perf["ai_mult"] = 0.6   # more frequent neural decisions
			G.perf["dashboard_hz"] = 0.5
		"Visual-heavy":
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			world.sun.shadow_enabled = true
			G.perf["max_lights"] = 32
			G.perf["label_dist"] = 130.0
			G.perf["ai_mult"] = 1.4
			G.perf["dashboard_hz"] = 2.0
	world.environment.glow_enabled = preset_name == "Visual-heavy"
	if ui != null and ui.toast_label != null:
		ui.toast("Preset: %s" % preset_name)
