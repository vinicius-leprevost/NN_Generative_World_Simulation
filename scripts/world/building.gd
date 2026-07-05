class_name Building extends Node3D
const BuildingDB = preload("res://scripts/data/building_db.gd")
const Vis = preload("res://scripts/core/visuals.gd")

## Building: a completed structure. Holds stock, workers, residents,
## penned animals, power state and durability.

var id := 0
var btype := "home"
var def: Dictionary = {}
var hp := 100.0
var powered := false
var stock := {"food": 0.0, "water": 0.0}
var workers: Dictionary = {}    # person id -> role
var residents: Array = []       # person ids (homes)
var penned: Array = []          # animal ids (barns/pens)
var label: Label3D
var light: OmniLight3D = null

func setup(bid: int, type: String, pos: Vector3) -> void:
	id = bid
	btype = type
	def = BuildingDB.get_def(type)
	position = pos
	hp = 100.0 * Params.get_p("con.durability")
	if def.get("provides", "") == "food_store":
		stock["food"] = 15.0
	_build_visual()

func _build_visual() -> void:
	var sz: Vector2 = def["size"]
	var h: float = def["h"]
	if btype == "street_light":
		var pole := Vis.cylinder(0.08, h, def["color"])
		pole.position.y = h * 0.5
		add_child(pole)
		var head := Vis.sphere(0.25, Color(1.0, 0.95, 0.6))
		head.position.y = h
		add_child(head)
		light = OmniLight3D.new()
		light.position.y = h
		light.light_color = Color(1.0, 0.92, 0.6)
		light.omni_range = 14.0
		light.light_energy = 2.0
		light.visible = false
		add_child(light)
	else:
		var box := Vis.box(Vector3(sz.x, h, sz.y), def["color"])
		box.position.y = h * 0.5
		add_child(box)
		if btype == "well":
			var ring := Vis.cylinder(0.9, 0.5, Color(0.35, 0.55, 0.75))
			ring.position.y = 0.9
			add_child(ring)
	label = Vis.label(def["name"], 26, Color(0.95, 0.95, 0.9))
	label.position = Vector3(0, h + 1.2, 0)
	add_child(label)

func refresh_label() -> void:
	if G.cam == null:
		return
	var d: float = G.cam.camera.global_position.distance_to(global_position)
	label.visible = d < G.perf["label_dist"] * 1.3 or G.main.selected == self
	if not label.visible:
		return
	var extra := ""
	if stock["food"] > 0.5:
		extra = "\nfood: %d" % int(stock["food"])
	if not powered and Params.get_p("con.power_req") > 0.5 and btype == "street_light":
		extra += "\n(no power)"
	label.text = def["name"] + extra

func worker_count(role := "") -> int:
	if role == "":
		return workers.size()
	var n := 0
	for r in workers.values():
		if r == role:
			n += 1
	return n

func present_workers() -> int:
	var n := 0
	for pid in workers.keys():
		var p = G.people.get_person(pid)
		if p != null and p.alive and p.action == "work" and p.position.distance_to(position) < 8.0:
			n += 1
	return n

func serialize() -> Dictionary:
	var wser := {}
	for pid in workers.keys():
		wser[str(pid)] = workers[pid]
	return {"id": id, "btype": btype, "x": position.x, "z": position.z,
		"hp": hp, "powered": powered, "stock": stock, "workers": wser,
		"residents": residents, "penned": penned}

func deserialize(d: Dictionary) -> void:
	hp = float(d.get("hp", 100.0))
	powered = bool(d.get("powered", false))
	stock = d.get("stock", {"food": 0.0, "water": 0.0})
	workers = {}
	for k in d.get("workers", {}).keys():
		workers[int(k)] = d["workers"][k]
	residents = []
	for r in d.get("residents", []):
		residents.append(int(r))
	penned = []
	for p in d.get("penned", []):
		penned.append(int(p))
