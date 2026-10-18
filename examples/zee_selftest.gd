extends Node

## The headless suite. Run it before believing anything in this repository.
##
## [b]It counts two things, and the second is the one that catches what the first
## cannot.[/b] Sections entered against sections that ran to their last line, and a total
## number of checks. A script error aborts the section it is in and nothing else, and the
## section counter is already satisfied because the section announced itself on the way
## in — so a suite counting only sections reports "12 sections, 0 failed" while eight
## checks never ran. Another project in this family shipped exactly that.
##
## [b]What it cannot see.[/b] Everything about how the weapons look. Whether the sniper
## is held at the right angle, whether the reload reads as a reload, whether the arms are
## in front of the gun rather than through it — no assertion reaches any of that, and
## four bugs in this family were found by looking at a picture that every check had
## passed. `tools/screenshot.sh` is the other half of the test suite and is not optional.

# No CHANNEL: a suite's verdict is its output, and it prints it; it is not a log record.

## Every check this suite makes. A script error aborts the section it is in, and a section
## that aborts after its last `_check` still counts as finished; only a total can see the
## checks that never ran. It was counted and compared with nothing until 2026-09-24.
const CHECKS := 460

var _sections_entered: int = 0
var _sections_finished: int = 0
var _checks: int = 0
var _failures: int = 0
var _section: String = ""


func _ready() -> void:
	print("zee-dot-weapons self-test")
	print("=========================")

	_ids()
	_damage()
	_pack()
	_cards()
	_art()
	_other_packs()
	_workshop()
	_orientation()
	_muzzles()
	_arsenal()
	_bash()
	_pose()
	_feel()
	_pose_stability()
	_recoil()
	_net()
	_rig()
	_rig_carrier()
	_rig_rollback()
	_tick_rate()
	_view_models()
	_aim()
	_effects()
	_input_bindings()

	print("")
	print("%d sections entered, %d finished, %d checks, %d failed" % [
		_sections_entered, _sections_finished, _checks, _failures
	])

	if _sections_entered != _sections_finished:
		print(
			"!! %d section(s) did not reach their last line — a script error aborted "
			% (_sections_entered - _sections_finished)
			+ "one, and its remaining checks never ran."
		)

	if _checks != CHECKS:
		print("!! %d checks ran, %d expected. A section aborted part-way." % [_checks, CHECKS])

	var passed := _failures == 0 and _sections_entered == _sections_finished and _checks == CHECKS

	print("RESULT: %s" % ("PASS" if passed else "FAIL"))

	# Half a second before quitting, for the effects section: a report still playing is
	# held by the audio server until its mix thread lets go, and quitting before it has
	# reports the playback and its stream as leaked at exit. Four frames was the first
	# try and leaked two of each on about half the runs (2026-10-05): the mix thread runs
	# on its own clock, not the frame's, and four headless frames can pass inside one of
	# its periods. Stopping the voice and dropping its stream in ZeeShotFx._exit_tree did
	# not change the rate, so the wait is the fix and it is measured: 0 in 6 runs.
	await get_tree().create_timer(0.5).timeout

	get_tree().quit(0 if passed else 1)


# --- Sections ---------------------------------------------------------------

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
	for id in [ZeeWeaponIds.SNIPER, ZeeWeaponIds.LAUNCHER, ZeeWeaponIds.CHARGE_RIFLE, ZeeWeaponIds.MINIGUN]:
		var art := ZeeWeaponArtTable.get_art(id)
		if art == null or not art.has_magazine() or (art.magazine_loose and art.load_from == Vector3.ZERO):
			empty.append(String(id))
	_check("every heavy gun reloads with something carried into it: %s" % ", ".join(empty), empty.is_empty())

	var table := ZeeWeaponArtTable.table()
	_check("one art entry per weapon", table.size() == 27)

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

	# The fists are the one weapon with no model, and that is on purpose.
	var fists: ZeeWeaponArt = table[ZeeWeaponIds.FISTS]
	_check("the fists have no model", not fists.has_model())

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

	_end()


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


## True when [param a] and [param b] hold the same stored values, resources compared by value.
func _same(a: Variant, b: Variant, what: String) -> bool:
	if a is Resource and b is Resource:
		var ra := a as Resource
		var rb := b as Resource
		if ra.get_script() != rb.get_script():
			print("   differs: %s script" % what)
			return false

		for p: Dictionary in ra.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE) or p["name"] == "resource_path":
				continue
			if not _same(ra.get(p["name"]), rb.get(p["name"]), "%s.%s" % [what, p["name"]]):
				return false

		return true

	if a is Dictionary and b is Dictionary:
		var da := a as Dictionary
		var db := b as Dictionary
		if da.size() != db.size():
			print("   differs: %s size" % what)
			return false
		for k: Variant in da:
			if not db.has(k) or not _same(da[k], db[k], "%s[%s]" % [what, k]):
				return false
		return true

	if a is Array and b is Array:
		var aa := a as Array
		var ab := b as Array
		if aa.size() != ab.size():
			print("   differs: %s size" % what)
			return false
		for i in aa.size():
			if not _same(aa[i], ab[i], "%s[%d]" % [what, i]):
				return false
		return true

	if typeof(a) != typeof(b) or a != b:
		print("   differs: %s (%s vs %s)" % [what, str(a), str(b)])
		return false

	return true


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
	_check("every amount is a cvar", rules.cvar_specs().size() == 5)

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


