extends RefCounted
const Accent = preload("res://scripts/app/CardAccent.gd")

static func run() -> bool:
	var fallback := Color("b06070")
	if Accent.from_texture(null, fallback) != fallback: return false
	var image := Image.create(100, 140, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.fill_rect(Rect2i(5, 5, 90, 130), Color("e8c24f")) # gold card frame
	image.fill_rect(Rect2i(10, 19, 80, 61), Color("228e7c")) # teal artwork
	image.fill_rect(Rect2i(10, 82, 80, 50), Color.WHITE) # rules text area
	var result := Accent.from_image(image, fallback)
	if absf(result.h - Color("228e7c").h) > 0.04: return false
	image.fill_rect(Rect2i(10, 19, 80, 61), Color("666666"))
	if Accent.from_image(image, fallback).s > 0.09: return false
	image.fill_rect(Rect2i(10, 19, 80, 61), Color("276dcd"))
	image.fill_rect(Rect2i(35, 35, 8, 8), Color.RED) # small bright accent must not outweigh the scene
	result = Accent.from_image(image, fallback)
	if absf(result.h - Color("276dcd").h) > 0.04: return false
	# Nearby reds straddling the hue boundary should form one cluster.
	image.fill_rect(Rect2i(10, 19, 40, 61), Color.from_hsv(0.99, 0.8, 0.8))
	image.fill_rect(Rect2i(50, 19, 40, 61), Color.from_hsv(0.01, 0.8, 0.8))
	result = Accent.from_image(image, fallback)
	return result.h < 0.04 or result.h > 0.96
