extends RefCounted
## The README studio shot's model hook (tools/readme.cfg [shot] model_script): weapon id -> the gun as a player
## sees it in hand, from the pack's own art table: the model turned muzzle toward -Z, its magazine and its attachments.

const Dress := preload("res://addons/zee_weapons/view/zee_attachment_dress.gd")
const ReloadParts := preload("res://addons/zee_weapons/view/zee_reload_parts.gd")


static func instantiate(id: StringName) -> Node3D:
	var art: ZeeWeaponArt = ZeeWeaponArtTable.table().get(id)
	if art == null or not art.has_model():
		return null
	var weapon := ZeeModelCache.instantiate(art.model_path)
	if weapon == null:
		return null
	var root := Node3D.new()
	var holder := Node3D.new()
	holder.basis = art.orientation()
	root.add_child(holder)
	Dress.ensure_sockets(weapon, art)
	holder.add_child(weapon)
	if art.has_magazine() and not art.magazine_loose:
		var mag: Node3D = ZeeModelCache.instantiate(art.magazine_path) if art.magazine_path != "" else ReloadParts.build(art.magazine_part)
		if mag != null:
			holder.add_child(mag)
			mag.transform = art.magazine_transform()
	Dress.art_parts(art, holder)
	return root
