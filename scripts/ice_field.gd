class_name IceField
extends Node3D
## The glacier as one smooth block of ice you can carve.
##
## The ice is a 3D grid of density values every `res` metres: 1 = solid ice,
## 0 = air, and the surface sits where the density crosses 0.5. Heat lowers
## the density near where it lands, so the surface creeps back smoothly.
## The grid is cut into chunks; each chunk becomes a mesh ("surface nets":
## one vertex per cell the surface passes through, one quad per grid edge it
## crosses) plus a matching collision shape for walking on and aiming at.
##
## Grid points are (i, j, k) with i in [0, nx), j in [0, ny), k in [0, nz).
## The storage has one extra column of air on every side in x and z, so the
## mesher never needs bounds checks. Under y = 0 the bottom row repeats, so
## the ice simply carries on into the ground with no bottom face.

signal ice_melted(at: Vector3, volume: float, value: float)   # m³ that just turned to water, and their hp x m³ x worth
signal find_exposed(find: int)

const CH := 8                    # chunk size in cells, along x and z
const MELT_K := 0.3              # tool hp -> density. A point of fresh snow takes 0.25 / MELT_K hp
const REMESH_BUDGET_USEC := 7000 # per frame
const CHUNK_MIN_INTERVAL := 0.07 # re-mesh the same chunk at most this often (seconds)
# Ice that has lost its connection to the ground, and small loose chunks
# sitting on the ground, melt away slowly by themselves, from the outside in,
# so carving doesn't leave floating patches and fiddly scraps around.
const FLOAT_SCAN_DELAY := 1.2    # seconds after something melts before looking for loose bits
const FLOAT_BUDGET_USEC := 1200  # per frame, for that search
const FLOAT_MELT_RATE := 0.08    # density lost per second per side open to the air: corners go
                                 # first (about 2 s), flat faces last (about 6 s), like real melting
const FLOAT_CORE_RATE := 0.06    # inside a bit, so big ones soften all the way through
const FLOAT_TICK := 0.2
const SMALL_CHUNK_VOLUME := 4.0  # loose chunks on the ground smaller than this (m³) melt too

var spec: Dictionary             # this glacier's description (Levels: a level's "glaciers")
var seed_value := 0
var res := 0.5                   # metres between grid points (big glaciers use a coarser grid)
var point_volume := 0.125        # m³ of ice per grid point
var layer_depth := 1.0           # metres of ice per layer, counted from the original surface
var layers: Array = []           # Balance.LAYER_SETS[spec.layers]: name, hp, colour, deepest last
var worth := 1.0                 # meltwater per hp x m³ (the frozen lake's ice sells for more)
var collide := true              # build collision shapes (off while the glacier is out of reach)
var origin := Vector3.ZERO       # world position of grid point (0, 0, 0)
var nx := 0
var ny := 0
var nz := 0
var px := 0                      # padded sizes: one air point on each side in x and z
var pz := 0
var plane := 0                   # px * pz

var f := PackedFloat32Array()    # density per point, see _s()
var lay := PackedByteArray()     # ice layer per point (0 = surface snow)
var top0 := PackedFloat32Array() # original surface height per column (index i+1 + px*(k+1))
var col_top := PackedFloat32Array()  # current top of the ice per column, -1 = bare ground
var remaining := 0               # points that are still ice (density > 0.5)
var total := 0
var find_points := {}            # storage index -> find number

var body: StaticBody3D           # collision layer 2: the tool's ray and the player hit this
var material: ShaderMaterial
var ncx := 0
var ncz := 0

var _small_points := 32
var _layer_hp := PackedFloat32Array()
var _layer_col: Array = []
var _chunks: Array = []          # {mesh: MeshInstance3D, shape: CollisionShape3D, t: float}
var _dirty := {}                 # chunk index -> true
var _clock := 0.0
var _heat := 0.0
var _glow_t := 0.0

# Looking for floating ice. Each column's solid stretches ("runs") are read a
# few columns per frame, then runs that touch (same height range in a
# neighbouring column) are grouped. Groups that don't reach the ground melt.
var _scan_dirty := true          # something melted since the last search started
var _scan_wait := 0.0
var _scan_phase := 0             # 0 = idle, 1 = reading columns, 2 = grouping runs
var _scan_c := 0                 # next column to read (k * nx + i)
var _runs := PackedInt32Array()  # 3 ints per run: padded column index, lowest j, highest j
var _col_first := PackedInt32Array()   # per padded column: its first run
var _col_count := PackedInt32Array()   # and how many runs it has
var _group := PackedInt32Array() # per run: its group, -1 = not reached yet
var _group_melts := PackedByteArray()  # per group: 1 = floating (or a small chunk), melt it
var _queue := PackedInt32Array()
var _q_head := 0
var _next_seed := 0
var _cur_size := 0
var _cur_grounded := false
var _floating := PackedInt32Array()    # points melting away by themselves
var _float_t := 0.0
var _drips: CPUParticles3D             # meltwater dripping off them


