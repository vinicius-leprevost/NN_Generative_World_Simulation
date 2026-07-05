class_name LanguageSystem extends Node3D
## LanguageSystem: sound-based communication that evolves into language.
## People emit sound symbols tied to meanings; listeners interpret them
## through their personal lexicon, learn new associations from context,
## mislearn under noise, and teach each other. Groups fork dialects that
## drift apart in isolation and converge through contact. Animal calls are
## species sounds humans can learn to read as danger signals.

const MEANINGS := ["food_found", "water_found", "danger", "predator", "help",
	"follow_me", "come_home", "work_here", "build_this", "attack", "run",
	"trade", "hungry", "thirsty", "hurt", "trusted", "dangerous_person",
	"leader_command", "police_warning", "gang_signal", "family_call",
	"need_workers", "animal_escaped", "crime_witnessed"]

const CONSONANTS := ["k", "t", "m", "n", "r", "s", "l", "v", "g", "b", "d", "z"]
const VOWELS := ["a", "e", "i", "o", "u"]

var dialects: Dictionary = {}   # id -> {"name", "symbols": {meaning: symbol}, "parent"}
var next_dialect := 1
var base_dialect := -1
var recent: Array = []          # recent sound events for debug/stats
var stats := {"sounds": 0, "success": 0, "fail": 0, "miscomm": 0, "learned": 0,
	"animal_warnings": 0, "parent_transfers": 0, "symbols_created": 0}

var _players: Array = []
var _tones: Dictionary = {}
var _diverge_timer := 0.0

func _ready() -> void:
	for i in range(12):
		var pl := AudioStreamPlayer3D.new()
		pl.max_distance = 60.0
		add_child(pl)
		_players.append(pl)

func setup_base() -> void:
	dialects.clear()
	next_dialect = 1
	base_dialect = new_dialect(-1)
	# the founding population starts with a few primitive shared sounds
	for m in ["danger", "food_found", "water_found", "help"]:
		symbol_for(base_dialect, m)

func gen_symbol() -> String:
	var syllables := Rng.randi_range(2, 3)
	var parts: Array = []
	for i in range(syllables):
		parts.append(str(Rng.pick(CONSONANTS)) + str(Rng.pick(VOWELS)))
	stats["symbols_created"] += 1
	return "-".join(parts)

func new_dialect(parent := -1) -> int:
	var symbols := {}
	if parent >= 0 and dialects.has(parent):
		# fork: inherit the parent tongue, mutate a little
		for m in dialects[parent]["symbols"].keys():
			if Rng.chance(0.85):
				symbols[m] = dialects[parent]["symbols"][m]
	var d := {"name": "Dialect %d" % next_dialect, "symbols": symbols, "parent": parent}
	dialects[next_dialect] = d
	var id := next_dialect
	next_dialect += 1
	if parent >= 0:
		Events.add("language", "A new dialect formed (%s)" % d["name"])
	return id

func dialect_of(p) -> int:
	for gid in p.group_ids:
		var g = G.groups.get_group(gid)
		if g != null and int(g.get("dialect", -1)) >= 0:
			return int(g["dialect"])
	return base_dialect

func symbol_for(dialect_id: int, meaning: String) -> String:
	if not dialects.has(dialect_id):
		dialect_id = base_dialect
	var d: Dictionary = dialects[dialect_id]
	if d["symbols"].has(meaning):
		return d["symbols"][meaning]
	var sym := gen_symbol()
	d["symbols"][meaning] = sym
	Events.add("language", "New sound symbol '%s' now means '%s'" % [sym, meaning])
	return sym

# ---------------- Human speech ----------------

func speak(p, meaning: String, urgent := false) -> void:
	stats["sounds"] += 1
	var did := dialect_of(p)
	# prefer a symbol the speaker personally knows for this meaning
	var symbol := ""
	var best_conf := 0.0
	for sym in p.lexicon.keys():
		var e: Dictionary = p.lexicon[sym]
		if e["m"] == meaning and e["c"] > best_conf:
			best_conf = e["c"]
			symbol = sym
	if symbol == "":
		symbol = symbol_for(did, meaning)
		p.lexicon[symbol] = {"m": meaning, "c": 0.6}
	var radius := Params.get_p("nn.comm_radius") * Params.get_p("aud.radius_mult")
	if urgent:
		radius *= 1.5
	var evt := {"symbol": symbol, "meaning": meaning, "speaker": p.id,
		"pos": p.position, "radius": radius, "urgent": urgent,
		"dialect": did, "t": G.clock.total_time, "kind": "human", "ok": 0, "fail": 0}
	recent.append(evt)
	_play_tone(p.position, 1.0 + (0.4 if p.sex == "f" else 0.0) + (0.8 if p.age < 13.0 else 0.0),
		Params.get_p("aud.human_vol") * (1.3 if urgent else 0.8))
	for listener in G.people.nearby(p.position, radius, p.id):
		listener.on_hear(evt)

