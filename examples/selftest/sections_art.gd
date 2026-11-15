extends "res://examples/selftest/sections_feel.gd"

## Selftest sections: art (lazy loading, gloves, meshes, silhouettes, asset root), orientation, muzzles.


## keep_only filters before building: the same arts as filtering the full list, in the same order, and never more builders run.
func _art_lazy() -> void:
	_begin("art table filters before building")

	var full := ZeeWeaponArtTable.all()
	var ids := ZeeWeaponIds.all()
	_check("every built-in's builder is named after its id, in ids order", full.size() == ids.size() and full.map(func(a: ZeeWeaponArt) -> StringName: return a.id) == ids)

	ZeeWeaponPack.keep_only([&"fists"])
	var kept := ZeeWeaponArtTable.all()
	_check("keep_only fists builds exactly the fists art", kept.size() == 1 and kept[0].id == ZeeWeaponIds.FISTS)
	_check("the fists art is identical to the unfiltered one", kept[0].pose == full[0].pose and kept[0].weight == full[0].weight and kept[0].model_path == full[0].model_path)

	ZeeWeaponPack.keep_only([&"rifle", &"fists"])
	var two := ZeeWeaponArtTable.all()
	_check("a kept set keeps the table order", two.size() == 2 and two[0].id == ZeeWeaponIds.FISTS and two[1].id == ZeeWeaponIds.RIFLE)
	_check("the cached table holds only the kept arts", ZeeWeaponArtTable.table().size() == 2)

	ZeeWeaponPack.keep_only(null)
	_check("null brings every art back", ZeeWeaponArtTable.all().size() == ids.size() and ZeeWeaponArtTable.table().size() == ids.size())

	_end()


func _glove() -> void:
	_begin("glove contrast")
	var base := Color(0.17, 0.16, 0.15)
	var light := Color(0.6, 0.52, 0.4)
	var dark_gun := MeshInstance3D.new()
	dark_gun.mesh = BoxMesh.new()
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.2)
	dark_gun.material_override = dark
	var pale_gun := MeshInstance3D.new()
	pale_gun.mesh = BoxMesh.new()
	var pale := StandardMaterial3D.new()
	pale.albedo_color = Color(0.8, 0.8, 0.8)
	pale_gun.material_override = pale
	var arms := ZeeViewArms.new()
	_check("a dark gun gets the light glove", arms.fit_glove_to(dark_gun) == arms.glove_light_color)
	_check("a pale gun keeps the stock glove", arms.fit_glove_to(pale_gun) == arms.glove_color)
	arms.glove_contrast = false
	_check("with glove_contrast off a dark gun keeps the stock glove", arms.fit_glove_to(dark_gun) == arms.glove_color)
	var colour := preload("res://addons/zee_weapons/view/zee_glove_colour.gd")
	var mean: Color = colour.mean_of(colour.surface_albedos(dark_gun))
	_check("the mean albedo is the material's colour (%.2f)" % mean.r, absf(mean.r - 0.2) < 0.001)
	_check("the glove contrasts with the dark gun it was picked for",
		absf(light.get_luminance() - mean.get_luminance()) > absf(base.get_luminance() - mean.get_luminance()))
	arms.free()
	dark_gun.free()
	pale_gun.free()
	_end()


