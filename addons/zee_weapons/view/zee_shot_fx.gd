class_name ZeeShotFx
extends Node3D

## What a shot looks and sounds like: a tracer to where it landed, a flash at the muzzle,
## a spark where it struck, and the report.
##
## [b]It existed nowhere, and that is why every weapon in the pack "fired nothing".[/b] The
## rig decided the use, the ammunition went down, the server resolved the hit — and the
## only thing a player saw was the gun kick. dot-weapon refuses to draw a shot, correctly;
## this pack is the half that draws, and it drew the gun and stopped there, leaving the
## rest to "a game hanging a muzzle flash off [signal ZeeViewModel.model_ready]". No game
## did. Two games carried the pack and both were silent and tracerless.
##
## [b]Where the tracer ends is a presentation raycast, never the server's answer.[/b] A
## client does not know what the server's lag-compensated hitboxes decided and must not
## wait for it, so the line is drawn to whatever the client's own physics world has along
## the shot's direction. It is right almost always, and on the occasions it is not the
## server's damage is still the server's.
##
## [b]Only ever on a render frame, never on a server, never on a replayed tick.[/b] The rig
## does not build one in [constant ZeeWeaponRig.Role.SERVER] and only calls it from
## [method ZeeWeaponRig._record_use] outside a replay — a reconciliation that replayed
## eight ticks would otherwise play eight reports.
##
## [b]Every node it makes is its own and freed by it.[/b] Effects are top-level so the
## carrier moving does not drag a tracer already in flight, and capped, so a minigun held
## down for a minute does not leave a thousand nodes behind.

# No CHANNEL: this runs per shot per frame, and there is nothing in it an operator acts on.

## Most pellets drawn per use. A shotgun's twelve all land; drawing all twelve tracers is
## a fan of lines that reads as a beam weapon.
const MAX_TRACERS_PER_USE := 6

## Most effects alive at once, per carrier.
const MAX_LIVE := 48

## Most marks left on the world at once, per carrier. A mark outlives every other effect, so
## it has its own budget: sharing [constant MAX_LIVE] let a held minigun evict its own tracers.
const MAX_MARKS := 32

## How long a mark stays on a wall, in seconds, the last quarter of it fading.
const MARK_LIFE := 8.0

## Put a node in this group to have a shot that lands on it drawn as a hit on a body (a red
## burst, no mark), whatever its class. A character, a ragdoll's bone and this group are bodies.
const BODY_GROUP := &"zee_body"

## Put a node in this group to have it never drawn as a body, even if it is a character: a game
## where what was hit must not be given away by the impact (a disguised player).
const NOT_BODY_GROUP := &"zee_not_body"

## What a presentation ray's collider is, for [method impact_kind].
const IMPACT_WORLD := &"world"
const IMPACT_BODY := &"body"

## Most reports playing at once, per carrier. A minigun cuts its own oldest report off
## rather than stacking forty.
const MAX_VOICES := 6

@export_group("Behaviour")

## Draw tracers, flashes and impacts.
@export var visuals: bool = true

## Play reports.
@export var sounds: bool = true

## The audio bus reports are played on.
@export var bus: StringName = &"Master"

## Decibels added to every report. A game's mixer is the better place for this; this is
## for the game that has none.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0

## How far a tracer is drawn when nothing is hit, in metres.
@export_range(5.0, 1000.0, 1.0) var miss_distance: float = 120.0

## Physics layers the presentation ray stops on.
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF

## Bodies the presentation ray must not stop on: the carrier's own. Filled by whoever
## owns this, see [method exclude_carrier].
var exclude: Array[RID] = []

## What each effect still alive is: {node, age, life, kind, ...}.
var _live: Array[Dictionary] = []

var _voices: Array[AudioStreamPlayer3D] = []

## The marks on the world still showing: {node, age, size}. See [constant MAX_MARKS].
var _marks: Array[Dictionary] = []

## Where and when (msec) the last body was drawn hit, so a confirmation of the same hit
## arriving from the server ([method play_body_hit]) does not draw it twice.
var _last_body_at := Vector3.INF
var _last_body_msec: int = -100000

