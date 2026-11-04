extends RefCounted
## Prominent artwork hue, excluding card borders, headings and rules text.
static var cache: Dictionary = {}
const BINS := 36

static func from_texture(texture: Texture2D, fallback: Color) -> Color:
	if texture == null: return fallback
	var key := texture.get_instance_id()
	if cache.has(key): return cache[key]
	var result := from_image(texture.get_image(), fallback)
	cache[key] = result
	return result

static func from_image(source: Image, fallback: Color) -> Color:
	if source == null or source.is_empty(): return fallback
	var image := source
	if image.is_compressed():
		image = source.duplicate()
		if image.decompress() != OK: return fallback
	var weights: Array[float] = []
	var colors: Array[Vector3] = []
	weights.resize(BINS)
	colors.resize(BINS)
	weights.fill(0.0)
	colors.fill(Vector3.ZERO)
	var neutral := Vector3.ZERO
	var neutral_weight := 0.0
	for row in range(40):
		var v := 0.14 + (row + 0.5) / 40.0 * 0.43
		for column in range(56):
			var u := 0.10 + (column + 0.5) / 56.0 * 0.80
			var pixel := image.get_pixel(mini(int(u * image.get_width()), image.get_width() - 1), mini(int(v * image.get_height()), image.get_height() - 1))
			if pixel.a < 0.8: continue
			var rgb := Vector3(pixel.r, pixel.g, pixel.b)
			# Interior artwork counts more than the edges of its printed frame.
			var spatial := 0.5 + 0.5 * sin((u - 0.1) / 0.8 * PI)
			neutral += rgb * spatial
			neutral_weight += spatial
			if pixel.s < 0.14 or pixel.v < 0.12: continue
			var weight := pow(pixel.s, 1.7) * smoothstep(0.12, 0.5, pixel.v) * spatial
			var bucket := mini(int(pixel.h * BINS), BINS - 1)
			weights[bucket] += weight
			colors[bucket] += rgb * weight
	var best := -1
	var best_score := 0.0
	for bucket in range(BINS):
		var score := weights[posmod(bucket - 1, BINS)] + weights[bucket] + weights[(bucket + 1) % BINS]
		if score > best_score:
			best_score = score
			best = bucket
	if best < 0 or best_score < neutral_weight * 0.012:
		if neutral_weight == 0: return fallback
		var average := neutral / neutral_weight
		var gray := Color(average.x, average.y, average.z)
		return Color.from_hsv(gray.h, minf(gray.s, 0.08), clampf(gray.v, 0.44, 0.68))
	var rgb := (colors[posmod(best - 1, BINS)] + colors[best] + colors[(best + 1) % BINS]) / best_score
	var accent := Color(rgb.x, rgb.y, rgb.z)
	# Keep the sampled hue while giving dark/bright art a usable plastic finish.
	return Color.from_hsv(accent.h, clampf(accent.s * 0.9 + 0.06, 0.30, 0.72), clampf(accent.v * 0.9 + 0.1, 0.48, 0.80))
