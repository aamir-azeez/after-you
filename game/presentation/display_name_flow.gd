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
## (read at call time): api, _relay_identity, saves (reduced motion),
## _toast, soundscape (the pip's grab tick), and the PlatformGames autoload.
const DisplayNames = preload("res://services/display_names.gd")
const DisplayNameClient = preload("res://services/display_name_client.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const Chip = preload("res://presentation/display_name_chip.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformGames = preload("res://services/platform_games/platform_games.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")

## The player's own name or where it stands changed (chips redraw).
signal changed

var host: Node
var client: RefCounted
var _chips: Array[WeakRef] = []
var _prompt: WeakRef = null

func _init(main: Node = null) -> void:
	host = main

func _client() -> RefCounted:
	if client == null:
		client = DisplayNameClient.new(host.api, host._relay_identity)
		client.settled.connect(_settled)
	return client

## {server, owner} of the signed-in player, or {}.
func scope() -> Dictionary:
	if host == null or host.api == null or not host._relay_identity().get("ready", false): return {}
	return {"server": str(host.api.base_url), "owner": str(host.api.player_id)}

func enabled() -> bool:
	var current := scope()
	return not current.is_empty() and DisplayNames.shared().enabled(current.server, current.owner)

## The first-run prompt over `parent`, once per player, when names are on and
## the player has not chosen yet. True when it opened.
func maybe_ask(parent: Control) -> bool:
	if not enabled() or prompt_open() or not is_instance_valid(parent) or not parent.is_inside_tree(): return false
	var current := scope()
	var own: Dictionary = DisplayNames.shared().own(current.server, current.owner)
	if not str(own.choice).is_empty() or own.asked: return false
	DisplayNames.shared().mark_asked(current.server, current.owner)
	_open(parent, false, null)
	return true

## The prompt opened to change the name (the Friends chip's Change).
func edit(parent: Control, opener: Control = null) -> void:
	if not enabled() or prompt_open() or not is_instance_valid(parent): return
	_open(parent, true, opener)

func prompt_open() -> bool:
	return _prompt != null and _prompt.get_ref() != null

func _open(parent: Control, editing: bool, opener: Control) -> void:
	var current := scope()
	var names: RefCounted = DisplayNames.shared()
	var context := {
		"edit": editing,
		"own": names.own(current.server, current.owner),
		"anonymous": DisplayNames.anonymous_name(current.owner),
		"platform": _platform_label(),
		"read_platform": _read_platform,
		"save": _save,
		"reduced_motion": bool(host.saves.data.settings.get("reduced_motion", false)) if host.saves != null else false,
		"haptic": func() -> void: if is_instance_valid(host.get("soundscape")): host.soundscape.tap_haptic(),
	}
	var modal: Control = Prompt.open(parent, context, opener)
	_prompt = weakref(modal)
	# Flush a send that waited from an earlier visit.
	_client().flush()

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
	var games: Node = PlatformGames.shared(get_tree()) if is_inside_tree() else null
	if games == null or not games.offered() or not games.signed_in(): return ""
	return PlayerCopy.DISPLAY_NAME_GAME_CENTER if games.kind() == GamesProvider.GAME_CENTER else PlayerCopy.DISPLAY_NAME_PLAY_GAMES

func _read_platform() -> Dictionary:
	var games: Node = PlatformGames.shared(get_tree()) if is_inside_tree() else null
	if games == null: return {"ok": false, "code": "unavailable"}
	return await games.player_name()

## The prompt's Save: kept on this phone at once, then sent, waiting a moment
## for the answer so a refusal shows on the card. A send that takes longer goes
## on in the background and the card closes.
func _save(choice: String, name: String) -> Dictionary:
	var current := scope()
	if current.is_empty(): return {"closed": true}
	if DisplayNames.shared().choose(current.server, current.owner, choice, name).is_empty(): return {"closed": false, "code": "characters"}
	_refresh_chips()
	var answer: Dictionary = await _client().send(DisplayNameClient.SAVE_WAIT_MS)
	_refresh_chips()
	if answer.get("done", false) and not answer.get("ok", false): return {"closed": false, "code": str(answer.get("code", ""))}
	return {"closed": true}

## A send that came back after its card closed: a refusal is said once.
func _settled(answer: Dictionary) -> void:
	_refresh_chips()
	if answer.get("ok", false) or prompt_open(): return
	var line := str(PlayerCopy.DISPLAY_NAME_ERRORS.get(str(answer.get("code", "")), ""))
	if not line.is_empty() and host.has_method("_toast"): host._toast(line)

## Sends a choice still waiting (after a friends read).
func flush() -> void:
	if not scope().is_empty(): _client().flush()
	_refresh_chips()