## Materials shared by every carrier's effects, built once.
static var _tracer_material: StandardMaterial3D = null
static var _beam_material: StandardMaterial3D = null
static var _flash_material: StandardMaterial3D = null
static var _spark_material: StandardMaterial3D = null
static var _puff_material: StandardMaterial3D = null
static var _hit_material: StandardMaterial3D = null
static var _petal_material: StandardMaterial3D = null
static var _mist_material: StandardMaterial3D = null
static var _mark_material: StandardMaterial3D = null
static var _streak: BoxMesh = null
static var _quad: QuadMesh = null
static var _soft: GradientTexture2D = null


func _ready() -> void:
	top_level = true
	# Placed at the world origin and never moved: every effect is written in world space.
	global_transform = Transform3D.IDENTITY


## Stops every report on the way out.
##
## [b]A report still playing when its player is freed is held by the audio server[/b], and
## a process that quits in the same frame — a suite, a shell unloading a game — reports
## the playback and its stream as leaked at exit.
func _exit_tree() -> void:
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()


# --- Being told what happened -----------------------------------------------

## Collects every physics body under [param carrier] into [member exclude], so a shot from
## the eye does not stop on the shooter's own capsule.
func exclude_carrier(carrier: Node) -> void:
	exclude.clear()
	if carrier != null:
		_collect_bodies(carrier, 0)


## A use this machine simulated, with its shots in hand.
##
## [param muzzle] is where the effect leaves from — the view model's muzzle in first
## person — and [param id] is the weapon, for its sound.
func play_use(outcome: DotWeaponOutcome, muzzle: Transform3D, id: StringName) -> void:
	if outcome == null or not outcome.used or not is_inside_tree():
		return

	var kind := outcome.kind
	_report(id, kind, muzzle.origin)

	if not visuals:
		return

	match kind:
		DotWeaponOutcome.KIND_SWING, DotWeaponOutcome.KIND_THROW:
			return
		DotWeaponOutcome.KIND_SPAWN:
			_flash(muzzle, 1.4)
			return

	var beam := kind == DotWeaponOutcome.KIND_BEAM
	if not beam:
		_flash(muzzle, 1.0)

	var drawn := 0
	for shot: DotShot in outcome.shots:
		var directions: Array[Vector3] = shot.pellets
		if directions.is_empty():
			directions = [shot.direction]

		for direction in directions:
			if drawn >= MAX_TRACERS_PER_USE:
				break
			drawn += 1
			_trace(muzzle.origin, shot.origin, direction, shot.max_range, beam)


## A use somebody else made, known only by its kind: a watcher's view, from the world
## model's muzzle along its barrel.
func play_remote(kind: int, muzzle: Transform3D, direction: Vector3, id: StringName) -> void:
	if not is_inside_tree():
		return

	_report(id, ZeeWeaponNet.kind_name(kind), muzzle.origin)

	if not visuals:
		return

	match kind:
		ZeeWeaponNet.KIND_SWING, ZeeWeaponNet.KIND_THROW, ZeeWeaponNet.KIND_NONE:
			return
		ZeeWeaponNet.KIND_SPAWN:
			_flash(muzzle, 1.4)
			return

	var beam := kind == ZeeWeaponNet.KIND_BEAM
	if not beam:
		_flash(muzzle, 1.0)

	_trace(muzzle.origin, muzzle.origin, direction, miss_distance, beam)


## How many effects are alive. For a suite, and for [method describe].
func live_count() -> int:
	return _live.size()


## How many tracers are alive.
func tracer_count() -> int:
	var count := 0
	for fx in _live:
		if fx["kind"] == &"tracer":
			count += 1
	return count


## How many marks are on the world.
func mark_count() -> int:
	return _marks.size()


## How many live effects are of [param kind] (`&"spark"`, `&"puff"`, `&"hit"`, `&"mist"`, ...).
func count_of(kind: StringName) -> int:
	var count := 0
	for fx in _live:
		if fx["kind"] == kind:
			count += 1
	return count


