extends "res://examples/selftest/harness.gd"

## Selftest sections: ids, damage, pack, art, workshop, orientation, bash, pose.


func _ids() -> void:
	_begin("ids")

	var all := ZeeWeaponIds.all()
	_check("twenty-seven weapons are named", all.size() == 27)

	var seen: Dictionary = {}
	var duplicates := 0

	for id in all:
		_check_quiet("no id is empty", id != &"")
		if seen.has(id):
			duplicates += 1
		seen[id] = true

	_check("no id appears twice", duplicates == 0)
	_check("seven ammunition pools", ZeeWeaponIds.ammo_pools().size() == 7)

	_end()


## What a loadout screen says about each weapon, read off its own document.
func _cards() -> void:
	_begin("loadout cards")

	var table := ZeeWeaponPack.table()
	var bad := PackedStringArray()
	for id in ZeeWeaponIds.all():
		var card := ZeeWeaponCards.card(table[id])
		var stats: Array = card.get("stats", [])
		var in_range := stats.all(func(s: Variant) -> bool:
			var v := float((s as Dictionary)["value"])
			return v >= 0.0 and v <= 1.0 and str((s as Dictionary)["text"]) != "")
		if str(card.get("detail", "")) == "" or str(card.get("kind", "")) == "" or stats.size() < 3 or not in_range:
			bad.append(String(id))
	_check("every weapon has a line, a kind and at least three bars in 0..1 (%s)" % ", ".join(bad), bad.is_empty())

	var rifle: Array = ZeeWeaponCards.stats(table[ZeeWeaponIds.RIFLE])
	var smg: Array = ZeeWeaponCards.stats(table[ZeeWeaponIds.SMG])
	_check("the rifle out-ranges the SMG and the SMG out-fires the rifle, on the bars",
		float(rifle[2]["value"]) > float(smg[2]["value"]) and float(smg[1]["value"]) > float(rifle[1]["value"]))
	var frag: Array = ZeeWeaponCards.stats(table[ZeeWeaponIds.FRAG])
	_check("a grenade's bars are its blast, radius and count", frag[0]["label"] == "Blast" and frag.size() == 3)
	_check("a shotgun's damage is all its pellets",
		float(ZeeWeaponCards.stats(table[ZeeWeaponIds.SHOTGUN])[0]["text"]) >= 100.0)

	_end()


## A second pack adds weapons, art and a sound class without this one changing, and cannot
## take an id this one has.
func _other_packs() -> void:
	_begin("another pack adds to this one")

	var before := ZeeWeaponPack.weapons().size()
	ZeeWeaponPack.add_source(&"test_pack", func(_types: Dictionary) -> Array[DotWeaponDef]:
		var mine := ZeeWeaponPack.pistol()
		mine.id = &"test_sidearm"
		var clash := ZeeWeaponPack.pistol()
		return [mine, clash])
	ZeeWeaponArtTable.add_source(&"test_pack", func() -> Array[ZeeWeaponArt]:
		var art := ZeeWeaponArtTable.pistol()
		art.id = &"test_sidearm"
		return [art])
	ZeeWeaponSound.set_class(&"test_sidearm", ZeeWeaponSound.MAGNUM)

	var table := ZeeWeaponPack.table()
	_check("its weapon is in the catalogue a rig defaults to",
		ZeeWeaponPack.catalogue().has(&"test_sidearm") and table.has(&"test_sidearm"))
	_check("one more weapon, not two: an id this pack has stays this pack's",
		ZeeWeaponPack.weapons().size() == before + 1)
	_check("the pistol is still this pack's pistol", (table[&"pistol"] as DotWeaponDef).display_name == ZeeWeaponPack.pistol().display_name)
	_check("its art is in the table", ZeeWeaponArtTable.get_art(&"test_sidearm") != null)
	_check("and the table still validates with it there", ZeeWeaponArtTable.validate().ok)
	_check("and it sounds like the class it asked for",
		ZeeWeaponSound.class_for(&"test_sidearm", DotWeaponOutcome.KIND_SHOT) == ZeeWeaponSound.MAGNUM)

	ZeeWeaponPack.remove_source(&"test_pack")
	ZeeWeaponArtTable.remove_source(&"test_pack")
	_check("removed, it is gone from the catalogue", not ZeeWeaponPack.table().has(&"test_sidearm"))
	_check("and from the art", ZeeWeaponArtTable.get_art(&"test_sidearm") == null)

	# The table is memoised (per figure per frame callers): the same instance twice, and a
	# source added or removed rebuilds it.
	var cached := ZeeWeaponArtTable.table()
	_check("the art table is cached: two calls, one instance",
		cached == ZeeWeaponArtTable.table() and ZeeWeaponArtTable.get_art(&"pistol") == cached[&"pistol"])
	ZeeWeaponArtTable.add_source(&"cache_pack", func() -> Array[ZeeWeaponArt]:
		var extra := ZeeWeaponArtTable.pistol()
		extra.id = &"cache_sidearm"
		return [extra])
	_check("add_source invalidates the cached table",
		ZeeWeaponArtTable.table() != cached and ZeeWeaponArtTable.get_art(&"cache_sidearm") != null)
	ZeeWeaponArtTable.remove_source(&"cache_pack")
	_check("remove_source invalidates it again",
		ZeeWeaponArtTable.get_art(&"cache_sidearm") == null and ZeeWeaponArtTable.table().size() == 27)

	_end()


