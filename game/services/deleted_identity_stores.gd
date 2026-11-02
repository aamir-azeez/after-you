extends RefCounted
## Forgets a deleted player's part of the files every player of this phone
## shares (names, friends, nicknames, Pollen, wardrobe, leaderboard, duels).
##
## Account deletion calls forget() once the identity's secret is removed. A
## marker naming the deleted player goes on first, so a clear that cannot write,
## or the app closing part way, finishes on the next launch (resume()). The
## marker keeps the stores still to clear and goes only when every one reports
## success. It holds player ids, their server and store names, never a secret.
## Every clear touches only that player's entries, so going again is harmless,
## even once a new identity plays here.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const DisplayNames = preload("res://services/display_names.gd")
const FriendRoster = preload("res://services/friend_roster.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const LeaderboardRuns = preload("res://services/leaderboard_runs.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const StoreSupport = preload("res://services/store_support.gd")
const LeaderboardPlacings = preload("res://services/leaderboard_placings.gd")
const LeaderboardClient = preload("res://services/leaderboard_client.gd")
const PATH := "user://deleted_identity_stores.json"
const VERSION := 1
## Every store cleared, in order, by the name a marker keeps for one still to finish.
const STORES := ["nicknames", "names", "friends", "wallet", "wardrobe", "runs", "duels", "bundle_claims", "monthly_pollen", "store_support", "placings", "name_choice"]
## Deletions kept waiting; more than this keeps the newest.
const MAX_OWNERS := 8
const MAX_SERVER := 2048

var path := PATH

func _init(storage_path: String = PATH) -> void:
	path = storage_path

## Forgets `owner` (deleted on `server`) in every shared store. `nicknames` is
## Main's friend nickname store (services/friend_nicknames.gd). True when every
## clear succeeded; otherwise the marker keeps the rest for resume().
func forget(owner: String, server: String, nicknames: RefCounted) -> bool:
	if not Typed.valid_id(owner): return false
	var marked := _note(owner, server, STORES)
	# The clears run even without a marker, as they always have.
	var left := clear(owner, server, nicknames)
	if marked: _note(owner, server, left)
	return left.is_empty()

## App start: finishes the clears a failed write or a closed app left. Without
## a marker this is one file check.
func resume(nicknames: RefCounted) -> void:
	if not FileAccess.file_exists(path): return
	var waiting_now: Array = []
	for entry: Dictionary in _read():
		var left := clear(entry.owner, entry.server, nicknames, entry.stores)
		if not left.is_empty(): waiting_now.append({"owner": entry.owner, "server": entry.server, "stores": left})
	_write(waiting_now)

## Clears `owner` from each of `stores` (names in STORES), each tried even when
## one before it failed. The names of those that did not finish.
func clear(owner: String, server: String, nicknames: RefCounted, stores: Array = STORES) -> Array:
	if not Typed.valid_id(owner): return stores.duplicate()
	return stores.filter(func(store: String) -> bool: return not _clear(store, owner, server, nicknames))

## Deletions still waiting (tests).
func waiting() -> Array:
	return _read() if FileAccess.file_exists(path) else []

func _clear(store: String, owner: String, server: String, nicknames: RefCounted) -> bool:
	match store:
		"nicknames": return nicknames != null and nicknames.clear_owner(owner, server)
		"names": return DisplayNames.shared().clear_owner(owner)
		"friends": return FriendRoster.shared().clear_owner(owner)
		"wallet": return PollenWallet.shared().clear_owner(owner)
		"wardrobe": return Wardrobe.shared().clear_owner(owner)
		"runs": return LeaderboardRuns.clear_owner(owner)
		"duels": return DuelsClient.clear_owner(owner)
		"bundle_claims": return BundleClaims.shared().clear_owner(owner)
		"monthly_pollen": return PollenGrant.shared().clear_owner(owner)
		"store_support": return StoreSupport.shared().clear_owner(owner)
		"placings": return LeaderboardPlacings.shared().clear_owner(owner)
		"name_choice": return LeaderboardClient.clear_owner(owner)
	return false

## Keeps `stores` as what `owner` still needs (none drops the entry). False when
## the marker could not be written.
func _note(owner: String, server: String, stores: Array) -> bool:
	var owners := _read()
	var at := -1
	for index in range(owners.size()):
		if owners[index].owner == owner and owners[index].server == server: at = index
	var entry := {"owner": owner, "server": server, "stores": stores}
	if at < 0 and stores.is_empty(): return true
	if at < 0: owners.append(entry)
	elif stores.is_empty(): owners.remove_at(at)
	else: owners[at] = entry
	return _write(owners.slice(-MAX_OWNERS))

func _read() -> Array:
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("owners") is Array)
	var owners: Array = []
	if not parsed is Dictionary: return owners
	for entry: Variant in parsed.owners:
		if not entry is Dictionary or not Typed.valid_id(entry.get("owner")) or not entry.get("server") is String or str(entry.server).length() > MAX_SERVER: continue
		# Stores kept in STORES order; a list that names none of them means every one.
		var named: Array = entry.get("stores") if entry.get("stores") is Array else []
		var stores: Array = STORES.filter(func(store: String) -> bool: return store in named)
		owners.append({"owner": entry.owner, "server": entry.server, "stores": stores if not stores.is_empty() else STORES.duplicate()})
	return owners.slice(-MAX_OWNERS)

func _write(owners: Array) -> bool:
	if owners.is_empty():
		# A damaged marker read as none: the copy kept aside of it goes too.
		var removed := AtomicFile.remove(path)
		return AtomicFile.remove_unreadable(path) and removed
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "owners": owners}))
