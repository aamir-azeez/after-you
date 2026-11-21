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
## prompt is open, since Play Games is checked a few seconds after launch). Every
## card that offers the platform name (the first-run prompt and Change) opens
## through _open, so all of them read the one source: PlatformGames.name_offered,
## ensure_started, account_key and player_name, which signs in on the tap when
## it has to.
## While the shop is on, the prompt shows the name change price from the
## wardrobe and wallet this phone keeps, and a saved change asks wardrobe_flow
## (refresh) to read them again. While the balance is short, the prompt's "Get
## Pollen" opens the Wardrobe's short of Pollen card (presentation/
## wardrobe_sheets.gd, pollen board 6), which buys its bundle in place through
## the Pollen store's purchase engine (pollen_store_flow, when Main has it and bundles sell).
##
## While the server has players pick usernames (services/usernames.gd), the
## same prompt opens in its username mode instead: once a run for a player
## with none (over Home at launch, Friends, or Play with your friend), and from
## the chip's Change. A username is saved online only, with the answer on the
## card (taken, refused, the price); the GET read fills the price and the
## suggested name after the card opens. The Friends page then shows the new
## friend code at once (friends_flow username_changed).
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
const OfflineHold = preload("res://presentation/offline_hold.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const Usernames = preload("res://services/usernames.gd")

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
## The username prompt opened by itself once this run.
var _asked_username := false
## Tests: transport(method, path, body) -> response in place of the API's queue.
var username_transport: Callable = Callable()

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
	if usernames_on(): return maybe_ask_username(parent, hint_later)
	if not enabled() or prompt_open() or not is_instance_valid(parent) or not parent.is_inside_tree(): return false
	var current := scope()
	var own: Dictionary = DisplayNames.shared().own(current.server, current.owner)
	if not str(own.choice).is_empty() or own.asked: return false
	DisplayNames.shared().mark_asked(current.server, current.owner)
	_open(parent, false, null, hint_later)
	return true

## The prompt opened to change the name (the Friends chip's Change).
## A name change needs the server: offline it says why and asks the server once.
func edit(parent: Control, opener: Control = null) -> void:
	if not enabled() or prompt_open() or not is_instance_valid(parent): return
	if OfflineHold.refuse(): return
	if usernames_on(): _open_username(parent, true, opener)
	else: _open(parent, true, opener)

# --- Usernames ----------------------------------------------------------------

## Whether the server has this player pick a username (what it last said).
func usernames_on() -> bool:
	var current := scope()
	return not current.is_empty() and DisplayNames.shared().usernames_on(current.server, current.owner)

## This player's username as the server last confirmed it, or "".
func username() -> String:
	var current := scope()
	return DisplayNames.shared().username(current.server, current.owner) if not current.is_empty() else ""

## The username prompt over `parent`, once a run, while usernames are on and
## this player has none. True when it opened.
func maybe_ask_username(parent: Control, hint_later: bool = false) -> bool:
	if not usernames_on() or _asked_username or not username().is_empty() or prompt_open() or not is_instance_valid(parent) or not parent.is_inside_tree(): return false
	_asked_username = true
	_open_username(parent, false, null, hint_later)
	return true

func _open_username(parent: Control, editing: bool, opener: Control, hint_later: bool = false) -> void:
	_prompt_price = {}
	var context := {
		"username": true,
		"edit": editing,
		"own": _own_username(),
		"alias": _own_alias(),
		"save": _save_username,
		"reduced_motion": bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false,
		"haptic": func() -> void: if is_instance_valid(host.get("soundscape")): host.soundscape.tap_haptic(),
		"dismissed": func() -> void: if hint_later and host.has_method("_toast"): host._toast(PlayerCopy.USERNAME_LATER_HINT),
		"price": {},
		"get_pollen": func(link: Control) -> void: _open_short(parent, link),
	}
	var modal: Control = Prompt.open(parent, context, opener)
	_prompt = weakref(modal)
	_read_username(modal, editing)

## The own username as the prompt prices it: a change of capitals alone is no change.
func _own_username() -> Dictionary:
	return {"choice": "typed", "name": username(), "fold": true}

## The player's short name from the friends page ("" for none), which they may take as a username.
func _own_alias() -> String:
	var friends: Variant = host._friends_client(false) if host != null and host.has_method("_friends_client") else null
	return str(friends.friend_alias()) if friends is Object and friends.has_method("friend_alias") else ""

## GET /v1/profile/username once the card is open: the username the server
## holds, the change price while the shop is on, and a suggested name. A card
## that opened by itself closes when the player turns out to have one already
## (a phone that never heard it, such as a new install).
func _read_username(modal: Control, editing: bool) -> void:
	var current := scope()
	var response: Dictionary = await _username_request(HTTPClient.METHOD_GET, {})
	var data: Variant = response.get("data")
	if scope() != current or not response.get("ok", false) or not data is Dictionary: return
	var held: Variant = data.get("username")
	if held is String and Usernames.valid_remote(held): _keep_username(current, held)
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false) if is_instance_valid(modal) and not modal.is_queued_for_deletion() else null
	if prompt == null: return
	if held is String and not editing and not prompt.busy():
		prompt.close_quietly()
		return
	var priced: Variant = data.get("pollen_price")
	var wallet: Dictionary = PollenWallet.shared().wallet(str(current.server), str(current.owner))
	if (priced is int or priced is float) and not wallet.is_empty():
		_prompt_price = {"price": int(priced), "balance": int(wallet.balance), "shown": PollenSurfaces.shared().shop_visible(),
			"next": int(data.get("pollen_price_next", -1)), "offer": Wardrobe.shared().view(str(current.server), str(current.owner)).get("bundles", {})}
		prompt.set_price(_prompt_price)
	var suggestion: Variant = data.get("suggestion")
	if suggestion is String and Usernames.problem(suggestion, _own_alias()).is_empty(): prompt.set_suggestion(suggestion)

