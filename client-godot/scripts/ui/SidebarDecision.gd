extends RefCounted
## Every sidebar decision uses the same container sizing, including space
## reserved for a scrollbar. Navigation/header/footer layout belongs to Main.
static func dock(panel: PanelContainer, host: ScrollContainer, labels: Array, relayout: Callable) -> bool:
	if not is_instance_valid(host): return false
	if panel.get_parent() != host:
		panel.reparent(host, false)
		host.scroll_vertical = 0
	if not host.resized.is_connected(relayout): host.resized.connect(relayout, CONNECT_DEFERRED)
	if not host.visibility_changed.is_connected(relayout): host.visibility_changed.connect(relayout, CONNECT_DEFERRED)
	var content_width := host.size.x - host.get_v_scroll_bar().get_combined_minimum_size().x
	for label in labels: label.custom_minimum_size.x = maxf(100, content_width - 28)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the scroll viewport and align the panel's content at the bottom.
	# Taller decisions still scroll from the top.
	panel.custom_minimum_size.y = 0
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size = Vector2(content_width, maxf(host.size.y, panel.get_combined_minimum_size().y))
	# The child below provides the bottom alignment. Offsetting the panel as
	# well can put its controls below the clipped viewport after a resize/show.
	panel.position = Vector2.ZERO
	var content := panel.get_child(0) as Control
	if content != null:
		content.size_flags_vertical = Control.SIZE_SHRINK_END
	return true
