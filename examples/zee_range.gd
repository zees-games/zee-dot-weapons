extends "res://examples/zee_range_world.gd"

## A firing range you can walk around, holding every weapon in the pack: `godot --path . res://examples/zee_range.tscn`.
## Options after `--`: `--seconds N --weapon ID --fire --capture DIR --sheet DIR --dummy`. WASD, space, ctrl, mouse, R, 1-5, Q, wheel; F1 dumps the rig.
## The half of the suite no assertion reaches: look at it (`tools/screenshot.sh`). It sets no [DotNodeRef]s; the defaults find everything by type.

const CHANNEL := "zee.range"

## Where the player stands, far enough back that a target is a shot rather than a poke.
const SPAWN := Vector3(0.0, 0.2, 14.0)

@onready var _controller: DotFpsController = $Player/Controller
@onready var _camera: Camera3D = $Player/Head/Camera
@onready var _readout: Label = $UI/Readout
@onready var _crosshair: Label = $UI/Crosshair

var _rig: ZeeWeaponRig = null
var _view: ZeeViewModel = null

## The scope drawn over the screen at full aim with a scoped weapon.
var _scope: ZeeScopeOverlay = null

## `--aim` holds the aim for the whole run, so a capture shows the aimed pose.
var _always_aim: bool = false
var _input := ZeeWeaponInput.make()

## The simulation tick. Advanced in `_physics_process`, never read from a clock.
var _tick: int = 0

## Whether `--fire` was passed.
var _auto_fire: bool = false

## Whether a `--capture` sequence has started.
var _capturing: bool = false

## Whether `--sheet` is running: the range stops simulating and driving the view itself,
## and [method _run_sheet] steps the view model by hand.
var _sheet: bool = false

## The simulation tick the sheet's own shots are fired on, clear of the range's.
var _sheet_tick: int = 100000

## Every shot's impact, drawn as a short-lived marker so a hit is visible.
var _markers: Array[Node3D] = []


func _ready() -> void:
	ZeeWeaponInput.register_default_actions()
	# `--pack <spawn_provider.gd>`: another pack's weapons join the range, dressed in its own models.
	var pack := _argument("--pack")
	if pack != "" and ResourceLoader.exists(pack):
		var provider := load(pack) as Script
		ZeePackSource.register(&"range_pack", provider, Callable(provider, &"weapon_defs"))
	_auto_fire = OS.get_cmdline_user_args().has("--fire")
	_build_world()
	_build_weapons()
	_arm_exit_timer()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_controller.landed.connect(_on_landed)
	_controller.teleport(SPAWN, 0.0, 0.0)

	# `--wall [--wall-yaw DEG]`: the capsule pressed against the back wall, turned DEG off square, to see whether the view model clips it.
	if OS.get_cmdline_user_args().has("--wall"):
		var yaw := deg_to_rad(_argument("--wall-yaw").to_float())
		_controller.teleport(Vector3(0.0, 0.0, -17.5 + 0.36), yaw, 0.0)

	# `--dark`: no sun and almost no ambient, so only a muzzle light lights the wall beside the player.
	if OS.get_cmdline_user_args().has("--dark"):
		(get_node("Sun") as DirectionalLight3D).light_energy = 0.0
		(get_node("Environment") as WorldEnvironment).environment.ambient_light_energy = 0.03

	_crosshair.text = "+"

	print("zee-dot-weapons range — %d weapons" % ZeeWeaponIds.all().size())
	print("1-5 slots · wheel cycles · LMB fire · RMB bash · R reload · F1 state")

	_equip_requested()

	if OS.get_cmdline_user_args().has("--dummy"):
		_add_dummy()

	if _argument("--sheet") != "":
		_run_sheet(_argument("--sheet"))
	# `--still PATH`: one frame saved by the range itself three seconds in, then quit (a box with no screen grabber).
	if _argument("--still") != "":
		get_tree().create_timer(3.0).timeout.connect(_save_still)


