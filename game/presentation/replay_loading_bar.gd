extends VBoxContainer
## Counts completed work, rather than estimating time remaining.
## A known total fills the bar to the share done; only work without a total
## (preparing playback, reading the account) sweeps.
const TRACK := Color("254b45")
const EDGE := Color("54766a")
const FILL := Color("a6d9c4")
## Visible floor of a determinate fill, so 0 / n still shows a sliver.
const MIN_FILL := 0.02
var reduced_motion := false
var bar: ProgressBar
var status: Label

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
