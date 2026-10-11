# Testing

`./game.sh test` runs the family's two-step check ([family CLAUDE.md](../../../CLAUDE.md#validating-anything)): every script parses, then `examples/zee_selftest.tscn`. Read its stderr even when it exits 0: the suite counts sections and checks, because a script error aborts the section it is in after the section has announced itself.

## What the suite reaches

All twenty-seven weapons load, measure, simulate, replicate and roll back; the pose's springs settle and produce no `NaN`; the climb drawn at 144 fps and at 30 fps is the one asked for; a server rig under a positioned, rotated carrier fires from the carrier where it faces (`_rig_carrier`); the art resolves through `set_asset_root`; another pack's source adds an id and loses a clashing one.

**A test rig with no player is the easiest one to write, and it hid a server firing from the world origin.** `_make_rig()` never set a carrier; `_rig_carrier()` is the check that does. When a new behaviour depends on the carrier, test it on a rig that has one.

## Look at it, because the suite cannot

Everything about this pack that can be wrong is invisible to every assertion in it: a weapon held at the wrong angle, an arm drawn over the gun it holds, a knife pointing away from the eye, a view model casting a shadow on the ground. Every one was a real bug here and every one was found by rendering a frame.

```bash
tools/screenshot.sh --rack          # all twenty-seven, with a pip on each muzzle
tools/screenshot.sh sniper          # one weapon, first person
tools/screenshot.sh --all           # one frame per weapon
EXTRA="--aim" tools/screenshot.sh sniper     # aimed, through the scope
EXTRA="--no-arms 1" tools/screenshot.sh rifle  # the weapon alone
tools/screenshot.sh --sheet rifle pistol knife  # contact sheets: screenshots/sheet_<id>.png
tools/screenshot.sh --sheet --all               # one sheet per weapon
```

**The contact sheet is the view model's review.** Eighteen frames of one weapon on one image: hip, aimed, fire frames 1/2/4/8/14 after a shot, reload at 0/25/50/75/90%, walking, turning right, the draw at 30% and 70%, standing under a roof in its shadow, and aimed four frames after a shot. The range (`--sheet <prefix>`) stops simulating, switches the view model's `_process` off and calls `ZeeViewModel.advance()` with a fixed 1/60 s step, so each frame is a number of steps and not wherever a software renderer's clock landed: the same frame is the same picture every run, and a before and an after compare side by side (`SHEET_DIR=/somewhere`). One screenshot of a weapon at rest says nothing about a reload, a kick or a draw, which is where every complaint about the hands came from.

**The rack is the sharpest of them**: each weapon gets a red pip at its measured muzzle and three green pips lie along Godot's forward as a reference. Every red pip must sit on the same side of its weapon as the green ones sit of the rack; that one comparison proved the orientation and is what would catch it breaking. `docs/rack.png` is the README's picture of it.

`tools/screenshot.sh` is not `--headless`: Godot's headless display driver renders nothing and a capture under it is a black PNG, which looks like a screenshot. It runs the real renderer against Xvfb. It cannot judge input feel or frame pacing.

## GDScript hazards this repository walked into

Both are in the family's [gdscript-hazards.md](../../../docs/gdscript-hazards.md).

- **A lambda captures locals by value.** A counter incremented in a signal handler stays zero outside it; the bash section reported a failure for a signal that fired, and the rollback section beside it passed because its initial value happened to be the answer. Accumulate into an `Array`.
- **A lambda kept in a static outlives its script** and aborts the process at exit ([design](design.md#a-second-pack-adds-to-this-one)).