## `--dummy`: a character standing in the line of fire, so a capture shows a shot landing on a
## body (ZeeShotFx's red burst) rather than on the far wall.
func _add_dummy() -> void:
	var body := CharacterBody3D.new()
	body.name = "Dummy"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var look := CapsuleMesh.new()
	look.radius = 0.35
	look.height = 1.8
	mesh.mesh = look
	mesh.material_override = _material(Color(0.55, 0.62, 0.72))
	body.add_child(mesh)
	$World.add_child(body)
	var eye := _controller.eye_transform()
	var ahead := -eye.basis.z
	ahead.y = 0.0
	body.global_position = eye.origin + ahead.normalized() * 6.0 + Vector3(0.0, -0.75, 0.0)


func _build_weapons() -> void:
	# The view model hangs off the camera, which is what makes it a view model: it
	# inherits the camera's pitch for free and needs no code to follow it.
	_view = ZeeViewModel.new()
	_view.name = "ViewModel"
	_view.arm_skin = "res://assets/arms/Textures/texture-c.png"
	# `--no-arms` draws the weapon alone. Not a debug toggle left in by accident: it is
	# how you tell an arm drawn wrongly from a weapon drawn wrongly, and the two look
	# identical in a screenshot until one of them is switched off.
	_view.show_arms = _argument("--no-arms") == ""
	# `--ads-rules` draws with the layered aiming rules (size, place, zoom) a game would assign.
	if OS.get_cmdline_user_args().has("--ads-rules"):
		_view.ads_rules = ZeeAdsRules.load_config()
	_camera.add_child(_view)

	_always_aim = OS.get_cmdline_user_args().has("--aim")
	var layer := CanvasLayer.new()
	add_child(layer)
	_scope = ZeeScopeOverlay.new()
	layer.add_child(_scope)

	_rig = ZeeWeaponRig.new()
	_rig.name = "WeaponRig"
	_rig.role = ZeeWeaponRig.Role.LOCAL
	_rig.ads_rules = _view.ads_rules
	# A single-player range is its own authority. A client joining a server would set
	# this false and let the server's copy of the same rig decide.
	_rig.authority = true
	_rig.tick_rate = ZeeWeaponPack.TICK_RATE
	_rig.view_model_ref = DotNodeRef.of_path(_view.get_path())
	$Player.add_child(_rig)

	var res := _rig.setup()

	if not res.ok:
		DotLog.error(CHANNEL, "the rig would not set up", {"why": res.error.message})
		return

	_rig.give_everything()
	_rig.used.connect(_on_used)
	_rig.bashed.connect(_on_used)
	_rig.equipped.connect(_on_equipped)


## Honours `--weapon <id>` so a screenshot sweep can ask for one by name.
func _equip_requested() -> void:
	var wanted := _argument("--weapon")

	if wanted == "":
		return

	var def: DotWeaponDef = ZeeWeaponPack.table().get(StringName(wanted), null)

	if def == null:
		DotLog.warn(CHANNEL, "no such weapon", {"asked_for": wanted})
		return

	# Forced rather than requested: a switch takes deploy_ticks to finish, and a
	# screenshot three seconds later of a weapon that is still coming up is a screenshot
	# of the bottom of the screen.
	_rig.arsenal.give(def.id)
	_rig.arsenal.select(def.slot, 0)

	for i in range(200):
		_rig.simulate_tick(DotWeaponCommand.new(), i)


