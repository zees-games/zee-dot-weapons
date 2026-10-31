extends "res://examples/selftest/sections_pose.gd"

## Selftest sections: pose stability and the shot effects, split out of zee_selftest.gd for file size.


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

	_pose_keys()
	_pose_jitter()

	_pose_cadence()

	_end()


func _pose_swing() -> void:
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


func _pose_cadence() -> void:
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


func _effects() -> void:
	_begin("shots are seen and heard")

	_effects_sound()

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

	_effects_budgets()
	var stranger := _effects_world(carrier)
	_effects_world_motion(stranger)

	_effects_impacts(fx)

	var server := _make_rig()
	server.setup()
	_check("a server rig draws and plays nothing", server.shot_fx() == null)

	_cleanup(server)
	carrier.queue_free()
	stranger.queue_free()
	_end()


func _pose_keys() -> void:
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
	# Every gun resolves to a reload (its own or its class's), and every key set is at rest at both ends.
	var no_reload: PackedStringArray = []
	var bad_ends: PackedStringArray = []
	for art in ZeeWeaponArtTable.all():
		if art.pose == ZeeWeaponArtTable.POSE_MELEE or art.pose == ZeeWeaponArtTable.POSE_THROWN:
			continue
		var keys := ZeeWeaponArtTable.effective_reload_keys(art)
		if keys.is_empty():
			no_reload.append(String(art.id))
			continue
		if ZeeWeaponPose.sample_keys(keys, 0.0)[0].length() > 0.0001 or ZeeWeaponPose.sample_keys(keys, 1.0)[0].length() > 0.0001:
			bad_ends.append(String(art.id))
	_check("every gun resolves to a reload animation (missing: %s)" % ", ".join(no_reload), no_reload.is_empty())
	_check("every gun's reload starts and ends at rest (bad: %s)" % ", ".join(bad_ends), bad_ends.is_empty())
	var base_art := ZeeWeaponArtTable.all()[0] as ZeeWeaponArt
	var by_class := base_art.with_overrides({"reload_class": "smg"})
	var by_keys := base_art.with_overrides({"reload_keys": [[0.0, [0, 0, 0], [0, 0, 0]], [0.5, [0, 0.1, 0], [10, 0, 0]], [1.0, [0, 0, 0], [0, 0, 0]]]})
	_check("a profile names a reload class or gives its own keys", by_class.reload_keys == ZeeWeaponPose.RELOAD_KEYS_SMG and by_keys.reload_keys.size() == 3 and base_art.with_overrides({"reload_class": "nope"}).reload_keys == base_art.reload_keys)
	var sock := ZeeWeaponArt.new()
	ZeeArtDress.apply(sock, {"model": "res://assets/low-poly-guns/smg.glb", "motion": "gun", "grip_socket": [0.01, -0.02, 0.03], "support_grip": Vector3(0, 0.05, -0.2), "hand_scale": 0.36, "forearm_scale": 0.5})
	var over_hand := base_art.with_overrides({"hand_scale": 0.4, "grip_socket": [0, 0, 0.1]})
	_check("a row names the grip socket, the support grip and the hand size, and a profile overrides them",
		sock.grip_socket.is_equal_approx(Vector3(0.01, -0.02, 0.03)) and sock.support_grip.is_equal_approx(Vector3(0, 0.05, -0.2)) and is_equal_approx(sock.hand_scale, 0.36) and is_equal_approx(sock.forearm_scale, 0.5) and is_equal_approx(over_hand.hand_scale, 0.4) and over_hand.grip_socket.is_equal_approx(Vector3(0, 0, 0.1)))
	var thin := base_art.with_overrides({"forearm_scale": 0.4})
	_check("a row or profile sizes the first-person forearm, and the default keeps the arms' own", is_equal_approx(thin.forearm_scale, 0.4) and is_equal_approx(base_art.forearm_scale, 0.0) and is_equal_approx(ZeeWeaponArt.new().forearm_scale, 0.0))
	var tuned := base_art.with_overrides({"scope_arms_hide": 0.3, "max_lean": 0.1})
	var dressed_art := ZeeWeaponArt.new()
	ZeeArtDress.apply(dressed_art, {"model": "res://assets/low-poly-guns/smg.glb", "scope_arms_hide": 0.2, "max_lean": 0.0})
	var vm := ZeeViewModel.new()
	vm.set("_art", tuned)
	var at_art := vm.scope_arms_hide_at()
	vm.scope_arms_hide_override = 0.9
	var at_override := vm.scope_arms_hide_at()
	vm.free()
	_check("scope_arms_hide and max_lean are art keys and a cvar override beats the weapon's",
		is_equal_approx(tuned.scope_arms_hide, 0.3) and is_equal_approx(tuned.max_lean, 0.1) and is_equal_approx(dressed_art.scope_arms_hide, 0.2) and is_equal_approx(dressed_art.max_lean, 0.0)
		and is_equal_approx(at_art, 0.3) and is_equal_approx(at_override, 0.9) and base_art.scope_arms_hide < 0.0 and base_art.max_lean < 0.0)
	_check("the draw's keys are at rest in hand",
		ZeeWeaponPose.sample_keys(ZeeWeaponPose.DRAW_KEYS, 1.0)[0].length() < 0.0001)
	_pose_swing()

	var odd: Vector3 = ZeeWeaponPose.sample_keys([[0.0, Vector3.ONE, Vector3.ONE]], NAN)[0]
	_check("malformed keys sample as rest", odd == Vector3.ZERO)


