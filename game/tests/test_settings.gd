extends SceneTree
## Settings (presentation/settings_flow.gd) is one page: a rail of categories
## and the chosen category's rows, all from the rows table
## (presentation/settings_rows.gd).
## - Every saved switch is reachable in its category and a real click changes
##   it, saves it and keeps the row's look; reopening keeps every choice.
## - The rows table: each row's category exists, ids are unique, every saved
##   setting has a row, a fake new row is drawn by the shared builders, and
##   each category's summary comes from its rows and follows a change live.
## - On/off settings are tiles, two to a row, above the other rows: the whole
##   tile flips it, an odd last tile keeps its width, the knob slides (snaps
##   under Reduce motion), and a long page scrolls only its panel, down, with
##   a fade while more lies below; a drag over a tile scrolls without flipping.
## - Every category draws its rows inside the panel, with 48 px targets, at
##   the base and phone shapes; Done and the rail stay put.
## - Friends & notifications holds the notification switches inline.
## - Account & recovery holds its actions inline and they still work.
## - Its first row is Pollen board 1's: the balance with the grain on the gold
##   surface, named "Pollen and purchases" while bundles sell and "Pollen"
##   otherwise (iPhone, no bundles), and it opens the Pollen page.
## - Its rows follow the identity state while it is open.
## - Callers land in the right category, and Back goes where Done goes.
## - A damaged save still opens with every switch; Always skip waits starts off.
## - The header spirit turns under a drag with one light tick, follows Reduce
##   motion, and a tap on it ticks nothing (test_spirit_drag_turn has the rest).
const Main=preload("res://main.gd")
const Storage=preload("res://services/local_save.gd")
const Rows=preload("res://presentation/settings_rows.gd")
const Flow=preload("res://presentation/settings_flow.gd")
const PlayerCopy=preload("res://presentation/player_copy.gd")
const FakeApi=preload("res://tests/fake_rooms_api.gd")
const RoomsApi=preload("res://services/rooms_api.gd")
const SAVED_SWITCHES := ["assistance","reduced_motion","left_handed","sound","haptics","photo_prompts","share_online_status","skip_waits"]
var checks := 0
var failures := 0

const Kit=preload("res://presentation/settings_kit.gd")
const PollenPlayFlow=preload("res://presentation/pollen_play_flow.gd")

## Stands in for Main's pollen_play_flow (presentation/pollen_play_flow.gd).
class PollenStub extends PollenPlayFlow:
	var purchases := false
	var opened := 0
	func available() -> bool: return true
	func balance() -> int: return 24000
	func purchases_shown(_history: Dictionary = {}) -> bool: return purchases
	func open_from_settings() -> void: opened += 1

class Ticks extends Node:
	var count := 0
	func tap_haptic() -> void: count+=1

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _path(tag: String) -> String:
	return "user://settings-%s-%s.json" % [tag, Crypto.new().generate_random_bytes(8).hex_encode()]

func _remove(path: String) -> void:
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)

func _app(path: String, size: Vector2i) -> Node:
	var viewport := SubViewport.new()
	viewport.size=size
	root.add_child(viewport)
	var app := Main.new()
	app.saves=Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	return app

func _settle() -> void:
	await process_frame
	await process_frame

func _click(app: Node, control: Control) -> void:
	var viewport: Viewport = app.get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position=control.get_global_rect().get_center()
	viewport.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=motion.position
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		viewport.push_input(event,true)
	await process_frame

func _control(app: Node, id: String) -> Control:
	return app.overlay.find_child(id,true,false) as Control

func _scroll_of(control: Control) -> ScrollContainer:
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	return parent as ScrollContainer

func _reveal(control: Control) -> void:
	var scroll := _scroll_of(control)
	if scroll != null:
		scroll.ensure_control_visible(control)
		await _settle()

## Opens a category by tapping its rail item, as a player would.
func _open(app: Node, category: String) -> void:
	var item := _control(app,"category_"+category)
	_check(item != null,"The rail has the category: "+category)
	if item == null: return
	await _reveal(item)
	await _click(app,item)
	await _settle()

func _category_of(id: String, app: Node) -> String:
	return str(Rows.find(Rows.rows(app),id).get("category",""))