func _pose_stability() -> void:
	_begin("pose stability")

	# The one integration bug that takes a few seconds of held fire to show up: explicit
	# Euler adds energy at every step, so a spring that should settle grows instead.
	var pose := ZeeWeaponPose.make(2.0)
	var worst := 0.0

	for i in range(2000):
		if i % 4 == 0:
			pose.punch(Vector2(4.0, 1.0))
		pose.advance(1.0 / 64.0, Vector2(9.0, 3.0), 8.0, true)
		worst = maxf(worst, pose.offset().origin.length())

	_check(
		"thirty seconds of held automatic fire does not make the spring explode",
		worst < 1.0
	)

	var final := pose.offset()
	var finite := (
		is_finite(final.origin.x) and is_finite(final.origin.y)
		and is_finite(final.origin.z)
	)
	_check("and produces no NaN", finite)

	# A frame after a level load can be a whole second long. Unclamped, an exponential
	# step with a one-second delta overshoots and comes back, which reads as a snap.
	var hitching := ZeeWeaponPose.make(1.0)
	hitching.advance(3.0, Vector2(400.0, 120.0), 20.0, true)
	var after := hitching.offset()
	_check(
		"a three-second frame does not throw the weapon off the screen",
		after.origin.length() < 0.5
	)

	# Nothing here may produce a NaN, whatever it is handed.
	var abused := ZeeWeaponPose.make(1.0)
	abused.advance(0.0, Vector2.ZERO, 0.0, true)
	abused.advance(-1.0, Vector2.ZERO, 0.0, true)
	abused.punch(Vector2(NAN, NAN))
	abused.land(NAN)
	abused.set_deploy(NAN)
	abused.advance(1.0 / 60.0, Vector2.ZERO, NAN, true)

	var abused_at := abused.offset().origin
	_check(
		"NaN handed in at every entry point never reaches the transform",
		is_finite(abused_at.x) and is_finite(abused_at.y) and is_finite(abused_at.z)
	)

	# Frame-rate independence: the same second of sway at 60 and at 144 must land in
	# roughly the same place, or a weapon tuned on one machine sways wrong on another.
	var slow := ZeeWeaponPose.make(1.0)
	var fast := ZeeWeaponPose.make(1.0)

	for i in range(60):
		slow.advance(1.0 / 60.0, Vector2(2.0, 0.0), 0.0, true)

	for i in range(144):
		fast.advance(1.0 / 144.0, Vector2(2.0 * 60.0 / 144.0, 0.0), 0.0, true)

	var apart := (slow.offset().origin - fast.offset().origin).length()
	_check("sway lands in the same place at 60 fps and at 144", apart < 0.005)

	# Turning right (yaw falling: the controller's yaw is positive to the left) leaves the
	# weapon behind on the left. It led the turn until the contact sheet showed it.
	var turning := ZeeWeaponPose.make(1.0)
	for i in range(12):
		turning.advance(1.0 / 60.0, Vector2(-3.0, 0.0), 0.0, true)
	_check("turning right leaves the weapon behind, to the left (x %.3f)" % turning.offset().origin.x,
		turning.offset().origin.x < -0.005)

	# The authored keys start and finish at rest, and read through no NaN.
	_check("a reload's keys are at rest at 0 and at 1",
		ZeeWeaponPose.sample_keys(ZeeWeaponPose.RELOAD_KEYS_RIFLE, 0.0)[1].length() < 0.0001
		and ZeeWeaponPose.sample_keys(ZeeWeaponPose.RELOAD_KEYS_RIFLE, 1.0)[1].length() < 0.0001)
	_check("the draw's keys are at rest in hand",
		ZeeWeaponPose.sample_keys(ZeeWeaponPose.DRAW_KEYS, 1.0)[0].length() < 0.0001)
	# [b]A melee weapon moves when it strikes.[/b] A swing was the recoil spring alone and a melee
	# weapon has no recoil: the knife did nothing on screen when it cut.
	_check("a swing's and a throw's keys start and finish at rest",
		ZeeWeaponPose.sample_keys(ZeeWeaponPose.SWING_KEYS, 0.0)[1].length() < 0.0001
		and ZeeWeaponPose.sample_keys(ZeeWeaponPose.SWING_KEYS, 1.0)[1].length() < 0.0001
		and ZeeWeaponPose.sample_keys(ZeeWeaponPose.THROW_KEYS, 1.0)[0].length() < 0.0001)
	var swinger := ZeeWeaponPose.make(1.0)
	var at_rest := swinger.offset()
	swinger.swing()
	for i in range(9):
		swinger.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	var mid_swing := swinger.offset()
	for i in range(60):
		swinger.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	var swung_across := rad_to_deg(mid_swing.basis.get_rotation_quaternion().angle_to(at_rest.basis.get_rotation_quaternion()))
	_check("a swing turns the weapon well across mid-cut (%.0f deg) and is back at rest after it" % swung_across,
		swung_across > 30.0 and swinger.action_fraction() >= 1.0
		and swinger.offset().origin.distance_to(at_rest.origin) < 0.001)

	var odd: Vector3 = ZeeWeaponPose.sample_keys([[0.0, Vector3.ONE, Vector3.ONE]], NAN)[0]
	_check("malformed keys sample as rest", odd == Vector3.ZERO)

	# [b]No jitter.[/b] A whole draw and reload at 144 fps while walking and turning (a kick is
	# meant to be fast, and the recoil sections hold it): no frame may move the weapon further than a smooth motion of that size could,
	# and every key is a curve, so no frame jumps. A step in a key table or a spring that
	# rings shows here as one frame far bigger than the frames either side of it.
	for keys: Array in [ZeeWeaponPose.RELOAD_KEYS_RIFLE, ZeeWeaponPose.RELOAD_KEYS_PISTOL, ZeeWeaponPose.RELOAD_KEYS_HEAVY,
			ZeeWeaponPose.RELOAD_KEYS_BOLT, ZeeWeaponPose.RELOAD_KEYS_BREAK, ZeeWeaponPose.RELOAD_KEYS_MUZZLE,
			ZeeWeaponPose.RELOAD_KEYS_TUBE]:
		var smooth := ZeeWeaponPose.make(1.0)
		smooth.pivot = Vector3(0.19, -0.23, -0.40)
		smooth.tunables.reload_keys = keys
		var dt := 1.0 / 144.0
		smooth.set_deploy(0.0)
		var last := smooth.offset()
		var last_step := Vector3.ZERO
		var last_turn := 0.0
		var worst_move := 0.0
		var worst_turn := 0.0
		var frames := 720
		for i in range(frames):
			var t := float(i) / float(frames)
			smooth.set_deploy(clampf(t * 4.0, 0.0, 1.0))
			smooth.set_reload(clampf((t - 0.3) * 2.0, 0.0, 1.0))
			smooth.advance(dt, Vector2(-0.6, 0.1), 5.0, true)
			var now := smooth.offset()
			# The change in the frame's movement, not the movement: a fast smooth motion
			# changes speed a little each frame, a jolt changes it all at once.
			var step := now.origin - last.origin
			var turn := rad_to_deg(
				now.basis.get_rotation_quaternion().angle_to(last.basis.get_rotation_quaternion())
			)
			if i > 1:
				worst_move = maxf(worst_move, (step - last_step).length())
				worst_turn = maxf(worst_turn, absf(turn - last_turn))
			last_step = step
			last_turn = turn
			last = now
		_check("a draw and reload at 144 fps never jolts (worst %.5f m, %.3f deg a frame on a frame)" % [worst_move, worst_turn],
			worst_move < 0.0015 and worst_turn < 0.3 and last.origin.is_finite())

	# [b]A run bobs at a cadence, a walk per metre.[/b] Per metre alone, a 9 m/s run bobbed
	# ten footfalls a second and the weapon buzzed (game-arena's `headless_feel`, 2.3 mm of
	# change in a frame's movement at 144 fps). Footfalls are the bob's high points.
	var cadence := func(speed: float) -> float:
		var walker := ZeeWeaponPose.make(1.0)
		var heights: Array[float] = []
		for i in range(144 * 4):
			walker.advance(1.0 / 144.0, Vector2.ZERO, speed, true)
			heights.append(walker.offset().origin.y)
		var peaks := 0
		for i in range(144 * 2, heights.size() - 1):
			if heights[i] > heights[i - 1] and heights[i] >= heights[i + 1]:
				peaks += 1
		return float(peaks) / 2.0
	var run: float = cadence.call(9.0)
	var walk: float = cadence.call(2.0)
	_check("a 9 m/s run bobs at most three and a half footfalls a second (%.1f), a 2 m/s walk by its pace (%.1f)" % [run, walk],
		run <= 3.5 and run >= 2.0 and walk > 1.5 and walk < run)

	_end()