func _pack_source() -> void:
	_begin("ZeePackSource")

	var provider := GDScript.new()
	provider.source_code = "extends RefCounted\nstatic func weapon_defs(_t: Dictionary) -> Array[DotWeaponDef]:\n\tvar a := ZeeWeaponPack.pistol()\n\ta.id = &\"ps_gun\"\n\tvar b := ZeeWeaponPack.knife()\n\tb.id = &\"ps_blade\"\n\treturn [a, b]\n"
	provider.reload()
	var defs_source := Callable(provider, &"weapon_defs")
	ZeePackSource.register(&"ps_test", provider, defs_source)
	_check("its weapons join the catalogue", ZeeWeaponPack.table().has(&"ps_gun") and ZeeWeaponPack.table().has(&"ps_blade"))
	_check("a pack with no art gets stand-in art for each", ZeeWeaponArtTable.get_art(&"ps_gun") != null and ZeeWeaponArtTable.get_art(&"ps_blade") != null)
	var gun := ZeeWeaponArtTable.get_art(&"ps_gun")
	var pistol := ZeeWeaponArtTable.get_art(&"pistol")
	_check("a sidearm stands in as the pistol's art", gun.id == &"ps_gun" and gun.model_path == pistol.model_path)
	_check("a melee weapon as the knife's, not the pistol's",
		ZeeWeaponArtTable.get_art(&"ps_blade").model_path == ZeeWeaponArtTable.get_art(&"knife").model_path)
	_check("the table still validates", ZeeWeaponArtTable.validate().ok)
	var plain := ZeeWeaponPack.rifle()
	plain.tags.clear()
	plain.slot = ZeeWeaponIds.SLOT_HEAVY
	_check("no tier tag: the slot decides", ZeePackSource.stand_in_art([plain], provider)[0].model_path == ZeeWeaponArtTable.launcher().model_path)
	ZeePackSource.unregister(&"ps_test")
	_check("unregistered, the weapons are gone", not ZeeWeaponPack.table().has(&"ps_gun"))
	_check("and the art", ZeeWeaponArtTable.get_art(&"ps_gun") == null)

	_end()