## A body the server says this machine's shot hit, at [param at], the shot travelling along
## [param direction].
##
## [b]For bodies the presentation ray cannot see.[/b] A game whose targets have no physics body
## on the client (a horde drawn as figures, hit through the server's hitboxes) gets a world
## impact behind its target from the ray, and the hit on the body only from this. Called from
## the same confirmation that flashes the hit marker. A body the ray already drew within a
## fifth of a second and half a metre of [param at] is not drawn again.
func play_body_hit(at: Vector3, direction: Vector3 = Vector3.ZERO) -> void:
	if not visuals or not is_inside_tree() or not at.is_finite():
		return
	if Time.get_ticks_msec() - _last_body_msec < 200 and _last_body_at.distance_to(at) < 0.5:
		return
	var back := -direction.normalized() if direction.is_finite() and not direction.is_zero_approx() else Vector3.UP
	_impact(at, back, IMPACT_BODY, false)


## What a shot landing on [param collider] is drawn as: [constant IMPACT_BODY] for a character,
## a ragdoll's bone or a node in [constant BODY_GROUP]; otherwise [constant IMPACT_WORLD].
static func impact_kind(collider: Object) -> StringName:
	var node := collider as Node
	if node == null:
		return IMPACT_WORLD
	if node.is_in_group(NOT_BODY_GROUP):
		return IMPACT_WORLD
	if node is CharacterBody3D or node is PhysicalBone3D or node.is_in_group(BODY_GROUP):
		return IMPACT_BODY
	return IMPACT_WORLD


