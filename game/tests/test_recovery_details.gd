extends SceneTree

const Parser = preload("res://services/recovery_details.gd")
# Synthetic values only. Test output identifies cases, never their input/result.
const PLAYER := "AbCdEfGhIjKlMnOpQrSt_-"
const CODE := PLAYER + "0123456789abcdefghij_"
const TITLE := "After You recovery details"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func _accept(text: String, description: String) -> void:
	var result: Dictionary = Parser.parse(text)
	_check(result == {"player_id": PLAYER, "recovery_code": CODE}, description)


func _reject(text: String, description: String) -> void:
	_check(Parser.parse(text).is_empty(), description)


func _block(player: String = PLAYER, recovery: String = CODE) -> String:
	return TITLE + "\nIdentity: " + player + "\nRecovery code: " + recovery


func _run() -> void:
	_check(PLAYER.length() == 22 and CODE.length() == 43, "Synthetic fixtures have wire-format lengths")
	var canonical := _block()
	_accept(canonical, "Canonical copied block yields exactly the two fields")
	_accept(canonical.replace("\n", "\r\n"), "Windows CRLF copy is accepted")
	_accept(canonical.replace("\n", "\r"), "Carriage-return separators are accepted")
	_accept(canonical.replace("\n", " "), "LineEdit newline-to-space flattening is accepted")
	_accept(canonical.replace("\n", "   "), "Flattened extra separating spaces are accepted")
	_accept(canonical.replace("\n", "\t"), "Tab separators are accepted")
	_accept(" \t\r\n" + canonical + "\r\n \t", "Leading and trailing whitespace is accepted")
	_accept("Identity: " + PLAYER + "\nRecovery code: " + CODE, "Optional title may be absent")
	_accept("Identity:" + PLAYER + " Recovery code:" + CODE, "Spaces after colons are optional")
	_accept("Identity:\n" + PLAYER + "\nRecovery code:\n" + CODE, "Wrapped values remain complete labelled fields")
	_accept("Identity: \t" + PLAYER + "\r\n\tRecovery code: \t" + CODE, "Mixed whitespace preserves token case and URL-safe symbols")
	_accept(canonical + " ".repeat(2048 - canonical.length()), "Exactly 2048 characters is accepted")
	_reject(canonical + " ".repeat(2049 - canonical.length()), "Input above 2048 characters is rejected")
	_reject(" ".repeat(2049), "Oversized blank input is rejected")
	_reject("", "Empty input is rejected")
	_reject(" \t\n", "Whitespace-only input is rejected")
	_reject(TITLE, "Title alone is not recovery details")
	_reject("Identity: " + PLAYER, "Missing recovery code stays unanswered")
	_reject("Recovery code: " + CODE, "Missing identity stays unanswered")
	_reject(PLAYER + " " + CODE, "Unlabelled tokens are not guessed")
	_reject(canonical + "\n" + canonical, "Two complete blocks are ambiguous")
	_reject(canonical + "\nIdentity: " + PLAYER, "Duplicate identity after a complete block is rejected")
	_reject("Identity: " + PLAYER + "\n" + canonical, "Duplicate identity before a block is rejected")
	_reject(canonical + "\nRecovery code: " + CODE, "Repeated identical recovery code is rejected")
	_reject(canonical + "\nRecovery code: " + "Z".repeat(43), "Contradictory recovery code is rejected")
	_reject(canonical + "\nIdentity: " + "Z".repeat(22), "Contradictory identity is rejected")
	_reject(TITLE + "\n" + canonical, "Repeated title is rejected")
	_reject("Please use these:\n" + canonical, "Unknown prefix is rejected")
	_reject(canonical + "\nKeep this safe.", "Unknown suffix is rejected")
	_reject("Identity: " + PLAYER + " note Recovery code: " + CODE, "Unknown content between fields is rejected")
	_reject("Recovery code: " + CODE + " Identity: " + PLAYER, "Unexpected field order does not silently reinterpret a block")
	_reject(canonical.replace("Identity:", "Identity="), "Malformed identity label is rejected")
	_reject(canonical.replace("Recovery code:", "Recovery token:"), "Unknown recovery label is rejected")
	_reject(canonical.replace(TITLE, "Another app recovery details"), "An unrelated title is rejected")
	_reject(canonical.replace("\n", ""), "Missing field boundaries are rejected")
	_reject(_block(PLAYER.left(21)), "Short identity is rejected")
	_reject(_block(PLAYER + "x"), "Long identity is rejected")
	_reject(_block(PLAYER, CODE.left(42)), "Short recovery code is rejected")
	_reject(_block(PLAYER, CODE + "x"), "Long recovery code is rejected")
	_reject(_block(PLAYER + "="), "Padded base64 identity is rejected")
	_reject(_block(PLAYER, CODE + "="), "Padded base64 recovery code is rejected")
	var forbidden := ["+", "/", ".", ":", " ", "\n", "é", "А", "\u200B", "\u0001"]
	for index in forbidden.size():
		var invalid: String = forbidden[index]
		_reject(_block(PLAYER.left(8) + invalid + PLAYER.substr(9)), "Unsupported identity character case %d is rejected" % index)
		_reject(_block(PLAYER, CODE.left(8) + invalid + CODE.substr(9)), "Unsupported recovery character case %d is rejected" % index)
	_reject("\u0001" + canonical, "Leading non-whitespace control is not trimmed into valid input")
	_reject(canonical + "\u0001", "Trailing non-whitespace control is not trimmed into valid input")
	_reject(canonical + "\nUnexpected: value\n", "Trailing-newline anchor cannot hide content")
	var modified_result: Dictionary = Parser.parse(canonical)
	modified_result["player_id"] = "changed"
	_accept(canonical, "Caller mutation cannot affect a subsequent parse")
	print("Recovery details: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
