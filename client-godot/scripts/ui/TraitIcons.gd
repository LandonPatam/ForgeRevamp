extends RefCounted
## Vector glyphs for creature traits. Authored as white SVG on a 24-unit grid and
## rasterized at the exact display size, so they stay sharp at every card zoom.
const FEATHER_WING := "M12.7 18C12.9 12.6 15.2 8 23 4.6C23.2 6.6 22.6 8.2 21.4 9.4C22 9.5 22.6 9.4 23 9.2C22.4 11 21.2 12.4 19.6 13.2C20.2 13.4 20.8 13.3 21.2 13.2C19.8 15.8 16.8 18 12.7 18Z"
const MIRRORED_BLADE := "M6.6 0.8L8.9 5.6V15.4H4.3V5.6Z M2.2 15.4H11V17.6H2.2Z M5.4 17.6H7.8V22.8H5.4Z"
const BIOHAZARD_LOBE := "<path transform='translate(0,-2.4)' d='M8.1 3.6A5.5 5.5 0 1 0 15.9 3.6A4 4 0 1 1 8.1 3.6Z'/>"
const SHIELD_SPIKE := "<path d='M12 0.5L14.8 6.2H9.2Z'/>"
## ICON_COLORS replace the trait's role color for glyph tints and hover-list names.
## Multicolor glyphs carry their colors in the SVG and are never tinted.
const BAKED_COLORS := ["DEATHTOUCH", "DEFENDER", "SHADOW", "SHROUD"]
const ICON_COLORS := {
	"FLYING": Color.WHITE, "TRAMPLE": Color("b5793f"), "DEATHTOUCH": Color("b266ff"), "LIFELINK": Color("e5383b"),
	"HASTE": Color("ffd60a"), "HEXPROOF": Color.WHITE, "DEFENDER": Color.WHITE,
	"FIRST_STRIKE": Color("dfe7ef"), "DOUBLE_STRIKE": Color("ffb27a"), "INFECT": Color("4cd964"), "WITHER": Color("5fae3c"),
	"MENACE": Color("ff453a"), "SKULK": Color("93a1b5"), "SHADOW": Color("9d5cff"), "FEAR": Color.WHITE,
	"INTIMIDATE": Color("ff8a5c"), "HORSEMANSHIP": Color("e3c08d"), "REACH": Color.WHITE, "INDESTRUCTIBLE": Color("f2c14e"),
	"SHROUD": Color.WHITE, "PROTECTION": Color("f0f4ff"),
}
const SVG := {
	"FLYING": "<path d='%s'/><path transform='translate(24,0) scale(-1,1)' d='%s'/>" % [FEATHER_WING, FEATHER_WING],
	"TRAMPLE": "<path d='M0.8 21.5L11.5 3L9.9 8.2L11.9 11.2L9.5 15L11.3 18L10.2 21.5Z'/><path d='M23.2 21.5L12.5 3L12.3 8.2L14.3 11.2L11.9 15L13.7 18L12.6 21.5Z'/>",
	"DEATHTOUCH": "<path fill='#b266ff' fill-rule='evenodd' d='M9.5 1.56C12.05 0.47 15.35 0.62 17.3 2.03C18.2 6.71 15.65 11.23 9.2 13.73C11.45 9.83 11.6 5.46 9.5 1.56ZM14.6 3.59C14.98 6.24 14 8.58 12.35 10.45C13.1 8.27 13.3 5.77 12.6 3.59Z'/><path fill='#4cd964' d='M9 14.6C6.6 17.4 5.2 18.8 5.2 20C5.2 22 7 23.4 9 23.4C11 23.4 12.8 22 12.8 20C12.8 18.8 11.4 17.4 9 14.6Z'/>",
	"LIFELINK": "<path fill-rule='evenodd' d='M12 21.5C5.5 16.4 2 12.8 2 8.4C2 5.2 4.5 3 7.3 3C9.2 3 11 4 12 5.8C13 4 14.8 3 16.7 3C19.5 3 22 5.2 22 8.4C22 12.8 18.5 16.4 12 21.5ZM6.5 14.4H9.2L10.8 10.8L13.2 17.6L14.8 14.4H17.5V13H14L13.4 14.2L10.9 7.8L8.4 13H6.5Z'/>",
	"VIGILANCE": "<path fill-rule='evenodd' d='M12 1.2L21 4.4V11.5C21 17 17 21 12 22.8C7 21 3 17 3 11.5V4.4ZM12 4.3L18.4 6.5V11.5C18.4 15.6 15.6 18.6 12 20C8.4 18.6 5.6 15.6 5.6 11.5V6.5ZM12 7.6L15.6 8.8V11.6C15.6 13.8 14.2 15.6 12 16.6C9.8 15.6 8.4 13.8 8.4 11.6V8.8Z'/>",
	"HASTE": "<path d='M14.5 1L5 13.5H11L9 23L19.5 9.8H13.4Z'/>",
	"HEXPROOF": "<path fill-rule='evenodd' d='M12 1L21.5 6.5V17.5L12 23L2.5 17.5V6.5ZM12 4.4L5.4 8.2V15.8L12 19.6L18.6 15.8V8.2ZM12 8.2L15.3 10.1V13.9L12 15.8L8.7 13.9V10.1Z'/>",
	"WARD": "<path fill-rule='evenodd' d='M1.5 12a10.5 10.5 0 1 0 21 0a10.5 10.5 0 1 0 -21 0ZM4 12a8 8 0 1 0 16 0a8 8 0 1 0 -16 0Z'/><path fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' stroke-linejoin='round' d='M12 18V6.5M12 12.5L7.6 7.6M12 12.5L16.4 7.6'/>",
	"DEFENDER": "<defs><linearGradient id='rainbow' gradientUnits='userSpaceOnUse' x1='0' y1='1.5' x2='0' y2='22.5'><stop offset='0' stop-color='#ff3b30'/><stop offset='0.2' stop-color='#ff9500'/><stop offset='0.4' stop-color='#ffd60a'/><stop offset='0.6' stop-color='#34c759'/><stop offset='0.8' stop-color='#0a84ff'/><stop offset='1' stop-color='#bf5af2'/></linearGradient></defs><g fill='none' stroke='url(#rainbow)' stroke-width='2.6' stroke-linecap='round'><circle cx='12' cy='12' r='9.6'/><path d='M12 2.4V21.6M12 12L5.2 18.8M12 12L18.8 18.8'/></g>",
	"FIRST_STRIKE": "<path transform='rotate(45 12 12)' d='M12 -1L13.7 2.4V18H10.3V2.4Z M7.5 18H16.5V20.2H7.5Z M10.9 20.2H13.1V25H10.9Z'/><path transform='rotate(-45 12 12)' d='M13 -1.5L15 1.6V6.4L11 7.2V1.6Z M10 16.8L14 17.6V21H10Z M7.8 21H16.2V23H7.8Z M10.9 23H13.1V26.8H10.9Z'/>",
	"DOUBLE_STRIKE": "<path d='%s'/><path transform='translate(24,0) scale(-1,1)' d='%s'/>" % [MIRRORED_BLADE, MIRRORED_BLADE],
	"INFECT": "<g transform='rotate(0 12 12)'>%s</g><g transform='rotate(120 12 12)'>%s</g><g transform='rotate(240 12 12)'>%s</g><circle cx='12' cy='12' r='2'/>" % [BIOHAZARD_LOBE, BIOHAZARD_LOBE, BIOHAZARD_LOBE],
	"WITHER": "<path fill='none' stroke='white' stroke-width='1.9' stroke-linecap='round' d='M4.6 22.6C4.4 14 7 6 12.8 4.8'/><path fill-rule='evenodd' d='M12.5 4.2C16.5 3 20.5 5 21.5 9.5C22.4 13.5 21 18 17.5 20.8C16.4 21.6 15 21.2 14.8 20C15.9 20.2 16.8 19.6 17 18.6L14.8 18.4L15.6 15.8L13 15.6L13.9 12.8L11.2 12L12.6 9.6L10.4 8C11 6.4 11.6 5 12.5 4.2ZM13.6 6C16.8 6.8 18.8 10.4 17.6 15.6C17.9 10.8 16.2 7.6 13.4 6.6Z'/>",
	"MENACE": "<path fill-rule='evenodd' d='M1.5 7L11 12C10.6 15.6 8 17.6 5.4 16.6C2.8 15.6 1.4 11.8 1.5 7ZM6.2 11L7.8 11.9L7.4 14.9L6.4 14.6Z'/><path fill-rule='evenodd' d='M22.5 7L13 12C13.4 15.6 16 17.6 18.6 16.6C21.2 15.6 22.6 11.8 22.5 7ZM17.8 11L16.2 11.9L16.6 14.9L17.6 14.6Z'/>",
	"SKULK": "<ellipse cx='7.4' cy='13.4' rx='3.2' ry='4.2'/><ellipse cx='7.4' cy='20.4' rx='2.3' ry='2'/><ellipse cx='16.6' cy='5.4' rx='3.2' ry='4.2'/><ellipse cx='16.6' cy='12.4' rx='2.3' ry='2'/>",
	"SHADOW": "<path fill='#9d5cff' d='M14.97 12.00L14.95 12.59L14.82 13.17L14.58 13.72L14.22 14.22L13.78 14.66L13.24 15.00L12.65 15.24L12.00 15.37L11.33 15.37L10.66 15.24L10.01 14.97L9.42 14.58L8.90 14.07L8.47 13.46L8.17 12.76L8.00 12.00L7.98 11.20L8.12 10.39L8.41 9.60L8.87 8.87L9.47 8.22L10.21 7.68L11.06 7.28L12.00 7.05L12.99 7.00L14.01 7.15L15.01 7.50L15.95 8.05L16.79 8.80L17.49 9.73L18.02 10.80L18.34 12.00L18.42 13.28L18.26 14.59L17.82 15.89L17.12 17.12L16.17 18.24L14.97 19.18L13.57 19.89L12.00 20.33L10.32 20.47L8.57 20.27L6.84 19.72L5.19 18.81L3.70 17.55L2.43 15.97L1.45 14.10L0.83 12.00L1.07 12.00L1.74 14.04L2.74 15.83L4.02 17.33L5.51 18.49L7.12 19.30L8.79 19.76L10.43 19.88L12.00 19.68L13.43 19.19L14.68 18.47L15.72 17.56L16.51 16.51L17.06 15.38L17.36 14.22L17.42 13.08L17.26 12.00L16.91 11.02L16.40 10.18L15.76 9.49L15.04 8.96L14.26 8.61L13.48 8.43L12.71 8.41L12.00 8.54L11.36 8.80L10.82 9.15L10.39 9.59L10.07 10.07L9.87 10.58L9.78 11.08L9.80 11.56L9.91 12.00L10.09 12.38L10.33 12.69L10.61 12.93L10.91 13.09L11.22 13.17L11.51 13.19L11.77 13.14L12.00 13.05L12.18 12.92L12.32 12.76L12.40 12.60L12.43 12.43L12.43 12.29L12.38 12.16L12.32 12.06L12.23 12.00ZM9.03 12.00L9.05 11.41L9.18 10.83L9.42 10.28L9.78 9.78L10.22 9.34L10.76 9.00L11.35 8.76L12.00 8.63L12.67 8.63L13.34 8.76L13.99 9.03L14.58 9.42L15.10 9.93L15.53 10.54L15.83 11.24L16.00 12.00L16.02 12.80L15.88 13.61L15.59 14.40L15.13 15.13L14.53 15.78L13.79 16.32L12.94 16.72L12.00 16.95L11.01 17.00L9.99 16.85L8.99 16.50L8.05 15.95L7.21 15.20L6.51 14.27L5.98 13.20L5.66 12.00L5.58 10.72L5.74 9.41L6.18 8.11L6.88 6.88L7.83 5.76L9.03 4.82L10.43 4.11L12.00 3.67L13.68 3.53L15.43 3.73L17.16 4.28L18.81 5.19L20.30 6.45L21.57 8.03L22.55 9.90L23.17 12.00L22.93 12.00L22.26 9.96L21.26 8.17L19.98 6.67L18.49 5.51L16.88 4.70L15.21 4.24L13.57 4.12L12.00 4.32L10.57 4.81L9.32 5.53L8.28 6.44L7.49 7.49L6.94 8.62L6.64 9.78L6.58 10.92L6.74 12.00L7.09 12.98L7.60 13.82L8.24 14.51L8.96 15.04L9.74 15.39L10.52 15.57L11.29 15.59L12.00 15.46L12.64 15.20L13.18 14.85L13.61 14.41L13.93 13.93L14.13 13.42L14.22 12.92L14.20 12.44L14.09 12.00L13.91 11.62L13.67 11.31L13.39 11.07L13.09 10.91L12.78 10.83L12.49 10.81L12.23 10.86L12.00 10.95L11.82 11.08L11.68 11.24L11.60 11.40L11.57 11.57L11.57 11.71L11.62 11.84L11.68 11.94L11.77 12.00Z'/><circle cx='12' cy='12' r='2.2' fill='#efe6ff'/>",
	"FEAR": "<path fill-rule='evenodd' d='M12 1.5C6.8 1.5 4 5.5 4 10.5V22.5C5 20.6 6 20 7 20C8 20 8.6 21.2 9.5 22.5C10.4 21 11 20 12 20C13 20 13.6 21 14.5 22.5C15.4 21.2 16 20 17 20C18 20 19 20.6 20 22.5V10.5C20 5.5 17.2 1.5 12 1.5ZM7.3 9.8a1.7 2.4 0 1 0 3.4 0a1.7 2.4 0 1 0 -3.4 0ZM13.3 9.8a1.7 2.4 0 1 0 3.4 0a1.7 2.4 0 1 0 -3.4 0ZM10.5 15.2a1.5 2 0 1 0 3 0a1.5 2 0 1 0 -3 0Z'/>",
	"INTIMIDATE": "<g transform='rotate(0 12 12)'>%s</g><g transform='rotate(45 12 12)'>%s</g><g transform='rotate(90 12 12)'>%s</g><g transform='rotate(135 12 12)'>%s</g><g transform='rotate(180 12 12)'>%s</g><g transform='rotate(225 12 12)'>%s</g><g transform='rotate(270 12 12)'>%s</g><g transform='rotate(315 12 12)'>%s</g><path fill-rule='evenodd' d='M4.5 12a7.5 7.5 0 1 0 15 0a7.5 7.5 0 1 0 -15 0ZM8 12a4 4 0 1 0 8 0a4 4 0 1 0 -8 0Z'/><circle cx='12' cy='12' r='1.9'/>" % [SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE, SHIELD_SPIKE],
	"HORSEMANSHIP": "<path fill-rule='evenodd' d='M12 2C6.5 2 3 6.5 3 12C3 16 4.2 19.4 5.5 22H10.2C8.8 19 7.8 15.8 7.8 12.2C7.8 9 9.6 6.8 12 6.8C14.4 6.8 16.2 9 16.2 12.2C16.2 15.8 15.2 19 13.8 22H18.5C19.8 19.4 21 16 21 12C21 6.5 17.5 2 12 2ZM4.4 11a1 1 0 1 0 2 0a1 1 0 1 0 -2 0ZM17.6 11a1 1 0 1 0 2 0a1 1 0 1 0 -2 0ZM5 16.4a0.95 0.95 0 1 0 1.9 0a0.95 0.95 0 1 0 -1.9 0ZM17.1 16.4a0.95 0.95 0 1 0 1.9 0a0.95 0.95 0 1 0 -1.9 0Z'/>",
	"REACH": "<path d='M7 9.5H17.8V14.5C17.8 16 16.8 17 15.8 17.6L16.8 23H8L9 17.6C7.6 16.6 7 15.5 7 14Z'/><path fill='none' stroke='white' stroke-width='2.2' stroke-linecap='round' d='M8 10L6.6 4.4M11 9.5L10.4 2M14 9.5L14.4 2.2M17 10.4L18.4 4.8M7.4 14L3.6 10.2'/>",
	"INDESTRUCTIBLE": "<path d='M1.5 5.5H8V4.5H22.5V10C19.4 10 17.2 11 16.8 13.5L18.2 16H19.6V20.5H6.4V16H7.8L9.2 13.5C8.8 11 7.4 9.8 5 9.2C3.2 8.8 2 7.4 1.5 5.5Z'/>",
	"SHROUD": "<path fill='#000000' stroke='white' stroke-width='1.4' stroke-linejoin='round' d='M12 2C7.2 2 4.6 5.8 4.4 10.5C4.2 15 3.4 19 2.2 22.2H21.8C20.6 19 19.8 15 19.6 10.5C19.4 5.8 16.8 2 12 2Z'/><path d='M12 5.8C9.2 5.8 7.6 8.1 7.6 10.8C7.6 13.3 9.6 15.5 12 16.4C14.4 15.5 16.4 13.3 16.4 10.8C16.4 8.1 14.8 5.8 12 5.8Z'/>",
	"PROTECTION": "<path fill-rule='evenodd' d='M3 3.5L7.5 1.8L12 3.5L16.5 1.8L21 3.5V12C21 17.5 17 21 12 23C7 21 3 17.5 3 12ZM10.6 6H13.4V10H17.5V12.8H13.4V19.4H10.6V12.8H6.5V10H10.6Z'/>",
}
static var cache: Dictionary = {}