func _pose_jitter() -> void:
	# No jitter: a whole draw and reload at 144 fps while walking and turning. A step in a key table
	# or a ringing spring shows as one frame far bigger than the frames either side of it.
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


func _effects_budgets() -> void:
	# Budgets: a held minigun asks for a flash and a case per shot, and neither may grow.
	var capped := ZeeShotFx.new()
	capped.binbun_flash = false
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


## A flash (dot-fx's when linked, else ours) still makes the one capped muzzle light, and the art's own is off (no double).
func _effects_pack_light() -> void:
	_begin("dot-fx muzzle light")
	var linked := ResourceLoader.exists(DotWeaponMuzzle.SCRIPT_PATH)
	var script: GDScript = load(DotWeaponMuzzle.SCRIPT_PATH) if linked else null
	if linked:
		script.set("force_available", true)
	var fx := ZeeShotFx.new()
	add_child(fx)
	var at := Transform3D(Basis.IDENTITY, Vector3(0, 0, -1))
	fx.call(&"_flash", at, 1.0, ZeeWeaponSound.RIFLE, &"", false)
	var lights := int(fx.call(&"_lights_live"))
	_check("a dot-fx flash makes a muzzle light (%d)" % lights, lights == 1)
	var lit := _lit_lights(fx)
	_check("a dot-fx flash adds only our light, the art's is off (%d lit)" % lit, lit == 1)
	for i in 40:
		fx.call(&"_flash", at, 1.0, ZeeWeaponSound.MINIGUN, &"", false)
	lights = int(fx.call(&"_lights_live"))
	_check("dot-fx flash lights stay under the cap (%d of %d)" % [lights, fx.max_flash_lights],
		lights >= 1 and lights <= fx.max_flash_lights)
	var found := fx.find_children("*", "OmniLight3D", true, false)
	_check("the muzzle light exists and has no shadows", not found.is_empty() and not (found[0] as OmniLight3D).shadow_enabled)
	fx.flash_light_scale = 0.0
	fx.advance(1.0)
	fx.call(&"_flash", at, 1.0, ZeeWeaponSound.RIFLE, &"", false)
	_check("flash_light_scale 0 draws no light with a dot-fx flash",
		int(fx.call(&"_lights_live")) == 0 and _lit_lights(fx) == 0)
	fx.flash_light_scale = 1.0
	fx.call(&"_flash", at, 1.0, ZeeWeaponSound.RIFLE, &"", false)
	fx.advance(0.2)
	_check("the muzzle light is gone after its life", int(fx.call(&"_lights_live")) == 0)
	fx.queue_free()
	if linked:
		script.set("force_available", false)
	_end()


## Lights shining under [param root] that are visible and lit (ours or the art's).
## Whether a node, or the flash it hangs under, is already queued to be freed (its light dies with it).
func _going(node: Node) -> bool:
	while node != null:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false


func _lit_lights(root: Node) -> int:
	var count := 0
	for light in root.find_children("*", "OmniLight3D", true, false):
		var l := light as OmniLight3D
		if not _going(l) and l.is_visible_in_tree() and l.light_energy > 0.0 and l.get_parent().get("light_enable") != false:
			count += 1
	return count


## The carrier's own world model and somebody else's; returns the stranger it made.
func _effects_world(carrier: Node3D) -> Node3D:
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
	return stranger


func _effects_world_motion(stranger: Node3D) -> void:
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


