extends Node
## Autoload "Sound": every sound effect, the music and the ambience.
##
## All the audio is made by script (art/audio/), so it's original and can be
## rebuilt. Game code calls play() / play_at() for one-off sounds; the
## continuous ones (your tool, steam where it lands, the jetpack, footsteps,
## wind, birds, music) are worked out here every frame from the game state.
##
## Buses (default_bus_layout.tres): Music, Ambience, SFX, all into Master.
## Settings (volumes, mute) live in user://settings.cfg, apart from the save,
## so starting over keeps them.
##
## Web: one-off sounds play as Web Audio samples (no stutter when the frame
## rate dips). Anything that loops (tools, steam, jetpack, wind, birds) and the
## music are mixed by Godot instead ("stream" playback), because the web build
## loops samples by restarting them, with a tiny gap each time. Without threads
## that mixing happens between frames, so the buffer is roomy (project setting
## audio/driver/output_latency.web = 200 ms, about a third of a second once
## rounded up) and rides out slow frames. The lag doesn't show: each loop
## starts with an instant one-off sound (the tool clicking on, the jetpack
## firing) and fades in under it.
## Browsers only allow sound after the first tap or key; Godot resumes its
## audio then by itself.

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const AMB_DIR := "res://audio/amb/"
const SETTINGS_PATH := "user://settings.cfg"
const VOICES_2D := 12
const VOICES_3D := 14

# Which music plays when. Tracks take turns, with quiet stretches in between
# (wind and the ice), so an hour on the glacier doesn't wear the tunes out.
const PLAYLISTS := {
	"valley": ["valley_1", "valley_2"],
	"lake": ["lake_1", "lake_2"],
	"summer": ["summer"],
}
const MUSIC_GAP := Vector2(35.0, 80.0)       # seconds of quiet between tracks
const MUSIC_FIRST_DELAY := 3.0
const MUSIC_DB := -4.0                        # music sits under the effects

var music_volume := 0.7        # 0..1, the settings sliders
var sfx_volume := 0.9
var muted := false
var indoors := false            # in the shed: footsteps on boards, the wind muffled

var _bank := {}                 # name -> Array[AudioStream] (variations)
var _v2d: Array = []
var _v3d: Array = []
var _next2d := 0
var _next3d := 0
var _cooldown := {}             # name -> earliest time it may play again
var _loops := {}                # id -> {player, name, vol, want, pitch, pitch_want, rate}
var _music: AudioStreamPlayer
var _music_list := ""
var _music_index := 0
var _music_wait := MUSIC_FIRST_DELAY
var _music_fade := 0.0          # > 0: fading the current track out
var _duck := 0.0                # seconds left of the music being turned down for a jingle
var _duck_gain := 1.0
var _hush := false              # an ad is showing, or the tab is hidden: everything off
var _web_hidden := false
var _web_check := 0.0
var _clock := 0.0

# What the player was doing last frame (for edges: tool on/off, jump, land...)
var _tool_on := false
var _tool_shown := -1
var _steps := 0
var _was_floor := true
var _fall_speed := 0.0
var _jetting := false
var _sputtered := false
var _crack_t := 0.0
var _drip_t := 0.0
var _loose_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	for i in VOICES_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_v2d.append(p)
	for i in VOICES_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = 90.0
		p.panning_strength = 0.8
		add_child(p)
		_v3d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_music.volume_db = MUSIC_DB
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	GameState.discovered_item.connect(_on_discovered)
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.won.connect(_on_won)


# =====================================================================================
# Playing sounds
# =====================================================================================
func streams(name: String) -> Array:
	## Every variation of a sound: "crack" finds crack_1.ogg, crack_2.ogg...
	if _bank.has(name):
		return _bank[name]
	var list: Array = []
	for dir in [SFX_DIR, AMB_DIR, MUSIC_DIR]:
		var path: String = dir + name + ".ogg"
		if ResourceLoader.exists(path):
			list.append(load(path))
			break
	if list.is_empty():
		var i := 1
		while ResourceLoader.exists(SFX_DIR + "%s_%d.ogg" % [name, i]):
			list.append(load(SFX_DIR + "%s_%d.ogg" % [name, i]))
			i += 1
	if list.is_empty():
		push_warning("Sound: no audio called '%s'" % name)
	_bank[name] = list
	return list


func _pick(name: String) -> AudioStream:
	var list := streams(name)
	return null if list.is_empty() else list[randi() % list.size()]


func _ready_to_play(name: String, gap: float) -> bool:
	if gap <= 0.0:
		return true
	if _clock < float(_cooldown.get(name, -1.0)):
		return false
	_cooldown[name] = _clock + gap
	return true


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_rand: float = 0.0, gap: float = 0.0) -> void:
	## A sound with no position (UI, jingles, your own footsteps). `gap`: don't
	## play this one again for that many seconds.
	if not _ready_to_play(name, gap):
		return
	var s := _pick(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _v2d[_next2d]
	_next2d = (_next2d + 1) % _v2d.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_rand, pitch_rand)))
	p.play()


