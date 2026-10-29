@tool
class_name ZeeWeaponRig
extends "zee_weapon_rig_state.gd"

## One player's weapons: the arsenal, the bash, the view model and the world model, driven from one command a tick.
## The one node a game adds. The same code runs in all three roles; [member role] only changes what is drawn.
## Order matters (arsenal before presentation, no drawing in a replay, the bash rolls back) and breaking it is silent.

const CHANNEL := "zee.rig"

const BASH_BEHAVIOUR := "res://addons/zee_weapons/behaviour/zee_weapon_bash.gd"

## A use happened. Carries the whole outcome, so a listener can tell a swing from a shot.
signal used(outcome: DotWeaponOutcome)

## A bash happened. Separate from [signal used] because it is a different animation, a
## different sound and, for most games, a different statistic.
signal bashed(outcome: DotWeaponOutcome)

## The weapon in hand changed, once the deploy has finished.
signal equipped(id: StringName)

## A reload's sound was played: [constant ZeeWeaponSound.RELOAD_OUT] when it starts,
## [constant ZeeWeaponSound.RELOAD_IN] when it finishes. Never on a server or in a replay.
signal reload_sound(stage: StringName)


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if arsenal == null:
		setup()


## Builds everything and validates the catalogue. Safe to call twice.
func setup() -> DotResult:
	if _ready_for_use:
		return DotResult.success(null)

	var res := _resolve_arsenal()
	if not res.ok:
		return res.wrap("The rig could not find or build an arsenal.")

	arsenal.catalogue = catalogue if catalogue != null else ZeeWeaponPack.catalogue()
	arsenal.tick_rate = tick_rate
	arsenal.authority = authority

	var ready_res := arsenal.setup()
	if not ready_res.ok:
		return ready_res

	if allow_bash:
		var script: Variant = load(BASH_BEHAVIOUR)
		if script is Script:
			_bash = (script as Script).new()

	_resolve_carrier()
	_resolve_presentation()
	_connect_arsenal()

	_ready_for_use = true
	return DotResult.success(null)


func is_ready() -> bool:
	return _ready_for_use


func _resolve_arsenal() -> DotResult:
	if arsenal_ref != null:
		var found := arsenal_ref.resolve(self)
		if found.ok and found.value is DotWeaponArsenal:
			arsenal = found.value
			return DotResult.success(null)

	arsenal = DotWeaponArsenal.new()
	arsenal.name = "Arsenal"
	add_child(arsenal)
	return DotResult.success(null)


## Who is carrying this: not presentation, so it must not be skipped on a server.
## A null player makes [method DotWeaponPlayerBridge.context_for] return defaults, so every shot traces from the world origin.
## Nothing else reports it: the weapon fires and the counters move, but hit registration finds nothing.
func _resolve_carrier() -> void:
	if player_ref == null:
		return

	var player := player_ref.resolve(self)

	if player.ok:
		_player = player.value
		return

	# Loud, because a carrier that cannot be found is a carrier that shoots the map.
	DotLog.warn(CHANNEL, "the rig could not find the player carrying it", {
		"why": player.error.message,
		"consequence": "shots resolve from the world origin",
	})


func _resolve_presentation() -> void:
	if role == Role.SERVER:
		return

	if role == Role.LOCAL and view_model_ref != null:
		var view := view_model_ref.resolve(self)
		if view.ok and view.value is ZeeViewModel:
			_view = view.value
			_view.ads_rules = ads_rules
			# Cvars bound before the view model existed keep their object.
			if _standalone_feel != null:
				_view.feel_rules = _standalone_feel

	if world_model_ref != null:
		var world := world_model_ref.resolve(self)
		if world.ok and world.value is ZeeWorldModel:
			_world = world.value

	# Only a first-person rig draws its own shots. Without a view model there is no muzzle
	# this rig owns, and the world model draws them from the hand instead.
	if effects and _view != null:
		_fx = ZeeShotFx.new()
		_fx.name = "ShotFx"
		_fx.catalogue = catalogue
		add_child(_fx)
		_fx.exclude_carrier(_player)
		_view.wall_mask = _fx.collision_mask


func _connect_arsenal() -> void:
	arsenal.reload_started.connect(_on_reload_started)
	arsenal.reload_finished.connect(_on_reload_finished)
	arsenal.switched.connect(_on_switched)
	arsenal.dry_used.connect(_on_dry_used)


# --- Carrying ---------------------------------------------------------------

