extends "res://addons/gs_weapon/tools/gs_weapon_anim_export.gd"

## Bakes each weapon's procedural first-person animations into <asset>.anim.json (see ZeeAnimBake): the sidecar Nightly's asset viewer plays next to the model.
## The arguments and the output are the shared shell's (addons/gs_weapon/tools/gs_weapon_anim_export.gd). No ids bakes every weapon, plus each separate magazine model and each attachment (attach, detach); the ammo, arms and range models are static and get no sidecar.
## godot --headless --path . --script res://tools/export_anim_tracks.gd -- out_dir rifle,pistol


func _bake_all(host: Node3D, wanted: PackedStringArray) -> void:
	var done := {}
	for art in ZeeWeaponArtTable.all():
		if not wanted.is_empty() and not String(art.id) in wanted:
			continue
		var sidecar := ZeeAnimBake.new().bake(host, art.id)
		if sidecar.is_empty():
			print("SKIP %s (no model)" % art.id)
			continue
		for part in ZeeAnimBake.split(sidecar):
			if part.is_empty() or done.has(part.asset):
				continue
			done[part.asset] = true
			emit(part)
	# the attachments mount rather than shoot: attach and detach clips, baked when no weapon ids narrow the run (or an attachment's file stem is named)
	for model in ZeeAttachmentBake.models():
		if not wanted.is_empty() and not model.get_file().get_basename() in wanted:
			continue
		emit(ZeeAttachmentBake.bake(model))
