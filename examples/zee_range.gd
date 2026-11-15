extends "res://examples/zee_range_sheet.gd"

## A firing range you can walk around, holding every weapon in the pack: `godot --path . res://examples/zee_range.tscn`.
## Options after `--`: `--seconds N --weapon ID --fire --capture DIR --sheet DIR --dummy`. WASD, space, ctrl, mouse, R, 1-5, Q, wheel; F1 dumps the rig.
## The half of the suite no assertion reaches: look at it (`tools/screenshot.sh`). It sets no [DotNodeRef]s; the defaults find everything by type.

const CHANNEL := "zee.range"

## Where the player stands, far enough back that a target is a shot rather than a poke.
const SPAWN := Vector3(0.0, 0.2, 14.0)

## `--aim` holds the aim for the whole run, so a capture shows the aimed pose.
var _always_aim: bool = false
var _input := ZeeWeaponInput.make()

## The simulation tick. Advanced in `_physics_process`, never read from a clock.
var _tick: int = 0

## Whether `--fire` was passed.
var _auto_fire: bool = false

## Whether a `--capture` sequence has started.
var _capturing: bool = false

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
	_fit_requested(def)

	for i in range(200):
		_rig.simulate_tick(DotWeaponCommand.new(), i)


## Honours `--fit zee_scope,zee_suppressor`: the pack's attachments on the weapon asked for, for an aimed-in look at an optic.
func _fit_requested(def: DotWeaponDef) -> void:
	var wanted := _argument("--fit")
	if wanted == "":
		return
	_rig.arsenal.attachments = ZeeAttachmentPack.attachments()
	var fitting := DotWeaponFitting.make(def.id)
	for id in wanted.split(",", false):
		var att := _rig.arsenal.attachments.get_attachment(StringName(id))
		if att != null:
			fitting.fit(att.mount, att.id)
	var fitted := _rig.arsenal.fit(def.slot, fitting)
	if not fitted.ok:
		DotLog.warn(CHANNEL, "the fitting was refused", {"why": fitted.error.message})


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