func _pack_scan() -> void:
	_begin("ZeePackScan and ZeePackRoles")

	var provider := GDScript.new()
	provider.source_code = "extends RefCounted\nstatic func weapon_defs(_t: Dictionary) -> Array[DotWeaponDef]:\n\tvar a := ZeeWeaponPack.pistol()\n\ta.id = &\"sc_gun\"\n\ta.tags = [&\"ranged\"]\n\tvar b := ZeeWeaponPack.knife()\n\tb.id = &\"sc_blade\"\n\tb.tags = [&\"melee\"]\n\treturn [a, b]\n"
	provider.reload()
	var defs := ZeePackScan.defs_of({}, provider)
	_check("defs_of hands the provider's defs through", defs.size() == 2)
	_check("kept drops excluded ids", ZeePackScan.kept(defs, ["sc_gun"]).size() == 1)
	_check("kept drops ids already taken", ZeePackScan.kept(defs, [], [&"sc_blade"]).size() == 1)
	var tiers: Array[StringName] = [&"sidearm", &"primary", &"melee"]
	var tiered := ZeePackRoles.tiered({}, provider, tiers, {})
	_check("an untiered ranged def joins the fallback", tiered[0].tags.has(&"primary"))
	_check("an untiered melee def joins melee", tiered[1].tags.has(&"melee"))
	var forced := ZeePackRoles.tiered({}, provider, tiers, {"sc_gun": "sidearm"})
	_check("an override wins", forced[0].tags.has(&"sidearm") and not forced[0].tags.has(&"primary"))
	var by_id := {}

	for def in defs:
		by_id[def.id] = def

	_check("first_for_slot picks by slot", ZeePackRoles.first_for_slot([&"sc_gun", &"sc_blade"], by_id, ZeeWeaponIds.SLOT_MELEE, &"knife") == &"sc_blade")
	_check("none in the slot is empty", ZeePackRoles.first_for_slot([&"sc_gun"], by_id, ZeeWeaponIds.SLOT_HEAVY, &"launcher") == &"")
	_check("a missing folder has no providers", ZeePackScan.provider_dirs("res://no_such_dir", "spawn_provider.gd").is_empty())

	_end()


func _damage() -> void:
	_begin("damage types")

	var table := ZeeWeaponDamage.table()
	_check("four damage types", table.size() == 4)

	for id: StringName in table.keys():
		var type: DotDamageType = table[id]
		_check_quiet("%s has its own id" % String(id), type.id == id)

	_check(
		"a dart does not hurt the person who fired it",
		ZeeWeaponDamage.dart().self_scale == 0.0
	)
	_check(
		"a blast does, at half",
		is_equal_approx(ZeeWeaponDamage.blast().self_scale, 0.5)
	)
	_check(
		"a blast ignores hit groups",
		not ZeeWeaponDamage.blast().uses_hit_groups
	)
	_check(
		"armour barely stops a strike",
		ZeeWeaponDamage.strike().armour_share < 0.25
	)

	# The fallback path: a game supplying an incomplete table still gets a type back.
	var partial := {ZeeWeaponIds.DAMAGE_DART: ZeeWeaponDamage.dart()}
	var fell_back := ZeeWeaponDamage.from(partial, ZeeWeaponIds.DAMAGE_BLAST)
	_check("a missing type falls back rather than returning null", fell_back != null)
	_check(
		"and falls back to the right one",
		fell_back != null and fell_back.id == ZeeWeaponIds.DAMAGE_BLAST
	)

	_end()


func _pack() -> void:
	_begin("the weapon table")

	var catalogue := ZeeWeaponPack.catalogue()
	var res := catalogue.validate()
	_check("the whole catalogue validates: %s" % _why(res), res.ok)
	_check("twenty-seven rows", catalogue.size() == 27)

	# The check that catches an id added to one file and not the other. ids() is in text
	# order, so this sorts by text too: sort() on StringNames orders them by where each was
	# interned, which differs per process (it passed only while ids() made the same mistake).
	var ids := catalogue.ids()
	var named := ZeeWeaponIds.all()
	named.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_check(
		"the catalogue and ZeeWeaponIds name exactly the same weapons, in text order",
		ids == named
	)

	var behaviours := catalogue.validate_behaviours()
	_check("every behaviour script resolves: %s" % _why(behaviours), behaviours.ok)

	# Every duration is in ticks, so nothing may be fractional or negative.
	var bad_timing := 0
	var no_tuning := 0

	for def in ZeeWeaponPack.weapons():
		if def.use_interval_ticks < 0 or def.deploy_ticks < 0 or def.reload_ticks < 0:
			bad_timing += 1
		if def.tuning == null:
			no_tuning += 1

	_check("no negative durations", bad_timing == 0)
	_check("every weapon carries tuning", no_tuning == 0)

	# The roles have to actually differ, or this is one weapon with twenty-seven skins.
	var damages: Dictionary = {}
	for def in ZeeWeaponPack.weapons():
		var b := def.tuning as DotWeaponBallistics
		if b != null:
			damages[snappedf(b.damage, 0.5)] = true

	_check("at least fifteen distinct damage values", damages.size() >= 15)

	var melee := catalogue.ids_with_tag(ZeeWeaponIds.TAG_MELEE)
	_check("seven melee weapons carry the melee tag", melee.size() == 7)

	var slots := catalogue.ids_in_slot(ZeeWeaponIds.SLOT_THROWN)
	_check("two weapons in the thrown slot", slots.size() == 2)

	# The death reactions' params (read by dot-player-char by name): the two heaviest hits
	# always throw the body, and nothing light can.
	var table := ZeeWeaponPack.table()
	_check("the sniper and the launcher name the power launch",
		(table[ZeeWeaponIds.SNIPER] as DotWeaponDef).params.get(ZeeWeaponIds.PARAM_DEATH_REACTION) == &"power_launch"
		and (table[ZeeWeaponIds.LAUNCHER] as DotWeaponDef).params.get(ZeeWeaponIds.PARAM_DEATH_REACTION) == &"power_launch")
	var powered := 0
	var light_powered := 0
	for def in ZeeWeaponPack.weapons():
		var power := float(def.params.get(ZeeWeaponIds.PARAM_DEATH_POWER, 0.0))
		if power >= 0.5:
			powered += 1
		if power > 0.0 and def.tags.has(ZeeWeaponIds.TAG_SIDEARM):
			light_powered += 1
	_check("six weapons are powerful enough to launch a body (%d)" % powered, powered == 6)
	_check("no sidearm is", light_powered == 0)

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
	var mean := ZeeViewArms.mean_of(ZeeViewArms.surface_albedos(dark_gun))
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


