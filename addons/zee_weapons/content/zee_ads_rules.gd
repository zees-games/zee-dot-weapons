class_name ZeeAdsRules
extends Resource

## Aiming down sights, as a server owner sets it: one default profile and overrides by weapon id, assigned as `rig.ads_rules = ZeeAdsRules.load_config()`.
## Spread and move speed apply in [ZeeWeaponRig] from the command's aim bit (server and prediction alike); time, zoom, sway and toggle are the view model's.
## Layered through [DotAddonConfig] (`cfg/addons/zee_weapons/*.yml`, env, argv); shape: `ads: {default: {zoom: 0.0}, weapons: {sniper: {zoom: 0.25}}}`.

## The keys the simulation reads (spread, move speed, whether aiming exists). A client predicts with
## them, so they are replicated; the rest is the view model's own and stays local.
const PREDICTED := ["enabled", "aim_time", "move_speed_multiplier", "spread_multiplier", "recoil_multiplier", "quickscope_fire_min"]

## The replicated cvar holding [method to_wire].
const CVAR := "zee_ads_rules"

## DotClientLink skips a replicated cvar over 1024 bytes without a word; warn from here.
const WIRE_WARN_BYTES := 1000

const CHANNEL := "zee.ads"
const ADDON := "zee_weapons"

## Every key, its default and its range. `aim_time` and `zoom` of 0 mean "the weapon's art".
const SPECS := {
	"enabled": {"default": true},
	"aim_time": {"default": 0.0, "min": 0.0, "max": 2.0},
	"zoom": {"default": 0.0, "min": 0.0, "max": 1.0},
	"move_speed_multiplier": {"default": 0.8, "min": 0.05, "max": 1.0},
	"spread_multiplier": {"default": 0.6, "min": 0.0, "max": 1.0},
	"recoil_multiplier": {"default": 0.6, "min": 0.0, "max": 1.0},
	"sway_multiplier": {"default": 0.5, "min": 0.0, "max": 1.0},
	"toggle": {"default": false},
	"quickscope_fire_min": {"default": 0.0, "min": 0.0, "max": 1.0},
	"scope_fade_start": {"default": 0.6, "min": 0.0, "max": 0.99},
	"scope_lens_min": {"default": 0.3, "min": 0.05, "max": 1.0},
	"view_scale": {"default": 2.0, "min": 0.5, "max": 4.0},
	"view_shift_x": {"default": 0.12, "min": -0.5, "max": 0.5},
	"view_shift_y": {"default": -0.10, "min": -0.5, "max": 0.5},
	"view_shift_z": {"default": -0.15, "min": -0.5, "max": 0.5},
	"thrown_span": {"default": 0.31, "min": 0.05, "max": 1.0},
	"hip_cant": {"default": 0.3, "min": 0.0, "max": 1.0},
	"hip_lean": {"default": 25.0, "min": -30.0, "max": 60.0},
	"hit_flinch_multiplier": {"default": 1.0, "min": 0.0, "max": 5.0},
}

## The profile every weapon without an override uses.
var base: Dictionary = defaults()
## Weapon id (String) -> only the keys that weapon changes.
var weapons: Dictionary = {}
## Weapon id (String) -> keys a weapon's own profile sets (`extra: params: ads:`); below the server's `weapons`, above the default.
var def_rows: Dictionary = {}


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
	if row.has(key):
		return row[key]
	var own: Dictionary = def_rows.get(String(id), {})
	return own.get(key, base.get(key, SPECS[key]["default"]))


## Takes a weapon def's `params["ads"]` as that weapon's profile-owned values; keys out of range or unknown are dropped.
func set_def_row(id: StringName, row: Variant) -> void:
	var clean := {}
	if row is Dictionary:
		var scratch := ZeeAdsRules.new()
		for key: String in (row as Dictionary):
			if scratch.set_value(&"x", key, (row as Dictionary)[key]):
				clean[key] = scratch.weapons["x"][key]
	if clean.is_empty():
		def_rows.erase(String(id))
	else:
		def_rows[String(id)] = clean


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


## What is left of the recoil kick at full aim.
func recoil_for(id: StringName) -> float:
	return float(value_for(id, "recoil_multiplier"))


## What is left of the sway and bob at full aim, on top of `mp_vm_aim_steadiness`.
func sway_for(id: StringName) -> float:
	return float(value_for(id, "sway_multiplier"))


## How much bigger than the art's own hip scale the gun is drawn (aimed, the sight still lines up).
func view_scale_for(id: StringName) -> float:
	return float(value_for(id, "view_scale"))


## How far into the aim-in (0 to 1) the weapon may fire: 0 fires at any moment (a quick scope), 1 only once fully aimed.
func quickscope_fire_min_for(id: StringName) -> float:
	return float(value_for(id, "quickscope_fire_min"))


