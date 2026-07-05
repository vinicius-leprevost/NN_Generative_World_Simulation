class_name ConstructionSite extends Node3D
const BuildingDB = preload("res://scripts/data/building_db.gd")
const Vis = preload("res://scripts/core/visuals.gd")

## ConstructionSite: a building in progress. Advances from assigned workers
## who are present; shows floating info (name, %, ETA, workers, status).

var id := 0
var btype := "home"
var def: Dictionary = {}
var progress := 0.0
var work_required := 100.0
var workers: Array = []       # assigned person ids
var required_workers := 2
var sponsor := "society"
var frame: MeshInstance3D
var label: Label3D
var _label_timer := 0.0

func setup(sid: int, type: String, pos: Vector3, from_sponsor: String) -> void:
	id = sid
	btype = type
	def = BuildingDB.get_def(type)
	position = pos
	sponsor = from_sponsor
	work_required = def["work"] * Params.get_p("con.materials_req")
	required_workers = clampi(int(ceil(def["work"] / 60.0 * Params.get_p("con.workers_req"))), 1, 6)
	_build_visual()

func _build_visual() -> void:
	var sz: Vector2 = def["size"]
	var h: float = maxf(def["h"], 1.0)
	frame = Vis.box(Vector3(sz.x, h, sz.y), Color(0.7, 0.68, 0.6, 0.4))
	frame.position.y = 0.1
	frame.scale.y = 0.05
	add_child(frame)
	for corner in [Vector3(-sz.x / 2, 0, -sz.y / 2), Vector3(sz.x / 2, 0, -sz.y / 2),
			Vector3(-sz.x / 2, 0, sz.y / 2), Vector3(sz.x / 2, 0, sz.y / 2)]:
		var pole := Vis.cylinder(0.06, h + 0.5, Color(0.55, 0.45, 0.3))
		pole.position = corner + Vector3(0, (h + 0.5) * 0.5, 0)
		add_child(pole)
	label = Vis.label("", 24, Color(1.0, 0.9, 0.5))
	label.position = Vector3(0, def["h"] + 2.0, 0)
	add_child(label)
	_update_label(0, "starting")

func present_worker_data() -> Dictionary:
	cleanup_workers()
	var present := 0
	var skill_sum := 0.0
	for pid in workers:
		var p = G.people.get_person(pid)
		if p != null and p.action == "build" and p.target_id == id and p.position.distance_to(position) < 8.0:
			present += 1
			skill_sum += p.skills.get("construction", 0.0)
	var avg_skill := 0.5
	if present > 0:
		avg_skill = 0.5 + (skill_sum / present) * 0.8
	return {"present": present, "skill": avg_skill}

func cleanup_workers() -> void:
	for i in range(workers.size() - 1, -1, -1):
		var pid := int(workers[i])
		var p = G.people.get_person(pid)
		if p == null or not p.alive or p.action != "build" or p.target_id != id:
			workers.remove_at(i)
	while workers.size() > required_workers:
		var extra_id := int(workers.pop_back())
		var extra = G.people.get_person(extra_id)
		if extra != null and extra.alive and extra.action == "build" and extra.target_id == id:
			extra.action = "idle"
			extra.arrived = true
			extra.target_id = -1
			extra.target_kind = "point"

func assigned_worker_count() -> int:
	cleanup_workers()
	return workers.size()

func has_open_worker_slot() -> bool:
	return assigned_worker_count() < required_workers

func reserve_worker(pid: int) -> bool:
	cleanup_workers()
	if workers.has(pid):
		return true
	if workers.size() >= required_workers:
		return false
	workers.append(pid)
	return true

func release_worker(pid: int) -> void:
	workers.erase(pid)

func tick(dt: float) -> void:
	var wd := present_worker_data()
	var present: int = wd["present"]
	var rate := 0.0
	if present > 0:
		var speed_mult := Params.get_p("con.speed")
		if btype == "street_light" or btype == "park":
			speed_mult *= Params.get_p("con.road_speed")
		rate = float(mini(present, required_workers * 2)) * Params.get_p("con.efficiency") \
			* wd["skill"] * G.weather.build_mult() * speed_mult
		if G.buildings.road_at(position):
			rate *= 1.15
		progress += rate * dt
	var h: float = maxf(def["h"], 1.0)
	frame.scale.y = clampf(progress / work_required, 0.05, 1.0)
	frame.position.y = h * frame.scale.y * 0.5
	_label_timer -= dt
	if _label_timer <= 0.0:
		_label_timer = 0.5
		var status := "waiting for workers"
		var eta := "--"
		if present > 0:
			status = "building"
			var remaining := (work_required - progress) / maxf(rate, 0.01)
			eta = "%ds" % int(remaining)
		elif G.weather.build_mult() < 0.5:
			status = "halted (weather)"
		_update_label_full(present, status, eta)
	if progress >= work_required:
		G.buildings.finish_site(id)

func _update_label(present: int, status: String) -> void:
	_update_label_full(present, status, "--")

func _update_label_full(present: int, status: String, eta: String) -> void:
	cleanup_workers()
	var pct := int(progress / work_required * 100.0)
	label.text = "%s\n%d%%  ETA %s\nworkers %d/%d (%d assigned)\n%s" % [
		def["name"], pct, eta, present, required_workers, workers.size(), status]

func serialize() -> Dictionary:
	return {"id": id, "btype": btype, "x": position.x, "z": position.z,
		"progress": progress, "work_required": work_required,
		"workers": workers, "sponsor": sponsor}

func deserialize(d: Dictionary) -> void:
	progress = float(d.get("progress", 0.0))
	work_required = float(d.get("work_required", work_required))
	workers = []
	for w in d.get("workers", []):
		workers.append(int(w))
	sponsor = str(d.get("sponsor", "society"))
