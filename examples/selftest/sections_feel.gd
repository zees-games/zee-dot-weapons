extends "res://examples/selftest/harness.gd"

## Selftest sections: the feel cvars and the pose.


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

	var hip_yaw := right.basis.get_euler().y
	_check("strafing right swings the muzzle left, mirrored on the left",
		hip_yaw > 0.005 and left.offset().basis.get_euler().y < -0.005)
	_check("aimed, the roll is less than at the hip and the yaw too",
		absf(aimed.basis.get_euler().z) < right.basis.get_euler().z * 0.5
		and absf(aimed.basis.get_euler().y) < hip_yaw * 0.5)
	for i in range(120):
		strafed.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true, false, 0.0)
	_check("when strafing stops it eases back to rest",
		absf(strafed.offset().origin.x) < 0.001 and absf(strafed.offset().basis.get_euler().z) < 0.002)
	for i in range(60):
		strafed.advance(1.0 / 60.0, Vector2.ZERO, 0.0, true, false, 5.0)
	strafed.rules.strafe_tilt = 0.0
	strafed.rules.aim_steadiness = 0.0
	strafed.set_aim(0.0)
	_check("strafe tilt 0 switches it off", absf(strafed.offset().basis.get_euler().z) < 0.001
		and absf(strafed.offset().basis.get_euler().y) < 0.001 and absf(strafed.offset().origin.x) < 0.001)
	strafed.rules.strafe_tilt = 1.0
	strafed.rules.strafe_yaw = 0.0
	_check("strafe yaw 0 keeps the roll and drops the swing",
		absf(strafed.offset().basis.get_euler().y) < 0.001 and strafed.offset().basis.get_euler().z > 0.03)

	var gun_ads := ZeeAdsRules.new()
	_check("a gun with no strafe key falls back to the server's", gun_ads.strafe_for(&"rifle").is_empty())
	var _ok := gun_ads.set_value(&"rifle", "strafe_yaw", 2.0)
	_check("a per-gun strafe override is read and the others stay absent",
		is_equal_approx(float(gun_ads.strafe_for(&"rifle").get("yaw", -1.0)), 2.0) and gun_ads.strafe_for(&"rifle").size() == 1)
	strafed.rules.strafe_yaw = 0.0
	strafed.gun_strafe = {}
	var fallback_yaw := absf(strafed.offset().basis.get_euler().y)
	strafed.gun_strafe = gun_ads.strafe_for(&"rifle")
	_check("the gun's own yaw wins over the server's, an absent key falls back",
		fallback_yaw < 0.001 and absf(strafed.offset().basis.get_euler().y) > 0.003 and strafed.offset().basis.get_euler().z > 0.03)
	strafed.gun_strafe = {}

	var rules := ZeeViewFeel.new()
	_check("a cvar value is applied", rules.set_cvar(ZeeViewFeel.CVAR_BOB, "0.5") and is_equal_approx(rules.bob, 0.5))
	_check("a value out of range is refused", not rules.set_cvar(ZeeViewFeel.CVAR_BOB, "9") and is_equal_approx(rules.bob, 0.5))
	_check("so is one that is not a number", not rules.set_cvar(ZeeViewFeel.CVAR_SWAY, "lots"))
	_check("every amount is a cvar", rules.cvar_specs().size() == 12)

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