func _run() -> void:
	var path := _path("main")
	var app := _app(path,Vector2i(1600,720))
	app.settings_flow.show_settings()
	await _settle()
	_check(app.mode=="settings" and app.settings_flow.category()==Flow.EVERYDAY,"Settings opens on Everyday")
	for key: String in SAVED_SWITCHES:
		await _open(app,_category_of(key,app))
		var toggle := _control(app,key) as CheckButton
		_check(toggle != null,"Every saved setting has one reachable switch: "+key)
		if toggle == null: continue
		await _reveal(toggle)
		_check(_scroll_of(toggle).get_global_rect().encloses(toggle.get_global_rect()),"The switch is wholly on show in the panel: "+key)
		if key == "skip_waits": _check(not toggle.button_pressed and toggle.accessibility_name == "Always skip waits","Always skip waits has its switch, off at first")
		for cycle in range(4):
			var before := toggle.button_pressed
			await _click(app,toggle)
			if key == "assistance" and not before: await _accept_confirm(app,toggle)
			_check(toggle.button_pressed!=before,"Repeated click changes the setting: "+key)
			_check(toggle.get_draw_mode()==(BaseButton.DRAW_HOVER_PRESSED if toggle.button_pressed else BaseButton.DRAW_HOVER),"Pointer remains over the checked/unchecked switch")
			for state: String in ["normal","hover","pressed","hover_pressed"]:
				var style := toggle.get_theme_stylebox(state)
				_check(style is StyleBoxFlat and style.bg_color.a>0.9,"Switch background remains opaque in "+state)
			var loaded := Storage.new(path)
			loaded.load_data()
			_check(loaded.data.settings[key]==toggle.button_pressed,"Changed setting survives a fresh file read: "+key)
			_check(app.saves.data.settings[key]==toggle.button_pressed,"Runtime setting matches the visible switch")
	await _assistance_asks_first(app)
	app._show_home()
	for key: String in SAVED_SWITCHES:
		app.settings_flow.show_settings(_category_of(key,app))
		await process_frame
		var toggle := _control(app,key) as CheckButton
		_check(toggle != null and toggle.button_pressed==app.saves.data.settings[key],"Reopening Settings preserves the chosen state: "+key)
	await _failed_save(app)
	_rows_table(app)
	await _fake_row(app)
	await _tiles(app)
	await _spirit_turn(app)
	await _long_page(app)
	await _summaries(app)
	await _redo_request_option(app,path)
	await _account_inline(app)
	await _pollen_row(app)
	await _identity_arrives(app)
	await _callers(app)
	app.get_viewport().queue_free()
	await process_frame
	await _categories_fit(Vector2i(1280,720))
	await _categories_fit(Vector2i(1560,720))
	await _damaged_setting_types()
	_skip_waits_default()
	await process_frame
	await create_timer(0.15).timeout
	_remove(path)
	print("AFTER YOU SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

## A save that fails puts the switch back and says so.
## Turning Forgiving catches on asks first (settings_rows.gd confirm_on): the
## switch stays off behind the question and nothing is saved until Turn on.
func _accept_confirm(app: Node, toggle: CheckButton) -> void:
	await _settle()
	var modal := app.ui.find_child("ConfirmOn_assistance",true,false) as Control
	_check(modal != null and not toggle.button_pressed and app.saves.data.settings.assistance == false,"Turning Forgiving catches on asks first and leaves it off meanwhile")
	if modal == null: return
	_check(_texts(modal).has(PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_TITLE) and _texts(modal).has(PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_BODY),"The question says leaderboard times won't count")
	var accept := modal.find_child("ModalConfirm",true,false) as Button
	_check(accept != null and accept.text == PlayerCopy.SETTINGS_ASSISTANCE_CONFIRM_ACCEPT,"Its button says Turn on")
	await _click(app,accept)
	# The pointer goes back over the switch, where the loop checks its look.
	var motion := InputEventMouseMotion.new()
	motion.position=toggle.get_global_rect().get_center()
	app.get_viewport().push_input(motion,true)
	await _settle()

func _assistance_asks_first(app: Node) -> void:
	await _open(app,_category_of("assistance",app))
	var toggle := _control(app,"assistance") as CheckButton
	if toggle.button_pressed: await _click(app,toggle)
	_check(not toggle.button_pressed and app.saves.data.settings.assistance == false,"Turning Forgiving catches off asks nothing")
	await _reveal(toggle)
	await _click(app,toggle)
	await _settle()
	var modal := app.ui.find_child("ConfirmOn_assistance",true,false) as Control
	_check(modal != null,"The question shows")
	if modal == null: return
	await _click(app,modal.find_child("ModalCancel",true,false) as Control)
	await _settle()
	_check(not toggle.button_pressed and app.saves.data.settings.assistance == false and app.ui.find_child("ConfirmOn_assistance",true,false) == null,"Cancel leaves it off and saves nothing")
	await _click(app,toggle)
	await _settle()
	modal = app.ui.find_child("ConfirmOn_assistance",true,false) as Control
	if modal != null: modal.go_back()
	await _settle()
	_check(not toggle.button_pressed and app.saves.data.settings.assistance == false,"Back leaves it off too")
	var loaded := Storage.new(app.saves.path)
	loaded.load_data()
	_check(loaded.data.settings.assistance == false,"Nothing was written while it asked")
	await _click(app,toggle)
	await _settle()
	modal = app.ui.find_child("ConfirmOn_assistance",true,false) as Control
	var accept := modal.find_child("ModalConfirm",true,false) as Button if modal != null else null
	var generation := int(app.saves.data.generation)
	if accept != null:
		accept.pressed.emit()
		accept.pressed.emit()
	await _settle()
	_check(app.saves.data.settings.assistance == true and int(app.saves.data.generation) == generation + 1,"A double tap on Turn on writes once")

func _texts(node: Node) -> Array:
	var result: Array = []
	for label: Node in node.find_children("*","Label",true,false): result.append((label as Label).text)
	return result

func _failed_save(app: Node) -> void:
	app.settings_flow.show_settings(Flow.EVERYDAY)
	await _settle()
	var toggle := _control(app,"sound") as CheckButton
	var before := toggle.button_pressed
	app.saves.read_only=true
	await _click(app,toggle)
	_check(toggle.button_pressed==before and app.saves.data.settings.sound==before,"A failed save puts the switch back as saved")
	_check(app.toast.visible and app.toast.text==PlayerCopy.MAIN_34B82590B663,"A failed save says the setting could not be saved")
	app.saves.read_only=false

func _rows_table(app: Node) -> void:
	var categories: Array[Dictionary] = Rows.categories(app)
	var rows: Array[Dictionary] = Rows.rows(app)
	var ids: Dictionary = {}
	var category_ids: Array = categories.map(func(entry: Dictionary) -> String: return entry.id)
	for row: Dictionary in rows:
		_check(not ids.has(row.id),"Row ids are unique: "+str(row.id))
		ids[row.id]=true
		_check(row.category in category_ids,"Each row's category is in the rail: "+str(row.id))
		_check(row.kind in [Rows.TOGGLE,Rows.CHOICE,Rows.LINK,Rows.ACTION,Rows.INFO],"Each row has a known kind: "+str(row.id))
		_check(row.has("label"),"Each row has a label: "+str(row.id))
		match str(row.kind):
			Rows.TOGGLE, Rows.CHOICE: _check(row.has("key") or (row.has("get") and row.has("set")),"A setting row saves somewhere: "+str(row.id))
			Rows.LINK: _check(row.get("open") is Callable,"A link opens something: "+str(row.id))
			Rows.ACTION: _check(row.get("run") is Callable or row.get("inline") is Callable,"An action does something: "+str(row.id))
		if row.kind == Rows.TOGGLE: _check(row.get("icon") is Texture2D,"Each on/off setting has its tile icon: "+str(row.id))
	var saved: Dictionary = Storage.defaults().settings
	for key: String in saved:
		if key in ["turn_notifications","turn_request_notifications","unlimited_frame_rate"]: continue
		_check(rows.any(func(row: Dictionary) -> bool: return row.get("key")==key),"Every saved setting has a row: "+key)
	_check(Rows.summary(Rows.category(categories,Flow.GRAPHICS),rows,func(row: Dictionary) -> Variant: return saved.get(row.get("key"))) == "Balanced · 60 fps","The Graphics summary is made from its rows")

## A new setting is one row: the shared builders draw it in its category.
func _fake_row(app: Node) -> void:
	app.settings_flow.show_settings(Flow.PLAY)
	await _settle()
	app.settings_flow._rows.append({"id":"fake_new_setting","category":Flow.PLAY,"kind":Rows.TOGGLE,"label":"A new setting","note":"Drawn from one row","key":"sound","icon":preload("res://assets/ui/settings/sound.svg")})
	app.settings_flow._select(Flow.PLAY)
	await _settle()
	var toggle := _control(app,"fake_new_setting") as CheckButton
	_check(toggle != null and toggle.accessibility_name=="A new setting","A new row in the table appears in its category")
	if toggle == null: return
	await _reveal(toggle)
	var before: bool=app.saves.data.settings.sound
	await _click(app,toggle)
	_check(app.saves.data.settings.sound!=before,"The new row saves through the shared path")
	await _click(app,toggle)
	_check(app.saves.data.settings.sound==before,"and back again")
	app.settings_flow._select(Flow.EVERYDAY)
	await _settle()
	_check(_control(app,"fake_new_setting")==null,"Another category does not draw it")

## Everyday and Play are tile grids: two columns, the whole tile is the
## switch, and an odd last tile keeps its column's width.
func _tiles(app: Node) -> void:
	for category: String in [Flow.EVERYDAY,Flow.PLAY]:
		app.settings_flow.show_settings(category)
		await _settle()
		var grid := app.overlay.find_child("Tiles",true,false) as GridContainer
		var ids: Array = Rows.in_category(Rows.rows(app),category).filter(func(row: Dictionary) -> bool: return row.kind == Rows.TOGGLE).map(func(row: Dictionary) -> String: return row.id)
		_check(grid != null and grid.columns==2 and grid.get_child_count()==ids.size(),"%s draws its on/off settings as a two-column tile grid" % category)
		if grid == null or ids.is_empty(): continue
		var first := _control(app,ids[0]) as Control
		var last := _control(app,ids[-1]) as Control
		_check(absf(first.size.x-last.size.x)<1.0,"Every tile in %s keeps the same width, an odd last one too" % category)
		if ids.size() % 2 == 1: _check(last.get_global_rect().end.x < grid.get_global_rect().end.x - first.size.x * 0.5,"An odd last tile leaves the second cell empty")
		var rows_after: Array = app.overlay.find_child("SettingsRows",true,false).find_children("*","Button",true,false).filter(func(button: Button) -> bool: return not grid.is_ancestor_of(button))
		for button: Button in rows_after:
			_check(button.get_global_rect().position.y >= grid.get_global_rect().end.y - 0.5,"Rows sit below the tiles: "+str(button.name))
	app.settings_flow.show_settings(Flow.EVERYDAY)
	await _settle()
	var tile := _control(app,"skip_waits") as CheckButton
	var mark := tile.get_parent().find_child("Switch",true,false)
	var before := tile.button_pressed
	# A tap far from the switch, on the tile's text, flips it.
	var label := tile.get_parent().find_child("Label",true,false) as Control
	var motion := InputEventMouseMotion.new()
	motion.position=label.get_global_rect().get_center()
	app.get_viewport().push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=motion.position
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		app.get_viewport().push_input(event,true)
	await process_frame
	_check(tile.button_pressed!=before and app.saves.data.settings.skip_waits==tile.button_pressed,"A tap anywhere on the tile flips its setting")
	_check(mark._at > 0.0 and mark._at < 1.0,"The knob slides to its new side")
	await create_timer(0.4).timeout
	_check(is_equal_approx(mark._at,1.0 if tile.button_pressed else 0.0),"and settles there")
	await _click(app,tile)
	var reduce := _control(app,"reduced_motion") as CheckButton
	await _click(app,reduce)
	_check(app.saves.data.settings.reduced_motion,"Reduce motion is on for the snap check")
	await _click(app,tile)
	_check(is_equal_approx(mark._at,1.0 if tile.button_pressed else 0.0),"Under Reduce motion the knob snaps")
	await _click(app,tile)
	await _click(app,reduce)
	_check(tile.toggle_mode and tile.accessibility_name==PlayerCopy.SETTINGS_SKIP_WAITS,"The tile is one switch that reads out its name and state")

## The header spirit: a drag on it ticks once through the soundscape (which
## keeps the Haptics switch), a tap does not, and it follows Reduce motion.
func _spirit_turn(app: Node) -> void:
	app.settings_flow.show_settings(Flow.EVERYDAY)
	await _settle()
	var spirit := _control(app,"SettingsSpirit")
	_check(spirit != null and spirit.mouse_filter==Control.MOUSE_FILTER_STOP,"The header spirit takes drags")
	if spirit == null: return
	var sound: Node = app.soundscape
	var ticks := Ticks.new()
	app.soundscape=ticks
	var viewport: Viewport = app.get_viewport()
	var start := spirit.get_global_rect().get_center()
	for step: int in range(5):
		if step==0 or step==4:
			var button := InputEventMouseButton.new()
			button.button_index=MOUSE_BUTTON_LEFT
			button.pressed=step==0
			button.position=start+Vector2(step*12,0)
			viewport.push_input(button,true)
		else:
			var motion := InputEventMouseMotion.new()
			motion.button_mask=MOUSE_BUTTON_MASK_LEFT
			motion.position=start+Vector2(step*12,0)
			viewport.push_input(motion,true)
	await process_frame
	_check(ticks.count==1 and spirit.turn.offset != 0.0,"A drag turns the spirit with one light tick")
	_check(app.settings_flow.showing(Flow.EVERYDAY),"and changes nothing on the page")
	await _click(app,spirit)
	_check(ticks.count==1,"A tap on the spirit does not tick")
	app.soundscape=sound
	ticks.free()
	var reduce := _control(app,"reduced_motion") as CheckButton
	await _click(app,reduce)
	_check(spirit.turn.reduced and spirit.turn.offset==0.0,"Reduce motion reaches the spirit and sends it home")
	await _click(app,reduce)
	_check(not spirit.turn.reduced,"and turning it off lets it coast again")

## A page with more than fits: only the panel scrolls, down; a fade shows
## while more is below.
func _long_page(app: Node) -> void:
	app.settings_flow.show_settings(Flow.PLAY)
	await _settle()
	var keys := ["sound","haptics","skip_waits","reduced_motion","assistance","left_handed","photo_prompts","share_online_status"]
	for index: int in range(keys.size()):
		app.settings_flow._rows.append({"id":"long_%d" % index,"category":Flow.PLAY,"kind":Rows.TOGGLE,"label":"Long page switch %d" % index,"note":"A switch on a long page","key":keys[index],"icon":preload("res://assets/ui/settings/sound.svg")})
	for index: int in range(3):
		app.settings_flow._rows.append({"id":"long_row_%d" % index,"category":Flow.PLAY,"kind":Rows.LINK,"label":"Long page row %d" % index,"note":"A row below the tiles","open":func(): pass})
	app.settings_flow._select(Flow.PLAY)
	await _settle()
	await _settle()
	var scroll := app.overlay.find_child("SettingsRows",true,false) as ScrollContainer
	var fade := app.overlay.find_child("MoreBelow",true,false) as Control
	var bar := scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page,"A long page overflows its panel")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and not scroll.get_h_scroll_bar().visible,"It never scrolls sideways")
	_check(fade != null and fade.visible and scroll.get_global_rect().grow(0.5).encloses(fade.get_global_rect()),"A fade at the panel's bottom says more is below")
	var done_before := (app.overlay.find_child("SettingsDone",true,false) as Control).get_global_rect()
	var rail_before := (app.overlay.find_child("category_play",true,false) as Control).get_global_rect()
	# The drag itself is checked with real finger input in test_touch_scrolling.
	scroll.scroll_vertical = int(bar.max_value)
	await _settle()
	_check(not fade.visible,"At the end the fade goes")
	scroll.scroll_vertical = 0
	await _settle()
	_check(fade.visible,"and comes back above the end")
	app.settings_flow.show_settings(Flow.EVERYDAY)
	await _settle()
	var short_fade := app.overlay.find_child("MoreBelow",true,false) as Control
	_check(short_fade != null and not short_fade.visible,"A page that fits shows no fade")

