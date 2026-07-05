extends Node
## Events: global event log. Records every major simulation event,
## filterable by type in the UI and persisted in saves.

signal logged(evt: Dictionary)

const MAX_ENTRIES := 3000
const TYPES := ["birth", "death", "survival", "social", "group", "construction",
	"crime", "police", "politics", "economy", "animal", "language", "weather",
	"god", "system"]

var entries: Array = []

func add(type: String, text: String) -> void:
	var day := 0
	var tstr := ""
	if G.clock != null:
		day = G.clock.day
		tstr = "%02d:%02d" % [int(G.clock.hour), int(fmod(G.clock.hour, 1.0) * 60.0)]
	var evt := {"day": day, "time": tstr, "type": type, "text": text}
	entries.append(evt)
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES, entries.size())
	logged.emit(evt)

func clear() -> void:
	entries.clear()

func to_dict() -> Dictionary:
	# persist the most recent slice to keep saves compact
	var keep: Array = entries
	if keep.size() > 800:
		keep = keep.slice(keep.size() - 800, keep.size())
	return {"entries": keep}

func from_dict(d: Dictionary) -> void:
	entries = d.get("entries", [])
	logged.emit({"day": 0, "time": "", "type": "system", "text": "Event log restored"})