## Aim-in progress at which a scope's black surround starts to fade in; it is full at 1.
func scope_fade_start_for(id: StringName) -> float:
	return float(value_for(id, "scope_fade_start"))


## The scope lens's size at the start of the aim-in, as a share of its full size; it grows to 1.
func scope_lens_min_for(id: StringName) -> float:
	return float(value_for(id, "scope_lens_min"))


## Metres the longest side of a thrown weapon's model is drawn at, so a small model and a large one fill the same share of the screen.
func thrown_span_for(id: StringName) -> float:
	return float(value_for(id, "thrown_span"))


## How much of the art's hip roll is kept: 1 is the table's full cant, 0 holds the gun upright.
func hip_cant_for(id: StringName) -> float:
	return float(value_for(id, "hip_cant"))


## Degrees the barrel leans toward the screen's middle at the hip, as drawn. The view model turns the gun to it.
func hip_lean_for(id: StringName) -> float:
	return float(value_for(id, "hip_lean"))


## How much a hit shakes the view and wobbles the aim while this weapon is held, on top of the server's `sv_hit_*` numbers: 0 steady, 1 as set.
func hit_flinch_for(id: StringName) -> float:
	return float(value_for(id, "hit_flinch_multiplier"))


## Metres added to the art's hip place (view space: +X right, +Y up, +Z toward the eye).
func view_shift_for(id: StringName) -> Vector3:
	return Vector3(float(value_for(id, "view_shift_x")), float(value_for(id, "view_shift_y")),
		float(value_for(id, "view_shift_z")))


## The simulation-side numbers as one canonical JSON line, for a replicated cvar or a handshake.
func to_wire() -> String:
	var d := {}
	for key: String in PREDICTED:
		d[key] = base.get(key, SPECS[key]["default"])
	var w := {}
	for id: String in weapons:
		var row := {}
		for key: String in PREDICTED:
			if (weapons[id] as Dictionary).has(key):
				row[key] = weapons[id][key]
		if not row.is_empty():
			w[id] = row
	return JSON.stringify({"d": d, "w": w}, "", true)


## A short hash of [method to_wire], to compare two ends cheaply.
func wire_hash() -> String:
	return to_wire().sha256_text().left(12)


## Replaces the simulation-side numbers with a server's [method to_wire]; false (state unchanged)
## when the text is not that. The view-side keys are left alone.
func adopt_wire(text: String) -> bool:
	# JSON.new().parse, not parse_string: a bad value from the wire is an answer here, not an engine error.
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var parsed: Variant = json.data
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("d", {}) is Dictionary) or not ((parsed as Dictionary).get("w", {}) is Dictionary):
		return false
	if text == to_wire():
		return true
	for key: String in PREDICTED:
		base[key] = SPECS[key]["default"]
	for id: String in weapons:
		for key: String in PREDICTED:
			(weapons[id] as Dictionary).erase(key)
	var tree: Dictionary = parsed
	for key: String in tree["d"]:
		if key in PREDICTED:
			var _ok := set_value(&"", key, tree["d"][key])
	for id: String in tree["w"]:
		if tree["w"][id] is Dictionary:
			for key: String in tree["w"][id]:
				if key in PREDICTED:
					var _ok := set_value(StringName(id), key, tree["w"][id][key])
	changed.emit()
	return true


## Registers the replicated cvar on the server ([param add] is the module's `add_cvar`, taking flags
## as a fourth argument; [param flags] should carry REPLICATED). Returns the cvars made.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var size := to_wire().length()
	if size > WIRE_WARN_BYTES:
		DotLog.warn(CHANNEL, "ads rules too long to replicate; clients will not receive them", {"bytes": size, "limit": WIRE_WARN_BYTES})
	var made: Variant = add.call(CVAR, to_wire(), "Aim-down-sights numbers the simulation uses (JSON). Players follow it, so their prediction agrees.", flags)
	if not (made is Object):
		return []
	var cv := made as Object
	# An operator's edit of the cvar reaches the simulation; the handler holds no reference to `cv`.
	if cv.has_signal(&"changed"):
		cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: var _ok := adopt_wire(str(new_value)))
	if cv.has_method(&"get_string"):
		var held := String(cv.call(&"get_string"))
		if held != "" and held != to_wire():
			var _ok := adopt_wire(held)
	return [cv]


## Follows a server's value through its link; false for a link that cannot replicate cvars.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	var held := String(source.call(&"replicated_cvar", CVAR, ""))
	if held != "":
		var _ok := adopt_wire(held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)
	return true


func _on_replicated(cvar_name: String, value: String) -> void:
	if cvar_name == CVAR:
		var _ok := adopt_wire(value)


func describe() -> Dictionary:
	return {"default": base.duplicate(), "weapons": weapons.duplicate(true)}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray(["ads default: %s" % str(base)])
	for id: String in weapons:
		lines.append("ads %s: %s" % [id, str(weapons[id])])
	return lines
