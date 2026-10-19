# Renders each gun .glb from four sides (right, left-front three-quarter, top, rear
# three-quarter) in Cycles, with a red marker just past the muzzle end (glTF -Z, +Y here) so
# the axis is settled by looking, not by trusting the bounds.
#
#   blender -b --python art-src/guns/render_views.py -- <out dir> <size px> <samples> a.glb b.glb ...
#
# With ZEE_MEASURE set to build.py's measure.json, each gun's <name>_magazine.glb beside it is
# placed at the measured offset, so the magazine's seat is checked by eye too.
#
# On staging02 (the RTX 2070) it renders on CUDA; anywhere without a CUDA device, on the CPU.
import bpy
import json
import math
import os
import sys
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir, px, samples, files = args[0], int(args[1]), int(args[2]), args[3:]
os.makedirs(out_dir, exist_ok=True)

VIEWS = {
    "right": (90, 0, 90),      # camera on +X looking -X: the side the hip pose shows
    "front34": (72, 0, 140),   # from the front-left, above
    "top": (0, 0, 90),
    "rear34": (65, 0, 35),     # from behind-right, above: what the shooter sees
}


def use_gpu(scene):
    prefs = bpy.context.preferences.addons["cycles"].preferences
    found = []
    try:
        prefs.compute_device_type = "CUDA"
        prefs.get_devices()
        found = [d for d in prefs.devices if d.type == "CUDA"]
    except TypeError:
        pass
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    scene.cycles.device = "GPU" if found else "CPU"
    return bool(found)


measure = json.load(open(os.environ["ZEE_MEASURE"])) if os.environ.get("ZEE_MEASURE") else {}

for f in files:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=f)
    stem = os.path.splitext(os.path.basename(f))[0]
    off = measure.get(stem, {}).get("magazine_offset")
    mag_file = f[:-4] + "_magazine.glb"
    if off and os.path.exists(mag_file):
        before = set(sc.objects)
        bpy.ops.import_scene.gltf(filepath=mag_file)
        for o in set(sc.objects) - before:
            if o.parent is None:
                # Godot (x, y, z) is Blender (x, -z, y).
                o.location = (off[0], -off[2], off[1])
        bpy.context.view_layer.update()
    meshes = [o for o in sc.objects if o.type == "MESH"]
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    for o in meshes:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    c = (lo + hi) / 2
    size = hi - lo
    span = max(size)
    mk = bpy.data.materials.new("marker")
    mk.use_nodes = True
    b = next(n for n in mk.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (1, 0, 0, 1)
    b.inputs["Emission Color"].default_value = (1, 0, 0, 1)
    b.inputs["Emission Strength"].default_value = 2.0
    bpy.ops.mesh.primitive_uv_sphere_add(radius=span * 0.015, location=(c.x, hi.y + span * 0.03, c.z))
    bpy.context.object.data.materials.append(mk)
    # Floor and light.
    bpy.ops.mesh.primitive_plane_add(size=span * 8, location=(c.x, c.y, lo.z - span * 0.02))
    fl = bpy.data.materials.new("floor")
    fl.use_nodes = True
    next(n for n in fl.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.42, 0.44, 0.47, 1)
    bpy.context.object.data.materials.append(fl)
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.58, 0.62, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(60))
    sc.collection.objects.link(sun)
    sc.render.engine = "CYCLES"
    use_gpu(sc)
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.resolution_x = px
    sc.render.resolution_y = px // 2
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    for view, (rx, ry, rz) in VIEWS.items():
        cam.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
        # From the euler, not matrix_world: that is stale until the depsgraph next updates.
        d = cam.rotation_euler.to_matrix() @ Vector((0, 0, 1))
        cam.location = c + d * span * 3
        # Wide enough for the length and tall enough for the height in a 2:1 frame.
        cam.data.ortho_scale = max(size.x, size.y, 2 * size.z) * 1.12
        sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (stem, view))
        bpy.ops.render.render(write_still=True)
    print("rendered", stem, "size xyz %.3f %.3f %.3f" % tuple(size))
