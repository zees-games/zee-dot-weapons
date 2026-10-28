@tool
extends Node

## Exports and state of ZeeWeaponRig, split out for file size; no behaviour lives here.

## Which role this rig is playing.
enum Role {
	## The player at this keyboard. Predicts, draws a view model and a world model.
	LOCAL,
	## Somebody else, drawn from replicated state. No prediction, no view model.
	REMOTE,
	## A dedicated server or a headless simulation. Draws nothing at all.
	SERVER,
}

@export_group("Role")

@export var role: Role = Role.LOCAL

## True on the machine that decides. Handed to every context and to the arsenal.
## Not the same as [member role]: a listen server's own player is LOCAL and authoritative, a predicting client LOCAL and not;
## folding the two is how a client resolves its own damage.
@export var authority: bool = false

## The rate the carrier's world runs at, handed to the arsenal, which scales every row
## written at another rate to it. Forwarded on every assignment, not only at [method setup],
## because a client learns its server's rate after its rig may already exist.
@export_range(1, 240, 1) var tick_rate: int = 64:
	set(value):
		tick_rate = value
		if arsenal != null:
			arsenal.tick_rate = value

@export_group("Content")

## Every weapon this carrier could hold. Left null, the pack's own catalogue is built.
@export var catalogue: DotWeaponCatalogue = null

@export_group("Wiring")

## The arsenal. Left null, the rig creates one as its own child.
@export var arsenal_ref: DotNodeRef = null

## The first-person rig, usually a child of the camera. Ignored unless
## [member role] is [constant Role.LOCAL].
@export var view_model_ref: DotNodeRef = null

## The third-person weapon. Drawn in every role but [constant Role.SERVER].
@export var world_model_ref: DotNodeRef = null

## The player this carrier is, for the origin and the aim direction.
## Duck-typed through [DotWeaponPlayerBridge], so this addon names no player class.
@export var player_ref: DotNodeRef = null

@export_group("Rules")

## Whether the alt-fire bash is available at all.
@export var allow_bash: bool = true

@export_group("Presentation")

## Whether a use draws a tracer, a flash and an impact, and plays a report.
## On by default: a game with its own effects turns it off and listens to [signal used].
@export var effects: bool = true

@export_group("Aiming")

## The aim button in the command (a `DotWeaponCommand.BUTTON_USER_*` bit set while the aim key is held), so the server sees aiming
## and scales spread and walk speed. 0 leaves both alone. Pick a bit nothing else in the game's command uses.
@export var ads_button: int = DotWeaponCommand.BUTTON_USER_0

## Aiming rules: assign a [ZeeAdsRules] (usually `ZeeAdsRules.load_config()`); null keeps the art's own.
var ads_rules: ZeeAdsRules = null:
	set(value):
		ads_rules = value
		if _view != null:
			_view.ads_rules = value


## The arsenal, once [method setup] has run.
## Public because [ZeeWeaponNet] reads it by name and a HUD asks it about ammunition.
var arsenal: DotWeaponArsenal = null

## Uses so far, for the replication counter. Wraps in [ZeeWeaponNet], not here.
var fire_seq: int = 0

## What the last use was, as a [ZeeWeaponNet] kind number.
var fire_kind: int = ZeeWeaponNet.KIND_NONE

var _view: ZeeViewModel = null
var _standalone_feel: ZeeViewFeel = null
var _world: ZeeWorldModel = null
var _fx: ZeeShotFx = null
var _player: Node = null
var _art: Dictionary = {}

var _bash: ZeeWeaponBash = null
var _ads_move: float = 1.0
var _aim_ticks: int = 0

## The tick the carrier may next bash on.
var _bash_ready_tick: int = 0

## Tick the current reload started on, and how long one round of it takes. -1 when not
## reloading.
var _reload_started: int = -1
var _reload_ticks: int = 0

## The current weapon's magazine last tick of a per-round reload, to hear each shell go in; -1 otherwise.
var _rounds_seen: int = -1

## False until the first presentation tick, so the weapon a carrier spawns with is not an "equip".
var _fx_origin_known: bool = false

## Tick the current switch started on, how long it lasts, and whether it is the holster
## half or the deploy half.
var _switch_started: int = -1
var _switch_ticks: int = 0
var _switch_deploying: bool = false

## Tick a charged weapon's draw started on. -1 when the button is up.
var _charge_started: int = -1

## The weapon the presentation is currently showing, so it is only rebuilt on a change.
var _shown: StringName = &""
var _shown_fit: String = ""

## The tick most recently simulated, so a signal handler knows when it fired.
## Arsenal signals carry no tick; a handler reading a clock would be wrong during a replay.
var _last_tick: int = 0

## Whether the arsenal was mid-switch last tick, so the holster half can be noticed.
var _was_switching: bool = false

var _previous_command: DotWeaponCommand = null
var _replaying: bool = false
var _ready_for_use: bool = false
