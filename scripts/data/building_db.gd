class_name BuildingDB
## BuildingDB: static definitions for every constructible structure.
## work: worker-seconds of construction effort. jobs: role -> slot count.
## capacity: residents (homes), students (schools), inmates (prisons),
## animals (barns/pens) depending on type.

const DEFS := {
	"home": {"name": "Home", "size": Vector2(4, 4), "h": 2.6, "color": Color(0.76, 0.6, 0.42),
		"cost": 100.0, "work": 70.0, "jobs": {}, "capacity": 5, "provides": "shelter"},
	"apartment": {"name": "Apartment Building", "size": Vector2(6, 8), "h": 9.0, "color": Color(0.65, 0.62, 0.58),
		"cost": 500.0, "work": 280.0, "jobs": {}, "capacity": 16, "provides": "shelter"},
	"condo": {"name": "Condo", "size": Vector2(5, 6), "h": 12.0, "color": Color(0.6, 0.66, 0.7),
		"cost": 700.0, "work": 340.0, "jobs": {}, "capacity": 12, "provides": "shelter"},
	"school": {"name": "School", "size": Vector2(8, 6), "h": 3.2, "color": Color(0.85, 0.75, 0.35),
		"cost": 300.0, "work": 160.0, "jobs": {"teacher": 2}, "capacity": 30, "provides": "education"},
	"hospital": {"name": "Hospital", "size": Vector2(8, 8), "h": 4.5, "color": Color(0.9, 0.9, 0.92),
		"cost": 400.0, "work": 200.0, "jobs": {"doctor": 3}, "capacity": 20, "provides": "health"},
	"police_station": {"name": "Police Station", "size": Vector2(6, 6), "h": 3.4, "color": Color(0.3, 0.42, 0.75),
		"cost": 350.0, "work": 160.0, "jobs": {"police": 4}, "capacity": 0, "provides": "safety"},
	"prison": {"name": "Prison", "size": Vector2(9, 7), "h": 4.0, "color": Color(0.45, 0.45, 0.48),
		"cost": 400.0, "work": 220.0, "jobs": {"guard": 2}, "capacity": 10, "provides": "prison"},
	"power_plant": {"name": "Power Plant", "size": Vector2(10, 8), "h": 6.0, "color": Color(0.55, 0.35, 0.3),
		"cost": 600.0, "work": 320.0, "jobs": {"power_worker": 3}, "capacity": 0, "provides": "power"},
	"store": {"name": "Store", "size": Vector2(5, 5), "h": 3.0, "color": Color(0.4, 0.7, 0.55),
		"cost": 250.0, "work": 110.0, "jobs": {"shop_worker": 2}, "capacity": 0, "provides": "food_store"},
	"market": {"name": "Market", "size": Vector2(8, 8), "h": 3.0, "color": Color(0.5, 0.75, 0.5),
		"cost": 350.0, "work": 150.0, "jobs": {"shop_worker": 4}, "capacity": 0, "provides": "food_store"},
	"workplace": {"name": "Workplace", "size": Vector2(6, 6), "h": 3.6, "color": Color(0.6, 0.55, 0.65),
		"cost": 300.0, "work": 160.0, "jobs": {"worker": 6}, "capacity": 0, "provides": "work"},
	"construction_yard": {"name": "Construction Yard", "size": Vector2(8, 6), "h": 3.0, "color": Color(0.72, 0.5, 0.28),
		"cost": 260.0, "work": 140.0, "jobs": {"builder": 8}, "capacity": 0, "provides": "construction"},
	"government": {"name": "Government Building", "size": Vector2(8, 8), "h": 5.0, "color": Color(0.85, 0.8, 0.6),
		"cost": 500.0, "work": 260.0, "jobs": {"president": 1, "politician": 3, "gov_worker": 2}, "capacity": 0, "provides": "government"},
	"farm": {"name": "Farm", "size": Vector2(10, 10), "h": 0.4, "color": Color(0.55, 0.45, 0.25),
		"cost": 200.0, "work": 130.0, "jobs": {"farmer": 3}, "capacity": 0, "provides": "food_production"},
	"barn": {"name": "Barn", "size": Vector2(6, 8), "h": 4.0, "color": Color(0.6, 0.3, 0.22),
		"cost": 150.0, "work": 90.0, "jobs": {"animal_handler": 1}, "capacity": 10, "provides": "animal_shelter"},
	"animal_pen": {"name": "Animal Pen", "size": Vector2(6, 6), "h": 0.9, "color": Color(0.55, 0.42, 0.3),
		"cost": 80.0, "work": 55.0, "jobs": {}, "capacity": 8, "provides": "animal_shelter"},
	"well": {"name": "Well", "size": Vector2(2, 2), "h": 1.2, "color": Color(0.5, 0.55, 0.6),
		"cost": 80.0, "work": 65.0, "jobs": {}, "capacity": 0, "provides": "water"},
	"water_storage": {"name": "Water Storage", "size": Vector2(4, 4), "h": 3.5, "color": Color(0.4, 0.55, 0.7),
		"cost": 150.0, "work": 100.0, "jobs": {}, "capacity": 0, "provides": "water"},
	"warehouse": {"name": "Warehouse", "size": Vector2(8, 6), "h": 4.0, "color": Color(0.5, 0.5, 0.45),
		"cost": 200.0, "work": 110.0, "jobs": {}, "capacity": 0, "provides": "storage"},
	"watchtower": {"name": "Watch Tower", "size": Vector2(2.5, 2.5), "h": 7.0, "color": Color(0.5, 0.44, 0.35),
		"cost": 120.0, "work": 75.0, "jobs": {"guard": 1}, "capacity": 0, "provides": "safety"},
	"street_light": {"name": "Street Light", "size": Vector2(0.6, 0.6), "h": 4.0, "color": Color(0.35, 0.35, 0.38),
		"cost": 25.0, "work": 16.0, "jobs": {}, "capacity": 0, "provides": "light"},
	"park": {"name": "Park", "size": Vector2(8, 8), "h": 0.3, "color": Color(0.35, 0.6, 0.3),
		"cost": 60.0, "work": 45.0, "jobs": {}, "capacity": 0, "provides": "leisure"},
	"food_processing": {"name": "Food Processing", "size": Vector2(6, 6), "h": 3.5, "color": Color(0.62, 0.5, 0.4),
		"cost": 250.0, "work": 140.0, "jobs": {"worker": 2}, "capacity": 0, "provides": "food_processing"},
}

static func get_def(btype: String) -> Dictionary:
	return DEFS.get(btype, DEFS["home"])

static func types() -> Array:
	return DEFS.keys()
