extends "res://examples/selftest/sections_rig.gd"

## The recoil sections of the suite, split out of zee_selftest.gd for file size.


func _recoil() -> void:
	_begin("recoil")
	_recoil_climbs()
	_recoil_small()
	_recoil_drawn()
	_recoil_sides()
	_recoil_params()
	_recoil_grip()
	_end()


func _recoil_climbs() -> void:
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


func _recoil_small() -> void:
	# A small recoil still lifts the drawn weapon (kick_min), the camera punch does not follow it,
	# and a kick scale of 0 draws no kick at all.
	var vm_small := ZeeWeaponPose.make(1.0)
	vm_small.punch(Vector2(0.1, 0.0))
	var vm_peak := 0.0
	var vm_cam := 0.0
	for i in range(144):
		vm_small.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
		vm_peak = maxf(vm_peak, absf(vm_small.offset().basis.get_euler().x))
		vm_cam = maxf(vm_cam, vm_small.view_punch().x)
	_check("a small shot lifts the drawn weapon at least a degree (%.2f)" % rad_to_deg(vm_peak), rad_to_deg(vm_peak) > 1.0)
	var vm_bare := ZeeWeaponPose.make(1.0)
	vm_bare.tunables.kick_min = 0.0
	vm_bare.punch(Vector2(0.1, 0.0))
	var vm_bare_cam := 0.0
	for i in range(144):
		vm_bare.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
		vm_bare_cam = maxf(vm_bare_cam, vm_bare.view_punch().x)
	_check("the camera punch is the same with or without the drawn top-up", is_equal_approx(vm_cam, vm_bare_cam))
	var vm_off := ZeeWeaponPose.make(1.0)
	vm_off.rules.kick = 0.0
	vm_off.punch(Vector2(1.0, 0.2))
	var vm_moved := 0.0
	for i in range(72):
		vm_off.advance(1.0 / 144.0, Vector2.ZERO, 0.0, true)
		vm_moved = maxf(vm_moved, vm_off.offset().origin.length() + absf(vm_off.offset().basis.get_euler().x))
	_check("kick scale 0 draws no kick (%.4f)" % vm_moved, vm_moved < 0.0001)


func _recoil_drawn() -> void:
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


func _recoil_sides() -> void:
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

	# Same punches, same kick: the pose has no hidden randomness when signed.
	var seq_a: Array = []
	var seq_b: Array = []
	for run in [seq_a, seq_b]:
		var sp := ZeeWeaponPose.make(1.0)
		for i in range(8):
			sp.punch(Vector2(2.0, 1.0 if i % 3 else -1.0), true)
			for j in range(6):
				sp.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
			run.append(sp.view_punch())
	_check("the same signed punches give the same camera sequence", seq_a == seq_b)

	# A faster weapon's kick settles sooner.
	var slow_p := ZeeWeaponPose.make(1.0)
	var fast_p := ZeeWeaponPose.make(1.0)
	slow_p.fire_interval = 0.5
	fast_p.fire_interval = 0.06
	slow_p.punch(Vector2(3.0, 0.0))
	fast_p.punch(Vector2(3.0, 0.0))
	for j in range(12):
		slow_p.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
		fast_p.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	_check(
		"a faster weapon's kick has settled further after the same time",
		absf(fast_p.view_punch().x) < absf(slow_p.view_punch().x)
	)