# =====================================================================================
# Building
# =====================================================================================
func generate(p_spec: Dictionary, p_seed: int, carve: Array = [], mesh_now: bool = true) -> void:
	## Fills the grid from a glacier's shape (see Levels), cuts its crevasses,
	## and hollows out `carve` boxes (the buried houses). Then builds every
	## chunk (or, with mesh_now off, leaves them for the next frames).
	spec = p_spec
	seed_value = p_seed
	res = float(spec.get("res", 0.5))
	point_volume = res * res * res
	_small_points = int(round(SMALL_CHUNK_VOLUME / point_volume))
	layer_depth = float(spec.get("layer_depth", 1.0))
	layers = Balance.LAYER_SETS[spec.get("layers", "valley")]
	worth = float(spec.get("worth", 1.0))
	var mn: Vector3 = spec.field_min
	var mx: Vector3 = spec.field_max
	origin = mn
	nx = int(round((mx.x - mn.x) / res)) + 1
	ny = int(round((mx.y - mn.y) / res)) + 1
	nz = int(round((mx.z - mn.z) / res)) + 1
	px = nx + 2
	pz = nz + 2
	plane = px * pz
	f.resize(plane * ny)
	f.fill(0.0)
	lay.resize(plane * ny)
	lay.fill(0)
	top0.resize(plane)
	top0.fill(0.0)
	col_top.resize(plane)
	col_top.fill(-1.0)
	_layer_hp.resize(layers.size())
	_layer_col.clear()
	for l in layers.size():
		_layer_hp[l] = float(layers[l].hp)
		_layer_col.append(layers[l].color)

	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.075
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 1
	detail.frequency = 0.3
	var nl := layers.size() - 1
	for k in range(1, nz - 1):
		for i in range(1, nx - 1):
			var x := origin.x + i * res
			var z := origin.z + k * res
			var h := minf(_height(x, z, noise, detail), mx.y - 1.0)
			var c := (i + 1) + px * (k + 1)
			top0[c] = h
			if h <= 0.02:
				continue
			var jtop := mini(ny - 2, int(ceil(h / res)) + 1)
			for j in jtop + 1:
				var y := origin.y + j * res
				var v := clampf(0.5 + (h - y) / (2.0 * res), 0.0, 1.0)
				if v <= 0.0:
					continue
				var s := c + plane * j
				f[s] = v
				lay[s] = clampi(int((h - y) / layer_depth), 0, nl)
	for cv in spec.get("crevasses", []):
		_cut_crevasse(cv)
	for box in carve:
		_carve_box((box as AABB).grow(0.25))
	_count()
	total = remaining
	_update_col_top(0, nx - 1, 0, nz - 1)
	_build_nodes()
	for ci in _chunks.size():
		if mesh_now:
			_remesh(ci)
		else:
			_dirty[ci] = true


func clear_all() -> void:
	## This glacier is already gone (loading a save): no ice left, and no
	## meltwater for it either.
	f.fill(0.0)
	remaining = 0
	col_top.fill(-1.0)
	find_points.clear()
	_floating.clear()
	_scan_phase = 0
	_scan_dirty = false
	for ci in _chunks.size():
		_dirty[ci] = true


func _height(x: float, z: float, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	if spec.get("kind", "tongue") == "dome":
		return _dome_height(x, z, noise, detail)
	## A tongue of ice down the valley: full thickness at the back, sloping
	## down to a toe at snout_z, with rounded sides.
	var g: Dictionary = spec
	var full_z: float = g.full_z
	var snout_z: float = g.snout_z
	var t := clampf((z - full_z) / (snout_z - full_z), 0.0, 1.0)   # 0 = full, 1 = the toe
	var wobble := noise.get_noise_2d(z * 0.7, 40.0) * 1.2          # edges aren't ruler-straight
	var hw := lerpf(float(g.half_width_back), float(g.half_width_snout), t) + wobble
	var ax := absf(x) / hw
	if ax >= 1.0:
		return 0.0
	var across := pow(1.0 - ax * ax, 0.42)
	var along := 1.0 - smoothstep(0.0, 1.0, t)
	along *= smoothstep(float(g.back_z) - 1.0, float(g.back_z) + 0.6, z)
	if along <= 0.0:
		return 0.0
	var shape := across * along
	var h := float(g.height) * shape
	h += noise.get_noise_2d(x, z) * float(g.bumps) * minf(1.0, shape * 2.0)
	h += detail.get_noise_2d(x, z) * 0.18 * minf(1.0, shape * 3.0)
	return maxf(h, 0.0)


func _dome_height(x: float, z: float, noise: FastNoiseLite, detail: FastNoiseLite) -> float:
	## A round ice cap (the frozen lake): rolling on top, highest in the
	## middle, with a steep, wobbly edge all the way round.
	var c: Vector2 = spec.center
	var rad: Vector2 = spec.radius
	var a := atan2((z - c.y) / rad.y, (x - c.x) / rad.x)
	var wob := 1.0 + noise.get_noise_2d(cos(a) * 25.0, sin(a) * 25.0 + 300.0) * float(spec.get("wobble", 0.08))
	var ex := (x - c.x) / (rad.x * wob)
	var ez := (z - c.y) / (rad.y * wob)
	var r2 := ex * ex + ez * ez
	if r2 >= 1.0:
		return 0.0
	var shape := pow(1.0 - r2, float(spec.get("edge", 0.5)))
	var h := float(spec.height) * shape
	h += noise.get_noise_2d(x * 0.35, z * 0.35 + 500.0) * float(spec.get("hills", 0.0)) * minf(1.0, shape * 1.5)
	h += noise.get_noise_2d(x, z) * float(spec.bumps) * minf(1.0, shape * 2.0)
	h += detail.get_noise_2d(x, z) * 0.18 * minf(1.0, shape * 3.0)
	return maxf(h, 0.0)


func _cut_crevasse(cv: Dictionary) -> void:
	var x0: float = cv.x0
	var x1: float = cv.x1
	var mid := (x0 + x1) * 0.5
	var half := (x1 - x0) * 0.5
	var w: float = cv.width
	var depth: float = cv.depth
	for i in range(1, nx - 1):
		var x := origin.x + i * res
		if x < x0 or x > x1:
			continue
		var u := (x - mid) / half
		var taper := 1.0 - u * u                      # shallower and narrower at the ends
		var zc: float = cv.z + float(cv.bow) * taper
		for k in range(1, nz - 1):
			var z := origin.z + k * res
			var dz := absf(z - zc)
			if dz > w + res * 2.0:
				continue
			var c := (i + 1) + px * (k + 1)
			var h := top0[c]
			if h < 1.0:
				continue
			var bottom := h - depth * taper
			for j in ny:
				var y := origin.y + j * res
				if y > h + res:
					break
				var open := w * taper * clampf((y - bottom) / maxf(h - bottom, 0.01), 0.0, 1.0)
				var v := clampf(0.5 + (dz - open) / (2.0 * res), 0.0, 1.0)
				var s := c + plane * j
				f[s] = minf(f[s], v)


func _carve_box(box: AABB) -> void:
	var lo := box.position
	var hi := box.end
	var i0 := clampi(int(floor((lo.x - origin.x) / res)) - 1, 0, nx - 1)
	var i1 := clampi(int(ceil((hi.x - origin.x) / res)) + 1, 0, nx - 1)
	var j1 := clampi(int(ceil((hi.y - origin.y) / res)) + 1, 0, ny - 1)
	var k0 := clampi(int(floor((lo.z - origin.z) / res)) - 1, 0, nz - 1)
	var k1 := clampi(int(ceil((hi.z - origin.z) / res)) + 1, 0, nz - 1)
	var c := box.get_center()
	var half := box.size * 0.5
	for j in range(0, j1 + 1):
		for k in range(k0, k1 + 1):
			for i in range(i0, i1 + 1):
				var p := origin + Vector3(i, j, k) * res
				var q := (p - c).abs() - half
				var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
				var sd := outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
				var v := clampf(0.5 + sd / (2.0 * res), 0.0, 1.0)
				var s := _s(i, j, k)
				f[s] = minf(f[s], v)


func _count() -> void:
	remaining = 0
	for j in ny:
		for k in nz:
			var base := plane * j + px * (k + 1) + 1
			for i in nx:
				if f[base + i] > 0.5:
					remaining += 1


func _build_nodes() -> void:
	for c in get_children():
		c.queue_free()
	_drips = null
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/ice.gdshader")
	material.set_shader_parameter("detail_tex", detail_texture(seed_value))
	body = StaticBody3D.new()
	body.name = "IceBody"
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	ncx = int(ceil(float(nx) / CH))
	ncz = int(ceil(float(nz) / CH))
	_chunks = []
	for ci in ncx * ncz:
		var mi := MeshInstance3D.new()
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		var cs := CollisionShape3D.new()
		cs.disabled = true
		body.add_child(cs)
		_chunks.append({"mesh": mi, "shape": cs, "t": -1.0})


static var _detail_cache := {}


static func detail_texture(seed_base: int) -> ImageTexture:
	## Grey noise for the shaders: R = fine grain, G = big soft blotches,
	## B = streaks stretched along the glacier's flow. Tiles seamlessly.
	## Shared by the ice and the mountains.
	if _detail_cache.has(seed_base):
		return _detail_cache[seed_base]
	var n := 256
	var a := FastNoiseLite.new()
	a.seed = seed_base + 31
	a.frequency = 0.045
	a.fractal_octaves = 4
	var b := FastNoiseLite.new()
	b.seed = seed_base + 32
	b.frequency = 0.012
	var c := FastNoiseLite.new()
	c.seed = seed_base + 33
	c.frequency = 0.02
	var da := a.get_seamless_image(n, n).get_data()   # L8: one byte per pixel
	var db := b.get_seamless_image(n, n).get_data()
	var dc := c.get_seamless_image(n, n).get_data()
	var rgb := PackedByteArray()
	rgb.resize(n * n * 3)
	var o := 0
	for y in n:
		var row := y * n
		var srow := ((y * 4) % n) * n   # streaks: the third noise squashed 4x along y
		for x in n:
			rgb[o] = da[row + x]
			rgb[o + 1] = db[row + x]
			rgb[o + 2] = dc[srow + x]
			o += 3
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGB8, rgb)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_detail_cache[seed_base] = tex
	return tex