func _workshop() -> void:
	_begin("the Workshop files agree with the code table")

	var text := FileAccess.get_file_as_string("res://provides.json")
	var doc: Variant = JSON.parse_string(text)
	_check("provides.json parses to a dictionary", doc is Dictionary)
	if not (doc is Dictionary):
		_end()
		return

	var provides := doc as Dictionary
	var code := ZeeDefExport.own_weapons()
	var entries: Array = provides.get("entries", [])
	_check("schema 1, kind weapon", int(provides.get("schema", 0)) == 1 and provides.get("kinds", []) == ["weapon"])
	_check("one entry per code weapon", entries.size() == code.size() and code.size() == ZeeWeaponIds.all().size())
	_check("provides.json is what the exporter writes now (run tools/export-defs.sh)",
		JSON.stringify(provides) == JSON.stringify(JSON.parse_string(JSON.stringify(ZeeDefExport.provides(code)))))

	var cat_ids := {}
	for c: Dictionary in provides.get("categories", []):
		cat_ids[c["id"]] = true

	var by_id := {}
	for def in code:
		by_id[def.id] = def

	for e: Dictionary in entries:
		var id := StringName(e["id"])
		var def: DotWeaponDef = by_id.get(id, null)
		_check_quiet("%s: an entry for a code weapon" % id, def != null)
		_check_quiet("%s: category is declared and matches the slot" % id,
			cat_ids.has(e.get("category", "")) and def != null and e["category"] == ZeeDefExport.category_for(def.slot))
		_check_quiet("%s: the file exists" % id, ResourceLoader.exists("res://" + String(e["def"])))
		var loaded := load("res://" + String(e["def"])) as DotWeaponDef
		_check_quiet("%s: loads as a DotWeaponDef with the entry's id" % id, loaded != null and String(loaded.id) == e["id"])
		if loaded != null and def != null:
			_check_quiet("%s: the .tres equals the code row" % id, _same(loaded, def, id))
			_check_quiet("%s: behaviour stays in the host build" % id, loaded.behaviour_path.begins_with("res://addons/dot_weapon/"))
		_check_quiet("%s: asset_root is declared" % id, (e.get("meta", {}) as Dictionary).has("asset_root"))

	# Fed the way a mounted pack is: the index holds the document, the catalogue follows it.
	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var added := index.add_pack({
		"content_id": "gamemann/zee-dot-weapons", "version": "1.0.0", "prefix": "res://",
		"session": "solo", "source": "subscription", "provides": provides,
	})
	_check("the index takes the pack", added.ok)
	var cat := DotWeaponCatalogue.new().follow_content(index)
	_check("the catalogue resolves every weapon", cat.size() == code.size())
	_check("and validates", cat.validate().ok)

	var missing := 0
	for def in code:
		if not cat.has(def.id) or cat.listing(def.id) == null:
			missing += 1
	_check("every code id is delivered", missing == 0)
	var l := cat.listing(&"rifle")
	_check("a listing carries the pack, the category and asset_root",
		l != null and l.is_delivered() and l.category == "primary" and l.meta.get("asset_root", "") == ZeeDefExport.ASSET_ROOT)
	_check("a delivered weapon instantiates its behaviour", cat.instantiate(&"knife").ok and cat.instantiate(&"launcher").ok)
	cat.unfollow_content()

	# The same document over a catalogue that already has the code table: code wins every id.
	var full := ZeeWeaponPack.catalogue().follow_content(index)
	_check("over the code table every delivered row is refused and nothing doubles", full.size() == code.size())
	full.unfollow_content()

	_end()


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

	_end()


