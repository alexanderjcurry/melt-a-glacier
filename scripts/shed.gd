class_name Shed
extends Node3D
## The tool shed: a red cabin you walk into. Everything for sale is a real
## thing in the room. Tools hang on the pegboard wall, upgrades sit on the
## workbench under the windows, helpers wait in the hiring corner, finds go on
## a shelf by the door, and the catalogue (boosts and purchases) lies open on a
## table. Look at something to see what it is and what it costs, then click
## (or tap BUY) to get it.
##
## The building is one mesh drawn with shaders/wood.gdshader. Things that
## change (the tools, props, figures, signs) are their own nodes.

const SHOP_LAYER := 8          # physics layer of the "what am I looking at" boxes
const X0 := 9.0                # the room, inside the walls
const X1 := 17.0
const Z0 := 8.0
const Z1 := 15.0
const WALL := 0.2
const H := 3.2                 # wall height
const RISE := 2.0              # the ridge, above the wall tops
const EAVE := 0.4              # how far the roof hangs over the long walls
const GABLE := 0.3             # and over the gable ends
const DOOR_Z0 := 10.75
const DOOR_Z1 := 12.25
const DOOR_H := 2.4
const WINDOWS := [[10.9, 12.1], [13.9, 15.1]]   # in the south wall, x from..to
const WIN_Y0 := 2.15
const WIN_Y1 := 2.85
const LOOK_RANGE := 4.0
const SLOTS := [10.45, 11.58, 12.71, 13.84, 14.97, 16.1]   # columns on the tool wall and the bench
const HELPER_Z := [9.6, 11.5, 13.4]
# The last slots on the finds shelf are the glaciers themselves.
const GLACIER_SLOTS := [
	{"glacier": 0, "icon": "🏘️", "title": "The Village", "body": "Free at last! Everyone's home.",
		"hint": "Something big is under all that ice."},
	{"glacier": 1, "icon": "🏞️", "title": "The Lake", "body": "Thawed out. Summer is back!",
		"hint": "What's under the frozen lake?"},
]
const FIND_ROWS := [0.08, 0.5, 0.92, 1.34, 1.76]   # shelf heights, bottom up
const FIND_Z := [8.56, 9.12, 9.68, 10.24]
const LAMPS := [Vector3(11.5, 2.66, 11.5), Vector3(14.5, 2.66, 11.5)]

const RED_PAINT := Color(0.62, 0.17, 0.13)
const TRIM := Color(0.93, 0.9, 0.82)
const PINE := Color(0.82, 0.64, 0.44)
const FLOOR := Color(0.56, 0.39, 0.26)
const BEAM := Color(0.45, 0.3, 0.19)
const ROOF := Color(0.3, 0.31, 0.34)
const STONE := Color(0.55, 0.55, 0.56)
const TEAL := Color(0.3, 0.5, 0.48)
const INK := Color(0.27, 0.15, 0.09)
const PAPER := Color(0.97, 0.93, 0.82)
const GREEN_INK := Color(0.12, 0.42, 0.18)
const GREY_INK := Color(0.45, 0.42, 0.4)
const HILITE := Color(0.85, 0.32, 0.04)

const BOARDS := 1.0            # vertex alpha = pattern in the wood shader
const SHINGLES := 0.5
const PEGBOARD := 0.2
const PAINT := 0.0

const HELPER_NAMES := ["Penguin", "Sauna Crew", "Kevin the Volcano"]
const UPGRADE_NAMES := {"jet": "Fuel Tank"}

var items: Array = []          # {kind, id, node, label, price, body, base_rot, base_pos, base_scale}
var marker: Label3D            # "🏠 Shed", seen from anywhere in the valley
var player: Node3D             # for Kevin's eyes

var _st: SurfaceTool           # everything that doesn't move: one mesh, wood shader
var _body: StaticBody3D        # walls, roof and furniture you bump into
var _hilite := -1
var _refresh_t := 0.0
var _t := 0.0
var _figures: Array = []       # [node, type]
var _shown_gold := false
var _ice_cubes := {}           # find slot -> MeshInstance3D (still frozen)


func build(detail: Texture2D) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = Player.WORLD_LAYER
	_body.collision_mask = 0
	add_child(_body)
	_st = MeshKit.begin()
	_build_walls()
	_build_roof()
	_build_door()
	_build_room()
	_build_lamps()
	_build_tools()
	_build_bench()
	_build_helpers()
	_build_finds()
	_build_catalogue()
	_build_marker()
	var mi := MeshInstance3D.new()
	mi.name = "Building"
	mi.mesh = MeshKit.finish(_st)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wood.gdshader")
	mat.set_shader_parameter("detail_tex", detail)
	mi.material_override = mat
	mi.layers = 3   # layer 2: lit by the lamps inside (the valley floor outside isn't)
	add_child(mi)
	_st = null
	refresh()


# =====================================================================================
# Questions the world asks
# =====================================================================================
func contains(p: Vector3) -> bool:
	## Is p inside (counting the doorway)?
	return p.x > X0 - WALL * 0.5 and p.x < X1 and p.z > Z0 and p.z < Z1 and p.y < H


func blocks(x: float, z: float, margin: float) -> bool:
	## Would something placed at x, z stand in the shed, under its roof, or on the doormat?
	if x > X0 - WALL - GABLE - margin and x < X1 + WALL + GABLE + margin \
			and z > Z0 - WALL - EAVE - margin and z < Z1 + WALL + EAVE + margin:
		return true
	return x > 7.4 - margin and x < X0 and z > DOOR_Z0 - 0.4 - margin and z < DOOR_Z1 + 0.4 + margin


func aim(from: Vector3, dir: Vector3) -> Dictionary:
	## The thing for sale under the crosshair ({} if none).
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * LOOK_RANGE, SHOP_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.collider == null or not (hit.collider as Object).has_meta("item"):
		return {}
	return items[int((hit.collider as Object).get_meta("item"))]


func item(kind: String, id: Variant) -> Dictionary:
	for it in items:
		if it.kind == kind and it.id == id:
			return it
	return {}


# =====================================================================================
# What things are and what they cost
# =====================================================================================
func describe(it: Dictionary) -> Dictionary:
	## {title, body, price, can, action}: `action` is the word on the buy button
	## ("" = nothing to do here), `can` says whether pressing it does anything.
	match it.kind:
		"tool":
			return _describe_tool(int(it.id))
		"upgrade":
			return _describe_upgrade(str(it.id))
		"helper":
			return _describe_helper(int(it.id))
		"find":
			return _describe_find(int(it.id))
		"catalogue":
			return {"title": "📖 The Catalogue", "body": "Mail-order extras: the 2x heat boost, no ads, the golden hair dryer.",
				"price": "", "can": true, "action": "OPEN"}
	return {}


