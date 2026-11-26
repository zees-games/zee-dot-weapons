class_name ZeeAttachmentBake
extends RefCounted

## Bakes the attach and detach clips of a pack attachment model (scope, silencer, clip) into Nightly's animation sidecar (version 1, see [ZeeAnimBake]): the part slides to its mount along the axis it
## really mounts on, a silencer turning as it screws on. The clips are authored here (a mount slide is not procedural view motion); the model rests at the origin, which is where it sits on a gun.
## Models with nothing to mount (ammo, the arms, the range's props) stay static and get no sidecar: [method static_models].

const ATTACH_SECONDS := 0.45
const HOLD_SECONDS := 0.15
## Metres the part starts from the mount, and the turns a silencer makes.
const SCOPE_LIFT := 0.12
const SILENCER_PULL := 0.18
const SILENCER_TURNS := 1.5
const CLIP_DROP := 0.14
## The models that mount: file stem -> mount kind.
const KINDS := {
	"scope-small": &"optic", "scope-large-a": &"optic", "scope-large-b": &"optic",
	"silencer-small": &"muzzle", "silencer-larger": &"muzzle",
	"clip-small": &"magazine", "clip-large": &"magazine",
}


## The mount kind of a model path (optic, muzzle, magazine), or &"" for a model that does not mount.
static func kind_of(model_path: String) -> StringName:
	return KINDS.get(model_path.get_file().get_basename(), &"")


## Every model under res://assets/ that stays static: no mount, no sidecar.
static func static_models() -> Array[String]:
	var out: Array[String] = []
	for dir in ["ammo", "arms", "range"]:
		for f in DirAccess.get_files_at("res://assets/%s" % dir):
			if f.ends_with(".glb"):
				out.append("res://assets/%s/%s" % [dir, f])
	out.sort()
	return out


## The attachment models of the pack, one path each.
static func models() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(ZeeWeaponArtTable.ATTACHMENTS):
		if f.ends_with(".glb") and kind_of(f) != &"":
			out.append(ZeeWeaponArtTable.ATTACHMENTS + f)
	out.sort()
	return out


## The sidecar for the attachment model [param model_path]: clips attach and detach. {} for a model that does not mount.
static func bake(model_path: String) -> Dictionary:
	var kind := kind_of(model_path)
	if kind == &"":
		return {}
	var stem := model_path.get_file().get_basename()
	var move := int(ATTACH_SECONDS * ZeeAnimBake.FPS)
	var hold := int(HOLD_SECONDS * ZeeAnimBake.FPS)
	var attach: Array = []
	var detach: Array = []
	for i in move + hold:
		# attach: travel for [move] frames, then hold seated; detach: hold seated, then travel back
		attach.append_array(ZeeAnimBake.t7(_pose(kind, 1.0 - _ease(float(i) / float(move)))))
		detach.append_array(ZeeAnimBake.t7(_pose(kind, _ease(float(maxi(i - hold, 0)) / float(move)))))
	return {
		"version": ZeeAnimBake.VERSION,
		"weapon": stem,
		"model": stem,
		"asset": ZeeAnimBake.asset_of(model_path),
		"fps": ZeeAnimBake.FPS,
		"lens": ZeeAnimBake.lens(),
		"nodes": {"bolt": "", "magazine": ""},
		"clips": [_clip("attach", attach, move + hold), _clip("detach", detach, move + hold)],
	}


static func _clip(clip_name: String, values: Array, frames: int) -> Dictionary:
	return {
		"name": clip_name, "length": snappedf(float(frames) / float(ZeeAnimBake.FPS), 0.001), "frames": frames, "loop": false,
		"tracks": [{"target": "weapon", "path": "transform", "values": ZeeAnimBake.rounded(values)}],
	}


## The part's transform when it is [param away] from the mount (1 = clear, 0 = seated).
static func _pose(kind: StringName, away: float) -> Transform3D:
	match kind:
		&"optic":
			return Transform3D(Basis.IDENTITY, Vector3(0.0, SCOPE_LIFT * away, 0.0))
		&"magazine":
			return Transform3D(Basis.IDENTITY, Vector3(0.0, -CLIP_DROP * away, 0.0))
	# muzzle: pulled forward (-Z) and unscrewed
	return Transform3D(Basis(Vector3.BACK, TAU * SILENCER_TURNS * away), Vector3(0.0, 0.0, -SILENCER_PULL * away))


static func _ease(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
