# Pioneer Isles

A **Godot 4 / GDScript clone of *Paragon Pioneers 2*** — the idle, Anno-like island
settlement builder. Built for the aiDev portfolio (game #2). The goal is *system
parity* with PP2, not engine parity: the luxury-cascade economy, range/warehouse
logistics (no roads), branching production chains, idle/offline progression, and the
seven-tier population ladder.

Derived from the research spec at
[`docs/pp2-spec-extract.json`](docs/pp2-spec-extract.json) (a structured teardown of
the original game). Art is generated with [PixelLab](https://pixellab.ai).

## Status

Playable temperate-region vertical slice:

- **Procedural islands** — seeded `MapGen` (grass / beach / ocean / forest / mountain /
  river). Deterministic for a fixed seed.
- **Build grid** — square, whole-tile footprints with terrain placement rules (forest
  for lumberjacks, mountains for mines, *straight river spots* for mills, coast for the
  Kontor). No rotation, no roads.
- **Range logistics** — buildings operate only within Chebyshev range of a storage
  building (Kontor / Warehouse), which holds the shared island stockpile.
- **Production chains** — ~35 buildings, single-output recipes with verbatim PP2
  iteration times and input ratios (fish, wood→plank, apple→cider, pig→sausage,
  wheat→flour→bread, yarn→fabric, cattle→tallow + wood→potash→soap, hops/malt→beer,
  hide+salt→leather, ore→ingot→tools, …).
- **The luxury cascade** — the heart of PP2: each tier's *luxuries* are exactly the next
  tier's *basics* (same good **and** per-resident rate). Pioneers → Colonists → Townsmen
  → Merchants → Paragons. Encoded once and golden-asserted.
- **Population** — houses grow with met basics, emigrate when starved (never die/revolt),
  pay Coin scaled by luxury satisfaction, and *ascend a tier in place* when full and fully
  supplied. Paragons emit Favor.
- **Idle / offline** — the sim is `advance(Δt)` with `advance(a)+advance(b) == advance(a+b)`,
  so closing the game and returning simulates the elapsed wall-clock.
- **Save/load** — versioned JSON; offline catch-up applied on load.

Combat (auto-battle Orcs), ships/trade-routes, Cartography discovery, the Creativity
research trees, and the Palace→Reputation→Custodian prestige loop are specced in the
research doc and scaffolded for later milestones.

## Architecture

Matches the spec's "const catalogs + one mutable world object, not many singletons":

| Layer | File(s) | Role |
|---|---|---|
| **Constants** | `scripts/Constants.gd` | terrain enum, tuning constants (`class_name`) |
| **Data defs** | `scripts/data/*.gd` | `GoodDef`, `RecipeDef`, `BuildingDef`, `PopTierDef`, `Island`, `PlacedBuilding` |
| **Catalog** | `scripts/autoload/Database.gd` | static `class_name` — goods/buildings/recipes/tiers, built at load |
| **Sim core** | `scripts/WorldSim.gd` | the mutable world + deterministic 5-phase tick (plain object, testable headless) |
| **Map gen** | `scripts/systems/MapGen.gd` | seeded island generation |
| **Engine glue** | `scripts/autoload/Game.gd` | the one autoload — owns `WorldSim`, ticks it, save/load |
| **Persistence** | `scripts/autoload/SaveManager.gd` | versioned JSON, discard-on-mismatch |
| **Presentation** | `scenes/*` | island view, HUD, build menu (read the sim, never own state) |

`Database` and `WorldSim` are reachable headless (no autoload dependency), so the whole
economy is unit-testable.

## Running

Open `project.godot` in **Godot 4.6+**, or:

```bash
godot --path . --import                                  # first time: register classes
godot --path .                                           # play
godot --headless --path . --script res://tests/run_economy_tests.gd   # run tests (exit 0/1)
```

## Tests

`tests/run_economy_tests.gd` — 28 headless checks: catalog integrity, the cascade
invariant, production + input consumption, connectivity gating, growth/emigration, coin
payout, the upgrade gate, save round-trip, offline-catch-up determinism, and deterministic
mapgen.
