extends "zee_shot_fx_materials.gd"

## Sound half of ZeeShotFx, split out for file size.
## A sound was handed to a voice. For a suite that asserts which stream played, and a HUD.
signal heard(stream: AudioStream)

## Most reports playing at once, per carrier. A minigun cuts its own oldest report off
## rather than stacking forty.
const MAX_VOICES := 6

## A report from further than this plays the stock's distant recording, when there is one.
const FAR_METRES := 60.0

## Shortest gap between two dry clicks and two case landings, in ms: a held trigger on an
## empty gun and a minigun would otherwise use every voice on them.
const DRY_GAP_MSEC := 250

const CASING_GAP_MSEC := 90

## Replaces the stock report and tail: `func(id: StringName, kind: StringName, at: Vector3, indoors: bool) -> bool`, e.g. wrapping a DotShotPlayer's `fire`. Return true when it played the shot; false falls back to the stock sound. Unset keeps the stock sound.
var shot_sound: Callable = Callable()

var _layers: ZeeShotLayers = null

## Play reports.
@export var sounds: bool = true

## The game's roof probe ([code]DotAmbienceRoof[/code], which the game steps); roofed means indoors, so a shot is followed by a room tail.
var roof: RefCounted = null

var _voices: Array[AudioStreamPlayer3D] = []

var _last_dry_msec: int = -100000

var _last_casing_msec: int = -100000

## The audio bus reports are played on.
@export var bus: StringName = &"Master"

## Play guns as dot-audio's layered, room-aware shot when it is linked and the class has a stock shot; off, or missing, plays the single sound.
@export var layered_shots: bool = true

## Decibels added to every report. A game's mixer is the better place for this; this is
## for the game that has none.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0


## A reload's sound at [param at]: [param stage] is [constant ZeeWeaponSound.RELOAD_OUT] or
## [constant ZeeWeaponSound.RELOAD_IN]. The rig decides when; this only plays it. [param weapon_id] picks the class's own reload.
func play_reload(stage: StringName, at: Vector3, weapon_id: StringName = &"") -> void:
	_play(ZeeWeaponSound.reload_stream(weapon_id, stage), at, -4.0)


## The selector switch of weapon [param weapon_id] at [param at]; the click differs per gun class.
func play_mode_click(at: Vector3, weapon_id: StringName) -> void:
	if not sounds or not is_inside_tree():
		return
	_play(ZeeWeaponSound.stream(ZeeWeaponSound.mode_click_for(weapon_id)), at, -2.0)


## The hammer falling on nothing. Throttled, because a held trigger asks every tick.
func play_dry(at: Vector3, weapon_id: StringName = &"") -> void:
	var now := Time.get_ticks_msec()
	if not sounds or not is_inside_tree() or now - _last_dry_msec < DRY_GAP_MSEC:
		return
	_last_dry_msec = now
	_play(ZeeWeaponSound.dry_stream(weapon_id), at, -4.0)


## A weapon coming up in the hands; a grenade ([param thrown]) is heard as its pin coming out.
func play_equip(at: Vector3, thrown: bool = false, weapon_id: StringName = &"") -> void:
	if not is_inside_tree():
		return
	var pin := DotWeaponSound.pick(&"pin_pull", randi()) if thrown else null
	_play(pin if pin != null else ZeeWeaponSound.equip_stream(weapon_id), at, -6.0)


## One shell going into a tube magazine: a per-round reload plays this once per round.
func play_reload_shell(at: Vector3) -> void:
	if is_inside_tree():
		_play(ZeeWeaponSound.stream(ZeeWeaponSound.RELOAD_SHELL), at, -4.0)


## The case landing, a little after it left the port.
func _schedule_casing(at: Vector3, delay: float) -> void:
	var now := Time.get_ticks_msec()
	if not sounds or not is_inside_tree() or now - _last_casing_msec < CASING_GAP_MSEC:
		return
	_last_casing_msec = now
	var timer := get_tree().create_timer(0.38 + delay)
	timer.timeout.connect(_play_casing.bind(at))


func _play_casing(at: Vector3) -> void:
	if is_inside_tree():
		_play(ZeeWeaponSound.stream(ZeeWeaponSound.CASING), at - Vector3(0.0, 1.2, 0.0), -2.0)


func _report(id: StringName, kind: StringName, at: Vector3) -> void:
	if not sounds or kind == DotWeaponOutcome.KIND_NONE:
		return
	if shot_sound.is_valid() and bool(shot_sound.call(id, kind, at, roof != null and bool(roof.get(&"roofed")))):
		return
	if _layered(id, kind, at):
		return

	var heard: AudioStream = null
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null and camera.global_position.distance_to(at) > FAR_METRES:
		heard = ZeeWeaponSound.far_for(id, kind)

	_play(heard if heard != null else ZeeWeaponSound.stream_for(id, kind), at, 0.0)
	_play_tail(id, kind, at)


## Plays the layered shot for a gun class that has one; false leaves the single sound to the caller.
func _layered(id: StringName, kind: StringName, at: Vector3) -> bool:
	if not layered_shots or not is_inside_tree():
		return false
	if ZeeShotLayers.shot_class(ZeeWeaponSound.class_for(id, kind)) == &"":
		return false
	if _layers == null:
		if not ZeeShotLayers.available():
			layered_shots = false
			return false
		_layers = ZeeShotLayers.new()
		add_child(_layers)
		if not _layers.setup(bus):
			layered_shots = false
			return false
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var listener := camera.global_position if camera != null else at
	if not _layers.fire(ZeeWeaponSound.class_for(id, kind), at, listener):
		return false
	heard.emit(ZeeWeaponSound.stream_for(id, kind))
	return true


## Indoors the class's distant recording follows the report, [constant DotWeaponSound.TAIL_DELAY] late.
func _play_tail(id: StringName, kind: StringName, at: Vector3) -> void:
	var indoors := roof != null and bool(roof.get(&"roofed"))
	var tail := DotWeaponSound.pick_tail(ZeeWeaponSound.class_for(id, kind), indoors, randi())
	if tail == null or not is_inside_tree():
		return
	await get_tree().create_timer(DotWeaponSound.TAIL_DELAY).timeout
	if is_instance_valid(self) and is_inside_tree():
		_play(tail, at, DotWeaponSound.TAIL_GAIN_DB)


## Builds one report voice, idle and parked. Also what [method prewarm_voices] calls.
func _make_voice() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
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
	return voice


## Builds [param count] voices now (default: all of them), so the first shots and impacts create no AudioStreamPlayer3D.
## Opt-in: call under a loading cover. Nothing calls it for you, so [method describe]'s voice count is unchanged until you do.
func prewarm_voices(count: int = -1) -> void:
	var want := MAX_VOICES if count < 0 else mini(count, MAX_VOICES)

	while _voices.size() < want:
		var _made := _make_voice()


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
		voice = _make_voice()

	if voice == null:
		voice = _voices.pop_front()
		_voices.append(voice)

	heard.emit(stream)
	voice.bus = bus
	voice.stream = stream
	voice.volume_db = volume_db + extra_db
	# A rifle that sounds identical every shot is a metronome. Presentation, so randf.
	voice.pitch_scale = randf_range(0.94, 1.06)
	voice.global_position = at
	voice.play()