func _summary(app: Node, category: String) -> String:
	var item := _control(app,"category_"+category)
	return (item.find_child("Summary",true,false) as Label).text if item != null else ""

## The rail's summaries show live values and follow a change at once.
func _summaries(app: Node) -> void:
	app.settings_flow.show_settings()
	await _settle()
	_check(_summary(app,Flow.EVERYDAY)==PlayerCopy.SETTINGS_EVERYDAY_SUMMARY and _summary(app,Flow.ACCOUNT)==PlayerCopy.SETTINGS_ACCOUNT_SUMMARY,"Fixed summaries read as written")
	_check(_summary(app,Flow.GRAPHICS)=="Balanced · 60 fps","Graphics shows its live values")
	_check(_summary(app,Flow.FRIENDS)=="Notifications: Off","Friends shows whether notifications are on")
	await _open(app,Flow.GRAPHICS)
	var thirty := _control(app,"Option_30") as Button
	await _click(app,thirty)
	_check(_summary(app,Flow.GRAPHICS)=="Balanced · 30 fps","A change shows in the rail at once")
	await _click(app,_control(app,"Option_60"))
	_check(_summary(app,Flow.GRAPHICS)=="Balanced · 60 fps","and changes back")

func _redo_request_option(app: Node, path: String) -> void:
	app.settings_flow.show_settings(Flow.FRIENDS)
	await _settle()
	var toggle := _control(app,"turn_requests") as CheckButton
	var notify := _control(app,"turn_notifications") as CheckButton
	var hint: Label = toggle.get_parent().find_child("Note",true,false) as Label if toggle != null else null
	_check(toggle != null and notify != null and hint != null,"Notifications has its switches inline in Friends & notifications")
	if toggle == null or notify == null or hint == null: return
	_check(_control(app,"notifications_off") != null,"Turn notifications off is inline too")
	_check(toggle.disabled and hint.visible and hint.text==PlayerCopy.TURN_REQUEST_NOTIFICATIONS_NEEDS_TURNS and not toggle.button_pressed,"The redo request switch starts off and waits for notifications")
	_check(toggle.accessibility_name.begins_with("Also "),"The redo request switch reads as an extra")
	await _reveal(notify)
	await _click(app,notify)
	_check(app.turn_notifications.enabled() and notify.button_pressed,"Turn notifications can be switched on for the redo request check")
	_check(not toggle.disabled and not hint.visible,"Turning notifications on makes the redo request switch available")
	_check(_summary(app,Flow.FRIENDS)=="Notifications: On","The rail says notifications are on")
	await _reveal(toggle)
	await _click(app,toggle)
	var loaded := Storage.new(path)
	loaded.load_data()
	_check(loaded.data.settings.turn_request_notifications == true and app.turn_notifications.requests_enabled(), "The redo request choice survives a fresh file read")
	app.settings_flow.show_settings(Flow.FRIENDS)
	await _settle()
	toggle = _control(app,"turn_requests") as CheckButton
	_check(toggle != null and toggle.button_pressed, "Reopening Notifications keeps the redo request choice")
	if toggle == null: return
	var off := _control(app,"notifications_off") as Button
	await _reveal(off)
	await _click(app,off)
	_check(toggle.disabled and toggle.button_pressed and not app.turn_notifications.requests_enabled(), "Turning notifications off pauses redo request alerts and keeps the choice")
	_check(off.disabled and _summary(app,Flow.FRIENDS)=="Notifications: Off","Off is done: its action rests and the rail says Off")