func _describe_tool(i: int) -> Dictionary:
	var t: Dictionary = Balance.TOOLS[i]
	var stats := "Power %s · heat zone %.1f m · reach %s m" % [Fmt.num(t.power), t.radius, Fmt.num(t.range)]
	var d := {"title": "%s %s" % [t.icon, t.name], "body": "%s\n%s" % [t.desc, stats], "price": "", "can": false, "action": ""}
	if i < GameState.tool_index:
		d.price = "✔ Owned"
		d.action = "OWNED"
	elif i == GameState.tool_index:
		d.price = "In your hands"
		d.action = "IN USE"
	elif i == GameState.next_tool_index():
		var cost: float = t.cost
		d.price = "💧 " + Fmt.num(cost)
		d.can = GameState.water >= cost
		d.action = "BUY"
	else:
		d.price = "🔒 💧 " + Fmt.num(t.cost)
		d.body = "%s\nBuy the %s first." % [t.desc, Balance.TOOLS[i - 1].name]
		d.action = "LOCKED"
	return d


func _describe_upgrade(key: String) -> Dictionary:
	var u := GameState.upgrade_def(key)
	var lvl := int(GameState.upgrade_levels.get(key, 0))
	var d := {"title": "%s %s · Lv %d/%d" % [u.icon, u.name, lvl, int(u.max)],
		"body": "%s per level.\nRight now: x%.2f" % [u.desc, GameState.upgrade_mult(key)],
		"price": "", "can": false, "action": ""}
	if GameState.upgrade_maxed(key):
		d.price = "MAX"
		d.action = "MAXED"
	else:
		var cost := GameState.upgrade_cost(key)
		d.price = "💧 " + Fmt.num(cost)
		d.can = GameState.water >= cost
		d.action = "BUY"
	return d


func _describe_helper(i: int) -> Dictionary:
	var h: Dictionary = Balance.HELPERS[i]
	var n := int(GameState.helper_counts[i])
	var cost := GameState.helper_cost(i)
	var each := GameState.helper_each(i) / maxf(GameState.debug_speed, 0.001)
	return {"title": "%s %s" % [h.icon, h.name],
		"body": "%s\nMelts %s hp/s. You have %d." % [h.desc, Fmt.num(each), n],
		"price": "💧 " + Fmt.num(cost), "can": GameState.water >= cost, "action": "HIRE"}


func _glacier_slot_found(slot: int) -> bool:
	var g := int(GLACIER_SLOTS[slot].glacier)
	return GameState.has_won or GameState.stage > g


func _describe_find(d: int) -> Dictionary:
	if d >= Balance.DISCOVERIES.size():
		var gs: Dictionary = GLACIER_SLOTS[d - Balance.DISCOVERIES.size()]
		if _glacier_slot_found(d - Balance.DISCOVERIES.size()):
			return {"title": "%s %s" % [gs.icon, gs.title], "body": gs.body, "price": "", "can": false, "action": ""}
		return {"title": "🧊 ???", "body": gs.hint, "price": "", "can": false, "action": ""}
	var info: Dictionary = Balance.DISCOVERIES[d]
	if GameState.discovered[d]:
		return {"title": "%s %s" % [info.icon, info.name],
			"body": "%s\nSold for 💧 %s" % [info.flavor, Fmt.num(float(info.value) * GameState.sell_mult())],
			"price": "", "can": false, "action": ""}
	var layer_set: Array = Balance.LAYER_SETS[GameState.grids[int(info.glacier)].spec.layers] if not GameState.grids.is_empty() else Balance.LAYER_SETS.valley
	var where := "Somewhere in the %s" % layer_set[int(info.layer)].name
	if int(info.glacier) > GameState.stage:
		where += " of the frozen lake"
	return {"title": "🧊 Still frozen", "body": where + ".", "price": "", "can": false, "action": ""}


func use(it: Dictionary) -> Dictionary:
	## Buy, hire or open what's being looked at. {ok, text, open_catalogue}
	var r := {"ok": false, "text": "", "open_catalogue": false}
	if it.is_empty():
		return r
	var d := describe(it)
	match it.kind:
		"catalogue":
			r.ok = true
			r.open_catalogue = true
			return r
		"tool":
			var i := int(it.id)
			var t: Dictionary = Balance.TOOLS[i]
			if d.action == "BUY" and GameState.buy_tool(i):
				r.ok = true
				r.text = "%s %s is yours! Go try it on the ice" % [t.icon, t.name]
			elif d.action == "LOCKED":
				r.text = "🔒 Buy the %s first" % Balance.TOOLS[i - 1].name
			elif d.action == "BUY":
				r.text = "Not enough 💧: %s more to go" % Fmt.num(float(t.cost) - GameState.water)
			else:
				r.text = "%s Already yours" % t.icon
		"upgrade":
			var key := str(it.id)
			var u := GameState.upgrade_def(key)
			if GameState.upgrade_maxed(key):
				r.text = "%s %s is maxed out" % [u.icon, u.name]
			elif GameState.buy_upgrade(key):
				r.ok = true
				r.text = "%s %s: level %d!" % [u.icon, u.name, int(GameState.upgrade_levels[key])]
			else:
				r.text = "Not enough 💧: %s more to go" % Fmt.num(GameState.upgrade_cost(key) - GameState.water)
		"helper":
			var i := int(it.id)
			var h: Dictionary = Balance.HELPERS[i]
			if GameState.buy_helper(i):
				r.ok = true
				r.text = "%s %s hired!%s" % [h.icon, h.name, "" if i == 2 else " Look for it on the ice"]
			else:
				r.text = "Not enough 💧: %s more to go" % Fmt.num(GameState.helper_cost(i) - GameState.water)
	if r.ok:
		_bounce(it)
		refresh()
	elif d.action != "":
		_shake(it)
	return r


# =====================================================================================
# Every frame: signs, the highlighted item, the figures
# =====================================================================================
func update(delta: float, aimed: Dictionary) -> void:
	_t += delta
	_refresh_t += delta
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		refresh()
	var want: int = int(aimed.get("index", -1))
	if want != _hilite:
		if _hilite >= 0:
			_set_hilite(items[_hilite], false)
		_hilite = want
		if _hilite >= 0:
			_set_hilite(items[_hilite], true)
	if _hilite >= 0:
		var it: Dictionary = items[_hilite]
		var node: Node3D = it.node
		if node != null:
			node.rotation = it.base_rot + Vector3(0.0, sin(_t * 7.0) * 0.09, 0.0)
	for f in _figures:
		_idle(f[0], int(f[1]))