func _process(_delta: float) -> void:
	if _sheet:
		return

	_input.sample()

	var state := _controller.render_state()

	# [b]The view is driven every render frame, not every tick.[/b] Sway and bob are
	# interpolation between ticks; doing them on the tick quantises them to the tick rate
	# and undoes the point of having them.
	_rig.drive_view(
		Vector2(state.yaw, state.pitch),
		Vector2(state.velocity.x, state.velocity.z).length(),
		state.mode != DotFpsState.Mode.AIR,
		state.crouch_fraction > 0.5
	)

	# The camera's half of the recoil. Through the view's own offset, because the view
	# writes the camera's angles from scratch every frame and would undo anything set here.
	if _controller.view != null:
		var punch := _rig.view_punch()
		_controller.view.external_angles = Vector3(punch.x, punch.y, 0.0)

	# Right mouse aims, as a game would wire it: the view model eases and draws, the camera
	# takes the zoom, the HUD takes the scope.
	_view.aim(_always_aim or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if _controller.view != null:
		_controller.view.external_fov_scale = _view.aim_fov_scale()
	_scope.follow(_view)

	_draw_readout()


func _physics_process(_delta: float) -> void:
	if _sheet:
		return

	_tick += 1

	var state := _controller.render_state()

	# [b]Copied from the movement, never sampled again.[/b] Two samples of the same mouse
	# a frame apart differ, and a shot fired along an angle the movement never had is a
	# shot that leaves the muzzle somewhere the player was not looking.
	_input.set_aim(state.yaw, state.pitch)

	var command := _input.take(8)

	# `--fire` pulls the trigger on its own, pressed and released every few ticks so a
	# semi-automatic fires too: a screenshot taken at a fixed second then catches a shot in
	# flight, which is the only way a machine with no hands sees a tracer.
	if _auto_fire:
		command.set_button(DotWeaponCommand.BUTTON_ATTACK, (_tick / 6) % 2 == 0)

	# [b]The shot leaves the controller's eye, handed over explicitly.[/b] This rig has no
	# player_ref — the range's player is a bare body with no `component()` for the bridge
	# to ask — so left to build its own context it fired every shot from the world origin
	# along -Z, the bug `ZeeWeaponRig._resolve_carrier` documents for servers. Nobody saw it
	# for as long as the range existed because the targets sit on that axis: the hit marks
	# landed where a player aiming straight ahead expected them. The first tracer drawn
	# showed it, running from the gun to the floor under the player's feet.
	#
	# The eye, not the camera: the camera carries the recoil punch and the landing dip, and
	# a shot aimed along those would make presentation part of where a bullet goes.
	var eye := _controller.eye_transform()
	var ctx := DotWeaponContext.make(1, _tick, eye.origin, -eye.basis.z)
	var outcome := _rig.simulate_tick(command, _tick, ctx)

	# The range is its own authority, so it resolves its own shots. A client would send
	# the command and let the server do this.
	for shot in outcome.shots:
		_trace(shot)

	for spawn in outcome.spawns:
		_launch(spawn)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).physical_keycode == KEY_F1:
			for line in _rig.describe_lines():
				print(line)


func _on_used(outcome: DotWeaponOutcome) -> void:
	_capture_shot()

	# Nothing here may run on a replayed tick, and nothing here is replayed: a range is
	# its own authority so there is nothing to reconcile. In a networked game this is
	# where `ctx.replayed` earns its keep.
	if outcome.kind == DotWeaponOutcome.KIND_SWING:
		return


func _on_equipped(id: StringName) -> void:
	var def: DotWeaponDef = ZeeWeaponPack.table().get(id, null)

	if def != null:
		print("equipped %s" % def.name_or_id())


func _on_landed(impact: float) -> void:
	_rig.on_landed(impact)


## Traces one shot and marks where it landed.
##
## [b]A range, not a combat system.[/b] dot-combat is what resolves a shot properly —
## hitboxes, hit groups, lag compensation, armour — and this pack does not depend on it
## for anything but its [DotShot] type. What this does is put a mark on a wall so you can
## see where the pellets went, which is the only question a firing range asks.
func _trace(shot: DotShot) -> void:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state

	for pellet in shot.pellets:
		var query := PhysicsRayQueryParameters3D.create(
			shot.origin, shot.origin + pellet * shot.max_range
		)
		query.collide_with_areas = false

		var hit: Dictionary = space.intersect_ray(query)

		if hit.is_empty():
			continue

		_mark(hit["position"] as Vector3)


## A projectile, as the simplest thing that can possibly fly.
func _launch(spawn: DotWeaponSpawn) -> void:
	var body := RigidBody3D.new()
	var mesh := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	var ball := SphereMesh.new()

	sphere.radius = maxf(0.05, spawn.radius)
	ball.radius = sphere.radius
	ball.height = sphere.radius * 2.0

	shape.shape = sphere
	mesh.mesh = ball
	mesh.material_override = _material(Color(1.0, 0.55, 0.15))

	body.add_child(shape)
	body.add_child(mesh)
	body.gravity_scale = spawn.gravity_scale
	body.position = spawn.origin
	body.linear_velocity = spawn.velocity

	$World.add_child(body)

	# The spawn's own life is a hard ceiling rather than a hint: a projectile that
	# forgets to free itself is a leak that looks like a slow problem in the game rather
	# than a bug in one weapon.
	var timer := get_tree().create_timer(
		float(spawn.life_ticks) / float(ZeeWeaponPack.TICK_RATE)
	)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(body):
			_mark(body.global_position)
			body.queue_free()
	)