# =====================================================================================
# Grid helpers
# =====================================================================================
func _s(i: int, j: int, k: int) -> int:
	return (i + 1) + px * (k + 1) + plane * j


func point_pos(s: int) -> Vector3:
	var j := s / plane
	var r := s - j * plane
	var k := r / px - 1
	var i := r % px - 1
	return origin + Vector3(i, j, k) * res


func point_at(p: Vector3) -> int:
	## Storage index of the grid point nearest to p, or -1 outside the grid.
	var q := (p - origin) / res
	var i := int(round(q.x))
	var j := int(round(q.y))
	var k := int(round(q.z))
	if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
		return -1
	return _s(i, j, k)


func density_at(p: Vector3) -> float:
	## Trilinear density at a world point (0 outside the grid).
	var q := (p - origin) / res
	if q.x < 0.0 or q.z < 0.0 or q.x >= nx - 1 or q.z >= nz - 1 or q.y >= ny - 1:
		return 0.0
	q.y = maxf(q.y, 0.0)
	var i := int(q.x)
	var j := int(q.y)
	var k := int(q.z)
	var tx := q.x - i
	var ty := q.y - j
	var tz := q.z - k
	var s := _s(i, j, k)
	var c00 := lerpf(f[s], f[s + 1], tx)
	var c10 := lerpf(f[s + px], f[s + px + 1], tx)
	var c01 := lerpf(f[s + plane], f[s + plane + 1], tx)
	var c11 := lerpf(f[s + plane + px], f[s + plane + px + 1], tx)
	return lerpf(lerpf(c00, c10, tz), lerpf(c01, c11, tz), ty)


func solid_at(p: Vector3) -> bool:
	return density_at(p) > 0.5


func layer_at(p: Vector3) -> int:
	var s := point_at(p)
	return int(lay[s]) if s >= 0 else 0


func fraction_left() -> float:
	return float(remaining) / float(maxi(total, 1))


func volume_left() -> float:
	return float(remaining) * point_volume


func layer_name(l: int) -> String:
	return str(layers[clampi(l, 0, layers.size() - 1)].name)


func layer_hp(l: int) -> float:
	return _layer_hp[clampi(l, 0, layers.size() - 1)]


# =====================================================================================
# Surface queries (helpers, finds, flowers)
# =====================================================================================
func _update_col_top(i0: int, i1: int, k0: int, k1: int) -> void:
	for k in range(maxi(k0, 0), mini(k1, nz - 1) + 1):
		for i in range(maxi(i0, 0), mini(i1, nx - 1) + 1):
			var c := (i + 1) + px * (k + 1)
			var top := -1.0
			for j in range(ny - 2, -1, -1):
				var v := f[c + plane * j]
				if v > 0.5:
					var above := f[c + plane * (j + 1)]
					top = origin.y + (float(j) + (v - 0.5) / maxf(v - above, 0.001)) * res
					break
			col_top[c] = top


