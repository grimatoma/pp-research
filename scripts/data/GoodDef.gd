class_name GoodDef
extends RefCounted
## One tradeable good (e.g. "fish", "bread", "plank"). PP2 has ~166; we model the
## temperate cascade plus the goods its production chains need. Pure data.

var id: String
var display_name: String
var category: String      ## "raw" | "food" | "luxury" | "material" | "tool" | "currency"
var color: Color          ## placeholder swatch until a goods icon is wired in
var icon_path: String     ## res:// path to a PixelLab icon (optional)

func _init(p_id: String, p_name: String, p_category := "material", p_color := Color.WHITE) -> void:
	id = p_id
	display_name = p_name
	category = p_category
	color = p_color