func _mark(at: Vector3) -> void:
	var dot := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	dot.mesh = sphere
	dot.material_override = _material(Color(1.0, 0.85, 0.2))
	dot.position = at
	$World.add_child(dot)

	_markers.append(dot)

	# Bounded rather than timed: at eleven hundred rounds a minute a timed cleanup still
	# leaves a few thousand markers on screen, and the frame rate is what tells you.
	while _markers.size() > 200:
		var oldest: Node3D = _markers.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _draw_readout() -> void:
	var def := _rig.current_def()

	if def == null:
		_readout.text = "nothing in hand"
		return

	var slot := _rig.arsenal.current()
	var ammo := _rig.arsenal.ammo().count(def.ammo_type)

	var rounds := "∞"

	if def.uses_magazine():
		rounds = "%d / %d" % [slot.magazine, ammo]
	elif def.uses_ammo():
		rounds = str(ammo)

	_readout.text = "%s\n%s\n%s%s" % [
		def.name_or_id(),
		rounds,
		DotWeaponDef.Fire.keys()[def.fire_mode].to_lower(),
		"  ·  reloading" if _rig.arsenal.is_reloading() else "",
	]


## With `--capture prefix`, saves the frames just after the first shot and quits.
##
## [b]Counted from the shot, not from the clock.[/b] A screenshot taken at a fixed second
## under a software renderer lands wherever the start-up happened to leave it — usually
## mid-reload, with the magazine already emptied — and a tracer lives a tenth of a second.
func _capture_shot() -> void:
	var prefix := _argument("--capture")

	if prefix == "" or _capturing:
		return

	_capturing = true

	# A software renderer draws a frame every tenth of a second or so, and a tracer lives
	# about that long: at full speed the capture shows the flash and nothing after it.
	# Slowed twenty times, the frames are a flip-book of the shot.
	Engine.time_scale = 0.05

	var frame := 0
	for wanted in [1, 2, 3, 5, 8, 14]:
		while frame < wanted:
			await RenderingServer.frame_post_draw
			frame += 1
		var path := "%s_%02d.png" % [prefix, wanted]
		var err := get_viewport().get_texture().get_image().save_png(path)
		print("captured %s (%s)" % [path, error_string(err)])

	get_tree().quit()


## The frames of one weapon's contact sheet, in order: a label and what to do before it.
##
## [b]Why a sheet and not a screenshot.[/b] A view model is motion, and one frame of it at
## rest says nothing about the reload, the kick or the sway, which are where every
## complaint about this pack's hands came from (a reload that pointed the gun at the sky,
## a kick nobody could see). Eighteen frames on one image are a review a person can do in
## a glance, and the same sixteen every time, so a before and an after can be laid side by
## side.
const SHEET_FRAMES := [
	["hip", "rest"], ["aimed", "aim"],
	["fire 1", "fire:1"], ["fire 2", "fire:2"], ["fire 4", "fire:4"],
	["fire 8", "fire:8"], ["fire 14", "fire:14"],
	["reload 0%", "reload:0.0"], ["reload 25%", "reload:0.25"],
	["reload 50%", "reload:0.5"], ["reload 75%", "reload:0.75"],
	["reload 90%", "reload:0.9"],
	["walking", "walk"], ["turning right", "turn"],
	["draw 30%", "deploy:0.3"], ["draw 70%", "deploy:0.7"],
	["in shade", "shade"], ["aimed, fire 4", "aimfire:4"],
]

## `--moves`: how the weapon moves with its carrier, hip and aimed. Review on this after
## touching sway, tilt, bob or the landing.
const MOVE_FRAMES := [
	["hip", "rest"], ["aimed", "aim"],
	["strafe right", "strafe:5"], ["strafe left", "strafe:-5"],
	["aimed, strafe right", "aimstrafe:5"], ["aimed, strafe left", "aimstrafe:-5"],
	["turning right", "turn"], ["aimed, turning right", "aimturn"],
	["walking", "walk"], ["aimed, walking", "aimwalk"],
	["landing", "land"], ["aimed, landing", "aimland"],
	["sprint, stride low", "sprint:30"], ["sprint, stride high", "sprint:45"],
]

