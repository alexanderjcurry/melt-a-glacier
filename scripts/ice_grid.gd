class_name IceGrid
extends Node3D
## The glacier: a grid of 1 m ice blocks, each with hit points.
## Every block is drawn by one MultiMesh. The grid also answers ray, collision
## and surface queries for the player and the helpers.

signal block_melted(cell: Vector3i, layer: int)

const HIDDEN_SCALE := Vector3(0.0001, 0.0001, 0.0001)

var sx: int = Balance.GRID_X
var sy: int = Balance.GRID_Y
var sz: int = Balance.GRID_Z
var origin: Vector3 = Balance.GRID_ORIGIN

var hp := PackedFloat32Array()        # current hp per cell (0 = no ice)
var max_hp := PackedFloat32Array()    # hp of a full block in that cell (0 = never had ice)
var layer := PackedByteArray()        # ice layer per cell (0 = surface snow)
var heights := PackedInt32Array()     # original column heights, index x + z * sx
var inst := PackedInt32Array()        # cell -> MultiMesh instance (-1 = none)
var inst_cell := PackedInt32Array()   # MultiMesh instance -> cell
var tint := PackedFloat32Array()      # per-instance brightness jitter
var total_blocks := 0
var remaining := 0

var _mm: MultiMesh
var _pulse_t := 0.0
var _rng := RandomNumberGenerator.new()


# --- Building ---------------------------------------------------------------------
func generate(carve: Array = []) -> void:
	## Builds the glacier. Cells whose centre is inside one of the `carve` AABBs
	## (the buried houses) are left empty.
	var n := sx * sy * sz
	hp.resize(n)
	max_hp.resize(n)
	layer.resize(n)
	inst.resize(n)
	hp.fill(0.0)
	max_hp.fill(0.0)
	layer.fill(0)
	inst.fill(-1)
	heights.resize(sx * sz)
	var noise := FastNoiseLite.new()
	noise.seed = Balance.WORLD_SEED
	noise.frequency = 0.09
	for z in sz:
		for x in sx:
			var h := _column_height(x, z, noise)
			heights[x + z * sx] = h
			for y in h:
				if _carved(cell_center(Vector3i(x, y, z)), carve):
					continue
				var i := idx(x, y, z)
				var l := mini(h - 1 - y, Balance.LAYERS.size() - 1)
				layer[i] = l
				max_hp[i] = Balance.layer_hp(l)
				hp[i] = max_hp[i]
	_rng.seed = Balance.WORLD_SEED + 99
	_build_multimesh()


func _carved(p: Vector3, carve: Array) -> bool:
	for box in carve:
		if (box as AABB).has_point(p):
			return true
	return false


func _column_height(x: int, z: int, noise: FastNoiseLite) -> int:
	var nx := (float(x) + 0.5) / float(sx) * 2.0 - 1.0   # -1..1 across the valley
	var nz := (float(z) + 0.5) / float(sz)                # 0 = back wall, 1 = front tongue
	if absf(nx) > 0.94:
		return 0   # a walkable gap along the valley walls
	var across := clampf(1.0 - pow(absf(nx), 2.4), 0.0, 1.0)
	var front := smoothstep(1.0, 0.5, nz)              # ramp down towards the front
	var bumps := noise.get_noise_2d(float(x), float(z)) * 1.5
	var h := float(sy) * sqrt(across) * front + bumps * front
	return clampi(int(round(h)), 0, sy)


