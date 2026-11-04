extends VBoxContainer
## Sample the source artwork, rather than the tinted/shaded floppy render.
signal color_picked(color: Color)
var preview: TextureRect
var swatch: ColorRect
var readout: Label
var pixels: Image
var sampled_color := Color.WHITE

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "PICK FROM CARD"
	add_child(title)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(220, 308)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_default_cursor_shape = Control.CURSOR_CROSS
	preview.gui_input.connect(_sample_input)
	add_child(preview)
	var row := HBoxContainer.new()
	add_child(row)
	swatch = ColorRect.new()
	swatch.custom_minimum_size = Vector2(28, 24)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)
	readout = Label.new()
	readout.text = "Hover to preview"
	row.add_child(readout)
	var hint := Label.new()
	hint.text = "Hover a shade, then click to select.\nApply color to save it to the floppy."
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)

func set_artwork(texture: Texture2D) -> void:
	preview.texture = texture
	pixels = texture.get_image() if texture != null else null
	if pixels != null and pixels.is_compressed():
		if pixels.decompress() != OK: pixels = null
	preview.mouse_default_cursor_shape = Control.CURSOR_CROSS if pixels != null else Control.CURSOR_ARROW
	readout.text = "Hover to preview" if pixels != null else "Artwork unavailable"
	swatch.color = Color.TRANSPARENT

func _sample_input(event: InputEvent) -> void:
	if pixels == null: return
	if not (event is InputEventMouseMotion or event is InputEventMouseButton): return
	var image_size := Vector2(pixels.get_size())
	var scale_factor := minf(preview.size.x / image_size.x, preview.size.y / image_size.y)
	var shown := image_size * scale_factor
	var artwork := Rect2((preview.size - shown) * 0.5, shown)
	if not artwork.has_point(event.position): return
	var pixel := Vector2i((event.position - artwork.position) / scale_factor)
	sampled_color = pixels.get_pixel(pixel.x, pixel.y)
	# The floppy's plastic is always opaque.
	sampled_color.a = 1.0
	swatch.color = sampled_color
	readout.text = "#" + sampled_color.to_html(false).to_upper()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		color_picked.emit(sampled_color)
		preview.accept_event()
