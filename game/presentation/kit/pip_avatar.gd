extends "res://presentation/kit/spirit_preview.gd"
## One pip, wherever a little pip appears on a screen. Two modes:
## - live (the default): the real SpiritVisual in its own small view, idling at
##   the idle card rate, turned by a drag (kit/spirit_preview.gd);
## - still: a texture of the pip at rest from the one shared offscreen renderer
##   (kit/pip_snapshots.gd). No view of its own and no processing, so a list
##   may show many; matching pips share one render. It takes no input.
## With `own`, it is the player's own pip: its colour and outfit come from
## services/own_look.gd when it enters the tree.
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const OwnLook = preload("res://services/own_look.gd")

## Drawn as a still texture instead of live.
var still := false
## The player's own pip (services/own_look.gd).
var own := false
## The snapshot key this pip shows or waits for (still mode).
var _wanted := ""

func _init(reduced: bool = false, color: Color = PEACH, size_at_least: Vector2 = MIN_SIZE, still_view: bool = false, own_pip: bool = false) -> void:
	super(reduced, color, size_at_least)
	name = "PipAvatar"
	still = still_view
	own = own_pip
	if still: mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	if own:
		_color = OwnLook.color()
		outfit = OwnLook.outfit()
	if not still:
		super()
		return
	set_process(false)
	_show_still()

## Dresses the pip in `worn` (services/outfit.gd).
func wear(worn: Dictionary) -> void:
	if not still:
		super(worn)
		return
	outfit = worn.duplicate()
	if is_inside_tree(): _show_still()

func set_reduced(reduced: bool) -> void:
	if still:
		_reduced = reduced
		return
	super(reduced)

func _gui_input(event: InputEvent) -> void:
	if still: return
	super(event)

func _process(delta: float) -> void:
	if still:
		set_process(false)
		return
	super(delta)

## The size the still texture is drawn at, in pixels.
func still_size() -> Vector2i:
	return Vector2i(custom_minimum_size * RENDER_SCALE)

func _show_still() -> void:
	_wanted = Snapshots.key(_color, outfit, still_size(), rest_yaw)
	var cached := Snapshots.request(_color, outfit, still_size(), rest_yaw, _on_still)
	if cached != null: texture = cached

func _on_still(key: String, drawn_texture: Texture2D) -> void:
	if key == _wanted: texture = drawn_texture