## Gives the carrier a weapon, by id.
func give(id: StringName, full: bool = true) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	return arsenal.give(id, full)


## Gives the carrier everything in the pack. For a test range and a sandbox mode.
func give_everything() -> int:
	var given := 0

	for id in ZeeWeaponIds.all():
		if arsenal.give(id).ok:
			given += 1

	return given


func current_def() -> DotWeaponDef:
	return arsenal.current_def() if arsenal != null else null


func current_art() -> ZeeWeaponArt:
	var def := current_def()
	return ZeeWeaponArtTable.table().get(def.id, null) if def != null else null


# --- The tick ---------------------------------------------------------------

## One tick of one command: the arsenal, then the bash, then the picture.
## [param ctx] is optional; left null, one is built from the player through [DotWeaponPlayerBridge].
## The order is load-bearing: presentation first shows the previous tick, and a bash first can fire through a weapon being holstered.
func simulate_tick(
	command: DotWeaponCommand,
	tick: int,
	ctx: DotWeaponContext = null
) -> DotWeaponOutcome:
	if not _ready_for_use:
		return DotWeaponOutcome.nothing("setup() has not been called.")

	_last_tick = tick

	# A shooter with nothing pressed and nothing under way: no context to build, no command to copy.
	if ctx == null and arsenal.is_idle_for(command, _previous_command):
		return _idle_tick(command, tick)

	var context := ctx if ctx != null else _context_for(tick)
	context.tick = tick
	context.authority = authority
	if _view != null:
		_view.set_sprinting(context.sprinting)
	_aim_along_sprint_barrel(context)

	_notice_holster(tick)

	var outcome := _simulate_aimed(command, context)

	_notice_switch_end()

	if outcome.used:
		_record_use(outcome)

	var bash_outcome := _advance_bash(command, context, tick)

	if bash_outcome != null and bash_outcome.used:
		_record_use(bash_outcome)
		bashed.emit(bash_outcome)
		outcome = bash_outcome

	_advance_charge(command, tick)
	_update_presentation(tick)

	_previous_command = command.duplicate_command()
	return outcome


## Turns [member DotWeaponContext.direction] to where the sprint carry points the barrel (full blend, from the art, so a server and a replay agree without reading the rendered pose). The origin stays the eye.
func _aim_along_sprint_barrel(context: DotWeaponContext) -> void:
	if not (context.sprinting and context.sprint_shot_follows_barrel):
		return
	var art := current_art()
	if art == null or absf(context.direction.dot(Vector3.UP)) > 0.999:
		return
	var rot: Vector3 = art.sprint_rotation if art.sprint_rotation.is_finite() \
		else ZeeWeaponArtTable.sprint_view(art.pose)[1]
	var hand := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	var aim := Basis.looking_at(context.direction, Vector3.UP)
	context.direction = (aim * (hand * Vector3.FORWARD)).normalized()


## What [method simulate_tick] does when [method DotWeaponArsenal.is_idle_for] holds: with no button
## down there is no aim, bash or use, so only the bookkeeping that every tick does is left.
func _idle_tick(command: DotWeaponCommand, tick: int) -> DotWeaponOutcome:
	# Sprinting is just movement: no button is down, so this is the path a sprint usually takes.
	if _view != null and _player != null:
		_view.set_sprinting(_context_for(tick).sprinting)
	_notice_holster(tick)
	_ads_move = 1.0
	_aim_ticks = 0
	var outcome := arsenal.idle_tick()
	_notice_switch_end()
	_advance_charge(command, tick)
	_update_presentation(tick)

	# The previous command is only read for its buttons and slot; copy it only when they differ.
	if _previous_command == null or _previous_command.buttons != 0 or _previous_command.slot != command.slot:
		_previous_command = command.duplicate_command()

	return outcome


