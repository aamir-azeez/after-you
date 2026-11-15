extends Container
## One line of same-size tiles that never wraps (the Wardrobe's "Featured this
## week" shelf). Where the line is too narrow for every tile, the tiles shrink a
## little, to MIN_SCALE of their size at most, and past that the last ones are
## left out, so the first tile always shows and the tiles kept are the first in
## the row's own order. fit() is the whole rule. The row asks for only one small
## tile's width, so it never makes the page wider than the screen.
const MIN_SCALE := 0.85

## A tile's full size; each tile shows at this size times the scale, in whole units.
var tile := Vector2.ZERO:
	set(value):
		tile = value
		update_minimum_size()
		queue_sort()
var separation := 10:
	set(value):
		separation = value
		queue_sort()
var _height := -1.0

## How many of `count` tiles `tile_width` wide fit on a line `width` wide with
## `gap` between them, and at what scale: all at full size if they fit, else all
## shrunk down to MIN_SCALE, else the fewest dropped from the end. At least one.
static func fit(width: float, tile_width: float, gap: float, count: int) -> Dictionary:
	if count <= 0 or tile_width <= 0.0: return {"shown": maxi(count, 0), "scale": 1.0}
	for shown in range(count, 0, -1):
		var scale := minf(1.0, (width - gap * (shown - 1)) / (tile_width * shown))
		if scale >= MIN_SCALE: return {"shown": shown, "scale": scale}
	return {"shown": 1, "scale": MIN_SCALE}

func _get_minimum_size() -> Vector2:
	return Vector2(floorf(tile.x * MIN_SCALE), _height if _height >= 0.0 else tile.y)

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN: return
	var tiles: Array = get_children().filter(func(node: Node) -> bool: return node is Control and not (node as Control).top_level)
	var fitted := fit(size.x, tile.x, separation, tiles.size())
	var each := (tile * float(fitted.scale)).floor()
	var x := 0.0
	for index in range(tiles.size()):
		var item: Control = tiles[index]
		var kept: bool = index < int(fitted.shown)
		if item.visible != kept: item.visible = kept
		if not kept: continue
		if item.custom_minimum_size != each: item.custom_minimum_size = each
		fit_child_in_rect(item, Rect2(Vector2(x, 0.0), each))
		x += each.x + separation
	if each.y != _height:
		_height = each.y
		update_minimum_size()
