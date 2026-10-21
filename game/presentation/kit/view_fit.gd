extends RefCounted
## World kit: the one rule that keeps an orthographic camera's view as wide on a
## tall screen as in the authored frame. The project stretches with "expand", so
## a screen narrower than 16:9 (a 4:3 iPad, a 16:10 tablet) keeps its height of
## world (KEEP_HEIGHT) and shows less of it across. A camera writes its size
## through here and grows just enough to show the authored width again. At 16:9
## and wider, every phone included, the size comes back unchanged.

## The authored frame: project.godot's base viewport.
const BASE := Vector2(1280, 720)

## `authored` (a KEEP_HEIGHT camera size) for a view `shown` wide per unit of
## height, grown when that is narrower than `reference`. Unchanged otherwise.
static func fit(authored: float, shown: float, reference: float = BASE.x / BASE.y) -> float:
	if not (shown > 0.0) or shown >= reference: return authored
	return authored * reference / shown

## `authored` for the viewport `node` draws in.
static func viewport(authored: float, node: Node) -> float:
	if node == null or not node.is_inside_tree(): return authored
	var view := node.get_viewport().get_visible_rect().size
	if view.y <= 0.0: return authored
	return fit(authored, view.x / view.y)
