extends Label
## Text always accompanies the dot; status never relies on colour alone.
var service: Node
var family := ""
var room_id := ""

func configure(owner_service: Node, room_family: String, room: String) -> void:
	service = owner_service
	family = room_family
	room_id = room

func _ready() -> void:
	name = "FriendPresence"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 16)
	if is_instance_valid(service): service.changed.connect(_update)
	_update()

func _update() -> void:
	var status: Dictionary = service.view(family, room_id) if is_instance_valid(service) else {"state": "unknown", "text": "Friend status unavailable"}
	text = ("● " if status.state == "online" else "○ ") + str(status.text)
	add_theme_color_override("font_color", Color("a6d9c4") if status.state == "online" else Color("afc7bd"))
