extends RefCounted
## The little stamps on chapter letters' envelopes, one per kind a chapter's
## descriptor names ("letter": {"stamp": kind}, content/chapters/index.gd):
## a perforated white edge, a coloured field and a small flat drawing, as SVG
## made into a texture for the size it is shown at.

## The stamp's own units: 60 wide, 72 tall; the field inside is 48 by 60.
const SIZE := Vector2(60, 72)
const FIELD := Rect2(6, 6, 48, 60)
## {kind: [field colour, drawing inside the field]}.
const KINDS := {
	"teacup": ["#96cdba", '<ellipse cx="30" cy="52" rx="16" ry="4" fill="#ffffff"/><path d="M17 30h26v6a13 13 0 0 1-26 0z" fill="#f2a080"/><circle cx="44" cy="35" r="5" fill="none" stroke="#f2a080" stroke-width="3"/><path d="M24 25q-3-4 0-8M30 25q-3-4 0-8M36 25q-3-4 0-8" stroke="#ffffff" stroke-width="2" fill="none" stroke-linecap="round"/>'],
	"bench": ["#a9d3e0", '<rect x="6" y="52" width="48" height="14" fill="#8cc47e"/><rect x="15" y="34" width="30" height="5" rx="1" fill="#c48c58"/><rect x="15" y="42" width="30" height="5" rx="1" fill="#c48c58"/><rect x="17" y="47" width="3" height="10" fill="#8a5a36"/><rect x="40" y="47" width="3" height="10" fill="#8a5a36"/>'],
	"daisy": ["#96c478", '<path d="M30 36q-2 14-4 26" stroke="#3f7e4c" stroke-width="3" fill="none"/><ellipse cx="22" cy="54" rx="6" ry="3" fill="#3f7e4c"/><g fill="#ffffff"><circle cx="30" cy="22" r="6"/><circle cx="39" cy="27" r="6"/><circle cx="39" cy="37" r="6"/><circle cx="30" cy="42" r="6"/><circle cx="21" cy="37" r="6"/><circle cx="21" cy="27" r="6"/></g><circle cx="30" cy="32" r="7" fill="#f4c446"/>'],
	"bee": ["#bfe0f0", '<ellipse cx="24" cy="26" rx="8" ry="6" fill="#ffffff" opacity="0.9"/><ellipse cx="36" cy="26" rx="8" ry="6" fill="#ffffff" opacity="0.9"/><ellipse cx="30" cy="40" rx="13" ry="10" fill="#f4c446"/><rect x="25" y="31" width="4" height="18" fill="#3a3a36"/><rect x="33" y="31" width="4" height="18" fill="#3a3a36"/><circle cx="41" cy="38" r="1.8" fill="#3a3a36"/>'],
	"house": ["#b0d2e4", '<rect x="6" y="54" width="48" height="12" fill="#78b06e"/><rect x="18" y="36" width="24" height="20" fill="#f4deb4"/><path d="M14 37l16-14 16 14z" fill="#ce6850"/><rect x="36" y="22" width="4" height="8" fill="#96593f"/><rect x="27" y="45" width="6" height="11" fill="#78543c"/><rect x="20" y="40" width="5" height="5" fill="#ffe68c"/><rect x="35" y="40" width="5" height="5" fill="#ffe68c"/>'],
	"fern": ["#e2ecc8", '<path d="M30 60q6-20-2-46" stroke="#408c60" stroke-width="2.5" fill="none"/><g fill="#408c60"><ellipse cx="22" cy="48" rx="8" ry="2.6"/><ellipse cx="38" cy="46" rx="8" ry="2.6"/><ellipse cx="22" cy="38" rx="7" ry="2.4"/><ellipse cx="37" cy="36" rx="7" ry="2.4"/><ellipse cx="24" cy="28" rx="5.5" ry="2.2"/><ellipse cx="35" cy="26" rx="5.5" ry="2.2"/><ellipse cx="28" cy="18" rx="3.5" ry="2"/></g><ellipse cx="30" cy="61" rx="11" ry="4" fill="#be6e50"/>'],
	"basket": ["#d8e8c4", '<path d="M18 14l12 14 12-14" stroke="#7a5a3a" stroke-width="1.5" fill="none"/><path d="M16 28h28l-4 14h-20z" fill="#c48c58"/><g fill="#408c60"><ellipse cx="20" cy="46" rx="3" ry="7"/><ellipse cx="30" cy="50" rx="3" ry="9"/><ellipse cx="40" cy="46" rx="3" ry="7"/></g><circle cx="24" cy="27" r="3" fill="#f28c8c"/><circle cx="34" cy="26" r="3" fill="#f4c446"/>'],
	"firefly": ["#3c5c6e", '<circle cx="18" cy="20" r="2" fill="#fff0a0"/><circle cx="44" cy="16" r="1.5" fill="#fff0a0"/><circle cx="40" cy="54" r="1.5" fill="#fff0a0"/><circle cx="30" cy="38" r="12" fill="#fff0a0" opacity="0.3"/><ellipse cx="25" cy="33" rx="6" ry="4" fill="#ffffff" opacity="0.8"/><ellipse cx="35" cy="33" rx="6" ry="4" fill="#ffffff" opacity="0.8"/><ellipse cx="30" cy="40" rx="5" ry="7" fill="#fff0a0"/><circle cx="30" cy="31" r="3.5" fill="#2e3a40"/>'],
	"signpost": ["#3c5c6e", '<rect x="28" y="16" width="4" height="46" fill="#96643e"/><path d="M14 20h26l5 5-5 5h-26z" fill="#c48c58"/><path d="M46 34h-26l-5 5 5 5h26z" fill="#c48c58"/><circle cx="15" cy="58" r="5" fill="#46824e"/><circle cx="45" cy="57" r="6" fill="#46824e"/><circle cx="16" cy="12" r="1.5" fill="#ffe678"/><circle cx="46" cy="14" r="1.5" fill="#ffe678"/>'],
	"coin": ["#5c5480", '<circle cx="30" cy="36" r="16" fill="#e8ba4a"/><circle cx="30" cy="36" r="12.5" fill="none" stroke="#c8963a" stroke-width="2"/><path d="M30 28l2.4 5 5.4.6-4 3.7 1.1 5.3-4.9-2.7-4.9 2.7 1.1-5.3-4-3.7 5.4-.6z" fill="#ffeeaa"/>'],
	"crab": ["#acd6e2", '<g stroke="#e86854" stroke-width="2.5" stroke-linecap="round"><path d="M20 40l-8 5M20 44l-8 6M40 40l8 5M40 44l8 6M24 34l-4-8M36 34l4-8"/></g><circle cx="18" cy="23" r="5" fill="#e86854"/><circle cx="42" cy="23" r="5" fill="#e86854"/><ellipse cx="30" cy="40" rx="13" ry="9" fill="#e86854"/><circle cx="26" cy="31" r="2.6" fill="#ffffff"/><circle cx="34" cy="31" r="2.6" fill="#ffffff"/><circle cx="26" cy="31" r="1.2" fill="#2a2a2a"/><circle cx="34" cy="31" r="1.2" fill="#2a2a2a"/><path d="M26 42q4 3 8 0" stroke="#7a281e" stroke-width="1.5" fill="none"/>'],
	"boat": ["#acd6e2", '<rect x="6" y="54" width="48" height="12" fill="#f0dcae"/><path d="M12 46h36l-6 10h-24z" fill="#c4784e" transform="rotate(-14 30 50)"/><path d="M14 46h32" stroke="#ffffff" stroke-width="2" transform="rotate(-14 30 50)"/><path d="M8 26q6-4 12 0t12 0" stroke="#ffffff" stroke-width="2" fill="none"/>'],
	"lighthouse": ["#f4d6a0", '<rect x="6" y="54" width="48" height="12" fill="#78b4c8"/><path d="M23 54l2-24h10l2 24z" fill="#ffffff"/><path d="M23.6 47l.6-7h11.6l.6 7zM24.8 33l.4-3h9.6l.4 3z" fill="#ec5c50"/><rect x="25" y="22" width="10" height="8" fill="#3c4648"/><path d="M23 22l7-7 7 7z" fill="#ec5c50"/><path d="M10 60q5-3 10 0t10 0t10 0t10 0" stroke="#ffffff" stroke-width="1.5" fill="none"/>'],
}

## A stamp of this kind as a texture `scale` times its own units, its
## perforation holes in `paper` (the colour it sits on).
static func texture(kind: String, scale: float, paper: Color) -> Texture2D:
	assert(KINDS.has(kind), "Unknown letter stamp: " + kind)
	var spec: Array = KINDS.get(kind, KINDS.teacup)
	var holes := ""
	var hole := "#" + paper.to_html(false)
	for x in range(0, 61, 6): holes += '<circle cx="%d" cy="0" r="2.6"/><circle cx="%d" cy="72" r="2.6"/>' % [x, x]
	for y in range(6, 72, 6): holes += '<circle cx="0" cy="%d" r="2.6"/><circle cx="60" cy="%d" r="2.6"/>' % [y, y]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="60" height="72" viewBox="0 0 60 72"><rect width="60" height="72" fill="#fcfaf4"/><g fill="%s">%s</g><rect x="6" y="6" width="48" height="60" fill="%s"/>%s</svg>' % [hole, holes, spec[0], spec[1]]
	var image := Image.new()
	image.load_svg_from_string(svg, scale)
	return ImageTexture.create_from_image(image)