## The fixed step the sheet advances the view model by: 60 frames a second, so "fire 4"
## is 67 ms after the shot on any machine and under any renderer.
const SHEET_STEP := 1.0 / 60.0


## Renders [constant SHEET_FRAMES] to `<prefix>_NN.png` and quits.
##
## [b]The view model is stepped by hand.[/b] Its own `_process` is switched off and
## [method ZeeViewModel.advance] is called with [constant SHEET_STEP], so what a frame shows
## depends on the number of steps and not on how fast a software renderer happens to draw.
## The range stops simulating too: the rig would otherwise push its own reload and deploy
## fractions over the ones the sheet sets.
func _run_sheet(prefix: String) -> void:
	_sheet_setup()

	var def := _rig.current_def()
	var recoil := Vector2(0.5, 0.1)
	if def != null and def.tuning != null and "recoil_pitch" in def.tuning:
		recoil = Vector2(def.tuning.get("recoil_pitch"), def.tuning.get("recoil_yaw"))
	_sheet_hold(def)

	# `--frames 0,2,9` renders only those frames of the sheet.
	var only := _argument("--frames").split_floats(",") if _argument("--frames") != "" else PackedFloat64Array()

	# A second to let the art load and the first frames settle.
	for i in range(30):
		await RenderingServer.frame_post_draw

	# `--reloads 0.1,0.3,0.5` renders a reload frame at each fraction instead: a whole reload on
	# one sheet, which the sheet's five reload frames cannot show for a gun fed a round at a time.
	var frames: Array = SHEET_FRAMES
	if OS.get_cmdline_user_args().has("--moves"):
		frames = MOVE_FRAMES
	# `--wallsheet`: five wall distances in four directions (head-on, wall only below, only above, only on the right).
	if OS.get_cmdline_user_args().has("--wallsheet"):
		frames = []
		for kind: String in ["full", "below", "above", "right"]:
			for d: float in [0.9, 0.7, 0.55, 0.4, 0.28]:
				frames.append(["wall %s %.0f%%" % [kind, d * 100.0], "wall:%f:%s" % [d, kind]])
	if _argument("--reloads") != "":
		frames = []
		for fraction in _argument("--reloads").split_floats(","):
			frames.append(["reload %d%%" % roundi(fraction * 100.0), "reload:%f" % fraction])

	# `--aimin 2,4,6` renders the sights coming up after that many 60 fps steps: the quick scope's transition.
	if _argument("--aimin") != "":
		frames = []
		for steps in _argument("--aimin").split_floats(","):
			frames.append(["aim-in %d" % int(steps), "aimin:%f" % steps])

	var roof: Node3D = null
	for n in range(frames.size()):
		if not only.is_empty() and not only.has(float(n)):
			continue
		var label: String = frames[n][0]
		var step: String = frames[n][1]
		_sheet_reset()
		var parts := step.split(":")
		var arg := parts[1].to_float() if parts.size() > 1 else 0.0

		match parts[0]:
			"rest":
				_sheet_steps(30)
			"aim":
				_view.aim(true)
				_sheet_steps(40)
			"aimin":
				_view.aim(true)
				_sheet_steps(int(arg))
			"fire":
				_sheet_steps(10)
				_sheet_fire(recoil)
				_sheet_steps(int(arg))
			"reload":
				# `--aimed` holds the aim button through the reload: a player reloading with
				# the button down, which the hip-only frames never showed.
				if OS.get_cmdline_user_args().has("--aimed"):
					_view.aim(true)
					_sheet_steps(40)
				_view.on_reload(arg)
				_sheet_steps(30 if OS.get_cmdline_user_args().has("--aimed") else 2)
			"walk":
				# A quarter of a stride past a footfall, where the bob is furthest out.
				for i in range(27):
					_view.drive(Vector2.ZERO, 5.0, true)
					_view.advance(SHEET_STEP)
			"sprint":
				_view.set_sprinting(true)
				for i in range(int(arg)):
					_view.drive(Vector2.ZERO, 8.0, true)
					_view.advance(SHEET_STEP)
				_view.set_sprinting(false)
			"turn":
				# 180 degrees a second to the right, for a fifth of a second.
				for i in range(12):
					_view.drive(Vector2(-3.0 * float(i + 1), 0.0), 0.0, true)
					_view.advance(SHEET_STEP)
			"strafe", "aimstrafe":
				_view.aim(parts[0] == "aimstrafe")
				for i in range(40):
					_view.drive(Vector2.ZERO, absf(arg), true, false, arg)
					_view.advance(SHEET_STEP)
			"aimturn":
				_view.aim(true)
				_sheet_steps(40)
				for i in range(12):
					_view.drive(Vector2(-3.0 * float(i + 1), 0.0), 0.0, true)
					_view.advance(SHEET_STEP)
			"aimwalk":
				_view.aim(true)
				_sheet_steps(40)
				for i in range(27):
					_view.drive(Vector2.ZERO, 5.0, true)
					_view.advance(SHEET_STEP)
			"land", "aimland":
				_view.aim(parts[0] == "aimland")
				_sheet_steps(40)
				_view.on_landed(9.0)
				_sheet_steps(3)
			"deploy":
				_view.on_deploy(arg)
				_sheet_steps(2)
			"shade":
				# A roof between the sun and the player: the view model must look exactly as
				# it does in the open, because the world's shadow map is not its business.
				roof = _sheet_roof()
				_sheet_steps(30)
			"wall":
				_sheet_steps(60)
				await _sheet_wall(arg, parts[2])
			"aimfire":
				_view.aim(true)
				_sheet_steps(40)
				_sheet_fire(recoil)
				_sheet_steps(int(arg))

		var weapon := String(def.id) if def != null else "?"
		_readout.text = "%s  ·  %s" % [weapon, label]
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s_%02d.png" % [prefix, n]
		var err := get_viewport().get_texture().get_image().save_png(path)
		if err != OK:
			printerr("could not save %s: %s" % [path, error_string(err)])
		if roof != null:
			roof.queue_free()
			roof = null
		if _sheet_wall_body != null:
			_sheet_wall_body.queue_free()
			_sheet_wall_body = null

	print("sheet: %d frames at %s_NN.png" % [frames.size(), prefix])
	get_tree().quit()