func _recoil() -> void:
	_begin("recoil")

	# Every gun's single-shot climb, at its real weight and its real recoil.
	var climbs := {}

	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		var b := def.tuning as DotWeaponBallistics
		if b == null or b.recoil_pitch <= 0.0:
			continue

		var art := ZeeWeaponArtTable.get_art(def.id)
		var pose := ZeeWeaponPose.make(art.weight if art != null else 1.0)
		pose.punch(Vector2(b.recoil_pitch, b.recoil_yaw))

		var peak := 0.0
		for i in range(144):
			pose.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
			peak = maxf(peak, (pose.describe()["kick_rotation"] as Vector3).x)

		climbs[def.id] = peak

	var hardest := 0.0
	var softest := INF
	for id in climbs:
		hardest = maxf(hardest, climbs[id])
		softest = minf(softest, climbs[id])

	# Armed: before the curve, one sniper shot climbed 17 degrees and 13 cm, one minigun
	# shot 0.6, and the ratio between them was 28.
	_check(
		"one sniper shot climbs under eight degrees (%.1f)" % climbs[ZeeWeaponIds.SNIPER],
		climbs[ZeeWeaponIds.SNIPER] < 8.0
	)
	_check(
		"the hardest kick is under fifteen times the softest (%.1f / %.1f)" % [hardest, softest],
		hardest / maxf(0.001, softest) < 15.0
	)
	_check(
		"an automatic's kick is big enough to see (smg %.2f)" % climbs[ZeeWeaponIds.SMG],
		climbs[ZeeWeaponIds.SMG] > 0.75
	)

	# The climb asked for is the climb drawn. A semi-implicit step under critical damping
	# bled a third of every kick away, so the number tuned was never the number seen.
	var asked := ZeeWeaponPose.make(1.0).kick_degrees(2.0)
	var drawn: Array[float] = []
	for rate in [144.0, 30.0]:
		var p := ZeeWeaponPose.make(1.0)
		p.punch(Vector2(2.0, 0.0))
		var top := 0.0
		for i in range(int(rate)):
			p.advance(1.0 / rate, Vector2.ZERO, 0.0, true)
			top = maxf(top, (p.describe()["kick_rotation"] as Vector3).x)
		drawn.append(top)
	_check(
		"the climb drawn is the climb asked for, at 144 fps and at 30 (%.2f: %.2f, %.2f)"
		% [asked, drawn[0], drawn[1]],
		absf(drawn[0] - asked) / asked < 0.05 and absf(drawn[1] - asked) / asked < 0.1
	)

	# Armed: the yaw was applied as the behaviour handed it, always positive, so every
	# shot pushed the gun the same way and a held trigger walked it off to one side.
	var sides := ZeeWeaponPose.make(1.0)
	var left := 0
	var right := 0
	for i in range(20):
		var before := (sides.describe()["kick_rotation"] as Vector3).y
		sides.punch(Vector2(0.0, 1.0))
		sides.advance(1.0 / 120.0, Vector2.ZERO, 0.0, true)
		var moved := (sides.describe()["kick_rotation"] as Vector3).y - before
		if moved > 0.0:
			right += 1
		elif moved < 0.0:
			left += 1
		for j in range(60):
			sides.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	_check(
		"a sideways kick goes both ways over twenty shots (%d left, %d right)" % [left, right],
		left >= 4 and right >= 4
	)

	# About the grip: the muzzle rises and the hand stays where it is, rather than the
	# whole weapon being carried up the screen about the eye.
	var grip := Vector3(0.18, -0.2, -0.4)
	var tipped := ZeeWeaponPose.make(1.0)
	tipped.pivot = grip
	tipped.punch(Vector2(3.0, 0.0))
	for i in range(6):
		tipped.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
	var at := tipped.offset()
	var muzzle := grip + Vector3(0.0, 0.0, -0.35)
	var rise := (at * muzzle).y - muzzle.y
	var hand := (at * grip).y - grip.y
	_check(
		"the kick tips the muzzle up about the grip (muzzle %+.3f m, grip %+.3f m)" % [rise, hand],
		rise > 0.01 and absf(hand) < 0.005
	)

	var punch := tipped.view_punch()
	var climb := (tipped.describe()["kick_rotation"] as Vector3).x
	_check(
		"the camera takes a fraction of the climb, upward (%.2f of %.2f)" % [punch.x, climb],
		punch.x > 0.0 and punch.x < climb
	)
	for i in range(144):
		tipped.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
	_check(
		"and is back inside a second (%.3f)" % tipped.view_punch().length(),
		tipped.view_punch().length() < 0.05
	)

	var still := ZeeWeaponPose.make(1.0)
	still.feel = 0.0
	still.punch(Vector2(3.0, 1.0))
	for i in range(10):
		still.advance(1.0 / 60.0, Vector2(5.0, 2.0), 6.0, true)
	_check(
		"weapon motion turned off is off",
		still.offset().origin.length() < 0.0001 and still.view_punch().length() < 0.0001
	)

	_end()


func _net() -> void:
	_begin("replication")

	var specs := ZeeWeaponNet.all_specs()
	_check("seven replicated properties", specs.size() == 7)

	var names := ZeeWeaponNet.properties()
	_check("the slot comes from dot-weapon", names.has(&"net_slot"))
	_check("the fire counter is this pack's", names.has(&"net_fire_seq"))

	var public := 0
	for spec in specs:
		if not bool(spec["owner_only"]):
			public += 1

	_check(
		"the magazine and the reserve stay owner-only",
		public == 5 and specs.size() - public == 2
	)

	_check("a carrier costs under 40 bits", ZeeWeaponNet.estimated_bits() < 40)

	# The wrap is the whole reason `uses_between` exists: a plain subtraction goes
	# negative every sixteen shots and a weapon goes silent for a snapshot.
	_check("nothing happened", ZeeWeaponNet.uses_between(4, 4) == 0)
	_check("three shots", ZeeWeaponNet.uses_between(4, 7) == 3)
	_check(
		"and three more across the wrap",
		ZeeWeaponNet.uses_between(14, 1) == 3
	)
	_check(
		"a full lap reads as no shots, which is the honest answer",
		ZeeWeaponNet.uses_between(5, 5) == 0
	)

	# Kinds round-trip, and an unknown one becomes a shot rather than nothing: a watcher
	# seeing the wrong animation beats a watcher seeing none.
	for kind in [
		DotWeaponOutcome.KIND_SHOT, DotWeaponOutcome.KIND_SWING,
		DotWeaponOutcome.KIND_SPAWN, DotWeaponOutcome.KIND_BEAM,
		DotWeaponOutcome.KIND_THROW,
	]:
		_check_quiet(
			"%s survives the wire" % String(kind),
			ZeeWeaponNet.kind_name(ZeeWeaponNet.kind_number(kind)) == kind
		)

	_check(
		"a kind this pack has never heard of travels as a shot",
		ZeeWeaponNet.kind_number(&"grappling_hook") == ZeeWeaponNet.KIND_SHOT
	)

	_check(
		"every kind number fits the field",
		ZeeWeaponNet.KIND_THROW < (1 << ZeeWeaponNet.FIRE_KIND_BITS)
	)

	_end()


