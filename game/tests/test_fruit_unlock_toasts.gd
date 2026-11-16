extends SceneTree
## A Fruit goal's pop-up (presentation/fruit_unlock_toasts.gd) through a real
## Main, its flows' gates open and their reads stilled:
## - it shows the Fruit mark (kit/currency_mark.gd), the one pop-up look any
##   currency line gets;
## - the owner's bug: the line was up over a room's result card (it outlives
##   the screen it was posted on) and its View tore the room down onto Home.
##   View inside a room never touches the room: the Fruits page waits and opens
##   once the player is back on the room hub, and its Back comes to the hub;
## - left to Home instead, it opens over Home and Back comes Home;
## - a shared replay is play too: no goal line posts over one, nor on a
##   screen its View could not open over (Friends, Journey);
## - a waiting View is forgotten when the player changes.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const MenuBack = preload("res://presentation/menu_back.gd")
const FruitsPageFlow = preload("res://presentation/fruits_page_flow.gd")
const RoomHubFlow = preload("res://presentation/room_hub_flow.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Connectivity = preload("res://services/connectivity.gd")

# Synthetic ids only.
const SERVER := "https://fruit-toasts.example.test"
const ME := "ffffffffffffffffffffff"

class OpenFruits extends FruitsPageFlow:
	func available() -> bool: return true
	func refresh() -> void: pass

class OpenMain extends Main:
	func _new_fruits_page_flow() -> FruitsPageFlow: return OpenFruits.new(self)
	func _names_scope() -> Dictionary: return {"server": SERVER, "owner": ME}

var checks := 0
var failures := 0
var app: Node
var fruits: RefCounted
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _path(name: String) -> String:
	var path := "user://fruit-toasts-%s-%s.json" % [name, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _frames(count: int) -> void:
	for _i in count: await process_frame

func _run() -> void:
	Connectivity.shared().note_reached()
	PollenSurfaces.set_shared_for_tests(true, true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2400, 1080)
	root.add_child(viewport)
	app = OpenMain.new()
	app.saves = Storage.new(_path("saves"))
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.data.settings.reduced_motion = true
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	fruits = FruitWallet.new(_path("fruits"))
	fruits.set_enabled(SERVER, ME, true, true)
	fruits.note_view(SERVER, ME, {"fruits": {"schema_version": 1.0, "balance": 40.0, "earned": 40.0, "achievements": []}})
	app.fruit_unlock_toasts.fruits = fruits
	app.fruit_unlock_toasts.surfaces = PollenSurfaces.new(true, true)
	await _room_result()
	await _left_to_home()
	await _replay_is_play()
	await _only_where_view_opens()
	await _player_changed()
	viewport.free()
	await process_frame
	PollenSurfaces.set_shared_for_tests(false, false)
	for path: String in _paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("AFTER YOU FRUIT UNLOCK TOASTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## A goal paid now, waiting for its line.
func _pay(id: String, amount: int) -> void:
	fruits.note_receipt(SERVER, ME, {"fruits": {"balance": 40 + amount, "paid": [{"id": id, "amount": amount}]}})

## The pop-up's line, posted as Main's loop posts it, with its Fruit mark.
func _post_goal(id: String, amount: int) -> String:
	app.toast.dismiss()
	_pay(id, amount)
	var line: String = app.fruit_unlock_toasts.service()
	var mark := app.toast.card.find_child("FruitMark", true, false) as Control
	_check(not line.is_empty() and app.toast.showing() and app.toast._action.visible, "%s: the goal's line shows with View" % id)
	_check(mark != null and mark.is_visible_in_tree() and app.toast.card.get_global_rect().grow(0.5).encloses(mark.get_global_rect()), "%s: the line wears the Fruit mark inside the card" % id)
	return line

## Main as a room shows it: Main's screens hidden, the room on top.
func _enter_room() -> Node3D:
	app.room_hub_flow.release()
	app.mode = "relay_online"
	app.ui.visible = false
	var room := Node3D.new()
	room.name = "StandInRoom"
	app.relay_child = room
	app.add_child(room)
	return room

func _leave_room() -> void:
	app.remove_child(app.relay_child)
	app.relay_child.free()
	app.relay_child = null
	app.ui.visible = true

## The owner's bug: the hub's line is still up over the room's result card;
## View there keeps the room exactly as it was.
func _room_result() -> void:
	app._show_home()
	await process_frame
	app.room_hub_flow.open_hub("", false)
	await process_frame
	_check(app.mode == RoomHubFlow.MODE_ROOMS and app.room_hub_flow.is_open(), "The room hub is up")
	_post_goal("top_ten", 50)
	var room := _enter_room()
	var home: Control = app.home_stage_view
	_check(app.toast.showing(), "The line posted on the hub is still up over the room")
	_check(app.fruit_unlock_toasts.service() == "", "and no new goal line posts over play")
	app.toast._action.pressed.emit()
	await _frames(3)
	_check(is_instance_valid(app.relay_child) and app.relay_child == room and app.mode == "relay_online" and not app.ui.visible, "View in a room keeps the room up (mode %s)" % app.mode)
	_check(not app.fruits_page_flow.is_open() and app.home_stage_view == home and app.menu_back.entries().is_empty(), "and opens nothing under it, nor Home (history %s)" % [app.menu_back.entries()])
	_check(not app.toast.showing(), "The line closes on View")
	app.toast._process(0.016)
	await _frames(2)
	_check(not app.fruits_page_flow.is_open(), "Still nothing while the room stays")
	_leave_room()
	app.room_hub_flow.open_hub("", false)
	app.toast._process(0.016)
	await _frames(3)
	_check(app.fruits_page_flow.is_open() and app.mode == FruitsPageFlow.MODE and app.ui.visible, "Back on the hub, the Fruits page opens (mode %s)" % app.mode)
	_check(app.menu_back.entries() == [MenuBack.ROOMS, MenuBack.FRUITS], "over the hub in the back history: %s" % [app.menu_back.entries()])
	app._back_on_screen()
	await _frames(2)
	_check(app.mode == RoomHubFlow.MODE_ROOMS and app.room_hub_flow.is_open() and not app.fruits_page_flow.is_open(), "Back comes to the hub (mode %s)" % app.mode)
	app.toast._process(0.016)
	await process_frame
	_check(not app.fruits_page_flow.is_open(), "and the page opens once only")

## Left the room for Home: the page opens over Home and Back comes Home.
func _left_to_home() -> void:
	app._show_home()
	await process_frame
	_post_goal("gold_leaf", 100)
	_enter_room()
	app.toast._action.pressed.emit()
	await process_frame
	_leave_room()
	app._show_home()
	app.toast._process(0.016)
	await _frames(2)
	_check(app.fruits_page_flow.is_open() and app.menu_back.entries() == [MenuBack.HOME, MenuBack.FRUITS], "Left to Home, the page opens over Home: %s" % [app.menu_back.entries()])
	app._back_on_screen()
	await _frames(2)
	_check(app.mode == "home" and not app.fruits_page_flow.is_open(), "and Back comes Home")

## A shared replay plays inside Main too: no goal line over it.
func _replay_is_play() -> void:
	app._show_home()
	app.toast.dismiss()
	await process_frame
	_pay("ghost_first", 10)
	var replay := Node3D.new()
	app.shared_replay_child = replay
	app.add_child(replay)
	_check(app.fruit_unlock_toasts.service() == "" and not app.toast.showing(), "No goal line posts over a shared replay")
	app.remove_child(replay)
	replay.free()
	app.shared_replay_child = null
	_check(app.fruit_unlock_toasts.service() != "", "and it says itself once the replay closes")

## A line posts only where its View opens the page at once: not over Friends
## or Journey, and once back on Home it says itself.
func _only_where_view_opens() -> void:
	app._show_home()
	app.toast.dismiss()
	await process_frame
	_pay("public_duel_first", 10)
	for screen: String in ["friends", "journey"]:
		app.mode = screen
		_check(app.fruit_unlock_toasts.service() == "" and not app.toast.showing(), "No goal line posts on %s, where View could not open the page" % screen)
	app._show_home()
	await process_frame
	_check(app.fruit_unlock_toasts.service() != "" and app.toast.showing(), "and back on Home it says itself")
	app.toast.dismiss()

## A View kept for later is the signed-in player's: a change forgets it.
func _player_changed() -> void:
	app._show_home()
	await process_frame
	_post_goal("duel_win_first", 10)
	_enter_room()
	app.toast._action.pressed.emit()
	await process_frame
	app.notification_flow.forget_friends_news()
	_leave_room()
	app._show_home()
	app.toast._process(0.016)
	await _frames(2)
	_check(not app.fruits_page_flow.is_open(), "A View kept from before the player changed opens nothing")
