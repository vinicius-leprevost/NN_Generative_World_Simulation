extends Node
## G: global system registry. Populated by main.gd at startup.
## Every system talks to the others through this node, which keeps the
## script dependency graph acyclic (no cross class_name references).

var main = null          # Main (root)
var world = null         # WorldManager
var clock = null         # TimeSystem
var weather = null       # WeatherSystem
var people = null        # PersonManager
var animals = null       # AnimalManager
var buildings = null     # BuildingManager
var vehicles = null      # VehicleSystem
var economy = null       # EconomySystem
var groups = null        # GroupSystem
var language = null      # LanguageSystem
var crime = null         # CrimeSystem
var politics = null      # PoliticsSystem
var stats = null         # StatsSystem
var god = null           # GodTools
var cam = null           # CameraRig
var ui = null            # UIManager
var dbg = null           # DebugOverlay

# Performance preset knobs (set by Main.apply_preset)
var perf := {
	"name": "Medium",
	"ai_mult": 1.0,        # multiplier on neural decision interval
	"label_dist": 70.0,    # max camera distance at which 3D labels show
	"max_lights": 12,      # max simultaneously active street lights
	"dashboard_hz": 1.0,   # dashboard refresh rate
}

func ready_all() -> bool:
	return main != null and people != null and buildings != null
