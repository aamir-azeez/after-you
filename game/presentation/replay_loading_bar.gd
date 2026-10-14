extends VBoxContainer
## Counts completed work, rather than estimating time remaining.
## A known total fills the bar to the share done; only work without a total
## (preparing playback, reading the account) sweeps.
const TRACK := Color("254b45")
const EDGE := Color("54766a")
const FILL := Color("a6d9c4")
## Visible floor of a determinate fill, so 0 / n still shows a sliver.
const MIN_FILL := 0.02
## follow(): how fast the shown fill closes on its target (per second), the
## longest frame step the motion takes (a long blocked frame resumes smoothly
## instead of jumping), and one shimmer pass across the bar in seconds.
const EASE_RATE := 9.0
const MAX_STEP := 0.1
const SHIMMER_SECONDS := 1.2
var reduced_motion := false
var bar: ProgressBar
var status: Label
## follow() mode: the target fraction (negative until follow is called) and
## the fill shown now, which only ever moves forward.
var target := -1.0
var shown := 0.0
## Closes on the target three times as fast (the last steps before a wait).
var hurry := false
## 0..1 position of the shimmer band across the bar.
var shimmer_phase := 0.0
var _shimmer: Control

func _init() -> void:
	add_theme_constant_override("separation",5)
	# Room above and below so the bar never touches neighbouring captions.
	var above := Control.new()
	above.custom_minimum_size.y=6
	above.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(above)
	bar=ProgressBar.new()
	bar.custom_minimum_size.y=14
	bar.max_value=1.0
	bar.step=0.001
	bar.show_percentage=false
	var track := StyleBoxFlat.new()
	track.bg_color=TRACK
	track.border_color=EDGE
	track.set_border_width_all(1)
	track.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("background",track)
	var fill := StyleBoxFlat.new()
	fill.bg_color=FILL
	fill.set_corner_radius_all(7)
	bar.add_theme_stylebox_override("fill",fill)
	add_child(bar)
	status=Label.new()
	status.add_theme_font_size_override("font_size",16)
	status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)
	var below := Control.new()
	below.custom_minimum_size.y=2
	below.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(below)
	_update({})

func update_progress(progress: Dictionary) -> void:
	_update(progress)

## For a long wait with partial progress (the chapter opening card): the fill
## eases toward fraction and never moves back, and a soft shimmer keeps
## passing over the bar while it waits. With reduced motion the fill steps
## straight to each new value and nothing sweeps.
func follow(fraction: float) -> void:
	if target < 0.0:
		bar.indeterminate = false
		status.text = "Loading…"
		if not reduced_motion:
			_shimmer = Shimmer.new()
			_shimmer.owner_bar = self
			bar.add_child(_shimmer)
			_shimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_process(true)
	target = maxf(target, clampf(fraction, 0.0, 1.0))
	if reduced_motion: shown = target
	bar.value = maxf(shown, MIN_FILL)

## One frame of follow() motion; delta is capped at MAX_STEP.
func advance(delta: float) -> void:
	if target < 0.0: return
	var step := clampf(delta, 0.0, MAX_STEP)
	shown = maxf(shown, lerpf(shown, target, 1.0 - exp(-EASE_RATE * (3.0 if hurry else 1.0) * step)))
	if target - shown < 0.001: shown = target
	bar.value = maxf(shown, MIN_FILL)
	if is_instance_valid(_shimmer):
		shimmer_phase = fposmod(shimmer_phase + step / SHIMMER_SECONDS, 1.0)
		_shimmer.queue_redraw()

func _ready() -> void:
	set_process(target >= 0.0)

func _process(delta: float) -> void:
	advance(delta)

## A soft light band that sweeps along the track, drawn over the fill.
class Shimmer extends Control:
	var owner_bar: VBoxContainer
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var width := size.x
		var height := size.y
		if width < 8.0 or height < 4.0 or owner_bar == null: return
		var band := clampf(width * 0.22, 24.0, 120.0)
		var middle := -band + (width + band * 2.0) * float(owner_bar.shimmer_phase)
		var clear := Color(1, 1, 1, 0)
		var light := Color(1, 1, 1, 0.34)
		var top := 2.0
		var bottom := height - 2.0
		# Kept inside the rounded ends of the track.
		var left := 4.0
		var right := width - 4.0
		var points: Array = [[middle - band, clear], [middle, light], [middle + band, clear]]
		for index in range(2):
			var from: float = points[index][0]
			var to: float = points[index + 1][0]
			var a := clampf(from, left, right)
			var b := clampf(to, left, right)
			if b - a < 0.5: continue
			var color_a: Color = (points[index][1] as Color).lerp(points[index + 1][1], (a - from) / (to - from))
			var color_b: Color = (points[index][1] as Color).lerp(points[index + 1][1], (b - from) / (to - from))
			draw_polygon(PackedVector2Array([Vector2(a, top), Vector2(b, top), Vector2(b, bottom), Vector2(a, bottom)]), PackedColorArray([color_a, color_b, color_b, color_a]))

func _update(progress: Dictionary) -> void:
	var checked := int(progress.get("checked",0))
	var total := int(progress.get("total",0))
	var failed := bool(progress.get("failed",false))
	var fraction := clampf(float(checked)/total,0.0,1.0) if total>0 else 0.0
	var known := total>0
	if progress.has("rooms_total") or progress.has("sources_total"):
		# Saved rooms (Together) or saved solo sources, counted the same way.
		var rooms := int(progress.get("rooms_total",progress.get("sources_total",0)))
		var done := int(progress.get("rooms_done",progress.get("sources_done",0)))
		known=rooms>0
		bar.value=clampf((done+fraction)/maxi(rooms,1),0.0,1.0)
		if progress.get("active",false) or failed: bar.value=minf(bar.value,0.99)
		status.text="%s  %d / %d" % [str(progress.get("label","Loading saved replays…")),done,rooms]
	else:
		bar.value=fraction
		status.text="Checking replay…  %d / %d" % [checked,total] if total>0 else "Loading…"
	if known: bar.value=maxf(bar.value,MIN_FILL)
	bar.indeterminate=not known and not reduced_motion and not failed
	if progress.get("phase","")=="preparing":
		bar.indeterminate=not reduced_motion
		status.text="Preparing replay…"