func surface_y(x: float, z: float) -> float:
	## Height of the top of the ice (or the ground, 0) at a spot, smoothly.
	var qx := clampf((x - origin.x) / res, 0.0, float(nx - 1) - 0.001)
	var qz := clampf((z - origin.z) / res, 0.0, float(nz - 1) - 0.001)
	var i := int(qx)
	var k := int(qz)
	var tx := qx - i
	var tz := qz - k
	var c := (i + 1) + px * (k + 1)
	var a := maxf(col_top[c], 0.0)
	var b := maxf(col_top[c + 1], 0.0)
	var d := maxf(col_top[c + px], 0.0)
	var e := maxf(col_top[c + px + 1], 0.0)
	return lerpf(lerpf(a, b, tx), lerpf(d, e, tx), tz)


func has_ice_at(x: float, z: float) -> bool:
	## Is there any ice left in the column at this spot?
	var q := Vector3(x, 0.0, z) - origin
	var i := int(round(q.x / res))
	var k := int(round(q.z / res))
	if i < 0 or k < 0 or i >= nx or k >= nz:
		return false
	return col_top[(i + 1) + px * (k + 1)] > 0.0


func floor_below(p: Vector3) -> float:
	## Height of the first ice surface (or the ground) at or below p.
	var q := (p - origin) / res
	var i := int(round(q.x))
	var k := int(round(q.z))
	if i < 0 or k < 0 or i >= nx or k >= nz:
		return 0.0
	var c := (i + 1) + px * (k + 1)
	for j in range(mini(int(floor(q.y)), ny - 2), -1, -1):
		var v := f[c + plane * j]
		if v > 0.5:
			var above := f[c + plane * (j + 1)]
			return origin.y + (float(j) + (v - 0.5) / maxf(v - above, 0.001)) * res
	return 0.0


func random_surface_point(rng: RandomNumberGenerator) -> Vector3:
	## A random spot on top of the ice, or Vector3.INF if it's all gone.
	if remaining <= 0:
		return Vector3.INF
	for _t in 300:
		var i := rng.randi_range(1, nx - 2)
		var k := rng.randi_range(1, nz - 2)
		var top := col_top[(i + 1) + px * (k + 1)]
		if top > 0.25:
			return Vector3(origin.x + i * res, top, origin.z + k * res)
	for k in nz:   # not much left: scan for it
		for i in nx:
			var top := col_top[(i + 1) + px * (k + 1)]
			if top > 0.0:
				return Vector3(origin.x + i * res, top, origin.z + k * res)
	return Vector3.INF


func nearby_surface_point(from: Vector3, rng: RandomNumberGenerator, reach: float = 3.0) -> Vector3:
	for _t in 24:
		var x := from.x + rng.randf_range(-reach, reach)
		var z := from.z + rng.randf_range(-reach, reach)
		if has_ice_at(x, z) and surface_y(x, z) > 0.25:
			return Vector3(x, surface_y(x, z), z)
	return random_surface_point(rng)


func original_top(x: float, z: float) -> float:
	## How high the glacier's surface was here before any melting.
	var i := clampi(int(round((x - origin.x) / res)), 0, nx - 1)
	var k := clampi(int(round((z - origin.z) / res)), 0, nz - 1)
	return top0[(i + 1) + px * (k + 1)]


func watch_find(p: Vector3, d: int) -> bool:
	## A find is frozen at p: when the ice right around it melts, find_exposed(d)
	## fires. Returns false if that ice is already gone.
	var s := point_at(p)
	if s < 0:
		return false
	var any := false
	for o in [0, 1, -1, px, -px, plane, -plane]:
		var t: int = s + o
		if t >= 0 and t < f.size() and f[t] > 0.5:
			find_points[t] = d
			any = true
	return any


func _expose(d: int) -> void:
	for t in find_points.keys():
		if find_points[t] == d:
			find_points.erase(t)
	find_exposed.emit(d)


# =====================================================================================
# Saving: the densities as raw floats, deflated (most are exactly 0 or 1)
# =====================================================================================
func to_save_string() -> String:
	var packed := f.to_byte_array().compress(FileAccess.COMPRESSION_DEFLATE)
	return "v3:%d:%d:%d:%s" % [px, pz, ny, Marshalls.raw_to_base64(packed)]


