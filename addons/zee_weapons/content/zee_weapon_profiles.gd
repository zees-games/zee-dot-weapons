class_name ZeeWeaponProfiles
extends RefCounted

## Shim over [GSWeaponProfiles]' overlay (profiles laid over code-built defs); kept for the old name.
## zed-gs-weapons and other packs may call [GSWeaponProfiles] directly.


static func profile_set(addon: String, game: String = "", pack_root: String = "", base_roots: PackedStringArray = PackedStringArray(), layer: Variant = null) -> GSProfileSet:
	return GSWeaponProfiles.overlay_set(addon, game, pack_root, base_roots, layer)


static func tune(defs: Array[GSWeaponDef], set: GSProfileSet) -> PackedStringArray:
	return GSWeaponProfiles.tune(defs, set)


static func file_flat(p: GSProfile) -> Dictionary:
	return GSWeaponProfiles.file_flat(p)


static func apply_flat(def: GSWeaponDef, flat: Dictionary) -> void:
	GSWeaponProfiles.apply_flat(def, flat)


static func flat_of(def: GSWeaponDef) -> Dictionary:
	return GSWeaponProfiles.flat_of(def)


static func to_yaml(def: GSWeaponDef, addon_title: String) -> String:
	return GSWeaponProfiles.to_yaml(def, addon_title)


static func profile_path(addon: String, id: String, root: String = "res://cfg") -> String:
	return GSWeaponProfiles.profile_path(addon, id, root)


static func upgraded(def: GSWeaponDef, ids: Array, set: GSProfileSet) -> GSResult:
	return GSWeaponProfiles.upgraded(def, ids, set)
