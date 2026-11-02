extends "res://examples/selftest/sections_reload.gd"

## Selftest sections: the view model and the shot against a wall.


func _wall_obstruction_maths() -> void:
	_check("obstruction maths: no hit is 0", ZeeWallSlam.obstruction(0.45, INF) == 0.0)
	_check("a hit past the muzzle and margin is 0", ZeeWallSlam.obstruction(0.45, 0.6) == 0.0)
	_check("a hit short of the muzzle is positive", ZeeWallSlam.obstruction(0.45, 0.3) > 0.1)
	_check("the retract is capped", ZeeWallSlam.obstruction(0.9, 0.0) == 0.34)
	_check("world model: no wall is no pull", ZeeWorldModel.wall_pull(INF, 0.8) == 0.0)
	_check("world model: a wall past the gun is no pull", ZeeWorldModel.wall_pull(1.5, 0.8) == 0.0)
	_check("world model: a wall inside the gun pulls it back by the overlap", is_equal_approx(ZeeWorldModel.wall_pull(1.0, 0.8), 0.29))
	_check("world model: the pull is capped", ZeeWorldModel.wall_pull(0.0, 0.8, 0.45, 0.04, 0.3) == 0.3)
	_check("the reach is the drawn distance over the drawn scale", is_equal_approx(ZeeWallSlam.reach_of(1.0, 2.0, 1.0), 0.5))


func _wall_slam_response() -> void:
	# The response: a spring that settles, direction by approach speed, and nothing while aimed.
	var slam := ZeeWallSlam.new()
	var peak := 0.0
	for i in range(120):
		slam.step(0.2, 1.0 / 60.0)
		peak = maxf(peak, slam.amount)
	_check("the spring settles on its target with little overshoot (%.4f, peak %.4f)" % [slam.amount, peak],
		absf(slam.amount - 0.2) < 0.002 and peak < 0.24)
	slam.aim_at(Vector3(0.6, 0.0, 0.8), 0.0)
	var slow := slam.offset(1.0, 1.0)
	slam.aim_at(Vector3(0.0, 0.0, 1.0), 8.0)
	var fast := slam.offset(1.0, 1.0)
	_check("a slow angled approach nudges up and sideways (%s)" % str(slow.origin), slow.origin.y > 0.01 and absf(slow.origin.x) > 0.01)
	_check("a fast head-on sprint pushes back harder with no nudge (%.3f vs %.3f)" % [fast.origin.z, slow.origin.z],
		fast.origin.z > slow.origin.z and absf(fast.origin.x) < 0.001 and fast.origin.y < 0.001)
	var aimed := slam.offset(1.0, 1.0, 1.0, 0.6, 1.0)
	_check("fully aimed the gun is not moved off the sight line", aimed.origin.is_zero_approx() and aimed.basis.is_equal_approx(Basis.IDENTITY))


