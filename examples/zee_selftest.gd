extends "res://examples/selftest/sections_pose.gd"

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
const CHECKS := 572


func _ready() -> void:
	print("zee-dot-weapons self-test")
	print("=========================")

	_ids()
	_damage()
	_pack()
	_cards()
	_art()
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
	_previews()
	_aim()
	_ads_rules()
	_effects()
	_input_bindings()
	await _stock_sounds()

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

	overlay.queue_free()
	view.queue_free()
	_end()


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


func _effects() -> void:
	_begin("shots are seen and heard")

	# --- Sound ---
	var silent: Array[String] = []
	var clicks: Array[String] = []

	for sound_class in ZeeWeaponSound.RECIPES.keys():
		# The bake itself (the fallback when dot-audio is not linked); the stock is checked in its own section.
		var wav := ZeeWeaponSound.bake(ZeeWeaponSound.RECIPES[sound_class], hash(sound_class))
		if wav == null or wav.data.size() < 200 or _wav_peak(wav) < 0.2:
			silent.append(String(sound_class))
		elif wav.data.decode_s16(wav.data.size() - 2) != 0:
			clicks.append(String(sound_class))

	_check("every sound class bakes something audible: %s" % ", ".join(silent), silent.is_empty())
	_check(
		"and every one ends at exactly zero, so none of them clicks: %s" % ", ".join(clicks),
		clicks.is_empty()
	)

	var rifle := ZeeWeaponSound.bake(
		ZeeWeaponSound.RECIPES[ZeeWeaponSound.RIFLE], hash(ZeeWeaponSound.RIFLE)
	)
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

	_effects_impacts(fx)

	var server := _make_rig()
	server.setup()
	_check("a server rig draws and plays nothing", server.shot_fx() == null)

	_cleanup(server)
	carrier.queue_free()
	stranger.queue_free()
	_end()


func _effects_impacts(fx: ZeeShotFx) -> void:
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

	var warmed := ZeeShotFx.warm()
	var warmed_again := ZeeShotFx.warm()
	var shared := warmed.size() >= 15
	for i in warmed.size():
		shared = shared and warmed[i] != null and warmed[i] == warmed_again[i]
	_check("warm() builds every shared mesh and material once, so the first shot makes none", shared)

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


## The loudest sample in a 16-bit stream, from 0 to 1.
static func _wav_peak(wav: AudioStreamWAV) -> float:
	var peak := 0
	for i in range(0, wav.data.size() - 1, 2):
		peak = maxi(peak, absi(wav.data.decode_s16(i)))
	return float(peak) / 32767.0


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