func _build_multimesh() -> void:
	var count := 0
	for i in max_hp.size():
		if max_hp[i] > 0.0:
			count += 1
	total_blocks = count
	inst_cell.resize(count)
	tint.resize(count)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE * Balance.BLOCK
	_mm.mesh = box
	_mm.instance_count = count
	_mm.custom_aabb = AABB(origin - Vector3(1, 51, 1), Vector3(sx + 2, sy + 52, sz + 2) * Balance.BLOCK)
	var jitter := RandomNumberGenerator.new()
	jitter.seed = Balance.WORLD_SEED + 1
	var k := 0
	for i in max_hp.size():
		if max_hp[i] <= 0.0:
			continue
		inst[i] = k
		inst_cell[k] = i
		tint[k] = jitter.randf_range(-0.04, 0.04)
		k += 1
	remaining = 0
	for j in count:
		var c := inst_cell[j]
		if hp[c] > 0.0:
			remaining += 1
		_refresh_instance(c)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _block_texture()
	mat.roughness = 0.3
	mat.metallic_specular = 0.6
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _block_texture() -> ImageTexture:
	## Six tiles in BoxMesh's 3x2 UV layout (row 0: front, right, back;
	## row 1: left, top, bottom): faint noise with darker edges so blocks read
	## as blocks, and the sides a little darker than the top, like a voxel game.
	var tile := 64
	var img := Image.create(tile * 3, tile * 2, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = Balance.WORLD_SEED + 3
	noise.frequency = 0.07
	for ty in 2:
		for tx in 3:
			var shade := 1.0 if (tx == 1 and ty == 1) else 0.84
			for y in tile:
				for x in tile:
					var edge := mini(mini(x, y), mini(tile - 1 - x, tile - 1 - y))
					var v := 0.95 + 0.05 * noise.get_noise_2d(float(x + tx * 97), float(y + ty * 57))
					if edge < 2:
						v = 0.66
					elif edge < 4:
						v = 0.82
					v *= shade
					img.set_pixel(tx * tile + x, ty * tile + y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _refresh_instance(c: int) -> void:
	var k := inst[c]
	if k < 0:
		return
	var p := cell_center_i(c)
	if hp[c] <= 0.0:
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(HIDDEN_SCALE), p + Vector3(0, -50, 0)))
		return
	var f := hp[c] / max_hp[c]
	var s := lerpf(0.6, 1.0, f)
	_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
	var col: Color = Balance.LAYERS[layer[c]].color
	col = col.lightened(tint[k]) if tint[k] >= 0.0 else col.darkened(-tint[k])
	if f < 1.0:
		col = col.lerp(Color(0.55, 0.88, 1.0), (1.0 - f) * 0.5)   # wet and glassy while melting
	_mm.set_instance_color(k, col)


# --- Cells -----------------------------------------------------------------------------
func idx(x: int, y: int, z: int) -> int:
	return x + sx * (z + sz * y)


func cell_of(i: int) -> Vector3i:
	var x := i % sx
	var t := i / sx
	return Vector3i(x, t / sz, t % sz)


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < sx and y < sy and z < sz


func solid(c: Vector3i) -> bool:
	return in_bounds(c.x, c.y, c.z) and hp[idx(c.x, c.y, c.z)] > 0.0