func _set_hilite(it: Dictionary, on: bool) -> void:
	var node: Node3D = it.node
	if node != null and not on:
		node.rotation = it.base_rot
	var l: Label3D = it.label
	if l != null:
		l.modulate = HILITE if on else INK


func _bounce(it: Dictionary) -> void:
	var node: Node3D = it.node
	if node == null:
		return
	var base: Vector3 = it.base_scale
	node.scale = base * 1.3
	node.create_tween().tween_property(node, "scale", base, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(it: Dictionary) -> void:
	var node: Node3D = it.node
	if node == null:
		return
	var base: Vector3 = it.base_pos
	var side := Vector3(0.035, 0, 0) if it.kind != "helper" and it.kind != "find" else Vector3(0, 0, 0.035)
	var tw := node.create_tween()
	for k in 4:
		tw.tween_property(node, "position", base + side * (1.0 if k % 2 == 0 else -1.0), 0.04)
	tw.tween_property(node, "position", base, 0.04)


func _idle(node: Node3D, type: int) -> void:
	match type:
		0:   # the penguin sways and waves now and then
			var body: Node3D = node.get_node("Body")
			body.rotation.z = sin(_t * 2.3) * 0.05
			var wave := maxf(0.0, sin(_t * 0.9)) ** 8
			(body.get_node("FlipperL") as Node3D).rotation.z = -0.25
			(body.get_node("FlipperR") as Node3D).rotation.z = 0.25 + wave * 1.5 * (0.6 + 0.4 * sin(_t * 18.0))
		1:   # the sauna crew breathes in the steam
			var body: Node3D = node.get_node("Body")
			body.rotation.x = sin(_t * 1.4) * 0.03
		2:   # Kevin's eyes follow you round the room
			if player == null:
				return
			for eye_name in ["EyeL", "EyeR"]:
				var eye: Node3D = node.get_node(eye_name)
				var pupil: Node3D = eye.get_node("Pupil")
				var to: Vector3 = player.global_position + Vector3(0, 1.5, 0) - eye.global_position
				var dir := eye.global_transform.basis.inverse() * to
				pupil.position = pupil.position.lerp(dir.normalized() * 0.85, 0.15)


func refresh() -> void:
	## Prices, levels, what's on the wall, what's been found.
	for it in items:
		var price: Label3D = it.price
		match it.kind:
			"tool":
				var i := int(it.id)
				var t: Dictionary = Balance.TOOLS[i]
				var node: Node3D = it.node
				node.visible = i != GameState.tool_index
				if i == 0 and GameState.golden_equipped != _shown_gold:
					_shown_gold = GameState.golden_equipped
					(node as MeshInstance3D).mesh = Props.tool_mesh(0, _shown_gold)
				if i < GameState.tool_index:
					_set_text(price, "✔ Owned", GREEN_INK)
				elif i == GameState.tool_index:
					_set_text(price, "✋ In your hands", GREEN_INK)
				elif i == GameState.next_tool_index():
					_set_text(price, "💧 " + Fmt.num(t.cost), INK)
				else:
					_set_text(price, "🔒 💧 " + Fmt.num(t.cost), GREY_INK)
			"upgrade":
				var key := str(it.id)
				var lvl := int(GameState.upgrade_levels.get(key, 0))
				if GameState.upgrade_maxed(key):
					_set_text(price, "Lv %d · MAX" % lvl, GREEN_INK)
				else:
					_set_text(price, "Lv %d · 💧 %s" % [lvl, Fmt.num(GameState.upgrade_cost(key))], INK)
			"helper":
				var i := int(it.id)
				var n := int(GameState.helper_counts[i])
				var cost := "💧 " + Fmt.num(GameState.helper_cost(i))
				_set_text(price, cost if n == 0 else "%d hired · %s" % [n, cost], INK)
			"find":
				var d := int(it.id)
				var nd := Balance.DISCOVERIES.size()
				var found: bool = _glacier_slot_found(d - nd) if d >= nd else GameState.discovered[d]
				(it.node as Node3D).visible = found
				(_ice_cubes[d] as Node3D).visible = not found


func _set_text(l: Label3D, text: String, color: Color) -> void:
	if l.text != text:
		l.text = text
	l.modulate = color


# =====================================================================================
# Building it: helpers
# =====================================================================================
func _k(c: Color, kind: float) -> Color:
	return Color(c.r, c.g, c.b, kind)


func _box(lo: Vector3, hi: Vector3, c: Color, kind: float, solid: bool = false) -> void:
	MeshKit.box(_st, (lo + hi) * 0.5, hi - lo, _k(c, kind))
	if solid:
		_solid(lo, hi)


func _rbox(center: Vector3, size: Vector3, basis: Basis, c: Color, kind: float) -> void:
	MeshKit.box(_st, center, size, _k(c, kind), basis)


func _solid(lo: Vector3, hi: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = hi - lo
	cs.shape = bs
	cs.position = (lo + hi) * 0.5
	_body.add_child(cs)


func _text(t: String, pos: Vector3, rot_y: float, font_size: int, pixel: float, color: Color = INK) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.position = pos
	l.rotation.y = rot_y
	add_child(l)
	return l


func _board(center: Vector3, w: float, h: float, rot_y: float, c: Color = PAPER) -> void:
	## A sign board on a wall, its face toward rot_y's +Z.
	var b := Basis(Vector3.UP, rot_y)
	_rbox(center, Vector3(w, h, 0.02), b, c, PAINT)
	_rbox(center - b.z * 0.012, Vector3(w + 0.05, h + 0.05, 0.015), b, BEAM, PAINT)


func _place(node: Node3D, mesh: Mesh, at: Vector3, rot_y: float, s: float, center_y: bool) -> void:
	## Puts a prop with its middle over `at` (and its bottom on it unless center_y).
	node.rotation.y = rot_y
	node.scale = Vector3.ONE * s
	var box := mesh.get_aabb()
	var c := Basis(Vector3.UP, rot_y) * (box.get_center() * s)
	var off := Vector3(-c.x, -c.y if center_y else -box.position.y * s, -c.z)
	node.position = at + off


func _set_layers(n: Node, layers: int) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = layers
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_layers(c, layers)


func _add_item(kind: String, id: Variant, node: Node3D, hit_lo: Vector3, hit_hi: Vector3,
		label: Label3D, price: Label3D) -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = SHOP_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = hit_hi - hit_lo
	cs.shape = bs
	body.add_child(cs)
	body.position = (hit_lo + hit_hi) * 0.5
	body.set_meta("item", items.size())
	add_child(body)
	var it := {"kind": kind, "id": id, "index": items.size(), "node": node, "label": label, "price": price, "body": body,
		"base_rot": node.rotation if node != null else Vector3.ZERO,
		"base_pos": node.position if node != null else Vector3.ZERO,
		"base_scale": node.scale if node != null else Vector3.ONE}
	items.append(it)
	return it


# =====================================================================================
# The building
# =====================================================================================
func _wall_x(x_out: float, x_in: float, z0: float, z1: float, y0: float, y1: float) -> void:
	## A piece of a wall across x (the gable ends): red boards outside, pine inside.
	var mid := (x_out + x_in) * 0.5
	_box(Vector3(minf(x_out, mid), y0, z0), Vector3(maxf(x_out, mid), y1, z1), RED_PAINT, BOARDS)
	_box(Vector3(minf(x_in, mid), y0, z0), Vector3(maxf(x_in, mid), y1, z1), PINE, BOARDS)
	_solid(Vector3(minf(x_out, x_in), y0, z0), Vector3(maxf(x_out, x_in), y1, z1))


func _wall_z(z_out: float, z_in: float, x0: float, x1: float, y0: float, y1: float) -> void:
	## A piece of a long wall (north and south).
	var mid := (z_out + z_in) * 0.5
	_box(Vector3(x0, y0, minf(z_out, mid)), Vector3(x1, y1, maxf(z_out, mid)), RED_PAINT, BOARDS)
	_box(Vector3(x0, y0, minf(z_in, mid)), Vector3(x1, y1, maxf(z_in, mid)), PINE, BOARDS)
	_solid(Vector3(x0, y0, minf(z_out, z_in)), Vector3(x1, y1, maxf(z_out, z_in)))


func _build_walls() -> void:
	var xo0 := X0 - WALL
	var xo1 := X1 + WALL
	var zo0 := Z0 - WALL
	var zo1 := Z1 + WALL
	# North wall (the tool wall inside): whole.
	_wall_z(zo0, Z0, xo0, xo1, 0.0, H)
	# South wall, with two windows up high.
	_wall_z(zo1, Z1, xo0, xo1, 0.0, WIN_Y0)
	_wall_z(zo1, Z1, xo0, xo1, WIN_Y1, H)
	var x := xo0
	for w in WINDOWS:
		_wall_z(zo1, Z1, x, w[0], WIN_Y0, WIN_Y1)
		x = w[1]
	_wall_z(zo1, Z1, x, xo1, WIN_Y0, WIN_Y1)
	# West wall with the door, and the east wall.
	_wall_x(xo0, X0, Z0, DOOR_Z0, 0.0, H)
	_wall_x(xo0, X0, DOOR_Z1, Z1, 0.0, H)
	_wall_x(xo0, X0, DOOR_Z0, DOOR_Z1, DOOR_H, H)
	_wall_x(xo1, X1, Z0, Z1, 0.0, H)
	# The gables: triangles from the wall tops up to the ridge.
	var zc := (Z0 + Z1) * 0.5
	for g in [[xo0, -1.0, RED_PAINT], [X0, 1.0, PINE], [xo1, 1.0, RED_PAINT], [X1, -1.0, PINE]]:
		var gx: float = g[0]
		MeshKit.triangle(_st, Vector3(gx, H, zo0), Vector3(gx, H, zo1), Vector3(gx, H + RISE, zc),
				Vector3(g[1], 0, 0), _k(g[2], BOARDS))
	# White corner boards and a stone footing.
	for cx in [xo0, xo1]:
		for cz in [zo0, zo1]:
			_box(Vector3(cx - 0.08, 0.0, cz - 0.08), Vector3(cx + 0.08, H, cz + 0.08), TRIM, PAINT)
	var s := 0.06
	var sy := 0.32
	_box(Vector3(xo0 - s, 0, zo0 - s), Vector3(xo1 + s, sy, zo0), STONE, PAINT)
	_box(Vector3(xo0 - s, 0, zo1), Vector3(xo1 + s, sy, zo1 + s), STONE, PAINT)
	_box(Vector3(xo1, 0, zo0), Vector3(xo1 + s, sy, zo1), STONE, PAINT)
	_box(Vector3(xo0 - s, 0, zo0), Vector3(xo0, sy, DOOR_Z0 - 0.16), STONE, PAINT)
	_box(Vector3(xo0 - s, 0, DOOR_Z1 + 0.16), Vector3(xo0, sy, zo1), STONE, PAINT)
	# Window frames: trim outside and in, a sill, and a cross in the middle.
	for w in WINDOWS:
		var a: float = w[0]
		var b: float = w[1]
		for side in [[zo1, zo1 + 0.04], [Z1 - 0.04, Z1]]:
			_box(Vector3(a - 0.09, WIN_Y1, side[0]), Vector3(b + 0.09, WIN_Y1 + 0.1, side[1]), TRIM, PAINT)
			_box(Vector3(a - 0.09, WIN_Y0 - 0.08, side[0]), Vector3(a, WIN_Y1, side[1]), TRIM, PAINT)
			_box(Vector3(b, WIN_Y0 - 0.08, side[0]), Vector3(b + 0.09, WIN_Y1, side[1]), TRIM, PAINT)
		_box(Vector3(a - 0.12, WIN_Y0 - 0.08, Z1 - 0.06), Vector3(b + 0.12, WIN_Y0, zo1 + 0.1), TRIM, PAINT)
		_box(Vector3(a, WIN_Y1 - 0.02, Z1), Vector3(b, WIN_Y1, zo1), TRIM, PAINT)
		_box(Vector3(a, WIN_Y0, Z1), Vector3(a + 0.02, WIN_Y1, zo1), TRIM, PAINT)
		_box(Vector3(b - 0.02, WIN_Y0, Z1), Vector3(b, WIN_Y1, zo1), TRIM, PAINT)
		var m := (a + b) * 0.5
		_box(Vector3(m - 0.025, WIN_Y0, Z1 + 0.08), Vector3(m + 0.025, WIN_Y1, Z1 + 0.12), TRIM, PAINT)
		_box(Vector3(a, (WIN_Y0 + WIN_Y1) * 0.5 - 0.025, Z1 + 0.08), Vector3(b, (WIN_Y0 + WIN_Y1) * 0.5 + 0.025, Z1 + 0.12), TRIM, PAINT)


func _build_roof() -> void:
	var zc := (Z0 + Z1) * 0.5
	var half := (Z1 - Z0) * 0.5 + WALL
	var slope := RISE / half
	var xa := X0 - WALL - GABLE
	var xb := X1 + WALL + GABLE
	var xm := (xa + xb) * 0.5
	var xl := xb - xa
	var ridge := Vector3(xm, H + RISE, zc)
	for side in [-1.0, 1.0]:
		var eave := Vector3(xm, H - EAVE * slope, zc + side * (half + EAVE))
		var u := (eave - ridge).normalized()                 # down the slope
		var n := Vector3(0.0, absf(u.z), side * absf(u.y))   # out of the roof, square to the slope
		var basis := Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n))
		var length := ridge.distance_to(eave) + 0.12
		var mid := (ridge + eave) * 0.5 - u * 0.06
		_rbox(mid + n * 0.05, Vector3(xl, 0.1, length), basis, PINE, BOARDS)
		_rbox(mid + n * 0.125 + u * 0.03, Vector3(xl + 0.06, 0.05, length + 0.06), basis, ROOF, SHINGLES)
		# Bargeboards up the gable ends, and a fascia board along the eave.
		for bx in [xa - 0.02, xb + 0.02]:
			_rbox(Vector3(bx, mid.y, mid.z) + n * 0.06, Vector3(0.05, 0.22, length), basis, TRIM, PAINT)
		var e := eave + n * 0.06 + u * 0.03
		_box(Vector3(xa - 0.05, e.y - 0.12, e.z - 0.025), Vector3(xb + 0.05, e.y + 0.1, e.z + 0.025), TRIM, PAINT)
	_box(Vector3(xa - 0.04, H + RISE + 0.08, zc - 0.13), Vector3(xb + 0.04, H + RISE + 0.22, zc + 0.13), ROOF.darkened(0.25), PAINT)
	# Collision: one prism over the whole roof, down to the eaves. It also
	# makes the ceiling inside, just above where you can jump.
	var bottom := H - EAVE * slope
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for px in [xa, xb]:
		for pz in [zc - half - EAVE, zc + half + EAVE]:
			pts.append(Vector3(px, bottom, pz))
			pts.append(Vector3(px, bottom + 0.18, pz))
		pts.append(Vector3(px, H + RISE + 0.2, zc))
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	_body.add_child(cs)