## Pollen board 1's row in Account & recovery: first after the intro, the
## balance with its grain on the gold surface, its name following the build.
func _pollen_row(app: Node) -> void:
	var real: Node = app.pollen_play_flow
	var stub := PollenStub.new()
	app.add_child(stub)
	app.pollen_play_flow = stub
	for purchases: bool in [true, false]:
		stub.purchases = purchases
		app.settings_flow.show_settings(Flow.ACCOUNT)
		await _settle()
		var button := _control(app, "pollen") as Button
		_check(button != null, "Account & recovery has the Pollen row")
		if button == null: continue
		var row := button.get_parent() as Control
		var words: Array = row.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.is_visible_in_tree()).map(func(label: Label) -> String: return label.text)
		var name := PlayerCopy.SETTINGS_POLLEN_PURCHASES if purchases else PlayerCopy.SETTINGS_POLLEN
		var note := PlayerCopy.SETTINGS_POLLEN_PURCHASES_NOTE if purchases else PlayerCopy.SETTINGS_POLLEN_NOTE
		_check(words.has(name) and words.has(note) and words.has("24,000") and row.find_child("PollenMark", true, false) != null and button.accessibility_name == name, "The row reads %s, its note, and the balance with the grain: %s" % [name, str(words)])
		var style := button.get_theme_stylebox("normal") as StyleBoxFlat
		_check(style != null and style.bg_color == Kit.FEATURE and style.border_color == Kit.FEATURE_EDGE and style.border_width_left == 2, "It sits on board 1's gold surface")
		var links: Array = app.settings_flow.find_children("*", "Button", true, false).filter(func(other: Button) -> bool: return other.is_visible_in_tree() and other.get_parent().name.ends_with("Row") and other.get_global_rect().position.y < button.get_global_rect().position.y)
		_check(links.is_empty(), "It is the category's first row: " + str(links.map(func(other: Button) -> String: return other.name)))
		_check(_scroll_of(button).get_global_rect().encloses(button.get_global_rect()), "and wholly on show")
		await _click(app, button)
		_check(stub.opened == (1 if purchases else 2), "A tap opens the Pollen page")
	app.pollen_play_flow = real
	stub.free()
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()