var _sheet_wall_body: StaticBody3D = null


## A wall [param share] of the gun's real reach in front of the eye, covering all of the view or only a side of the muzzle's line.
func _sheet_wall(share: float, kind: String) -> void:
	var cam := _view.get_parent() as Node3D
	var to_muzzle := cam.global_transform.affine_inverse() * _view.muzzle_transform().origin
	var reach := ZeeWallSlam.reach_of(to_muzzle.length(), ZeeAdsRules.new().view_scale_for(&"rifle"), 1.0)
	var dist := reach * share
	var edge := Vector2(to_muzzle.x, to_muzzle.y) / maxf(-to_muzzle.z, 0.05) * dist
	var size := Vector3(40.0, 40.0, 1.0)
	var at := Vector3(0.0, 0.0, -(dist + 0.5))
	match kind:
		"below":
			at.y = edge.y - 20.0
		"above":
			at.y = edge.y + 20.0
		"right":
			at.x = edge.x + 20.0
	_sheet_wall_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_sheet_wall_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = size
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.42)
	mesh.material_override = mat
	_sheet_wall_body.add_child(mesh)
	cam.add_child(_sheet_wall_body)
	_sheet_wall_body.position = at
	await get_tree().physics_frame
	await get_tree().physics_frame
	_sheet_steps(90)


func _sheet_setup() -> void:
	_sheet = true
	_view.set_process(false)
	# The shot's effects are stepped with the view model, or a flash that lives three frames
	# at 60 fps is gone before a software renderer has drawn one.
	if _rig.shot_fx() != null:
		_rig.shot_fx().set_process(false)
	# Read at a quarter of the size on the tiled sheet, so the label is drawn large.
	_readout.add_theme_font_size_override("font_size", 52)
	_crosshair.add_theme_font_size_override("font_size", 48)
	# Grown both ways from the centre: the scene's box is sized for 24 px, and a 48 px "+" grew
	# it downward only, drawing the crosshair 15 px under the screen's centre, below a sight
	# that was on it.
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH


