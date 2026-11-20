# The pack's own grenades, replacing the Blaster Kit's grenade-a (a capsule that read as a lantern)
# and grenade-b (a grey ball). Both stand on their base with the origin at the bottom centre and
# their top along +Z (glTF +Y), as ZeeWeaponArtTable._thrown expects (model_forward UP).
#
#   blender -b --python art-src/guns/grenades.py -- [--out <dir>]
#
# frag: an olive fragmentation body cut into a pineapple's facets and segment bands, a steel
#       fuse with its spoon running down the side and a pull ring on the pin.
# sticky: a squat charge on a teal adhesive pad, orange hazard straps, a timer face with a red lamp.
# Heights are the Kenney models' (0.21-0.24); the sticky is narrower (0.14), as the suite holds a thrown
# weapon to 20-35% of the screen and the kit's 0.18 drum, tipped toward the eye, took 40%.
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zee_kit  # noqa: E402
from zee_kit import box, cyl, join, paint, rotate, _tidy  # noqa: E402


def _sphere(radius, z, sx=1.0, sz=1.0, segs=12, rings=8, material="olive", name="sphere"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    bmesh.ops.scale(bm, vec=(sx, sx, sz), verts=bm.verts)
    bmesh.ops.translate(bm, vec=(0, 0, z), verts=bm.verts)
    ob = zee_kit._new_object(name, bm)
    paint(ob, material)
    return ob


def _torus(major, minor, centre, axis="Y", material="steel", name="ring"):
    bm = bmesh.new()
    n, m = 14, 6
    verts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        row = []
        for j in range(m):
            b = 2 * math.pi * j / m
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        verts.append(row)
    for i in range(n):
        for j in range(m):
            bm.faces.new((verts[i][j], verts[(i + 1) % n][j], verts[(i + 1) % n][(j + 1) % m], verts[i][(j + 1) % m]))
    if axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    ob = zee_kit._new_object(name, bm)
    paint(ob, material)
    return ob


def frag():
    body_r, body_z = 0.07, 0.09
    parts = [_sphere(body_r, body_z, sz=1.22, segs=10, rings=7, material="olive", name="body")]
    # Two raised bands round the body and a base plug: the segmenting a pineapple body has.
    for z, r in ((body_z - 0.035, 0.066), (body_z + 0.035, 0.066)):
        parts.append(cyl(r, 0.012, "ccc", (0, 0, z), axis="Z", material="ranger", sides=10, chamfer=0.3))
    parts.append(cyl(0.022, 0.012, "ccd", (0, 0, 0.0), axis="Z", material="ranger", sides=10))
    top = body_z + body_r * 1.22
    # Fuse: a steel collar and head.
    parts.append(cyl(0.028, 0.026, "ccd", (0, 0, top - 0.008), axis="Z", material="steel", sides=12))
    parts.append(cyl(0.022, 0.022, "ccd", (0, 0, top + 0.016), axis="Z", material="gunmetal", sides=10))
    # Spoon: off the head along +Y (the side the thumb holds), then down the body.
    parts.append(box((0.026, 0.05, 0.008), "cfd", (0, 0.0, top + 0.03), "steel", 0.15))
    spoon = box((0.024, 0.008, 0.11), "cbu", (0, 0.05, top + 0.038), "steel", 0.15)
    rotate(spoon, -14, "X", about=(0, 0.05, top + 0.038))
    parts.append(spoon)
    # Pin through the head and its pull ring on the -X side.
    parts.append(cyl(0.003, 0.05, "ccc", (0, 0, top + 0.026), axis="X", material="steel", sides=6))
    parts.append(_torus(0.017, 0.0035, (-0.04, 0, top + 0.026), axis="Y", material="brass"))
    return join(parts, "frag")


def sticky():
    parts = [
        # The adhesive pad it is stuck down with.
        cyl(0.07, 0.018, "ccd", (0, 0, 0.0), axis="Z", material="teal", sides=16, chamfer=0.3),
        # Charge body.
        cyl(0.062, 0.11, "ccd", (0, 0, 0.016), axis="Z", material="graphite", sides=16, chamfer=0.15),
        cyl(0.056, 0.014, "ccd", (0, 0, 0.124), axis="Z", material="gunmetal", sides=16, chamfer=0.3),
        # Hazard straps.
        cyl(0.0645, 0.014, "ccc", (0, 0, 0.046), axis="Z", material="signal", sides=16, chamfer=0.2),
        cyl(0.0645, 0.014, "ccc", (0, 0, 0.096), axis="Z", material="signal", sides=16, chamfer=0.2),
        # Detonator: a timer box with its lamp, and a short arming handle.
        box((0.05, 0.044, 0.03), "ccd", (0, -0.008, 0.136), "polymer", 0.15),
        box((0.036, 0.004, 0.016), "ccc", (0, -0.031, 0.152), "lens", 0.1),
        cyl(0.011, 0.012, "ccd", (0.013, 0.01, 0.166), axis="Z", material="red", sides=10, chamfer=0.3),
        box((0.012, 0.012, 0.03), "ccd", (-0.014, 0.01, 0.166), "steel", 0.15),
        box((0.044, 0.012, 0.01), "ccd", (-0.014, 0.01, 0.194), "steel", 0.15),
    ]
    return join(parts, "sticky")


def export(ob, path):
    _tidy(ob)
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT")
    lo, hi = zee_kit.bounds(ob)
    size = hi - lo
    print("GRENADE %-8s size %.3f x %.3f x %.3f (w, d, h) tris %d" % (
        ob.name, size.x, size.y, size.z, sum(len(p.vertices) - 2 for p in ob.data.polygons)))


args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = os.path.join(zee_kit.REPO, "assets", "low-poly-guns")
if "--out" in args:
    out = os.path.abspath(args[args.index("--out") + 1])
os.makedirs(out, exist_ok=True)
for name, fn in (("frag", frag), ("sticky", sticky)):
    zee_kit.reset()
    export(fn(), os.path.join(out, name + ".glb"))