## The prompt's Save in username mode: PUT /v1/profile/username, waiting for
## the answer, which the card shows when it is a no.
func _save_username(_choice: String, name: String) -> Dictionary:
	var current := scope()
	if current.is_empty(): return {"closed": true}
	var body := {"schema_version": 1, "username": name}
	# While the shop is on, the price shown beside Save goes too, so the server never charges one the player did not see.
	if Wardrobe.shared().shop(str(current.server), str(current.owner)): body["pollen_price"] = Prompt.choice_cost(_prompt_price, _own_username(), "typed", name)
	var response: Dictionary = await _username_request(HTTPClient.METHOD_PUT, body)
	if scope() != current: return {"closed": true}
	var data: Variant = response.get("data")
	if response.get("ok", false) and data is Dictionary and Usernames.valid_remote(data.get("username")):
		_keep_username(current, str(data.username))
		_refresh_wardrobe(true)
		return {"closed": true}
	var code := str(response.get("code", ""))
	if not PlayerCopy.USERNAME_ERRORS.has(code): code = "network"
	_refresh_wardrobe(code in ["pollen_short", "name_change_price"])
	return {"closed": false, "code": refusal_code(code)}

## A username the server confirmed: kept, the chips redraw and Friends shows the new code.
func _keep_username(current: Dictionary, name: String) -> void:
	if DisplayNames.shared().username(current.server, current.owner) == name: return
	DisplayNames.shared().set_username(current.server, current.owner, name)
	_refresh_chips()
	var friends: Variant = host.get("friends_flow") if host != null else null
	if friends is Object and is_instance_valid(friends) and friends.has_method("username_changed"): friends.username_changed(name)

func _refresh_wardrobe(read: bool) -> void:
	var wardrobe: Variant = host.get("wardrobe_flow") if host != null else null
	if read and wardrobe is Object and is_instance_valid(wardrobe) and wardrobe.has_method("refresh"): wardrobe.refresh()

func _username_request(method: int, body: Dictionary) -> Dictionary:
	if username_transport.is_valid(): return await username_transport.call(method, Usernames.PATH, body)
	if host == null or not is_instance_valid(host.get("api")): return {"ok": false, "code": "network"}
	return await host.api.request_json(method, Usernames.PATH, body)

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
		"platform_account": _platform_account,
		"read_platform": _read_platform,
		"save": _save,
		"reduced_motion": bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false,
		"haptic": func() -> void: if is_instance_valid(host.get("soundscape")): host.soundscape.tap_haptic(),
		"dismissed": func() -> void: if hint_later and host.has_method("_toast"): host._toast(PlayerCopy.DISPLAY_NAME_LATER_HINT),
		"price": _price_for_prompt(current),
		"get_pollen": func(link: Control) -> void: _open_short(parent, link),
	}
	# Choosing or changing a name also asks whether to show it, wherever Settings shows the same choice.
	if _name_choice_offered():
		context["name_shown"] = LeaderboardClient.shared(host.api, str(host.api.player_id)).show_name()
		context["show_name"] = _choose_show_name
	var modal: Control = Prompt.open(parent, context, opener)
	_prompt = weakref(modal)
	# An offer this session never learned (a launch read that failed) is read again; the card follows it.
	if platform != null: platform.ensure_started()
	# Flush a send that waited from an earlier visit.
	_client().flush()

## What the next name change costs and the balance it comes from, as the prompt
## shows them ({} while the shop is off or this phone has not heard the price).
## `shown` is false on a build that shows no price (services/pollen_surfaces.gd);
## `offer` is the wardrobe's bundles part, for the short card's suggested bundle.
static func name_price(current: Dictionary) -> Dictionary:
	if current.is_empty(): return {}
	var price: int = Wardrobe.shared().name_price(str(current.server), str(current.owner))
	var wallet: Dictionary = PollenWallet.shared().wallet(str(current.server), str(current.owner))
	return {} if price < 0 or wallet.is_empty() else {"price": price, "balance": int(wallet.balance), "shown": PollenSurfaces.shared().shop_visible(),
		"next": Wardrobe.shared().name_price_next(str(current.server), str(current.owner)), "offer": Wardrobe.shared().view(str(current.server), str(current.owner)).get("bundles", {})}