## The arsenal's tick with the spread scaled while the command holds the aim button. The scale
## is put back after, so the def is never left changed; it follows the command, so a replay agrees.
func _simulate_aimed(command: DotWeaponCommand, context: DotWeaponContext) -> DotWeaponOutcome:
	_ads_move = 1.0
	var def := arsenal.current_def()
	if not _can_aim(command, def, context):
		_aim_ticks = 0
		return arsenal.simulate_tick(command, context, _previous_command)
	var art: ZeeWeaponArt = ZeeWeaponArtTable.table().get(def.id, null)
	var b := def.tuning as DotWeaponBallistics
	if b == null:
		return arsenal.simulate_tick(command, context, _previous_command)
	_aim_ticks += 1
	_ads_move = ads_rules.move_speed_for(def.id)
	# The spread closes as the sights come up, over the weapon's aim time, counted in ticks so a replay agrees.
	var seconds := ads_rules.aim_time_for(def.id, art.aim_time if art != null else 0.16)
	var ramp := clampf(float(_aim_ticks) / maxf(seconds * float(tick_rate), 1.0), 0.0, 1.0)
	var k := lerpf(1.0, ads_rules.spread_for(def.id), ramp)
	var kept := [b.spread, b.spread_moving, b.spread_airborne, b.bloom]
	b.spread *= k
	b.spread_moving *= k
	b.spread_airborne *= k
	b.bloom *= k
	var outcome := arsenal.simulate_tick(command, context, _previous_command)
	b.spread = kept[0]
	b.spread_moving = kept[1]
	b.spread_airborne = kept[2]
	b.bloom = kept[3]
	return outcome


## Whether the aim bit counts: the server does not take it on trust. Needs rules, a weapon that
## aims (rules and art), and a rifle that is neither being switched to nor reloaded, and a carrier not sprinting under `sv_sprint_noaim`.
func _can_aim(command: DotWeaponCommand, def: DotWeaponDef, context: DotWeaponContext = null) -> bool:
	if ads_rules == null or ads_button == 0 or def == null or (command.buttons & ads_button) == 0:
		return false
	if context != null and context.sprinting and context.sprint_blocks_aim:
		return false
	if not ads_rules.enabled_for(def.id) or arsenal.is_switching() or arsenal.is_reloading():
		return false
	var art: ZeeWeaponArt = ZeeWeaponArtTable.table().get(def.id, null)
	return art == null or art.aim_enabled


## The walk-speed multiplier of the last simulated command: [member ZeeAdsRules] move speed while it
## held the aim button, else 1. A game multiplies its motor's speed by it on the server and in prediction.
func ads_move_scale() -> float:
	return _ads_move


## Marks the start of a reconciliation replay.
## Everything still simulates; the drawing stops, or the view model would rebuild its meshes and the recoil spring re-punch on every correction.
func begin_replay() -> void:
	_replaying = true
	arsenal.begin_replay()


func end_replay() -> void:
	_replaying = false
	arsenal.end_replay()


func is_replaying() -> bool:
	return _replaying


# --- The bash ---------------------------------------------------------------

## The alt-fire, simulated here because dot-weapon's arsenal routes one button (see [ZeeWeaponBash]).
## The cooldown lives in [member _bash_ready_tick], travels in [method snapshot] and rolls back, so a correction cannot bash twice.
func _advance_bash(
	command: DotWeaponCommand, context: DotWeaponContext, tick: int
) -> DotWeaponOutcome:
	if _bash == null or not allow_bash:
		return null

	if not command.just_pressed(DotWeaponCommand.BUTTON_ALT, _previous_command):
		return null

	if arsenal.is_switching() or tick < _bash_ready_tick:
		return null

	var def := arsenal.current_def()

	if not ZeeWeaponBash.can_bash(def):
		return null

	_bash.for_def(def)

	# A bash interrupts a reload, the same as firing does. Unlike firing, it can always
	# afford to: a bash spends nothing, so there is no order-of-operations trap here of
	# the kind that made dot-weapon's `_try_use` check payment before cancelling.
	arsenal.cancel_reload()
	_reload_started = -1

	var outcome := _bash.use(context)

	if outcome.used:
		# The bash's cooldown is in the row's ticks, like any outcome's; the arsenal does not
		# see this outcome, so the rig scales it by the same rule the arsenal would.
		_bash_ready_tick = tick + maxi(1, arsenal.ticks_for(def, outcome.cooldown_ticks))

	return outcome


# --- Presentation -----------------------------------------------------------

## Everything the player sees, from state the simulation has already settled.
## Skipped during a replay: the simulation re-runs after a correction, a model rebuild, punch and sound must not.
func _update_presentation(tick: int) -> void:
	if _replaying or role == Role.SERVER:
		return

	var def := arsenal.current_def()
	var id := def.id if def != null else &""

	if id != _shown:
		_shown = id
		var art: ZeeWeaponArt = ZeeWeaponArtTable.table().get(id, null)
		# A profile's `extra: art:` overrides the table's art, as a figure's held gun does.
		if art != null and def != null and def.params.get("art") is Dictionary:
			art = art.with_overrides(def.params["art"])

		if _view != null:
			_view.equip(art)
			_view.set_kick_params(def.params if def != null else {})

		if _world != null:
			_world.equip(art)

		_shown_fit = ""
		equipped.emit(id)
		if _fx != null and _fx_origin_known and id != &"":
			_fx.play_equip(_listen_at(), def != null and ZeeWeaponIds.TAG_THROWN in def.tags)

	_show_fitting()
	_fx_origin_known = true
	_per_round_sound()

	if _view != null:
		_view.on_deploy(_deploy_fraction(tick))
		_view.on_reload(_reload_fraction(tick))
		_view.on_charge(_charge_fraction(tick, def))

	if _world != null:
		_world.on_switching(arsenal.is_switching())