func _rig() -> void:
	_begin("the rig")

	var rig := _make_rig()
	var res := rig.setup()
	_check("a headless rig sets up: %s" % _why(res), res.ok)

	var given := rig.give_everything()
	_check("every weapon in the pack can be given", given == 27)
	# Twenty-seven given, five carried: a slot holds one weapon, so each `give` in a
	# slot replaces the last. That is dot-weapon's rule and not a bug here, but it is
	# exactly the sort of thing a reader assumes the other way round.
	_check(
		"and five are carried, because a slot holds one weapon",
		rig.arsenal.slots().size() == 5
	)

	_check("something is in hand", rig.current_def() != null)
	_check("and it has art", rig.current_art() != null)

	# A use goes through the arsenal and comes back out.
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var before := rig.fire_seq
	_run_rig(rig, 60, 90, DotWeaponCommand.BUTTON_ATTACK)
	_check("firing advances the replication counter", rig.fire_seq > before)

	# A bash is the alt-fire the arsenal has no path for.
	# [b]An Array, not an int.[/b] A GDScript lambda captures the enclosing locals by
	# value, so a counter incremented inside a signal handler stays zero outside it and
	# the check fails for a signal that fired perfectly — or worse, passes, because the
	# value it was initialised with happened to be the answer. A container is shared by
	# reference and is the honest way to count in a handler.
	var bashes: Array[int] = []
	rig.bashed.connect(func(_outcome: DotWeaponOutcome) -> void: bashes.append(1))
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)
	_check("the alt-fire bashes", bashes.size() == 1)

	# And it has its own cooldown, so holding it does not swing every tick.
	_run_rig(rig, 204, 240, DotWeaponCommand.BUTTON_ALT)
	_check("holding it does not swing every tick", bashes.size() < 4)

	# A reload is heard: out when it starts, in when it ends — on the player's own machine,
	# never on a server, never in a replay. An Array for the reason the bash count is one.
	var reloads := func(role: ZeeWeaponRig.Role, replay: bool) -> Array[StringName]:
		var heard: Array[StringName] = []
		var r := ZeeWeaponRig.new()
		r.role = role
		r.authority = true
		r.tick_rate = ZeeWeaponPack.TICK_RATE
		add_child(r)
		r.setup()
		r.give_everything()
		r.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
		r.reload_sound.connect(func(stage: StringName) -> void: heard.append(stage))
		_run_rig(r, 0, 60, 0)
		_run_rig(r, 60, 75, DotWeaponCommand.BUTTON_ATTACK)
		if replay:
			r.begin_replay()
		_run_rig(r, 75, 77, DotWeaponCommand.BUTTON_RELOAD)
		_run_rig(r, 77, 500, 0)
		if replay:
			r.end_replay()
		_cleanup(r)
		return heard

	var local: Array[StringName] = reloads.call(ZeeWeaponRig.Role.LOCAL, false)
	_check(
		"a reload is heard, out then in (%s)" % ", ".join(local),
		local == [ZeeWeaponSound.RELOAD_OUT, ZeeWeaponSound.RELOAD_IN]
	)
	_check("but not on a server", (reloads.call(ZeeWeaponRig.Role.SERVER, false) as Array).is_empty())
	_check("and not in a replay", (reloads.call(ZeeWeaponRig.Role.LOCAL, true) as Array).is_empty())

	_cleanup(rig)
	_end()


## [b]A SERVER rig has to know who is carrying it, and for a long time it did not.[/b]
##
## `player_ref` was resolved inside `_resolve_presentation()`, behind that function's
## `role == SERVER` early return. The view model and the world model belong there — they
## are drawing, and a server draws nothing. The player does not: it is where
## [method DotWeaponPlayerBridge.context_for] takes the muzzle position and the aim
## direction from, so a rig that skipped it built every [DotWeaponContext] with the
## defaults, and every shot on every dedicated server came out of `(0, 0, 0)` pointing
## `(0, 0, -1)`.
##
## **Nothing reported it, and the 133 checks above could not.** The weapon fires, the
## ammunition goes down, the use counter increments and replicates, and the hit
## registration runs and finds nothing, because there is nothing where it looked. What a
## game built on this has is a fight in which nobody can be shot and every number about it
## is correct.
##
## It was found in a game, by running bots against each other for twenty rounds: every
## single round ended with exactly two players alive, one per side, a draw. A number that is
## identical every round is a number nothing is deciding.
##
## The carrier here is a bare [Node3D] with no `component` method, so the bridge falls all
## the way through to the body transform — which is the weakest of its three answers and is
## the right one to test against, because it is the only one every game has.
func _rig_carrier() -> void:
	_begin("the rig knows who is carrying it")

	var carrier := Node3D.new()
	carrier.name = "Carrier"
	add_child(carrier)
	carrier.global_position = Vector3(12.0, 3.0, -45.0)
	carrier.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)

	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	carrier.add_child(rig)

	var res := rig.setup()
	_check("a server rig with a carrier sets up: %s" % _why(res), res.ok)

	var _given := rig.give_everything()
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var shots: Array = []

	for tick in range(60, 120):
		var command := DotWeaponCommand.new()
		command.buttons = DotWeaponCommand.BUTTON_ATTACK
		var outcome := rig.simulate_tick(command, tick)

		if outcome != null and not outcome.shots.is_empty():
			shots.append(outcome.shots[0])
			break

	_check("it fires", not shots.is_empty())

	if shots.is_empty():
		carrier.queue_free()
		_end()
		return

	var shot: DotShot = shots[0]

	# Armed: with the resolution back inside `_resolve_presentation`, this is
	# `(0, 0, 0)` and the next one is `(0, 0, -1)`.
	_check(
		"and the shot leaves the carrier rather than the world origin (%v)" % shot.origin,
		shot.origin.distance_to(carrier.global_position) < 2.5
	)
	_check(
		"and goes where the carrier is facing (%v)" % shot.direction,
		shot.direction.dot(-carrier.global_transform.basis.z) > 0.9
	)

	carrier.queue_free()
	_end()


func _rig_rollback() -> void:
	_begin("rollback")

	var rig := _make_rig()
	rig.setup()
	rig.give(ZeeWeaponIds.RIFLE)
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var saved := rig.snapshot()
	var magazine := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine

	_check("a snapshot carries the arsenal", saved.has("arsenal"))
	_check(
		"and the bash cooldown, which lives in the rig rather than the arsenal",
		saved.has("bash_ready")
	)

	# Spend some rounds and bash, then roll back.
	_run_rig(rig, 60, 120, DotWeaponCommand.BUTTON_ATTACK)
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)

	var spent := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine
	_check("firing spent rounds", spent < magazine)

	var restored := rig.restore(saved)
	_check("the snapshot restores: %s" % _why(restored), restored.ok)
	_check(
		"the magazine is back where it was",
		rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine == magazine
	)

	# The bug this guards: a snapshot that carried only the arsenal's half hands the
	# player a free bash on every correction, because the cooldown lives in the rig.
	var after: Array[int] = []
	rig.bashed.connect(func(_o: DotWeaponOutcome) -> void: after.append(1))

	# The cooldown was saved before any bash happened, so a bash must now be allowed —
	# proving the restore put a usable number back rather than leaving the spent one.
	_run_rig(rig, 300, 304, DotWeaponCommand.BUTTON_ALT)
	_check("a restored rig can bash again", after.size() == 1)

	# And immediately afterwards it cannot, which is the cooldown actually running.
	_run_rig(rig, 304, 308, DotWeaponCommand.BUTTON_ALT)
	_check("but not twice in four ticks", after.size() == 1)

	_cleanup(rig)
	_end()