func process_hearing(listener, evt: Dictionary) -> void:
	var symbol: String = evt["symbol"]
	var meaning: String = evt["meaning"]
	var entry = listener.lexicon.get(symbol)
	var understood := false
	var reacted_meaning := meaning
	var learn_mult := Params.get_p("nn.lang_learn") * Params.get_p("aud.lang_speed")
	if entry != null:
		if entry["m"] == meaning:
			entry["c"] = minf(entry["c"] + 0.05 * learn_mult, 1.0)
			understood = true
		else:
			# the listener believes this sound means something else
			if Rng.chance(Params.get_p("aud.miscomm") + 0.15):
				understood = true
				reacted_meaning = entry["m"]
				stats["miscomm"] += 1
				evt["fail"] += 1
				if Rng.chance(0.08):
					Events.add("language", "%s misunderstood '%s'" % [listener.pname, symbol])
			else:
				entry["c"] -= 0.12
				if entry["c"] <= 0.05:
					listener.lexicon[symbol] = {"m": meaning, "c": 0.2}
					stats["learned"] += 1
	else:
		# learn a brand-new association from context
		var speaker = G.people.get_person(evt["speaker"])
		var familiarity := 0.0
		if speaker != null:
			familiarity = clampf(listener.rel(speaker.id) / 100.0, 0.0, 1.0) * 0.3
		var pr: float = learn_mult * 0.25 * (0.25 + listener.traits["intelligence"] * 0.4
			+ listener.education * 0.003 + listener.skills.get("language", 0.0) * 0.4 + familiarity)
		if evt["urgent"]:
			pr *= 1.6  # urgent context makes meaning clearer
		if Rng.chance(pr):
			listener.lexicon[symbol] = {"m": meaning, "c": 0.3}
			stats["learned"] += 1
	if understood:
		stats["success"] += 1
		evt["ok"] += 1
		listener.react_to_meaning(reacted_meaning, evt)
		# shared-language convergence: adopted words spread between dialects
		if Rng.chance(Params.get_p("aud.shared_lang_speed") * 0.02):
			var did := dialect_of(listener)
			if did != int(evt["dialect"]) and dialects.has(did):
				dialects[did]["symbols"][meaning] = symbol
	else:
		stats["fail"] += 1
		evt["fail"] += 1

func school_teach(student, school) -> void:
	# schools spread the local dialect systematically
	if school.worker_count("teacher") == 0:
		return
	var did := dialect_of(student)
	var d: Dictionary = dialects.get(did, dialects.get(base_dialect, {}))
	if d.is_empty() or d["symbols"].is_empty():
		return
	var meaning: String = Rng.pick(d["symbols"].keys())
	var symbol: String = d["symbols"][meaning]
	var entry = student.lexicon.get(symbol)
	if entry != null and entry["m"] == meaning:
		entry["c"] = minf(entry["c"] + 0.15, 1.0)
	else:
		student.lexicon[symbol] = {"m": meaning, "c": 0.5}
		stats["learned"] += 1

# ---------------- Animal calls ----------------

func animal_call(a, kind: String) -> void:
	var radius := 10.0
	var vol := 0.5
	match kind:
		"warning", "attack":
			radius = 22.0
			vol = 1.0
		"fear":
			radius = 16.0
			vol = 0.8
		"hunger":
			radius = 8.0
	radius *= Params.get_p("aud.radius_mult")
	var evt := {"symbol": "%s-%s" % [a.species, kind], "meaning": kind, "speaker": -1,
		"pos": a.position, "radius": radius, "urgent": kind != "idle",
		"dialect": -1, "t": G.clock.total_time, "kind": "animal", "ok": 0, "fail": 0}
	recent.append(evt)
	_play_tone(a.position, a.def["pitch"], Params.get_p("aud.animal_vol") * vol)
	if kind == "idle":
		return
	for person in G.people.nearby(a.position, radius):
		person.hear_animal(a, kind)
	# herd/pack panic propagation
	if kind == "fear" or kind == "attack":
		for other in G.animals.nearby(a.position, radius):
			if other.id != a.id and other.species == a.species:
				other.fear = 1.0

