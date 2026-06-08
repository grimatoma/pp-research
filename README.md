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

**Feature-complete vertical slice of the full PP2 loop** — economy, military,
multi-island world, and the roguelite prestige meta all wired together and
validated by a headless end-to-end playthrough test. Highlights:

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
- **Creativity research (M9)** — population generates Creativity (decoupled from
  luxuries, so it never stalls); spend it on a tree of perks that boost the economy
  (production multipliers, Coin tax, build-cost reductions, +Creativity) plus a
  repeatable Infinite tree. Perks gate by reached tier; full HUD panel.
- **Military & expeditions (M8)** — satisfied houses muster Militia; weapon smiths +
  training grounds trade militia & weapons up the unit ladder; Orc forts block buildable
  land until conquered. Send an army and the battle resolves over wall-clock time via a
  deterministic resolver (strike phases, Ranged/Flank, Splash/Trample, Bulletproof/Spiky,
  and boss Armageddon/Lightning/Revive/Summon). Clearing a warchief grants Cartography.
- **Multi-island world (M6/M7)** — spend Cartography to charter procedural islands across
  climate regions (temperate/tropical/northern, research-gated); conquer them, then keep &
  settle, hand to the Paragons for Favor, or turn in for Coin. Ships run trade routes that
  move goods (never people) between islands — so a Merchant city must import tropical
  coffee/sugar, exactly as PP2 intends.
- **Prestige roguelite (M10)** — grow ~30 Paragons, found a Palace, and complete its five
  Favor-fuelled stages for a permanent Reputation point. Reputation (saved to a meta file
  that survives restarts) unlocks Custodians — run-modifiers you pick at New Game+.

The DLC magic track (Mana/Elder Mana), distinct Northern production chains, the 12
Challenges, and per-region tilesets remain as future polish.

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
godot --headless --path . --script res://tests/run_economy_tests.gd     # economy/world/prestige (exit 0/1)
godot --headless --path . --script res://tests/run_combat_tests.gd      # combat resolver (exit 0/1)
godot --headless --path . --script res://tests/run_playthrough_test.gd  # full end-to-end loop (exit 0/1)
```

## Tests

- `tests/run_economy_tests.gd` — 109 checks: catalog integrity, the cascade invariant,
  production + input consumption, connectivity gating, growth/emigration, coin payout,
  the upgrade gate, save round-trip, offline-catch-up determinism, deterministic mapgen,
  Creativity research, **the whole production tree being producible to Paragons**,
  recruitment, Orc-camp generation/blocking, expeditions & warchief rewards, Cartography
  discovery, region gating, settle/handover/turn-in, trade routes, and the Palace →
  Reputation → Custodian → New Game+ prestige loop.
- `tests/run_combat_tests.gd` — 22 checks: golden determinism (incl. with boss abilities),
  win-on-mutual-death, ranged protection, stronger-army-wins, the duration formula, and
  Trample/Bulletproof resolution.
- `tests/run_playthrough_test.gd` — 19 checks: one WorldSim driven through the *entire*
  game loop (economy → recruit → conquer → Cartography → discover → settle → trade →
  Paragons → Palace → Reputation → New Game+) to prove the systems compose.
