@tool
extends Node3D

## State and constants of ZeeViewModel, split out for file size; no behaviour lives here.

var _source_art: ZeeWeaponArt = null

## How far above the body's underside a hand's centre may sit, as a fraction of the gun's length.
const HAND_REACH := 0.06

var _aim_button_was: bool = false
var _arms: ZeeViewArms = null
var _light: DirectionalLight3D = null
var _animated: Node3D = null
var _aim_node: Node3D = null
var _holder: Node3D = null
var _weapon: Node3D = null
var _magazine: Node3D = null
var _attachments: Array[Node3D] = []
var _sight: Node3D = null

## The fitted attachments (what the rig was told) and what [code]zee_attachment_dress.gd[/code] drew for them.
var _fitting: DotWeaponFitting = null
var _dressed: Dictionary = {}

## The iron sight's line, measured at equip in the holder's (model) space: `rear` and `front`
## on the line, or empty when the weapon aims at its written aim_offset. See zee_iron_sight.gd.
var _sight_line: Dictionary = {}

## The holder's transform at full aim when there is a sight line: the line through the eye.
var _sight_aim := Transform3D.IDENTITY

## The camera's near plane the eye relief keeps the gun's back end in front of, plus a margin
## for the kick pushing it back. A view model under no camera assumes Godot's default.
const NEAR_MARGIN := 0.05

var _pose := ZeeWeaponPose.make()
var _wall := ZeeWallSlam.new()
var _wall_excluded: Array[RID] = []
var _art: ZeeWeaponArt = null
var _id: StringName = &""

## Where the right and left hands go, in the Aim node's space, measured at equip.
var _grip_at := Vector3.ZERO
var _fore_at := Vector3.ZERO

## The axis of what each hand holds (a pistol grip, a fore-end, a handle), in the same space.
var _grip_axis := Vector3.UP
var _fore_axis := Vector3.FORWARD
var _grip_radius := 0.0

## Where the magazine sits at rest, in the Aim node's space (the well), or NAN-free zero
## with [member _has_well] false when the weapon has none.
var _well := Vector3.ZERO
var _has_well := false

## A round fed by hand from [member ZeeWeaponArt.load_from], and its keys (`_build_feed_keys`):
## where its push starts, and the bolt's handle forward and drawn back, in the well's space.
var _feeds := false
var _entry := Vector3.ZERO
var _bolted := false
var _bolt := Vector3.ZERO
var _bolt_back := Vector3.ZERO
var _feed_keys: Array = []

## The share of a reload the rounds are fed in, and where in each round's share the hand has it
## at the start of its push and home. Matched by the fed weapons' keys (ZeeWeaponPose
## `RELOAD_KEYS_BOLT`, `_BREAK`, `_MUZZLE`), which hold the gun still across it.
const FEED_START := 0.26
const FEED_END := 0.70
const FEED_AT_ENTRY := 0.45
const FEED_AT_SEAT := 0.82

## Where a fed round is held from the palm: above it and to its right, between the fingertips,
## so the fist is below and beside the round rather than over it. Straight above the palm by
## 3.5 cm, the glove hid every round on the contact sheet.
const FEED_CARRY := Vector3(0.03, 0.06, 0.0)

## The last reload fraction handed in, for the hand that fetches the magazine.
var _reload_fraction: float = 0.0

## Where the muzzle sits in the weapon's own space, measured when the model was built.
var _muzzle := Vector3.ZERO

## The look angles last frame, so sway can be driven by how far the view moved.
var _last_look := Vector2.ZERO
var _look_seen := false

var _built: bool = false

## Posture for this frame, written by whoever drives the rig.
## Plain fields, because a remote player, bot or replay has no controller to ask; the default is standing still.
var _speed: float = 0.0
var _on_floor: bool = true
var _crouched: bool = false
var _look := Vector2.ZERO

## Sideways ground speed, m/s, positive to the right: handed in by [method drive], else
## measured from how this node moved between frames (a game that never heard of strafing
## still gets the tilt). NAN is "not handed in".
var _strafe_given: float = NAN
var _last_origin := Vector3.ZERO
var _origin_seen := false

## Whether the aim button is held, and how far the weapon has come up to the eye.
## Presentation only: never part of a command or a snapshot.
var _aim_held: bool = false
var _aim_fraction: float = 0.0

## The vertical field of view, in degrees, the hands are drawn at whatever the camera's is. 0 uses the camera's lens.
## Poses were set under 90 degrees; a different lens would make the same pose a different gun.
## Done by scaling X and Y by tan(camera/2)/tan(this/2) with Z alone, which is exact for a perspective projection and keeps depth sorting.
@export var hands_fov: float = 90.0

## How much of the size a narrower [member hands_fov] adds is given back by drawing the hands farther away, 0 to 1.
## 1 keeps the size at [constant REFERENCE_FOV]; wider than the reference pulls the hands in, never past [constant MAX_PULL_IN].
@export_range(0.0, 1.0, 0.05) var hands_depth_comp: float = 1.0

## The field of view the pack's poses were authored under, vertical degrees.
const REFERENCE_FOV := 90.0
## The depth the gun's middle sits at under the reference lens, in metres.
const REFERENCE_DEPTH := 0.55
## The most the hands are drawn closer than authored, in metres.
const MAX_PULL_IN := 0.1

## Seconds to blend the sprint carry in or out.
const SPRINT_SECONDS := 0.2

## Whether sprinting changes the pose (a game's cvar to turn it off).
var sprint_pose: bool = true

var _sprinting: bool = false
var _sprint: float = 0.0
