extends SceneTree

const Story = preload("res://services/campaign_story.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/campaign/control-v2.json"))
	var definition: Dictionary = fixture.definition.duplicate(true)
	var content := {"schema_version":1,"story_id":"test-story","story_version":1,"content_hash":"","title":"Test title","summary":"Test summary","chapters":[]}
	for chapter: Dictionary in definition.chapters:
		content.chapters.append({"level_id":chapter.level_id,"level_version":chapter.level_version,"arrival":[{"speaker":"p0","text":"First test line."}],"completion":[{"speaker":"p1","text":"Second test line."}]})
	content.content_hash = _hash(content, "content_hash")
	definition.story = Story.pin(content)
	definition.definition_hash = _hash(definition, "definition_hash")
	var story := Story.new()
	_check(story.bind(content,definition), "Exact locally pinned story binds to its chapter sequence")
	var lines: Array = story.lines(0,"arrival")
	lines[0].text = "Edited by a view"
	content.chapters[0].arrival[0].text = "Edited by caller"
	_check(story.lines(0,"arrival")[0].text == "First test line.", "Caller and presentation edits cannot change bound dialogue")
	_check(story.lines(-1,"arrival").is_empty() and story.lines(8,"arrival").is_empty() and story.lines(0,"turn").is_empty(), "Only known bounded interlude phases are exposed")
	_check(not story.bind(content,definition) and story.title().is_empty(), "Changed prose with an old hash clears the previous bound story")
	content.chapters[0].arrival[0].text = "First test line."
	var foreign := definition.duplicate(true)
	foreign.story.story_version = 2
	foreign.definition_hash = _hash(foreign,"definition_hash")
	_check(not story.bind(content,foreign), "Valid campaign hash does not authorize a different story revision")
	var reordered := content.duplicate(true)
	reordered.chapters.reverse()
	reordered.content_hash = _hash(reordered,"content_hash")
	foreign = definition.duplicate(true)
	foreign.story = Story.pin(reordered)
	foreign.definition_hash = _hash(foreign,"definition_hash")
	_check(not story.bind(reordered,foreign), "Rehashed dialogue cannot be applied to another chapter order")
	for field: String in ["title","summary"]:
		var changed := content.duplicate(true)
		changed[field] = "Hidden\u0001control"
		changed.content_hash = _hash(changed,"content_hash")
		_check(not Story.content_valid(changed), "Invisible control characters are rejected")
	var wrong := content.duplicate(true)
	wrong.chapters[0].arrival[0].speaker = "server"
	wrong.content_hash = _hash(wrong,"content_hash")
	_check(not Story.content_valid(wrong), "Dialogue cannot invent a third authoritative speaker")
	wrong = content.duplicate(true)
	wrong.chapters[0].arrival.append_array(wrong.chapters[0].arrival.duplicate(true))
	wrong.chapters[0].arrival.append_array(wrong.chapters[0].arrival.duplicate(true))
	wrong.content_hash = _hash(wrong,"content_hash")
	_check(not Story.content_valid(wrong), "Each interlude stays within three short lines")
	var maximum := content.duplicate(true)
	maximum.chapters = []
	for index in range(8):
		var chapter: Dictionary = content.chapters[index % content.chapters.size()].duplicate(true)
		for phase: String in ["arrival","completion"]:
			chapter[phase] = []
			for line_index in range(3): chapter[phase].append({"speaker":"p0" if line_index % 2 == 0 else "p1","text":"🌱".repeat(280)})
		maximum.chapters.append(chapter)
	maximum.content_hash = _hash(maximum,"content_hash")
	_check(Story.content_valid(maximum), "Eight chapters with maximum four-byte Unicode dialogue fit the byte and node envelope")
	maximum.chapters[7].completion[2].text += "🌱"
	maximum.content_hash = _hash(maximum,"content_hash")
	_check(not Story.content_valid(maximum), "A 281st character is rejected even with a valid content digest")
	for mismatch: String in ["count","version"]:
		wrong = content.duplicate(true)
		if mismatch == "count": wrong.chapters.append(wrong.chapters[0].duplicate(true))
		else: wrong.chapters[0].level_version += 1
		wrong.content_hash = _hash(wrong,"content_hash")
		foreign = definition.duplicate(true)
		foreign.story = Story.pin(wrong)
		foreign.definition_hash = _hash(foreign,"definition_hash")
		_check(Story.content_valid(wrong) and not story.bind(wrong,foreign), "A rehashed chapter %s mismatch cannot bind" % mismatch)
	print("CAMPAIGN STORY: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _hash(value: Dictionary, field: String) -> String:
	var body := value.duplicate(true)
	body.erase(field)
	return Canonical.digest(body)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
