extends Node
## Audio (autoload "Sfx"): looping background music, sound effects and auctioneer voice.
## Assets were generated with ElevenLabs and live in res://assets/audio.

const DIR := "res://assets/audio/"
const SETTINGS := "user://audio.cfg"

var music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var voice: AudioStreamPlayer      # the auctioneer: one line at a time
var _voice_next := ""             # latest line waiting for the current one to finish
var _lines := {}
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
	voice = AudioStreamPlayer.new()
	voice.volume_db = 1.0
	voice.finished.connect(_on_voice_done)
	add_child(voice)
	var f := FileAccess.open("res://data/auctioneer.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_lines = d
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


## The auctioneer's words for a line ("bid_250", "open_75"), or "" if none.
func line_text(name: String) -> String:
	return str(_lines.get(name, ""))


## The auctioneer calls a line. Calls never overlap: while he's talking, only the
## most recent request is kept, so in a quick bidding war he skips straight to
## the current price instead of lagging behind it.
func say(name: String, interrupt := false) -> void:
	if not sfx_on:
		return
	var path := DIR + "vo/" + name + ".mp3"
	if not _lines.has(name) and not ResourceLoader.exists(DIR + name + ".mp3"):
		return
	if interrupt:
		_voice_next = ""
		voice.stop()
	if voice.playing:
		_voice_next = name
		return
	var s: AudioStream = _load("vo/" + name) if ResourceLoader.exists(path) else _load(name)
	if s == null:
		return
	voice.stream = s
	voice.play()
	duck(s.get_length())


## How long a line takes to say, in ms (0 if there is no clip). Used to pace
## the AI so paddles go up after the auctioneer finishes, even with sound off.
func line_ms(name: String) -> int:
	var path := DIR + "vo/" + name + ".mp3"
	var s: AudioStream = _load("vo/" + name) if ResourceLoader.exists(path) else _load(name)
	return int(s.get_length() * 1000.0) if s != null else 0


## True while the auctioneer is talking (or has a line queued).
func talking() -> bool:
	return voice.playing or _voice_next != ""


## "Sold! To the <team>!" — per-team lines; the Friends edition has its own
## clips with real team names in private/vo. Renamed teams get the generic call.
func say_sold(tid: String) -> void:
	var priv := "res://private/vo/sold_%s.mp3" % tid.to_lower()
	if DB.is_friends_edition() and not DB.is_renamed(tid) and ResourceLoader.exists(priv):
		hush()
		if sfx_on:
			voice.stream = load(priv)
			voice.play()
		return
	if not DB.is_friends_edition() and not DB.is_renamed(tid) and ResourceLoader.exists(DIR + "vo/sold_%s.mp3" % tid.to_lower()):
		say("sold_%s" % tid.to_lower(), true)
	else:
		say("vo_sold", true)


func hush() -> void:
	_voice_next = ""
	voice.stop()


func _on_voice_done() -> void:
	if _voice_next != "":
		var n := _voice_next
		_voice_next = ""
		say(n)


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