func _build_door() -> void:
	var xo := X0 - WALL
	# Frame: trim around the opening, outside and in, and the jambs.
	for f in [[xo - 0.04, xo], [X0, X0 + 0.04]]:
		_box(Vector3(f[0], 0.0, DOOR_Z0 - 0.13), Vector3(f[1], DOOR_H + 0.13, DOOR_Z0), TRIM, PAINT)
		_box(Vector3(f[0], 0.0, DOOR_Z1), Vector3(f[1], DOOR_H + 0.13, DOOR_Z1 + 0.13), TRIM, PAINT)
		_box(Vector3(f[0], DOOR_H, DOOR_Z0), Vector3(f[1], DOOR_H + 0.13, DOOR_Z1), TRIM, PAINT)
	_box(Vector3(xo, 0.0, DOOR_Z0), Vector3(X0, DOOR_H, DOOR_Z0 + 0.025), TRIM, PAINT)
	_box(Vector3(xo, 0.0, DOOR_Z1 - 0.025), Vector3(X0, DOOR_H, DOOR_Z1), TRIM, PAINT)
	_box(Vector3(xo, DOOR_H - 0.025, DOOR_Z0), Vector3(X0, DOOR_H, DOOR_Z1), TRIM, PAINT)
	_box(Vector3(xo - 0.05, 0.0, DOOR_Z0), Vector3(X0, 0.035, DOOR_Z1), BEAM, BOARDS)
	# Two barn doors swung open flat against the wall, with white Z braces.
	var leaf := 0.75
	for side in [-1.0, 1.0]:
		var z0: float = DOOR_Z0 - 0.15 - leaf if side < 0.0 else DOOR_Z1 + 0.15
		var z1 := z0 + leaf
		var x0 := xo - 0.1
		var x1 := xo - 0.05
		_box(Vector3(x0, 0.03, z0), Vector3(x1, DOOR_H - 0.03, z1), RED_PAINT.darkened(0.05), BOARDS, true)
		var fx0 := x0 - 0.02
		_box(Vector3(fx0, 0.03, z0), Vector3(x0, 0.15, z1), TRIM, PAINT)
		_box(Vector3(fx0, DOOR_H - 0.15, z0), Vector3(x0, DOOR_H - 0.03, z1), TRIM, PAINT)
		_box(Vector3(fx0, 0.03, z0), Vector3(x0, DOOR_H - 0.03, z0 + 0.1), TRIM, PAINT)
		_box(Vector3(fx0, 0.03, z1 - 0.1), Vector3(x0, DOOR_H - 0.03, z1), TRIM, PAINT)
		var dz := leaf - 0.2
		var dy := DOOR_H - 0.36
		var ang: float = atan2(dy, dz) * side
		_rbox(Vector3((fx0 + x0) * 0.5, DOOR_H * 0.5, (z0 + z1) * 0.5), Vector3(0.02, 0.1, sqrt(dz * dz + dy * dy)),
				Basis(Vector3.RIGHT, -ang), TRIM, PAINT)
		for hy in [0.35, DOOR_H - 0.35]:
			var hz: float = z1 - 0.02 if side < 0.0 else z0 + 0.02
			_box(Vector3(x0 - 0.035, hy - 0.03, hz - 0.2), Vector3(x0 - 0.015, hy + 0.03, hz + 0.2), Color(0.15, 0.15, 0.17), PAINT)
	# A doormat, and the sign over the door.
	_box(Vector3(7.65, 0.0, DOOR_Z0 + 0.1), Vector3(xo - 0.12, 0.03, DOOR_Z1 - 0.1), Color(0.66, 0.48, 0.24), PAINT)
	var welcome := _text("WELCOME", Vector3(8.18, 0.033, (DOOR_Z0 + DOOR_Z1) * 0.5), 0.0, 44, 0.0035, Color(0.38, 0.24, 0.1))
	welcome.rotation = Vector3(-PI / 2.0, -PI / 2.0, 0.0)   # lying on the mat, read from outside
	_board(Vector3(xo - 0.07, DOOR_H + 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), 2.1, 0.5, -PI / 2.0)
	_text("TOOL SHED", Vector3(xo - 0.085, DOOR_H + 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5), -PI / 2.0, 80, 0.0042, RED_PAINT.darkened(0.2))