func load_save_string(data: String) -> bool:
	var parts := data.split(":", false, 4)
	if parts.size() != 5 or parts[0] != "v3" or int(parts[1]) != px or int(parts[2]) != pz or int(parts[3]) != ny:
		return false   # a different glacier: keep the fresh one
	var raw := Marshalls.base64_to_raw(parts[4]).decompress(f.size() * 4, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != f.size() * 4:
		return false
	var loaded := raw.to_float32_array()
	for s in loaded.size():
		if loaded[s] > f[s]:
			loaded[s] = f[s]   # ice never grows back (and keeps the edges clean)
	f = loaded
	_count()
	_scan_dirty = true
	_scan_phase = 0
	_update_col_top(0, nx - 1, 0, nz - 1)
	for ci in _chunks.size():
		_dirty[ci] = true
	flush()
	return true


# =====================================================================================
# Melting
# =====================================================================================
func damage_sphere(center: Vector3, radius: float, amount: float) -> int:
	## Heat lands in a ball: every bit of ice inside loses density, most at the
	## centre (100%) fading to 35% at the edge. Harder layers lose less.
	## Returns how many grid points turned to water.
	if amount <= 0.0 or radius <= 0.0:
		return 0
	var inv := 1.0 / res
	var i0 := maxi(1, int(ceil((center.x - radius - origin.x) * inv)))
	var i1 := mini(nx - 2, int(floor((center.x + radius - origin.x) * inv)))
	var j0 := maxi(0, int(ceil((center.y - radius - origin.y) * inv)))
	var j1 := mini(ny - 2, int(floor((center.y + radius - origin.y) * inv)))
	var k0 := maxi(1, int(ceil((center.z - radius - origin.z) * inv)))
	var k1 := mini(nz - 2, int(floor((center.z + radius - origin.z) * inv)))
	if i0 > i1 or j0 > j1 or k0 > k1:
		return 0
	var r2 := radius * radius
	var per := amount * MELT_K / 0.25
	var melted := 0
	var hp_sum := 0.0
	var changed := false
	var found: Array = []
	for j in range(j0, j1 + 1):
		var dy := origin.y + j * res - center.y
		for k in range(k0, k1 + 1):
			var dz := origin.z + k * res - center.z
			var dyz := dy * dy + dz * dz
			if dyz > r2:
				continue
			var base := plane * j + px * (k + 1) + 1
			for i in range(i0, i1 + 1):
				var s := base + i
				var v := f[s]
				if v <= 0.0:
					continue
				var dx := origin.x + i * res - center.x
				var d2 := dx * dx + dyz
				if d2 > r2:
					continue
				var hp := _layer_hp[lay[s]]
				var nv := maxf(v - per * (1.0 - 0.65 * d2 / r2) / hp, 0.0)
				f[s] = nv
				changed = true
				if v > 0.5 and nv <= 0.5:
					melted += 1
					hp_sum += hp
					if find_points.has(s) and not found.has(find_points[s]):
						found.append(find_points[s])
	if changed:
		_touch(i0, i1, k0, k1)
	if melted > 0:
		remaining -= melted
		_scan_dirty = true
		ice_melted.emit(center, melted * point_volume, hp_sum * point_volume * worth)
	for d in found:
		_expose(d)
	return melted


func melt_everything() -> void:
	## The finale (and the dev menu): whatever ice is left turns to water.
	var melted := 0
	var hp_sum := 0.0
	var found: Array = []
	for s in f.size():
		if f[s] > 0.5:
			melted += 1
			hp_sum += _layer_hp[lay[s]]
			if find_points.has(s) and not found.has(find_points[s]):
				found.append(find_points[s])
	f.fill(0.0)
	remaining = 0
	col_top.fill(-1.0)
	_floating.clear()
	_scan_phase = 0
	for ci in _chunks.size():
		_dirty[ci] = true
	if melted > 0:
		ice_melted.emit(Vector3.INF, melted * point_volume, hp_sum * point_volume * worth)
	for d in found:
		_expose(d)


func _touch(i0: int, i1: int, k0: int, k1: int) -> void:
	## Marks chunks whose mesh depends on points in this range as dirty.
	_update_col_top(i0, i1, k0, k1)
	var ca := clampi((i0 - 1) / CH, 0, ncx - 1)
	var cb := clampi((i1 + 1) / CH, 0, ncx - 1)
	var za := clampi((k0 - 1) / CH, 0, ncz - 1)
	var zb := clampi((k1 + 1) / CH, 0, ncz - 1)
	for cz in range(za, zb + 1):
		for cx in range(ca, cb + 1):
			_dirty[cx + cz * ncx] = true


func set_heat(at: Vector3, amount: float, radius: float = 0.9, color: Color = Color(1.0, 0.45, 0.12)) -> void:
	## Where the player's tool is hitting: the shader makes that spot glow (as
	## big as the tool's heat zone, in the tool's colour) and look wet.
	if material == null:
		return
	_heat = amount
	material.set_shader_parameter("heat_pos", at)
	material.set_shader_parameter("heat_amount", amount)
	material.set_shader_parameter("heat_radius", radius)
	material.set_shader_parameter("heat_color", Vector3(color.r, color.g, color.b))


func set_collide(on: bool) -> void:
	## Collision shapes on or off (re-meshes everything over the next frames).
	if on == collide:
		return
	collide = on
	for ci in _chunks.size():
		_dirty[ci] = true


func flush() -> void:
	## Re-mesh every dirty chunk right now (tests, screenshots, loading).
	for ci in _dirty.keys():
		_remesh(ci)
	_dirty.clear()


func _process(delta: float) -> void:
	_clock += delta
	_update_floating(delta)
	if not _dirty.is_empty():
		var start := Time.get_ticks_usec()
		for ci in _dirty.keys():
			var ch: Dictionary = _chunks[ci]
			if _clock - float(ch.t) < CHUNK_MIN_INTERVAL:
				continue
			_dirty.erase(ci)
			_remesh(ci)
			if Time.get_ticks_usec() - start > REMESH_BUDGET_USEC:
				break
	# The last bits of ice pulse so you can find them.
	var left := fraction_left()
	if material != null:
		if left < 0.06 and remaining > 0:
			_glow_t += delta
			material.set_shader_parameter("glow", (0.5 + 0.5 * sin(_glow_t * 4.0)) * clampf((0.06 - left) / 0.04, 0.0, 1.0))
		elif _glow_t > 0.0:
			_glow_t = 0.0
			material.set_shader_parameter("glow", 0.0)


# =====================================================================================
# Loose ice: floating bits, and small chunks on the ground, slowly melt away
# =====================================================================================
func _update_floating(delta: float) -> void:
	_float_t += delta
	if _float_t >= FLOAT_TICK:
		_melt_floating(_float_t)
		_float_t = 0.0
	if _scan_phase == 0:
		if not _scan_dirty or remaining <= 0:
			return
		_scan_wait += delta
		if _scan_wait < FLOAT_SCAN_DELAY:
			return
		_start_scan()
	var deadline := Time.get_ticks_usec() + FLOAT_BUDGET_USEC
	if _scan_phase == 1:
		if not _read_runs(deadline):
			return
		_scan_phase = 2
		var nruns := _runs.size() / 3
		_group.resize(nruns)
		_group.fill(-1)
		_group_melts.clear()
		_queue.clear()
		_q_head = 0
		_next_seed = 0
		if Time.get_ticks_usec() > deadline:
			return
	if _scan_phase == 2:
		if not _group_runs(deadline):
			return
		_collect_floating()
		_scan_phase = 0


func find_floating_now() -> void:
	## Runs the whole search at once (tests, and after loading a save).
	_start_scan()
	_read_runs(Time.get_ticks_usec() + 60000000)
	var nruns := _runs.size() / 3
	_group.resize(nruns)
	_group.fill(-1)
	_group_melts.clear()
	_queue.clear()
	_q_head = 0
	_next_seed = 0
	_group_runs(Time.get_ticks_usec() + 60000000)
	_collect_floating()
	_scan_phase = 0


func floating_count() -> int:
	## Points that are still solid and melting away by themselves.
	var n := 0
	for s in _floating:
		if f[s] > 0.5:
			n += 1
	return n


func _start_scan() -> void:
	_scan_dirty = false
	_scan_wait = 0.0
	_scan_phase = 1
	_scan_c = 0
	_runs.clear()
	if _col_count.size() != plane:
		_col_count.resize(plane)
		_col_first.resize(plane)
	_col_count.fill(0)


func _read_runs(deadline: int) -> bool:
	## Reads each column's solid stretches. Returns true when every column is done.
	var cols := nx * nz
	while _scan_c < cols:
		var k := _scan_c / nx
		var i := _scan_c - k * nx
		_scan_c += 1
		var c := (i + 1) + px * (k + 1)
		var top := col_top[c]
		if top < 0.0:
			continue
		var jmax := mini(ny - 1, int((top - origin.y) / res) + 1)
		var first := _runs.size() / 3
		var n := 0
		var j := 0
		while j <= jmax:
			if f[c + plane * j] > 0.5:
				var j0 := j
				while j < jmax and f[c + plane * (j + 1)] > 0.5:
					j += 1
				_runs.append(c)
				_runs.append(j0)
				_runs.append(j)
				n += 1
			j += 1
		if n > 0:
			_col_first[c] = first
			_col_count[c] = n
		if (_scan_c & 15) == 0 and Time.get_ticks_usec() > deadline:
			return false
	return true


func _group_runs(deadline: int) -> bool:
	## Groups touching runs (flood fill). Returns true when every run has a group.
	var nruns := _runs.size() / 3
	var steps := 0
	while true:
		if _q_head >= _queue.size():
			if not _queue.is_empty():
				# This group is done: does it melt?
				_group_melts.append(1 if (not _cur_grounded or _cur_size < _small_points) else 0)
				_queue.clear()
				_q_head = 0
			while _next_seed < nruns and _group[_next_seed] >= 0:
				_next_seed += 1
			if _next_seed >= nruns:
				return true
			_group[_next_seed] = _group_melts.size()
			_queue.append(_next_seed)
			_cur_size = 0
			_cur_grounded = false
		var r := _queue[_q_head]
		_q_head += 1
		var g := _group[r]
		var c := _runs[r * 3]
		var j0 := _runs[r * 3 + 1]
		var j1 := _runs[r * 3 + 2]
		_cur_size += j1 - j0 + 1
		if j0 == 0:
			_cur_grounded = true
		for side in 4:
			var nc := c + (-1 if side == 0 else (1 if side == 1 else (-px if side == 2 else px)))
			var cnt := _col_count[nc]
			if cnt == 0:
				continue
			var q := _col_first[nc]
			for _n in cnt:
				if _group[q] < 0 and _runs[q * 3 + 1] <= j1 and _runs[q * 3 + 2] >= j0:
					_group[q] = g
					_queue.append(q)
				q += 1
		steps += 1
		if (steps & 15) == 0 and Time.get_ticks_usec() > deadline:
			return false
	return true


func _collect_floating() -> void:
	## Every solid point in a group that melts joins the list (points still
	## fading from the last search stay on it).
	var keep := PackedInt32Array()
	for s in _floating:
		if f[s] > 0.0 and f[s] <= 0.5:
			keep.append(s)
	var nruns := _runs.size() / 3
	for r in nruns:
		var g := _group[r]
		if g < 0 or g >= _group_melts.size() or _group_melts[g] == 0:
			continue
		var c := _runs[r * 3]
		for j in range(_runs[r * 3 + 1], _runs[r * 3 + 2] + 1):
			var s := c + plane * j
			if f[s] > 0.5:
				keep.append(s)
	_floating = keep


func _drip_from(lo: Vector3, hi: Vector3) -> void:
	## Meltwater dripping off the underside of whatever is melting away.
	if _drips == null:
		_drips = CPUParticles3D.new()
		_drips.amount = 28
		_drips.lifetime = 0.9
		_drips.local_coords = false
		_drips.direction = Vector3(0, -1, 0)
		_drips.spread = 8.0
		_drips.gravity = Vector3(0, -9.0, 0)
		_drips.initial_velocity_min = 0.0
		_drips.initial_velocity_max = 0.4
		_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		var quad := QuadMesh.new()
		quad.size = Vector2(0.07, 0.11)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true   # see Player._make_particles
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = UiTheme.soft_dot()
		quad.material = mat
		_drips.mesh = quad
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.8, 0.93, 1.0, 0.95))
		ramp.set_color(1, Color(0.65, 0.85, 1.0, 0.0))
		_drips.color_ramp = ramp
		add_child(_drips)
	var c := (lo + hi) * 0.5
	_drips.position = Vector3(c.x, lo.y, c.z)
	_drips.emission_box_extents = Vector3(maxf(0.2, (hi.x - lo.x) * 0.5), 0.05, maxf(0.2, (hi.z - lo.z) * 0.5))
	_drips.emitting = true