## Whether a shot landing on [param collider] may leave a mark: only on what never moves. A mark
## is placed in world space and would hang in the air where a crate or a door used to be.
static func takes_marks(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is RigidBody3D or collider is CharacterBody3D or collider is AnimatableBody3D \
			or collider is PhysicalBone3D:
		return false
	# By class name, not by type: a build without the CSG or GridMap module must still parse this.
	return collider is StaticBody3D or collider.is_class("CSGShape3D") or collider.is_class("GridMap")


## The effects of a shot landing at [param at] on [param collider], facing [param normal]: what a
## presentation ray would draw. Public for a suite and for a game that traces its own shots.
func play_impact(at: Vector3, normal: Vector3, collider: Object) -> void:
	if not visuals or not is_inside_tree() or not at.is_finite():
		return
	_impact(at, normal, impact_kind(collider), takes_marks(collider))


# --- The frame --------------------------------------------------------------

func _process(delta: float) -> void:
	advance(delta)


## Moves every effect on by [param delta] seconds. [method _process] calls it; a capture that
## steps time by hand (the range's contact sheet) calls it instead.
func advance(delta: float) -> void:
	if not _marks.is_empty():
		_advance_marks(delta)

	if _live.is_empty():
		return

	var kept: Array[Dictionary] = []

	for fx in _live:
		var node: Node3D = fx["node"]
		if not is_instance_valid(node):
			continue

		fx["age"] = float(fx["age"]) + delta
		var through := float(fx["age"]) / float(fx["life"])

		if through >= 1.0:
			node.queue_free()
			continue

		_animate(fx, node, through)
		kept.append(fx)

	_live = kept


func _animate(fx: Dictionary, node: Node3D, through: float) -> void:
	match fx["kind"]:
		&"tracer":
			# A streak that travels, rather than a line that appears: a line from the gun
			# to the wall all at once reads as a laser, and a short bright segment moving
			# along it reads as something that was fired.
			var from: Vector3 = fx["from"]
			var to: Vector3 = fx["to"]
			var length: float = fx["length"]
			var total := from.distance_to(to)
			var head := minf(total, total * through * 1.15 + length * 0.5)
			var tail := maxf(0.0, head - length)
			var mid := from.lerp(to, ((head + tail) * 0.5) / maxf(0.001, total))
			var span := maxf(0.001, head - tail)
			_place_along(node, mid, to - from, span, _screen_width(mid, float(fx["width"])))
		&"beam", &"petal":
			node.transparency = through
		&"flash":
			var grow := 1.0 + through * 0.6
			node.scale = Vector3.ONE * float(fx["size"]) * grow
			node.transparency = through * through
			var light: Variant = fx.get("light")
			if light is OmniLight3D and is_instance_valid(light):
				(light as OmniLight3D).light_energy = float(fx["energy"]) * (1.0 - through)
		&"spark":
			var near := _distance_scale(node.global_position)
			node.scale = Vector3.ONE * float(fx["size"]) * near * (1.0 - through * 0.5)
			node.transparency = through
		&"puff":
			var far := _distance_scale(node.global_position)
			node.scale = Vector3.ONE * float(fx["size"]) * far * (0.6 + through * 1.4)
			node.transparency = 0.1 + through * 0.9
		&"hit":
			# A burst that opens fast and is gone: on a body the news is "that landed", and a
			# cloud hanging on a moving target trails behind it.
			var near := _distance_scale(node.global_position)
			node.scale = Vector3.ONE * float(fx["size"]) * near * (0.7 + sqrt(through) * 0.8)
			node.transparency = through * through
		&"mist":
			var far := _distance_scale(node.global_position)
			node.global_position = (fx["origin"] as Vector3) + (fx["drift"] as Vector3) * float(fx["age"])
			node.scale = Vector3.ONE * float(fx["size"]) * far * (0.5 + through * 1.2)
			node.transparency = 0.3 + through * 0.7


func _advance_marks(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for mark in _marks:
		var node: Node3D = mark["node"]
		if not is_instance_valid(node):
			continue
		mark["age"] = float(mark["age"]) + delta
		var through := float(mark["age"]) / MARK_LIFE
		if through >= 1.0:
			node.queue_free()
			continue
		# Holds, then fades over its last quarter: a mark that fades from the start is gone
		# before anybody looks at the wall.
		node.transparency = clampf((through - 0.75) / 0.25, 0.0, 1.0)
		kept.append(mark)
	_marks = kept


# --- Building effects -------------------------------------------------------

func _trace(
	muzzle: Vector3, eye: Vector3, direction: Vector3, reach: float, beam: bool
) -> void:
	var dir := direction.normalized()
	if not dir.is_finite() or dir.is_zero_approx():
		return

	# Traced from the eye, where the shot really started, and drawn from the muzzle. The
	# eye is what decides where it lands; the muzzle is only where the picture leaves.
	var end := eye + dir * minf(reach, miss_distance)
	var hit := false
	var normal := Vector3.UP
	var collider: Object = null

	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(eye, eye + dir * reach, collision_mask, exclude)
		query.collide_with_areas = false
		var found := space.intersect_ray(query)
		if not found.is_empty():
			end = found["position"]
			normal = found["normal"]
			hit = true
			collider = found.get("collider")

	if beam:
		_beam(muzzle, end)
	else:
		_tracer(muzzle, end)

	if hit:
		play_impact(end, normal, collider)


func _tracer(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.05:
		return

	var node := _mesh(_streak_mesh(), _tracer_mat())
	# The time it takes to cross is fixed rather than physical: a real round crosses a room
	# in a few milliseconds, which is no frames at all. A fifteenth of a second is two to
	# eight frames, which is enough to be seen and short enough to read as fast.
	var life := clampf(total / 420.0, 0.045, 0.11)
	var length := clampf(total * 0.3, 0.6, 5.0)
	_add(node, {"kind": &"tracer", "life": life, "from": from, "to": to,
		"length": length, "width": 0.004})
	_place_along(node, from, to - from, 0.001, 0.001)


func _beam(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.05:
		return

	var node := _mesh(_streak_mesh(), _beam_mat())
	_place_along(node, (from + to) * 0.5, to - from, total, 0.03)
	# Lives about as long as the gap between two of the beam's uses, so a held beam reads
	# as continuous without one use's line outliving where it was aimed.
	_add(node, {"kind": &"beam", "life": 0.07})


func _flash(muzzle: Transform3D, size: float) -> void:
	var node := _mesh(_quad_mesh(), _flash_mat())
	var forward := -muzzle.basis.z.normalized()
	node.global_position = muzzle.origin
	node.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	# Twelve centimetres, half a metre from the eye in first person: about a seventh of the screen.
	# Twice the first seven was a pale square over the gun; seven alone was the play test's
	# "almost no muzzle flash", a white dot lost against a pale barrel.
	var across := 0.12 * size * randf_range(0.85, 1.15)
	node.scale = Vector3.ONE * across

	# Two petals along the barrel's line, crossed, so the flash has a direction and a shape and
	# is read as fire leaving the muzzle rather than as a light on the gun.
	var petals: Array[MeshInstance3D] = []
	for turn in [0.0, PI * 0.5]:
		var petal := _mesh(_quad_mesh(), _petal_mat())
		var length := 0.16 * size * randf_range(0.85, 1.2)
		var width := 0.05 * size
		var x := forward.cross(Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT).normalized()
		x = x.rotated(forward, turn)
		# The quad lies in its X/Y plane: Y along the barrel, X across it.
		petal.global_transform = Transform3D(Basis(x * width, forward * length, x.cross(forward)),
			muzzle.origin + forward * (length * 0.5))
		petals.append(petal)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.omni_range = 4.5 * size
	light.light_energy = 2.2 * size
	light.shadow_enabled = false
	node.add_child(light)
	light.top_level = true
	light.global_position = muzzle.origin - forward * 0.05

	_add(node, {"kind": &"flash", "life": 0.06, "size": across,
		"light": light, "energy": light.light_energy})
	for petal in petals:
		_add(petal, {"kind": &"petal", "life": 0.05})


func _impact(at: Vector3, normal: Vector3, kind: StringName, mark: bool) -> void:
	if _live.size() > MAX_LIVE - 2:
		return

	var facing := normal.normalized() if normal.is_finite() and not normal.is_zero_approx() else Vector3.UP
	var lifted := at + facing * 0.02

	if kind == IMPACT_BODY:
		_last_body_at = at
		_last_body_msec = Time.get_ticks_msec()
		# A red burst and a darker mist drifting back toward the shooter: "that was somebody",
		# told apart from a wall's grey dust at a glance. No spark: a body does not strike one.
		var burst := _mesh(_quad_mesh(), _hit_mat())
		burst.global_position = lifted + facing * 0.04
		var burst_size := randf_range(0.30, 0.40)
		burst.scale = Vector3.ONE * burst_size
		_add(burst, {"kind": &"hit", "life": 0.16, "size": burst_size})

		var mist := _mesh(_quad_mesh(), _mist_mat())
		mist.global_position = lifted + facing * 0.08
		var mist_size := randf_range(0.32, 0.42)
		mist.scale = Vector3.ONE * mist_size
		_add(mist, {"kind": &"mist", "life": 0.45, "size": mist_size, "drift": facing * 0.4,
			"origin": mist.global_position})
		_play(ZeeWeaponSound.stream(ZeeWeaponSound.IMPACT), at, -10.0)
		return

	var spark := _mesh(_quad_mesh(), _spark_mat())
	spark.global_position = lifted
	var spark_size := randf_range(0.24, 0.32)
	spark.scale = Vector3.ONE * spark_size
	_add(spark, {"kind": &"spark", "life": 0.09, "size": spark_size})

	var puff := _mesh(_quad_mesh(), _puff_mat())
	puff.global_position = lifted + facing * 0.05
	var puff_size := randf_range(0.3, 0.4)
	puff.scale = Vector3.ONE * puff_size
	_add(puff, {"kind": &"puff", "life": 0.45, "size": puff_size})

	if mark:
		_mark(at, facing)

	_play(ZeeWeaponSound.stream(ZeeWeaponSound.IMPACT), at, -8.0)


## A dark scorch on the wall where a shot landed, flat on the surface, held for
## [constant MARK_LIFE]. [b]The one effect that says where the shots went after they went[/b]:
## a spark and a puff are gone in a third of a second, and a player correcting their aim reads
## the group on the wall.
func _mark(at: Vector3, facing: Vector3) -> void:
	if _marks.size() >= MAX_MARKS:
		var oldest: Dictionary = _marks.pop_front()
		var old: Node3D = oldest["node"]
		if is_instance_valid(old):
			old.queue_free()

	var node := _mesh(_quad_mesh(), _mark_mat())
	# A quad faces +Z: turn +Z onto the surface's normal, any roll.
	var up := Vector3.UP if absf(facing.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(facing).normalized()
	var y := facing.cross(x).normalized()
	# Grown with distance like an impact (capped at four times, at twenty-four metres): left at
	# its real size a mark at range was three pixels, which is no mark at all.
	var size := randf_range(0.09, 0.11) * _distance_scale(at)
	var spin := Basis(facing, randf() * TAU)
	node.global_transform = Transform3D(spin * Basis(x * size, y * size, facing),
		at + facing * 0.004)
	_marks.append({"node": node, "age": 0.0})


## A reload's sound at [param at]: [param stage] is [constant ZeeWeaponSound.RELOAD_OUT] or
## [constant ZeeWeaponSound.RELOAD_IN]. The rig decides when; this only plays it.
func play_reload(stage: StringName, at: Vector3) -> void:
	_play(ZeeWeaponSound.stream(stage), at, -4.0)


func _report(id: StringName, kind: StringName, at: Vector3) -> void:
	if not sounds or kind == DotWeaponOutcome.KIND_NONE:
		return

	_play(ZeeWeaponSound.stream_for(id, kind), at, 0.0)


func _play(stream: AudioStream, at: Vector3, extra_db: float) -> void:
	if not sounds or stream == null:
		return

	var voice: AudioStreamPlayer3D = null

	# A finished voice is reused before a new one is made; with every voice busy the
	# oldest is cut off, which is what a gun firing faster than its report can ring out
	# actually sounds like.
	for candidate in _voices:
		if is_instance_valid(candidate) and not candidate.playing:
			voice = candidate
			break

	if voice == null and _voices.size() < MAX_VOICES:
		voice = AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % _voices.size()
		voice.top_level = true
		# Heard across a map rather than across a room, and falling off gently: a shot is
		# the loudest thing in the game, and the default attenuation makes one at forty
		# metres inaudible.
		voice.unit_size = 12.0
		voice.max_distance = 260.0
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(voice)
		_voices.append(voice)

	if voice == null:
		voice = _voices.pop_front()
		_voices.append(voice)

	voice.bus = bus
	voice.stream = stream
	voice.volume_db = volume_db + extra_db
	# A rifle that sounds identical every shot is a metronome. Presentation, so randf.
	voice.pitch_scale = randf_range(0.94, 1.06)
	voice.global_position = at
	voice.play()


# --- Internals --------------------------------------------------------------

## A width that stays about the same on screen wherever the effect is.
##
## [b]Sized by distance from the camera, because a fixed width is invisible.[/b] A tracer
## is seen almost end-on from behind the gun, and two centimetres at thirty metres is a
## pixel — the first render of this showed a sniper shot as one yellow fleck. Here
## [param per_metre] is metres of width per metre of distance, so 0.004 is about a
## quarter of a degree: three or four pixels on a 1080-line screen at any range.
func _screen_width(at: Vector3, per_metre: float) -> float:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var distance := camera.global_position.distance_to(at) if camera != null else 4.0
	return clampf(distance * per_metre, 0.004, 0.25)


## How much larger an impact is drawn for being far away: 1 within six metres, rising to
## 4 at twenty-four. The same reason as [method _screen_width], held to a gentler curve,
## because a spark the size of a door at range reads as an explosion.
func _distance_scale(at: Vector3) -> float:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return 1.0
	return clampf(camera.global_position.distance_to(at) / 6.0, 1.0, 4.0)


func _add(node: Node3D, fx: Dictionary) -> void:
	if _live.size() >= MAX_LIVE:
		var oldest: Dictionary = _live.pop_front()
		var old: Node3D = oldest["node"]
		if is_instance_valid(old):
			old.queue_free()

	fx["node"] = node
	fx["age"] = 0.0
	_live.append(fx)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true
	add_child(node)
	return node


## Lays a unit box along [param along], centred on [param centre], [param span] long.
static func _place_along(
	node: Node3D, centre: Vector3, along: Vector3, span: float, width: float
) -> void:
	var z := along.normalized()
	if not z.is_finite() or z.is_zero_approx():
		return

	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	node.global_transform = Transform3D(
		Basis(x * width, y * width, z * maxf(0.001, span)), centre
	)


func _collect_bodies(node: Node, depth: int) -> void:
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())

	# Deep enough for a body under a character under a player; shallow enough that a
	# carrier parented under a whole level does not walk the level.
	if depth >= 4:
		return

	for child in node.get_children():
		_collect_bodies(child, depth + 1)


static func _streak_mesh() -> BoxMesh:
	if _streak == null:
		_streak = BoxMesh.new()
		_streak.size = Vector3.ONE
	return _streak


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


## A white disc fading to nothing at its edge, made once.
static func _soft_disc() -> GradientTexture2D:
	if _soft == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.35, Color(1.0, 1.0, 1.0, 0.75))
		_soft = GradientTexture2D.new()
		_soft.gradient = gradient
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func _glow(colour: Color, billboard: bool, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = colour
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		# A quad with no texture is a square, and a square of light reads as a rendering
		# fault rather than as a flash. The soft disc is what makes it a glow.
		m.albedo_texture = _soft_disc()
	m.no_depth_test = false
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Without it a billboard ignores its node's scale, and every flash, spark and puff
		# is drawn one metre across whatever size it was given.
		m.billboard_keep_scale = true
	return m


static func _tracer_mat() -> StandardMaterial3D:
	if _tracer_material == null:
		_tracer_material = _glow(Color(1.0, 0.86, 0.52, 0.95), false, true)
	return _tracer_material


static func _beam_mat() -> StandardMaterial3D:
	if _beam_material == null:
		_beam_material = _glow(Color(0.45, 0.85, 1.0, 0.9), false, true)
	return _beam_material


static func _flash_mat() -> StandardMaterial3D:
	if _flash_material == null:
		_flash_material = _glow(Color(1.0, 0.74, 0.32, 1.0), true, true)
		# The flash sits a few centimetres past the muzzle, inside the depth the barrel
		# has already written in first person. Tested against it, half the flash is cut
		# off by the gun that made it.
		_flash_material.no_depth_test = true
		_flash_material.render_priority = 1
	return _flash_material


static func _spark_mat() -> StandardMaterial3D:
	if _spark_material == null:
		_spark_material = _glow(Color(1.0, 0.9, 0.6, 1.0), true, true)
	return _spark_material


static func _puff_mat() -> StandardMaterial3D:
	if _puff_material == null:
		# Darker and warmer than the pale grey it was: grey dust on a grey wall was invisible on
		# every frame of the contact sheet after the spark had gone.
		_puff_material = _glow(Color(0.36, 0.32, 0.27, 0.8), true, false)
	return _puff_material


## The flash's petals: additive like the flash and, like it, drawn over the barrel that made it.
static func _petal_mat() -> StandardMaterial3D:
	if _petal_material == null:
		_petal_material = _glow(Color(1.0, 0.62, 0.22, 0.95), false, true)
		_petal_material.albedo_texture = _soft_disc()
		_petal_material.no_depth_test = true
		_petal_material.render_priority = 1
	return _petal_material


static func _hit_mat() -> StandardMaterial3D:
	if _hit_material == null:
		_hit_material = _glow(Color(0.85, 0.05, 0.04, 0.95), true, false)
	return _hit_material


static func _mist_mat() -> StandardMaterial3D:
	if _mist_material == null:
		_mist_material = _glow(Color(0.45, 0.02, 0.03, 0.6), true, false)
	return _mist_material


## A soft dark disc laid on the surface, not a billboard. Mixed, not added: added black is
## nothing at all.
static func _mark_mat() -> StandardMaterial3D:
	if _mark_material == null:
		_mark_material = _glow(Color(0.05, 0.045, 0.04, 0.85), false, false)
		_mark_material.albedo_texture = _soft_disc()
		# Drawn over the surface it sits on, a few millimetres off it: without the offset it
		# flickers in and out of the wall (z-fighting), and depth-tested it still hides behind
		# whatever stands in front of the wall.
		_mark_material.render_priority = -1
	return _mark_material


func describe() -> Dictionary:
	return {
		"live": _live.size(),
		"tracers": tracer_count(),
		"marks": _marks.size(),
		"voices": _voices.size(),
		"excluded": exclude.size(),
		"visuals": visuals,
		"sounds": sounds,
	}
