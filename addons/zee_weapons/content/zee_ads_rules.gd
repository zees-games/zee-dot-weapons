class_name ZeeAdsRules
extends Resource

## Aiming down sights, as a server owner sets it: one default profile and overrides by weapon id.
##
## A game assigns one to the rig (`rig.ads_rules = ZeeAdsRules.load_config()`); with none, every
## aimable weapon aims by its art's own numbers. The server-side numbers (spread, move speed) are
## applied by [ZeeWeaponRig] from the command's aim button, so they hold on the server and in
## prediction alike; the rest (time, zoom, sway, toggle) is the view model's.
##
## [b]Layers[/b] (through [DotAddonConfig], addon `zee_weapons`): the defaults below < every
## `cfg/addons/zee_weapons/*.yml` < `cfg/game/<game>/...` < `cfg/server/addons/zee_weapons/*.yml`
## < environment (`ZEE_WEAPONS_ADS_DEFAULT_ZOOM`) < argv (`--zee_weapons.ads.default.zoom=0.7`).
## Shape of the file, weapon keys by weapon id:
## [codeblock]
## ads:
##   default:
##     zoom: 0.0
##     spread_multiplier: 0.6
##   weapons:
##     sniper:
##       zoom: 0.25
##     pistol:
##       enabled: false
## [/codeblock]

const CHANNEL := "zee.ads"
const ADDON := "zee_weapons"

## Every key, its default and its range. `aim_time` and `zoom` of 0 mean "the weapon's art".
const SPECS := {
	"enabled": {"default": true},
	"aim_time": {"default": 0.0, "min": 0.0, "max": 2.0},
	"zoom": {"default": 0.0, "min": 0.0, "max": 1.0},
	"move_speed_multiplier": {"default": 0.8, "min": 0.05, "max": 1.0},
	"spread_multiplier": {"default": 0.6, "min": 0.0, "max": 1.0},
	"sway_multiplier": {"default": 0.5, "min": 0.0, "max": 1.0},
	"toggle": {"default": false},
	"view_scale": {"default": 1.2, "min": 0.5, "max": 2.5},
	"view_shift_x": {"default": 0.0, "min": -0.5, "max": 0.5},
	"view_shift_y": {"default": 0.03, "min": -0.5, "max": 0.5},
	"view_shift_z": {"default": 0.0, "min": -0.5, "max": 0.5},
}

## The profile every weapon without an override uses.
var base: Dictionary = defaults()
## Weapon id (String) -> only the keys that weapon changes.
var weapons: Dictionary = {}


static func defaults() -> Dictionary:
	var out := {}
	for key: String in SPECS:
		out[key] = SPECS[key]["default"]
	return out


## Reads the layered config; a bad file is logged and the defaults stand.
static func load_config(addon: String = ADDON) -> ZeeAdsRules:
	var rules := ZeeAdsRules.new()
	var res := DotAddonConfig.load_dir(addon, {"ads": {"default": defaults(), "weapons": {}}})
	if not res.ok:
		DotLog.warn(CHANNEL, "ads config refused", {"error": str(res.error)})
		return rules
	rules.apply_tree(DotAddonConfig.get_value(res.value, "ads", {}) as Dictionary)
	return rules


## Applies an `ads` tree (`default` and `weapons`). A key outside its range or of the wrong type
## is refused with a log line and the rest stands.
func apply_tree(tree: Dictionary) -> void:
	var def: Variant = tree.get("default", {})
	if def is Dictionary:
		for key: String in (def as Dictionary):
			var _ok := set_value(&"", key, (def as Dictionary)[key])
	var per: Variant = tree.get("weapons", {})
	if per is Dictionary:
		for id: Variant in (per as Dictionary):
			var row: Variant = (per as Dictionary)[id]
			if row is Dictionary:
				for key: String in (row as Dictionary):
					var _ok := set_value(StringName(str(id)), key, (row as Dictionary)[key])


## Sets one key on the default (empty [param id]) or on a weapon. False when refused.
func set_value(id: StringName, key: String, value: Variant) -> bool:
	if not SPECS.has(key):
		DotLog.warn(CHANNEL, "unknown ads key", {"key": key, "weapon": id})
		return false
	var spec: Dictionary = SPECS[key]
	var clean: Variant = null
	if spec["default"] is bool:
		if value is bool:
			clean = value
	elif (value is float or value is int) and is_finite(float(value)):
		var number := float(value)
		if number >= float(spec["min"]) and number <= float(spec["max"]):
			clean = number
	if clean == null:
		DotLog.warn(CHANNEL, "ads value refused", {"key": key, "value": str(value), "weapon": id})
		return false
	if id == &"":
		base[key] = clean
	else:
		var row: Dictionary = weapons.get(String(id), {})
		row[key] = clean
		weapons[String(id)] = row
	return true


## The effective value of [param key] for [param id]: its override, else the default.
func value_for(id: StringName, key: String) -> Variant:
	var row: Dictionary = weapons.get(String(id), {})
	return row.get(key, base.get(key, SPECS[key]["default"]))


func enabled_for(id: StringName) -> bool:
	return bool(value_for(id, "enabled"))


func toggle_for(id: StringName) -> bool:
	return bool(value_for(id, "toggle"))


## Seconds from hip to sight; [param art_time] is the weapon's own, used when the profile says 0.
func aim_time_for(id: StringName, art_time: float) -> float:
	var t := float(value_for(id, "aim_time"))
	return t if t > 0.0 else art_time


## The field-of-view multiplier at full aim; [param art_zoom] when the profile says 0.
func zoom_for(id: StringName, art_zoom: float) -> float:
	var z := float(value_for(id, "zoom"))
	return z if z > 0.0 else art_zoom


## The walk speed multiplier while aiming (1 when this weapon cannot aim).
func move_speed_for(id: StringName) -> float:
	return float(value_for(id, "move_speed_multiplier")) if enabled_for(id) else 1.0


func spread_for(id: StringName) -> float:
	return float(value_for(id, "spread_multiplier")) if enabled_for(id) else 1.0


## What is left of the sway and bob at full aim, on top of `mp_vm_aim_steadiness`.
func sway_for(id: StringName) -> float:
	return float(value_for(id, "sway_multiplier"))


## How much bigger than the art's own hip scale the gun is drawn (aimed, the sight still lines up).
func view_scale_for(id: StringName) -> float:
	return float(value_for(id, "view_scale"))


## Metres added to the art's hip place (view space: +X right, +Y up, +Z toward the eye).
func view_shift_for(id: StringName) -> Vector3:
	return Vector3(float(value_for(id, "view_shift_x")), float(value_for(id, "view_shift_y")),
		float(value_for(id, "view_shift_z")))


func describe() -> Dictionary:
	return {"default": base.duplicate(), "weapons": weapons.duplicate(true)}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["ads default: %s" % str(base)])
	for id: String in weapons:
		lines.append("ads %s: %s" % [id, str(weapons[id])])
	return lines