func _wall_slam_person(view: ZeeViewModel, surface: float) -> void:
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

	var reach := rest / 2.0
	wall.position = Vector3(0.0, 0.0, -(rest * 0.8 + 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("a wall short of the drawn muzzle but past the gun's real reach pushes nothing (%.3f m, reach %.2f)" % [view.wall_amount(), reach],
		view.wall_amount() == 0.0)

	var surface := reach - 0.12
	wall.position = Vector3(0.0, 0.0, -(surface + 0.5))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(60):
		view.advance(1.0 / 60.0)
	var slammed := -(camera.global_transform.affine_inverse() * view.muzzle_transform().origin).z
	_check("a wall inside the real reach retracts the weapon (%.3f m)" % view.wall_amount(), view.wall_amount() > 0.05)
	_check("and the gun is drawn back (%.3f of %.3f)" % [slammed, rest], slammed < rest - 0.05)
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

	await _wall_slam_person(view, surface)

	_wall_obstruction_maths()

	# A floor under a low eye (crouch, slide) is not an obstacle unless the view looks down at it.
	wall.position = Vector3(0.0, 0.0, -100.0)
	var floor_body := StaticBody3D.new()
	var fbox := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(40.0, 1.0, 40.0)
	fbox.shape = fshape
	floor_body.add_child(fbox)
	floor_body.position = Vector3(0.0, -0.2 - 0.5, 0.0)
	add_child(floor_body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("a floor just below a level view does not move the gun (%.3f m)" % view.wall_amount(), view.wall_amount() == 0.0)
	camera.rotation_degrees.x = -75.0
	for i in range(60):
		view.advance(1.0 / 60.0)
	_check("looking down at it, the floor is an obstacle (%.3f m)" % view.wall_amount(), view.wall_amount() > 0.03)
	camera.rotation_degrees.x = 0.0
	floor_body.queue_free()

	_wall_slam_response()
	camera.queue_free()
	wall.queue_free()
	_end()


## The gun leans away from where it meets the wall and eases in with depth.
func _near_plane() -> void:
	_begin("a hand never comes through the near plane")
	var camera := Camera3D.new()
	add_child(camera)
	var view := ZeeViewModel.new()
	camera.add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"charge_rifle"))
	for i in range(30):
		view.advance(1.0 / 60.0)
	var floor_m := camera.near + ZeeViewModel.NEAR_CLEAR
	var rest: float = view._arms.nearest_hand_depth(camera.global_transform)
	_check("hands at rest are clear of the near plane (%.3f m past it)" % (rest - camera.near), rest >= floor_m)
	view._animated.global_position += camera.global_basis.z * (rest - camera.near + 0.04)
	var pressed: float = view._arms.nearest_hand_depth(camera.global_transform)
	_check("a hand pressed to the lens is through it (%.3f m)" % pressed, pressed < camera.near)
	view._keep_off_near_plane()
	var after: float = view._arms.nearest_hand_depth(camera.global_transform)
	_check("it is slid back past the near plane and margin (%.3f m)" % after, after >= floor_m - 0.0001)
	var again := view._animated.global_position
	view._keep_off_near_plane()
	_check("and a model already clear is left where it is", view._animated.global_position.is_equal_approx(again))
	_end()


func _wall_lean() -> void:
	_begin("the view model leans by where it meets the wall")
	var camera := Camera3D.new()
	add_child(camera)
	var view := ZeeViewModel.new()
	view.show_arms = false
	camera.add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"rifle"))
	for i in range(150):
		view.advance(1.0 / 60.0)
	var mz := camera.global_transform.affine_inverse() * view.muzzle_transform().origin
	var rest := -(camera.global_transform.affine_inverse() * view.muzzle_transform().origin).z
	var reach := rest / 2.0
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	box.shape = shape
	wall.add_child(box)
	add_child(wall)
	var settle := func(size: Vector3, centre: Vector3) -> void:
		shape.size = size
		wall.position = centre
		await get_tree().physics_frame
		await get_tree().physics_frame
		for i in range(90):
			view.advance(1.0 / 60.0)
	# Graded: five distances, each deeper than the last, and the tilt follows without a jump.
	var depths := []
	var tips := []
	for d in [0.9, 0.75, 0.6, 0.45, 0.3]:
		var surface: float = reach * d
		await settle.call(Vector3(20, 20, 1), Vector3(0, 0, -(surface + 0.5)))
		depths.append(view.wall_amount())
		tips.append(view.muzzle_transform().basis * Vector3.FORWARD)
	var graded := true
	for i in range(1, depths.size()):
		graded = graded and depths[i] >= depths[i - 1] - 0.001
	_check("a closer wall pushes deeper in steps (%s)" % str(depths.map(func(x: float) -> String: return "%.3f" % x)), graded and depths[4] > depths[1] + 0.03)
	_check("the first bump is slight (%.3f vs %.3f)" % [depths[0], depths[4]], depths[0] < depths[4] * 0.5)
	_check("a head-on wall tips the barrel up, more when closer (%.3f -> %.3f)" % [tips[1].y, tips[4].y], tips[4].y > tips[1].y)
	# Direction: the wall meets only part of the gun.
	var deep: float = reach * 0.45 + 0.5
	await settle.call(Vector3(20, 20, 1), Vector3(0, 0, -deep))
	var full := view.wall_lean()
	var edge_y: float = mz.y / -mz.z * (deep - 0.5)
	var edge_x: float = mz.x / -mz.z * (deep - 0.5)
	await settle.call(Vector3(20, 10, 1), Vector3(0, edge_y - 5.0, -deep))
	var low := view.wall_lean()
	await settle.call(Vector3(20, 10, 1), Vector3(0, edge_y + 5.0, -deep))
	var high := view.wall_lean()
	_check("a wall meeting only the lower part tips up more than the whole (%.2f vs %.2f)" % [low.y, full.y], low.y > full.y + 0.1)
	_check("a wall meeting only the upper part dips the barrel (%.2f)" % high.y, high.y < full.y - 0.3 and high.y < low.y)
	await settle.call(Vector3(10, 20, 1), Vector3(edge_x + 5.0, 0, -deep))
	var on_right := view.wall_lean()
	await settle.call(Vector3(10, 20, 1), Vector3(edge_x - 5.0, 0, -deep))
	var on_left := view.wall_lean()
	_check("a wall on the right turns the barrel left, on the left right (%.2f / %.2f)" % [on_right.x, on_left.x], on_right.x > on_left.x + 0.4 and on_right.x > 0.0 and on_left.x < 0.0)
	var slam := ZeeWallSlam.new()
	slam.amount = 0.2
	slam.set_lean({"up": 0.3, "down": 0.0, "left": 0.0, "right": 0.2}, Vector2(0.1, -0.1))
	for i in range(60):
		slam.step(0.2, 1.0 / 60.0)
	var aimed := slam.offset(1.0, 1.0, 1.0, 0.6, 1.0)
	_check("fully aimed the lean moves nothing", aimed.origin.is_zero_approx() and aimed.basis.is_equal_approx(Basis.IDENTITY))
	var hip := slam.offset(1.0, 1.0)
	_check("a lean toward up-left on the right shows as a dip and a left turn (%s)" % str(slam.lean), slam.lean.y < 0.0 and slam.lean.x > 0.0 and hip.basis != Basis.IDENTITY)
	slam.set_lean({"up": 0.3, "down": 0.0, "left": 0.0, "right": 0.2}, Vector2(0.1, -0.1), 0.0)
	_check("lean 0 keeps the plain tilt up", slam.offset(1.0, 1.0).basis.get_euler().x > 0.0)
	camera.queue_free()
	wall.queue_free()
	_end()