## Tells both models what is fitted to the weapon in hand, when that changes.
func _show_fitting() -> void:
	if _world != null:
		_world.attachments = arsenal.attachments
	var fitting := arsenal.fitting_at(arsenal.current_slot())
	if fitting.key() == _shown_fit:
		return
	_shown_fit = fitting.key()
	if _view != null:
		_view.set_fitting(fitting)
	if _world != null:
		_world.set_fitting(fitting)


## Drives the view model's sway and bob from the carrier's motion.
## Called on a render frame, not a tick, so sway is not quantised to the tick rate.
## [param strafe] is sideways speed in m/s, positive right; left out, the view model measures it.
func drive_view(look: Vector2, speed: float, on_floor: bool, crouched: bool, strafe: float = NAN) -> void:
	if _view != null:
		_view.drive(look, speed, on_floor, crouched, strafe)


## The amounts for the view model's motion, and the `mp_vm_*` cvars: `feel_rules().bind_cvars(
## add_cvar, flags)` on a server, `follow_cvars(link)` on a client. A fresh set when there is no
## view model (a server rig), so a module can bind before anything is built.
func feel_rules() -> ZeeViewFeel:
	if _view != null:
		return _view.feel_rules
	if _standalone_feel == null:
		_standalone_feel = ZeeViewFeel.new()
	return _standalone_feel


## A landing, for the view model's dip.
func on_landed(impact: float) -> void:
	if _view != null:
		_view.on_landed(impact)


## Everything back to rest: a respawn, a teleport, a correction that moved the carrier.
func on_reset() -> void:
	if _fx != null:
		_fx.stop_flashes()
	if _view != null:
		_view.on_reset()


## Hangs the world model off the carrier's character, if they have one.
## Duck-typed; false is not an error (a server has no model).
func attach_world_model(character: Object = null) -> bool:
	if _world == null:
		return false

	var target := character if character != null else _player
	return _world.attach_to(target)


func view_model() -> ZeeViewModel:
	return _view


## The shot effects, or null on a server, without a view model, or with [member effects]
## off. For a game that wants to set the bus or turn the sound down.
func shot_fx() -> ZeeShotFx:
	return _fx


## How far recoil should turn the camera this frame, in degrees: x pitch up, y yaw.
## Presentation, added after the controller writes the camera and never to the command's angles; see [method ZeeViewModel.view_punch].
func view_punch() -> Vector2:
	return _view.view_punch() if _view != null else Vector2.ZERO


func world_model() -> ZeeWorldModel:
	return _world


## Where the muzzle is, for an effect. Never for a shot — see
## [method ZeeViewModel.muzzle_transform].
func muzzle_transform() -> Transform3D:
	if _view != null:
		return _view.muzzle_transform()

	if _world != null:
		return _world.muzzle_transform()

	return Transform3D.IDENTITY


# Counted here, not read off the arsenal: it keeps reload progress private, and exposing a fraction would tie
# the simulation's interface to one animation. The rig listens to the signals and counts ticks itself.

func _deploy_fraction(tick: int) -> float:
	if _switch_started < 0 or _switch_ticks <= 0:
		return 1.0

	var through := clampf(
		float(tick - _switch_started) / float(_switch_ticks), 0.0, 1.0
	)

	# A holster runs the animation down and a deploy runs it back up. One number for
	# both is why this is a fraction rather than a flag.
	return through if _switch_deploying else 1.0 - through


func _reload_fraction(tick: int) -> float:
	# The arsenal decides whether a reload runs; this rig only times it. Firing, a switch, a drop and a rollback end a reload
	# without announcing it, so a start tick kept past its end would play the reload pose for ever.
	if _reload_started < 0 or _reload_ticks <= 0 or not arsenal.is_reloading():
		return 0.0

	return fposmod(float(tick - _reload_started) / float(_reload_ticks), 1.0)


