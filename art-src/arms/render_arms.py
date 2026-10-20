"""Contact sheet of assets/arms/arms-rigged.glb in Cycles (GPU where there is one).

    blender -b --python render_arms.py -- <arms-rigged.glb> <out-prefix>

Three views of the rest pose (side, top, three-quarter), the Glove surface in the pack's glove
colour and the Sleeve in its sleeve colour, so the cuff, the fingers and the weights show.
"""
import sys
import math
import bpy
from mathutils import Vector

glb, prefix = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 64
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type == "CUDA"
    sc.cycles.device = "GPU"
except Exception as e:  # CPU is fine, only slower
    print("render: no GPU:", e)
sc.render.resolution_x = sc.render.resolution_y = 512
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.37, 0.4, 1)
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 0.7
sc.collection.objects.link(cam)
sc.camera = cam
centre = Vector((0.2, -0.05, -0.2))
for name, off in {"side": (1, 0, 0), "top": (0, 0, 1), "three": (0.7, -0.7, 0.5)}.items():
    d = Vector(off).normalized()
    cam.location = centre + d * 2.0
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s-%s.png" % (prefix, name)
    bpy.ops.render.render(write_still=True)