func play_at(name: String, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0, pitch_rand: float = 0.06,
		unit: float = 6.0, gap: float = 0.0) -> void:
	## A sound out in the world: it gets quieter with distance and comes from
	## its side. `unit` is how far away it still sounds full volume (bigger =
	## carries further: Kevin's booms).
	if not at.is_finite() or not _ready_to_play(name, gap):
		return
	var s := _pick(name)
	if s == null:
		return
	var p: AudioStreamPlayer3D = _v3d[_next3d]
	_next3d = (_next3d + 1) % _v3d.size()
	p.stream = s
	p.global_position = at
	p.volume_db = volume_db
	p.unit_size = unit
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_rand, pitch_rand)))
	p.play()


func jingle(name: String, volume_db: float = 0.0, seconds: float = 3.0) -> void:
	## A musical sting: the music steps back while it plays.
	play(name, volume_db)
	_duck = maxf(_duck, seconds)


# --- Loops -----------------------------------------------------------------------------
func set_loop(id: String, name: String, volume: float, pitch: float = 1.0, rate: float = 6.0, bus: String = "SFX") -> void:
	## A sound that keeps going (a tool, the wind...): `volume` 0..1 is where it
	## fades to at `rate` per second; at 0 it stops. Change `name` to swap it.
	var l: Dictionary = _loops.get(id, {})
	if l.is_empty():
		if volume <= 0.0:
			return
		var p := AudioStreamPlayer.new()
		p.bus = bus
		# Mixed by Godot, not as a Web Audio sample: the web build loops samples by
		# restarting them, which leaves a tiny gap every time round. (The long
		# ambience also isn't decoded into memory all at once this way.)
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(p)
		l = {"player": p, "name": "", "vol": 0.0, "want": 0.0, "pitch": pitch, "pitch_want": pitch, "rate": rate}
		_loops[id] = l
	if l.name != name and volume > 0.0:
		var s := _pick(name)
		if s == null:
			return
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		var p: AudioStreamPlayer = l.player
		p.stream = s
		l.name = name
		l.vol = 0.0 if not p.playing else l.vol
		p.play(randf() * maxf(0.0, s.get_length() - 0.1))   # from anywhere: no two starts sound alike
	l.want = clampf(volume, 0.0, 1.5)
	l.pitch_want = pitch
	l.rate = rate


func loop_volume(id: String) -> float:
	return float(_loops[id].vol) if _loops.has(id) else 0.0


func _update_loops(delta: float) -> void:
	for id in _loops:
		var l: Dictionary = _loops[id]
		var p: AudioStreamPlayer = l.player
		l.vol = move_toward(l.vol, l.want, delta * float(l.rate))
		l.pitch = lerpf(l.pitch, l.pitch_want, minf(1.0, delta * 6.0))
		if l.vol <= 0.001 and l.want <= 0.0:
			if p.playing:
				p.stop()
			l.name = ""
			continue
		p.volume_db = linear_to_db(maxf(l.vol, 0.0001))
		if absf(p.pitch_scale - l.pitch) > 0.002:
			p.pitch_scale = maxf(0.05, l.pitch)


# =====================================================================================
# Every frame: you, the world, the music
# =====================================================================================
func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_clock += delta
	_check_hush(delta)
	var p = GameState.player
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		_update_player(p, delta)
		_update_ambience(p, delta)
	else:
		for id in ["tool", "sizzle", "jet", "wind", "birds"]:
			if _loops.has(id):
				_loops[id].want = 0.0
	_update_loops(delta)
	_update_music(delta)