func _melt_floating(dt: float) -> void:
	if _floating.is_empty():
		return
	# The more sides of a point are open to the air, the faster it melts: a
	# chunk loses its corners, then its edges, and shrinks from the outside in
	# instead of fading all at once.
	var count := _floating.size()
	var open := PackedByteArray()
	open.resize(count)
	for n in count:
		open[n] = _open_sides(_floating[n])
	var keep := PackedInt32Array()
	var melted := 0
	var hp_sum := 0.0
	var at := Vector3.ZERO
	var found: Array = []
	var cols := {}
	var drip := -1
	var drip_n := 0
	for n in count:
		var s := _floating[n]
		var v := f[s]
		var rate := FLOAT_CORE_RATE
		if v <= 0.5:
			rate = FLOAT_MELT_RATE * maxi(open[n], 2)   # already gone: fade out
		elif open[n] > 0:
			rate = FLOAT_MELT_RATE * open[n]
		var nv := maxf(v - rate * dt, 0.0)
		f[s] = nv
		cols[s % plane] = true
		if v > 0.5 and nv <= 0.5:
			melted += 1
			hp_sum += _layer_hp[lay[s]]
			at += point_pos(s)
			if find_points.has(s) and not found.has(find_points[s]):
				found.append(find_points[s])
		if nv > 0.0:
			keep.append(s)
			if open[n] > 0 and nv > 0.5:
				drip_n += 1
				if randi() % drip_n == 0:
					drip = s   # one melting spot, picked at random, drips this tick
	_floating = keep
	# Only the columns that changed: loose bits can be far apart.
	for r in cols:
		var i: int = r % px - 1
		var k: int = r / px - 1
		_touch(i, i, k, k)
	if drip >= 0:
		var p := point_pos(drip)
		_drip_from(p - Vector3(0.3, 0.25, 0.3), p + Vector3(0.3, -0.25, 0.3))
	elif _drips != null:
		_drips.emitting = false
	if melted > 0:
		remaining -= melted
		ice_melted.emit(at / float(melted), melted * point_volume, hp_sum * point_volume * worth)
	for d in found:
		_expose(d)


