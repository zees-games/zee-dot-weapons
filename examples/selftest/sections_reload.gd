extends "res://examples/selftest/sections_view.gd"

## Selftest sections: each weapon's reload phases (view/zee_reload_sequence.gd), measured on a built view model.

const ReloadSequence := preload("res://addons/zee_weapons/view/zee_reload_sequence.gd")

var _fore_seen: Array = []
var _grip_seen: Array = []


func _reload_sequences() -> void:
	_begin("reload sequences")
	var view := ZeeViewModel.new()
	add_child(view)
	view.hands_reached.connect(_on_hands)
	var table := ZeeWeaponPack.table()
	var styled := 0
	var guns := 0
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		var def: DotWeaponDef = table.get(art.id)
		if def == null or not def.uses_magazine() or not art.has_model():
			continue
		guns += 1
		var style := ReloadSequence.style_of(art)
		_check_quiet("%s has a reload style of its own (%s)" % [art.id, style], style != &"generic")
		if style == &"generic":
			continue
		styled += 1
		var _e := view.equip(art)
		var left := mini(1, def.magazine - 1)
		var run := _play(view, left, def.magazine)
		_check_quiet("%s: the support hand leaves the fore-end (%.2f m)" % [art.id, run.reach], run.reach > 0.08)
		_check_quiet("%s: something is carried in sight (%d parts at most)" % [art.id, run.parts], run.parts >= 1)
		_check_quiet("%s: the hands are back on the gun at the end" % art.id, run.back)
	_check("every magazine weapon has its own reload style (%d of %d)" % [styled, guns], styled == guns and guns > 0)

	# Count-aware: a launcher with 2 of 6 left throws 4 cases and loads 4 rounds; empty, 6 and 6.
	var gl := _art_with(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE), {"style": "launcher"})
	var _g := view.equip(gl)
	var part_run := _play(view, 2, 6)
	_check("launcher, 2 of 6 left: 4 cases thrown, 4 rounds loaded (%d, %d)" % [part_run.cases, part_run.rounds], part_run.cases == 4 and part_run.rounds == 4)
	var empty_run := _play(view, 0, 6)
	_check("launcher, empty: 6 cases thrown, 6 rounds loaded (%d, %d)" % [empty_run.cases, empty_run.rounds], empty_run.cases == 6 and empty_run.rounds == 6)
	var all_out := _art_with(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE), {"style": "launcher", "eject": "all"})
	_g = view.equip(all_out)
	var dumped := _play(view, 2, 6)
	_check("launcher, eject all: the 2 live rounds come out too (%d cases, %d loaded)" % [dumped.cases, dumped.rounds], dumped.cases == 6 and dumped.rounds == 6)

	# A revolver throws only what was fired; a tube loads one shell per round missing and pumps only when empty.
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.REVOLVER))
	var rev := _play(view, 2, 6)
	_check("revolver, 2 of 6 left: 4 cases fall out, a speedloader goes in (%d, %s)" % [rev.cases, rev.names], rev.cases == 4 and "fetch" in rev.names)
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SHOTGUN))
	var top := _play(view, 3, 6, 0.2)
	var dry := _play(view, 0, 6, 0.2)
	_check("shotgun: 3 shells for 3 missing, no pump topping up (%d, %s)" % [top.rounds, "pump" in top.names], top.rounds == 3 and not "pump" in top.names)
	_check("shotgun empty: 6 shells and a pump (%d, %s)" % [dry.rounds, "pump" in dry.names], dry.rounds == 6 and "pump" in dry.names)

	# Tactical and empty differ: the rifle's charging handle is worked only from empty, by the firing hand.
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	var tac := _play(view, 10, 30)
	var dead := _play(view, 0, 30)
	_check("rifle tactical: no charging handle, the old magazine kept (%s)" % [tac.names], not "charge" in tac.names and tac.grip_reach < 0.01)
	_check("rifle empty: the firing hand works the charging handle (%.2f m)" % dead.grip_reach, "charge" in dead.names and dead.grip_reach > 0.03)
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.SNIPER))
	var bolt := _play(view, 0, 5)
	_check("bolt action: bolt back by the firing hand, a stripper clip, one case out (%.2f m, %d)" % [bolt.grip_reach, bolt.cases], bolt.grip_reach > 0.05 and "clip_0" in bolt.names and bolt.cases == 1)
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.MINIGUN))
	var belt := _play(view, 20, 100)
	_check("belt-fed: cover open, box out, belt laid, cover shut (%s)" % [belt.names], "cover_open" in belt.names and "belt_lay" in belt.names and "cover_close" in belt.names)

	# Interrupted: the reload ending at any point puts every part away and the hand back.
	_g = view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	view.on_reload_begin(0, 30)
	view.on_reload(0.4)
	var mid := view.reload_parts_shown()
	view.on_reload(0.0)
	_check("a cancelled reload ends the sequence and hides its parts (%d shown mid-way, %d after)" % [mid, view.reload_parts_shown()],
		mid >= 1 and view.reload_sequence() == null and view.reload_parts_shown() == 0)

	# Data: a profile's `art: reload:` row picks the style; the cvar turns every gun back to the generic reload.
	var over := ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE).with_overrides({"reload": {"style": "belt"}})
	_check("a profile row sets the style (%s)" % ReloadSequence.style_of(over), ReloadSequence.style_of(over) == &"belt")
	view.feel_rules.reload_detail = 0.0
	view.on_reload_begin(0, 30)
	_check("cl_vm_reload_detail 0 plays the generic reload", view.reload_sequence() == null)
	view.feel_rules.reload_detail = 1.0

	# Timing is the rig's: keys run 0 to 1 in order whatever the weights, so server and client agree on its length.
	var seq := ReloadSequence.new()
	seq.compose(gl, ReloadSequence.anchors_for(Vector3(0.05, -0.1, -0.3), Vector3(0.05, -0.08, -0.5), Vector3(0, 0, -0.8), null, {}, Transform3D.IDENTITY), 6, 1)
	var ordered := true
	for i in range(1, seq.gun_keys.size()):
		ordered = ordered and float(seq.gun_keys[i][0]) > float(seq.gun_keys[i - 1][0])
	_check("a sequence's keys start at 0, end at 1 and only go forward", ordered and float(seq.gun_keys[0][0]) == 0.0 and float(seq.gun_keys.back()[0]) == 1.0)
	view.queue_free()
	_end()


