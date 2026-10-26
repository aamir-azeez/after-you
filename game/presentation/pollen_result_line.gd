extends RefCounted
## The Pollen line after a turn (POLLEN-RULES.md "On screen"): what the turn
## earned, its skill bonus, the room's Full Journey boost and whose it was,
## and a small flower beside a lucky bloom. Kept small and quiet: no reel, no
## countdown, nothing to buy, and pace only as words after the turn.
##
## It is drawn only from a receipt the server confirmed (services/pollen_wallet.gd),
## only while the server says Pollen earning is on, and never on a build that
## hides paid content (Purchases.paid_content_hidden), which still earns.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Purchases = preload("res://services/purchases.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")

const FONT_SIZE := 18

## Read once: the build's configuration never changes while the app runs.
static var _hidden := -1

static func paid_content_hidden() -> bool:
	if _hidden < 0: _hidden = 1 if Purchases.paid_content_hidden(Purchases.read_configuration()) else 0
	return _hidden == 1

## Tests set what this build hides (true or false), or -1 to read the configuration again.
static func set_hidden_for_tests(value: int) -> void:
	_hidden = value

## The lines for one receipt, top to bottom. `partner` is the friend's name as
## the room shows it ("" when unknown). Bloom lines start with "*", where the
## flower goes.
static func lines(receipt: Dictionary, partner: String) -> PackedStringArray:
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
		if percent > 0:
			var from: Array = turn.get("boost_from", [])
			# A friend with no name the room knows reads "Your friend" first in a line and "your friend" after "You and".
			var named := not partner.is_empty() and partner != FriendNicknames.FALLBACK
			if "you" in from and "partner" in from: out.append(PlayerCopy.POLLEN_BOOST_BOTH % [partner if named else PlayerCopy.POLLEN_BOOST_FRIEND.to_lower(), percent])
			elif "you" in from: out.append(PlayerCopy.POLLEN_BOOST_YOU % percent)
			else: out.append(PlayerCopy.POLLEN_BOOST_PARTNER % [partner if named else PlayerCopy.POLLEN_BOOST_FRIEND, percent])
		match str(turn.get("reason", "")):
			"repeat": out.append(PlayerCopy.POLLEN_REPEAT)
			"bank_empty": out.append(PlayerCopy.POLLEN_BANK_EMPTY)
	for clear: Dictionary in receipt.get("clears", []):
		out.append((PlayerCopy.POLLEN_FIRST_HARD_CLEAR if clear.get("kind") == "hardclear" else PlayerCopy.POLLEN_FIRST_CLEAR) % int(clear.get("total", 0)))
	return out

## The line for one of the viewer's turns in a room, or null when there is
## nothing to show. `scope` is {server, owner} of the signed-in player.
static func build(scope: Dictionary, room_id: String, recording_hash: String, partner: String, color: Color, store: RefCounted = null) -> Control:
	if paid_content_hidden() or scope.is_empty(): return null
	var wallet: RefCounted = store if store != null else PollenWallet.shared()
	if not wallet.enabled(str(scope.server), str(scope.owner)): return null
	var text := lines(wallet.result_for(str(scope.server), str(scope.owner), room_id, recording_hash), partner)
	if text.is_empty(): return null
	var box := VBoxContainer.new()
	box.name = "PollenResultLine"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	for line: String in text:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if line.begins_with("*"):
			row.add_child(Flower.new())
			line = line.substr(1)
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", color)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(label)
		box.add_child(row)
	return box

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
