extends RefCounted
## Only a locally bundled story matching the campaign's immutable pin can bind.
## Dialogue is cosmetic and never supplies gameplay, room or entitlement state.
const Protocol = preload("res://services/campaign_protocol.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MAX_BYTES := 65536
var _content: Dictionary = {}

func bind(content: Variant, definition: Dictionary) -> bool:
	_content = {}
	if not content_valid(content) or not Protocol.definition_valid(definition): return false
	if not Canonical.same(pin(content), definition.story) or content.chapters.size() != definition.chapters.size(): return false
	for index in range(content.chapters.size()):
		var chapter: Dictionary = content.chapters[index]
		var expected: Dictionary = definition.chapters[index]
		if chapter.level_id != expected.level_id or chapter.level_version != expected.level_version: return false
	_content = content.duplicate(true)
	return true

func title() -> String:
	return str(_content.get("title", ""))

func summary() -> String:
	return str(_content.get("summary", ""))

func lines(index: int, phase: String) -> Array:
	if _content.is_empty() or index < 0 or index >= _content.chapters.size() or phase not in ["arrival", "completion"]: return []
	return _content.chapters[index][phase].duplicate(true)

static func pin(content: Dictionary) -> Dictionary:
	return {"story_id":content.get("story_id"), "story_version":content.get("story_version"), "content_hash":content.get("content_hash")}

static func content_valid(content: Variant) -> bool:
	if not Protocol.bounded(content, MAX_BYTES) or not Protocol.exact(content, ["schema_version", "story_id", "story_version", "content_hash", "title", "summary", "chapters"]): return false
	if content.schema_version != 1 or not Protocol.slug(content.story_id) or not Protocol.integer(content.story_version, 1) or not Protocol.hash_valid(content.content_hash): return false
	if not _text(content.title, 96) or not _text(content.summary, 280) or not content.chapters is Array or content.chapters.size() < 2 or content.chapters.size() > Protocol.MAX_CHAPTERS: return false
	for chapter: Variant in content.chapters:
		if not Protocol.exact(chapter, ["level_id", "level_version", "arrival", "completion"]) or not Protocol.slug(chapter.level_id) or not Protocol.integer(chapter.level_version, 1): return false
		for phase: String in ["arrival", "completion"]:
			if not chapter[phase] is Array or chapter[phase].is_empty() or chapter[phase].size() > 3: return false
			for line: Variant in chapter[phase]:
				if not Protocol.exact(line, ["speaker", "text"]) or line.speaker not in ["p0", "p1"] or not _text(line.text, 280): return false
	var body: Dictionary = content.duplicate(true)
	body.erase("content_hash")
	return Canonical.digest(body) == content.content_hash

static func _text(value: Variant, maximum: int) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum or value.strip_edges() != value: return false
	for index in range(value.length()):
		var codepoint: int = value.unicode_at(index)
		if codepoint < 32 or codepoint == 127: return false
	return true