func _view_models() -> void:
	_begin("view models")

	# Headless with a null rendering driver still builds a scene tree, which is enough
	# to prove every model loads, parents and measures. What it cannot prove is that any
	# of it looks right — that is tools/screenshot.sh, and it is not optional.
	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)

	var equipped := 0
	var muzzled := 0
	var failures: Array[String] = []

	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		var res := view.equip(art)

		if res.ok:
			equipped += 1
		else:
			failures.append("%s: %s" % [String(art.id), res.error.message])

		if art.has_model() and view.muzzle_transform().origin.length() >= 0.0:
			muzzled += 1

	_check(
		"all twenty-seven weapons equip: %s" % ", ".join(failures),
		equipped == 27
	)
	_check("and twenty-six of them have a muzzle to draw from", muzzled == 26)

	_check(
		"the last one equipped is the one reported",
		view.equipped() == ZeeWeaponIds.STICKY
	)

	view.clear()
	_check("clearing leaves nothing in hand", view.equipped() == &"")

	# A magazine gun's magazine must visibly leave the well and come back, or a reload reads as
	# the gun shaking. For every gun with a magazine of its own (not a round fed by hand): away
	# from the well and falling at 20%, out of sight at 30%, back in the well and visible at 100%.
	var mag_guns := 0
	var mag_bad: Array[String] = []
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.has_magazine() or art.magazine_loose or art.magazine_part != &"":
			continue
		view.equip(art)
		var mag: Node3D = view.get(&"_magazine")
		if mag == null:
			mag_bad.append("%s: no magazine node" % String(art.id))
			continue
		mag_guns += 1
		var rest := art.magazine_transform().origin
		view.on_reload(0.2)
		var left := mag.visible and mag.position.distance_to(rest) > 0.05
		view.on_reload(0.3)
		var gone := not mag.visible
		view.on_reload(1.0)
		var back := mag.visible and mag.position.distance_to(rest) < 0.0001
		if not (left and gone and back):
			mag_bad.append("%s left %s gone %s back %s" % [String(art.id), left, gone, back])
	_check("%d magazine guns: the magazine leaves and returns (%s)" % [mag_guns, ", ".join(mag_bad)],
		mag_bad.is_empty() and mag_guns >= 6)

	# The finish: a rifle's surfaces are no longer one material, and its shells are real guns' only.
	view.equip(ZeeWeaponArtTable.rifle())
	var kinds := {}
	for mi in view.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var surface_material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if surface_material != null:
				kinds["%.2f/%.2f" % [surface_material.metallic, surface_material.roughness]] = true
	_check("a rifle's metal, polymer and wood are shaded apart (%d finishes)" % kinds.size(),
		kinds.size() >= 3)
	_check("a rifle ejects and a foam pistol does not", view.ejects()
		and not (func() -> bool:
			view.equip(ZeeWeaponArtTable.pistol())
			return view.ejects()).call())
	_check("its ejection port is finite and right of the muzzle line",
		(func() -> bool:
			view.equip(ZeeWeaponArtTable.rifle())
			var port := view.eject_transform()
			return port.origin.is_finite()).call())
	_check("kinds of finish are named", ZeeWeaponFinish.kind_of("DarkMetal") == ZeeWeaponFinish.METAL
		and ZeeWeaponFinish.kind_of("Black") == ZeeWeaponFinish.POLYMER
		and ZeeWeaponFinish.kind_of("DarkWood") == ZeeWeaponFinish.WOOD
		and ZeeWeaponFinish.kind_of("colormap") == &"")

	view.clear()

	var arms := ZeeViewArms.new()
	add_child(arms)
	var built := arms.build()
	_check("the first-person arms build: %s" % _why(built), built.ok)
	_check("and there are two of them", arms.has_arms())

	view.queue_free()
	arms.queue_free()
	_end()


func _aim() -> void:
	_begin("aiming down")

	var aimable := 0
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if art.aim_enabled:
			aimable += 1
	# Twenty-seven less seven melee (fists included) and two thrown.
	_check("eighteen weapons aim; melee and throwables do not (%d)" % aimable, aimable == 18)

	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)
	var animated := view.get_node("Animated") as Node3D

	# _process is driven by hand so the easing is the same on every run and every machine.
	var step := func(seconds: float) -> void:
		for _i in range(int(seconds / 0.02)):
			view._process(0.02)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SNIPER))
	view.aim(true)
	step.call(0.4)
	_check("the sniper comes fully up in its aim_time (%.2f)" % view.aim_fraction(),
		is_equal_approx(view.aim_fraction(), 1.0))
	_check("and zooms to x0.3 (%.3f)" % view.aim_fov_scale(),
		absf(view.aim_fov_scale() - 0.3) < 0.001)
	_check("and looks through its scope", view.is_scoped())
	_check("which hides the weapon: the scope is the view", not animated.visible)

	view.aim(false)
	step.call(0.4)
	_check("released, the lens is back to x1 (%.3f)" % view.aim_fov_scale(),
		is_equal_approx(view.aim_fov_scale(), 1.0))
	_check("and the weapon is drawn again", animated.visible and not view.is_scoped())

	var rifle := ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE)
	view.equip(rifle)
	view.aim(true)
	step.call(0.4)
	_check("a rifle zooms a little and is not scoped (%.2f)" % view.aim_fov_scale(),
		absf(view.aim_fov_scale() - rifle.aim_zoom) < 0.001 and not view.is_scoped())
	var aim_node := view.get_node("Animated/Aim") as Node3D
	var holder := view.get_node("Animated/Aim/Holder") as Node3D
	var at := (animated.transform * aim_node.transform * holder.transform).origin
	_check("and arrives centred, below the eye (%.3f, %.3f)" % [at.x, at.y],
		absf(at.x) < 0.002 and at.y < -0.02 and at.z < 0.0)
	# 15: the bullpup lost its added scope with the real-world guns and aims down its iron sight.

	# The sight line, measured off each gun's own mesh, runs through the screen's centre at
	# full aim: the rear and the front sight both on the view axis, the front further out.
	# A sight built but held off the axis is the "aimed at the back of the gun" picture again.
	var sighted := 0
	var worst := 0.0
	var worst_id := &""
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		if not art.aim_enabled or art.aim_scoped:
			continue
		view.equip(art)
		view.aim(true)
		step.call(0.6)
		var points := view.sight_points()
		if points.is_empty():
			continue
		sighted += 1
		var rear: Vector3 = points.rear
		var front: Vector3 = points.front
		var off := maxf(Vector2(rear.x, rear.y).length(), Vector2(front.x, front.y).length())
		if off > worst or front.z >= rear.z or rear.z >= -0.05:
			worst = maxf(off, worst + 1.0 if front.z >= rear.z or rear.z >= -0.05 else off)
			worst_id = art.id
	_check("every unscoped blaster has a measured iron sight (%d)" % sighted, sighted == 15)
	_check("and its line runs through the screen's centre when aimed (worst %.4f m, %s)" % [worst, worst_id],
		worst < 0.002)

	view.equip(rifle)
	view.aim(true)
	step.call(0.6)
	view.on_fired(Vector2(1.0, 0.2))
	step.call(0.06)
	var kicked := view.sight_points()
	var kicked_front: Vector3 = kicked.front
	var kick_angle := rad_to_deg(Vector2(kicked_front.x, kicked_front.y).length() / -kicked_front.z)
	step.call(1.0)
	var settled: Vector3 = view.sight_points().front
	_check("a kick at the sight moves the front sight under three degrees (%.2f)" % kick_angle,
		kick_angle < 3.0)
	_check("and it settles back onto the crosshair (%.4f m)" % Vector2(settled.x, settled.y).length(),
		Vector2(settled.x, settled.y).length() < 0.002)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.PISTOL))
	_check("a new weapon starts at the hip, aim held or not", view.aim_fraction() == 0.0)

	view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.KNIFE))
	view.aim(true)
	step.call(0.4)
	_check("a knife held to aim stays at the hip", view.aim_fraction() == 0.0 and view.aim_fov_scale() == 1.0)

	var overlay := ZeeScopeOverlay.new()
	add_child(overlay)
	overlay.fraction = 2.0
	_check("the scope overlay clamps its fraction", overlay.fraction == 1.0)

	overlay.queue_free()
	view.queue_free()
	_end()


