class_name ZeeAttachmentPack
extends RefCounted

## This pack's attachments, as one [GSWeaponAttachments] catalogue for an arsenal's `attachments`.
## Numbers only, like the weapons; [method ZeeWeaponArtTable.attachment_art] says how each is drawn, and a gun takes
## one only on a mount its definition lists (`mounts` in [ZeeWeaponPack]'s builders).

# No CHANNEL: built by static functions; GSWeaponAttachments.validate_fitting returns a GSResult for the caller.


## The four, in menu order.
static func attachment_defs() -> Array[GSWeaponAttachment]:
	return [
		_make(ZeeWeaponIds.ATT_RED_DOT, "Red Dot", GSWeaponAttachment.MOUNT_OPTIC,
			"A dot on the glass in place of the iron sights.", {"spread": 0.9}),
		_make(ZeeWeaponIds.ATT_SCOPE, "4x Scope", GSWeaponAttachment.MOUNT_OPTIC,
			"Four-power glass for the long lanes.", {"spread": 0.85}, {}, [ZeeWeaponIds.TAG_SCOPED],
			{GSWeaponAttachment.PARAM_ZOOM: 0.4}),
		_make(ZeeWeaponIds.ATT_SUPPRESSOR, "Suppressor", GSWeaponAttachment.MOUNT_MUZZLE,
			"Quieter and steadier, for a little range.", {"recoil_pitch": 0.9, "max_range": 0.9}, {},
			[ZeeWeaponIds.TAG_SILENCED], {GSWeaponAttachment.PARAM_SUPPRESSED: true}),
		_make(ZeeWeaponIds.ATT_EXTENDED_MAG, "Extended Magazine", GSWeaponAttachment.MOUNT_MAGAZINE,
			"Ten more rounds, a slower change.", {"reload_ticks": 1.1}, {"magazine": 10}),
	]


static func attachments() -> GSWeaponAttachments:
	var out := GSWeaponAttachments.new()
	for att in attachment_defs():
		var _added := out.add(att)
	return out


static func _make(id: StringName, name: String, mount: StringName, description: String, scale: Dictionary,
		add: Dictionary = {}, tags: Array[StringName] = [], params: Dictionary = {}) -> GSWeaponAttachment:
	var att := GSWeaponAttachment.new()
	att.id = id
	att.display_name = name
	att.description = description
	att.mount = mount
	att.scale = scale
	att.add = add
	att.tags_added = tags
	att.params_set = params
	return att
