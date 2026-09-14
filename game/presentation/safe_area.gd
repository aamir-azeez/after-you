extends RefCounted
## DisplayServer returns physical screen pixels; controls use viewport coordinates.

static func viewport_rect(screen_safe: Rect2, screen_transform: Transform2D, viewport: Rect2) -> Rect2:
	if not screen_safe.is_finite() or not screen_transform.is_finite() or not screen_safe.has_area() or is_zero_approx(screen_transform.determinant()):
		return viewport
	var mapped := (screen_transform.affine_inverse() * screen_safe).intersection(viewport)
	return mapped if mapped.has_area() else viewport
