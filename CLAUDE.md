# CLAUDE.md — Pioneer Isles

Guidance for AI agents working in this repo. A Godot 4 / GDScript clone of *Paragon
Pioneers 2* (idle Anno-like settlement builder). System parity with PP2 is the goal.

## Mental model (read first)

The architecture deliberately follows the spec's "**const catalogs + one mutable world
object, not many singletons**" — which also makes the whole sim **unit-testable headless**.

- **`Database`** (`scripts/autoload/Database.gd`) — a static `class_name`, *not* an
  autoload. Holds all goods / buildings / recipes / population tiers, built once at class
  load (`_static_init`). Access statically: `Database.building("fishery")`,
  `Database.tier("pioneers")`. All balance numbers are transcribed from
  `docs/pp2-spec-extract.json` (the research teardown). Invented numbers are commented
  `CHOSEN DEFAULT`.
- **`WorldSim`** (`scripts/WorldSim.gd`) — a plain `RefCounted` object (not an autoload)
  holding the live world: islands, stockpiles, currencies, population, clock. The
  deterministic 5-phase tick lives in `advance(dt)`. Has its own signals.
- **`Game`** (`scripts/autoload/Game.gd`) — **the one autoload**. Owns a `WorldSim`,
  ticks it each frame, autosaves, handles app lifecycle. UI reads `Game.sim` and connects
  to `Game.sim`'s signals.
- **Presentation** (`scenes/*`) reads the sim and renders it; it never owns game state.

Because `Database` and `WorldSim` need no autoloads, `tests/run_economy_tests.gd`
(`extends SceneTree`) can build a world and assert on it headless.

## The core mechanic (don't break these)

- **The luxury cascade**: a tier's `luxury_needs` are exactly the next tier's
  `basic_needs` — same good *and* per-resident rate. Encoded once in `Database._build_tiers`
  and golden-asserted in `Database._assert_cascade` (Hat is the one terminal exception).
- **Consumption** is `1 unit / N seconds` per resident; `N` is authoritative game data —
  transcribe exactly, never invent.
- **5-phase tick order** (fixed, in `WorldSim._tick`): connectivity → production →
  consumption → population → payout. `advance(a)+advance(b) == advance(a+b)` (offline
  catch-up correctness) — preserve this.
- **Range logistics, no roads**: a building works only within Chebyshev `storage_range`
  of a storage building (`WorldSim._recompute_connectivity`).

## Commands

```bash
godot --path . --import                                              # register class_names (first run / after new scripts)
godot --path .                                                       # play
godot --headless --path . --script res://tests/run_economy_tests.gd     # economy/world/prestige, exit 0/1
godot --headless --path . --script res://tests/run_combat_tests.gd      # combat resolver, exit 0/1
godot --headless --path . --script res://tests/run_playthrough_test.gd  # full end-to-end loop, exit 0/1
godot --path . -- --capture                                          # windowed: build demo, screenshot → docs/screenshot.png
```

**Run the `--script` test, not just `--import`, to catch compile errors** — `--import`
registers `class_name`s but does not deep-compile method bodies, so type-inference errors
inside functions only surface when a script is actually loaded by a test run.

Godot 4.6 lives at `C:/Users/grima/Documents/VoidYield/Godot_v4.6.2-stable_win64_console.exe`
on this machine (console build → stdout).

**Always run the economy tests after touching `Database`, `WorldSim`, `Island`, or
`MapGen`.** Add a check to `tests/run_economy_tests.gd` for any new sim behavior.

## Where to look

| Task | File |
|---|---|
| Add/tune a good, building, recipe, or tier | `scripts/autoload/Database.gd` |
| Change the production/consumption/population math | `scripts/WorldSim.gd` |
| Terrain rules / placement legality / stockpile | `scripts/data/Island.gd` |
| Procedural island shape | `scripts/systems/MapGen.gd` |
| Terrain rendering (Wang autotiling) | `scripts/systems/TerrainRenderer.gd` |
| Map rendering / placement & selection input | `scenes/IslandView.gd` |
| HUD (top bar, stockpile, build menu, inspector) | `scenes/HUD.gd` |
| Camera / scene wiring / screenshot harness | `scenes/Main.gd` |

## Art (PixelLab)

Sprites are AI-generated via the PixelLab MCP and saved under `assets/art/`
(`terrain/`, `buildings/`, `characters/`, `ships/`, `goods/`). Buildings reference a
`sprite_path` in `Database`; the renderer falls back to a flat colour swatch when the file
is missing, so the game always runs. Terrain uses the 16-tile Wang autotile sheet
`assets/art/terrain/grass_ocean_tileset.png` (corner→tile map in `TerrainRenderer`).

## Roadmap (per the research spec's milestones)

**All core milestones implemented.** M1 sim core + grid · M2 range logistics · M3
population & cascade · M4 production chains (now complete to Paragons — copper/gold/
grape/paper + tropical imports) · M5 coin economy · M6 ships + trade routes + regions ·
M7 Cartography discovery · M8 full combat + expeditions (recruitment, Orc camps,
army-over-time, warchief→Cartography) · M9 Creativity research · M10 Palace→Reputation→
Custodian prestige (New Game+). The battle resolver handles strike phases, Ranged/Flank,
Splash/Trample, Bulletproof/Spiky, and boss Armageddon/Lightning/Revive/Summon.

Remaining polish (not blockers): distinct northern-region production chains, DLC magic
track (Mana/Elder Mana), the 12 Challenges, bribery/more custodians, per-region tilesets.
See `docs/pp2-spec-extract.json`.

## Systems map (where each milestone lives)

| System | Key code |
|---|---|
| Military units / training / weapons | `Database._build_goods`/`_build_buildings` (military category), `_build_units` |
| Orc camps (block land, conquerable) | `scripts/data/OrcCamp.gd`, `MapGen._add_camps` |
| Expeditions (send army → battle over time) | `WorldSim.send_expedition`/`_advance_expeditions` |
| Multi-island world / discovery / regions | `WorldSim` (discoveries, `start_discovery`, `settle_island`, `handover_to_paragons`) |
| Ships + trade routes | `scripts/data/ShipDef.gd`, `WorldSim.add_trade_route`/`_advance_trade` |
| Palace / Reputation / Custodians | `scripts/data/CustodianDef.gd`, `WorldSim` (palace + prestige), `SaveManager` meta |
| UI panels (World/Military/Prestige) | `scenes/HUD.gd` |

## Engineering rules

- No fakes/stubs in shipped code — wire real implementations. Test-only scaffolding lives
  in `tests/`.
- Keep balance numbers sourced from `docs/pp2-spec-extract.json`; mark any invented value
  `CHOSEN DEFAULT` with a comment.
- Static typing throughout; doc-comment public funcs with `##` (house style).
