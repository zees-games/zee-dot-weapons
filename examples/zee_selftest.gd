extends "res://examples/selftest/sections_reload.gd"

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
const CHECKS := 734


func _ready() -> void:
	print("zee-dot-weapons self-test")
	print("=========================")

	_ids()
	_damage()
	_pack()
	_cards()
	_art()
	_glove()
	_other_packs()
	_pack_source()
	_pack_scan()
	_workshop()
	_profiles()
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
	_rig_idle()
	_tick_rate()
	_view_models()
	_reload_sequences()
	_previews()
	_aim()
	_ads_rules()
	_effects()
	_input_bindings()
	await _stock_sounds()
	await _wall_slam()
	await _wall_arms()
	_effects_pack_light()
	_view_screen()

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

	# A game mounting its own arms turns show_arms off after the model is in the tree: one arm set, never two.
	var late := ZeeViewModel.new()
	add_child(late)
	var _e := late.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	var had := late.find_children("*", "ZeeViewArms", true, false).size()
	late.show_arms = false
	_check("show_arms turned off after the build removes the built arms (%d before, %d after)" % [had, late.find_children("*", "ZeeViewArms", true, false).size()],
		had == 1 and late.find_children("*", "ZeeViewArms", true, false).is_empty())
	late.show_arms = true
	_check("and turned back on builds them again", late.find_children("*", "ZeeViewArms", true, false).size() == 1)
	late.queue_free()

	view.queue_free()
	arms.queue_free()
	_end()


func _aim() -> void:
	_begin("aiming down")
	_aim_lens()
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

	_aim_marked_sights()

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
	var sniper_art := ZeeWeaponArtTable.get_art(&"sniper")
	_check("a sniper aims in near-instantly (%.2f)" % sniper_art.aim_time, sniper_art.aim_time <= 0.1 and sniper_art.scope_style is Dictionary)

	overlay.queue_free()
	view.queue_free()
	_end()


func _aim_lens() -> void:
	_check("100 horizontal on 4:3 is 83.6 vertical",
		absf(ZeeViewModel.vertical_from_horizontal_4_3(100.0) - 83.6) < 0.1)
	_check("the same lens is a scale of 1", is_equal_approx(ZeeViewModel.lens_scale(70.0, 70.0), 1.0))
	_check("a narrower hands lens draws them larger", ZeeViewModel.lens_scale(80.0, 60.0) > 1.0)
	var lensed := ZeeViewModel.new()
	lensed.show_arms = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.add_child(lensed)
	camera.fov = 80.0
	lensed.hands_fov = 60.0
	lensed._apply_hands_lens()
	var size_90 := ZeeViewModel.lens_scale(90.0, 60.0)
	_check("a narrower lens is drawn farther off by the size it adds",
		is_equal_approx(lensed.position.z, -(size_90 - 1.0) * ZeeViewModel.REFERENCE_DEPTH))
	camera.fov = 30.0
	lensed._apply_hands_lens()
	_check("and a zoom leaves the hands where they were", is_equal_approx(lensed.position.z, -(size_90 - 1.0) * ZeeViewModel.REFERENCE_DEPTH))
	camera.queue_free()


func _aim_marked_sights() -> void:
	# A model with real sights marks their line with two nodes, and is aimed along those
	# instead of a measured line with a ring and a notch built over its own sights.
	var sight_script := load("res://addons/zee_weapons/view/zee_iron_sight.gd")
	var marked_gun := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.6)
	# An ArrayMesh, as an imported model's is: a primitive mesh has no surface_get_primitive_type.
	var box_mesh := ArrayMesh.new()
	box_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	body.mesh = box_mesh
	marked_gun.add_child(body)
	for mark: Array in [["sight_rear", Vector3(0.0, 0.05, -0.2)], ["sight_front", Vector3(0.0, 0.05, 0.25)]]:
		var m := Marker3D.new()
		m.name = mark[0]
		m.position = mark[1]
		marked_gun.add_child(m)
	add_child(marked_gun)
	var marked: Dictionary = sight_script.from_marks(marked_gun, marked_gun, Vector3.BACK)
	_check("a model's own sight marks are its line, the back end measured behind them (%s)" % str(marked),
		marked.get("marked", false) and (marked.rear as Vector3).is_equal_approx(Vector3(0.0, 0.05, -0.2))
		and absf((marked.back as Vector3).z + 0.3) < 0.001)
	_check("and a model without marks has none", (sight_script.from_marks(body, body, Vector3.BACK) as Dictionary).is_empty())
	marked_gun.queue_free()
	_aim_own_sights()


