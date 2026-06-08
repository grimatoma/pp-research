class_name TerrainRenderer
extends RefCounted
## Bakes an Island's terrain into a single texture using corner-based (dual-grid)
## Wang autotiling, so coastlines get the sandy beach transition automatically.
## The 16-tile atlas is the PixelLab tileset at assets/art/terrain/grass_ocean_tileset.png.
##
## Corner mask convention: bit 0 = NW, 1 = NE, 2 = SW, 3 = SE; set bit = land (grass),
## clear bit = water. Region table transcribed from the tileset metadata.

const TILE := 32
const ATLAS_PATH := "res://assets/art/terrain/grass_ocean_tileset.png"

# mask (NW|NE<<1|SW<<2|SE<<3) -> source pixel position in the 128×128 atlas.
const MASK_REGION := {
	0: Vector2i(64, 32), 1: Vector2i(32, 32), 2: Vector2i(64, 0), 3: Vector2i(96, 0),
	4: Vector2i(64, 64), 5: Vector2i(32, 0), 6: Vector2i(0, 32), 7: Vector2i(32, 96),
	8: Vector2i(96, 32), 9: Vector2i(64, 96), 10: Vector2i(96, 64), 11: Vector2i(0, 0),
	12: Vector2i(32, 64), 13: Vector2i(0, 64), 14: Vector2i(96, 96), 15: Vector2i(0, 96),
}

static var _atlas_img: Image

static func _atlas() -> Image:
	if _atlas_img == null and ResourceLoader.exists(ATLAS_PATH):
		var tex: Texture2D = load(ATLAS_PATH)
		_atlas_img = tex.get_image()
		if _atlas_img.is_compressed():
			_atlas_img.decompress()
		_atlas_img.convert(Image.FORMAT_RGBA8)
	return _atlas_img

static func _is_land(isl: Island, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= isl.width or y >= isl.height:
		return false
	return isl.get_terrain(Vector2i(x, y)) != Constants.Terrain.WATER

## Bake the whole island terrain. The returned texture should be shown with a
## Sprite2D that has centered=false and position (-TILE/2, -TILE/2) so that logical
## cell (x,y) lands at world rect [x*TILE, (x+1)*TILE].
static func bake(isl: Island) -> ImageTexture:
	var atlas := _atlas()
	var w := (isl.width + 1) * TILE
	var h := (isl.height + 1) * TILE
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	if atlas == null:
		# Fallback: flat colours (atlas not imported yet).
		_bake_flat(isl, img)
		return ImageTexture.create_from_image(img)
	for j in range(isl.height + 1):
		for i in range(isl.width + 1):
			var nw := 1 if _is_land(isl, i - 1, j - 1) else 0
			var ne := 1 if _is_land(isl, i, j - 1) else 0
			var sw := 1 if _is_land(isl, i - 1, j) else 0
			var se := 1 if _is_land(isl, i, j) else 0
			var mask := nw | (ne << 1) | (sw << 2) | (se << 3)
			var src: Vector2i = MASK_REGION[mask]
			img.blit_rect(atlas, Rect2i(src, Vector2i(TILE, TILE)), Vector2i(i * TILE, j * TILE))
	return ImageTexture.create_from_image(img)

static func _bake_flat(isl: Island, img: Image) -> void:
	for y in isl.height:
		for x in isl.width:
			var col: Color = Constants.TERRAIN_COLOR[isl.get_terrain(Vector2i(x, y))]
			img.fill_rect(Rect2i((x * TILE) + TILE / 2, (y * TILE) + TILE / 2, TILE, TILE), col)