func _effects_sound() -> void:
	# The synthesiser and the stock recordings.
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

	var sound_problems := DotWeaponSound.check_classes(ZeeWeaponSound.WEAPONS)
	_check("every weapon's sound class has fire, reload and dry files of a fitting length: %s" % "; ".join(sound_problems), sound_problems.is_empty())
	var shared := DotWeaponSound.check_unique()
	_check("no two sound classes share a recording: %s" % "; ".join(shared), shared.is_empty())

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


## The railgun's charge ball: grows with the draw, is ready only at the top, fizzles on an early release,
## reaches a watcher through the snapshot, and the beam is drawn only from a full charge.
func _belt_feed() -> void:
	_begin("belt feed and eject port")
	var row := ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE).with_overrides({"belt_feed": true, "eject_speed": 2.0, "eject_port": [0.3, 0.6, 0.4]})
	_check("art rows carry the belt flag, eject speed and port", row.belt_feed and is_equal_approx(row.eject_speed, 2.0) and row.eject_port.is_equal_approx(Vector3(0.3, 0.6, 0.4)))
	var view := ZeeViewModel.new()
	add_child(view)
	var _e := view.equip(row)
	view.advance(0.05)
	_check("a belt-fed gun builds a belt", view.belt_feed() != null)
	_check("its eject speed is the art's", is_equal_approx(view.eject_speed(), 2.0))
	if view.belt_feed() != null:
		var shot := _fake_shot()
		for i in 3:
			view.on_used(shot)
		for i in 30:
			view.advance(0.02)
		_check("the belt advances a round a shot (%.1f)" % view.belt_feed().travelled(), is_equal_approx(view.belt_feed().travelled(), 3.0))
	view.queue_free()
	var plain := ZeeViewModel.new()
	add_child(plain)
	var _p := plain.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.RIFLE))
	_check("a plain gun has no belt", plain.belt_feed() == null)
	plain.queue_free()
	_end()


func _charge_ball() -> void:
	_begin("charge ball")
	var view := ZeeViewModel.new()
	add_child(view)
	var _e := view.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.CHARGE_RIFLE))
	view.advance(0.05)
	view.on_charge(0.0)
	_check("no ball before the first charge", view.charge_fx() == null)
	var sizes: Array[float] = []
	for f in [0.2, 0.5, 0.9]:
		view.on_charge(f)
		view.charge_fx().advance(0.016)
		sizes.append(view.charge_fx().shown())
	_check("the ball grows with the draw (%s)" % [sizes], sizes[0] < sizes[1] and sizes[1] < sizes[2])
	_check("it is not ready at 90%", not view.charge_fx().is_ready())
	view.on_charge(1.0)
	_check("it is ready at 100%", view.charge_fx().is_ready())
	view.on_charge(0.0)
	_check("an unfired release fizzles", view.charge_fx().is_fizzling())
	for i in 30:
		view.charge_fx().advance(0.016)
	_check("and the fizzle ends", not view.charge_fx().visible)
	view.on_charge(1.0)
	view.note_fired()
	view.on_charge(0.0)
	_check("a fired release is a shot, not a fizzle", not view.charge_fx().is_fizzling())

	var fx := ZeeShotFx.new()
	add_child(fx)
	var before := fx.live_count()
	fx._rail_beam(Vector3.ZERO, Vector3(0, 0, -20))
	_check("a full-charge beam adds glow, core and ring (%d)" % (fx.live_count() - before), fx.live_count() - before == 3)
	for i in 40:
		fx.advance(0.016)
	_check("and it fades out within a second", fx.live_count() == 0)

	var held := _ChargeSource.new()
	var world := ZeeWorldModel.new()
	add_child(world)
	var _w := world.equip(ZeeWeaponArtTable.get_art(ZeeWeaponIds.CHARGE_RIFLE))
	var got := ZeeWeaponNet.apply(held, world, 0)
	_check("a watcher's copy shows the ball from the snapshot", world.charge_fx() != null and absf(world._last_charge - 8.0 / ZeeWeaponNet.CHARGE_MAX) < 0.01)
	_check("the charge fits its field (%d bits)" % ZeeWeaponNet.CHARGE_BITS, ZeeWeaponNet.charge_specs()[0]["bits"] == ZeeWeaponNet.CHARGE_BITS and got != null)
	view.queue_free()
	fx.queue_free()
	world.queue_free()
	_end()


class _ChargeSource:
	var net_fire_seq := 0
	var net_fire_kind := 0
	var net_switching := false
	var net_reloading := false
	var net_charge := 8