func _open_sides(s: int) -> int:
	## How many of the six neighbours of grid point `s` are air (the ground
	## below the bottom row doesn't count).
	var n := 0
	if f[s - 1] <= 0.5:
		n += 1
	if f[s + 1] <= 0.5:
		n += 1
	if f[s - px] <= 0.5:
		n += 1
	if f[s + px] <= 0.5:
		n += 1
	if s + plane >= f.size() or f[s + plane] <= 0.5:
		n += 1
	if s >= plane and f[s - plane] <= 0.5:
		n += 1
	return n


# =====================================================================================
# Meshing: surface nets, one chunk at a time
# =====================================================================================
func _remesh(ci: int) -> void:
	var ch: Dictionary = _chunks[ci]
	ch.t = _clock
	var mi: MeshInstance3D = ch.mesh
	var cs: CollisionShape3D = ch.shape
	var mesh := _build_chunk_mesh(ci)
	mi.mesh = mesh
	if mesh == null or not collide:
		cs.disabled = true
		cs.shape = null
		return
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	cs.disabled = false


func _build_chunk_mesh(ci: int) -> ArrayMesh:
	var cx := ci % ncx
	var cz := ci / ncx
	var x0 := cx * CH                 # owned points: [x0, x1) x [z0, z1)
	var z0 := cz * CH
	var x1 := mini(x0 + CH, nx)
	var z1 := mini(z0 + CH, nz)
	# Vertices live in cells [x0-1, x1) x [z0-1, z1) x [-1, ny-1); cell row r = y + 1.
	var cw := x1 - x0 + 1
	var cd := z1 - z0 + 1
	var crows := ny
	var cell_v := PackedInt32Array()
	cell_v.resize(cw * cd * crows)
	cell_v.fill(-1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var ff := f
	var pl := plane
	var ox := origin.x
	var oy := origin.y
	var oz := origin.z
	var nl := _layer_col.size() - 1
	var inv_res := 1.0 / res

	for lz in cd:
		var k := z0 - 1 + lz
		for lx in cw:
			var i := x0 - 1 + lx
			var s00 := (i + 1) + px * (k + 1)
			var s10 := s00 + 1
			var s01 := s00 + px
			var s11 := s01 + 1
			# Nothing to do above the highest ice in these four columns.
			var hi := maxf(maxf(col_top[s00], col_top[s10]), maxf(col_top[s01], col_top[s11]))
			if hi < 0.0:
				continue
			var rows := mini(crows - 1, int((hi - oy) * inv_res) + 3)
			var top_here := top0[s00]
			# Bottom corners of row -1 repeat row 0.
			var a0 := ff[s00]
			var a1 := ff[s10]
			var a2 := ff[s01]
			var a3 := ff[s11]
			for r in rows:
				var off := r * pl            # row r is cells at y = r - 1; top corners are point row r
				var b0 := ff[s00 + off]
				var b1 := ff[s10 + off]
				var b2 := ff[s01 + off]
				var b3 := ff[s11 + off]
				var n_in := int(a0 > 0.5) + int(a1 > 0.5) + int(a2 > 0.5) + int(a3 > 0.5) \
					+ int(b0 > 0.5) + int(b1 > 0.5) + int(b2 > 0.5) + int(b3 > 0.5)
				if n_in != 0 and n_in != 8:
					# Average of where the surface crosses the cell's 12 edges.
					var sx := 0.0
					var sy := 0.0
					var sz := 0.0
					var n := 0
					if (a0 > 0.5) != (a1 > 0.5):
						sx += (0.5 - a0) / (a1 - a0)
						n += 1
					if (a2 > 0.5) != (a3 > 0.5):
						sx += (0.5 - a2) / (a3 - a2)
						sz += 1.0
						n += 1
					if (b0 > 0.5) != (b1 > 0.5):
						sx += (0.5 - b0) / (b1 - b0)
						sy += 1.0
						n += 1
					if (b2 > 0.5) != (b3 > 0.5):
						sx += (0.5 - b2) / (b3 - b2)
						sy += 1.0
						sz += 1.0
						n += 1
					if (a0 > 0.5) != (a2 > 0.5):
						sz += (0.5 - a0) / (a2 - a0)
						n += 1
					if (a1 > 0.5) != (a3 > 0.5):
						sz += (0.5 - a1) / (a3 - a1)
						sx += 1.0
						n += 1
					if (b0 > 0.5) != (b2 > 0.5):
						sz += (0.5 - b0) / (b2 - b0)
						sy += 1.0
						n += 1
					if (b1 > 0.5) != (b3 > 0.5):
						sz += (0.5 - b1) / (b3 - b1)
						sx += 1.0
						sy += 1.0
						n += 1
					if (a0 > 0.5) != (b0 > 0.5):
						sy += (0.5 - a0) / (b0 - a0)
						n += 1
					if (a1 > 0.5) != (b1 > 0.5):
						sy += (0.5 - a1) / (b1 - a1)
						sx += 1.0
						n += 1
					if (a2 > 0.5) != (b2 > 0.5):
						sy += (0.5 - a2) / (b2 - a2)
						sz += 1.0
						n += 1
					if (a3 > 0.5) != (b3 > 0.5):
						sy += (0.5 - a3) / (b3 - a3)
						sx += 1.0
						sz += 1.0
						n += 1
					var inv_n := 1.0 / float(n)
					var wx := ox + (float(i) + sx * inv_n) * res
					var wy := oy + (float(r - 1) + sy * inv_n) * res
					var wz := oz + (float(k) + sz * inv_n) * res
					var g := Vector3((a1 + a3 + b1 + b3) - (a0 + a2 + b0 + b2),
						(b0 + b1 + b2 + b3) - (a0 + a1 + a2 + a3),
						(a2 + a3 + b2 + b3) - (a0 + a1 + b0 + b1))
					var nrm := -g.normalized() if g.length_squared() > 0.000001 else Vector3.UP
					cell_v[lx + cw * (lz + cd * r)] = verts.size()
					verts.append(Vector3(wx, wy, wz))
					norms.append(nrm)
					cols.append(_vertex_color(wx, wy, wz, nrm, top_here, nl))
				a0 = b0
				a1 = b1
				a2 = b2
				a3 = b3

	if verts.is_empty():
		return null
	var idx := PackedInt32Array()
	# Quads: one per crossed grid edge whose start point this chunk owns.
	for k in range(z0, z1):
		var lz := k - z0 + 1                 # local cell z of cells at z = k
		for i in range(x0, x1):
			var lx := i - x0 + 1
			var c := (i + 1) + px * (k + 1)
			var hi := maxf(col_top[c], maxf(col_top[c + 1], col_top[c + px]))
			if hi < 0.0:
				continue
			var jn := mini(ny - 1, int((hi - oy) * inv_res) + 2)
			for j in range(0, jn):
				var r := j + 1                   # cell row of cells at y = j
				var s := c + pl * j
				var inside := ff[s] > 0.5
				# x edge: (i,j,k) -> (i+1,j,k); cells (i, j-1..j, k-1..k)
				if inside != (ff[s + 1] > 0.5) and i < nx - 1:
					var c0 := cell_v[lx + cw * ((lz - 1) + cd * (r - 1))]
					var c1 := cell_v[lx + cw * ((lz - 1) + cd * r)]
					var c2 := cell_v[lx + cw * (lz + cd * r)]
					var c3 := cell_v[lx + cw * (lz + cd * (r - 1))]
					if c0 >= 0 and c1 >= 0 and c2 >= 0 and c3 >= 0:
						if inside:
							idx.append_array([c0, c3, c2, c0, c2, c1])
						else:
							idx.append_array([c0, c1, c2, c0, c2, c3])
				# y edge: (i,j,k) -> (i,j+1,k); cells (i-1..i, j, k-1..k)
				if inside != (ff[s + pl] > 0.5):
					var c0 := cell_v[(lx - 1) + cw * ((lz - 1) + cd * r)]
					var c1 := cell_v[lx + cw * ((lz - 1) + cd * r)]
					var c2 := cell_v[lx + cw * (lz + cd * r)]
					var c3 := cell_v[(lx - 1) + cw * (lz + cd * r)]
					if c0 >= 0 and c1 >= 0 and c2 >= 0 and c3 >= 0:
						if inside:
							idx.append_array([c0, c1, c2, c0, c2, c3])
						else:
							idx.append_array([c0, c3, c2, c0, c2, c1])
				# z edge: (i,j,k) -> (i,j,k+1); cells (i-1..i, j-1..j, k)
				if inside != (ff[s + px] > 0.5) and k < nz - 1:
					var c0 := cell_v[(lx - 1) + cw * (lz + cd * (r - 1))]
					var c1 := cell_v[lx + cw * (lz + cd * (r - 1))]
					var c2 := cell_v[lx + cw * (lz + cd * r)]
					var c3 := cell_v[(lx - 1) + cw * (lz + cd * r)]
					if c0 >= 0 and c1 >= 0 and c2 >= 0 and c3 >= 0:
						if inside:
							idx.append_array([c0, c3, c2, c0, c2, c1])
						else:
							idx.append_array([c0, c1, c2, c0, c2, c3])
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _vertex_color(x: float, y: float, z: float, n: Vector3, top: float, nl: int) -> Color:
	## RGB: the ice colour for how deep this spot sat in the original glacier,
	## darkened in nooks (a cheap ambient occlusion from the density around it).
	## A: 1 on the untouched snowy top, 0 on freshly carved ice.
	var depth := top - y
	var lf := clampf(depth / layer_depth - 0.5, 0.0, float(nl))
	var l0 := int(lf)
	var l1 := mini(l0 + 1, nl)
	var c: Color = (_layer_col[l0] as Color).lerp(_layer_col[l1], smoothstep(0.0, 1.0, lf - l0))
	var p := Vector3(x, y, z)
	var occ := density_at(p + n * 0.8) * 0.5 + density_at(p + Vector3(0, 1.4, 0)) * 0.35
	var ao := clampf(1.0 - occ, 0.45, 1.0)
	var cover := clampf(1.0 - depth / 0.45, 0.0, 1.0) * smoothstep(1.6, 4.2, top)   # thin ice is bare
	c = Color(c.r * ao, c.g * ao, c.b * ao, cover)
	return c
