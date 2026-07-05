class_name CameraRig extends Node3D
## CameraRig: god-view camera. Top-down or orbit, WASD/edge pan, wheel zoom,
## middle-drag orbit, right-drag pan, left-click select / god-place.

var camera: Camera3D
var yaw := 0.0
var pitch := -62.0
var dist := 70.0
var top_down := false
var focus := Vector3.ZERO

var _orbiting := false
var _panning := false
var _press_pos := Vector2.ZERO
var _rmb_press_pos := Vector2.ZERO

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	camera.current = true
	_update_cam()

func toggle_mode() -> void:
	top_down = not top_down
	_update_cam()

func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1
	if move != Vector3.ZERO:
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		focus += basis * move.normalized() * dist * 0.7 * delta
		focus = G.world.clamp_pos(focus) if G.world != null else focus
	if Input.is_key_pressed(KEY_Q):
		yaw += 60.0 * delta
	if Input.is_key_pressed(KEY_E):
		yaw -= 60.0 * delta
	_update_cam()

func _update_cam() -> void:
	var p := -85.0 if top_down else pitch
	var rot := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(p))
	camera.position = focus + rot * Vector3(0, 0, dist)
	camera.look_at_from_position(camera.position, focus, Vector3.UP)

func mouse_to_ground(mpos: Vector2) -> Variant:
	var ro := camera.project_ray_origin(mpos)
	var rd := camera.project_ray_normal(mpos)
	if absf(rd.y) < 0.0001:
		return null
	var t := -ro.y / rd.y
	if t < 0.0:
		return null
	var hit := ro + rd * t
	return G.world.clamp_pos(hit)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					dist = clampf(dist * 0.9, 8.0, 260.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					dist = clampf(dist * 1.1, 8.0, 260.0)
			MOUSE_BUTTON_MIDDLE:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				if mb.pressed:
					_rmb_press_pos = mb.position
				elif mb.position.distance_to(_rmb_press_pos) < 6.0:
					# right-click: cancel god tool / deselect
					if G.god.active():
						G.god.cancel()
					else:
						G.main.select(null)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press_pos = mb.position
				elif mb.position.distance_to(_press_pos) < 6.0:
					var ground = mouse_to_ground(mb.position)
					if ground != null:
						if G.god.active():
							G.god.ground_click(ground)
						else:
							G.main.select_at(ground)
		_update_cam()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _orbiting:
			yaw -= mm.relative.x * 0.35
			pitch = clampf(pitch + mm.relative.y * 0.25, -85.0, -15.0)
			_update_cam()
		elif _panning:
			var basis := Basis(Vector3.UP, deg_to_rad(yaw))
			focus += basis * Vector3(-mm.relative.x, 0, -mm.relative.y) * dist * 0.0016
			if G.world != null:
				focus = G.world.clamp_pos(focus)
			_update_cam()
