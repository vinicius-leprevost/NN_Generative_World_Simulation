class_name VehicleSystem extends Node3D
const Vis = preload("res://scripts/core/visuals.gd")

## VehicleSystem: cars owned by people. A car boosts its owner's speed on
## roads; visually it follows the driving owner and parks near their home.

var cars: Dictionary = {}   # id -> {"id", "owner", "color", "node"}
var next_id := 1

func buy_car(p) -> bool:
	if p.car_id >= 0:
		return false
	if not G.buildings.has_roads():
		return false
	var price: float = G.economy.price("car")
	if p.money < price:
		return false
	p.money -= price
	G.economy.absorb(price * 0.5)
	var color := Color(Rng.randf_range(0.2, 0.9), Rng.randf_range(0.2, 0.9), Rng.randf_range(0.2, 0.9))
	var node := Node3D.new()
	add_child(node)
	var chassis := Vis.box(Vector3(1.0, 0.5, 2.0), color)
	chassis.position.y = 0.4
	node.add_child(chassis)
	var cab := Vis.box(Vector3(0.85, 0.4, 1.0), Color(0.7, 0.85, 0.95))
	cab.position.y = 0.85
	node.add_child(cab)
	node.position = p.position + Vector3(1.5, 0, 1.5)
	var car := {"id": next_id, "owner": p.id, "color": color.to_html(), "node": node}
	cars[next_id] = car
	p.car_id = next_id
	next_id += 1
	Events.add("economy", "%s bought a car" % p.pname)
	return true

func remove_car(cid: int) -> void:
	var car = cars.get(cid)
	if car == null:
		return
	var owner = G.people.get_person(car["owner"])
	if owner != null:
		owner.car_id = -1
	car["node"].queue_free()
	cars.erase(cid)

func tick(_dt: float) -> void:
	for car in cars.values():
		var owner = G.people.get_person(car["owner"])
		var node: Node3D = car["node"]
		if owner == null or not owner.alive:
			continue  # car stays parked where it is
		if not owner.arrived and G.buildings.road_at(owner.position):
			# owner is driving
			node.position = owner.position + Vector3(0, 0, 0)
			node.rotation.y = owner.rotation.y
		else:
			var home = G.buildings.get_building(owner.home_id)
			if home != null and node.position.distance_to(home.position) > 6.0 and owner.arrived:
				node.position = home.position + Vector3(home.def["size"].x * 0.5 + 1.5, 0, 0)

func clear_all() -> void:
	for car in cars.values():
		car["node"].queue_free()
	cars.clear()
	next_id = 1

func to_dict() -> Dictionary:
	var list: Array = []
	for car in cars.values():
		list.append({"id": car["id"], "owner": car["owner"], "color": car["color"],
			"x": car["node"].position.x, "z": car["node"].position.z})
	return {"cars": list, "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	for cd in d.get("cars", []):
		var color := Color.from_string(str(cd["color"]), Color.GRAY)
		var node := Node3D.new()
		add_child(node)
		var chassis := Vis.box(Vector3(1.0, 0.5, 2.0), color)
		chassis.position.y = 0.4
		node.add_child(chassis)
		var cab := Vis.box(Vector3(0.85, 0.4, 1.0), Color(0.7, 0.85, 0.95))
		cab.position.y = 0.85
		node.add_child(cab)
		node.position = Vector3(float(cd["x"]), 0, float(cd["z"]))
		cars[int(cd["id"])] = {"id": int(cd["id"]), "owner": int(cd["owner"]),
			"color": str(cd["color"]), "node": node}