## A gun from boxes along -Z: a receiver, with rear sight parts and a front post as `[centre, size]` pairs.
func _box_gun(parts: Array) -> Node3D:
	var gun := Node3D.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in [[Vector3.ZERO, Vector3(0.05, 0.05, 0.6)]] + parts:
		var box := BoxMesh.new()
		box.size = part[1]
		tool.append_from(box, 0, Transform3D(Basis.IDENTITY, part[0]))
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	mesh.mesh = tool.commit()
	gun.add_child(mesh)
	mesh.owner = gun
	return gun


func _aim_own_sights() -> void:
	# A model's own notch and post, or its aperture, are read off the mesh: the line runs over the post's tip, and nothing is built.
	var own := load("res://addons/zee_weapons/view/zee_own_sight.gd")
	var post := [Vector3(0.0, 0.0325, -0.2575), Vector3(0.004, 0.015, 0.005)]
	var notched := _box_gun([[Vector3(0.012, 0.035, 0.16), Vector3(0.01, 0.02, 0.02)],
		[Vector3(-0.012, 0.035, 0.16), Vector3(0.01, 0.02, 0.02)], post])
	var ringed := _box_gun([[Vector3(0.0, 0.0625, 0.155), Vector3(0.034, 0.005, 0.01)],
		[Vector3(0.0145, 0.045, 0.155), Vector3(0.005, 0.04, 0.01)], [Vector3(-0.0145, 0.045, 0.155), Vector3(0.005, 0.04, 0.01)],
		[Vector3(0.0, 0.035, -0.2575), Vector3(0.004, 0.02, 0.005)]])
	var plain := _box_gun([])
	for gun: Node3D in [notched, ringed, plain]:
		add_child(gun)
	var a: Dictionary = own.measure(notched, notched, Vector3.FORWARD, -0.1)
	_check("a notch and post: the line runs over the post's tip (%s)" % str(a),
		a.get("kind", "") == "post" and a.get("post", false) and absf((a.front as Vector3).y - 0.04) < 0.001
		and absf((a.front as Vector3).z + 0.255) < 0.001 and is_equal_approx((a.rear as Vector3).z, 0.1))
	var b: Dictionary = own.measure(ringed, ringed, Vector3.FORWARD, -0.1)
	_check("a ring round a post: the line runs through the ring onto the post's tip (%s)" % str(b),
		b.get("kind", "") == "aperture" and b.get("post", false) and absf((b.front as Vector3).y - 0.045) < 0.001)
	_check("and a gun with neither has no sight of its own", (own.measure(plain, plain, Vector3.FORWARD, -0.1) as Dictionary).is_empty())
	plain.queue_free()
	ringed.queue_free()

	# Aimed in a view model, the own line goes through the screen's centre, nothing is built over it, and the post's dot shows.
	var scene := PackedScene.new()
	notched.get_parent().remove_child(notched)
	scene.pack(notched)
	var path := "user://zee_selftest_own_sight.scn"
	ResourceSaver.save(scene, path)
	notched.free()
	var art := ZeeWeaponArt.make(&"own_sight_test", path)
	art.model_forward = Vector3.FORWARD
	art.iron_sight = false
	art.sight_own = true
	art.aim_eye_relief = 0.32
	art.aim_offset = Vector3(0.0, -0.04, -0.42)
	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)
	view.equip(art)
	view.aim(true)
	for _i in 40:
		view._process(0.02)
	var points := view.sight_points()
	var off := 1.0
	if not points.is_empty():
		off = maxf(Vector2((points.rear as Vector3).x, (points.rear as Vector3).y).length(),
			Vector2((points.front as Vector3).x, (points.front as Vector3).y).length())
	_check("aimed, a model's own sight runs through the screen's centre (%.4f m)" % off, off < 0.002)
	var built := view.find_child("Sight", true, false)
	var dot := view.find_child("SightDot", true, false) as MeshInstance3D
	_check("with no sight built over it, and its post's dot shown", built == null and dot != null and dot.visible)
	view.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_aim_cut()
	_red_dot()


func _aim_cut() -> void:
	# A housing across the aim line is cut away round it as far as the post, and the rest of the gun is kept.
	var cut_script := load("res://addons/zee_weapons/view/zee_sight_cut.gd")
	var gun := _box_gun([[Vector3(0.0, 0.1, -0.1), Vector3(0.04, 0.04, 0.06)], [Vector3(0.0, 0.1, -0.3), Vector3(0.006, 0.006, 0.006)]])
	add_child(gun)
	var cone: Dictionary = cut_script.cone(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, -0.2)), 2.0, Vector3(0.0, 0.1, -0.297))
	var before: int = cut_script.occluders(gun, gun, cone)
	var done: Dictionary = cut_script.apply([gun], gun, cone)
	var after: int = cut_script.occluders(gun, gun, cone)
	_check("a housing over the aim line blocks it until cut (%d of 49 rays), then nothing does (%d)" % [before, after], before > 20 and after == 0)
	var past := {"eye": cone.eye, "axis": cone.axis, "tan": cone.tan, "stop": INF}
	_check("the post past the stop is kept, and so is the housing outside the cone (%s)" % str(done),
		int(done.get("removed", 0)) > 0 and cut_script.occluders(gun, gun, past) > 0
		and _hits(gun, Vector3(0.0, 0.115, 0.0), Vector3(0.0, 0.115, -0.2)))
	_check("a cone of 0 degrees cuts nothing", (cut_script.cone(Transform3D.IDENTITY, 0.0) as Dictionary).is_empty())
	gun.queue_free()


