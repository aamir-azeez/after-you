extends SceneTree
## ControlTheme.inset_button keeps After You's look in every state, even when
## it is called before the button joins the tree (the room code's Copy button
## went blank after a tap: touch keeps hover, which showed Godot's own style).

const ControlTheme = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var holder := Control.new()
	holder.theme = Theme.new()
	ControlTheme.install_buttons(holder.theme)
	root.add_child(holder)
	var early := Button.new()
	ControlTheme.secondary(early)
	ControlTheme.inset_button(early, 20, 6)
	holder.add_child(early)
	await process_frame
	var late := Button.new()
	ControlTheme.secondary(late)
	holder.add_child(late)
	ControlTheme.inset_button(late, 20, 6)
	await process_frame
	for pair: Array in [[early, "before"], [late, "after"]]:
		var button: Button = pair[0]
		var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
		_check(hover != null and hover.bg_color.is_equal_approx(UiTokens.CREAM_HOVER), "Hover keeps the theme's fill when inset %s joining the tree" % pair[1])
		for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var style := button.get_theme_stylebox(state)
			_check(is_equal_approx(style.content_margin_left, 20.0) and is_equal_approx(style.content_margin_top, 6.0), "%s carries the inset (%s)" % [state, pair[1]])
	print("INSET BUTTON: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