## A server rig with no view model sends a shot along the barrel a wall has pushed, from the carrier's own state alone.
func _wall_barrel_tilt(rig: ZeeWeaponRig, ctx: DotWeaponContext, art: ZeeWeaponArt) -> void:
	var faster := rig.wall_barrel(ctx.origin, Vector3.FORWARD, art, 6.0, 0.0)
	var slower := rig.wall_barrel(ctx.origin, Vector3.FORWARD, art, 0.0, 0.0)
	_check("a faster approach pushes back harder and tilts less", faster != slower and (faster * Vector3.FORWARD).y < (slower * Vector3.FORWARD).y)
	var strafing := rig.wall_barrel(ctx.origin, Vector3.FORWARD, art, 0.0, 0.0, 4.0)
	_check("strafing into the wall tilts the shot as it tilts the drawn gun", strafing != slower)
	var via_extra := DotWeaponContext.new()
	via_extra.origin = ctx.origin
	via_extra.direction = Vector3.FORWARD
	via_extra.extra[&"strafe"] = 4.0
	rig._aim_along_wall_barrel(via_extra)
	var via_arg := Basis.looking_at(Vector3.FORWARD) * (strafing * Vector3.FORWARD)
	_check("a server hands the strafe in the context and gets the same shot", via_extra.direction.is_equal_approx(via_arg.normalized()))
	rig.drive_view(Vector2.ZERO, 0.0, true, false, 4.0)
	var via_drive := DotWeaponContext.new()
	via_drive.origin = ctx.origin
	via_drive.direction = Vector3.FORWARD
	rig._aim_along_wall_barrel(via_drive)
	_check("the strafe given to drive_view is the strafe the shot tilts with", via_drive.direction.is_equal_approx(via_extra.direction))
	rig.drive_view(Vector2.ZERO, 0.0, true, false, 0.0)
	_check("aimed fully the barrel stays on the sight line", rig.wall_barrel(ctx.origin, Vector3.FORWARD, art, 0.0, 1.0).is_equal_approx(Basis.IDENTITY))
	rig.ads_rules.set_def_row(art.id, {"wall_shot": false})
	ctx.direction = Vector3.FORWARD
	rig._aim_along_wall_barrel(ctx)
	_check("a profile with wall_shot off keeps the crosshair line", ctx.direction.is_equal_approx(Vector3.FORWARD))


