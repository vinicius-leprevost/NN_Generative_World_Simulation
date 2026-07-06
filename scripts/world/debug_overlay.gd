class_name DebugOverlay extends Node3D
## DebugOverlay: F3 world-space debug drawing — agent goals/targets,
## sound/communication radii, crime hotspots, predator territories.

var enabled := false
var _im := ImmediateMesh.new()
var _mi: MeshInstance3D

const ACTION_COLORS := {
	"seek_food": Color(0.3, 0.9, 0.3), "seek_water": Color(0.3, 0.6, 1.0),
	"flee": Color(1.0, 0.2, 0.2), "work": Color(0.95, 0.9, 0.3),
	"build": Color(1.0, 0.6, 0.2), "hunt": Color(0.8, 0.3, 0.9),
	"commit_crime": Color(0.7, 0.1, 0.1), "arrest": Color(0.2, 0.3, 1.0),
	"socialize": Color(1.0, 0.6, 0.8), "wander": Color(0.7, 0.7, 0.7),
}

func _ready() -> void:
	_mi = MeshInstance3D.new()
	_mi.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	_mi.material_override = m
	add_child(_mi)

func toggle() -> void:
	enabled = not enabled

func _process(_delta: float) -> void:
	_im.clear_surfaces()
	if not enabled or G.people == null:
		return
	var lines: Array = []   # [from, to, color]
	for p in G.people.persons.values():
		if not p.alive or p.arrived:
			continue
		var c: Color = ACTION_COLORS.get(p.action, Color(0.6, 0.6, 0.6))
		# draw the planned A* route (waypoint polyline), not a straight ray
		var prev: Vector3 = p.position + Vector3(0, 0.4, 0)
		if p._path.is_empty():
			lines.append([prev, p.target_pos + Vector3(0, 0.4, 0), c])
		else:
			for i in range(p._path_i, p._path.size()):
				var nxt: Vector3 = p._path[i] + Vector3(0, 0.4, 0)
				lines.append([prev, nxt, c])
				prev = nxt
	for evt in G.language.recent:
		var col := Color(0.4, 1.0, 0.5) if evt["kind"] == "human" else Color(1.0, 0.5, 0.2)
		if evt["meaning"] == "danger" or evt["meaning"] == "predator" or evt["kind"] == "animal":
			col = Color(1.0, 0.4, 0.2)
		_circle(lines, evt["pos"], evt["radius"], col)
	for h in G.crime.hotspots:
		_circle(lines, Vector3(h["x"], 0, h["z"]), 6.0, Color(0.9, 0.1, 0.1))
	for a in G.animals.animals.values():
		if a.alive and a.is_predator():
			_circle(lines, a.territory, 20.0, Color(0.8, 0.2, 0.2, 0.5))
	if lines.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in lines:
		_im.surface_set_color(seg[2])
		_im.surface_add_vertex(seg[0])
		_im.surface_set_color(seg[2])
		_im.surface_add_vertex(seg[1])
	_im.surface_end()

func _circle(lines: Array, center: Vector3, radius: float, color: Color) -> void:
	var prev := center + Vector3(radius, 0.3, 0)
	var segs := 20
	for i in range(1, segs + 1):
		var ang := TAU * float(i) / segs
		var next := center + Vector3(cos(ang) * radius, 0.3, sin(ang) * radius)
		lines.append([prev, next, color])
		prev = next
