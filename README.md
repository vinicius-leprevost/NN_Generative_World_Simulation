# Genesis Biosphere Simulator

A 3D top-down emergent artificial-life sandbox for **Godot 4.4.1** (GDScript,
Vulkan Forward+, native Windows). People and animals start with almost
nothing and must survive: find water and food, build shelter, invent
language, form families, work, trade, hunt, farm, commit crimes, police
themselves, and grow a civilization — while you watch and intervene as God.

---

## Requirements

- **Godot 4.4.1 stable** (standard build, not .NET) — https://godotengine.org/download
- Windows 10/11, any Vulkan-capable GPU (AMD, NVIDIA, Intel). No CUDA, no
  vendor-specific features are used.

## Opening the project

1. Install/unzip Godot 4.4.1.
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** (or the Play button). The main scene is `scenes/main.tscn`.

First import takes a few seconds while Godot builds its cache (`.godot/`).

## Running the simulation

A new world is generated automatically: terrain, a lake, a river, wild food,
a predator zone (wolves + a bear), and a founding population of people,
chickens, cows, sheep, deer and dogs.

### Camera

| Input | Action |
|---|---|
| `W A S D` / arrows | Pan |
| Mouse wheel | Zoom in/out |
| Middle-drag | Orbit (rotate/tilt) |
| Right-drag | Pan |
| `Q` / `E` | Rotate |
| `T` | Toggle strict top-down / orbit view |
| Left-click | Select person / animal / building / site |
| Right-click | Cancel god tool / deselect |

### Simulation control

| Input | Action |
|---|---|
| `Space` | Pause / resume |
| `N` | Step one tick while paused |
| `+` / `-` | Double / halve simulation speed |
| `G` | God control panel |
| `L` | Event log |
| `F3` | Debug overlay (goals, sound radii, hotspots, territories) + perf stats |
| `F5` / `F9` | Quick save / quick load (slot 1) |
| `Esc` | Cancel tool / deselect |

## God Mode

Open the **God Panel** (`G`). Tabs:

- **Actions** — spawn tools. Click a button, then left-click the terrain:
  spawn people, spawn any of 10 animal species, place buildings instantly or
  as construction sites (22 building types), draw roads and rivers
  (two-click), place lakes, wild food, and zones (predator / livestock /
  hunting / restricted / crime / community). Time-of-day, weather, and
  disaster (drought/flood) controls live here too, plus New World and 3
  manual save/load slots.
- **World / Population / Neural / Economy / Society / Construction /
  Animals / Audio & Language** — ~100 live-tunable parameters (hunger rate,
  aging speed, crime multiplier, language learning speed, wages, prison
  capacity, dialect divergence, predator danger…). Every slider takes
  effect immediately and is saved with the world.
- **Dashboard** — live statistics: population by life stage, society,
  economy, construction, crime, politics, water, animals, language, food,
  and simulation health.

Select any entity (left-click) to open the **inspector**: full internal
state (needs, traits, skills, memory, known language symbols, brain
weights) plus god actions — kill, revive, heal, sicken, give/take money,
edit traits, tame/wild animals, feed, demolish, boost construction.

## How the simulation works (short version)

- **People** are autonomous agents with needs (hunger, thirst, energy,
  health), traits, skills, memory, and relationships. A neural-style brain
  scores ~20 candidate actions from weighted inputs with exploration noise;
  weights mutate at birth (inherited from both parents) and are reinforced
  by lived outcomes.
- **Language** starts as a few primitive shared sounds. Speaking emits a
  sound event with a symbol; listeners in radius interpret it through
  their personal lexicon, learn new associations from context, mislearn
  (miscommunication), and teach children/students. Groups fork dialects
  that drift in isolation and converge on contact.
- **Animals** use the same agent framework with species instincts:
  herbivores graze, herd, and flee; predators hold territory and hunt prey,
  livestock, and (rarely) humans; dogs bond, follow, and bark warnings that
  humans learn to read; livestock produce eggs/milk when fed.
- **Society** emerges: jobs and wages, stores and markets, families and
  children, communities, gangs, hunting groups, police and prisons,
  elections, public projects, corruption, laws.
- The **construction planner** watches society's needs (homeless, hunger,
  water distance, crime, sickness, predators, darkness) and starts sites;
  people join as workers; sites show name, %, ETA, worker counts, and
  status above them.