func _arsenal() -> void:
	_begin("the arsenal")

	var arsenal := _make_arsenal()
	var res := arsenal.setup()
	_check("an arsenal built on the pack sets up: %s" % _why(res), res.ok)

	var given := 0
	for id in [
		ZeeWeaponIds.KNIFE, ZeeWeaponIds.PISTOL, ZeeWeaponIds.RIFLE,
		ZeeWeaponIds.LAUNCHER, ZeeWeaponIds.FRAG,
	]:
		if arsenal.give(id).ok:
			given += 1

	_check("five weapons across five slots are carried", given == 5)
	_check("the first one given is in hand", arsenal.current() != null)

	# Firing the rifle: hold the trigger and count what comes out.
	arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run(arsenal, 0, 40, 0)                     # let the deploy finish

	var rifle := arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY)
	var before := rifle.magazine
	var shots := _run(arsenal, 40, 100, DotWeaponCommand.BUTTON_ATTACK)

	_check("holding the trigger fires an automatic weapon", shots > 3)
	_check("and spends the magazine", rifle.magazine < before)

	# The bug dot-weapon's CLAUDE.md is loudest about: a held trigger on an empty
	# weapon must not cancel the reload it just started, for ever.
	rifle.magazine = 0

	# Held through less than one reload, so nothing can legitimately come out yet.
	var dry := _run(arsenal, 140, 200, DotWeaponCommand.BUTTON_ATTACK)
	_check("an empty weapon fires nothing while held", dry == 0)

	# Kept held well past the reload. The bug this guards is that a held trigger cancels
	# the reload it just started, every time the cadence comes round, so the magazine
	# never refills — nothing errors and the weapon simply stops working.
	_run(arsenal, 200, 400, DotWeaponCommand.BUTTON_ATTACK)
	_check(
		"and refills anyway, rather than restarting its reload for ever",
		rifle.magazine > 0
	)

	_cleanup(arsenal)
	_end()


func _bash() -> void:
	_begin("the bash")

	_check(
		"a blaster can bash",
		ZeeWeaponBash.can_bash(ZeeWeaponPack.rifle())
	)
	_check(
		"a melee weapon cannot — that would be two buttons doing one thing",
		not ZeeWeaponBash.can_bash(ZeeWeaponPack.hatchet())
	)
	_check(
		"nor can a grenade",
		not ZeeWeaponBash.can_bash(ZeeWeaponPack.frag())
	)
	_check("and neither can nothing at all", not ZeeWeaponBash.can_bash(null))

	var bash := ZeeWeaponBash.new()
	bash.for_def(ZeeWeaponPack.rifle())

	var ctx := DotWeaponContext.make(7, 100, Vector3.ZERO, Vector3.FORWARD)
	var outcome := bash.use(ctx)

	_check("a bash is a swing", outcome.kind == DotWeaponOutcome.KIND_SWING)
	_check("it produces exactly one shot", outcome.shots.size() == 1)
	_check("it spends no ammunition", outcome.ammo_used == 0)
	_check("it sets its own cadence", outcome.cooldown_ticks > 0)
	_check(
		"it reaches about two metres, not two hundred",
		outcome.shots[0].max_range > 1.0 and outcome.shots[0].max_range < 3.0
	)
	_check(
		"it is billed to the weapon, so a kill feed can name it",
		outcome.shots[0].weapon_id == ZeeWeaponIds.RIFLE
	)

	# A behaviour must be a pure function of its context: the same context twice must
	# give the same answer, or a client and a server disagree about what happened.
	var again := bash.use(DotWeaponContext.make(7, 100, Vector3.ZERO, Vector3.FORWARD))
	_check(
		"the same context produces the same damage twice",
		is_equal_approx(again.shots[0].damage, outcome.shots[0].damage)
	)

	_end()