## Account & recovery's actions sit in the panel and still work.
func _account_inline(app: Node) -> void:
	var api := FakeApi.new()
	app.add_child(api)
	var original: Node = app.api
	app.api=api
	api.player_id="P".repeat(22)
	api.device_token="D".repeat(43)
	app.identity_restart_required=false
	app.identity_loading=false
	app.identity_data={"player_id":api.player_id,"recovery_code":"R".repeat(43),"device_token":api.device_token}
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()
	for id: String in ["recovery_details","hosting_access","photo_transfer","safety_reports","delete_identity"]:
		_check(_control(app,id) != null,"Account & recovery shows inline: "+id)
	for gone: String in ["cleanup_note","create_identity","offline_note"]:
		_check(_control(app,gone) == null,"Rows for other identity states stay hidden: "+gone)
	var details := _control(app,"recovery_details") as Button
	await _reveal(details)
	await _click(app,details)
	var box: VBoxContainer = app.settings_flow.detail("recovery_details")
	var fields: Array = box.find_children("*","LineEdit",true,false) if box != null else []
	_check(box != null and box.visible and fields.size()==2 and fields[0].text==api.player_id and not fields[0].editable,"Recovery details open in place")
	var copy: Button = null
	if box != null:
		for button: Button in box.find_children("*","Button",true,false):
			if button.text=="Copy recovery details": copy=button
	_check(copy != null and not copy.disabled,"with an enabled Copy")
	_check(app.mode=="settings","and Settings stays open")
	await _click(app,details)
	_check(box != null and not box.visible and box.get_child_count()==0,"A second tap hides them again")
	api.responses=[{"ok":true,"data":{"status":"verified","full_journey":true}}]
	var hosting := _control(app,"hosting_access") as Button
	await _reveal(hosting)
	await _click(app,hosting)
	await _settle()
	var hosting_box: VBoxContainer = app.settings_flow.detail("hosting_access")
	var shown: bool = hosting_box != null and hosting_box.find_children("*","Label",true,false).any(func(label: Label) -> bool: return label.text=="Full Journey confirmed")
	_check(shown and app.mode=="settings","Check hosting access answers under its row")
	# Photo transfer and Reports open screens of their own (Main's), through the account flow.
	var transfer := _control(app,"photo_transfer") as Button
	var reports := _control(app,"safety_reports") as Button
	_check(transfer.pressed.is_connected(app.account_flow.open_photo_transfer) and reports.pressed.is_connected(app.account_flow.open_safety),"Photo transfer and Reports & blocked players still open their screens")
	_check(app.account_flow.photo_transfer_requested.is_connected(app._open_photo_transfer),"Main opens Photo transfer when the row asks")
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()
	var delete := _control(app,"delete_identity") as Button
	_check(delete != null and delete.has_theme_stylebox_override("normal") and (delete.get_theme_stylebox("normal") as StyleBoxFlat).bg_color==Color("e9b3aa"),"Delete online identity is coral")
	var separation: Node = delete.get_parent().get_parent().get_child(delete.get_parent().get_index()-1) if delete != null else null
	_check(separation != null and separation.name=="Separation","and set apart from the rest")
	delete.pressed.emit()
	await process_frame
	_check(app.mode=="account","Delete asks first (mode %s)" % app.mode)
	_check(_has_button(app,"Delete identity and shared rooms"),"on its own card")
	_press_button(app,"Keep my identity")
	await _settle()
	_check(app.settings_flow.showing(Flow.ACCOUNT),"Keep my identity returns to Account & recovery")
	app.api=original
	api.queue_free()
	app.identity_data={}