func _art_with(art: ZeeWeaponArt, reload: Dictionary) -> ZeeWeaponArt:
	var out := art.duplicate() as ZeeWeaponArt
	out.reload = reload
	return out


## Plays one reload over 120 steps and measures it: hand travel, parts drawn, cases thrown and rounds carried.
func _play(view: ZeeViewModel, left: int, magazine: int, start_share: float = 0.0) -> Dictionary:
	view.on_reload_begin(left, magazine, start_share)
	var seq := view.reload_sequence()
	var out := {"reach": 0.0, "grip_reach": 0.0, "parts": 0, "cases": 0, "rounds": 0, "back": false, "names": []}
	if seq == null:
		return out
	for p: Dictionary in seq.phases:
		(out.names as Array).append(String(p.name))
	var cases := {}
	var rounds := {}
	_fore_seen.clear()
	_grip_seen.clear()
	view.on_reload(0.0001)
	view.advance(0.0)
	var fore0: Vector3 = _fore_seen.back() if not _fore_seen.is_empty() else Vector3.ZERO
	var grip0: Vector3 = _grip_seen.back() if not _grip_seen.is_empty() else Vector3.ZERO
	for i in range(1, 120):
		var f := float(i) / 120.0
		view.on_reload(f)
		view.advance(0.0)
		out.parts = maxi(out.parts, view.reload_parts_shown())
		if not _fore_seen.is_empty():
			out.reach = maxf(out.reach, (_fore_seen.back() as Vector3).distance_to(fore0))
			out.grip_reach = maxf(out.grip_reach, (_grip_seen.back() as Vector3).distance_to(grip0))
		for e: Dictionary in seq.props_at(f):
			if not e.shown:
				continue
			if e.part in [&"casing", &"grenade_case"] and seq.props[e.index].segments[0][2] == "eject":
				cases[e.index] = true
			elif e.part in [&"grenade", &"shell", &"round"]:
				rounds[e.index] = true
	out.cases = cases.size()
	out.rounds = rounds.size() if seq.style != &"revolver" else seq.loaded
	view.on_reload(0.9999)
	view.advance(0.0)
	out.back = not _fore_seen.is_empty() and (_fore_seen.back() as Vector3).distance_to(fore0) < 0.03
	view.on_reload(0.0)
	return out


func _on_hands(_anchor: Node3D, grip: Vector3, fore: Vector3, _pose_name: StringName) -> void:
	_fore_seen.append(fore)
	_grip_seen.append(grip)