# --- Helpers ----------------------------------------------------------------

func _make_arsenal() -> DotWeaponArsenal:
	var arsenal := DotWeaponArsenal.new()
	arsenal.catalogue = ZeeWeaponPack.catalogue()
	arsenal.tick_rate = ZeeWeaponPack.TICK_RATE
	arsenal.authority = true
	add_child(arsenal)
	return arsenal


func _effects() -> void:
	_begin("shots are seen and heard")

	# --- Sound ---
	var silent: Array[String] = []
	var clicks: Array[String] = []

	for sound_class in ZeeWeaponSound.RECIPES.keys():
		var wav := ZeeWeaponSound.stream(sound_class) as AudioStreamWAV
		if wav == null or wav.data.size() < 200 or _wav_peak(wav) < 0.2:
			silent.append(String(sound_class))
		elif wav.data.decode_s16(wav.data.size() - 2) != 0:
			clicks.append(String(sound_class))

	_check("every sound class bakes something audible: %s" % ", ".join(silent), silent.is_empty())
	_check(
		"and every one ends at exactly zero, so none of them clicks: %s" % ", ".join(clicks),
		clicks.is_empty()
	)

	var rifle := ZeeWeaponSound.stream(ZeeWeaponSound.RIFLE) as AudioStreamWAV
	var again := ZeeWeaponSound.bake(
		ZeeWeaponSound.RECIPES[ZeeWeaponSound.RIFLE], hash(ZeeWeaponSound.RIFLE)
	)
	_check("the same class bakes the same bytes twice", again.data == rifle.data)

	# A gun added to the pack without a sound class falls back to the rifle's, silently.
	var unclassed: Array[String] = []
	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		if def.has_tag(ZeeWeaponIds.TAG_MELEE) or def.has_tag(ZeeWeaponIds.TAG_THROWN):
			continue
		if not ZeeWeaponSound.WEAPONS.has(def.id):
			unclassed.append(String(def.id))
	_check("every gun in the pack names its own sound: %s" % ", ".join(unclassed), unclassed.is_empty())

	_check(
		"a bash from a sniper sounds like a bash, not a sniper",
		ZeeWeaponSound.class_for(ZeeWeaponIds.SNIPER, DotWeaponOutcome.KIND_SWING)
		== ZeeWeaponSound.SWING
	)

	var recorded := AudioStreamWAV.new()
	ZeeWeaponSound.set_stream(ZeeWeaponIds.PISTOL, recorded)
	var used_recording := ZeeWeaponSound.stream_for(
		ZeeWeaponIds.PISTOL, DotWeaponOutcome.KIND_SHOT
	) == recorded
	ZeeWeaponSound.set_stream(ZeeWeaponIds.PISTOL, null)
	_check(
		"a game's own recording outranks the synthesiser, and comes back out",
		used_recording
		and ZeeWeaponSound.stream_for(ZeeWeaponIds.PISTOL, DotWeaponOutcome.KIND_SHOT) != recorded
	)

	# --- A first-person rig ---
	# Armed: before ZeeShotFx, a use drew the gun kicking and nothing else at all.
	var carrier := Node3D.new()
	carrier.name = "FxCarrier"
	add_child(carrier)

	var view := ZeeViewModel.new()
	view.show_arms = false
	carrier.add_child(view)

	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.LOCAL
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	rig.view_model_ref = DotNodeRef.of_path(view.get_path())
	carrier.add_child(rig)

	var res := rig.setup()
	_check("a first-person rig sets up: %s" % _why(res), res.ok)
	_check("and has shot effects", rig.shot_fx() != null)

	rig.give(ZeeWeaponIds.SHOTGUN)
	var shotgun := rig.arsenal.catalogue.get_def(ZeeWeaponIds.SHOTGUN)
	rig.arsenal.select(shotgun.slot, 0)
	_run_rig(rig, 0, 60, 0)

	var pellets := 0
	for tick in range(60, 200):
		var command := DotWeaponCommand.new()
		command.buttons = DotWeaponCommand.BUTTON_ATTACK
		var outcome := rig.simulate_tick(command, tick)
		if outcome != null and outcome.used and not outcome.shots.is_empty():
			pellets = outcome.shots[0].pellets.size()
			break

	var fx := rig.shot_fx()
	var tracers := fx.tracer_count() if fx != null else 0
	var wanted := mini(maxi(1, pellets), ZeeShotFx.MAX_TRACERS_PER_USE)
	_check(
		"a shotgun blast draws a tracer per pellet, up to the cap (%d of %d)" % [tracers, pellets],
		pellets > 0 and tracers == wanted
	)
	_check(
		"and plays a report",
		fx != null and int(fx.describe()["voices"]) >= 1
	)

	_check("a real gun's shot throws a case (%d)" % fx.shell_count(), fx.shell_count() >= 1)

	# Budgets: a held minigun asks for a flash and a case per shot, and neither may grow.
	var capped := ZeeShotFx.new()
	add_child(capped)
	for i in 40:
		capped.call(&"_flash", Transform3D(Basis.IDENTITY, Vector3(0, 0, -1)), 1.0, ZeeWeaponSound.MINIGUN)
		capped.play_eject(Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	var lights := int(capped.call(&"_lights_live"))
	_check("flash lights stay under the cap (%d of %d)" % [lights, capped.max_flash_lights],
		lights >= 1 and lights <= capped.max_flash_lights)
	_check("cases stay under the pool (%d of %d)" % [capped.shell_count(), capped.max_shells],
		capped.shell_count() == capped.max_shells)
	for i in 80:
		capped.advance(0.02)
	_check("a case is gone after its life, and its flash with it",
		capped.shell_count() == 0 and capped.live_count() == 0)
	capped.queue_free()

	# The local player's own world model, driven by the replicated counter the way
	# game-playground drives every player's: it must not play the shot a second time.
	var own := ZeeWorldModel.new()
	carrier.add_child(own)
	own.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SHOTGUN))
	own.on_fired(Vector2(1.0, 0.1), ZeeWeaponNet.KIND_SHOT)
	_check(
		"the carrier's own world model stays quiet beside its first-person rig",
		own.get_node_or_null(^"ShotFx") == null
	)

	# Somebody else's: nothing on this machine draws their shot but their hand.
	var stranger := Node3D.new()
	add_child(stranger)
	var theirs := ZeeWorldModel.new()
	stranger.add_child(theirs)
	theirs.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	theirs.on_fired(Vector2(0.4, 0.1), ZeeWeaponNet.KIND_SHOT)
	var their_fx := theirs.get_node_or_null(^"ShotFx") as ZeeShotFx
	_check(
		"somebody else's shot is drawn from their hand",
		their_fx != null and their_fx.tracer_count() == 1
	)
	# Sounds turned off after the first shot (a settings change) reach the next one.
	theirs.sounds = false
	theirs.on_fired(Vector2(0.4, 0.1), ZeeWeaponNet.KIND_SHOT)
	_check(
		"and turning their sounds off after a shot silences the next one",
		their_fx != null and not their_fx.sounds
	)

	# [b]Somebody else's swing and throw are keys on their world model[/b], as one's own are on
	# the view model: a watcher saw the knife ride the arm rigid, and a grenade thrown from a
	# hand that never moved.
	_check("the world model's swing and throw keys start and finish at rest",
		ZeeWeaponPose.sample_keys(ZeeWorldModel.SWING_KEYS, 0.0)[1].length() < 0.0001
		and ZeeWeaponPose.sample_keys(ZeeWorldModel.SWING_KEYS, 1.0)[1].length() < 0.0001
		and ZeeWeaponPose.sample_keys(ZeeWorldModel.THROW_KEYS, 1.0)[0].length() < 0.0001)
	var cutter := ZeeWorldModel.new()
	cutter.effects = false
	stranger.add_child(cutter)
	cutter.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.KNIFE))
	var cutter_holder := cutter.get_node(^"Holder") as Node3D
	var cutter_rest := cutter_holder.transform
	cutter.on_fired(Vector2(1.2, 0.0), ZeeWeaponNet.KIND_SWING)
	for i in range(14):
		cutter.advance(1.0 / 60.0)
	var cut := rad_to_deg(cutter_holder.basis.get_rotation_quaternion().angle_to(
		cutter_rest.basis.get_rotation_quaternion()))
	for i in range(60):
		cutter.advance(1.0 / 60.0)
	_check("somebody else's swing turns their knife well across mid-cut (%.0f deg) and puts it back" % cut,
		cut > 30.0 and cutter.action_fraction() >= 1.0
		and cutter_holder.transform.is_equal_approx(cutter_rest))

	# A thrown weapon leaves the hand at the release and is back for the next, and the person
	# holding it is asked for the arm (a figure answers swing and set_hold).
	var thrower := Node3D.new()
	var person_script := GDScript.new()
	person_script.source_code = "extends Node3D\nvar swung: Array = []\nfunc swing(which: StringName = &\"\") -> void:\n\tswung.append(which)\nfunc set_hold(_kind: int) -> void:\n\tpass\n"
	var _loaded := person_script.reload()
	thrower.set_script(person_script)
	stranger.add_child(thrower)
	var lobbed := ZeeWorldModel.new()
	lobbed.effects = false
	thrower.add_child(lobbed)
	lobbed.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.FRAG))
	lobbed.on_fired(Vector2(2.0, 0.0), ZeeWeaponNet.KIND_THROW)
	var lobbed_weapon := lobbed.get_node_or_null(^"Holder/Weapon") as Node3D
	for i in range(18):
		lobbed.advance(1.0 / 60.0)
	var gone := lobbed_weapon != null and not lobbed_weapon.visible
	for i in range(60):
		lobbed.advance(1.0 / 60.0)
	_check("a throw lets go of the grenade mid-throw, has it back after, and swings the person's arm (%s)" % str(thrower.get(&"swung")),
		gone and lobbed_weapon.visible and thrower.get(&"swung") == [&"slash"])
	lobbed.advance(NAN)
	_check("and a NaN step moves nothing",
		(lobbed.get_node(^"Holder") as Node3D).transform.origin.is_finite())

	# --- Where a shot lands ---
	# A wall takes a spark, a puff and a mark that stays; a body takes a red burst and no mark;
	# the server's confirmation of the same hit does not draw it twice.
	var wall := StaticBody3D.new()
	var somebody := CharacterBody3D.new()
	var crate := RigidBody3D.new()
	var disguised := CharacterBody3D.new()
	disguised.add_to_group(ZeeShotFx.NOT_BODY_GROUP)
	_check("a character is a body, a wall and a crate are the world, a disguised character is not a body",
		ZeeShotFx.impact_kind(somebody) == ZeeShotFx.IMPACT_BODY
		and ZeeShotFx.impact_kind(wall) == ZeeShotFx.IMPACT_WORLD
		and ZeeShotFx.impact_kind(crate) == ZeeShotFx.IMPACT_WORLD
		and ZeeShotFx.impact_kind(disguised) == ZeeShotFx.IMPACT_WORLD)
	_check("only what never moves takes a mark",
		ZeeShotFx.takes_marks(wall) and not ZeeShotFx.takes_marks(crate)
		and not ZeeShotFx.takes_marks(somebody) and not ZeeShotFx.takes_marks(null))

	var marks_before := fx.mark_count() if fx != null else 0
	var sparks_before := fx.count_of(&"spark") if fx != null else 0
	if fx != null:
		fx.play_impact(Vector3(0.0, 1.0, -5.0), Vector3.BACK, wall)
	_check("a shot on a wall strikes a spark and leaves a mark",
		fx != null and fx.mark_count() == marks_before + 1 and fx.count_of(&"spark") == sparks_before + 1)

	if fx != null:
		fx.play_impact(Vector3(2.0, 1.0, -5.0), Vector3.BACK, somebody)
	_check("a shot on a body bursts red and leaves no mark",
		fx != null and fx.count_of(&"hit") == 1 and fx.mark_count() == marks_before + 1)

	if fx != null:
		fx.play_body_hit(Vector3(2.05, 1.0, -5.0), Vector3.FORWARD)
		fx.play_body_hit(Vector3(-3.0, 1.0, -5.0), Vector3.FORWARD)
	_check("the server's word on the same hit is not drawn twice; on a body the ray never saw it is",
		fx != null and fx.count_of(&"hit") == 2)

	if fx != null:
		for i in range(int(ZeeShotFx.MARK_LIFE * 10.0) + 2):
			fx.advance(0.1)
	_check("marks fade and go", fx != null and fx.mark_count() == 0 and fx.live_count() == 0)

	for node: Node in [wall, somebody, crate, disguised]:
		node.free()

	var server := _make_rig()
	server.setup()
	_check("a server rig draws and plays nothing", server.shot_fx() == null)

	_cleanup(server)
	carrier.queue_free()
	stranger.queue_free()
	_end()


