extends RefCounted
## Presentation keys include the separate Lighthouse and earlier-island catalogs.
const ENTRIES := [
	{"key":"sleeping-lighthouse","title":"Sleeping Lighthouse","stages":6,"together":false},
	{"key":"rolling-home","title":"Rolling Home","stages":2,"together":true},
	{"key":"a-house-for-two","title":"A House for Two","stages":2,"together":true},
	{"key":"conservatory","title":"Conservatory","stages":2,"together":true},
	{"key":"long-way-home","title":"Long Way Home","stages":2,"together":true},
	{"key":"legacy-rising-together","title":"Rising Together","stages":1,"together":true},
	{"key":"legacy-across-the-blue","title":"Across the Blue","stages":1,"together":true},
	{"key":"legacy-lantern-crossing","title":"Lantern Crossing","stages":1,"together":true},
	{"key":"legacy-two-beats","title":"Two Beats","stages":1,"together":true},
	{"key":"legacy-after-you","title":"After You","stages":1,"together":true},
]

static func keys() -> Array[String]:
	var result: Array[String] = []
	for item: Dictionary in ENTRIES: result.append(item.key)
	return result

static func entry(key: String) -> Dictionary:
	for item: Dictionary in ENTRIES:
		if item.key == key:
			var result := item.duplicate(true)
			result["texture"] = "res://assets/paid_levels/" + key + ".png"
			return result
	return {}
