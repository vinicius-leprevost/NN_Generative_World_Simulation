extends Node
## SaveMgr: JSON persistence with multiple slots, versioning,
## automatic .bak backups and corrupted-save recovery.
## Slot 0 is reserved for autosave.

const SAVE_DIR := "user://saves"
const VERSION := 1
const SLOTS := 6

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func slot_path(i: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, i]

func save_slot(i: int) -> bool:
	if G.main == null:
		return false
	var d: Dictionary = G.main.collect_state()
	d["version"] = VERSION
	d["saved_at"] = Time.get_datetime_string_from_system()
	var txt := JSON.stringify(d)
	var path := slot_path(i)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Events.add("system", "Save failed: cannot write %s" % path)
		return false
	f.store_string(txt)
	f.close()
	Events.add("system", "World saved to slot %d" % i)
	return true

func load_slot(i: int) -> bool:
	var path := slot_path(i)
	var d = _read_save(path)
	if d == null:
		d = _read_save(path + ".bak")
		if d != null:
			Events.add("system", "Primary save corrupted; loaded backup for slot %d" % i)
	if d == null:
		Events.add("system", "Load failed: slot %d missing or corrupted" % i)
		return false
	var ver := int(d.get("version", 0))
	if ver > VERSION:
		Events.add("system", "Load failed: save version %d is newer than app" % ver)
		return false
	G.main.apply_state(d)
	Events.add("system", "World loaded from slot %d" % i)
	return true

func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if d == null or not (d is Dictionary):
		return null
	return d

func slot_info() -> Array:
	var out: Array = []
	for i in range(SLOTS):
		var path := slot_path(i)
		var info := {"slot": i, "exists": FileAccess.file_exists(path), "saved_at": ""}
		if info["exists"]:
			var d = _read_save(path)
			if d != null:
				info["saved_at"] = str(d.get("saved_at", "?"))
		out.append(info)
	return out
