extends Node
## Display names on screen (services/display_names.gd): the first-run prompt,
## the prompt opened from Friends to change the name, and the Display name
## chip in the Friends header. The server is asked only to save a choice
## (services/display_name_client.gd); everything shown comes from the names
## this phone keeps.
##
## The first-run prompt opens once, the first time the player opens Friends or
## taps Play with your friend after the server shows names, over the screen
## that opened (the action is never held up). It never waits on the network:
## if this phone has not yet heard that names are on, it waits for a later visit.
##
## Main hosts it as a child and it reads Main only through this host contract
## (read at call time): api, _names_scope, saves (reduced motion), _toast,
## soundscape (the pip's grab tick), and the PlatformGames autoload (its state
## read when the prompt opens and followed through its changed signal while the
## prompt is open, since Play Games signs in a few seconds after launch).
## While the shop is on, the prompt shows the name change price from the
## wardrobe and wallet this phone keeps, and a saved change asks wardrobe_flow
## (refresh) to read them again. While the balance is short, the prompt's "Get
## Pollen" opens the Wardrobe's short of Pollen card (presentation/
## wardrobe_sheets.gd, pollen board 6), whose own link opens the Pollen store
## (pollen_store_flow, when Main has it and bundles sell) with Back to Friends.
const DisplayNames = preload("res://services/display_names.gd")
const DisplayNameClient = preload("res://services/display_name_client.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const Chip = preload("res://presentation/display_name_chip.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformGames = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const WardrobeSheets = preload("res://presentation/wardrobe_sheets.gd")

## The player's own name or where it stands changed (chips redraw).
signal changed

var host: Node
var client: RefCounted
var _chips: Array[WeakRef] = []
var _prompt: WeakRef = null
## The name change price the open prompt shows ({} for none), fixed when it opened, so Save records that very price.
var _prompt_price: Dictionary = {}
## The short of Pollen card opened from the prompt, while it is open.
var _short: WeakRef = null
## Tests: a stand-in for the PlatformGames autoload.
var games: Node = null

func _init(main: Node = null) -> void:
	host = main

func _client() -> RefCounted:
	if client == null:
		client = DisplayNameClient.new(host.api, host._names_scope)
		client.settled.connect(_settled)
	return client

## {server, owner} of the signed-in player, or {} (Main's one source).
func scope() -> Dictionary:
	return host._names_scope() if host != null else {}

func enabled() -> bool:
	var current := scope()
	return not current.is_empty() and DisplayNames.shared().enabled(current.server, current.owner)

## The first-run prompt over `parent`, once per player, when names are on and
## the player has not chosen yet. True when it opened.
func maybe_ask(parent: Control, hint_later: bool = false) -> bool:
	if not enabled() or prompt_open() or not is_instance_valid(parent) or not parent.is_inside_tree(): return false
	var current := scope()
	var own: Dictionary = DisplayNames.shared().own(current.server, current.owner)
	if not str(own.choice).is_empty() or own.asked: return false
	DisplayNames.shared().mark_asked(current.server, current.owner)
	_open(parent, false, null, hint_later)
	return true

## The prompt opened to change the name (the Friends chip's Change).
func edit(parent: Control, opener: Control = null) -> void:
	if not enabled() or prompt_open() or not is_instance_valid(parent): return
	_open(parent, true, opener)

func prompt_open() -> bool:
	return _prompt != null and _prompt.get_ref() != null

## hint_later: closing it with nothing saved says where to find it (when it
## opened somewhere other than Friends, whose header shows the name).
func _open(parent: Control, editing: bool, opener: Control, hint_later: bool = false) -> void:
	var current := scope()
	var names: RefCounted = DisplayNames.shared()
	var platform := _games()
	var context := {
		"edit": editing,
		"own": names.own(current.server, current.owner),
		"anonymous": DisplayNames.anonymous_name(current.owner),
		"platform": _platform_label,
		"platform_changed": Signal(platform, &"changed") if platform != null and platform.has_signal(&"changed") else Signal(),
		"read_platform": _read_platform,
		"save": _save,
		"reduced_motion": bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false,
		"haptic": func() -> void: if is_instance_valid(host.get("soundscape")): host.soundscape.tap_haptic(),
		"dismissed": func() -> void: if hint_later and host.has_method("_toast"): host._toast(PlayerCopy.DISPLAY_NAME_LATER_HINT),
		"price": _price_for_prompt(current),
		"get_pollen": func(link: Control) -> void: _open_short(parent, link),
	}
	var modal: Control = Prompt.open(parent, context, opener)
	_prompt = weakref(modal)
	# Flush a send that waited from an earlier visit.
	_client().flush()

## What the next name change costs and the balance it comes from, as the prompt
## shows them ({} while the shop is off or this phone has not heard the price).
## `shown` is false on a build that shows no price (services/pollen_surfaces.gd).
static func name_price(current: Dictionary) -> Dictionary:
	if current.is_empty(): return {}
	var price: int = Wardrobe.shared().name_price(str(current.server), str(current.owner))
	var wallet: Dictionary = PollenWallet.shared().wallet(str(current.server), str(current.owner))
	return {} if price < 0 or wallet.is_empty() else {"price": price, "balance": int(wallet.balance), "shown": PollenSurfaces.shared().shop_visible(),
		"next": Wardrobe.shared().name_price_next(str(current.server), str(current.owner))}

func _price_for_prompt(current: Dictionary) -> Dictionary:
	_prompt_price = name_price(current)
	return _prompt_price

## The short of Pollen card for the change the open prompt prices (board 5b's
## card, without "It stays in the shop."). Its own link, only while the Pollen
## store can open, closes the prompt and opens the store with Back to Friends.
func _open_short(parent: Control, opener: Control) -> void:
	var open: Variant = _short.get_ref() if _short != null else null
	if (open is Node and is_instance_valid(open) and not open.is_queued_for_deletion()) or _prompt_price.is_empty() or not bool(_prompt_price.get("shown", false)) or not is_instance_valid(parent): return
	var store: Variant = host.get("pollen_store_flow") if host != null else null
	var to_store := Callable()
	if store is Object and is_instance_valid(store) and store.available():
		to_store = func() -> void:
			var prompt: Variant = _prompt.get_ref() if _prompt != null else null
			if prompt is Control and is_instance_valid(prompt): prompt.close(false)
			store.show_store("friends")
	var card: Control = WardrobeSheets.short(parent, PlayerCopy.DISPLAY_NAME_SHORT_ITEM, "", int(_prompt_price.price), int(_prompt_price.balance), to_store, opener, false)
	# The prompt's name tag draws one step up (over its pip); the card goes over the whole prompt.
	card.z_index = 1
	_short = weakref(card)

## The Friends header's Display name chip, or null while names are off.
func chip() -> Control:
	if not enabled(): return null
	var made: Control = Chip.new(bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false)
	made.change_requested.connect(func(source: Control) -> void: edit(_chip_parent(made), source))
	_chips.append(weakref(made))
	_show_chip(made)
	return made

## The page root a chip sits in, so the prompt covers the whole screen.
static func _chip_parent(chip_node: Control) -> Control:
	var node: Node = chip_node
	while node.get_parent() != null and node.get_parent() is Control: node = node.get_parent()
	return node as Control

func _show_chip(made: Control) -> void:
	var current := scope()
	if current.is_empty() or not is_instance_valid(made): return
	var names: RefCounted = DisplayNames.shared()
	made.show_name(names.own_shown(current.server, current.owner), names.own(current.server, current.owner))

func _refresh_chips() -> void:
	var kept: Array[WeakRef] = []
	for ref: WeakRef in _chips:
		var made: Control = ref.get_ref()
		if made == null: continue
		_show_chip(made)
		kept.append(ref)
	_chips = kept
	changed.emit()

## The platform row's label when Play Games or Game Center is offered and
## signed in, else "".
func _platform_label() -> String:
	var platform := _games()
	if platform == null or not platform.offered() or not platform.signed_in(): return ""
	return PlayerCopy.DISPLAY_NAME_GAME_CENTER if platform.kind() == GamesProvider.GAME_CENTER else PlayerCopy.DISPLAY_NAME_PLAY_GAMES

func _read_platform() -> Dictionary:
	var platform := _games()
	if platform == null: return {"ok": false, "code": "unavailable"}
	return await platform.player_name()

## The PlatformGames service, or null (no autoload, or this node is out of the tree).
func _games() -> Node:
	if is_instance_valid(games): return games
	return PlatformGames.shared(get_tree()) if is_inside_tree() else null

## The prompt's Save: kept on this phone at once, then sent, waiting a moment
## for the answer so a refusal shows on the card. A send that takes longer goes
## on in the background and the card closes.
func _save(choice: String, name: String) -> Dictionary:
	var current := scope()
	if current.is_empty(): return {"closed": true}
	var own: Dictionary = DisplayNames.shared().own(current.server, current.owner)
	var shown := Prompt.choice_cost(_prompt_price, own, choice, name)
	if DisplayNames.shared().choose(current.server, current.owner, choice, name).is_empty():
		var wrong := DisplayNames.problem(name) if choice != "anonymous" else ""
		return {"closed": false, "code": wrong if not wrong.is_empty() else "characters"}
	_client().note_shown_price(int(DisplayNames.shared().own(current.server, current.owner).revision), shown)
	_refresh_chips()
	var answer: Dictionary = await _client().send(DisplayNameClient.SAVE_WAIT_MS)
	_refresh_chips()
	if answer.get("done", false) and not answer.get("ok", false): return {"closed": false, "code": refusal_code(str(answer.get("code", "")))}
	return {"closed": true}

## The server's code as the player hears it: a price refusal on a build that
## shows no price (services/pollen_surfaces.gd) names no price.
static func refusal_code(code: String) -> String:
	return "name_price_hidden" if code in ["pollen_short", "name_change_price"] and not PollenSurfaces.shared().shop_visible() else code

## A send that came back after its card closed: a refusal is said once.
func _settled(answer: Dictionary) -> void:
	_refresh_chips()
	# A saved change may have spent Pollen or used the free change, and a price refusal means
	# the price shown was out of date: read the wardrobe again.
	var wardrobe: Variant = host.get("wardrobe_flow") if host != null else null
	if (answer.get("ok", false) or str(answer.get("code", "")) in ["pollen_short", "name_change_price"]) and wardrobe is Object and is_instance_valid(wardrobe) and wardrobe.has_method("refresh"): wardrobe.refresh()
	if answer.get("ok", false) or prompt_open(): return
	var line := str(PlayerCopy.DISPLAY_NAME_ERRORS.get(refusal_code(str(answer.get("code", ""))), ""))
	if not line.is_empty() and host.has_method("_toast"): host._toast(line)

## Sends a choice still waiting (after a friends read).
func flush() -> void:
	if not scope().is_empty(): _client().flush()
	_refresh_chips()
