class_name Constants
extends RefCounted
## Global enums and tuning constants for Pioneer Isles (Paragon Pioneers 2 clone).
## Accessed without an autoload via the `class_name`, e.g. `Constants.Terrain.GRASS`.
## Mirrors the data-driven spec in docs/SPEC.html.

## Terrain types a build tile can have. Buildings declare a required terrain
## (see BuildingDef.terrain_req). RIVER tiles are the "straight river spot" mills need.
enum Terrain {
	WATER,    ## deep ocean — only coastal/ocean buildings touch it (none placed ON it)
	BEACH,    ## shallow/beach — weirs & salmon farms ("in the water next to the beach")
	GRASS,    ## open plowable ground — farms, houses, most buildings
	FOREST,   ## tree-covered — lumberjack/forester need these
	MOUNTAIN, ## ore & stone deposits — mines, quarries
	RIVER,    ## a straight river spot — sawmill, flour mill, tannery, etc.
}

## Terrain a building can be founded on when its terrain_req is GRASS-like "any land".
const LAND_TERRAINS := [Terrain.GRASS, Terrain.FOREST, Terrain.MOUNTAIN]

## Display tint per terrain — placeholder fills until PixelLab tiles are wired in.
const TERRAIN_COLOR := {
	Terrain.WATER:    Color("2e6fb0"),
	Terrain.BEACH:    Color("e3d09a"),
	Terrain.GRASS:    Color("6fae54"),
	Terrain.FOREST:   Color("3f7d3a"),
	Terrain.MOUNTAIN: Color("8a8273"),
	Terrain.RIVER:    Color("4aa3c4"),
}

const TERRAIN_NAME := {
	Terrain.WATER: "Ocean",
	Terrain.BEACH: "Beach",
	Terrain.GRASS: "Grass",
	Terrain.FOREST: "Forest",
	Terrain.MOUNTAIN: "Mountain",
	Terrain.RIVER: "River",
}

## Pixels per build-grid tile (matches the 32px PixelLab terrain tileset).
const TILE_PX := 32

## Real seconds per simulated game-tick of the economy. PP2 recipes are specified
## in real seconds (ITERATION_TIME), so the sim runs in real-time and we catch up
## elapsed wall-clock on load (idle/offline progression — the core of the genre).
const TICK_SECONDS := 0.25

## Hard cap on offline catch-up applied on load, in seconds (24h). PP2 has no
## efficiency penalty for being away; we just bound the single-frame catch-up cost.
const MAX_OFFLINE_SECONDS := 60.0 * 60.0 * 24.0

## A building needs a storage building (Kontor/warehouse) within this many tiles
## (Chebyshev distance) to be "connected" and operate. No roads — pure proximity.
const DEFAULT_STORAGE_RANGE := 8