static func has_icon(key: String) -> bool:
	return SVG.has(key)

static func color_for(key: String, role_color: Color) -> Color:
	return ICON_COLORS.get(key, role_color)

static func render_image(key: String, pixels: int) -> Image:
	var source := "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='white'>%s</svg>" % SVG[key]
	var image := Image.new()
	if image.load_svg_from_string(source, pixels / 24.0) != OK: return null
	return image

static func texture(key: String, pixels: int) -> Texture2D:
	var id := "%s:%d" % [key, pixels]
	if not cache.has(id):
		var image := render_image(key, pixels)
		cache[id] = null if image == null else ImageTexture.create_from_image(image)
	return cache[id]

## Draws the glyph in its own color, else the role color. False when it has no glyph.
static func draw_icon(canvas: CanvasItem, key: String, rect: Rect2, role_color: Color) -> bool:
	if not has_icon(key): return false
	var pixels := maxi(8, roundi(minf(rect.size.x, rect.size.y)))
	var glyph := texture(key, pixels)
	if glyph == null: return false
	var at := (rect.get_center() - Vector2(pixels, pixels) * 0.5).round()
	canvas.draw_texture_rect(glyph, Rect2(at, Vector2(pixels, pixels)), false, Color.WHITE if BAKED_COLORS.has(key) else color_for(key, role_color))
	return true
