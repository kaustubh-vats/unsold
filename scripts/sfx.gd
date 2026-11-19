extends Node
## Audio (autoload "Sfx"): looping background music, sound effects and auctioneer voice.
## Assets were generated with ElevenLabs and live in res://assets/audio.

const DIR := "res://assets/audio/"
const SETTINGS := "user://audio.cfg"

var music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var music_on := true
var sfx_on := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		music_on = cfg.get_value("audio", "music", true)
		sfx_on = cfg.get_value("audio", "sfx", true)
	music = AudioStreamPlayer.new()
	music.volume_db = -14.0
	add_child(music)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	var s = _load("music_loop")
	if s is AudioStreamMP3:
		s.loop = true
		music.stream = s
	if music_on:
		music.play()


func _load(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".mp3"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[name] = s
	return s


## Play a one-shot: click, bid, outbid, tick, sold, unsold, win, vo_sold, vo_unsold, vo_going.
func play(name: String, volume_db := 0.0) -> void:
	if not sfx_on:
		return
	var s := _load(name)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.play()
			return
	_pool[0].stream = s
	_pool[0].volume_db = volume_db
	_pool[0].play()


func set_music(on: bool) -> void:
	music_on = on
	if on and not music.playing:
		music.play()
	elif not on:
		music.stop()
	_save()


func set_sfx(on: bool) -> void:
	sfx_on = on
	_save()


## Lower the music while important moments play.
func duck(seconds := 1.5) -> void:
	if not music.playing:
		return
	var tw := create_tween()
	tw.tween_property(music, "volume_db", -26.0, 0.1)
	tw.tween_interval(seconds)
	tw.tween_property(music, "volume_db", -14.0, 0.6)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "sfx", sfx_on)
	cfg.save(SETTINGS)
