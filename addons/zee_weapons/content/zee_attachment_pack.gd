class_name ZeeAttachmentPack
extends RefCounted

## This pack's attachments, as one [DotWeaponAttachments] catalogue for an arsenal's `attachments`.
## Numbers only, like the weapons; [method ZeeWeaponArtTable.attachment_art] says how each is drawn, and a gun takes
## one only on a mount its definition lists (`mounts` in [ZeeWeaponPack]'s builders).

# No CHANNEL: built by static functions; DotWeaponAttachments.validate_fitting returns a DotResult for the caller.


## The four, in menu order.
static func attachment_defs() -> Array[DotWeaponAttachment]:
	return [
		_make(ZeeWeaponIds.ATT_RED_DOT, "Red Dot", DotWeaponAttachment.MOUNT_OPTIC,
			"A dot on the glass in place of the iron sights.", {"spread": 0.9}),
		_make(ZeeWeaponIds.ATT_SCOPE, "4x Scope", DotWeaponAttachment.MOUNT_OPTIC,
			"Four-power glass for the long lanes.", {"spread": 0.85}, {}, [ZeeWeaponIds.TAG_SCOPED],
			{DotWeaponAttachment.PARAM_ZOOM: 0.4}),
		_make(ZeeWeaponIds.ATT_SUPPRESSOR, "Suppressor", DotWeaponAttachment.MOUNT_MUZZLE,
			"Quieter and steadier, for a little range.", {"recoil_pitch": 0.9, "max_range": 0.9}, {},
			[ZeeWeaponIds.TAG_SILENCED], {DotWeaponAttachment.PARAM_SUPPRESSED: true}),
		_make(ZeeWeaponIds.ATT_EXTENDED_MAG, "Extended Magazine", DotWeaponAttachment.MOUNT_MAGAZINE,
			"Ten more rounds, a slower change.", {"reload_ticks": 1.1}, {"magazine": 10}),
	]


static func attachments() -> DotWeaponAttachments:
	var out := DotWeaponAttachments.new()
	for att in attachment_defs():
		var _added := out.add(att)
	return out


static func _make(id: StringName, name: String, mount: StringName, description: String, scale: Dictionary,
		add: Dictionary = {}, tags: Array[StringName] = [], params: Dictionary = {}) -> DotWeaponAttachment:
	var att := DotWeaponAttachment.new()
	att.id = id
	att.display_name = name
	att.description = description
	att.mount = mount
	att.scale = scale
	att.add = add
	att.tags_added = tags
	att.params_set = params
	return att
