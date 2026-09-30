extends VBoxContainer
## Counts completed work, rather than estimating time remaining.
var reduced_motion := false
var bar: ProgressBar
var status: Label

func _init() -> void:
	add_theme_constant_override("separation",5)
	bar=ProgressBar.new()
	bar.custom_minimum_size.y=14
	bar.max_value=1.0
	bar.step=0.001
	bar.show_percentage=false
	add_child(bar)
	status=Label.new()
	status.add_theme_font_size_override("font_size",16)
	status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)
	_update({})

func update_progress(progress: Dictionary) -> void:
	_update(progress)

func _update(progress: Dictionary) -> void:
	var checked := int(progress.get("checked",0))
	var total := int(progress.get("total",0))
	var failed := bool(progress.get("failed",false))
	var fraction := clampf(float(checked)/total,0.0,1.0) if total>0 else 0.0
	var starting := checked==0
	if progress.has("rooms_total"):
		var rooms := int(progress.rooms_total)
		var done := int(progress.get("rooms_done",0))
		bar.value=clampf((done+fraction)/maxi(rooms,1),0.0,1.0)
		if progress.get("active",false) or failed: bar.value=minf(bar.value,0.99)
		starting=done==0 and checked==0
		status.text="Loading saved replays…  %d / %d" % [done,rooms]
	else:
		bar.value=fraction
		status.text="Checking replay…  %d / %d" % [checked,total] if total>0 else "Loading…"
	bar.indeterminate=starting and not reduced_motion and not failed
	if progress.get("phase","")=="preparing":
		bar.indeterminate=not reduced_motion
		status.text="Preparing replay…"
