extends Node
## Play Solo's page: the Chapters page (the chapter picker, with its Hard
## chip), and which chapter a picked card opens.
## It also answers which chapters the player can open next, for Home's idle
## warm ups (GL programs, worlds and the page's pictures).
##
## Main hosts it as a child. The flow keeps only the page it has open (the
## picker, the Hard chip's state and the Full Journey access the page was drawn
## with). Opening a chapter stays with Main, which the Replays flow, the room
## hub and tester access share. The flow reads Main only through this host
## contract (read at call time, so Main or a test can swap a service or
## override an entry point):
## - services: title_font, hard_states, _chapter_marks,
##   _chapter_unlocks, _full_journey_access, _paid_content_hidden
## - screen: mode, ui, overlay, _screen_shell, _card, _scroll_list,
##   _button, _back_button, _label, _paragraph, _toast, _show_home
## - chapter opens: _open_premium_chapter, _open_chapter_preview, and
##   fruit_spend_flow.unlock_level for a chapter its Fruit price locks
## Main opens it through show_journey() (Home's Play Solo, StoreFlow's and
## RoomHubFlow's journey requests and the update screen's Play Solo) and
## refreshes it through refresh_marks() and access_changed().
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const ChapterThumbnailCatalog = preload("res://services/chapter_thumbnail_catalog.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const TouchInput = preload("res://presentation/touch_input.gd")
## Main's mode on this page.
const MODE_JOURNEY := "journey"

var host: Node
## The Chapters page's picker while it is drawn.
var picker: ChapterPicker
## Play Solo's Hard chip (services/hard_mode.gd), kept for the session.
var hard := false
## Full Journey access the open chapter grid was drawn with.
var _grid_access_drawn := false
## The marks and the locked cards the open chapter grid was drawn with: new
## marks that open a chapter draw the page again (refresh_marks).
var _marks_drawn := 0
var _locks_drawn: Array[String] = []

func _init(main: Node = null) -> void:
	host = main

func show_journey() -> void:
	host.mode = MODE_JOURNEY
	var shell: Dictionary = host._screen_shell("Your journey",host._show_home)
	var outer: VBoxContainer = shell.outer
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	var chapters_tab: Button = host._button("Chapters",show_journey,false)
	chapters_tab.disabled = true
	ControlTheme.selected_tab(chapters_tab)
	tabs.add_child(chapters_tab)
	# Hard: the whole chapter in one go (services/hard_mode.gd).
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(spacer)
	var hard_chip := HardModeView.chip(hard)
	hard_chip.toggled.connect(func(on: bool):
		hard = on
		show_journey())
	tabs.add_child(hard_chip)
	outer.add_child(tabs)
	var chapter_picker := ChapterPicker.new()
	chapter_picker.heading_font = host.title_font
	chapter_picker.available_width = func() -> float: return host.ui.size.x-44.0
	chapter_picker.hard_mode = HardMode.SOLO
	chapter_picker.hard_states = host.hard_states()
	outer.add_child(chapter_picker)
	shell.margin.resized.connect(chapter_picker.refit)
	# The picker puts every free chapter first, each part in registry order.
	var owned: bool = host._full_journey_access()
	_grid_access_drawn = owned
	var shown := entries(owned,hard)
	_marks_drawn = hash(host._chapter_marks())
	_locks_drawn = _locked(shown)
	chapter_picker.set_entries(shown,ChapterPicker.picture_for(host.ui.size.x))
	chapter_picker.chosen.connect(open_solo_chapter)
	picker = chapter_picker
	refresh_marks()

## Runs a Play Solo card's play button: the chapter's solo scene, through the
## premium gate when the chapter is premium. A chapter the chain has not
## reached says which chapter opens it (services/chapter_unlocks.gd). One its
## Fruit price locks offers the price while the server sells levels, and is a
## Full Journey chapter while it does not.
func open_solo_chapter(key: String) -> void:
	var unlocks: Dictionary = host._chapter_unlocks()
	if not ChapterUnlocks.reached(key, unlocks):
		host._toast(ChapterUnlocks.reason(key, unlocks))
		return
	if ChapterUnlocks.fruit_locked(key, unlocks):
		if ChapterUnlocks.fruit_offered(key, unlocks): host.fruit_spend_flow.unlock_level(key, host.overlay, _opener(key))
		else: host._open_premium_chapter(ChapterRegistry.open_scene(key))
		return
	if hard and host.mode == MODE_JOURNEY:
		_open_hard_chapter(key)
		return
	if not own_solo_card(key): return
	if ChapterRegistry.descriptor(key).premium: host._open_premium_chapter(ChapterRegistry.open_scene(key))
	else: host._open_chapter_preview(ChapterRegistry.open_scene(key))

## The card's play button for `key`, the confirm card's opener (focus returns to it).
func _opener(key: String) -> Control:
	var card: Control = picker.card_for(key) if is_instance_valid(picker) else null
	return card.find_child("ChapterOpen", true, false) as Control if card != null else null

## A chapter was opened with Fruits (Main, from fruit_spend_flow's `spent`):
## the page is drawn again when a card's lock changed, after any tap in progress.
func levels_changed() -> void:
	if host.mode != MODE_JOURNEY or not is_instance_valid(picker): return
	if _locked(entries(_grid_access_drawn,hard)) == _locks_drawn: return
	var drawn := picker
	await TouchInput.redraw_when_released(host.overlay,func() -> bool: return host.mode == MODE_JOURNEY and picker == drawn,show_journey)

## Every chapter with a solo screen has its own Solo card.
static func own_solo_card(key: String) -> bool:
	return not ChapterRegistry.solo_scene(key).is_empty()

## A solo hard run of the chapter, once it is finished (services/hard_mode.gd).
func _open_hard_chapter(key: String) -> void:
	if not HardMode.unlocked(host._chapter_marks(), key):
		host._toast(PlayerCopy.HARD_LOCKED_TOAST)
		return
	var request := {"chapter_key": key, "kind": "play"}
	if ChapterRegistry.descriptor(key).premium: host._open_premium_chapter(ChapterRegistry.solo_scene(key), {}, request)
	else: host._open_chapter_preview(ChapterRegistry.solo_scene(key), {}, request)

## The Chapters page's cards, as given to its picker (which shows free ones
## first): every chapter with its own Solo card, in offered order. A chapter
## the chain has not reached is locked with its reason as the card's note; a
## Full Journey one the player does not own keeps the Full Journey lock.
## With hard on: only chapters with hard runs, each locked until finished.
## A build that sells nothing lists the free chapters alone (Main._paid_content_hidden).
func entries(owned: bool, hard_on: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in ChapterRegistry.offered_keys():
		if own_solo_card(key): result.append(ChapterPicker.entry(key))
	if host._paid_content_hidden(): result = result.filter(func(item: Dictionary) -> bool: return not item.premium)
	var unlocks: Dictionary = host._chapter_unlocks()
	for item: Dictionary in result:
		item.locked = item.premium and not owned
		ChapterUnlocks.lock_entry(item, unlocks)
	return HardMode.picker_entries(result, host._chapter_marks()) if hard_on else result

## The Chapters page's pictures in its card order, which the thumbnail shelf
## loads ahead while Home is idle.
func thumbnail_paths() -> Array[String]:
	var paths: Array[String] = []
	for item: Dictionary in ChapterPicker.shown_order(entries(host._full_journey_access())):
		paths.append(ChapterThumbnailCatalog.path(str(item.key)))
	return paths

## The chapter the player most likely opens next: the first card the Chapters
## page shows, in its order, that is open to them and not yet finished solo;
## "" once every one is.
## `shown` is the page's cards in order, when the caller has them already.
func next_solo_chapter(shown: Array[Dictionary] = []) -> String:
	var marks: Dictionary = host._chapter_marks()
	for item: Dictionary in shown if not shown.is_empty() else ChapterPicker.shown_order(entries(host._full_journey_access())):
		if not bool(item.locked) and not bool(marks.get(str(item.mark), {}).get("solo", false)): return str(item.key)
	return ""

## Every chapter the player can open from the Chapters page now, the one they
## most likely open next first (services/world_prewarm.gd). Locked chapters,
## Full Journey or not yet reached, are never warmed.
func openable_chapters() -> Array[String]:
	var result: Array[String] = []
	var shown := ChapterPicker.shown_order(entries(host._full_journey_access()))
	var next := next_solo_chapter(shown)
	if not next.is_empty(): result.append(next)
	for item: Dictionary in shown:
		if not bool(item.locked) and not str(item.key) in result: result.append(str(item.key))
	return result

## The open page's ticks follow the marks at once. Marks that open a chapter
## (a keepsake check or a friend's room finishing while the page is up) draw
## the page again, after any tap in progress.
func refresh_marks() -> void:
	if host.mode != MODE_JOURNEY or not is_instance_valid(picker): return
	var marks: Dictionary = host._chapter_marks()
	picker.refresh_marks(marks)
	var signature := hash(marks)
	if signature == _marks_drawn: return
	_marks_drawn = signature
	if _locked(entries(_grid_access_drawn,hard)) == _locks_drawn: return
	var drawn := picker
	await TouchInput.redraw_when_released(host.overlay,func() -> bool: return host.mode == MODE_JOURNEY and picker == drawn,show_journey)

static func _locked(shown: Array[Dictionary]) -> Array[String]:
	var keys: Array[String] = []
	for item: Dictionary in shown:
		if bool(item.get("locked",false)): keys.append(str(item.key))
	return keys

## The store's customer information changed while the page is open
## (Main._customer_info_changed): the page is drawn again only when Full
## Journey access differs from what it was drawn with, after any tap in progress.
func access_changed() -> void:
	if host._full_journey_access() == _grid_access_drawn: return
	await TouchInput.redraw_when_released(host.overlay,func() -> bool: return host.mode == MODE_JOURNEY and host._full_journey_access() != _grid_access_drawn,show_journey)
