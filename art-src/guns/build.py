# Builds the real-world guns from guns.py and writes them where ZeeWeaponArtTable reads them.
#
#   blender -b --python art-src/guns/build.py -- [--out <dir>] [gun ...]
#
# Default out is assets/low-poly-guns/. Prints each gun's size and its magazine's offset
# (ZeeWeaponArt.magazine_offset, Godot axes) and writes them to art-src/guns/out/measure.json.
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zee_kit  # noqa: E402
import guns  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = os.path.join(zee_kit.REPO, "assets", "low-poly-guns")
if "--out" in args:
    i = args.index("--out")
    out = os.path.abspath(args[i + 1])
    del args[i:i + 2]
names = args or list(guns.RECIPES)
os.makedirs(out, exist_ok=True)
report = {}
for name in names:
    zee_kit.reset()
    gun, mag, length = guns.RECIPES[name]()
    mag_path = os.path.join(out, name + "_magazine.glb") if mag is not None else None
    offset, size = zee_kit.export(gun, os.path.join(out, name + ".glb"), mag, mag_path, length)
    tris = sum(len(p.vertices) - 2 for p in gun.data.polygons)
    report[name] = {"size": size, "magazine_offset": offset, "tris": tris}
    print("GUN %-15s size %s mag %s tris %d" % (name, size, offset, tris))
meas = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(meas, exist_ok=True)
path = os.path.join(meas, "measure.json")
old = json.load(open(path)) if os.path.exists(path) else {}
old.update(report)
json.dump(old, open(path, "w"), indent=1, sort_keys=True)