func _build_room() -> void:
	var zc := (Z0 + Z1) * 0.5
	# Floor boards, wall plates, tie beams, king posts and the ridge beam.
	_box(Vector3(X0, -0.03, Z0), Vector3(X1, 0.02, Z1), FLOOR, BOARDS)
	_box(Vector3(X0, H - 0.14, Z0), Vector3(X1, H + 0.06, Z0 + 0.14), BEAM, BOARDS)
	_box(Vector3(X0, H - 0.14, Z1 - 0.14), Vector3(X1, H + 0.06, Z1), BEAM, BOARDS)
	for bx in [LAMPS[0].x, LAMPS[1].x]:
		_box(Vector3(bx - 0.08, H - 0.14, Z0), Vector3(bx + 0.08, H + 0.04, Z1), BEAM, BOARDS)
		_box(Vector3(bx - 0.06, H + 0.04, zc - 0.06), Vector3(bx + 0.06, H + RISE - 0.15, zc + 0.06), BEAM, BOARDS)
	_box(Vector3(X0, H + RISE - 0.32, zc - 0.08), Vector3(X1, H + RISE - 0.1, zc + 0.08), BEAM, BOARDS)
	# A round rag rug.
	var rug := [[Vector3(1.75, 0.006, 1.2), Color(0.7, 0.2, 0.16)], [Vector3(1.5, 0.008, 0.98), PAPER],
		[Vector3(1.2, 0.01, 0.76), Color(0.26, 0.42, 0.62)], [Vector3(0.86, 0.012, 0.52), PAPER],
		[Vector3(0.5, 0.014, 0.28), Color(0.7, 0.2, 0.16)]]
	for r in rug:
		MeshKit.ellipsoid(_st, Vector3(13.0, 0.02, zc), r[0], _k(r[1], PAINT), Basis.IDENTITY, 4, 40)
	# Cords for the lamps.
	for lp in LAMPS:
		MeshKit.cylinder(_st, Vector3(lp.x, H - 0.14, lp.z), Vector3(lp.x, lp.y + 0.24, lp.z), 0.008, 0.008, _k(Color(0.1, 0.1, 0.1), PAINT), 6)


