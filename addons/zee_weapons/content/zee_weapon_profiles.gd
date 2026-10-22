class_name ZeeWeaponProfiles
extends RefCounted

## Weapon profiles (`cfg/addons/<addon>/weapon/<id>.yml`) laid over a pack's code-built [DotWeaponDef]s.
##
## A profile overlays only the keys its files set ([member DotProfile.file_keys]); everything
## else stays what the builder made, so a one-key yml retunes one number. Common [DotWeaponDef]
## fields sit at the top, `extra: tuning:` holds the [DotWeaponBallistics] numbers and
## `extra: params:` the def's params. Upgrades (`weapon/<id>/upgrades/*.yml`) name the same
## keys flat: `tuning.damage`, `params.bash_damage`, `magazine`. Shared by the packs that
## extend zee (zed-dot-weapons passes its own addon name).

const CHANNEL := "zee.profiles"
const TUNING := "tuning"
const PARAMS := "params"
const SKIP := ["menu", "enabled"]


## The profile set of [param addon]; a mounted pack's cfg root ([param pack_root]) is the weakest root.
static func profile_set(addon: String, game: String = "", pack_root: String = "", base_roots: PackedStringArray = PackedStringArray(), layer: Variant = null) -> DotProfileSet:
	var roots := base_roots if not base_roots.is_empty() else DotProfileSet.default_roots()
	if pack_root != "":
		roots = PackedStringArray([pack_root]) + roots
	return DotWeaponProfiles.make_set(addon, game, roots, layer)


## Lays the profiles over [param defs] in place; a profile with no weapon here is ignored with a WARN.
## Returns the profiles that failed to load (their weapons keep the builder's numbers).
static func tune(defs: Array[DotWeaponDef], set: DotProfileSet) -> PackedStringArray:
	var errors := PackedStringArray()
	var ids := set.list_ids()
	if ids.is_empty():
		return errors
	var by_id := {}
	for def in defs:
		by_id[String(def.id)] = def
	for id in ids:
		if not by_id.has(id):
			continue
		var res := set.load_profile(id)
		if not res.ok:
			errors.append(res.error.message)
			DotLog.error(CHANNEL, "weapon profile skipped", {"id": id, "why": res.error.message})
			continue
		apply_flat(by_id[id], file_flat(res.value))
	set.clear_cache()
	return errors


## The keys [param p]'s files set, as the flat form [method flat_of] writes.
static func file_flat(p: DotProfile) -> Dictionary:
	var out := {}
	for path in p.file_keys:
		var parts := String(path).split(".")
		if parts[0] == DotProfileSet.EXTRA_KEY:
			if parts.size() > 2:
				out[".".join(parts.slice(1))] = DotYaml.at(p.extra, ".".join(parts.slice(1)))
		elif parts[0] not in SKIP:
			out[parts[0]] = p.values[parts[0]]
	return out


## Applies a flat dictionary (see [method flat_of]) to [param def]; unknown tuning keys are logged and skipped.
static func apply_flat(def: DotWeaponDef, flat: Dictionary) -> void:
	var common := {}
	for key: String in flat:
		if key.begins_with(TUNING + "."):
			_set_tuning(def, key.trim_prefix(TUNING + "."), flat[key])
		elif key.begins_with(PARAMS + "."):
			var pk := StringName(key.trim_prefix(PARAMS + "."))
			def.params[pk] = _coerce(def.params.get(pk), flat[key])
		else:
			common[key] = flat[key]
	DotWeaponProfiles.apply_common(def, common)


static func _set_tuning(def: DotWeaponDef, name: String, value: Variant) -> void:
	if def.tuning == null or not (name in def.tuning) or typeof(def.tuning.get(name)) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
		DotLog.warn(CHANNEL, "unknown tuning key in profile; ignored", {"weapon": String(def.id), "key": name})
		return
	def.tuning.set(name, _coerce(def.tuning.get(name), value))


## Keeps the builder's type, so `magazine: 30.0` stays an int. A new key (no current value) is taken as written.
static func _coerce(current: Variant, given: Variant) -> Variant:
	if current is bool or current == null:
		return given
	if current is int and (given is int or given is float):
		return int(round(float(given)))
	if current is float and (given is int or given is float):
		return float(given)
	return given


