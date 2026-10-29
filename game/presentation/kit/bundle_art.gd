extends Control
## The four bundles' art (Pollen boards 1 and 2), growing with the amount:
## a pinch of grains, a cloth pouch, a glass jar and a woven basket, each
## holding grains drawn by kit/pollen_mark.gd draw_grain, the one source of the
## grain. Flat shapes drawn once per resize, never per frame; takes no input.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")

const CLOTH := Color("efe3c6")
const CLOTH_SHADE := Color("dccaa2")
const TIE := Color("e9a9a1")
const GLASS := Color(0.86, 0.93, 0.92, 0.55)
const GLASS_EDGE := Color(0.62, 0.75, 0.73, 0.9)
const LID := Color("b4805a")
const LID_SHADE := Color("94633f")
const WICKER := Color("c99358")
const WICKER_DARK := Color("a5703d")
const WICKER_RIM := Color("b37c46")

var bundle := "pinch"

func _init(bundle_id: String = "pinch", side: float = 96.0) -> void:
	bundle = bundle_id
	name = "BundleArt"
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resized.connect(queue_redraw)

func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	match bundle:
		"pouch": _pouch(o, s)
		"jar": _jar(o, s)
		"basket": _basket(o, s)
		_: _pinch(o, s)

func _grain(at: Vector2, radius: float) -> void:
	PollenMark.draw_grain(self, at, radius)

func _pinch(o: Vector2, s: float) -> void:
	_grain(o + Vector2(0.36, 0.62) * s, s * 0.2)
	_grain(o + Vector2(0.66, 0.6) * s, s * 0.19)
	_grain(o + Vector2(0.5, 0.36) * s, s * 0.21)

func _pouch(o: Vector2, s: float) -> void:
	# A soft sack: a wide rounded bottom narrowing to a tied neck, grains peeking over the top.
	_grain(o + Vector2(0.42, 0.2) * s, s * 0.11)
	_grain(o + Vector2(0.58, 0.18) * s, s * 0.1)
	_grain(o + Vector2(0.5, 0.1) * s, s * 0.1)
	var body := PackedVector2Array()
	for index in range(33):
		var t := TAU * index / 32.0
		var p := Vector2(cos(t) * 0.34, sin(t) * 0.32)
		# The upper half pulls in towards the neck.
		if p.y < 0.0: p.x *= 1.0 + p.y * 1.4
		body.append(o + (Vector2(0.5, 0.66) + p) * s)
	draw_colored_polygon(body, CLOTH)
	var shade := PackedVector2Array()
	for point: Vector2 in body:
		if point.x > o.x + 0.52 * s: shade.append(point)
	if shade.size() > 2:
		shade.append(o + Vector2(0.52, 0.98) * s)
		draw_colored_polygon(shade, Color(CLOTH_SHADE, 0.6))
	draw_rect(Rect2(o + Vector2(0.37, 0.27) * s, Vector2(0.26, 0.07) * s), TIE)
	draw_circle(o + Vector2(0.5, 0.305) * s, s * 0.045, TIE.darkened(0.12), true, -1.0, true)

func _jar(o: Vector2, s: float) -> void:
	var glass := Rect2(o + Vector2(0.25, 0.24) * s, Vector2(0.5, 0.66) * s)
	# Grains fill the jar, behind its glass.
	var rows := [[0.36, 0.8], [0.5, 0.82], [0.64, 0.8], [0.42, 0.66], [0.58, 0.66], [0.35, 0.52], [0.5, 0.5], [0.65, 0.52], [0.43, 0.37], [0.58, 0.38]]
	for at: Array in rows: _grain(o + Vector2(at[0], at[1]) * s, s * 0.085)
	var box := StyleBoxFlat.new()
	box.bg_color = GLASS
	box.border_color = GLASS_EDGE
	box.set_border_width_all(maxi(1, int(s * 0.02)))
	box.set_corner_radius_all(int(s * 0.1))
	box.anti_aliasing = true
	draw_style_box(box, glass)
	draw_rect(Rect2(o + Vector2(0.3, 0.3) * s, Vector2(0.05, 0.46) * s), Color(1, 1, 1, 0.45))
	var lid := StyleBoxFlat.new()
	lid.bg_color = LID
	lid.set_corner_radius_all(int(s * 0.04))
	lid.anti_aliasing = true
	draw_style_box(lid, Rect2(o + Vector2(0.28, 0.13) * s, Vector2(0.44, 0.13) * s))
	draw_rect(Rect2(o + Vector2(0.28, 0.22) * s, Vector2(0.44, 0.03) * s), LID_SHADE)

func _basket(o: Vector2, s: float) -> void:
	# A heap of grains on top, then the woven basket in front of them.
	var heap := [[0.3, 0.42], [0.45, 0.38], [0.6, 0.38], [0.73, 0.43], [0.38, 0.28], [0.53, 0.25], [0.67, 0.29], [0.46, 0.15], [0.6, 0.15]]
	for at: Array in heap: _grain(o + Vector2(at[0], at[1]) * s, s * 0.09)
	var body := PackedVector2Array([o + Vector2(0.12, 0.46) * s, o + Vector2(0.88, 0.46) * s, o + Vector2(0.78, 0.9) * s, o + Vector2(0.22, 0.9) * s])
	draw_colored_polygon(body, WICKER)
	for row in range(1, 5):
		var y := 0.46 + row * 0.088
		var inset := (y - 0.46) / 0.44 * 0.1
		draw_line(o + Vector2(0.12 + inset, y) * s, o + Vector2(0.88 - inset, y) * s, WICKER_DARK, maxf(1.0, s * 0.018), true)
	for column in range(1, 7):
		var x := 0.12 + column * 0.76 / 7.0
		draw_line(o + Vector2(x, 0.47) * s, o + Vector2(lerpf(x, 0.5, 0.2), 0.89) * s, Color(WICKER_DARK, 0.55), maxf(1.0, s * 0.012), true)
	var rim := StyleBoxFlat.new()
	rim.bg_color = WICKER_RIM
	rim.set_corner_radius_all(int(s * 0.04))
	rim.anti_aliasing = true
	draw_style_box(rim, Rect2(o + Vector2(0.09, 0.42) * s, Vector2(0.82, 0.08) * s))
