extends SceneTree

## Bakes each weapon's procedural first-person animations into <asset>.anim.json (see ZeeAnimBake): the sidecar Nightly's asset viewer plays next to the model.
## Args: out_dir (or - to print one SIDECAR<TAB>asset<TAB>json line each to stdout) [id,id ...]; the file is named like Nightly's GLB for the model (pack__path__with__underscores) so the viewer finds it beside the asset. No ids bakes every weapon, plus each separate magazine model and each attachment (attach, detach); the ammo, arms and range models are static and get no sidecar.
## godot --headless --path . --script res://tools/export_anim_tracks.gd -- out_dir rifle,pistol


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: export_anim_tracks.gd -- out_dir [ids]")
		quit(2)
		return
	var out := args[0]
	if out != "-":
		DirAccess.make_dir_recursive_absolute(out)
	var wanted: PackedStringArray = args[1].split(",") if args.size() > 1 and args[1] != "" else PackedStringArray()
	var host := Node3D.new()
	root.add_child(host)
	await process_frame
	var failed := 0
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
			failed += _write(out, part)
	# the attachments mount rather than shoot: attach and detach clips, baked when no weapon ids narrow the run (or an attachment's file stem is named)
	for model in ZeeAttachmentBake.models():
		var stem := model.get_file().get_basename()
		if not wanted.is_empty() and not stem in wanted:
			continue
		failed += _write(out, ZeeAttachmentBake.bake(model))
	quit(1 if failed > 0 else 0)


func _write(out: String, sidecar: Dictionary) -> int:
	if out == "-":
		# offloaded runs keep their files on the box: print one line per sidecar for the caller to collect
		print("SIDECAR\t%s\t%s" % [sidecar.asset, JSON.stringify(sidecar)])
		return 0
	var path := "%s/%s.anim.json" % [out, sidecar.asset]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return 1
	f.store_string(JSON.stringify(sidecar))
	f.close()
	var n := 0
	for c: Dictionary in sidecar.clips:
		n += (c.tracks as Array).size()
	print("BAKED %s -> %s (%d clips, %d tracks)" % [sidecar.weapon, path, (sidecar.clips as Array).size(), n])
	return 0