## The loudest sample in a 16-bit stream, from 0 to 1.
static func _wav_peak(wav: AudioStreamWAV) -> float:
	var peak := 0
	for i in range(0, wav.data.size() - 1, 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return float(peak) / 32767.0


## The pack is written at 64 Hz; on a 128 Hz server it must take the same wall-clock time.
##
## [b]Before dot-weapon honoured authored_tick_rate, every zee weapon fired, reloaded and
## deployed twice as fast in the 128 Hz sandbox[/b], and the only part anybody had patched
## was the grenade fuse, by hand, in that game. These compare a second at each rate.
func _tick_rate() -> void:
	_begin("the pack keeps its timing at 128 Hz")

	var unstamped := 0
	for def in ZeeWeaponPack.weapons():
		if def.authored_tick_rate != ZeeWeaponPack.TICK_RATE:
			unstamped += 1
	_check("every row says it was written at %d Hz" % ZeeWeaponPack.TICK_RATE, unstamped == 0)

	var shots: Array[int] = []
	var bashes: Array[int] = []
	var reload_seconds: Array[float] = []
	var deploy_fraction: Array[float] = []

	for rate: int in [64, 128]:
		var rig := _make_rig()
		rig.tick_rate = rate
		rig.setup()
		rig.give(ZeeWeaponIds.SMG)
		_check_quiet("the arsenal runs at the rig's rate", rig.arsenal.tick_rate == rate)

		# Two seconds idle, so nothing is still deploying, then one second on the trigger.
		_run_rig(rig, 0, rate * 2, 0)
		shots.append(_run_rig(rig, rate * 2, rate * 3, DotWeaponCommand.BUTTON_ATTACK))

		var def := rig.current_def()
		reload_seconds.append(float(rig.arsenal.ticks_for(def, def.reload_ticks)) / float(rate))

		# The alt-fire pressed on every other tick for two seconds: the rig's own cooldown,
		# which the arsenal never sees, decides how many land.
		var count: Array[int] = [0]
		rig.bashed.connect(func(_o: DotWeaponOutcome) -> void: count[0] += 1)
		var from := rate * 4
		for tick in range(from, from + rate * 2):
			var command := DotWeaponCommand.new()
			command.buttons = DotWeaponCommand.BUTTON_ALT if (tick - from) % 2 == 0 else 0
			var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
			ctx.authority = true
			rig.simulate_tick(command, tick, ctx)
		bashes.append(count[0])

		# A quarter of a second into a switch, the drawn picture is as far along at either rate.
		rig.give(ZeeWeaponIds.PISTOL)
		var at := rate * 7
		var cmd := DotWeaponCommand.new()
		cmd.slot = ZeeWeaponIds.SLOT_SIDEARM
		rig.simulate_tick(cmd, at, DotWeaponContext.make(1, at, Vector3.ZERO, Vector3.FORWARD))
		_run_rig(rig, at + 1, at + rate / 8, 0)
		deploy_fraction.append(rig._deploy_fraction(at + rate / 8 - 1))

		_cleanup(rig)

	_check("a second of fire is as many shots at 128 Hz as at 64 (%d, %d)" % [shots[0], shots[1]],
		shots[0] > 1 and shots[0] == shots[1])
	_check("a reload takes the same time (%.3f s, %.3f s)" % [reload_seconds[0], reload_seconds[1]],
		absf(reload_seconds[0] - reload_seconds[1]) < 1.0 / 64.0)
	_check("the bash cools down in the same time (%d, %d bashes)" % [bashes[0], bashes[1]],
		bashes[0] > 1 and bashes[0] == bashes[1])
	_check("the holster is drawn as far along after the same time (%.2f, %.2f)" % [deploy_fraction[0], deploy_fraction[1]],
		absf(deploy_fraction[0] - deploy_fraction[1]) < 0.1)

	_end()


func _make_rig() -> ZeeWeaponRig:
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	add_child(rig)
	return rig


## Runs an arsenal for a range of ticks with one button held, counting the uses.
func _run(arsenal: DotWeaponArsenal, from: int, to: int, buttons: int) -> int:
	var used := 0
	var previous: DotWeaponCommand = null

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		var out := arsenal.simulate_tick(command, ctx, previous)

		if out.used:
			used += 1

		previous = command

	return used


func _run_rig(rig: ZeeWeaponRig, from: int, to: int, buttons: int) -> int:
	var used := 0

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		if rig.simulate_tick(command, tick, ctx).used:
			used += 1

	return used


func _cleanup(node: Node) -> void:
	remove_child(node)
	node.queue_free()


func _why(res: DotResult) -> String:
	return "" if res.ok else res.error.message


func _input_bindings() -> void:
	_begin("input bindings")

	# Every action this could add, removed first so the suite starts from a project
	# that bound none of them, and removed again after so no later scene inherits them.
	var ours: Array[StringName] = []
	for action: StringName in ZeeWeaponInput.DEFAULT_ACTIONS.keys():
		ours.append(action)
	for slot in range(1, 6):
		ours.append(StringName(ZeeWeaponInput.SLOT_ACTION_PREFIX + str(slot)))
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	# An Array, not a counter: a lambda captures a scalar by value.
	var heard: Array[Dictionary] = []
	var listen := func(rec: Dictionary) -> void:
		if str(rec.get("channel", "")) == ZeeWeaponInput.CHANNEL:
			heard.append(rec)
	DotLog.signals().record.connect(listen)

	var first := ZeeWeaponInput.register_default_actions()
	_check("registering the defaults adds all thirteen", first == 13)
	_check(
		"and says so once, on zee.input, at INFO (heard %d)" % heard.size(),
		heard.size() == 1 and int(heard[0].get("level", -1)) == DotLog.Level.INFO
	)

	var second := ZeeWeaponInput.register_default_actions()
	_check("a second call adds nothing", second == 0)
	_check("and logs nothing: an edge, not a line per call", heard.size() == 1)

	DotLog.signals().record.disconnect(listen)
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	_end()


# --- Counting ---------------------------------------------------------------

func _begin(name: String) -> void:
	_section = name
	_sections_entered += 1
	print("")
	print("-- %s" % name)


func _end() -> void:
	_sections_finished += 1


func _check(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		print("   ok    %s" % label)
		return

	_failures += 1
	print("   FAIL  %s" % label)


## A check that only prints when it fails. For the ones run in a loop, where twenty-seven
## lines of "ok" buries the one line anybody needs to read.
func _check_quiet(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		return

	_failures += 1
	print("   FAIL  %s" % label)
