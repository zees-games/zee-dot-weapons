@tool
extends "zee_weapon_rig_state.gd"

## Reload, fire-mode and switch callbacks of ZeeWeaponRig, split out for file size.

## A reload sound played (RELOAD_OUT at the start, RELOAD_IN at the end); never on a server or in a replay.
signal reload_sound(stage: StringName)

## The fire-mode selector clicked (the sound id); never on a server or in a replay.
signal mode_click(sound: StringName)


func _on_reload_started(slot: int) -> void:
	var carried := arsenal.slot_at(slot)

	if carried == null:
		return

	# A tube magazine has no magazine to drop: its shells are heard one by one.
	if not carried.def.reload_per_round:
		_reload_sound(ZeeWeaponSound.RELOAD_OUT, carried.def.id)

	_reload_started = _last_tick
	_reload_ticks = reload_motion_ticks(carried.def, carried.magazine_space())
	if _view != null and not _replaying:
		var start := float(arsenal.ticks_for(carried.def, carried.def.reload_start_ticks)) if carried.def.reload_per_round else 0.0
		_view.on_reload_begin(carried.magazine, carried.def.magazine, start / float(_reload_ticks))


## Ticks the reload motion spans: a per-round reload is the start plus one round time per missing
## round, so the motion must cover all of it, not wrap every start-length.
func reload_motion_ticks(def: DotWeaponDef, space: int) -> int:
	var ticks := def.reload_ticks
	if def.reload_per_round:
		ticks = def.reload_start_ticks + def.reload_ticks * maxi(space, 1)
	return maxi(1, arsenal.ticks_for(def, ticks))


func _on_fire_mode_changed(slot: int, _mode: int) -> void:
	if _replaying or role == Role.SERVER:
		return
	var carried := arsenal.slot_at(slot)
	if carried == null:
		return
	var click := ZeeWeaponSound.mode_click_for(carried.def.id)
	mode_click.emit(click)
	if _fx != null:
		_fx.play_mode_click(_listen_at(), carried.def.id)


func _on_dry_used(slot: int) -> void:
	if _replaying or role == Role.SERVER or _fx == null:
		return
	var carried := arsenal.slot_at(slot)
	_fx.play_dry(_listen_at(), carried.def.id if carried != null else &"")


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
