extends SceneTree
## `godot --headless --path . --script res://tools/export_defs.gd` rewrites weapons/*.tres and
## provides.json from the code table. See ZeeDefExport.


func _initialize() -> void:
	var res := ZeeDefExport.export_to("res://")
	if not res.ok:
		printerr("export failed: %s" % res.error.message)
		quit(1)
		return

	print("wrote %d weapon definitions and provides.json" % int(res.value))
	quit(0)
