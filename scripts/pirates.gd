class_name PirateFleet
extends Node3D
## The goblin pirate fleet frozen into the lake (models/pirates.glb, made by
## art/blender/build_pirates.py). Where the ships are is level data: a glacier's
## "ships" list (see Levels).
##
## Each hull is hollowed out of the ice like the village houses, so you break
## into it as you melt down, and the masts poke out of the top as a hint from
## the start. A ship wakes up when the ice round its hull is (nearly) gone:
## the frozen crew thaws, cheers, and pays you a bounty. When the lake itself
## thaws at the very end, the ships float and rock on the water.

signal ship_spotted(ship_name: String)
signal ship_freed(ship_name: String, bounty: float)

# The shape of each hull, in the ship's own space (bow to -Z, y = 0 at the
# waterline): length, beam, deck height, the aft castle's height and where it
# starts (z), the masts (z), and the crew: [mesh, position, turn].
const HULLS := {
	"Galleon": {
		"length": 17.0, "beam": 5.4, "deck": 2.0, "aft": 1.6, "aft_z": 4.1, "bowsprit": 11.1,
		"masts": [-4.6, 0.2, 4.6],
		"crew": [
			["GoblinCaptain", Vector3(0.0, 3.6, 6.4), 0.0],
			["GoblinLookout", Vector3(0.2, 2.9, -7.2), 0.3],
			["GoblinDeckhand", Vector3(-1.3, 2.0, -2.4), 0.7],
			["GoblinDeckhand", Vector3(1.4, 2.0, 2.3), -2.3],
			["GoblinLookout", Vector3(-1.5, 2.0, 2.6), 1.9],
		],
	},
	"Sloop": {
		"length": 10.5, "beam": 3.6, "deck": 1.4, "aft": 0.9, "aft_z": 2.6, "bowsprit": 7.9,
		"masts": [-0.8],
		"crew": [
			["GoblinCaptain", Vector3(0.0, 2.3, 3.9), 0.0],
			["GoblinDeckhand", Vector3(0.6, 1.4, -2.6), -0.4],
			["GoblinLookout", Vector3(-0.5, 1.4, 0.7), 0.5],
		],
	},
}
const HEADROOM := 2.4          # air left above the top deck inside the ice
const SPOT_FRACTION := 0.8     # this much of the ice round a ship left: "there's a ship in here!"
const FREE_FRACTION := 0.1     # this little left: the ship is free
const ICE_TINT := Color(0.62, 0.8, 1.0)   # the crew, frozen

var ships: Array = []          # {def, glacier, node, crew: [Node3D], region: AABB, fresh: int, spotted, freed}
var carves := {}               # glacier index -> [AABB] to hollow out of its ice
var solids: Array[AABB] = []   # hulls and masts you can't walk through

var _frozen_mat: StandardMaterial3D
var _check_timer := 0.0
var _check_i := 0
var _time := 0.0


func build(level: Dictionary) -> void:
	## Places every glacier's ships and works out the boxes to carve and collide with.
	_frozen_mat = MeshKit.material().duplicate()
	_frozen_mat.albedo_color = ICE_TINT
	for g in level.glaciers.size():
		for def in level.glaciers[g].get("ships", []):
			_add_ship(def, g)


func _add_ship(def: Dictionary, g: int) -> void:
	var hull: Dictionary = HULLS[def.mesh]
	var node := Node3D.new()
	node.name = str(def.name)
	node.position = def.pos
	node.rotation.y = float(def.yaw)
	add_child(node)
	node.add_child(Models.baked_instance(Models.baked("pirates", def.mesh)))
	var crew: Array = []
	for c in hull.crew:
		var holder := Node3D.new()
		holder.position = c[1]
		holder.rotation.y = c[2]
		node.add_child(holder)
		var mi := Models.baked_instance(Models.baked("pirates", c[0]))
		mi.material_override = _frozen_mat
		holder.add_child(mi)
		crew.append(holder)
	var xf := node.transform
	var half_l: float = hull.length * 0.5
	var half_b: float = hull.beam * 0.5
	var deck: float = hull.deck
	var top: float = deck + float(hull.aft) + HEADROOM
	# The hollow: the whole ship from the lake's surface up to above the top deck.
	var hollow := _world_box(xf, Vector3(-half_b - 0.2, 0.0, -float(hull.bowsprit)),
			Vector3(half_b + 0.2, top, half_l + 0.3))
	if not carves.has(g):
		carves[g] = []
	carves[g].append(hollow)
	solids.append(_world_box(xf, Vector3(-half_b * 0.85, 0.0, -half_l + 1.2), Vector3(half_b * 0.85, deck, half_l)))
	solids.append(_world_box(xf, Vector3(-half_b * 0.8, deck, float(hull.aft_z)),
			Vector3(half_b * 0.8, deck + float(hull.aft), half_l)))
	for z in hull.masts:
		solids.append(_world_box(xf, Vector3(-0.3, deck, float(z) - 0.3), Vector3(0.3, deck + 8.0, float(z) + 0.3)))
	# The ice that has to go before the ship counts as free: the hollow and a
	# couple of metres round it, up to a metre above it.
	var region := hollow.grow(2.0)
	region.position.y = 0.0
	region.size.y = top + 1.0
	ships.append({"def": def, "glacier": g, "node": node, "crew": crew, "region": region, "fresh": 0,
		"spotted": false, "freed": false})