func _hits(node: Node3D, from: Vector3, to: Vector3) -> bool:
	for tri: Dictionary in load("res://addons/zee_weapons/view/zee_iron_sight.gd").triangles_of(node, node):
		if Geometry3D.segment_intersects_triangle(from, to, tri.a, tri.b, tri.c) != null:
			return true
	return false


func _red_dot() -> void:
	# A red-dot rule parses its colour, and the dot sits where the eye's line along the axis meets the lens.
	var rules := ZeeAdsRules.new()
	var red: Dictionary = rules.red_dot_for(&"gl")
	_check("a red dot is off by default and red when on (%s)" % str(red), not red.on and (red.color as Color).r > 0.9 and (red.color as Color).g < 0.3)
	_check("its colour is a colour or refused", rules.set_value(&"gl", "red_dot_color", "#00ff00") and not rules.set_value(&"gl", "red_dot_color", "nope")
		and (rules.red_dot_for(&"gl").color as Color).is_equal_approx(Color(0, 1, 0)) and rules.set_value(&"gl", "red_dot", true) and rules.red_dot_for(&"gl").on)
	var fit := ZeeViewModel.SightFit
	var cone: Dictionary = fit.Cut.cone(Transform3D.IDENTITY, 4.0)
	var sight: Node3D = fit._red_dot(cone, 0.2, rules.red_dot_for(&"gl"))
	add_child(sight)
	var dot := sight.find_child(fit.RETICLE_NAME, true, false) as Node3D
	fit.track(sight, Vector3(0.004, -0.002, 0.0))
	var at := sight.to_global(dot.position) if dot != null else Vector3.INF
	_check("the dot follows the eye across the lens, at the lens (%s)" % str(at), dot != null and dot.visible and at.is_equal_approx(Vector3(0.004, -0.002, -0.2)))
	fit.track(sight, Vector3(0.05, 0.0, 0.0))
	_check("and hides once the eye is outside the window", not dot.visible)
	# The next gun's dot is added beside this one while it waits to be freed, so the engine renames it.
	sight.queue_free()
	var next: Node3D = fit._red_dot(cone, 0.2, rules.red_dot_for(&"gl"))
	add_child(next)
	var next_dot := next.find_child(fit.RETICLE_NAME, true, false) as Node3D
	fit.track(next, Vector3(0.004, -0.002, 0.0))
	_check("the next gun's dot, renamed (%s), still tracks the eye" % next.name, next.name != fit.RED_DOT_NAME and next.to_global(next_dot.position).is_equal_approx(Vector3(0.004, -0.002, -0.2)))
	next.queue_free()


func _previews() -> void:
	_begin("weapon previews")
	var previews := ZeeWeaponPreview.new()
	add_child(previews)
	var rifle := previews.texture(&"rifle")
	_check("a weapon with a model gets a texture", rifle != null)
	_check("at the configured size", rifle != null and rifle.get_size() == Vector2(previews.size))
	_check("asking again returns the cached texture", previews.texture(&"rifle") == rifle)
	_check("an unknown id has no picture", previews.texture(&"no_such_weapon") == null)
	_check("the miss is cached too", previews.cached_count() == 2)
	var other := previews.texture(&"pistol")
	_check("each weapon has its own texture", other != null and other != rifle)
	previews.queue_free()
	_end()