func _wall_barrel() -> void:
	_begin("a shot follows the barrel a wall has pushed")
	var carrier := CharacterBody3D.new()
	var body := CollisionShape3D.new()
	body.shape = CapsuleShape3D.new()
	carrier.add_child(body)
	add_child(carrier)
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	rig.ads_rules = ZeeAdsRules.new()
	carrier.add_child(rig)
	_check("the server rig sets up", rig.setup().ok)
	var _given := rig.give(ZeeWeaponIds.RIFLE)
	rig.arsenal.select(rig.arsenal.catalogue.get_def(ZeeWeaponIds.RIFLE).slot, 0)
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 20, 1)
	box.shape = shape
	wall.add_child(box)
	add_child(wall)
	var art := rig.current_art()
	var reach := ZeeWallSlam.reach_of(art.hip_muzzle().length(), ZeeAdsRules.new().view_scale_for(art.id), 1.0)
	var ctx := DotWeaponContext.new()
	ctx.origin = Vector3(0, 1, 0)
	ctx.direction = Vector3.FORWARD
	wall.position = Vector3(0, 1, -(reach * 4.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	rig._aim_along_wall_barrel(ctx)
	_check("open air leaves the shot on the crosshair line", ctx.direction.is_equal_approx(Vector3.FORWARD))
	var tips := []
	for f in [0.8, 0.5, 0.3]:
		wall.position = Vector3(0, 1, -(reach * f + 0.5))
		await get_tree().physics_frame
		await get_tree().physics_frame
		ctx.direction = Vector3.FORWARD
		rig._aim_along_wall_barrel(ctx)
		tips.append(ctx.direction)
	_check("a wall inside the reach lifts the shot above the crosshair (%.3f)" % tips[1].y, tips[1].y > 0.01)
	_check("a closer wall lifts it more (%.3f -> %.3f)" % [tips[0].y, tips[2].y], tips[2].y > tips[0].y)
	_check("the turned direction is a unit vector", is_equal_approx(tips[2].length(), 1.0))
	ctx.direction = Vector3.FORWARD
	var again := DotWeaponContext.new()
	again.origin = ctx.origin
	again.direction = Vector3.FORWARD
	rig._aim_along_wall_barrel(ctx)
	rig._aim_along_wall_barrel(again)
	_check("the same state gives the same shot, so a client and a server agree", ctx.direction.is_equal_approx(again.direction))
	_wall_barrel_tilt(rig, ctx, art)
	wall.position = Vector3.ZERO
	carrier.queue_free()
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
		camera.position.z = maxf(-0.1 * i, -2.82)
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
