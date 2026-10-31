extends RefCounted
## The Pollen from play page's data (pollen board 7b), from GET /v1/pollen/history
## (services/pollen_client.gd history), checked before anything shows:
## - turns: the newest paid turns, newest first, each {amount, at, level_id,
##   stage_id, role, bonuses, bloom, reason}; a turn of a chapter this build
##   does not know, or that is not the contract's, is left out;
## - first_clears: each free chapter this build knows, {level_id, price, paid},
##   paid -1 until its first clear is paid, in the server's order. Paid chapters
##   are left out: the page names them in one sentence (and not at all on a build
##   that names no Full Journey);
## - bank: {left, refill, cap, tail: [{pay, turns}]}, or {} from a server that
##   does not send it. The numbers come from the server, never from the app.
## - purchases: each Pollen bundle bought or taken back by a refund, newest
##   first, {kind ("bundle" or "bundlerefund"), bundle, amount (negative for a
##   refund), at, order ("" when unknown), usd_cents (-1 when unknown)}, from the
##   server's own list (every line, never pushed out by turns). A server from
##   before that list has only the bundle lines among the newest entries.
## - spent_usd_cents: the money spent on bundles, refunds taken off, in US
##   cents as Google Play reported it: the server's figure, or -1 from a server
##   that sends none (its few lines would undercount; the flow then asks the
##   wallet read's figure).
## A purchases part off the contract reads as no purchases; the rest still shows.
## A history that is not the contract's reads as {}, and the page says so.
const Typed = preload("res://services/typed_values.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Bundles = preload("res://services/pollen_bundles.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")

const MAX_ENTRIES := 50
const BONUSES := ["first_try", "gold_pace", "silver_pace", "hard"]
const REASONS := ["repeat", "bank_empty", "late"]
const PURCHASE_KINDS := ["bundle", "bundlerefund"]
## As the server's PURCHASE_LIMIT (backend/src/pollen/wallet.ts).
const MAX_PURCHASES := 100

static var _order := RegEx.create_from_string(BundleClaims.ORDER_PATTERN)

static func checked(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not value.get("entries") is Array or value.entries.size() > MAX_ENTRIES: return {}
	var turns: Array[Dictionary] = []
	for entry: Variant in value.entries:
		var turn := _turn(entry)
		if not turn.is_empty(): turns.append(turn)
	var clears: Array[Dictionary] = []
	if value.get("first_clears") is Array:
		for clear: Variant in value.first_clears:
			if not clear is Dictionary or not _count(clear.get("price")) or (clear.has("paid") and not _count(clear.paid)): continue
			var key := chapter_key(clear.get("level_id"))
			if key.is_empty() or bool(Registry.descriptor(key).get("premium", false)): continue
			clears.append({"level_id": clear.level_id, "price": Typed.as_int(clear.price), "paid": Typed.as_int(clear.paid) if clear.has("paid") else -1})
	var sent: Variant = value.get("purchases") if value.has("purchases") else value.entries
	var purchases: Array[Dictionary] = []
	if sent is Array:
		for entry: Variant in (sent as Array).slice(0, MAX_PURCHASES):
			var line := _purchase(entry)
			if not line.is_empty(): purchases.append(line)
	var spent: Variant = value.get("spent_usd_cents")
	return {"turns": turns, "first_clears": clears, "bank": _bank(value.get("bank")), "purchases": purchases,
		"spent_usd_cents": Typed.as_int(spent) if _count(spent) and value.has("purchases") else -1}

## One bundle or refund line as kept, or {} (a turn's entry, or one off the contract).
static func _purchase(entry: Variant) -> Dictionary:
	if not entry is Dictionary or not entry.get("kind") in PURCHASE_KINDS or not str(entry.get("bundle", "")) in Bundles.ids() or not _count(entry.get("at")): return {}
	var amount: Variant = entry.get("amount")
	if not Typed.whole_number(amount) or (float(amount) <= 0.0 if entry.kind == "bundle" else float(amount) >= 0.0): return {}
	var order: Variant = entry.get("order", "")
	if not order is String or (not order.is_empty() and _order.search(order) == null): return {}
	var cents: Variant = entry.get("usd_cents")
	var kept := {"kind": entry.kind, "bundle": str(entry.bundle), "amount": Typed.as_int(amount), "at": Typed.as_int(entry.at), "order": order, "usd_cents": Typed.as_int(cents) if _count(cents) else -1}
	# An App Store line says so ("store": "app_store"); a Play line names no store, as before.
	if entry.get("store") == Bundles.APP_STORE: kept["store"] = Bundles.APP_STORE
	return kept

static func _turn(entry: Variant) -> Dictionary:
	if not entry is Dictionary or entry.get("kind") != "turn" or not Typed.whole_number(entry.get("amount")) or not _count(entry.get("at")): return {}
	if chapter_key(entry.get("level_id")).is_empty() or not entry.get("stage_id") is String or not entry.get("role") in ["a", "b"]: return {}
	var bonuses: Variant = entry.get("bonuses", [])
	if not bonuses is Array or bonuses.any(func(bonus: Variant) -> bool: return not bonus in BONUSES): return {}
	var bloom := Typed.as_int(entry.get("bloom", 1), 0)
	if not bloom in [1, 2, 3] or not entry.get("reason", "") in [""] + REASONS: return {}
	return {"amount": Typed.as_int(entry.amount), "at": Typed.as_int(entry.at), "level_id": entry.level_id, "stage_id": entry.stage_id, "role": entry.role,
		"bonuses": bonuses.duplicate(), "bloom": bloom, "reason": str(entry.get("reason", ""))}

static func _bank(value: Variant) -> Dictionary:
	if not value is Dictionary or not _count(value.get("left")) or not _count(value.get("refill")) or not _count(value.get("cap")) or not value.get("tail") is Array or value.tail.size() > 4: return {}
	var tail := []
	for step: Variant in value.tail:
		if not step is Dictionary or not _count(step.get("pay")) or not _count(step.get("turns")): return {}
		tail.append({"pay": Typed.as_int(step.pay), "turns": Typed.as_int(step.turns)})
	return {"left": Typed.as_int(value.left), "refill": Typed.as_int(value.refill), "cap": Typed.as_int(value.cap), "tail": tail}

static func _count(value: Variant) -> bool:
	return Typed.whole_number(value) and float(value) >= 0.0

## The newest chapter this build offers for a level id, or "".
static func chapter_key(level_id: Variant) -> String:
	if not level_id is String: return ""
	var found := ""
	for key: String in Registry.offered_keys():
		if key.get_slice("@", 0) == level_id: found = key
	return found

## "The Wishing Well" for a level id, or "".
static func chapter_title(level_id: String) -> String:
	var key := chapter_key(level_id)
	return "" if key.is_empty() else str(Registry.descriptor(key).get("title", ""))

## A stage's number in its chapter (1 for the first), or 0 when this build does not know it.
static func stage_number(level_id: String, stage_id: String) -> int:
	var key := chapter_key(level_id)
	if key.is_empty(): return 0
	var stages: Array = Registry.definition(key).get("stages", [])
	for index in range(stages.size()):
		if str(stages[index].get("id", "")) == stage_id: return index + 1
	return 0
