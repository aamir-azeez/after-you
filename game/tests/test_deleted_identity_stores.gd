extends SceneTree
## Account deletion's clears of the files every player of this phone shares
## (services/deleted_identity_stores.gd): a failed write or a closed app
## finishes on the next launch, and only the deleted player's part ever goes.
const Stores = preload("res://services/deleted_identity_stores.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Nicknames = preload("res://services/friend_nicknames.gd")
const DisplayNames = preload("res://services/display_names.gd")
const FriendRoster = preload("res://services/friend_roster.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Duels = preload("res://services/duels_client.gd")
const BundleClaims = preload("res://services/bundle_claims.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const StoreSupport = preload("res://services/store_support.gd")
const TesterSwitches = preload("res://services/tester_switches.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Board = preload("res://services/leaderboard_client.gd")
const SERVER := "https://stores.test"
## The deleted player, a second deleted player, and the new identity playing since.
const OWNER := "HHHHHHHHHHHHHHHHHHHHHH"
const SECOND := "JJJJJJJJJJJJJJJJJJJJJJ"
const NEW := "GGGGGGGGGGGGGGGGGGGGGG"
const FRIEND := "FFFFFFFFFFFFFFFFFFFFFF"
## Stores that keep every player in one {"schema_version", "scopes": {"server|owner": ...}} file.
const SCOPED := {"wallet": PollenWallet, "wardrobe": Wardrobe, "bundle claims": BundleClaims, "monthly Pollen": PollenGrant, "App Store support": StoreSupport, "names": DisplayNames, "friends": FriendRoster, "tester switches": TesterSwitches}
const SCOPE_VALUES := {"wallet": {}, "wardrobe": {}, "bundle claims": {"pending": true}, "monthly Pollen": {"enabled": true}, "App Store support": true, "names": {"enabled": true}, "friends": {}, "tester switches": {"full_journey_off": true}}
## Every shared store: the scoped ones, runs, placings, duels, name choice and nicknames.
const ALL := 13

var checks := 0
var failures := 0
var directory := ""
var nicknames: RefCounted

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _run() -> void:
	directory = "user://deleted-stores-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	_resume_after_close()
	_failed_write_finishes_later()
	_marker_merges_and_reads_safely()
	_no_marker_is_cheap()
	_restore()
	print("AFTER YOU DELETED IDENTITY STORES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	return directory.path_join(label.replace(" ", "-") + ".json")

func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()

func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Every store holds `owners`, as the files a fresh launch reads.
func _seed(owners: Array) -> void:
	for label: String in SCOPED:
		var scopes := {}
		for owner: String in owners: scopes[SERVER + "|" + owner] = SCOPE_VALUES[label]
		_write(_path(label), {"schema_version": 1, "scopes": scopes})
	var run := {"board": "relay-isles@2", "entry_id": "a".repeat(32), "ticks": 300, "assisted": false, "finished_at": "", "partner": ""}
	var players := {}
	var placings := {}
	var duels := {}
	var choices := {}
	for owner: String in owners:
		players[owner] = [run]
		placings[owner] = {"shown": [], "pending": []}
		duels[owner] = {"rooms": {}, "rung": []}
		choices[owner] = {"show": true, "pending": false}
	_write(_path("runs"), {"schema_version": 1, "players": players})
	_write(_path("placings"), {"version": 1, "players": placings})
	_write(Duels.SAVE_PATH, duels)
	_write(Board.CHOICE_PATH, choices)
	nicknames = Nicknames.new(_path("nicknames"))
	for owner: String in owners: nicknames.set_nickname(SERVER, owner, FRIEND, "Buddy")
	_install()

## Fresh shared stores read from the seeded files (an app launch).
func _install() -> void:
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	var wardrobe: RefCounted = Wardrobe.new(_path("wardrobe"))
	PollenWallet.use_shared(wallet)
	Wardrobe.use_shared(wardrobe)
	BundleClaims.use_shared(BundleClaims.new(_path("bundle claims"), wardrobe, wallet))
	PollenGrant.use_shared(PollenGrant.new(_path("monthly Pollen")))
	StoreSupport.use_shared(StoreSupport.new(_path("App Store support")))
	TesterSwitches.use_shared(TesterSwitches.new(_path("tester switches")))
	DisplayNames.use_shared(DisplayNames.new(_path("names")))
	FriendRoster.use_shared(FriendRoster.new(_path("friends")))
	Placings.use_shared(Placings.new(_path("placings")))
	Runs.use_path(_path("runs"))

## The stores whose files still hold `owner`.
func _holding(owner: String) -> Array:
	var found: Array = []
	for label: String in SCOPED:
		var kept: Variant = _read(_path(label))
		if kept is Dictionary and kept.scopes.has(SERVER + "|" + owner): found.append(label)
	var runs: Variant = _read(_path("runs"))
	if runs is Dictionary and runs.players.has(owner): found.append("runs")
	var placings: Variant = _read(_path("placings"))
	if placings is Dictionary and placings.players.has(owner): found.append("placings")
	for pair: Array in [["duels", Duels.SAVE_PATH], ["name choice", Board.CHOICE_PATH]]:
		var kept: Variant = _read(pair[1])
		if kept is Dictionary and kept.has(owner): found.append(pair[0])
	if not Nicknames.new(_path("nicknames")).nickname(SERVER, owner, FRIEND).is_empty(): found.append("nicknames")
	return found

func _stores() -> RefCounted:
	return Stores.new(_path("marker"))

## The app closed after the marker went on and before (or part way through)
## the clears; a new identity has played since. The next launch finishes the
## deleted player only.
func _resume_after_close() -> void:
	_seed([OWNER, NEW])
	check(_holding(OWNER).size() == ALL and _holding(NEW).size() == ALL, "Every store holds both players before: %s" % [_holding(OWNER)])
	_write(_path("marker"), {"schema_version": 1, "owners": [{"owner": OWNER, "server": SERVER}]})
	_stores().resume(nicknames)
	check(_holding(OWNER).is_empty(), "The next launch forgets the deleted player everywhere: %s" % [_holding(OWNER)])
	check(_holding(NEW).size() == ALL, "and keeps every part of the new identity: %s" % [_holding(NEW)])
	check(not FileAccess.file_exists(_path("marker")), "The marker goes once every clear succeeded")
	# Going again is harmless; a store list naming no store this build knows means every one.
	_write(_path("marker"), {"schema_version": 1, "owners": [{"owner": OWNER, "server": SERVER, "stores": ["a_later_store"]}]})
	_install()
	_stores().resume(nicknames)
	check(_holding(OWNER).is_empty() and _holding(NEW).size() == ALL and not FileAccess.file_exists(_path("marker")), "A second resume of the same deletion changes nothing else")

## One store cannot write: the others still clear, the marker stays, and the
## next launch finishes it.
func _failed_write_finishes_later() -> void:
	_seed([OWNER, NEW])
	var blocked := _path("wallet") + AtomicFile.TMP
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	var stores := _stores()
	check(not stores.forget(OWNER, SERVER, nicknames), "A clear that cannot write reports the deletion unfinished")
	check(_holding(OWNER) == ["wallet"], "Every other store still forgot the player: %s" % [_holding(OWNER)])
	check(stores.waiting() == [{"owner": OWNER, "server": SERVER, "stores": ["wallet"]}], "The marker names the deleted player, server and the store left, and nothing else: %s" % [stores.waiting()])
	var marker := FileAccess.get_file_as_string(_path("marker"))
	check(not "token" in marker and not "secret" in marker, "The marker holds no credential")
	# A damaged copy another store keeps aside (a new identity's) would go if that finished store ran again.
	var kept_aside := _path("names") + ".unreadable-test"
	_write(kept_aside, "{damaged")
	_install()
	_stores().resume(nicknames)
	check(_holding(OWNER) == ["wallet"] and FileAccess.file_exists(_path("marker")), "A launch whose write still fails keeps the marker")
	check(FileAccess.file_exists(kept_aside), "and goes again only to the store left, so a finished store is not cleared again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kept_aside))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	_install()
	_stores().resume(nicknames)
	check(_holding(OWNER).is_empty() and _holding(NEW).size() == ALL, "The next launch finishes the wallet and keeps the new identity's: %s" % [_holding(NEW)])
	check(not FileAccess.file_exists(_path("marker")), "and removes the marker")
	_seed([OWNER, NEW])
	check(_stores().forget(OWNER, SERVER, nicknames) and _holding(OWNER).is_empty() and _holding(NEW).size() == ALL, "A deletion whose clears all succeed forgets only that player")
	check(not FileAccess.file_exists(_path("marker")), "and leaves no marker behind")

## A second deletion while one waits keeps both; an invalid or damaged marker
## never clears anyone.
func _marker_merges_and_reads_safely() -> void:
	_seed([OWNER, SECOND, NEW])
	var blocked := _path("placings") + AtomicFile.TMP
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	var stores := _stores()
	check(not stores.forget(OWNER, SERVER, nicknames) and not stores.forget(SECOND, SERVER, nicknames) and not stores.forget(OWNER, SERVER, nicknames), "Unfinished deletions report so")
	check(stores.waiting() == [{"owner": OWNER, "server": SERVER, "stores": ["placings"]}, {"owner": SECOND, "server": SERVER, "stores": ["placings"]}], "Both deletions wait, each once: %s" % [stores.waiting()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	_install()
	_stores().resume(nicknames)
	check(_holding(OWNER).is_empty() and _holding(SECOND).is_empty() and _holding(NEW).size() == ALL, "The next launch finishes both and keeps the new identity")
	check(not stores.forget("not-an-id", SERVER, nicknames) and not FileAccess.file_exists(_path("marker")), "An invalid player id is refused and marks nothing")
	_seed([OWNER, NEW])
	for bad: Variant in ["{not json", {"schema_version": 2, "owners": [{"owner": NEW, "server": SERVER}]}, {"schema_version": 1, "owners": [{"owner": "short", "server": SERVER}, {"owner": NEW, "server": 7}]}]:
		_write(_path("marker"), bad)
		_stores().resume(nicknames)
		check(_holding(NEW).size() == ALL and _holding(OWNER).size() == ALL, "A marker that does not read clears no one: %s" % [bad])
		check(not FileAccess.file_exists(_path("marker")), "and is removed")
	check(not Array(DirAccess.get_files_at(directory)).any(func(name: String) -> bool: return name.begins_with("marker.json.unreadable-")), "with the damaged copy kept aside of it")

## Without a marker the launch writes nothing.
func _no_marker_is_cheap() -> void:
	_seed([OWNER, NEW])
	var before := _digests()
	_stores().resume(nicknames)
	check(_digests() == before and _holding(OWNER).size() == ALL, "A launch with no deletion waiting changes no file")
	check(Stores.new().waiting().is_empty() and not FileAccess.file_exists(Stores.PATH), "and creates no marker")

## Each file of the test folder (and the duels and name choice files) by its SHA-256, but `skip`.
func _digests(skip: Array = []) -> Dictionary:
	var found := {}
	for name: String in DirAccess.get_files_at(directory):
		var path := directory.path_join(name)
		if not path in skip: found[path] = FileAccess.get_sha256(path)
	for path: String in [Duels.SAVE_PATH, Board.CHOICE_PATH]: found[path] = FileAccess.get_sha256(path)
	return found

func _restore() -> void:
	for store: Variant in [PollenWallet, Wardrobe, BundleClaims, PollenGrant, StoreSupport, TesterSwitches, DisplayNames, FriendRoster, Placings]: store.use_shared(null)
	Runs.use_path(Runs.PATH)
	for path: String in [Duels.SAVE_PATH, Board.CHOICE_PATH]:
		AtomicFile.remove(path)
		AtomicFile.remove_unreadable(path)
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
