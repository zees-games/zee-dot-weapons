extends RefCounted

## The magazine a watcher sees change in the support hand during a reload; split out of ZeeWorldModel for file size.
## Built on the first reload, a child of the world model.

const ReloadParts := preload("zee_reload_parts.gd")

var _mag: Node3D = null


## Shows the magazine at [param hand] on the [param holder]'s axes when [param show_it]; builds it under [param parent] on first use.
func update(parent: Node3D, show_it: bool, hand: Vector3, holder: Transform3D) -> void:
	if not show_it:
		hide()
		return
	if _mag == null:
		_mag = ReloadParts.box_magazine()
		if _mag == null:
			return
		_mag.scale = Vector3.ONE * 0.8
		parent.add_child(_mag)
	_mag.visible = true
	_mag.global_transform = Transform3D(holder.basis.orthonormalized(), hand - holder.basis.y.normalized() * 0.03)
	_mag.scale = Vector3.ONE * 0.8


func hide() -> void:
	if _mag != null:
		_mag.visible = false
