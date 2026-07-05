class_name Vis
## Vis: static helpers for procedural meshes, cached materials and labels.
## All world visuals are built in code from these primitives.

static var _mats: Dictionary = {}

static func mat(c: Color, emissive := false) -> StandardMaterial3D:
	var key := c.to_html() + ("e" if emissive else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = 1.4
	_mats[key] = m
	return m

static func box(size: Vector3, c: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat(c, emissive)
	return mi

static func capsule(radius: float, height: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	mi.mesh = m
	mi.material_override = mat(c)
	return mi

static func cylinder(radius: float, height: float, c: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	mi.mesh = m
	mi.material_override = mat(c, emissive)
	return mi

static func sphere(radius: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	mi.mesh = m
	mi.material_override = mat(c)
	return mi

static func label(text: String, size := 36, color := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.font_size = size
	l.outline_size = 6
	l.modulate = color
	l.pixel_size = 0.01
	return l