func _update_player(p, delta: float) -> void:
	# --- The tool: switching on, the spray, and where it lands.
	var tool := GameState.tool_index
	var on: bool = p.tool_active
	if on and (not _tool_on or tool != _tool_shown):
		play("tool_on_%d" % tool, -3.0, 1.0, 0.04)
	_tool_shown = tool
	# Upgrades show in the sound: Heat Output pitches it up and makes it fiercer,
	# Wider Nozzle and Longer Reach make it bigger and louder, a heat boost lifts it.
	var heat_lvl := float(GameState.upgrade_levels.get("heat", 0))
	var nozzle_lvl := float(GameState.upgrade_levels.get("nozzle", 0))
	var reach_lvl := float(GameState.upgrade_levels.get("reach", 0))
	var pitch := 1.0 + minf(0.22, heat_lvl * 0.012)
	if GameState.is_boost_active() or GameState.owns_remove_ads_2x:
		pitch *= 1.04
	var vol := 0.55 + minf(0.35, nozzle_lvl * 0.02 + reach_lvl * 0.012)
	if on:
		set_loop("tool", "tool_loop_%d" % tool, vol, pitch, 10.0)
	elif _tool_on:
		# Let go: motors spin down, flames gutter out.
		var spin := tool <= 1
		set_loop("tool", "tool_loop_%d" % tool, 0.0, pitch * (0.6 if spin else 0.9), 3.0 if spin else 6.0)
	_tool_on = on

	var target: Dictionary = p.target
	var working: bool = on and target.get("hit", false)
	var hardness := 0
	var on_lake := false
	if working:
		var g: IceField = target.grid
		hardness = g.layer_at(target.pos - target.normal * 0.3)
		on_lake = g != GameState.grids[0] if not GameState.grids.is_empty() else false
	set_loop("sizzle", "sizzle_loop", float(p.heat) * (0.5 + 0.05 * tool), 1.05 - 0.025 * hardness, 5.0)
	if working:
		# Cracks and drips where the heat lands: harder (deeper) ice cracks
		# lower and louder, the lake's thick ice sings.
		_crack_t -= delta * (0.5 + 0.22 * tool + 0.04 * hardness)
		if _crack_t <= 0.0:
			_crack_t = randf_range(0.6, 1.6)
			var name := "lake_crack" if on_lake and randf() < 0.35 else "crack"
			play_at(name, target.pos, -6.0 + 0.6 * hardness, 1.12 - 0.03 * hardness, 0.1, 5.0)
		_drip_t -= delta * (2.0 + 0.4 * tool)
		if _drip_t <= 0.0:
			_drip_t = randf_range(0.5, 1.2)
			play_at("drip", target.pos + Vector3(0, -0.3, 0), -10.0, 1.0, 0.15, 4.0)

	# --- Walking: snow on the ice, earth (or grass) on the ground, boards in the shed.
	if p.steps != _steps:
		_steps = p.steps
		var surface := "wood" if indoors else ("snow" if p.on_ice else "ground")
		play("step_" + surface, -9.0 if surface == "snow" else -7.0, 1.0, 0.08)

	# --- Jumping and landing.
	var floor_now: bool = p.on_floor
	if not floor_now:
		_fall_speed = minf(_fall_speed, p.velocity.y)
	if _was_floor and not floor_now and p.velocity.y > 3.0:
		play("jump", -6.0, 1.0, 0.1)
	if floor_now and not _was_floor:
		if _fall_speed < -4.0:
			play("land", clampf(-14.0 - _fall_speed, -10.0, 0.0), 1.0, 0.08)
		_fall_speed = 0.0
	_was_floor = floor_now

	# --- The jetpack.
	var jet: bool = p.jetting
	if jet and not _jetting:
		play("jet_start", -6.0, 1.0, 0.05)
	_jetting = jet
	set_loop("jet", "jet_loop", 0.55 if jet else 0.0, 1.0 + 0.1 * (1.0 - float(p.fuel)), 8.0)
	var dry: bool = p.jet_held and not floor_now and float(p.fuel) <= 0.0
	if dry and not _sputtered:
		play("jet_sputter", -4.0)
	_sputtered = dry

	# --- Loose bits of ice dripping away by themselves.
	_loose_t -= delta
	if _loose_t <= 0.0:
		_loose_t = randf_range(0.25, 0.6)
		for g in GameState.grids:
			var at: Vector3 = (g as IceField).loose_drip_at
			if at.is_finite():
				play_at("drip", at, -12.0, 1.1, 0.2, 4.0)
				break


func _update_ambience(p, _delta: float) -> void:
	## Wind while there's a glacier (more of it high up, less indoors); birds
	## as the valley greens up, and all summer long after the ending.
	var grids: Array = GameState.grids
	var left := 1.0
	var green := 0.0
	if not grids.is_empty():
		left = (GameState.grid as IceField).fraction_left() if GameState.grid != null else 0.0
		green = 1.0 - (grids[0] as IceField).fraction_left()
	var height := clampf((float(p.global_position.y) - 2.0) / 18.0, 0.0, 1.0)
	var wind := 0.35 + 0.35 * left + 0.4 * height
	var birds := 0.12 * green if GameState.stage == 0 else 0.25
	if GameState.has_won:
		wind = 0.12 + 0.3 * height
		birds = 1.0
	if indoors:
		wind *= 0.35
		birds *= 0.3
	set_loop("wind", "wind", wind, 1.0, 0.4, "Ambience")
	set_loop("birds", "birds", birds, 1.0, 0.25, "Ambience")


# --- Music ---------------------------------------------------------------------------------
func _wanted_list() -> String:
	if GameState.has_won:
		return "summer"
	return "lake" if GameState.stage >= 1 else "valley"


