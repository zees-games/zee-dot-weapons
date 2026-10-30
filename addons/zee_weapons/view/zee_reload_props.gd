extends Node3D

## What a reload sequence (zee_reload_sequence.gd) has in sight this frame: one part per track, built in code on first
## use and placed in the holder's space. Preloaded by path (no class_name), as the sequence is.

const ReloadParts := preload("zee_reload_parts.gd")

## Called on every part built, so it draws as the view model does (no shadow, sorted over the world).
var on_top: Callable
var _nodes: Dictionary = {}


## Places every track of [param seq] at [param f]; [param to_holder] takes Aim space to this node's, [param size] scales the parts.
func show_at(seq: RefCounted, f: float, to_holder: Transform3D, size: float) -> void:
	for e: Dictionary in seq.call(&"props_at", f):
		var node: Node3D = _nodes.get(e.index)
		if not e.shown:
			if node != null:
				node.visible = false
			continue
		if node == null:
			node = ReloadParts.build(e.part)
			if node == null:
				continue
			add_child(node)
			if on_top.is_valid():
				on_top.call(node)
			_nodes[e.index] = node
		var turn: Vector3 = e.turn
		var at: Vector3 = to_holder * (e.at as Vector3)
		node.transform = Transform3D(Basis.from_euler(turn * (PI / 180.0)).scaled(Vector3.ONE * size), at)
		node.visible = at.is_finite()


## How many parts named [param part] are drawn now; every part when empty.
func shown(part: StringName = &"") -> int:
	var n := 0
	for k: Variant in _nodes:
		var node: Node3D = _nodes[k]
		if node.visible and (part == &"" or node.get_meta(&"part", &"") == part):
			n += 1
	return n