## An identity that finishes loading while Account & recovery is open redraws
## its rows: the "not read yet" rows go and the identity's rows come, with the
## focused row kept. A refresh with nothing changed redraws nothing.
func _identity_arrives(app: Node) -> void:
	var api := FakeApi.new()
	app.add_child(api)
	var original: Node = app.api
	app.api=api
	api.player_id=""
	api.device_token=""
	app.identity_restart_required=false
	app.identity_loading=true
	app.identity_read_state=Main.IdentityReadState.LOADING
	app.identity_data={}
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()
	var state: String = app.account_flow.panel_state()
	_check(state in ["unread","offline"],"Before the read finishes Account & recovery has no identity (%s)" % state)
	var waiting_row := "unread_note" if state == "unread" else "offline_note"
	_check(_control(app,waiting_row) != null and _control(app,"hosting_access") == null,"It shows the waiting rows, not the identity's")
	var kept_id := "tester_code" if _control(app,"tester_code") != null else ""
	if not kept_id.is_empty(): (_control(app,kept_id) as Control).grab_focus()
	var before := _control(app,waiting_row)
	app.settings_flow.refresh()
	_check(_control(app,waiting_row) == before,"A refresh with the same rows redraws nothing")
	app.identity_request="settings-identity-read"
	var identity := {"player_id":"Q".repeat(22),"device_token":"T".repeat(43),"recovery_code":"C".repeat(43)}
	app._secret_completed("settings-identity-read","get",{"found":true,"value":JSON.stringify(identity)})
	await _settle()
	await _settle()
	_check(app.account_flow.panel_state()=="ready" and app.settings_flow.showing(Flow.ACCOUNT),"The read finishes with Settings still on Account & recovery")
	_check(_control(app,waiting_row) == null,"The waiting rows go")
	for id: String in ["recovery_details","hosting_access","photo_transfer","safety_reports","delete_identity"]:
		_check(_control(app,id) != null,"The identity's row comes: "+id)
	if not kept_id.is_empty():
		var owner := app.get_viewport().gui_get_focus_owner()
		_check(owner != null and owner.name == kept_id,"The focused row keeps focus through the redraw")
	await _redraw_keeps_place(app)
	app.api=original
	api.queue_free()
	app.identity_data={}
	app.identity_loading=false

