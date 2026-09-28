extends RefCounted
## Exact bundled content only. Callers receive independently validated copies.
const Story = preload("res://services/campaign_story.gd")
const Protocol = preload("res://services/campaign_protocol.gd")
const BUNDLE_PATH := "res://content/campaigns/a-place-for-two-v1.json"
const MAX_BUNDLE_BYTES := Story.MAX_BYTES + Protocol.MAX_CONTROL_BYTES + 64

static func bundled() -> Array:
	var file := FileAccess.open(BUNDLE_PATH, FileAccess.READ)
	if file == null or file.get_length() > MAX_BUNDLE_BYTES: return []
	return _validated(JSON.parse_string(file.get_as_text()))

static func _validated(value: Variant) -> Array:
	if not Protocol.exact(value, ["definition", "story"]) or not value.definition is Dictionary: return []
	var story := Story.new()
	if not story.bind(value.story, value.definition): return []
	return [value.duplicate(true)]