func _build_lamps() -> void:
	var shade := MeshKit.begin()
	for lp in LAMPS:
		var top: Vector3 = lp + Vector3(0, 0.24, 0)
		var rim: Vector3 = lp + Vector3(0, 0.02, 0)
		MeshKit.cylinder(shade, top, rim, 0.06, 0.27, Color(0.16, 0.38, 0.3), 20, false)
		MeshKit.cylinder(shade, top, rim, 0.06, 0.27, Color(0.97, 0.96, 0.9), 20, false, true)
		MeshKit.cylinder(shade, top - Vector3(0, 0.01, 0), top + Vector3(0, 0.05, 0), 0.07, 0.04, Color(0.16, 0.38, 0.3), 12)
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.065
		sm.height = 0.13
		sm.radial_segments = 12
		sm.rings = 6
		bulb.mesh = sm
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.94, 0.78)
		bulb.material_override = glow
		bulb.position = lp + Vector3(0, 0.03, 0)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		var light := OmniLight3D.new()
		light.position = lp - Vector3(0, 0.06, 0)
		light.light_color = Color(1.0, 0.85, 0.64)
		light.light_energy = 1.35
		light.omni_range = 6.0
		light.light_specular = 0.25
		light.shadow_enabled = false
		light.light_cull_mask = 2   # only the shed and what's in it, not the valley outside
		add_child(light)
		_solid(lp - Vector3(0.3, 0.05, 0.3), lp + Vector3(0.3, 0.3, 0.3))
	var mi := Props.instance(MeshKit.finish(shade))
	mi.layers = 3
	add_child(mi)


func _build_marker() -> void:
	marker = Label3D.new()
	marker.text = "🏠 Shed"
	marker.font_size = 96
	marker.pixel_size = 0.0006
	marker.fixed_size = true
	marker.outline_size = 16
	UiTheme.sign_label(marker, Color(1.0, 0.93, 0.72))
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.render_priority = 5
	marker.outline_render_priority = 4
	marker.position = Vector3((X0 + X1) * 0.5, H + RISE + 1.3, (Z0 + Z1) * 0.5)
	add_child(marker)


# =====================================================================================
# The tool wall (north)
# =====================================================================================
func _build_tools() -> void:
	var z := Z0
	var px0: float = SLOTS[0] - 0.55
	var px1: float = SLOTS[SLOTS.size() - 1] + 0.55
	# A pegboard over a tool chest.
	_box(Vector3(px0, 0.85, z), Vector3(px1, 2.75, z + 0.03), Color(0.8, 0.64, 0.44), PEGBOARD)
	_box(Vector3(px0 - 0.06, 0.79, z), Vector3(px1 + 0.06, 0.85, z + 0.06), BEAM, PAINT)
	_box(Vector3(px0 - 0.06, 2.75, z), Vector3(px1 + 0.06, 2.81, z + 0.06), BEAM, PAINT)
	_box(Vector3(px0 - 0.06, 0.85, z), Vector3(px0, 2.75, z + 0.06), BEAM, PAINT)
	_box(Vector3(px1, 0.85, z), Vector3(px1 + 0.06, 2.75, z + 0.06), BEAM, PAINT)
	var chest := Color(0.32, 0.43, 0.55)
	_box(Vector3(px0, 0.0, z), Vector3(px1, 0.76, z + 0.5), chest, PAINT)
	_box(Vector3(px0 - 0.02, 0.76, z), Vector3(px1 + 0.02, 0.8, z + 0.52), BEAM, BOARDS)
	for i in SLOTS.size():
		var sx: float = SLOTS[i]
		for row in 2:
			var y0 := 0.08 + row * 0.34
			_box(Vector3(sx - 0.5, y0, z + 0.5), Vector3(sx + 0.5, y0 + 0.3, z + 0.515), chest.lightened(0.08), PAINT)
			_box(Vector3(sx - 0.12, y0 + 0.12, z + 0.515), Vector3(sx + 0.12, y0 + 0.16, z + 0.54), Color(0.75, 0.75, 0.78), PAINT)
		for hx in [-0.14, 0.14]:
			MeshKit.cylinder(_st, Vector3(sx + hx, 1.8, z + 0.03), Vector3(sx + hx, 1.83, z + 0.2), 0.012, 0.012,
					_k(Color(0.7, 0.7, 0.74), PAINT), 6)
		_board(Vector3(sx, 1.2, z + 0.045), 0.98, 0.42, 0.0)
	_board(Vector3((px0 + px1) * 0.5, 2.55, z + 0.045), 1.3, 0.3, 0.0, RED_PAINT)
	_solid(Vector3(px0 - 0.06, 0.0, z), Vector3(px1 + 0.06, 2.8, z + 0.55))
	_text("TOOLS", Vector3((px0 + px1) * 0.5, 2.55, z + 0.068), 0.0, 72, 0.0034, PAPER)
	for i in Balance.TOOLS.size():
		var sx: float = SLOTS[i]
		var mesh := Props.tool_mesh(i, false)
		var mi := Props.instance(mesh)
		var size := mesh.get_aabb().size
		var s := minf(2.0, 0.95 / maxf(size.z, 0.01))
		_place(mi, mesh, Vector3(sx, 1.98, z + 0.3), -PI / 2.0, s, true)
		mi.layers = 3
		add_child(mi)
		var name_l := _text(Balance.TOOLS[i].name, Vector3(sx, 1.29, z + 0.058), 0.0, 46, 0.0021)
		var price_l := _text("", Vector3(sx, 1.1, z + 0.058), 0.0, 50, 0.0024)
		_add_item("tool", i, mi, Vector3(sx - 0.53, 0.95, z), Vector3(sx + 0.53, 2.5, z + 0.6), name_l, price_l)


