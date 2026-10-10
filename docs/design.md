# Design: what the pack is, and the seams it uses

## The one idea

**dot-weapon decides that a use happened and refuses to draw anything. This is the half that draws.**

That refusal is dot-weapon being right: a dedicated server resolving thirty carriers must never need a mesh, and a `DotWeaponDef` that carried one could not be validated at boot by a server with no content installed. It leaves a weapon nobody can see, and every game was filling that gap privately and differently.

So the split is the same one, one level out. `ZeeWeaponPack` is documents a server validates; `ZeeWeaponArtTable` is filenames a client loads; and **a headless build never touches the second one**. If `ZeeModelCache` is reached in a headless run, something has asked a simulation question of the art layer.

## The prefix is `Zee`, not `Dot`

`class_name` is global and these addons install side by side. `Dot` is the family's namespace and this is a pack on top of it, so it takes its own; a `DotWeaponArt` here would collide the first time dot-weapon grew one.

## Weapons are named by role, never by model

`blaster-a` through `blaster-r` is the order the art was exported in and means nothing to a player, a console or a loadout. `ZeeWeaponIds` names roles (`SNIPER`, `DRUM_SHOTGUN`, `BEAMER`) and **`ZeeWeaponArtTable` is the only file that contains a filename**: replacing the art is replacing one table.

The roles were assigned from measurements, not filenames: the two widest short models became the revolver and the drum shotgun (width reads as a cylinder), the slimmest the beam weapon, the 1.39 m one the sniper, the 0.42 m one the derringer.

## Durations are ticks

Every duration in `ZeeWeaponPack` is in ticks, converted once at the top (`rpm_ticks`), and the table is tuned for `ZeeWeaponPack.TICK_RATE`, 64. Nothing in the pack, the rig or dot-weapon's arsenal scales a duration by the running tick rate, so on a 128 Hz server every weapon fires, reloads and deploys twice as fast in wall-clock time. That is open ([CLAUDE.md](../CLAUDE.md#not-here-yet)).

## The alt-fire is not a fork

dot-weapon's arsenal routes exactly one button into a behaviour, which is right: an alt-fire is a second state machine with its own cadence and refusals, and folding it in would make every game pay for it. So the bash lives in `ZeeWeaponBash` and its state machine in `ZeeWeaponRig`, which owns the cooldown, puts it in the snapshot and rolls it back with everything else. The addon is not forked; that is the extension point working.

## What the rig counts, and why

The arsenal knows how far through a reload it is and keeps it private, correctly: exposing a fraction would make an animation's needs part of a simulation's public interface. The rig listens to the signals the arsenal does emit and counts the ticks itself.

- **`switched` fires between the holster and the deploy**, not at the start of the holster. The holster half is noticed by watching `is_switching()` go true, before the arsenal runs; a rig that waited for `switched` draws the weapon at rest the whole way down.
- **The previous command's buttons are simulation state and belong in the snapshot.** The bash, the reload and every semi-automatic weapon are edge-triggered against it. The arsenal is handed the previous command; the rig keeps one, so the rig saves it. Left out, a restored rig thinks the alt-fire was already down and refuses the next press, once.

## The rig needs its player on every role

`player_ref` is resolved on a SERVER rig too, outside `_resolve_presentation()`'s `role == SERVER` early return. The view model and world model are drawing and belong there; the player does not, because it is where `DotWeaponPlayerBridge.context_for` takes the muzzle position and aim direction. A server rig with no player builds every context with `(0, 0, 0)` and `(0, 0, -1)`: every shot leaves the world origin pointing north, the weapon fires, the ammunition drops, the counter replicates, and nobody can be shot. A rig with no carrier (the range, a test) needs a context handed to it from the eye; the eye and not the camera, because the camera carries the punch.

## Replication is a counter, not an event

An RPC per shot needs a reliable channel for something worthless late, costs a packet per shot per watcher, and desynchronises from the snapshot it belongs with (a muzzle flash from a weapon the same snapshot says is holstered). A four-bit counter inside the snapshot cannot do any of those; a watcher who missed a snapshot sees it jump by two and plays one flash, which is the correct amount of wrong.

**`uses_between()` is wrap-aware**, which is why it is a function: plain subtraction goes negative every sixteen shots, and reading a negative as "nothing happened" silences a weapon for one snapshot in sixteen.

## The art inside a delivered game

`ZeeWeaponArtTable` and `ZeeViewArms` name `res://assets/…`, and a game delivered as a dot-cloud pack has its vendored copy under `res://dot_cloud/<id>/<version>/assets/…`, while the client shell carries this addon and no art. `ZeeModelCache.set_asset_root(root)` rewrites `res://assets/` paths under `root` at the one place every model is loaded; the table is untouched, because it must read the same in a game that builds the art in. **A game sets it when it loads and puts `res://` back when it goes**, because a static outlives one game in a shell that loads the next. A shell exported before this method existed cannot load a game that calls it.

## A second pack adds to this one

`ZeeWeaponPack.add_source`, `ZeeWeaponArtTable.add_source` and `ZeeWeaponSound.set_class` let a second pack (zed-dot-weapons) register a callable once in its own install, and `weapons()` / `all()` append what it returns, so one rig carries both packs without a fork or every game handing a second catalogue everywhere.

- **This pack's ids win**: a source bringing `pistol` loses it with a WARN, because changing what "pistol" means on a running server is a change nobody asked for.
- **`ZeeWeaponArtTable.validate()`**, which refuses art for an id the pack does not define, still passes with another pack's art in the table.
- **Sources are statics**, so a game installs a pack when it loads and removes it when it goes, as with `set_asset_root`.
- **A source must be a static method's Callable, never a lambda.** The registry is a static variable the engine clears after freeing the scripts at exit, and a lambda kept there outlives its script: the process aborts (`double free or corruption`, exit 134) after every check has passed. This suite's own test sources are lambdas and are removed before it quits, which is why it cannot see this; zed-dot-weapons checks it in a second process.
