extends "res://examples/selftest/sections_wall.gd"

## Selftest section: every weapon's baked animation clips (ZeeAnimBake), the sidecars Nightly's asset viewer plays.


func _anim_bake() -> void:
	_begin("every weapon bakes real animation clips for Nightly's viewer")
	var bad_names: Array[String] = []
	var missing_clip: Array[String] = []
	var flat: Array[String] = []
	var bad_len: Array[String] = []
	var nonfinite: Array[String] = []
	var wrong_width: Array[String] = []
	var no_reload_motion: Array[String] = []
	var no_third: Array[String] = []
	var mag_split := 0
	var baked := 0
	var assets := {}
	var width := {"transform": 7, "position": 3, "visible": 1}
	for art in ZeeWeaponArtTable.all():
		var def := ZeeWeaponPack.catalogue().get_def(art.id)
		var side := ZeeAnimBake.new().bake(self, art.id)
		if side.is_empty():
			continue
		baked += 1
		var asset: String = side.asset
		assets[asset] = true
		if not asset.begins_with("zee-gs-weapons__") or asset.contains("/") or asset.contains("res:"):
			bad_names.append(String(art.id))
		var by_name := {}
		for c: Dictionary in side.clips:
			by_name[c.name] = c
			if c.frames <= 0 or not is_equal_approx(c.length, snappedf(float(c.frames) / 60.0, 0.001)):
				bad_len.append("%s/%s" % [art.id, c.name])
			var tracks: Array = c.tracks
			if tracks.is_empty() or not tracks.any(func(t: Dictionary) -> bool: return t.target == "weapon"):
				flat.append("%s/%s" % [art.id, c.name])
			for t: Dictionary in tracks:
				var vals: Array = t.values
				if vals.size() != int(width[t.path]) * int(c.frames):
					wrong_width.append("%s/%s/%s" % [art.id, c.name, t.target])
				for v: float in vals:
					if not is_finite(v):
						nonfinite.append("%s/%s/%s" % [art.id, c.name, t.target])
						break
		for want in ZeeAnimBake.clip_names(art, def):
			if not by_name.has(want.name):
				missing_clip.append("%s/%s" % [art.id, want.name])
		# a clip that moves: the weapon's own track must not be a held pose
		for moving in ["fire", "draw", "inspect"]:
			if by_name.has(moving) and not _anim_moves(by_name[moving], "weapon"):
				flat.append("%s/%s moves nothing" % [art.id, moving])
		if def.magazine > 0 and by_name.has("reload") and not _anim_moves(by_name.reload, "weapon") and not _anim_has_motion(by_name.reload):
			no_reload_motion.append(String(art.id))
		if not side.has("third_person") or (side.third_person.rest as Array).size() != 12:
			no_third.append(String(art.id))
		var parts := ZeeAnimBake.split(side)
		if not parts[1].is_empty():
			mag_split += 1
			assets[parts[1].asset] = true
	_check("weapons with a model bake (%d of %d)" % [baked, ZeeWeaponArtTable.all().size()], baked >= 20)
	_check("every sidecar is named like Nightly's GLB for its model (bad: %s)" % [bad_names], bad_names.is_empty())
	_check("every weapon has the clips it plays (missing: %s)" % [missing_clip], missing_clip.is_empty())
	_check("every clip has a real length and a weapon track (bad: %s %s)" % [bad_len, flat], bad_len.is_empty() and flat.is_empty())
	_check("every track holds one value set per frame (bad: %s)" % [wrong_width], wrong_width.is_empty())
	_check("every baked value is finite (bad: %s)" % [nonfinite], nonfinite.is_empty())
	_check("every magazine-fed weapon's reload moves something (bad: %s)" % [no_reload_motion], no_reload_motion.is_empty())
	_check("every sidecar carries its third-person rest (bad: %s)" % [no_third], no_third.is_empty())
	_check("separate magazine models get a sidecar of their own (%d)" % mag_split, mag_split >= 4)
	_check("the sidecars name the models they play on (%d assets for %d weapons and %d magazines)" % [assets.size(), baked, mag_split], assets.size() >= baked - 4 and assets.size() > mag_split)
	_end()


func _anim_attachments() -> void:
	_begin("attachments bake attach and detach clips, the rest of the models stay static")
	var bad: Array[String] = []
	var models := ZeeAttachmentBake.models()
	for path in models:
		var side := ZeeAttachmentBake.bake(path)
		if side.is_empty() or side.asset != ZeeAnimBake.asset_of(path):
			bad.append("%s: no sidecar" % path)
			continue
		var by_name := {}
		for c: Dictionary in side.clips:
			by_name[c.name] = c
			var t: Dictionary = c.tracks[0]
			if (t.values as Array).size() != 7 * int(c.frames) or not (t.values as Array).all(func(v: float) -> bool: return is_finite(v)):
				bad.append("%s/%s: bad track" % [path, c.name])
			elif not _anim_moves(c, "weapon"):
				bad.append("%s/%s: moves nothing" % [path, c.name])
		if not by_name.has("attach") or not by_name.has("detach"):
			bad.append("%s: clips %s" % [path, by_name.keys()])
		else:
			# attach ends seated at the origin, detach starts there
			var a: Array = by_name.attach.tracks[0].values
			var d: Array = by_name.detach.tracks[0].values
			var seated := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]
			for i in 7:
				if absf(a[a.size() - 7 + i] - seated[i]) > 1e-4 or absf(d[i] - seated[i]) > 1e-4:
					bad.append("%s: not seated at the clip's end" % path)
					break
	_check("all 7 attachment models bake (%d; bad: %s)" % [models.size(), bad], models.size() == 7 and bad.is_empty())
	var statics := ZeeAttachmentBake.static_models()
	var mounted: Array[String] = []
	for path in statics:
		if not ZeeAttachmentBake.bake(path).is_empty():
			mounted.append(path)
	_check("the %d ammo, arms and range models stay static, no sidecar (bad: %s)" % [statics.size(), mounted], statics.size() >= 10 and mounted.is_empty())
	_end()


## Whether [param clip]'s track [param target] changes between frames.
func _anim_moves(clip: Dictionary, target: String) -> bool:
	for t: Dictionary in clip.tracks:
		if t.target != target:
			continue
		var w: int = {"transform": 7, "position": 3, "visible": 1}[t.path]
		var vals: Array = t.values
		for i in range(w, vals.size()):
			if absf(vals[i] - vals[i - w]) > 1e-5:
				return true
	return false


func _anim_has_motion(clip: Dictionary) -> bool:
	for t: Dictionary in clip.tracks:
		if _anim_moves(clip, t.target):
			return true
	return false