# =====================================================================================
# The upgrade bench (south, under the windows)
# =====================================================================================
func _build_bench() -> void:
	var z := Z1
	var bx0: float = SLOTS[0] - 0.55
	var bx1: float = SLOTS[SLOTS.size() - 1] + 0.55
	var top := 0.94
	_box(Vector3(bx0, top - 0.07, z - 0.68), Vector3(bx1, top, z), Color(0.64, 0.46, 0.3), BOARDS)
	_box(Vector3(bx0 + 0.02, top - 0.17, z - 0.66), Vector3(bx1 - 0.02, top - 0.07, z - 0.63), BEAM, BOARDS)
	for lx in [bx0 + 0.06, (bx0 + bx1) * 0.5, bx1 - 0.06]:
		for lz in [z - 0.62, z - 0.08]:
			_box(Vector3(lx - 0.04, 0.0, lz - 0.04), Vector3(lx + 0.04, top - 0.07, lz + 0.04), BEAM, BOARDS)
	_box(Vector3(bx0 + 0.02, 0.2, z - 0.62), Vector3(bx1 - 0.02, 0.24, z - 0.04), Color(0.64, 0.46, 0.3), BOARDS)
	# Paint cans and a bucket on the lower shelf.
	var cans := [[10.3, 0.12, Color(0.85, 0.3, 0.2)], [10.55, 0.1, Color(0.3, 0.55, 0.85)],
		[13.9, 0.14, Color(0.6, 0.6, 0.62)], [15.9, 0.11, Color(0.95, 0.8, 0.25)], [16.15, 0.1, Color(0.35, 0.65, 0.4)]]
	for c in cans:
		MeshKit.cylinder(_st, Vector3(c[0], 0.24, z - 0.33), Vector3(c[0], 0.24 + c[1] * 1.6, z - 0.33), c[1], c[1], _k(c[2], PAINT), 14)
	for i in SLOTS.size():
		_board(Vector3(SLOTS[i], 1.75, z - 0.045), 0.98, 0.42, PI)
	_board(Vector3(13.0, 2.5, z - 0.045), 1.6, 0.3, PI, RED_PAINT)
	_solid(Vector3(bx0, 0.0, z - 0.7), Vector3(bx1, top, z))
	_text("UPGRADES", Vector3(13.0, 2.5, z - 0.068), PI, 72, 0.0034, PAPER)
	for i in Balance.UPGRADES.size():
		var u: Dictionary = Balance.UPGRADES[i]
		var sx: float = SLOTS[i]
		var mesh := Props.upgrade_mesh(u.key)
		var mi := Props.instance(mesh)
		_place(mi, mesh, Vector3(sx, top, z - 0.36), 0.0, 1.3, false)
		mi.layers = 3
		add_child(mi)
		var name_l := _text(UPGRADE_NAMES.get(u.key, u.name), Vector3(sx, 1.84, z - 0.058), PI, 46, 0.0021)
		var price_l := _text("", Vector3(sx, 1.65, z - 0.058), PI, 46, 0.0022)
		_add_item("upgrade", u.key, mi, Vector3(sx - 0.53, top - 0.05, z - 0.72), Vector3(sx + 0.53, 2.0, z), name_l, price_l)


# =====================================================================================
# The hiring corner (east)
# =====================================================================================
func _build_helpers() -> void:
	var x := X1
	_box(Vector3(x - 0.03, 1.4, 8.8), Vector3(x, 2.78, 14.2), Color(0.74, 0.56, 0.36), PAINT)   # a cork board
	_box(Vector3(x - 0.05, 1.34, 8.74), Vector3(x, 1.4, 14.26), BEAM, PAINT)
	_box(Vector3(x - 0.05, 2.78, 8.74), Vector3(x, 2.84, 14.26), BEAM, PAINT)
	_box(Vector3(x - 0.05, 1.4, 8.74), Vector3(x, 2.78, 8.8), BEAM, PAINT)
	_box(Vector3(x - 0.05, 1.4, 14.2), Vector3(x, 2.78, 14.26), BEAM, PAINT)
	_board(Vector3(x - 0.045, 2.55, 11.5), 1.9, 0.3, -PI / 2.0, RED_PAINT)
	var crate := Color(0.68, 0.52, 0.33)
	for k in HELPER_Z.size():
		var cz: float = HELPER_Z[k]
		var h := 0.34 if k < 2 else 0.6
		_box(Vector3(x - 0.86, 0.0, cz - 0.4), Vector3(x - 0.06, h, cz + 0.4), crate, BOARDS)
		_box(Vector3(x - 0.87, h - 0.06, cz - 0.41), Vector3(x - 0.05, h, cz + 0.41), crate.darkened(0.2), PAINT)
		_box(Vector3(x - 0.87, 0.0, cz - 0.41), Vector3(x - 0.05, 0.06, cz + 0.41), crate.darkened(0.2), PAINT)
		# A note pinned up for each job.
		var tilt := Basis(Vector3.UP, -PI / 2.0) * Basis(Vector3.BACK, 0.04 * (k - 1))
		_rbox(Vector3(x - 0.04, 2.0, cz), Vector3(0.92, 0.46, 0.01), tilt, Color(0.99, 0.98, 0.94), PAINT)
		MeshKit.ellipsoid(_st, Vector3(x - 0.05, 2.19, cz), Vector3(0.025, 0.025, 0.025), _k(Color(0.85, 0.15, 0.12), PAINT))
	_solid(Vector3(x - 0.9, 0.0, 8.7), Vector3(x, 1.7, 14.3))
	_text("HELP WANTED", Vector3(x - 0.068, 2.55, 11.5), -PI / 2.0, 66, 0.0032, PAPER)
	for k in Balance.HELPERS.size():
		var cz: float = HELPER_Z[k]
		var fig: Node3D
		var top := 0.34
		if k == 0:
			fig = Creatures.penguin(0)
			fig.rotation.y = PI / 2.0
		elif k == 1:
			fig = Creatures.sauna(1)
			fig.rotation.y = PI / 2.0
		else:
			top = 0.6
			fig = Creatures.volcano()
			fig.scale = Vector3.ONE * 0.034
			fig.rotation.y = -PI / 2.0
			(fig.get_node("Body") as MeshInstance3D).material_override = Scenery.rock_material(0.0)
		fig.position = Vector3(x - 0.46, top, cz)
		_set_layers(fig, 3)
		add_child(fig)
		_figures.append([fig, k])
		var name_l := _text(HELPER_NAMES[k], Vector3(x - 0.052, 2.08, cz), -PI / 2.0, 44, 0.002)
		var price_l := _text("", Vector3(x - 0.052, 1.9, cz), -PI / 2.0, 44, 0.0021)
		_add_item("helper", k, fig, Vector3(x - 0.95, 0.0, cz - 0.85), Vector3(x, 2.3, cz + 0.85), name_l, price_l)