func _charge_fraction(tick: int, def: DotWeaponDef) -> float:
	if _charge_started < 0 or def == null or not def.is_charged():
		return 0.0

	return arsenal.charge_for(def, tick - _charge_started)


## Tracks a charged weapon's draw, so the view model can pull the weapon back.
##
## The arsenal has this number and does not publish it, for the reason above.
func _advance_charge(command: DotWeaponCommand, tick: int) -> void:
	var def := arsenal.current_def()

	if def == null or not def.is_charged():
		_charge_started = -1
		return

	var down := command.is_pressed(DotWeaponCommand.BUTTON_ATTACK)

	if down and _charge_started < 0:
		_charge_started = tick
	elif not down:
		_charge_started = -1


## Catches the start of a switch, which no signal announces.
## [signal DotWeaponArsenal.switched] fires between holster and deploy, so the holster half is noticed by watching
## [method DotWeaponArsenal.is_switching] go true on the tick before the arsenal runs.
func _notice_holster(tick: int) -> void:
	var switching := arsenal.is_switching()

	if switching and not _was_switching:
		var carried := arsenal.current()
		_switch_started = tick
		_switch_deploying = false
		_switch_ticks = maxi(1, arsenal.ticks_for(carried.def, carried.def.holster_ticks) if carried != null else 1)

	_was_switching = switching


## Puts the switch animation away once the arsenal says the switch is over.
## Otherwise the deploy fraction stays pinned at 1.0 from a stale start tick, and a rollback animates the weapon back down.
func _notice_switch_end() -> void:
	if _switch_started >= 0 and not arsenal.is_switching():
		_switch_started = -1
		_was_switching = false


func _on_reload_started(slot: int) -> void:
	var carried := arsenal.slot_at(slot)

	if carried == null:
		return

	# A tube magazine has no magazine to drop: its shells are heard one by one.
	if not carried.def.reload_per_round:
		_reload_sound(ZeeWeaponSound.RELOAD_OUT, carried.def.id)

	_reload_started = _last_tick
	_reload_ticks = reload_motion_ticks(carried.def, carried.magazine_space())


## Ticks the reload motion spans: a per-round reload is the start plus one round time per missing
## round, so the motion must cover all of it, not wrap every start-length.
func reload_motion_ticks(def: DotWeaponDef, space: int) -> int:
	var ticks := def.reload_ticks
	if def.reload_per_round:
		ticks = def.reload_start_ticks + def.reload_ticks * maxi(space, 1)
	return maxi(1, arsenal.ticks_for(def, ticks))


func _on_dry_used(_slot: int) -> void:
	if _replaying or role == Role.SERVER or _fx == null:
		return
	_fx.play_dry(_listen_at())


## One shell sound for every round a per-round reload has added since the last tick.
func _per_round_sound() -> void:
	var carried := arsenal.current()
	if carried == null or not carried.def.reload_per_round:
		_rounds_seen = -1
		return
	# The last round lands on the tick the reload ends, so compare before checking is_reloading.
	if _rounds_seen >= 0 and carried.magazine > _rounds_seen and _fx != null:
		_fx.play_reload_shell(_listen_at())
	_rounds_seen = carried.magazine if arsenal.is_reloading() else -1


