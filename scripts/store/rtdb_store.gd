class_name RtdbStore
extends RoomStore
## Multiplayer room backed by Firebase Realtime Database (rooms/{code}).

const HEARTBEAT_MS := 3000
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var _listen_handle := -1
var _last_beat := 0
var _synced := false


func root() -> String:
	return "rooms/" + room_code


func is_online() -> bool:
	return true


func now_ms() -> int:
	return Firebase.server_now()


static func random_code() -> String:
	var s := ""
	for i in 6:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


## Create a new room with this device as host. Returns "" or an error.
func create(player_name: String) -> String:
	if not Firebase.is_signed_in():
		return "Please sign in to play online."
	my_uid = Firebase.uid
	for attempt in 5:
		room_code = random_code()
		var existing = await Firebase.get_value(root() + "/meta/host")
		if existing == null:
			break
	var now := now_ms()
	var room := {
		"meta": {
			"host": my_uid, "status": "lobby", "seed": randi() % 1000000, "created": now, "online": true,
			"settings": {"timer": 10, "win_mode": "season", "ai_fill": true},
		},
		"players": {my_uid: {"name": player_name, "team": "", "joined": now, "seen": now}},
	}
	if not await Firebase.set_value(root(), room):
		return "Could not create room (check database rules)."
	# Show the room immediately; the live stream confirms and keeps it updated.
	state = room.duplicate(true)
	_synced = true
	changed.emit()
	_start_listening()
	return ""


func join(code: String, player_name: String) -> String:
	if not Firebase.is_signed_in():
		return "Please sign in to play online."
	my_uid = Firebase.uid
	room_code = code.strip_edges().to_upper()
	var meta = await Firebase.get_value(root() + "/meta")
	if meta == null:
		return "Room %s not found" % room_code
	var existing = await Firebase.get_value(root() + "/players/" + my_uid)
	if existing == null:
		if meta.get("status", "lobby") != "lobby":
			return "That auction has already started"
		var n = await Firebase.get_value(root() + "/players")
		if typeof(n) == TYPE_DICTIONARY and n.size() >= 10:
			return "Room is full"
		var now := now_ms()
		await Firebase.set_value(root() + "/players/" + my_uid,
			{"name": player_name, "team": "", "joined": now, "seen": now})
	var full = await Firebase.get_value(root())
	if typeof(full) == TYPE_DICTIONARY:
		state = full
		_synced = true
		changed.emit()
	_start_listening()
	return ""


func _start_listening() -> void:
	_listen_handle = Firebase.listen(root(), _on_event)


func _on_event(kind: String, path: String, data) -> void:
	if path == "/" and kind == "put":
		state = data if typeof(data) == TYPE_DICTIONARY else {}
	elif kind == "put":
		Auction.put_path(state, path, data)
	elif kind == "patch" and typeof(data) == TYPE_DICTIONARY:
		for k in data:
			Auction.put_path(state, path.trim_suffix("/") + "/" + str(k), data[k])
	_synced = true
	changed.emit()


func _process(_dt: float) -> void:
	if room_code == "" or not _synced:
		return
	var t := Time.get_ticks_msec()
	if t - _last_beat > HEARTBEAT_MS:
		_last_beat = t
		Firebase.update(root(), {"players/%s/seen" % my_uid: Firebase.TIMESTAMP})


func write(updates: Dictionary) -> bool:
	# Optimistic local apply so the UI responds immediately; the stream confirms.
	Auction.apply_updates(state, updates)
	changed.emit()
	return await Firebase.update(root(), updates)


func _transact_auction(fn: Callable) -> bool:
	var r: Dictionary = await Firebase.transaction(root() + "/auction", fn)
	return r.get("ok", false)


## Claim host if the current host has gone silent. Only the earliest-joined
## online player tries, and the claim is a transaction on meta/host.
func try_take_over_host() -> void:
	var players: Dictionary = state.get("players", {})
	var host: String = meta().get("host", "")
	var now := now_ms()
	var host_seen := int(players.get(host, {}).get("seen", 0))
	if now - host_seen < 10000:
		return
	var candidates := []
	for uid in players:
		if now - int(players[uid].get("seen", 0)) < 8000:
			candidates.append([int(players[uid].get("joined", 0)), uid])
	candidates.sort()
	if candidates.is_empty() or candidates[0][1] != my_uid:
		return
	await Firebase.transaction(root() + "/meta/host", func(cur):
		return my_uid if cur == host else null)


func leave() -> void:
	if _listen_handle >= 0:
		Firebase.unlisten(_listen_handle)
	if room_code != "" and status() == "lobby":
		await Firebase.set_value(root() + "/players/" + my_uid, null)
	queue_free()