func _feel() -> void:
	_begin("the feel cvars and the strafe tilt")

	var strafed := ZeeWeaponPose.make(1.0)
	for i in range(60):
		strafed.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true, false, 5.0)
	var right := strafed.offset()
	_check("strafing right trails the weapon left", right.origin.x < -0.005)
	_check("and rolls it counter-clockwise", right.basis.get_euler().z > 0.03)

	var left := ZeeWeaponPose.make(1.0)
	for i in range(60):
		left.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true, false, -5.0)
	_check("strafing left is the mirror", left.offset().origin.x > 0.005)

	# Aimed, the sight stays on the view axis: nothing slides it sideways.
	strafed.set_aim(1.0)
	var aimed := strafed.offset()
	_check("aimed, a strafe moves the weapon less than a hundredth of a metre sideways",
		absf(aimed.origin.x) < 0.01)
	_check("and rolls it under a degree", absf(aimed.basis.get_euler().z) < deg_to_rad(1.0))

	strafed.rules.strafe_tilt = 0.0
	strafed.rules.aim_steadiness = 0.0
	strafed.set_aim(0.0)
	_check("strafe tilt 0 switches it off", absf(strafed.offset().basis.get_euler().z) < 0.001)

	var rules := ZeeViewFeel.new()
	_check("a cvar value is applied", rules.set_cvar(ZeeViewFeel.CVAR_BOB, "0.5") and is_equal_approx(rules.bob, 0.5))
	_check("a value out of range is refused", not rules.set_cvar(ZeeViewFeel.CVAR_BOB, "9") and is_equal_approx(rules.bob, 0.5))
	_check("so is one that is not a number", not rules.set_cvar(ZeeViewFeel.CVAR_SWAY, "lots"))
	_check("every amount is a cvar", rules.cvar_specs().size() == 9)

	var landed := ZeeWeaponPose.make(1.0)
	landed.land(9.0)
	var dip := landed.offset().origin.y
	landed.reset()
	landed.rules.landing = 0.0
	landed.land(9.0)
	_check("a landing dips the weapon, and landing 0 does not", dip < -0.01 and absf(landed.offset().origin.y) < 0.001)
	_end()


func _pose() -> void:
	_begin("the pose")

	var pose := ZeeWeaponPose.make(1.0)
	var rest := pose.offset()

	_check("at rest it is near the origin", rest.origin.length() < 0.01)

	# A kick is an impulse into a spring, so it must move and then come back.
	pose.punch(Vector2(3.0, 0.5))
	for i in range(3):
		pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	var kicked := pose.offset()
	_check("firing moves the weapon", kicked.origin.length() > 0.001)

	for i in range(240):
		pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	var settled := pose.offset()
	_check(
		"and four seconds later it has settled back",
		settled.origin.length() < 0.002
	)

	# Bob is driven by distance travelled, not by time, so a player standing still has
	# none however long they stand there.
	var still := ZeeWeaponPose.make(1.0)
	for i in range(120):
		still.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)

	_check(
		"standing still produces no bob however long you stand",
		still.offset().origin.length() < 0.002
	)

	var walking := ZeeWeaponPose.make(1.0)
	for i in range(120):
		walking.advance(1.0 / 60.0, Vector2.ZERO, 6.0, true)

	_check("walking does produce bob", walking.offset().origin.length() > 0.002)

	# A holstered weapon drops out of frame. The deploy fraction is the whole animation.
	var switching := ZeeWeaponPose.make(1.0)
	switching.set_deploy(0.0)
	_check(
		"fully holstered, the weapon is well below its resting place",
		switching.offset().origin.y < -0.2
	)

	switching.set_deploy(1.0)
	_check(
		"fully deployed, it is back",
		absf(switching.offset().origin.y) < 0.02
	)

	_end()