func _update_music(delta: float) -> void:
	var want := _wanted_list()
	if GameState.player == null:
		want = ""   # (tests and loading: no world yet)
	if want != _music_list:
		if _music.playing:
			_music_fade = maxf(_music_fade, 0.01)   # finish this one gently
		_music_list = want
		_music_index = 0
		_music_wait = MUSIC_FIRST_DELAY if want != "summer" else 2.5
	# Jingles duck the music for a moment.
	_duck = maxf(0.0, _duck - delta)
	_duck_gain = move_toward(_duck_gain, 0.35 if _duck > 0.0 else 1.0, delta * (3.0 if _duck > 0.0 else 0.6))
	if _music_fade > 0.0:
		_music_fade += delta
		var k := clampf(1.0 - _music_fade / 2.5, 0.0, 1.0)
		_music.volume_db = MUSIC_DB + linear_to_db(maxf(k * _duck_gain, 0.0001))
		if k <= 0.0:
			_music.stop()
			_music_fade = 0.0
		return
	if _music.playing:
		_music.volume_db = MUSIC_DB + linear_to_db(maxf(_duck_gain, 0.0001))
		return
	if _music_list == "":
		return
	_music_wait -= delta
	if _music_wait > 0.0:
		return
	var list: Array = PLAYLISTS[_music_list]
	var track: String = list[_music_index % list.size()]
	_music_index += 1
	var s = load(MUSIC_DIR + track + ".ogg")
	if s == null:
		return
	(s as AudioStreamOggVorbis).loop = false
	_music.stream = s
	_music.volume_db = MUSIC_DB + linear_to_db(maxf(_duck_gain, 0.0001))
	_music.play()


func _on_music_finished() -> void:
	_music_wait = randf_range(MUSIC_GAP.x, MUSIC_GAP.y)
	if _music_list == "summer":
		_music_wait *= 0.4


func now_playing() -> String:
	## The track that's playing ("" between tracks). For tests.
	return (_music.stream as Resource).resource_path.get_file().get_basename() if _music.playing and _music.stream != null else ""


# =====================================================================================
# Game events
# =====================================================================================
func _on_discovered(i: int, _value: float) -> void:
	var rarity := clampi(int(Balance.DISCOVERIES[i].get("rarity", 0)), 0, 4)
	jingle("find_jingle_%d" % (rarity + 1), -2.0 if rarity >= 2 else -4.0, 2.0 + rarity * 0.6)


func _on_stage_changed(_stage: int) -> void:
	jingle("stage_done", 0.0, 6.0)


func _on_won() -> void:
	jingle("stage_done", 0.0, 4.0)


func set_indoors(on: bool) -> void:
	## Walked into (or out of) the shed: the bell over the door.
	if on == indoors:
		return
	indoors = on
	play("shed_bell", -4.0 if on else -9.0, 1.0 if on else 0.94, 0.02)


func _on_node_added(node: Node) -> void:
	## Every button in the menus clicks (unless it has its own sound: meta "silent").
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func():
			if not node.has_meta("silent"):
				play("click", -4.0, 1.0, 0.05))


# =====================================================================================
# Settings, ads, the tab being hidden
# =====================================================================================
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func set_muted(on: bool) -> void:
	muted = on
	_apply_volumes()
	_save_settings()


func _apply_volumes() -> void:
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, muted or _hush)
	for pair in [["Music", music_volume], ["SFX", sfx_volume], ["Ambience", sfx_volume]]:
		var b := AudioServer.get_bus_index(pair[0])
		if b < 0:
			continue
		var v: float = pair[1]
		AudioServer.set_bus_mute(b, v <= 0.001)
		# Perceived loudness: a curve, so 50% sounds like half.
		AudioServer.set_bus_volume_db(b, linear_to_db(maxf(v * v, 0.0001)))


func _check_hush(delta: float) -> void:
	## Ads play their own sound, and a hidden browser tab should be quiet.
	if OS.has_feature("web"):
		_web_check -= delta
		if _web_check <= 0.0:
			_web_check = 0.5
			_web_hidden = bool(JavaScriptBridge.eval("document.hidden", true))
	var hush: bool = _web_hidden or Monetization.is_showing_ad()
	if hush != _hush:
		_hush = hush
		_apply_volumes()


func _exit_tree() -> void:
	# Stop everything so the engine can let go of the streams when it quits.
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
			c.stream = null
	_bank.clear()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
		NOTIFICATION_APPLICATION_RESUMED:
			_apply_volumes()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	music_volume = clampf(float(cfg.get_value("sound", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("sound", "effects", sfx_volume)), 0.0, 1.0)
	muted = bool(cfg.get_value("sound", "muted", false))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep anything else in there
	cfg.set_value("sound", "music", music_volume)
	cfg.set_value("sound", "effects", sfx_volume)
	cfg.set_value("sound", "muted", muted)
	cfg.save(SETTINGS_PATH)
