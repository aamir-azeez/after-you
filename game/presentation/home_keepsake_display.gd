extends Node3D
## Home furniture is a view of earned descriptors, never an award source.
const Visual = preload("res://presentation/keepsake_visual.gd")
const WOOD := Color("94785e")
const EDGE := Color("c0a37d")
var _world: Node3D
var _items: Array[Dictionary] = []
var _shelf: Node3D
var _selected: Node3D
var selected_index := 0
var center := Vector3.ZERO

func configure(world: Node3D, items: Array[Dictionary], at: Vector3) -> void:
	_world = world
	center = at
	set_items(items)

func set_items(items: Array[Dictionary]) -> void:
	var selected_id := str(selected_item().get("id", ""))
	if not _items.is_empty():
		var previous := {}
		for item: Dictionary in _items: previous[item.id] = item
		for item: Dictionary in items:
			var before: Dictionary = previous.get(item.id,{})
			if (item.get("solo",false) and not before.get("solo",false)) or (item.get("friend",false) and not before.get("friend",false)):
				selected_id = item.id
	_items = items.duplicate(true)
	selected_index = clampi(selected_index, 0, maxi(0, _items.size()-1))
	for i in range(_items.size()):
		if _items[i].id == selected_id: selected_index = i
	_rebuild()

func selected_item() -> Dictionary:
	return {} if _items.is_empty() else _items[selected_index].duplicate(true)

func select_offset(offset: int) -> void:
	if _items.is_empty(): return
	selected_index = posmod(selected_index+offset, _items.size())
	_show_selected()

func _rebuild() -> void:
	if is_instance_valid(_shelf):
		remove_child(_shelf)
		_shelf.queue_free()
	_shelf = Node3D.new()
	_shelf.name = "EarnedKeepsakeShelf"
	add_child(_shelf)
	_shelf.position = center + Vector3(0, 0, -1.1)
	visible = not _items.is_empty()
	if _items.is_empty():
		_show_selected()
		return
	# Each earned level occupies one place. A shared ornament marks its friend
	# variant, avoiding two complete rows of tiny duplicates at a distance.
	var rows := ceili(float(_items.size())/6.0)
	var height := rows*0.55+0.2
	for side: int in [-1, 1]: _world.box(Vector3(0.10, height, 0.16), WOOD, Vector3(side*1.53, height/2, 0), _shelf)
	for row in range(rows):
		var y := 0.14+row*0.55
		_world.box(Vector3(3.14, 0.08, 0.65), EDGE, Vector3(0, y, 0.06), _shelf)
		for col in range(6):
			var index := row*6+col
			if index >= _items.size(): break
			var item: Dictionary = _items[index]
			var prop := Visual.create(_world, item, item.get("friend", false))
			prop.scale = Vector3.ONE*0.37
			prop.position = Vector3((col-2.5)*0.49, y+0.05, 0.06)
			prop.set_meta("keepsake_id", item.id)
			_shelf.add_child(prop)
	_show_selected()

func _show_selected() -> void:
	if is_instance_valid(_selected):
		remove_child(_selected)
		_selected.queue_free()
	_selected = Node3D.new()
	_selected.name = "SelectedKeepsakeVariants"
	add_child(_selected)
	_selected.position = center + Vector3(0, 0, 1.1)
	var item := selected_item()
	if item.is_empty(): return
	var both: bool = item.get("solo", false) and item.get("friend", false)
	for shared: bool in [false, true]:
		if not item.get("friend" if shared else "solo", false): continue
		var x := (0.65 if shared else -0.65) if both else 0.0
		_world.cylinder(0.48, 0.16, EDGE, Vector3(x, 0.09, 0), _selected)
		var prop := Visual.create(_world, item, shared)
		prop.position = Vector3(x, 0.18, 0)
		prop.scale = Vector3.ONE*0.90
		_selected.add_child(prop)