## A row set that changes while the page is scrolled keeps the scroll, and
## waits while a finger is on a row: the rows under it stay until it lifts.
func _redraw_keeps_place(app: Node) -> void:
	var supported: bool = RoomsApi.history_supported
	RoomsApi.history_supported = true
	app.settings_flow.show_settings(Flow.ACCOUNT)
	await _settle()
	_check(_control(app,"room_history") != null,"The storage line shows while room history is kept")
	var scroll := app.overlay.find_child("SettingsRows",true,false) as ScrollContainer
	scroll.scroll_vertical = 120
	await _settle()
	var at := scroll.scroll_vertical
	_check(at > 0,"Account & recovery is scrolled for the check")
	var row := _control(app,"safety_reports") as Button
	scroll.ensure_control_visible(row)
	await _settle()
	at = scroll.scroll_vertical
	var press := InputEventMouseButton.new()
	press.position = row.get_global_rect().get_center()
	press.global_position = press.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	app.get_viewport().push_input(press,true)
	await process_frame
	_check(row.is_pressed(),"A finger is down on a row")
	RoomsApi.history_supported = false
	app.settings_flow.refresh()
	await _settle()
	_check(is_instance_valid(row) and row.is_inside_tree() and _control(app,"room_history") != null,"Nothing is redrawn under the finger")
	# The finger slides off the row first, so lifting it does not press the row.
	var away := InputEventMouseMotion.new()
	away.position = Vector2(4,4)
	away.global_position = away.position
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	app.get_viewport().push_input(away,true)
	await process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	# Lifted off the row, so the row itself does not act.
	release.position = Vector2(4,4)
	release.global_position = release.position
	app.get_viewport().push_input(release,true)
	await _settle()
	await _settle()
	_check(app.mode == "settings","Lifting off the row does not act on it")
	_check(_control(app,"room_history") == null and app.settings_flow.showing(Flow.ACCOUNT),"Once it lifts, the row that went away is gone")
	_check(absi(scroll.scroll_vertical - at) <= 1 or scroll.scroll_vertical == int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page),"and the panel keeps its place")
	RoomsApi.history_supported = supported

func _has_button(app: Node, text: String) -> bool:
	return app.overlay.find_children("*","Button",true,false).any(func(button: Button) -> bool: return button.text==text and button.is_visible_in_tree())

func _press_button(app: Node, text: String) -> void:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text==text:
			button.pressed.emit()
			return

## Every way into Settings lands where it should.
func _callers(app: Node) -> void:
	app._show_home()
	await _settle()
	var cog: Button = app.overlay.find_child("HomeSettings",true,false)
	_check(cog != null,"Home has its Settings cog")
	if cog != null:
		cog.pressed.emit()
		_check(app.settings_flow.showing(Flow.EVERYDAY),"The Home cog opens Settings on Everyday")
	app.settings_flow.show_graphics_settings()
	_check(app.settings_flow.showing(Flow.GRAPHICS),"The Graphics entry point opens Graphics")
	app.settings_flow.show_licenses()
	_check(app.settings_flow.showing(Flow.ABOUT),"The Licenses entry point opens About")
	for item: Array in [[app.account_flow.settings_requested,"Account's way back"],[app.store_flow.settings_requested,"The store's way back"],[app.replays_flow.account_requested,"Replays' Account & recovery"]]:
		app._show_home()
		(item[0] as Signal).emit()
		_check(app.settings_flow.showing(Flow.ACCOUNT),item[1]+" lands on Account & recovery")
	for item: Array in [["account",Flow.ACCOUNT],["settings",Flow.ABOUT]]:
		app._show_home()
		app.safety_return=item[0]
		app._close_safety()
		_check(app.settings_flow.showing(item[1]),"Leaving Safety (%s) lands on %s" % item)
	app._show_home()
	app._leave_photo_transfer()
	_check(app.settings_flow.showing(Flow.ACCOUNT),"Leaving Photo transfer lands on Account & recovery")
	app.mode="tester_access"
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.settings_flow.showing(Flow.ACCOUNT),"Android Back from Tester code lands on Account & recovery")
	app.settings_flow.show_settings(Flow.ABOUT)
	await _settle()
	var last: String = Rows.license_id(Rows.license_rows(app).size()-1)
	var licence := _control(app,last) as Button
	_check(licence != null,"About lists every licence")
	if licence != null:
		licence.pressed.emit()
		await _settle()
		_check(app.mode=="license_text","A licence opens its full text")
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		await _settle()
		await _settle()
		var row := _control(app,last)
		var scroll: ScrollContainer = _scroll_of(row) if row != null else null
		_check(app.settings_flow.showing(Flow.ABOUT) and row != null and scroll.get_global_rect().encloses(row.get_global_rect()),"Android Back from a licence returns to the list, at that licence")
	for category: String in [Flow.EVERYDAY,Flow.ACCOUNT]:
		app.settings_flow.show_settings(category)
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_check(app.mode=="home","Android Back on Settings (%s) goes Home, like Done" % category)
	app.settings_flow.show_settings()
	await process_frame
	_check(app.settings_flow.is_open(),"Settings is open before Done")
	_press_button(app,"Done")
	await process_frame
	_check(app.mode=="home" and not app.settings_flow.is_open() and app.settings_flow._live.is_empty() and app.settings_flow._rail.is_empty(),"Done goes Home and Settings lets go of its page")