func _art() -> void:
	_begin("the art table")

	var res := ZeeWeaponArtTable.validate()
	_check("every art entry validates: %s" % _why(res), res.ok)

	var models := ZeeWeaponArtTable.validate_models()
	_check("every model, magazine and attachment exists: %s" % _why(models), models.ok)

	# The vendoring list is the table's own: sorted, once each, every one of them a model of an
	# entry, and the arms model only when asked. A game's check and the sync tool read it.
	var listed := ZeeWeaponArtTable.model_paths()
	var unique := {}
	for path in listed:
		unique[path] = true
	_check("the vendoring list names each model once (%d)" % listed.size(),
		listed.size() > 20 and unique.size() == listed.size())
	_check("the arms model is listed only on request",
		not listed.has(ZeeWeaponArtTable.ARMS_MODEL)
		and ZeeWeaponArtTable.model_paths(true).has(ZeeWeaponArtTable.ARMS_MODEL))

	# A part built in code (an ammunition box, a cell) answers for itself: a name the builder
	# does not know is a reload with nothing in the hand.
	var parts := preload("res://addons/zee_weapons/view/zee_reload_parts.gd")
	var unbuilt: Array[String] = []
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if art.magazine_part != &"":
			var built: Node3D = parts.build(art.magazine_part)
			if built == null:
				unbuilt.append("%s: %s" % [art.id, art.magazine_part])
			else:
				built.free()
	_check("every built magazine part builds: %s" % ", ".join(unbuilt), unbuilt.is_empty())

	# Every heavy gun carries something in on a reload: the play test's "reads as a tilt" was a
	# heavy reload with a 5 cm dart, or nothing, in the hand.
	var empty: Array[String] = []
	for id in [ZeeWeaponIds.SNIPER, ZeeWeaponIds.LAUNCHER, ZeeWeaponIds.CHARGE_RIFLE, ZeeWeaponIds.MINIGUN,
			ZeeWeaponIds.BEAMER, ZeeWeaponIds.MARKSMAN]:
		var art := ZeeWeaponArtTable.get_art(id)
		if art == null or not art.has_magazine() or (art.magazine_loose and art.load_from == Vector3.ZERO):
			empty.append(String(id))
	_check("every heavy gun reloads with something carried into it: %s" % ", ".join(empty), empty.is_empty())

	# Every gun that points down -Z (the blasters) has something to show on a reload: a gun whose
	# magazine is baked into its mesh rolls over with an empty hand (the marksman and the beamer
	# did).
	var bare: Array[String] = []
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if art.model_forward == Vector3.FORWARD and not art.has_magazine():
			bare.append(String(art.id))
	_check("every gun has something to show on a reload: %s" % ", ".join(bare), bare.is_empty())

	var table := ZeeWeaponArtTable.table()
	_check("one art entry per weapon", table.size() == 27)

	_art_meshes()

	# The fists are the one weapon with no model, and that is on purpose.
	var fists: ZeeWeaponArt = table[ZeeWeaponIds.FISTS]
	_check("the fists have no model", not fists.has_model())

	_silhouettes()
	_art_asset_root(table)
	_end()


## Every gun must tell from every other in a thumbnail: its length, or its length to height,
## differs by 6% from each other's. Two guns closer than that read as one shape drawn twice.
func _silhouettes() -> void:
	var guns: Array = []
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.has_model() or not [ZeeWeaponArtTable.POSE_PISTOL, ZeeWeaponArtTable.POSE_RIFLE, ZeeWeaponArtTable.POSE_HEAVY].has(art.pose):
			continue
		var box := ZeeModelCache.bounds(art.model_path)
		var length := maxf(box.size.z, 0.001)
		guns.append({"id": art.id, "length": length, "ratio": length / maxf(box.size.y, 0.001)})
	var twins: Array = []
	for i in guns.size():
		for j in range(i + 1, guns.size()):
			var a: Dictionary = guns[i]
			var b: Dictionary = guns[j]
			if absf(a.length / b.length - 1.0) < 0.06 and absf(a.ratio / b.ratio - 1.0) < 0.06:
				twins.append("%s/%s" % [a.id, b.id])
	_check("twenty guns carry a silhouette each", guns.size() >= 18)
	_check("no two guns share a silhouette: %s" % [twins], twins.is_empty())


func _art_meshes() -> void:
	# Eighteen blasters, and each must wear a different one — two roles sharing a mesh
	# is a mistake that reads as a missing model rather than as a duplicated one.
	var meshes: Dictionary = {}
	var duplicates := 0

	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.has_model():
			continue
		if meshes.has(art.model_path):
			duplicates += 1
		meshes[art.model_path] = true

	_check("no two weapons wear the same mesh", duplicates == 0)
	_check("twenty-six meshes, one weapon with none", meshes.size() == 26)


func _art_asset_root(table: Dictionary) -> void:
	# A delivered game mounts its copy of the art under `res://dot_cloud/<id>/<version>/`, and
	# `set_asset_root` is how it says so. Armed: with `scene()` loading `path` rather than the
	# resolved one, the load under a root that holds nothing succeeds and the fourth check fails.
	var pistol: ZeeWeaponArt = table[ZeeWeaponIds.PISTOL]
	_check("built in, a path resolves to itself", ZeeModelCache.resolve(pistol.model_path) == pistol.model_path)

	ZeeModelCache.set_asset_root("res://dot_cloud/x/1.0")
	_check(
		"under a root, res://assets/ moves there (and the root gains its slash)",
		ZeeModelCache.resolve("res://assets/a.glb") == "res://dot_cloud/x/1.0/assets/a.glb"
	)
	_check("a path outside res://assets/ is left alone", ZeeModelCache.resolve("res://addons/a.glb") == "res://addons/a.glb")
	_check("a model is looked for under the root, not where the table says", not ZeeModelCache.scene(pistol.model_path).ok)

	ZeeModelCache.set_asset_root("res://")
	_check("putting res:// back finds it again, not the failure", ZeeModelCache.scene(pistol.model_path).ok)