func _listen_at() -> Vector3:
	return (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO


func _on_reload_finished(slot: int, _rounds: int) -> void:
	_reload_started = -1
	var finished := arsenal.slot_at(slot)
	_reload_sound(ZeeWeaponSound.RELOAD_IN, finished.def.id if finished != null else &"")


## Plays one half of a reload's sound, under the same rule as a shot's report: never on a
## server and never on a replayed tick — a correction that replayed across a reload would
## otherwise click the magazine out twice.
func _reload_sound(stage: StringName, weapon_id: StringName = &"") -> void:
	if _replaying or role == Role.SERVER:
		return

	reload_sound.emit(stage)

	if _fx != null:
		var at: Vector3 = (_player as Node3D).global_position if _player is Node3D else Vector3.ZERO
		_fx.play_reload(stage, at, weapon_id)


## The holster half finished and the deploy half began.
## The arsenal emits this mid-switch, not at its end; treating it as the end leaves the weapon at the screen bottom.
func _on_switched(_from: int, to: int) -> void:
	var carried := arsenal.slot_at(to)
	if _fx != null:
		_fx.stop_flashes()

	_switch_started = _last_tick
	_switch_deploying = true
	_switch_ticks = maxi(1, arsenal.ticks_for(carried.def, carried.def.deploy_ticks) if carried != null else 1)


# --- Context ----------------------------------------------------------------

func _context_for(tick: int) -> DotWeaponContext:
	if _player != null:
		var ctx := DotWeaponPlayerBridge.context_for(_player, tick)
		ctx.authority = authority
		return ctx

	var made := DotWeaponContext.new()
	made.tick = tick
	made.authority = authority
	return made


func _record_use(outcome: DotWeaponOutcome) -> void:
	fire_seq += 1
	fire_kind = ZeeWeaponNet.kind_number(outcome.kind)

	if not _replaying:
		used.emit(outcome)

		if _view != null:
			var shot_def := arsenal.current_def()
			if shot_def != null and shot_def.use_interval_ticks > 0:
				_view.fire_interval = float(arsenal.ticks_for(shot_def, shot_def.use_interval_ticks)) / float(tick_rate)
			_view.on_used(outcome)

		if _fx != null:
			var def := arsenal.current_def()
			var weapon_id: StringName = def.id if def != null else &""
			_fx.play_use(outcome, _view.muzzle_transform(), weapon_id)
			if outcome.kind == DotWeaponOutcome.KIND_SHOT and _view.has_method(&"ejects") and _view.ejects():
				_fx.play_eject(_view.eject_transform(), weapon_id)

		if _world != null:
			# The world model draws the shot itself only when nothing here did.
			_world.on_fired(
				outcome.recoil, ZeeWeaponNet.kind_number(outcome.kind), effects and _fx == null
			)


# --- Netcode ----------------------------------------------------------------

## Everything that has to travel and everything a rollback has to restore.
## The arsenal's snapshot plus the rig's own: the bash cooldown and charge live here, and omitting them hands a free bash on correction.
func snapshot() -> Dictionary:
	return {
		"arsenal": arsenal.snapshot() if arsenal != null else {},
		"bash_ready": _bash_ready_tick,
		"charge_started": _charge_started,
		"fire_seq": fire_seq,
		"fire_kind": fire_kind,
		# The previous command's buttons are simulation state: the bash, reload and semi-automatic weapons are edge-triggered against them,
		# so a snapshot without them refuses the next press once. The arsenal is handed the previous command; the rig keeps one, so it saves it.
		"prev_buttons": _previous_command.buttons if _previous_command != null else 0,
		"prev_slot": _previous_command.slot if _previous_command != null else 0,
		"aim_ticks": _aim_ticks,
	}


func restore(state: Dictionary) -> DotResult:
	if not _ready_for_use:
		return DotResult.fail(DotError.CODE_STATE, "setup() has not been called.")

	var res := arsenal.restore(state.get("arsenal", {}))

	if not res.ok:
		return res

	_bash_ready_tick = int(state.get("bash_ready", 0))
	_charge_started = int(state.get("charge_started", -1))
	fire_seq = int(state.get("fire_seq", fire_seq))
	fire_kind = int(state.get("fire_kind", ZeeWeaponNet.KIND_NONE))

	_aim_ticks = int(state.get("aim_ticks", 0))
	_previous_command = DotWeaponCommand.new()
	_previous_command.buttons = int(state.get("prev_buttons", 0))
	_previous_command.slot = int(state.get("prev_slot", 0))

	# The switch bookkeeping is presentation only, but it is derived from ticks that have
	# just moved backwards. Left alone it animates a switch that already finished.
	_was_switching = arsenal.is_switching()
	_switch_started = -1
	_reload_started = -1

	return DotResult.success(null)


## Copies this rig's state onto a replicating object. See [ZeeWeaponNet].
func pull_net(target: Object) -> void:
	ZeeWeaponNet.pull(self, target)


# --- Reporting --------------------------------------------------------------

func describe() -> Dictionary:
	return {
		"ready": _ready_for_use,
		"role": Role.keys()[role],
		"authority": authority,
		"showing": String(_shown),
		"fire_seq": fire_seq,
		"bash_ready": _bash_ready_tick,
		"arsenal": arsenal.describe() if arsenal != null else {},
		"view": _view.describe() if _view != null else {},
		"fx": _fx.describe() if _fx != null else {},
		"world": _world.describe() if _world != null else {},
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("rig: %s%s, showing %s" % [
		Role.keys()[role],
		" (authority)" if authority else "",
		String(_shown) if _shown != &"" else "(nothing)",
	])

	if arsenal != null:
		out.append_array(arsenal.describe_lines())

	if _view != null:
		out.append_array(_view.describe_lines())

	return out
