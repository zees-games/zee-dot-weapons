extends "res://examples/selftest/sections_rig.gd"

## Selftest sections: input bindings, profiles and the stock sounds, split out of sections_rig.gd for file size.


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
	_check("registering the defaults adds all fourteen", first == 14)
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


func _profiles() -> void:
	_begin("weapon profiles overlay only the keys a file sets")
	var saved_roots := ZeeWeaponPack.base_roots
	var vanilla := _by_id(ZeeWeaponPack.weapons({}, false))
	ZeeWeaponPack.base_roots = PackedStringArray(["res://cfg"])
	var set := ZeeWeaponPack.profile_set()
	_check("one shipped profile per weapon", set.list_ids().size() == vanilla.size() and vanilla.size() == 27)
	set.clear_cache()
	var stale := PackedStringArray()
	for id in vanilla:
		var path := ZeeWeaponProfiles.profile_path("zee_weapons", id)
		if FileAccess.get_file_as_string(path) != ZeeWeaponProfiles.to_yaml(vanilla[id], "Zee Weapons"):
			stale.append(id)
	_check("shipped profiles are what the exporter writes (run tools/export-defs.sh): %s" % ", ".join(stale), stale.is_empty())
	var tuned := _by_id(ZeeWeaponPack.weapons())
	var drift := PackedStringArray()
	for id in vanilla:
		if str(ZeeWeaponProfiles.flat_of(tuned[id])) != str(ZeeWeaponProfiles.flat_of(vanilla[id])):
			drift.append(id)
	_check("loading every shipped profile changes no number: %s" % ", ".join(drift), drift.is_empty())
	_check("no shipped profile fails", ZeeWeaponPack.errors.is_empty())

	var tmp := "user://zee_profiles_cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp))
	_profile_file(tmp, "rifle.yml", "magazine: 12\nname: \"Test Rifle\"\nextra:\n  tuning:\n    damage: 99\n    nonsense: 1\n  params:\n    bash_damage: 7\n    fresh: 3\n")
	_profile_file(tmp, "pistol.yml", "magazine: -5\n")
	_profile_file(tmp, "ghost.yml", "magazine: 3\n")
	ZeeWeaponPack.base_roots = PackedStringArray([tmp])
	var set2 := ZeeWeaponPack.profile_set()
	_check("a file's keys are file keys, a schema default is not", set2.load_profile("rifle").value.file_keys == PackedStringArray(["extra.params.bash_damage", "extra.params.fresh", "extra.tuning.damage", "extra.tuning.nonsense", "magazine", "name"]))
	set2.clear_cache()
	# The bad pistol file logs ERROR on purpose: capture it and keep it off the engine's stderr.
	var seen: Array = []
	var catcher := func(rec: Dictionary) -> void: seen.append(rec)
	var old_mirror := DotLog.mirror_min_level
	DotLog.mirror_min_level = DotLog.Level.FATAL
	DotLog.add_sink(catcher)
	var t2 := _by_id(ZeeWeaponPack.weapons())
	DotLog.remove_sink(catcher)
	DotLog.mirror_min_level = old_mirror
	var bad := seen.filter(func(rec: Dictionary) -> bool: return rec["level"] == DotLog.Level.ERROR and str(rec["fields"].get("id")) == "pistol" and "magazine" in str(rec["fields"].get("why")))
	_check("the bad profile logged ERRORs naming the pistol and its magazine", bad.size() == 2)
	var r: DotWeaponDef = t2["rifle"]
	var rv: DotWeaponDef = vanilla["rifle"]
	_check("a common key, tuning and params key land", r.magazine == 12 and r.display_name == "Test Rifle" and is_equal_approx((r.tuning as DotWeaponBallistics).damage, 99.0) and is_equal_approx(float(r.params[&"bash_damage"]), 7.0))
	_check("a new params key is taken as written", int(r.params[&"fresh"]) == 3)
	_check("every key the file does not set keeps the builder's value", r.reload_ticks == rv.reload_ticks and r.deploy_ticks == rv.deploy_ticks and is_equal_approx((r.tuning as DotWeaponBallistics).spread, 0.45) and is_equal_approx((r.tuning as DotWeaponBallistics).bloom_recovery, 8.5 / 64.0))
	_check("other weapons are untouched", str(ZeeWeaponProfiles.flat_of(t2["smg"])) == str(ZeeWeaponProfiles.flat_of(vanilla["smg"])))
	_check("an out-of-range profile is reported and its weapon keeps the builder's numbers", ZeeWeaponPack.errors.size() == 1 and t2["pistol"].magazine == vanilla["pistol"].magazine)
	_check("the exporter's list ignores the profiles", ZeeDefExport.own_weapons()[13].magazine == rv.magazine)

	var pack_root := "user://zee_profiles_pack"
	_profile_file(pack_root, "smg.yml", "extra:\n  tuning:\n    damage: 55\n")
	ZeeWeaponPack.pack_cfg_root = pack_root
	ZeeWeaponPack.base_roots = PackedStringArray([tmp.path_join("none")])
	_check("a delivered pack's cfg root is read", is_equal_approx((_by_id(ZeeWeaponPack.weapons())["smg"].tuning as DotWeaponBallistics).damage, 55.0))
	_profile_file(tmp.path_join("over"), "smg.yml", "extra:\n  tuning:\n    damage: 66\n")
	ZeeWeaponPack.base_roots = PackedStringArray([tmp.path_join("over")])
	_check("and is the weakest root", is_equal_approx((_by_id(ZeeWeaponPack.weapons())["smg"].tuning as DotWeaponBallistics).damage, 66.0))
	ZeeWeaponPack.pack_cfg_root = ""

	ZeeWeaponPack.base_roots = PackedStringArray(["res://cfg"])
	var up := ZeeWeaponPack.upgraded(&"rifle", ["extended_mag"])
	_check("an upgrade is applied to a copy", up.ok and up.value["def"].magazine == 40 and up.value["def"].reload_ticks == int(round(141.0 * 1.15)) and up.value["cost"] == 100 and vanilla["rifle"].magazine == 30)
	var both := ZeeWeaponPack.upgraded(&"rifle", ["extended_mag", "hot_loads"])
	_check("upgrades stack and reach the tuning", both.ok and is_equal_approx((both.value["def"].tuning as DotWeaponBallistics).damage, 23.0 * 1.2) and both.value["cost"] == 250)
	_check("an upgrade whose requirement is missing is refused", not ZeeWeaponPack.upgraded(&"rifle", ["hot_loads"]).ok)
	var choke := ZeeWeaponPack.upgraded(&"shotgun", ["choke"])
	_check("a set upgrade changes an int field", choke.ok and (choke.value["def"].tuning as DotWeaponBallistics).pellets == 8)
	_check("an unknown weapon is refused", not ZeeWeaponPack.upgraded(&"ghost", []).ok)

	var out := "user://zee_profiles_export"
	var wrote := ZeeDefExport.write_cfg(out, "zee_weapons", "Zee Weapons", ZeeDefExport.own_weapons())
	_check("the export writes every profile and the upgrade folders", wrote.ok and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/rifle/rifle.yml")) and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/rifle/upgrades/hot_loads.yml")) and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/pistol.yml")))
	ZeeWeaponPack.base_roots = saved_roots
	_end()