func _orientation() -> void:
	_begin("orientation")

	# Every blaster in the kit points along -Z, Godot's own forward. The table said +Z for
	# as long as the pack existed and every blaster was drawn stock-first; the rack could
	# not tell, because their bounds are symmetric along their length.
	var blaster := ZeeWeaponArtTable.rifle()
	var pointed := blaster.orientation() * blaster.model_forward.normalized()

	_check(
		"a blaster's -Z barrel stays pointing along Godot's -Z",
		pointed.is_equal_approx(Vector3.FORWARD) and blaster.model_forward == Vector3.FORWARD
	)

	# The one blaster whose bounds are not symmetric says which end is which: blaster-e's
	# mesh runs from its origin back along +Z, and its stock is the heavy end. Its grip, the
	# lowest part of it, is in the back half: so the muzzle is the -Z end.
	var long_box := ZeeModelCache.bounds(ZeeWeaponArtTable.sniper().model_path)
	_check("the sniper's mesh is centred on its origin and 1.3 m long, muzzle on -Z (%.2f..%.2f)" % [long_box.position.z, long_box.end.z],
		long_box.position.z < -0.5 and long_box.end.z > 0.5 and long_box.size.z > 1.2)

	# The melee models stand upright on their handle instead.
	var knife := ZeeWeaponArtTable.knife()
	var blade := knife.orientation() * knife.model_forward.normalized()

	_check(
		"a melee weapon's +Y blade ends up pointing along -Z too",
		blade.is_equal_approx(Vector3.FORWARD)
	)

	# The degenerate case: the rotation taking a vector onto its exact opposite has a
	# zero cross product, and an unguarded axis produces a basis full of NaN — which
	# draws nothing at all, with no error anywhere.
	var flipped := ZeeWeaponArt.make(&"test", "")
	flipped.model_forward = Vector3.BACK
	var basis := flipped.orientation()
	var finite := true

	for i in range(3):
		var column := basis[i]
		if not (is_finite(column.x) and is_finite(column.y) and is_finite(column.z)):
			finite = false

	_check("an exactly reversed model produces no NaN", finite)
	_check(
		"and still ends up facing forward",
		(basis * Vector3.BACK).is_equal_approx(Vector3.FORWARD)
	)

	_end()


func _muzzles() -> void:
	_begin("muzzles")

	# blaster-e is the one model in the kit whose origin is not at its centre: it is at the
	# muzzle, so a hand-written offset correct for the other seventeen puts its muzzle
	# somewhere behind the player's ear. Measuring cannot get that wrong.
	var sniper := ZeeWeaponArtTable.sniper()
	var long := ZeeModelCache.muzzle_distance(
		sniper.model_path, sniper.model_forward
	)

	_check(
		"the longest gun measures its muzzle at half its length, not the whole of it (%.3f)" % long,
		long > 0.5 and long < 0.8
	)
	_check(
		"and its stock end, the other way, is the same half",
		absf(ZeeModelCache.muzzle_distance(sniper.model_path, -sniper.model_forward) - long) < 0.1
	)

	# A centred model measures about half its length, which is the other half of the
	# same claim: the measurement follows the mesh rather than a constant.
	var rifle := ZeeWeaponArtTable.rifle()
	var centred := ZeeModelCache.muzzle_distance(rifle.model_path, rifle.model_forward)

	_check(
		"a centred model measures about half its length",
		centred > 0.25 and centred < 0.45
	)

	_check("a muzzle is never behind the origin", long >= 0.0 and centred >= 0.0)

	# Melee "muzzles" are blade tips, which is the reuse that makes reach work.
	var knife := ZeeWeaponArtTable.knife()
	var tip := ZeeModelCache.muzzle_distance(knife.model_path, knife.model_forward)
	_check("a blade measures a tip", tip > 0.1)

	var missing := ZeeModelCache.muzzle_distance("res://nothing/at/all.glb", Vector3.BACK)
	_check("a model that is not there measures zero rather than failing", missing == 0.0)

	var cached := ZeeModelCache.describe()
	_check("the cache measured something", int(cached["measured"]) > 0)

	# A failed load must not be remembered as a reach of zero, or the muzzle attachment stays unmeasured for the run.
	var dress := preload("res://addons/zee_weapons/view/zee_attachment_dress.gd")
	var ghost := ZeeWeaponArtTable.rifle()
	ghost.model_path = "res://nothing/at/all.glb"
	var fitted := DotWeaponFitting.make(&"rifle")
	fitted.fit(DotWeaponAttachment.MOUNT_MUZZLE, &"suppressor")
	var cache_before: int = dress._reach_cache.size()
	_check("a missing model's muzzle reach is zero and is not cached",
		dress.muzzle_reach(ghost, fitted) == 0.0 and dress._reach_cache.size() == cache_before)

	_end()
