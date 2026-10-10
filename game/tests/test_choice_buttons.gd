extends SceneTree
const Controls = preload("res://presentation/control_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280,720)
	var parent := Control.new()
	parent.theme = Theme.new()
	parent.theme.default_font = preload("res://assets/fonts/nunito.ttf")
	parent.theme.default_font_size = 20
	Controls.install_buttons(parent.theme)
	root.add_child(parent)
	var choice := OptionButton.new()
	parent.add_child(choice)
	choice.position = Vector2(200,300)
	choice.size = Vector2(500,50)
	for label: String in ["First Steps","The Relay Isles","High and Low"]: choice.add_item(label)
	choice.select(1)
	var selected: Array[int] = []
	choice.item_selected.connect(func(index: int): selected.append(index))
	for _pass in range(3): Controls.secondary(choice)
	_check(choice.item_count == 3 and choice.selected == 1,"styling and restyling preserve chapter choices and selection")
	_check(choice.get_popup().about_to_popup.get_connections().size() == 1,"repeated styling never duplicates the popup layout hook")
	_check(choice.get_popup().theme.default_font == parent.theme.default_font,"the separate popup window retains the chapter picker font")
	var normal := choice.get_theme_stylebox("normal") as StyleBoxFlat
	var pressed := choice.get_theme_stylebox("pressed") as StyleBoxFlat
	_check(normal.bg_color == Color("254b45") and pressed.bg_color == Color("315e53") and choice.get_theme_color("font_pressed_color") == Controls.CREAM,"opening a secondary picker keeps readable ink on its themed surface")
	_check(choice.get_popup().get_theme_constant("v_separation") >= 24,"chapter choices retain touch-friendly row spacing")
	Controls._fit_choice_popup(choice)
	_check(choice.get_popup().max_size.y <= root.size.y-48,"the menu is bounded to its window with end clearance")
	choice.get_popup().index_pressed.emit(2)
	_check(choice.selected == 2 and selected == [2],"choosing a themed menu item updates and emits the original selected index once")
	for index in range(20): choice.add_item("Chapter %d" % index)
	choice.show_popup()
	for _frame in range(4): await process_frame
	_check(choice.get_popup().size.x == int(choice.size.x),"the open dropdown matches its button width")
	_check(choice.get_popup().position == Vector2i(choice.position + Vector2(0,choice.size.y)),"the dropdown begins immediately below the button")
	_check(choice.get_popup().size.y <= 720-int(choice.position.y+choice.size.y)-12,"long chapter lists scroll within the available space below the button")
	choice.get_popup().hide()
	parent.queue_free()
	await process_frame
	print("Chapter choices: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