## Saving & loading

- Full world state persists: people (including memories, lexicons and brain
  weights), animals, buildings, sites, roads, cars, groups, dialects,
  economy, crime, politics, weather, time, RNG state, all god parameters,
  and the event log.
- Saves are JSON in `%APPDATA%\Godot\app_userdata\Genesis Biosphere Simulator\saves\`
  (`user://saves/`). Slot 0 = autosave (every 3 in-game days), slots 1–3 in
  the UI, up to 6 total. Every save writes a `.bak` backup; corrupted saves
  fall back to the backup automatically. Saves are versioned.

## Exporting to Windows

1. Editor → **Editor → Manage Export Templates** → download templates for 4.4.1.
2. **Project → Export… → Add → Windows Desktop**.
3. Leave the renderer as Forward+ (project default). Export the `.exe`.

## Performance presets

Top bar dropdown: **Low / Medium / High / Sim-heavy / Visual-heavy**.
They trade render scale, MSAA, shadows, active street-light count, label
draw distance, dashboard refresh, and AI decision frequency. *Sim-heavy*
minimizes visuals and makes minds think more often; *Visual-heavy* is the
opposite.

Under the hood: hash-grid spatial partitioning for all agent queries,
staggered per-agent decision ticks, MultiMesh roads, pooled audio players,
capped light budgets, and distance-culled labels.

## Survival balance

The default parameters are calibrated so a 14-person founding colony
survives, grows, and builds through its first generations while still
feeling fragile (droughts, predators, disease and old age all kill).
The key difficulty knobs, all in the God panel:

- **Population tab** — Hunger Rate / Thirst Rate (0.15 / 0.26 by default),
  Aging Speed (1.5 yrs per game day), Child Growth Speed, Disease Chance.
- **World tab** — Resource Availability, Land Fertility, Disaster Frequency.
- **Animals tab** — Predator Danger, Animal Spawn/Reproduction rates.

Turn hunger/thirst up for a brutal survival scenario; turn disaster
frequency up for droughts and floods; drop Land Fertility to force
migration toward the river.

## Headless smoke test (for development)

```
Godot_v4.4.1-stable_win64_console.exe --headless --path . -- --smoke
```

`--smoke` runs a deterministic seed at 20x speed, exercises save+load in
slot 5, prints `SMOKE:` status lines (population, deaths by cause,
buildings, dialects, average vitals), and exits after the 2600-frame report.
Useful to verify the simulation is healthy after code changes without
opening the editor.

## Troubleshooting (Vulkan / AMD)

- **Black screen or crash at startup** — update the AMD Adrenalin driver;
  Vulkan Forward+ needs a current driver.
- **Still failing** — force the compatibility renderer to test:
  run `godot.exe --rendering-method mobile --path .` or
  `--rendering-driver opengl3`. If that works, the issue is the Vulkan
  driver, not the project.
- **Low FPS** — pick the *Low* or *Sim-heavy* preset, reduce simulation
  speed, and turn the day length up (fewer transitions). Street lights are
  the biggest GPU cost: the preset caps how many shine at once.
- **AMD-specific flicker** — disable MSAA (Low preset) and/or set
  `rendering/anti_aliasing/quality/msaa_3d=0` in `project.godot`.

## Project structure

```
project.godot            Godot 4.4.1 config (Forward+, autoloads)
scenes/main.tscn         single scene; everything else is built in code
scripts/core/            Params, Rng, Names, G (registry), Events, SaveMgr, Vis, SpatialGrid
scripts/data/            SpeciesDB, BuildingDB
scripts/agents/          Person, PersonBrain, Animal
scripts/systems/         Time, Weather, World, PersonManager, AnimalManager,
                         BuildingManager, Vehicles, Economy, Groups, Language,
                         Crime, Politics, Stats
scripts/world/           Building, ConstructionSite, CameraRig, GodTools, DebugOverlay
scripts/ui/              UIManager (HUD, God panel, dashboard, event log, inspector)
saves/                   (in-project placeholder; real saves go to user://saves)
```

Every system is a separate node registered on the `G` autoload — add a new
system by creating a class, instancing it in `main.gd`, and (optionally)
adding params to `sim_params.gd`; the God panel UI generates itself.