func _price_for_prompt(current: Dictionary) -> Dictionary:
	_prompt_price = name_price(current)
	return _prompt_price

## The short of Pollen card for the change the open prompt prices (board 5b's
## card). Only while the Pollen store can open, it suggests the smallest bundle
## that covers the change and buys it in place (presentation/short_card_buy.gd)
## through the store's purchase engine; once that Pollen arrives the card
## closes and the prompt shows the new balance, so Save is still the tap that spends.
func _open_short(parent: Control, opener: Control) -> void:
	var open: Variant = _short.get_ref() if _short != null else null
	if (open is Node and is_instance_valid(open) and not open.is_queued_for_deletion()) or _prompt_price.is_empty() or not bool(_prompt_price.get("shown", false)) or not is_instance_valid(parent): return
	var store: Variant = host.get("pollen_store_flow") if host != null else null
	var buyer: Node = store.get("purchase") if store is Object and is_instance_valid(store) and store.available() else null
	var card: Control = WardrobeSheets.short(parent, PlayerCopy.DISPLAY_NAME_SHORT_ITEM, "", int(_prompt_price.price), int(_prompt_price.balance), buyer, _after_bundle, opener, false, _prompt_price.get("offer", {}))
	# The prompt's name tag draws one step up (over its pip); the card goes over the whole prompt.
	card.z_index = 1
	_short = weakref(card)

## A bundle bought on the short card arrived: the card closes and the open
## prompt shows its price and balance again from what this phone now keeps.
func _after_bundle() -> void:
	var open: Variant = _short.get_ref() if _short != null else null
	if open is Control and is_instance_valid(open) and open.has_method("close"): open.close(false)
	_short = null
	var modal: Variant = _prompt.get_ref() if _prompt != null else null
	if not modal is Control or not is_instance_valid(modal) or (modal as Control).is_queued_for_deletion(): return
	var price := name_price(scope())
	var prompt: Node = (modal as Control).find_child("DisplayNamePrompt", true, false)
	# A price this phone cannot say now leaves the prompt's own, which the server checks on Save.
	if prompt == null or price.is_empty(): return
	_prompt_price = price
	prompt.set_price(price)

## Whether Settings offers "Show my name on leaderboards" now (settings_rows.gd
## leaderboard_name): leaderboards open and a player id. Public duels name you
## through the same choice.
func _name_choice_offered() -> bool:
	return host != null and host.has_method("_leaderboards_offered") and host._leaderboards_offered() and is_instance_valid(host.get("api")) and not str(host.api.player_id).is_empty()

## The prompt's switch, written as Settings writes it, only when it changed (each write is a server request).
func _choose_show_name(on: bool) -> void:
	var names: RefCounted = LeaderboardClient.shared(host.api, str(host.api.player_id))
	if names.show_name() != on: names.set_show_name(on)

## The Friends header's Display name chip, or null while names are off.
func chip() -> Control:
	if not enabled(): return null
	var made: Control = Chip.new(bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false)
	made.change_requested.connect(func(source: Control) -> void: edit(_chip_parent(made), source))
	# Change is greyed while offline (presentation/offline_hold.gd).
	if made.get("change_button") is BaseButton: OfflineHold.hold(made.change_button)
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
	var held: String = names.username(current.server, current.owner)
	if not held.is_empty(): made.show_name(held, names.own(current.server, current.owner), true)
	else: made.show_name(names.own_shown(current.server, current.owner), names.own(current.server, current.owner))

func _refresh_chips() -> void:
	var kept: Array[WeakRef] = []
	for ref: WeakRef in _chips:
		var made: Control = ref.get_ref()
		if made == null: continue
		_show_chip(made)
		kept.append(ref)
	_chips = kept
	changed.emit()

## The platform row's label while Play Games or Game Center can give the name
## (offered, and signed in or able to sign in on the tap), else "".
func _platform_label() -> String:
	var platform := _games()
	if platform == null or not platform.name_offered(): return ""
	return PlayerCopy.DISPLAY_NAME_GAME_CENTER if platform.kind() == GamesProvider.GAME_CENTER else PlayerCopy.DISPLAY_NAME_PLAY_GAMES

## The signed-in platform account ("" for none), so the card drops a name read from another one.
func _platform_account() -> String:
	var platform := _games()
	return platform.account_key() if platform != null else ""

## The gamer name; the service signs in first when the quiet check did not.
func _read_platform() -> Dictionary:
	var platform := _games()
	if platform == null: return {"ok": false, "code": "unavailable"}
	# The sign-in sheet shows only while the card that asked is still open (not a later one).
	var asked := _prompt
	return await platform.player_name(func() -> bool: return _prompt == asked and asked != null and asked.get_ref() != null)

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
