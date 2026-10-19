# Copies the Quaternius meshes the guns are kitbashed from into one small .blend in this repo,
# so a rebuild needs nothing outside it (the Kenney parts are already vendored in assets/).
#
#   blender -b --python art-src/guns/extract_donors.py -- "<Ultimate Gun Pack - July 2019>/Blends"
#
# Source: Quaternius, "Ultimate Low Poly Guns Pack", https://opengameart.org/content/low-poly-guns-pack
# (CC0 1.0 on that page; the archive itself carries no licence file).
import bpy, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "src", "quaternius_donors.blend")

# Every donor a recipe in guns.py names. Raw: the source's axes (muzzle +X, up +Z) and units.
DONORS = [
    "Revolver_2", "Revolver_3", "Pistol_3", "Pistol_6", "SubmachineGun_1", "SubmachineGun_3",
    "SubmachineGun_5", "AssaultRifle_1", "AssaultRifle_2", "AssaultRifle_3", "AssaultRifle_5",
    "AssaultRifle2_1", "AssaultRifle2_2", "AssaultRifle2_3", "Bullpup_1", "Bullpup_2",
    "Shotgun_2", "Shotgun_3", "Shotgun_ShortStock", "SniperRifle_1", "SniperRifle_2",
    "SniperRifle_5", "SniperRifle_6", "Accessories/Stock", "Accessories/Grip",
    "Accessories/Bipod", "Accessories/Scope_1", "Accessories/Scope_2", "Accessories/Scope_3",
    "Accessories/Flashlight", "Accessories/Silencer_2",
]

src = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
for rel in DONORS:
    path = os.path.join(src, rel + ".blend")
    with bpy.data.libraries.load(path, link=False) as (data_from, data_to):
        data_to.objects = [n for n in data_from.objects]
    name = os.path.basename(rel)
    meshes = [o for o in data_to.objects if o is not None and o.type == "MESH"]
    ob = meshes[0]
    bpy.context.scene.collection.objects.link(ob)
    # Bake the object transform into the mesh so every donor is in the same raw space.
    ob.data = ob.data.copy()
    ob.data.transform(ob.matrix_world)
    ob.matrix_world.identity()
    ob.name = name
    ob.data.name = name
    for o in data_to.objects:
        if o is not None and o is not ob and o.users == 0:
            bpy.data.objects.remove(o)
bpy.ops.outliner.orphans_purge(do_recursive=True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
print("wrote", OUT, len(bpy.data.objects), "donors")
