extends RefCounted
## Local, stable player marks. No images or identifiers leave the device.
const SIZE := 64
const CACHE_LIMIT := 128
static var _textures: Dictionary = {}
static var _order: Array[String] = []

static func texture_for(player_id: String) -> Texture2D:
	if _textures.has(player_id): return _textures[player_id]
	var digest := player_id.sha256_buffer()
	var hue := float(digest[0]) / 255.0
	var foreground := Color.from_hsv(hue,0.34,0.94)
	var background := Color.from_hsv(hue,0.44,0.31)
	var image := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			if Vector2(x-31.5,y-31.5).length_squared() <= 31.5*31.5:
				image.set_pixel(x,y,background)
	for y: int in range(5):
		for x: int in range(3):
			if (digest[1+y*3+x] & 1) == 0 and not (x == 2 and y == 2): continue
			image.fill_rect(Rect2i(12+x*8,12+y*8,8,8),foreground)
			if x < 2: image.fill_rect(Rect2i(12+(4-x)*8,12+y*8,8,8),foreground)
	var texture := ImageTexture.create_from_image(image)
	if _order.size() >= CACHE_LIMIT:
		_textures.erase(_order.pop_front())
	_order.append(player_id)
	_textures[player_id] = texture
	return texture