static func _world_box(xf: Transform3D, lo: Vector3, hi: Vector3) -> AABB:
	var box := AABB(xf * lo, Vector3.ZERO)
	for c in [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z),
			Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, lo.z), hi]:
		box = box.expand(xf * c)
	return box


func measure(glaciers: Array) -> void:
	## Counts the ice round each ship on the fresh glaciers (before a save is
	## loaded), to compare against later.
	for s in ships:
		s.fresh = maxi(_ice_round(s, glaciers[s.glacier]), 1)


func settle(glaciers: Array) -> void:
	## After loading a save: ships that were already freed wake up quietly.
	for s in ships:
		var left: float = float(_ice_round(s, glaciers[s.glacier])) / float(s.fresh)
		if left <= SPOT_FRACTION:
			s.spotted = true
		if left <= FREE_FRACTION:
			_wake(s, false)


func _ice_round(s: Dictionary, field: IceField) -> int:
	var box: AABB = s.region
	var n := 0
	var x := box.position.x + 0.5
	while x < box.end.x:
		var z := box.position.z + 0.5
		while z < box.end.z:
			var y := 0.5
			while y < box.end.y:
				if field.solid_at(Vector3(x, y, z)):
					n += 1
				y += 1.0
			z += 1.0
		x += 1.0
	return n


func _process(delta: float) -> void:
	_time += delta
	if GameState.has_won:
		_float(delta)
	# Check one ship every so often (each check reads a few thousand grid points).
	_check_timer -= delta
	if _check_timer > 0.0 or ships.is_empty():
		return
	_check_timer = 0.4
	_check_i = (_check_i + 1) % ships.size()
	var s: Dictionary = ships[_check_i]
	if s.freed or s.glacier != GameState.stage or GameState.grids.size() <= s.glacier:
		return
	var left: float = float(_ice_round(s, GameState.grids[s.glacier])) / float(s.fresh)
	if not s.spotted and left <= SPOT_FRACTION:
		s.spotted = true
		ship_spotted.emit(str(s.def.name))
	if left <= FREE_FRACTION:
		_wake(s, true)


func _wake(s: Dictionary, pay: bool) -> void:
	## The ice round a ship is gone: its crew thaws out and celebrates.
	s.freed = true
	var i := 0
	for holder in s.crew:
		var mi := (holder as Node3D).get_child(0) as MeshInstance3D
		mi.material_override = MeshKit.material()   # back to full colour (null would be plain grey)
		var tw := mi.create_tween().set_loops()
		tw.tween_interval(0.13 * i)
		tw.tween_property(mi, "position:y", 0.35, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.5 + 0.1 * (i % 3))
		if i % 2 == 0:
			tw.tween_property(mi, "rotation:y", TAU, 0.5).from(0.0)
		i += 1
	if pay:
		var bounty := float(s.def.get("bounty", 0.0)) * GameState.sell_mult()
		GameState.grant_water(bounty)
		ship_freed.emit(str(s.def.name), bounty)


func _float(_delta: float) -> void:
	## The lake has thawed: every ship rocks gently on the water.
	var k := 0
	for s in ships:
		var node: Node3D = s.node
		var t := _time + k * 1.7
		node.position.y = float(s.def.pos.y) - 0.1 + sin(t * 0.9) * 0.12
		node.rotation.z = sin(t * 0.6) * 0.035
		node.rotation.x = sin(t * 0.45 + 1.0) * 0.015
		k += 1
		if not s.freed:
			_wake(s, false)
