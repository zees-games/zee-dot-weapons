extends RefCounted

## Which glove a gun wants: the base colour, or the light one when the gun's surfaces would swallow it.

## Picks the glove for a gun whose surfaces are [param surfaces]: [param base] unless the mean or a third of the surfaces merge with it, then [param light].
static func glove_for(surfaces: Array[Color], base: Color, light: Color, gap: float) -> Color:
	if surfaces.is_empty():
		return base
	var mean := mean_of(surfaces)
	var merging := 0
	for c in surfaces:
		if absf(base.get_luminance() - c.get_luminance()) < gap:
			merging += 1
	var merges := absf(base.get_luminance() - mean.get_luminance()) < gap or merging * 3 >= surfaces.size()
	if not merges:
		return base
	return light if mean.get_luminance() < light.get_luminance() else base.darkened(0.6)


static func mean_of(colors: Array[Color]) -> Color:
	var sum := Color(0, 0, 0, 1)
	for c in colors:
		sum += Color(c.r, c.g, c.b, 0.0)
	var n := maxf(1.0, float(colors.size()))
	return Color(sum.r / n, sum.g / n, sum.b / n)


## The albedo of each mesh surface under [param root]: material colour times a 4x4 downsample of its texture where readable.
static func surface_albedos(root: Node) -> Array[Color]:
	var out: Array[Color] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var c := mat.albedo_color
			var tex := mat.albedo_texture
			var img: Image = tex.get_image() if tex != null else null
			if img != null and not img.is_empty() and img.is_compressed() and img.decompress() != OK:
				img = null
			if img != null and not img.is_empty():
				img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
				var t := Color(0, 0, 0, 0)
				for y in 4:
					for x in 4:
						t += img.get_pixel(x, y)
				c *= t / 16.0
			out.append(Color(c.r, c.g, c.b, 1.0))
	return out