## Every category draws inside the panel with full targets at the base and phone shapes.
func _categories_fit(size: Vector2i) -> void:
	var path := _path("fit")
	var app := _app(path,size)
	var api := FakeApi.new()
	app.add_child(api)
	app.api=api
	api.player_id="P".repeat(22)
	api.device_token="D".repeat(43)
	app.identity_restart_required=false
	app.settings_flow.show_settings()
	await _settle()
	var area := Rect2(Vector2.ZERO,Vector2(size))
	var done := _control(app,"SettingsDone")
	_check(done != null and area.encloses(done.get_global_rect()) and done.get_global_rect().size.y>=48,"Done is on screen with a full target at %s" % str(size))
	for entry: Dictionary in Rows.categories(app):
		await _open(app,str(entry.id))
		var item := _control(app,"category_"+str(entry.id))
		_check(item.get_global_rect().size.y>=48 and area.encloses(item.get_global_rect()),"The rail item is a full target on screen: %s at %s" % [entry.id,str(size)])
		_check(app.settings_flow.showing(str(entry.id)) and (_control(app,"PanelTitle") as Label).text==str(entry.title),"Tapping %s shows it at %s" % [entry.id,str(size)])
		_check(not (_summary(app,str(entry.id))).is_empty(),"Every category has a summary: "+str(entry.id))
		for row: Dictionary in Rows.in_category(Rows.rows(app),str(entry.id)):
			var control := _control(app,str(row.id))
			_check(control != null,"%s draws its row %s" % [entry.id,row.id])
			if control == null or str(row.kind)==Rows.INFO: continue
			await _reveal(control)
			var scroll := _scroll_of(control)
			_check(scroll != null and scroll.get_global_rect().grow(0.5).encloses(control.get_global_rect()) and area.encloses(scroll.get_global_rect()),"Row %s scrolls wholly into the panel at %s" % [row.id,str(size)])
			_check(control.get_global_rect().size.y>=48,"Row %s is a 48 px target" % row.id)
			_check(not control.get_global_rect().intersects(done.get_global_rect()),"Row %s never meets Done" % row.id)
	app.get_viewport().queue_free()
	await process_frame
	_remove(path)

## A save whose settings hold the wrong types (a damaged file) still opens
## Settings with every switch, and the wrong values fall back to defaults.
func _damaged_setting_types() -> void:
	var path := _path("types")
	var damaged := Storage.defaults()
	damaged.settings = {"sound":"yes","haptics":1,"reduced_motion":null,"left_handed":"no","assistance":0.5,"photo_prompts":[],"share_online_status":{},"graphics_quality":42,"unlimited_frame_rate":"x","frame_rate":60,"skip_waits":"yes","left_over":"kept"}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(damaged))
	file.close()
	var loaded := Storage.new(path)
	loaded.load_data()
	var defaults: Dictionary = Storage.defaults().settings
	for key: String in defaults:
		_check(typeof(loaded.data.settings[key])==typeof(defaults[key]) and loaded.data.settings[key]==defaults[key],"A wrong-typed setting loads as its default: "+key)
	_check(loaded.data.settings.get("left_over")=="kept","An unknown setting is kept as saved")
	var app := _app(path,Vector2i(1600,720))
	var found := 0
	for category: String in [Flow.EVERYDAY,Flow.PLAY,Flow.FRIENDS]:
		app.settings_flow.show_settings(category)
		await process_frame
		for key: String in SAVED_SWITCHES:
			if _control(app,key) is CheckButton: found+=1
	_check(found==SAVED_SWITCHES.size() and _control(app,"SettingsDone") is Button and (_control(app,"SettingsDone") as Button).text=="Done","Settings from a damaged save shows every switch and Done")
	app.get_viewport().queue_free()
	await process_frame
	_remove(path)

## Always skip waits starts off, an older save without it loads it off, and a
## chapter journal's settings envelope may omit it or hold only its default.
func _skip_waits_default() -> void:
	_check(Storage.defaults().settings.skip_waits == false,"Always skip waits is off by default")
	var path := _path("skip")
	var older := Storage.defaults()
	older.settings.erase("skip_waits")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(older))
	file.close()
	var loaded := Storage.new(path)
	loaded.load_data()
	_check(loaded.data.settings.get("skip_waits")==false,"A save from before the setting loads it off")
	_check(Storage.default_settings_envelope_valid({"sound":true}) and Storage.default_settings_envelope_valid({"skip_waits":false}) and not Storage.default_settings_envelope_valid({"skip_waits":true}),"Chapter envelopes may omit Always skip waits or hold its default only")
	_remove(path)
