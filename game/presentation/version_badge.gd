extends CanvasLayer
## Keep screenshots identifiable without consuming a gameplay control's space.

const SafeArea = preload("res://presentation/safe_area.gd")
var badge: Label

func _ready() -> void:
	layer=100
	process_mode=Node.PROCESS_MODE_ALWAYS
	badge=Label.new()
	badge.name="AppVersion"
	badge.text="v"+str(ProjectSettings.get_setting("application/config/version",""))
	badge.add_theme_font_override("font",preload("res://assets/fonts/nunito.ttf"))
	badge.add_theme_font_size_override("font_size",14)
	badge.add_theme_color_override("font_color",Color("9dbeb4"))
	badge.add_theme_color_override("font_shadow_color",Color("123936"))
	badge.add_theme_constant_override("shadow_offset_y",1)
	badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	get_viewport().size_changed.connect(_position_badge)
	_position_badge.call_deferred()

func _position_badge() -> void:
	if not is_instance_valid(badge): return
	var safe := get_viewport().get_visible_rect()
	if OS.has_feature("android"):
		safe=SafeArea.viewport_rect(Rect2(DisplayServer.get_display_safe_area()),get_viewport().get_screen_transform(),safe)
	badge.size=badge.get_combined_minimum_size()
	badge.position=Vector2(safe.end.x-badge.size.x-24,safe.position.y+4)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_RESUMED:
		_position_badge.call_deferred()
