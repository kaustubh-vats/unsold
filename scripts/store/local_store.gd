class_name LocalStore
extends RoomStore
## Offline single-player room. Same state shape as multiplayer.


func setup(player_name: String) -> void:
	my_uid = "local"
	state = {
		"meta": {
			"host": my_uid, "status": "lobby", "seed": randi() % 1000000,
			"settings": {"timer": 10, "win_mode": "season", "ai_fill": true},
			"created": now_ms(),
		},
		"players": {my_uid: {"name": player_name, "team": "", "joined": now_ms(), "seen": now_ms()}},
	}


func write(updates: Dictionary) -> bool:
	Auction.apply_updates(state, updates)
	changed.emit()
	return true


func _transact_auction(fn: Callable) -> bool:
	var n = fn.call(state.get("auction"))
	if n == null:
		return false
	state["auction"] = n
	changed.emit()
	return true