func _wall_slam() -> void:
	_begin("the view model against a wall")

	var camera := Camera3D.new()
	add_child(camera)
	var view := ZeeViewModel.new()
	view.show_arms = false
	camera.add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"rifle"))
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 20.0, 1.0)
	box.shape = shape
	wall.add_child(box)
	wall.position = Vector3(0.0, 0.0, -100.0)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame

	for i in range(30):
		view.advance(1.0 / 60.0)
	_check("in open air nothing is retracted", view.wall_amount() == 0.0)
	var rest := -(camera.global_transform.affine_inverse() * view.muzzle_transform().origin).z

	var surface := rest - 0.12
	wall.position = Vector3(0.0, 0.0, -(surface + 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(60):
		view.advance(1.0 / 60.0)
	var slammed := -(camera.global_transform.affine_inverse() * view.muzzle_transform().origin).z
	_check("a muzzle inside the wall retracts the weapon (%.3f m)" % view.wall_amount(), view.wall_amount() > 0.05)
	_check("the muzzle, where tracers and flashes leave, is in front of the wall (%.3f of %.3f)" % [slammed, surface],
		slammed <= surface)
	var up := (view.muzzle_transform().basis * Vector3.FORWARD).y
	_check("and the barrel is tipped up (%.2f)" % up, up > 0.05)

	view.feel_rules.wall_retract = 0.0
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("cl_vm_wall 0 turns it off", view.wall_amount() == 0.0)
	view.feel_rules.wall_retract = 1.0
	wall.position = Vector3(0.0, 0.0, -100.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(90):
		view.advance(1.0 / 60.0)
	_check("walking away from the wall brings it back", view.wall_amount() == 0.0)

	var person := CharacterBody3D.new()
	var pbox := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(2.0, 2.0, 0.2)
	pbox.shape = pshape
	person.add_child(pbox)
	person.position = Vector3(0.0, 0.0, -(surface + 0.1))
	add_child(person)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("a person in front of the muzzle does not retract it (%.3f m)" % view.wall_amount(), view.wall_amount() == 0.0)
	view.wall_ignore_characters = false
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("with wall_ignore_characters off the person is a wall (%.3f m)" % view.wall_amount(), view.wall_amount() > 0.05)
	view.wall_ignore_characters = true
	person.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check("obstruction maths: no hit is 0", ZeeWallSlam.obstruction(0.9, INF) == 0.0)
	_check("a hit past the muzzle and margin is 0", ZeeWallSlam.obstruction(0.9, 1.0) == 0.0)
	_check("a hit short of the muzzle is positive", ZeeWallSlam.obstruction(0.9, 0.8) > 0.1)
	_check("the retract is capped", ZeeWallSlam.obstruction(0.9, 0.0) == ZeeWallSlam.MAX_RETRACT)
	camera.queue_free()
	wall.queue_free()
	_end()


## A scripted run into a wall, then a reload against it: every frame the hands stay on the gun, each arm
## stays an arm's length, and the shoulders stay below the screen and in front of the near plane.
func _wall_arms() -> void:
	_begin("the arms while the weapon is pulled back from a wall")
	var camera := Camera3D.new()
	add_child(camera)
	var view := ZeeViewModel.new()
	camera.add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"bullpup"))
	var grip := {}
	view.hands_reached.connect(func(at: Node3D, hand: Vector3, _fore: Vector3, _pose: StringName) -> void: grip["at"] = at.global_transform * hand)
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = Vector3(20.0, 20.0, 1.0)
	wall.add_child(box)
	wall.position = Vector3(0.0, 0.0, -3.5)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var arms := view.get_node_or_null("Animated/Arms") as ZeeViewArms
	var worst := {"gap": 0.0, "long": 0.0, "high": -INF, "near": -INF, "pulled": 0.0}
	for i in range(150):
		camera.position.z = maxf(-0.1 * i, -2.65)
		view.on_reload(clampf((i - 90) / 50.0, 0.0, 1.0))
		view.advance(1.0 / 60.0)
		if arms == null or arms.last_hands.is_empty():
			break
		var to_cam := camera.global_transform.affine_inverse() * arms.global_transform
		var hands := arms.last_hands
		worst["gap"] = maxf(worst["gap"], (arms.global_transform * (hands["right"] as Vector3)).distance_to(grip.get("at", Vector3.INF)))
		worst["pulled"] = maxf(worst["pulled"], view.wall_amount())
		for side in ["right", "left"]:
			var shoulder: Vector3 = to_cam * (hands[side + "_shoulder"] as Vector3)
			worst["long"] = maxf(worst["long"], shoulder.distance_to(to_cam * (hands[side] as Vector3)))
			worst["high"] = maxf(worst["high"], shoulder.y)
			worst["near"] = maxf(worst["near"], shoulder.z)
	_check("the run reaches the wall and pulls the weapon back (%.3f m)" % worst["pulled"], worst["pulled"] > 0.2)
	_check("the right hand stays on the grip every frame (%.4f m at most)" % worst["gap"], worst["gap"] < 0.002)
	_check("no arm is drawn longer than an arm (%.3f m at most)" % worst["long"], worst["long"] < 0.6)
	_check("the shoulders stay below the screen and in front of the near plane (y %.3f, z %.3f at most)" % [worst["high"], worst["near"]],
		worst["high"] < -0.3 and worst["near"] < -camera.near)
	camera.queue_free()
	wall.queue_free()
	_end()
