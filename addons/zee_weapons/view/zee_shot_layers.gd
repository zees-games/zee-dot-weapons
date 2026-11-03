class_name ZeeShotLayers
extends Node

## dot-audio's layered, room-aware shot (DotShotPlayer) for ZeeShotFx. Duck-typed by script path so a project without dot-audio, or a class with no stock shot, falls back to ZeeShotFx's single sound.

const CHANNEL := "zee.shot_layers"
const ROOT := "res://addons/dot_audio/"
const PLAYER := ROOT + "runtime/dot_shot_player.gd"
const MANAGER := ROOT + "runtime/dot_audio_manager.gd"
const ENCLOSURE := ROOT + "runtime/dot_audio_enclosure.gd"
const CATALOGUE := ROOT + "core/dot_audio_catalogue.gd"
const SHOT_STOCK := ROOT + "core/dot_audio_shot_stock.gd"

## Weapon classes with a stock shot; the suppressed class plays the light set, suppressed.
const STOCK_CLASSES: Array[StringName] = [&"light", &"magnum", &"smg", &"rifle", &"heavy", &"sniper", &"shotgun", &"launcher", &"minigun", &"beam", &"charge", &"swing", &"throw"]

var player: Node = null
var enclosure: Node = null
var manager: Node = null

var _stock: GDScript = null
var _ready_ok := false


## True when dot-audio's shot player and stock are linked in this project.
static func available() -> bool:
	for path in [PLAYER, MANAGER, ENCLOSURE, CATALOGUE, SHOT_STOCK]:
		if not ResourceLoader.exists(path):
			return false
	return true


## The stock shot class for a ZeeWeaponSound class, or empty for a class with none.
static func shot_class(weapon_class: StringName) -> StringName:
	if weapon_class == ZeeWeaponSound.SUPPRESSED:
		return &"light"
	return weapon_class if STOCK_CLASSES.has(weapon_class) else &""


func is_ready() -> bool:
	return _ready_ok


## Builds the manager, player and enclosure once. False when dot-audio is missing or a stock shot fails to register.
func setup(send_bus: StringName) -> bool:
	if _ready_ok:
		return true
	if not available():
		return false
	_stock = load(SHOT_STOCK)
	manager = (load(MANAGER) as GDScript).new()
	manager.set(&"catalogue", (load(CATALOGUE) as GDScript).new())
	manager.set(&"register_as_service", false)
	manager.set(&"apply_mixer_to_buses", false)
	manager.set(&"limit_master", false)
	add_child(manager)
	var made: DotResult = manager.call(&"setup")
	if not made.ok:
		DotLog.warn(CHANNEL, "the audio manager did not start", {"cause": str(made)})
		return false
	enclosure = (load(ENCLOSURE) as GDScript).new()
	enclosure.set(&"send_bus", send_bus)
	add_child(enclosure)
	player = (load(PLAYER) as GDScript).new()
	player.set(&"manager", manager)
	player.set(&"enclosure", enclosure)
	add_child(player)
	for weapon_class in STOCK_CLASSES:
		var res: DotResult = player.call(&"register", _stock.call(&"shot", weapon_class))
		if not res.ok:
			DotLog.warn(CHANNEL, "a stock shot did not register", {"class": weapon_class, "cause": str(res)})
			return false
	_ready_ok = true
	return true


## Plays a shot of [param weapon_class] at [param at], heard from [param listener]; false when it could not, and the caller plays its single sound.
func fire(weapon_class: StringName, at: Vector3, listener: Vector3) -> bool:
	var stock_class := shot_class(weapon_class)
	if stock_class == &"" or not _ready_ok:
		return false
	manager.set(&"listener_position", listener)
	var id: StringName = _stock.call(&"id_of", stock_class)
	var res: DotResult = player.call(&"fire", id, at, weapon_class == ZeeWeaponSound.SUPPRESSED)
	return res.ok and int(res.value_or(0)) > 0


## Measures the room around [param listener] for the tail; call every frame.
func probe(delta: float, listener: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	if _ready_ok:
		enclosure.call(&"step", delta, listener, space)