## Every tunable of [param def] as one flat dictionary: the schema keys, `tuning.*` and `params.*`.
static func flat_of(def: DotWeaponDef) -> Dictionary:
	var out := {
		"name": def.display_name, "description": def.description,
		"tags": Array(def.tags).map(func(t: StringName) -> String: return String(t)),
		"behaviour": def.behaviour_path, "slot": def.slot, "authored_tick_rate": def.authored_tick_rate,
		"deploy_ticks": def.deploy_ticks, "holster_ticks": def.holster_ticks,
		"fire_mode": DotWeaponProfiles.FIRE_MODES[def.fire_mode],
		"use_interval_ticks": def.use_interval_ticks, "burst_count": def.burst_count,
		"burst_interval_ticks": def.burst_interval_ticks, "charge_ticks": def.charge_ticks,
		"charge_requires_min": def.charge_requires_min, "min_charge": def.min_charge,
		"ammo_type": String(def.ammo_type), "magazine": def.magazine, "reserve": def.reserve,
		"reserve_max": def.reserve_max, "cost_per_use": def.cost_per_use,
		"infinite_reserve": def.infinite_reserve, "reload_ticks": def.reload_ticks,
		"reload_per_round": def.reload_per_round, "reload_start_ticks": def.reload_start_ticks,
		"auto_reload": def.auto_reload,
		"mounts": Array(def.mounts).map(func(m: StringName) -> String: return String(m)),
	}
	if def.tuning != null:
		for p: Dictionary in def.tuning.get_property_list():
			if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(p["type"]) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				out["%s.%s" % [TUNING, p["name"]]] = def.tuning.get(p["name"])
	for k in def.params:
		if def.params[k] is int or def.params[k] is float or def.params[k] is bool or def.params[k] is String:
			out["%s.%s" % [PARAMS, k]] = def.params[k]
	return out


## The yml text of [param def]'s builder numbers: what the shipped `weapon/<id>.yml` holds.
static func to_yaml(def: DotWeaponDef, addon_title: String) -> String:
	var flat := flat_of(def)
	var top: PackedStringArray = ["# %s: %s. Durations are ticks at %d Hz; delete a key to keep the builder's value." % [addon_title, def.id, def.authored_tick_rate]]
	var tuning: PackedStringArray = []
	var params: PackedStringArray = []
	for key: String in flat:
		if key.begins_with(TUNING + "."):
			tuning.append("    %s: %s" % [key.trim_prefix(TUNING + "."), _scalar(flat[key])])
		elif key.begins_with(PARAMS + "."):
			params.append("    %s: %s" % [key.trim_prefix(PARAMS + "."), _scalar(flat[key])])
		else:
			top.append("%s: %s" % [key, _scalar(flat[key])])
	top.append("extra:")
	if not tuning.is_empty():
		top.append("  tuning:")
		top.append_array(tuning)
	if not params.is_empty():
		top.append("  params:")
		top.append_array(params)
	return "\n".join(top) + "\n"


static func _scalar(v: Variant) -> String:
	if v is String:
		return JSON.stringify(v)
	if v is Array:
		return "[" + ", ".join(PackedStringArray((v as Array).map(func(x: Variant) -> String: return _scalar(x)))) + "]"
	if v is float:
		return "%s" % v if is_finite(v) else "0.0"
	return str(v)


## Where the shipped yml for [param id] lives under [param root]: the folder form when the weapon has one (for its upgrades).
static func profile_path(addon: String, id: String, root: String = "res://cfg") -> String:
	var base := root.path_join("addons").path_join(addon).path_join("weapon")
	if DirAccess.dir_exists_absolute(base.path_join(id)):
		return base.path_join(id).path_join("%s.yml" % id)
	return base.path_join("%s.yml" % id)


## [param def] with the upgrades [param ids] applied, a copy; value `{def, cost}`.
static func upgraded(def: DotWeaponDef, ids: Array, set: DotProfileSet) -> DotResult:
	var ups := DotWeaponProfiles.upgrade_set(set, String(def.id))
	var res := DotWeaponProfiles.apply_upgrades(flat_of(def), ups, ids)
	ups.clear_cache()
	if not res.ok:
		return res
	var copy := def.duplicate(true) as DotWeaponDef
	apply_flat(copy, res.value["values"])
	return DotResult.success({"def": copy, "cost": res.value["cost"]})