# =====================================================================================
# The finds shelf (west wall, by the door) and the catalogue table
# =====================================================================================
func _build_finds() -> void:
	var x := X0
	var d := 0.42
	var za := 8.25
	var zb := 10.55
	_box(Vector3(x, 0.0, za), Vector3(x + d, 2.25, za + 0.04), TEAL, PAINT)
	_box(Vector3(x, 0.0, zb - 0.04), Vector3(x + d, 2.25, zb), TEAL, PAINT)
	_box(Vector3(x, 2.21, za), Vector3(x + d, 2.25, zb), TEAL, PAINT)
	_box(Vector3(x, 0.0, za), Vector3(x + d, 0.08, zb), TEAL.darkened(0.2), PAINT)
	for y in FIND_ROWS:
		if y > 0.1:
			_box(Vector3(x, y - 0.03, za + 0.04), Vector3(x + d, y, zb - 0.04), TEAL.lightened(0.1), PAINT)
	_board(Vector3(x + 0.045, 2.52, (za + zb) * 0.5), 2.1, 0.3, PI / 2.0, RED_PAINT)
	_solid(Vector3(x, 0.0, za), Vector3(x + d, 2.25, zb))
	_text("FOUND IN THE ICE", Vector3(x + 0.068, 2.52, (za + zb) * 0.5), PI / 2.0, 56, 0.0031, PAPER)
	# One slot per find, then one for each glacier itself (the village, the lake).
	var n := Balance.DISCOVERIES.size() + GLACIER_SLOTS.size()
	for slot in mini(n, FIND_ROWS.size() * FIND_Z.size()):
		var y: float = FIND_ROWS[FIND_ROWS.size() - 1 - slot / FIND_Z.size()]
		var z: float = FIND_Z[slot % FIND_Z.size()]
		# The find's model (World.find_mesh), small, facing into the room.
		var l := Models.fitted(World.find_mesh(slot), 0.3, -0.15)   # origin mid-height, like the ice cube
		l.position = Vector3(x + 0.22, y + 0.155, z)
		l.rotation.y = -PI / 2.0 + 0.25 * float((slot * 3) % 3 - 1)
		_set_layers(l, 3)
		add_child(l)
		# Still frozen: a see-through block of ice with a question mark inside.
		var cmi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.28, 0.28, 0.28)
		cmi.mesh = bm
		cmi.material_override = _ice_material()
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cmi.position = Vector3(x + 0.22, y + 0.16, z)
		cmi.rotation.y = 0.15 * float((slot * 7) % 5 - 2)
		cmi.layers = 3
		add_child(cmi)
		var q := Label3D.new()
		q.text = "?"
		q.font_size = 96
		q.pixel_size = 0.0018
		q.modulate = Color(0.16, 0.36, 0.62)
		q.outline_size = 0
		q.alpha_cut = Label3D.ALPHA_CUT_DISCARD   # drawn with the solid things, so the ice goes over it
		q.rotation.y = PI / 2.0 - cmi.rotation.y
		cmi.add_child(q)
		_ice_cubes[slot] = cmi
		_add_item("find", slot, l, Vector3(x, y, z - 0.27), Vector3(x + d + 0.05, y + 0.4, z + 0.27), null, null)


var _ice_mat: StandardMaterial3D


func _ice_material() -> StandardMaterial3D:
	if _ice_mat == null:
		_ice_mat = StandardMaterial3D.new()
		_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_mat.albedo_color = Color(0.6, 0.84, 1.0, 0.7)
		_ice_mat.roughness = 0.12
		_ice_mat.rim_enabled = true
		_ice_mat.rim = 0.6
		_ice_mat.rim_tint = 0.2
	return _ice_mat


func _build_catalogue() -> void:
	var x := X0
	var z0 := 12.8
	var z1 := 14.0
	var zc := (z0 + z1) * 0.5
	_box(Vector3(x + 0.08, 0.76, z0), Vector3(x + 0.82, 0.8, z1), TEAL, PAINT)
	_box(Vector3(x + 0.1, 0.62, z0 + 0.04), Vector3(x + 0.8, 0.76, z0 + 0.07), TEAL.darkened(0.15), PAINT)
	_box(Vector3(x + 0.1, 0.62, z1 - 0.07), Vector3(x + 0.8, 0.76, z1 - 0.04), TEAL.darkened(0.15), PAINT)
	for lx in [x + 0.14, x + 0.76]:
		for lz in [z0 + 0.06, z1 - 0.06]:
			_box(Vector3(lx - 0.035, 0.0, lz - 0.035), Vector3(lx + 0.035, 0.76, lz + 0.035), TEAL.darkened(0.15), PAINT)
	_board(Vector3(x + 0.045, 1.5, zc), 1.1, 0.42, PI / 2.0)
	_solid(Vector3(x, 0.0, z0), Vector3(x + 0.85, 0.8, z1))
	var book := Props.instance(Props.book_mesh())
	book.position = Vector3(x + 0.45, 0.8, zc)
	book.rotation.y = -PI / 2.0
	book.layers = 3
	add_child(book)
	var name_l := _text("CATALOGUE", Vector3(x + 0.058, 1.57, zc), PI / 2.0, 50, 0.0024)
	_text("boosts & extras", Vector3(x + 0.058, 1.4, zc), PI / 2.0, 40, 0.0021, GREY_INK)
	_add_item("catalogue", 0, book, Vector3(x, 0.6, z0 - 0.1), Vector3(x + 0.9, 1.8, z1 + 0.1), name_l, null)