func _recoil_params() -> void:
	# Kick numbers are profile params: defaults change nothing, a set key does, junk is ignored.
	var kd := ZeeWeaponPose.Tunables.kick_defaults()
	var base_t := ZeeWeaponPose.Tunables.new()
	var same := kd.size() == 12
	for key: StringName in ZeeWeaponPose.Tunables.KICK_PARAMS:
		same = same and is_equal_approx(float(kd[key]), float(base_t.get(ZeeWeaponPose.Tunables.KICK_PARAMS[key])))
	var def_pose := ZeeWeaponPose.make(1.0)
	var tuned_pose := ZeeWeaponPose.make(1.0)
	tuned_pose.tunables.apply_kick(kd)
	def_pose.punch(Vector2(2.0, 0.0))
	tuned_pose.punch(Vector2(2.0, 0.0))
	for j in range(9):
		def_pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
		tuned_pose.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	_check("kick params at their defaults give the identical kick", same and def_pose.describe()["kick_rotation"] == tuned_pose.describe()["kick_rotation"])
	var hard := ZeeWeaponPose.make(1.0)
	hard.tunables.apply_kick({&"view_kick_pitch": 8.0, &"view_kick_knee": "junk"})
	hard.punch(Vector2(2.0, 0.0))
	_check("a profile's view_kick_pitch scales the climb and junk keeps the default",
		hard.kick_degrees(2.0) > def_pose.kick_degrees(2.0) * 1.9 and is_equal_approx(hard.tunables.kick_knee, 0.45))
	var pack_rifle := ZeeWeaponPack.rifle()
	_check("every gun builder carries the kick params (rifle)", pack_rifle.params.has(&"view_kick_pitch") and pack_rifle.params.has(&"view_kick_rate_max"))

	# Signed (dot-weapon's recoil_signed): the sign of the yaw is the side, every time.
	var fixed := ZeeWeaponPose.make(1.0)
	var fixed_right := 0
	var fixed_left := 0
	for i in range(10):
		var was := (fixed.describe()["kick_rotation"] as Vector3).y
		fixed.punch(Vector2(0.0, 1.0 if i < 5 else -1.0), true)
		fixed.advance(1.0 / 120.0, Vector2.ZERO, 0.0, true)
		var went := (fixed.describe()["kick_rotation"] as Vector3).y - was
		if went > 0.0:
			fixed_right += 1
		elif went < 0.0:
			fixed_left += 1
		for j in range(60):
			fixed.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true)
	_check(
		"a signed sideways kick takes the side the rules chose (%d right, %d left)" % [fixed_right, fixed_left],
		fixed_right == 5 and fixed_left == 5
	)


func _recoil_grip() -> void:
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


const MIN_HIP_WIDTH := 0.18
## The barrel as drawn, degrees off screen-up toward the middle: below it the gun is seen end-on, above it diagonal.
const HIP_LEAN := Vector2(10.0, 35.0)
const MAX_HIP_CANT := 12.0


## What the player sees, measured through a camera, so a check cannot pass while the render is diagonal.
func _view_screen() -> void:
	_begin("view on screen")
	var measure := preload("res://tools/view_measure.gd").new()
	add_child(measure)
	measure.build(ZeeAdsRules.load_config())
	var leaning := []
	var canted := []
	var small := []
	var off_centre := []
	for id in ZeeWeaponIds.all():
		var hip: Dictionary = measure.measure(id, false)
		if hip.is_empty() or not hip.has("sight_off_px"):
			continue
		if float(hip.screen_lean) < HIP_LEAN.x or float(hip.screen_lean) > HIP_LEAN.y:
			leaning.append("%s %.1f" % [id, hip.screen_lean])
		if absf(float(hip.screen_cant)) > MAX_HIP_CANT:
			canted.append("%s %.1f" % [id, hip.screen_cant])
		if float(hip.width) < MIN_HIP_WIDTH:
			small.append("%s %.0f%%" % [id, float(hip.width) * 100.0])
		var aim: Dictionary = measure.measure(id, true)
		if aim.has("sight_off_px") and float(aim.sight_off_px) > 4.0:
			off_centre.append("%s %.0fpx" % [id, aim.sight_off_px])
	_check("hip: every barrel is drawn %d-%d degrees off upright %s" % [int(HIP_LEAN.x), int(HIP_LEAN.y), str(leaning)], leaning.is_empty())
	_check("hip: every gun is drawn canted at most %d degrees %s" % [int(MAX_HIP_CANT), str(canted)], canted.is_empty())
	_check("hip: every gun spans at least %d%% of the screen %s" % [int(MIN_HIP_WIDTH * 100.0), str(small)], small.is_empty())
	_check("aim: every sight sits on the screen centre " + str(off_centre), off_centre.is_empty())
	# A game that assigns no rules (the art's own hip) is stood up too.
	measure.view.ads_rules = null
	var bare := []
	for id in [ZeeWeaponIds.RIFLE, ZeeWeaponIds.SMG, ZeeWeaponIds.PISTOL]:
		var hip: Dictionary = measure.measure(id, false)
		if hip.is_empty() or float(hip.screen_lean) < HIP_LEAN.x or float(hip.screen_lean) > HIP_LEAN.y:
			bare.append("%s %s" % [id, str(hip.get("screen_lean"))])
	_check("hip without rules: the barrel is not drawn diagonally " + str(bare), bare.is_empty())
	measure.queue_free()
	_end()
