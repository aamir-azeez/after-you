extends RefCounted
## The Pollen line after a turn (POLLEN-RULES.md "On screen"): what the turn
## earned, its skill bonus, the room's Full Journey boost and whose it was,
## and a small flower beside a lucky bloom. Kept small and quiet: no reel, no
## countdown, nothing to buy, and pace only as words after the turn. An item
## bloom shows the new item on the player's own still pip ("A lucky bloom: a new
## Daisy!"), with the same small words as any other line: no reveal, no fanfare.
##
## It is drawn only from a receipt the server confirmed (services/pollen_wallet.gd),
## only while the server says Pollen earning is on and the build shows earning
## (services/pollen_surfaces.gd). A build that names no Full Journey leaves out
## the boost lines; the amount still counts the boost.
##
## A receipt with the base and each bonus's percent (a server that sends them)
## shows as the results card's rows (pollen board 7b: presentation/
## pollen_breakdown.gd and pollen_breakdown_view.gd); an older one as the plain
## lines below.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Outfit = preload("res://services/outfit.gd")
const OwnLook = preload("res://services/own_look.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const BreakdownView = preload("res://presentation/pollen_breakdown_view.gd")

const FONT_SIZE := 18
## The still pip beside an item bloom.
const PIP_SIZE := Vector2(42, 56)

## The lines for one receipt, top to bottom. `partner` is the friend's name as
## the room shows it ("" when unknown). Bloom lines start with "*", where the
## flower goes; an item bloom's line starts with "@<item id>|", where the
## player's own pip wearing that item goes. Without `full_journey` the boost
## lines, which name Full Journey, are left out.
static func lines(receipt: Dictionary, partner: String, full_journey: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	if receipt.is_empty(): return out
	var turn: Dictionary = receipt.get("turn", {})
	if int(receipt.get("earned", 0)) > 0: out.append(PlayerCopy.POLLEN_EARNED % int(receipt.earned))
	if not turn.is_empty():
		var names := PackedStringArray()
		for bonus: String in turn.get("bonuses", []):
			names.append({"first_try": PlayerCopy.POLLEN_FIRST_TRY, "gold_pace": PlayerCopy.POLLEN_GOLD_PACE, "silver_pace": PlayerCopy.POLLEN_SILVER_PACE, "hard": PlayerCopy.POLLEN_HARD}[bonus])
		if not names.is_empty():
			var joined := PlayerCopy.POLLEN_AND.join(names)
			out.append(PlayerCopy.POLLEN_BONUS % [joined.left(1).to_upper() + joined.substr(1), int(turn.bonus_percent)])
		if int(turn.get("bloom", 1)) > 1: out.append("*" + PlayerCopy.POLLEN_BLOOM % int(turn.bloom))
		var percent := int(turn.get("boost_percent", 0))
		if percent > 0 and full_journey:
			var from: Array = turn.get("boost_from", [])
			# A friend with no name the room knows reads "Your friend" first in a line and "your friend" after "You and".
			var named := not partner.is_empty() and partner != FriendNicknames.FALLBACK
			if "you" in from and "partner" in from: out.append(PlayerCopy.POLLEN_BOOST_BOTH % [partner if named else PlayerCopy.POLLEN_BOOST_FRIEND.to_lower(), percent])
			elif "you" in from: out.append(PlayerCopy.POLLEN_BOOST_YOU % percent)
			else: out.append(PlayerCopy.POLLEN_BOOST_PARTNER % [partner if named else PlayerCopy.POLLEN_BOOST_FRIEND, percent])
		match str(turn.get("reason", "")):
			"repeat": out.append(PlayerCopy.POLLEN_REPEAT)
			"bank_empty": out.append(PlayerCopy.POLLEN_BANK_EMPTY)
			"late": out.append(PlayerCopy.POLLEN_LATE)
	var item: Dictionary = receipt.get("item_bloom", {})
	if item.has("item_id"):
		var named := Catalog.display_name(str(item.item_id))
		out.append("@%s|%s" % [item.item_id, PlayerCopy.POLLEN_ITEM_BLOOM % (named if not named.is_empty() else PlayerCopy.POLLEN_ITEM_BLOOM_UNKNOWN)])
	elif item.has("pollen"):
		out.append("*" + PlayerCopy.POLLEN_ITEM_BLOOM_POLLEN % PollenMoney.grouped(int(item.pollen)))
	for clear: Dictionary in receipt.get("clears", []):
		out.append((PlayerCopy.POLLEN_FIRST_HARD_CLEAR if clear.get("kind") == "hardclear" else PlayerCopy.POLLEN_FIRST_CLEAR) % int(clear.get("total", 0)))
	return out

## The item an item bloom brought on one of the viewer's turns (its room
## receipt), or "": what the results card's Wear it wears.
static func dropped_item(scope: Dictionary, receipt: Dictionary, store: RefCounted = null) -> String:
	if scope.is_empty(): return ""
	var wallet: RefCounted = store if store != null else PollenWallet.shared()
	var kept: Dictionary = wallet.result_for(str(scope.server), str(scope.owner), str(receipt.get("room_id", "")), str(receipt.get("recording_hash", "")))
	return str(kept.get("item_bloom", {}).get("item_id", ""))

## The player's own pip at rest, wearing the item an item bloom brought: a still
## texture from the shared renderer, never a live view of its own.
static func dropped_pip(item_id: String) -> Control:
	var pip := PipAvatar.new(true, OwnLook.color(), PIP_SIZE, true)
	pip.name = "PollenItemBloomPip"
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pip.wear(Outfit.of(item_id, true))
	return pip

## The line for one of the viewer's turns in a room, or null when there is
## nothing to show. `scope` is {server, owner} of the signed-in player.
## Plain lines fill the width they are given and wrap only by words when it is
## narrow; a line with a flower or a pip keeps its few words on one row beside it.
static func build(scope: Dictionary, room_id: String, recording_hash: String, partner: String, color: Color, store: RefCounted = null) -> Control:
	var surfaces: RefCounted = PollenSurfaces.shared()
	if not surfaces.earning_visible() or scope.is_empty(): return null
	var wallet: RefCounted = store if store != null else PollenWallet.shared()
	if not wallet.enabled(str(scope.server), str(scope.owner)): return null
	var receipt: Dictionary = wallet.result_for(str(scope.server), str(scope.owner), room_id, recording_hash)
	var rows := Breakdown.rows(receipt, partner, surfaces.full_journey_visible())
	if not rows.is_empty():
		var card := BreakdownView.build(rows, color, dropped_pip, func() -> Control: return Flower.new())
		card.name = "PollenResultLine"
		return card
	var text := lines(receipt, partner, surfaces.full_journey_visible())
	if text.is_empty(): return null
	# The earned amount, when there is one, is the first line, with the Pollen mark (kit/pollen_mark.gd) before it.
	var marked := int(receipt.get("earned", 0)) > 0
	var box := VBoxContainer.new()
	box.name = "PollenResultLine"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	for line: String in text:
		var icon: Control = null
		if marked:
			icon = PollenMark.beside(FONT_SIZE)
			marked = false
		elif line.begins_with("*"):
			icon = Flower.new()
			line = line.substr(1)
		elif line.begins_with("@") and line.contains("|"):
			icon = dropped_pip(line.substr(1, line.find("|") - 1))
			line = line.substr(line.find("|") + 1)
		var label := _label(line, color)
		if icon == null:
			# A wrapping label asks for almost no width, so it sits straight in the
			# column, which gives it the whole width.
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(label)
			continue
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		row.add_child(label)
		box.add_child(row)
	return box

static func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The line for a room screen, shown once per credit: on the first screen drawn
## for the turn, and again only when that same screen draws again (a poll, a
## resize). Another screen (the chapter's end card after the waiting one), the
## room opened again or the app restarted never show it again. A credit that
## lands later (a claim) shows on the next draw of a screen for its turn.
## `seen` is the screen owner's memory of what it showed ({} to start, kept per
## room view); `screen` names the screen; `receipt` is the turn's room receipt,
## or room_clear(room) for the first clear a room's finish paid this player.
static func once(seen: Dictionary, screen: String, scope: Dictionary, receipt: Dictionary, partner: String, color: Color, store: RefCounted = null) -> Control:
	if scope.is_empty(): return null
	var wallet: RefCounted = store if store != null else PollenWallet.shared()
	var room_id := str(receipt.get("room_id", ""))
	var recording_hash := str(receipt.get("recording_hash", ""))
	var key := room_id + "|" + recording_hash
	var again: bool = seen.get(key) == screen
	if not again and wallet.result_shown(str(scope.server), str(scope.owner), room_id, recording_hash): return null
	var line := build(scope, room_id, recording_hash, partner, color, wallet)
	if line != null and not again:
		wallet.mark_shown(str(scope.server), str(scope.owner), room_id, recording_hash)
		seen[key] = screen
	return line

## The receipt `once` takes for the first clear a room's finish paid this player
## (the friend of the player whose turn finished it), kept from its clear claim.
static func room_clear(room_id: String) -> Dictionary:
	return {"room_id": room_id, "recording_hash": PollenWallet.ROOM_CLEAR}

## Calls `noted` (server, owner, room_id, recording_hash) whenever a credit is
## kept, so a screen still up for it can show its line; `unwatch` stops it.
static func watch(noted: Callable) -> void:
	var wallet: RefCounted = PollenWallet.shared()
	if not wallet.result_noted.is_connected(noted): wallet.result_noted.connect(noted)

static func unwatch(noted: Callable) -> void:
	var wallet: RefCounted = PollenWallet.shared()
	if wallet.result_noted.is_connected(noted): wallet.result_noted.disconnect(noted)

## A small flower drawn beside a lucky bloom: five petals round a heart.
class Flower extends Control:
	const SIDE := 18.0
	const PETAL := Color("f3d27a")
	const HEART := Color("e58a5b")
	func _init() -> void:
		name = "PollenBloomFlower"
		custom_minimum_size = Vector2(SIDE, SIDE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var middle := size * 0.5
		var radius := minf(size.x, size.y) * 0.22
		for index in range(5):
			draw_circle(middle + Vector2.UP.rotated(TAU * index / 5.0) * radius * 1.15, radius, PETAL)
		draw_circle(middle, radius * 0.8, HEART)
