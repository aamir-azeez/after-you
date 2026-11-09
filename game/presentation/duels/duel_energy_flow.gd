extends RefCounted
## Duel energy's glue on the duel pages (ENERGY-PLAN.md, boards 10), owned by
## the duels flow (presentation/duels/duels_flow.gd energy()), which asks it at
## each start or join:
## - shown(): the server charges energy for this player (services/duel_energy.gd
##   enabled, from the duels capability). Every energy surface hides otherwise.
## - opened(): the lobby opened: a meter missing or older than its fresh time is
##   read with the wallet (services/pollen_client.gd flush, its energy part
##   through services/wallet_reply.gd), so the meter shows without a read nobody made.
## - meter(): the lobby header's pill (energy_meter.gd), or null.
## - blocks(): a start or join tapped while the kept meter says 0 opens the
##   out-of-energy card at once, and nothing is sent.
## - refused(): what the server said instead of starting: energy_empty opens the
##   card (and reads the meter again), partner_energy_empty says "<partner> is
##   waiting for energy" where the button is. energy_unavailable and every other
##   refusal stay with the caller's usual line. A refused start spends nothing,
##   and the meter, drawn only from the server's parts, never moved, so no line
##   says so.
## - the card's Refill opens the shared Fruit confirm through
##   presentation/fruit_spend_flow.gd refill_energy, offered only while Fruits
##   show and the meter is below its max.
const DuelEnergy = preload("res://services/duel_energy.gd")
const EnergyMeter = preload("res://presentation/duels/energy_meter.gd")
const OutCard = preload("res://presentation/duels/energy_out_card.gd")
const Kit = preload("res://presentation/duels/duel_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const NOTE := "EnergyWaiting"

## The duels flow this belongs to; Main through its host.
var flow: Node
## services/duel_energy.gd; tests set their own.
var store: RefCounted

func _init(duels_flow: Node, energy: RefCounted = null) -> void:
	flow = duels_flow
	store = energy if energy != null else DuelEnergy.shared()

func host() -> Node:
	return flow.host

## {server, owner} of the signed-in player, or {}.
func scope() -> Dictionary:
	var api: Variant = host().get("api")
	if api == null or not is_instance_valid(api): return {}
	var server: Variant = api.get("base_url")
	var owner: Variant = api.get("player_id")
	if not server is String or server.is_empty() or owner == null or str(owner).is_empty(): return {}
	return {"server": server, "owner": str(owner)}

## Whether the server charges duel energy for this player.
func shown() -> bool:
	var player := scope()
	return not player.is_empty() and store.enabled(str(player.server), str(player.owner))

## The lobby opened: the meter is read with the wallet when none is kept or it is old.
func opened() -> void:
	var player := scope()
	if player.is_empty() or not store.ask_fresh(str(player.server), str(player.owner)): return
	_read()

## The lobby header's meter, or null while energy is off.
func meter() -> Control:
	return EnergyMeter.pill(store, scope()) if shown() else null

## A start or join tapped on `page` from `control`: true (and the out-of-energy
## card opens) when the kept meter says none is left, so nothing is sent.
func blocks(page: CanvasLayer, control: Control) -> bool:
	if not shown(): return false
	var player := scope()
	if not store.empty_now(str(player.server), str(player.owner)): return false
	out_card(page, control)
	return true

## A start or join `answer` the server refused: true when it was energy's
## (handled here), false for the caller's usual line. `partner`: the partner's
## name for "is waiting for energy" ("" says your partner). `place(words)`: where a screen that
## redraws its rows keeps that line (the lobby's challenge cards); else it goes under the control.
func refused(page: CanvasLayer, answer: Dictionary, control: Control, partner: String = "", place: Callable = Callable()) -> bool:
	match str(answer.get("code", "")):
		"energy_empty":
			# services/duels_client.gd marked the kept meter empty; the read brings the minutes back.
			_read()
			if is_instance_valid(page) and page.alive(): out_card(page, control)
			return true
		"partner_energy_empty":
			if place.is_valid(): place.call(waiting_words(partner))
			else: note_under(control, waiting_words(partner))
			return true
	return false

## "Maya is waiting for energy" for `partner` ("" says your partner).
static func waiting_words(partner: String) -> String:
	var who := partner if not partner.is_empty() else PlayerCopy.DUEL_PARTNER.left(1).to_upper() + PlayerCopy.DUEL_PARTNER.substr(1)
	return PlayerCopy.ENERGY_PARTNER_WAITING % who

## The out-of-energy card over `page`, from `opener`.
func out_card(page: CanvasLayer, opener: Control = null) -> Control:
	if not is_instance_valid(page) or not page.alive(): return null
	var player := scope()
	var price := 0
	var spends: Node = host().get("fruit_spend_flow")
	if spends != null and spends.visible() and store.refill_offered(str(player.server), str(player.owner)):
		price = int(store.meter(str(player.server), str(player.owner)).refill_fruits)
	return OutCard.open(page, store, player, price, func(from: Control) -> void: refill(page, from), opener, Callable(host(), "_toast"))

## The refill's confirm (or short) card over `page`, kept as the page's own card so Back closes it first.
func refill(page: CanvasLayer, opener: Control = null) -> void:
	var spends: Node = host().get("fruit_spend_flow")
	if spends == null or not is_instance_valid(page) or not page.alive(): return
	var modal: Control = spends.refill_energy(page.root, opener)
	if modal != null: page.hold_modal(modal)

## Reads the wallet for the meter (its stale mark makes the flush read it).
func _read() -> void:
	var pollen: Variant = host().get("pollen_client")
	if pollen != null and pollen.has_method("flush"): pollen.flush()

## Says `words` right under the row `control` sits in (the nearest column
## holding it), in place of an earlier note there. The row's own redraw takes it away.
static func note_under(control: Control, words: String) -> void:
	if not is_instance_valid(control): return
	var child: Node = control
	var column := control.get_parent()
	while column != null and not column is VBoxContainer:
		child = column
		column = column.get_parent()
	if column == null: return
	var note := column.get_node_or_null(NOTE) as Label
	if note == null:
		note = Kit.wrapped(words, 15, UiTokens.SOFT)
		note.name = NOTE
	else: column.remove_child(note)
	note.text = words
	column.add_child(note)
	column.move_child(note, child.get_index() + 1)