func _sheet_hold(def: DotWeaponDef) -> void:
	# `--hold "x,y,z,pitch,yaw,roll,scale"` re-equips the weapon with that first-person
	# placement instead of the table's: the knob for tuning a hold without an edit and a
	# re-import per guess. The numbers that look right then go into ZeeWeaponArtTable.
	var hold := _argument("--hold")
	if hold != "" and def != null:
		var art: ZeeWeaponArt = ZeeWeaponArtTable.get_art(def.id).duplicate(true)
		var v := hold.split_floats(",")
		if v.size() >= 3:
			art.view_offset = Vector3(v[0], v[1], v[2])
		if v.size() >= 6:
			art.view_rotation = Vector3(v[3], v[4], v[5])
		if v.size() >= 7:
			art.view_scale = v[6]
		_view.equip(art)



## A slab over the player on the sun's side, so the player stands in its shadow.
func _sheet_roof() -> Node3D:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var toward := sun.global_transform.basis.z.normalized() if sun != null else Vector3.UP
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 0.2, 5.0)
	mesh.mesh = box
	mesh.material_override = _material(Color(0.3, 0.3, 0.32))
	body.add_child(mesh)
	$World.add_child(body)
	body.global_position = _camera.global_position + toward * 3.0
	return body


## Back to rest between frames, so each one shows only what its own step did.
func _sheet_reset() -> void:
	_view.on_reset()
	_view.aim(false)
	_view.on_reload(0.0)
	_view.on_deploy(1.0)
	_view.drive(Vector2.ZERO, 0.0, true)
	_sheet_steps(1)


## Pulls the trigger through the rig, as a game does: the use reaches the view model (the kick,
## a melee swing, a throw) and the shot's effects (the flash, the tracer, the impact and its
## mark), so the fire frames show what a player sees and not the kick alone. The magazine is
## topped up first, so a two-round gun has a round for each fire frame. A weapon that will not
## go off in half a second of held trigger and its release falls back to the kick.
func _sheet_fire(recoil: Vector2) -> void:
	var held := _rig.arsenal.current() if _rig.arsenal != null else null
	var def := _rig.current_def()
	if held != null and def != null and def.magazine > 0:
		held.magazine = def.magazine
	var eye := _controller.eye_transform()
	for i in range(64):
		_sheet_tick += 1
		var command := DotWeaponCommand.new()
		# Held for half a second and then let go: a grenade goes on the release.
		command.set_button(DotWeaponCommand.BUTTON_ATTACK, i < 32)
		var ctx := DotWeaponContext.make(1, _sheet_tick, eye.origin, -eye.basis.z)
		var outcome := _rig.simulate_tick(command, _sheet_tick, ctx)
		if outcome != null and outcome.used:
			break
		if i == 63:
			_view.on_fired(recoil)
	# Let go, and give the rig a quiet second, so the next frame's shot is not refused by this
	# one's cooldown.
	for i in range(64):
		_sheet_tick += 1
		var _idle := _rig.simulate_tick(DotWeaponCommand.new(), _sheet_tick,
			DotWeaponContext.make(1, _sheet_tick, eye.origin, -eye.basis.z))
	# The rig pushes its own deploy and reload fractions; the sheet's frame decides them.
	_view.on_reload(0.0)
	_view.on_deploy(1.0)


func _sheet_steps(count: int) -> void:
	for i in range(count):
		_view.advance(SHEET_STEP)
		if _rig.shot_fx() != null:
			_rig.shot_fx().advance(SHEET_STEP)
	# The HUD's half of aiming, as _process does it: without it a scoped weapon's aimed frame
	# was an empty range, the gun hidden and no scope drawn.
	_scope.follow(_view)


func _save_still() -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(_argument("--still"))
	print("captured %s (%s)" % [_argument("--still"), error_string(err)])
	get_tree().quit()


## Quits after `--seconds N`, so a screenshot sweep can open this without a person.
func _arm_exit_timer() -> void:
	var seconds := _argument("--seconds")

	if seconds == "":
		return

	var after := seconds.to_float()

	if after <= 0.0:
		return

	get_tree().create_timer(after).timeout.connect(func() -> void:
		get_tree().quit()
	)


## One `--name value` argument from the command line, after the bare `--`.
##
## [b]The bare `--` matters.[/b] Everything before it is Godot's and everything after it
## is the project's, and an argument passed without it is swallowed by the engine —
## which presents as the flag being ignored with no error at all.
static func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""