func cell_center(c: Vector3i) -> Vector3:
	return origin + (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * Balance.BLOCK


func cell_center_i(i: int) -> Vector3:
	return cell_center(cell_of(i))


func world_to_cell(p: Vector3) -> Vector3i:
	var q := (p - origin) / Balance.BLOCK
	return Vector3i(floori(q.x), floori(q.y), floori(q.z))


func layer_at(c: Vector3i) -> int:
	return layer[idx(c.x, c.y, c.z)]


func hp_fraction(c: Vector3i) -> float:
	var i := idx(c.x, c.y, c.z)
	return hp[i] / max_hp[i] if max_hp[i] > 0.0 else 0.0


func fraction_left() -> float:
	return float(remaining) / float(maxi(total_blocks, 1))


# --- Surface queries ---------------------------------------------------------------------
func column_top_y(x: int, z: int) -> int:
	## Index of the highest block left in a column, or -1 if it's bare ground.
	if x < 0 or z < 0 or x >= sx or z >= sz:
		return -1
	for y in range(sy - 1, -1, -1):
		if hp[idx(x, y, z)] > 0.0:
			return y
	return -1


func surface_height_at(p: Vector3) -> float:
	## World height of the ice (or ground) under a point.
	var c := world_to_cell(p)
	return origin.y + float(column_top_y(c.x, c.z) + 1) * Balance.BLOCK


func random_surface_cell(rng: RandomNumberGenerator) -> Vector3i:
	## A random top block somewhere on the glacier, or y = -1 if all ice is gone.
	if remaining <= 0:
		return Vector3i(0, -1, 0)
	for _t in 200:
		var x := rng.randi_range(0, sx - 1)
		var z := rng.randi_range(0, sz - 1)
		var y := column_top_y(x, z)
		if y >= 0:
			return Vector3i(x, y, z)
	for j in total_blocks:   # sparse ice left: scan
		var c := inst_cell[j]
		if hp[c] > 0.0:
			var cc := cell_of(c)
			return Vector3i(cc.x, column_top_y(cc.x, cc.z), cc.z)
	return Vector3i(0, -1, 0)


func nearby_surface_cell(from: Vector3i, rng: RandomNumberGenerator, reach: int = 4) -> Vector3i:
	for _t in 24:
		var x := from.x + rng.randi_range(-reach, reach)
		var z := from.z + rng.randi_range(-reach, reach)
		var y := column_top_y(x, z)
		if y >= 0:
			return Vector3i(x, y, z)
	return random_surface_cell(rng)


# --- Melting -----------------------------------------------------------------------------
func damage_cell(c: Vector3i, amount: float) -> bool:
	## Returns true if the block melted away.
	if not in_bounds(c.x, c.y, c.z):
		return false
	return _damage_index(idx(c.x, c.y, c.z), amount)


func _damage_index(i: int, amount: float) -> bool:
	if hp[i] <= 0.0 or amount <= 0.0:
		return false
	hp[i] -= amount
	if hp[i] <= 0.0:
		hp[i] = 0.0
		remaining -= 1
		_refresh_instance(i)
		block_melted.emit(cell_of(i), int(layer[i]))
		return true
	_refresh_instance(i)
	return false


func damage_sphere(center: Vector3, radius: float, amount: float, always_index: int = -1) -> int:
	## Melts `amount` hp at the centre of a ball of heat, fading to 35% at its edge.
	## `always_index` (the block being aimed at) always takes full damage.
	## Returns how many blocks melted away.
	var melted := 0
	if always_index >= 0 and _damage_index(always_index, amount):
		melted += 1
	var lo := world_to_cell(center - Vector3.ONE * radius)
	var hi := world_to_cell(center + Vector3.ONE * radius)
	var r2 := radius * radius
	for y in range(maxi(lo.y, 0), mini(hi.y, sy - 1) + 1):
		for z in range(maxi(lo.z, 0), mini(hi.z, sz - 1) + 1):
			for x in range(maxi(lo.x, 0), mini(hi.x, sx - 1) + 1):
				var i := idx(x, y, z)
				if i == always_index or hp[i] <= 0.0:
					continue
				var c := origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * Balance.BLOCK
				var d2 := c.distance_squared_to(center)
				if d2 > r2:
					continue
				var falloff := lerpf(1.0, 0.35, sqrt(d2) / radius)
				if _damage_index(i, amount * falloff):
					melted += 1
	return melted


func melt_budget(budget: float, rng: RandomNumberGenerator) -> int:
	## Spends `budget` hp melting random surface blocks (offline helpers).
	var melted := 0
	var guard := 0
	while budget > 0.0 and remaining > 0 and guard < 200000:
		guard += 1
		var c := random_surface_cell(rng)
		if c.y < 0:
			break
		var i := idx(c.x, c.y, c.z)
		var need := hp[i]
		if need <= budget:
			budget -= need
			if _damage_index(i, need + 0.001):
				melted += 1
		else:
			_damage_index(i, budget)
			budget = 0.0
	return melted


func melt_everything() -> void:
	## Debug / dev menu helper.
	for j in total_blocks:
		var c := inst_cell[j]
		if hp[c] > 0.0:
			_damage_index(c, hp[c] + 1.0)


# --- Ray and collision queries -----------------------------------------------------------
func raycast(from: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	## Walks the grid along a ray (Amanatides & Woo). Returns the first ice block
	## hit within max_dist: {hit, cell, index, pos, normal, dist}.
	var p := (from - origin) / Balance.BLOCK
	var cx := floori(p.x)
	var cy := floori(p.y)
	var cz := floori(p.z)
	var stx := 1 if dir.x > 0.0 else -1
	var sty := 1 if dir.y > 0.0 else -1
	var stz := 1 if dir.z > 0.0 else -1
	var tdx := absf(1.0 / dir.x) if dir.x != 0.0 else INF
	var tdy := absf(1.0 / dir.y) if dir.y != 0.0 else INF
	var tdz := absf(1.0 / dir.z) if dir.z != 0.0 else INF
	var tmx := INF
	var tmy := INF
	var tmz := INF
	if dir.x > 0.0:
		tmx = (float(cx + 1) - p.x) / dir.x
	elif dir.x < 0.0:
		tmx = (p.x - float(cx)) / -dir.x
	if dir.y > 0.0:
		tmy = (float(cy + 1) - p.y) / dir.y
	elif dir.y < 0.0:
		tmy = (p.y - float(cy)) / -dir.y
	if dir.z > 0.0:
		tmz = (float(cz + 1) - p.z) / dir.z
	elif dir.z < 0.0:
		tmz = (p.z - float(cz)) / -dir.z
	var t := 0.0
	var nrm := Vector3.ZERO
	var max_t := max_dist / Balance.BLOCK
	for _i in 600:
		if in_bounds(cx, cy, cz):
			var i := idx(cx, cy, cz)
			if hp[i] > 0.0:
				return {"hit": true, "cell": Vector3i(cx, cy, cz), "index": i,
					"pos": from + dir * t * Balance.BLOCK, "normal": nrm, "dist": t * Balance.BLOCK}
		if tmx < tmy and tmx < tmz:
			t = tmx
			tmx += tdx
			cx += stx
			nrm = Vector3(-stx, 0, 0)
		elif tmy < tmz:
			t = tmy
			tmy += tdy
			cy += sty
			nrm = Vector3(0, -sty, 0)
		else:
			t = tmz
			tmz += tdz
			cz += stz
			nrm = Vector3(0, 0, -stz)
		if t > max_t or cy < -1:
			break
	return {"hit": false}


func box_hits_ice(mn: Vector3, mx: Vector3) -> bool:
	var a := world_to_cell(mn)
	var b := world_to_cell(mx - Vector3(0.0001, 0.0001, 0.0001))
	for y in range(maxi(a.y, 0), mini(b.y, sy - 1) + 1):
		for z in range(maxi(a.z, 0), mini(b.z, sz - 1) + 1):
			for x in range(maxi(a.x, 0), mini(b.x, sx - 1) + 1):
				if hp[idx(x, y, z)] > 0.0:
					return true
	return false


# --- Save data -------------------------------------------------------------------------
func to_save_string() -> String:
	var raw := PackedByteArray()
	raw.resize(total_blocks)
	for j in total_blocks:
		var c := inst_cell[j]
		var v := 0
		if hp[c] > 0.0:
			v = clampi(int(round(hp[c] / max_hp[c] * 255.0)), 1, 255)
		raw[j] = v
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return "%d:%s" % [total_blocks, Marshalls.raw_to_base64(packed)]


func load_save_string(s: String) -> bool:
	var parts := s.split(":", false, 1)
	if parts.size() != 2 or int(parts[0]) != total_blocks:
		return false   # different glacier layout: keep the fresh one
	var raw := Marshalls.base64_to_raw(parts[1]).decompress(total_blocks, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != total_blocks:
		return false
	remaining = 0
	for j in total_blocks:
		var c := inst_cell[j]
		hp[c] = max_hp[c] * float(raw[j]) / 255.0
		if hp[c] > 0.0:
			remaining += 1
		_refresh_instance(c)
	return true


# --- The last few blocks glow so you can find them ----------------------------------
func _process(delta: float) -> void:
	if remaining <= 0 or remaining > 30:
		return
	_pulse_t += delta
	if fmod(_pulse_t, 0.1) > delta:
		return
	var glow := 0.5 + 0.5 * sin(_pulse_t * 5.0)
	for j in total_blocks:
		var c := inst_cell[j]
		if hp[c] > 0.0:
			var col: Color = Balance.LAYERS[layer[c]].color
			_mm.set_instance_color(j, col.lerp(Color(1.0, 0.8, 0.3), glow))