func _stock_path(stream: AudioStream, sound: String) -> bool:
	return stream is AudioStreamOggVorbis and stream.resource_path.begins_with(
		"%s%s_" % [DotWeaponSound.DIR, sound]
	)


func _stock_sounds() -> void:
	_begin("the stock recordings are what plays")

	_check("dot-audio's weapon stock is linked", DotWeaponSound.count(&"light_fire") == 5)

	var wrong := PackedStringArray()
	for sound_class: StringName in DotWeaponSound.FIRE:
		var stream := ZeeWeaponSound.stream(sound_class)
		if not _stock_path(stream, String(DotWeaponSound.FIRE[sound_class])):
			wrong.append(String(sound_class))
	_check("every class plays a recording, not the bake (%s)" % ", ".join(wrong), wrong.is_empty())

	var bake_ids := PackedStringArray()
	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		for kind: StringName in [DotWeaponOutcome.KIND_SHOT, DotWeaponOutcome.KIND_SWING]:
			if not ZeeWeaponSound.stream_for(def.id, kind) is AudioStreamOggVorbis:
				bake_ids.append("%s/%s" % [def.id, kind])
	_check("every weapon's report is a recording (%s)" % ", ".join(bake_ids), bake_ids.is_empty())

	_check("a rifle heard from afar is the _far recording",
		_stock_path(ZeeWeaponSound.far_for(ZeeWeaponIds.RIFLE, DotWeaponOutcome.KIND_SHOT), "rifle_far"))
	_check("a melee class has no far recording", ZeeWeaponSound.far_for(ZeeWeaponIds.RIFLE, DotWeaponOutcome.KIND_SWING) == null)
	_check("a suppressed weapon plays its own report, not the pistol's",
		_stock_path(ZeeWeaponSound.stream(ZeeWeaponSound.SUPPRESSED), "suppressed_fire"))

	var fx := ZeeShotFx.new()
	add_child(fx)
	var heard: Array[AudioStream] = []
	fx.heard.connect(func(stream: AudioStream) -> void: heard.append(stream))
	fx.play_dry(Vector3.ZERO)
	fx.play_dry(Vector3.ZERO)
	_check("a dry fire clicks once, throttled", heard.size() == 1 and _stock_path(heard[0], "dry"))
	fx.play_equip(Vector3.ZERO)
	_check("an equip plays the stock equip", _stock_path(heard[-1], "equip"))
	fx.play_reload_shell(Vector3.ZERO)
	_check("a shell plays reload_shell", _stock_path(heard[-1], "reload_shell"))
	fx.play_reload(ZeeWeaponSound.RELOAD_OUT, Vector3.ZERO)
	_check("a magazine out plays reload_out", _stock_path(heard[-1], "reload_out"))
	fx.play_eject(Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	fx.call(&"_play_casing", Vector3.ZERO)
	_check("a case lands with the stock casing", _stock_path(heard[-1], "casing"))
	var before := heard.size()
	fx.play_use(_fake_shot(), Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	_check("a shot plays a stock report", heard.size() == before + 1 and _stock_path(heard[-1], "rifle_fire"))
	await get_tree().create_timer(DotWeaponSound.TAIL_DELAY + 0.1).timeout
	_check("outdoors a shot has no tail", heard.size() == before + 1)
	fx.roof = _FakeRoof.new()
	fx.play_use(_fake_shot(), Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	_check("indoors the report is alone until the delay", heard.size() == before + 2)
	await get_tree().create_timer(DotWeaponSound.TAIL_DELAY + 0.1).timeout
	_check("indoors the _far tail follows the report", heard.size() == before + 3 and _stock_path(heard[-1], "rifle_far"))
	fx.roof = null
	fx.sounds = false
	fx.play_equip(Vector3.ZERO)
	_check("and with sounds off nothing plays", heard.size() == before + 3)
	fx.queue_free()

	_stock_rig_sounds()
	_end()


func _stock_rig_sounds() -> void:
	# The rig wires the arsenal's dry signal and a tube magazine's shells to the effects.
	var carrier := Node3D.new()
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
	rig.setup()
	var rig_fx := rig.shot_fx()
	var rig_heard: Array[AudioStream] = []
	rig_fx.heard.connect(func(stream: AudioStream) -> void: rig_heard.append(stream))
	rig.arsenal.dry_used.emit(0)
	_check("the rig plays the dry click when the arsenal reports one",
		rig_heard.size() == 1 and _stock_path(rig_heard[0], "dry"))

	rig.give(ZeeWeaponIds.SHOTGUN)
	var gun := rig.arsenal.catalogue.get_def(ZeeWeaponIds.SHOTGUN)
	rig.arsenal.select(gun.slot, 0)
	_run_rig(rig, 0, 60, 0)
	rig_heard.clear()
	_run_rig(rig, 60, 120, DotWeaponCommand.BUTTON_ATTACK)
	rig.arsenal.current().magazine = 3
	_run_rig(rig, 120, 124, DotWeaponCommand.BUTTON_RELOAD)
	rig_heard.clear()
	_run_rig(rig, 124, 700, 0)
	var shells := 0
	var outs := 0
	for stream in rig_heard:
		if _stock_path(stream, "reload_shell"):
			shells += 1
		if _stock_path(stream, "reload_out"):
			outs += 1
	_check("a shotgun reload plays a shell per round, not a magazine out (%d shells)" % shells, shells >= 2 and outs == 0)
	_cleanup(carrier)


func _fake_shot() -> DotWeaponOutcome:
	var outcome := DotWeaponOutcome.new()
	outcome.used = true
	outcome.kind = DotWeaponOutcome.KIND_SHOT
	return outcome
