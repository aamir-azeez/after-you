extends RefCounted
## A room friend's little pip, the same face everywhere a redo request shows
## it (the room's friend strip, the nudge, Home's request card, the "Your turn
## again" note): a still PipAvatar in the friend's slot colour, wearing the
## look this phone last heard them wear in a room (services/turn_looks.gd
## members). No request; a friend never heard of wears the plain pip.
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const TurnLooks = preload("res://services/turn_looks.gd")

## `friend_id`: the friend's player id. `hosts`: whether the friend hosts the
## room (the host's slot is peach, the guest's mint).
static func make(friend_id: String, hosts: bool, size: float) -> Control:
	var pip := PipAvatar.new(true, SpiritLook.PEACH if hosts else SpiritLook.MINT, Vector2(size, size), true)
	pip.name = "FriendPip"
	pip.custom_minimum_size = Vector2(size, size)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.wear(Outfit.from(TurnLooks.shared().member(friend_id) if not friend_id.is_empty() else {}))
	return pip
