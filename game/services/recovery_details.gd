class_name RecoveryDetails
extends RefCounted
## Parses the complete copied recovery block locally. Never log input or results.

const MAX_TEXT_LENGTH := 2048
const BLOCK_PATTERN := "\\A[ \\t\\r\\n]*(?:After You recovery details[ \\t\\r\\n]+)?Identity:[ \\t\\r\\n]*([A-Za-z0-9_-]{22})[ \\t\\r\\n]+Recovery code:[ \\t\\r\\n]*([A-Za-z0-9_-]{43})[ \\t\\r\\n]*\\z"


static func parse(text: String) -> Dictionary:
	if text.is_empty() or text.length() > MAX_TEXT_LENGTH:
		return {}
	# Anchoring the entire block rejects duplicate labels and extra content instead
	# of silently choosing which identity or recovery code the player intended.
	var expression := RegEx.new()
	if expression.compile(BLOCK_PATTERN) != OK:
		return {}
	var matched := expression.search(text)
	if matched == null:
		return {}
	return {"player_id": matched.get_string(1), "recovery_code": matched.get_string(2)}