# ---------------- Evolution ----------------

func tick(dt: float) -> void:
	var now: float = G.clock.total_time
	while recent.size() > 0 and now - recent[0]["t"] > 3.0:
		recent.pop_front()
	while recent.size() > 250:
		recent.pop_front()
	_diverge_timer += dt
	if _diverge_timer >= 25.0:
		_diverge_timer = 0.0
		_dialect_drift()

func _dialect_drift() -> void:
	var rate := Params.get_p("nn.dialect_diverge") * Params.get_p("aud.dialect_speed") * 0.12
	for did in dialects.keys():
		if did == base_dialect:
			continue
		var d: Dictionary = dialects[did]
		if d["symbols"].is_empty() or not Rng.chance(rate):
			continue
		var meaning: String = Rng.pick(d["symbols"].keys())
		d["symbols"][meaning] = gen_symbol()
		if Rng.chance(0.25):
			Events.add("language", "%s drifted: new word for '%s'" % [d["name"], meaning])

# ---------------- Stats helpers ----------------

func success_rate() -> float:
	var total: int = stats["success"] + stats["fail"]
	if total == 0:
		return 0.0
	return float(stats["success"]) / total * 100.0

func avg_lexicon_size() -> float:
	var people: Array = G.people.alive_list()
	if people.is_empty():
		return 0.0
	var sum := 0
	for p in people:
		sum += p.lexicon.size()
	return float(sum) / people.size()

func dialect_summary() -> Array:
	var out: Array = []
	for did in dialects.keys():
		var d: Dictionary = dialects[did]
		out.append({"id": did, "name": d["name"], "words": d["symbols"].size(),
			"base": did == base_dialect})
	return out

func most_used_meanings() -> Array:
	var counts := {}
	for evt in recent:
		if evt["kind"] == "human":
			counts[evt["meaning"]] = int(counts.get(evt["meaning"], 0)) + 1
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	return keys.slice(0, 5)

# ---------------- Audio ----------------

func _make_tone(freq: float) -> AudioStreamWAV:
	var mix_rate := 22050
	var length := 0.14
	var n := int(mix_rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / mix_rate
		var envelope := sin(PI * float(i) / n)  # fade in/out
		var v := int(sin(TAU * freq * t) * envelope * 12000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav

func _play_tone(pos: Vector3, pitch: float, vol: float) -> void:
	if Params.get_p("aud.mute") > 0.5:
		return
	var master := Params.get_p("aud.master")
	if master <= 0.01 or vol <= 0.01:
		return
	var freq := clampf(220.0 * pitch, 80.0, 1400.0)
	var key := int(freq / 40.0)
	if not _tones.has(key):
		_tones[key] = _make_tone(key * 40.0)
	for pl in _players:
		if not pl.playing:
			pl.stream = _tones[key]
			pl.position = pos + Vector3(0, 1.5, 0)
			pl.volume_db = linear_to_db(clampf(vol * master, 0.02, 1.0))
			pl.play()
			return

func shutdown_audio() -> void:
	for pl in _players:
		if pl != null and is_instance_valid(pl):
			pl.stop()
			pl.stream = null
	_tones.clear()

# ---------------- Persistence ----------------

func clear_all() -> void:
	shutdown_audio()
	dialects.clear()
	recent.clear()
	next_dialect = 1
	base_dialect = -1
	for k in stats.keys():
		stats[k] = 0

func to_dict() -> Dictionary:
	var dser := {}
	for did in dialects.keys():
		dser[str(did)] = dialects[did]
	return {"dialects": dser, "next_dialect": next_dialect,
		"base_dialect": base_dialect, "stats": stats}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_dialect = int(d.get("next_dialect", 1))
	base_dialect = int(d.get("base_dialect", -1))
	var s: Dictionary = d.get("stats", {})
	for k in s.keys():
		stats[k] = int(s[k])
	for k in d.get("dialects", {}).keys():
		var dd: Dictionary = d["dialects"][k]
		dd["parent"] = int(dd.get("parent", -1))
		dialects[int(k)] = dd
	if base_dialect < 0 or not dialects.has(base_dialect):
		setup_base()
