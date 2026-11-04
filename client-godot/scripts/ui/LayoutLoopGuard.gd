extends Node
## A native ScrollContainer can keep re-sorting within one frame when child
## sizing feeds back into its own minimum size. Stop that loop before the
## deferred-call queue fills; leave the transport and authoritative match alive.
signal tripped(scroll: ScrollContainer)
const MAX_SORTS_PER_FRAME := 64
var table: Control
var frame := -1
var sorts: Dictionary = {}
var paused := false
var frozen: Array = []
var watched: Dictionary = {}

func watch(root: Control) -> void:
	table = root
	_scan(root)
	get_tree().node_added.connect(_added)

func _scan(node: Node) -> void:
	_added(node)
	for child in node.get_children(): _scan(child)

func _added(node: Node) -> void:
	if node is ScrollContainer and table.is_ancestor_of(node):
		var id := node.get_instance_id()
		watched[id] = node
		var cleanup := _forgot.bind(id)
		if not node.tree_exiting.is_connected(cleanup): node.tree_exiting.connect(cleanup)
		var callback := _before_sort.bind(node)
		if not node.pre_sort_children.is_connected(callback):
			node.pre_sort_children.connect(callback)

func _forgot(id: int) -> void:
	watched.erase(id)
	sorts.erase(id)

func _before_sort(scroll: ScrollContainer) -> void:
	if paused: return
	var current := Engine.get_process_frames()
	if frame != current:
		frame = current
		sorts.clear()
	var id := scroll.get_instance_id()
	sorts[id] = int(sorts.get(id, 0)) + 1
	if int(sorts[id]) < MAX_SORTS_PER_FRAME: return
	paused = true
	tripped.emit(scroll)
	# Remove every existing scroll content from automatic sizing, so a second
	# already-queued loop cannot overflow while the display is paused. Keep the
	# nodes in the tree for queued callbacks, and restore their exact flags on retry.
	for candidate in watched.values():
		if not is_instance_valid(candidate): continue
		for child in candidate.get_children():
			if child is Control and not child is ScrollBar:
				frozen.append({"node": child, "top_level": child.is_set_as_top_level(), "visible": child.visible})
				child.set_as_top_level(true)
				child.hide()

func retry() -> void:
	for saved in frozen:
		if is_instance_valid(saved.node):
			saved.node.set_as_top_level(saved.top_level)
			saved.node.visible = saved.visible
	frozen.clear()
	sorts.clear()
	frame = -1
	paused = false
