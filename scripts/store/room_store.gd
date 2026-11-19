class_name RoomStore
extends Node
## Shared room state + actions. LocalStore (single player) and RtdbStore
## (Firebase multiplayer) implement the I/O; game logic lives in the engine.

signal changed
signal error(msg: String)

const Auctioneer := preload("res://scripts/store/auctioneer.gd")

var state: Dictionary = {}
var my_uid := ""
var room_code := ""
var auctioneer: Node


func _ready() -> void:
	auctioneer = Auctioneer.new()
	auctioneer.store = self
	add_child(auctioneer)


# ------------------------------------------------------------ to implement

func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func write(_updates: Dictionary) -> bool:
	return false


func _transact_auction(_fn: Callable) -> bool:
	return false


func is_online() -> bool:
	return false


func leave() -> void:
	queue_free()


func try_take_over_host() -> void:
	pass


# ------------------------------------------------------------ queries

func meta() -> Dictionary:
	return state.get("meta", {})


func status() -> String:
	return meta().get("status", "lobby")


func settings() -> Dictionary:
	return meta().get("settings", {})


func is_host() -> bool:
	return meta().get("host", "") == my_uid


func my_team() -> String:
	return state.get("players", {}).get(my_uid, {}).get("team", "")


func team(tid: String) -> Dictionary:
	return state.get("teams", {}).get(tid, {})


func auction() -> Dictionary:
	return state.get("auction", {})


func team_owner_name(tid: String) -> String:
	var players: Dictionary = state.get("players", {})
	for uid in players:
		if players[uid].get("team", "") == tid:
			return players[uid].get("name", "")
	return ""


# ------------------------------------------------------------ actions

func choose_team(tid: String) -> void:
	for uid in state.get("players", {}):
		if uid != my_uid and state["players"][uid].get("team", "") == tid:
			error.emit("Team already taken")
			return
	await write({"players/%s/team" % my_uid: tid})


func set_setting(key: String, value) -> void:
	if is_host():
		await write({"meta/settings/" + key: value})


func start_auction() -> void:
	if not is_host():
		return
	if my_team() == "":
		error.emit("Pick your franchise first")
		return
	await write(Auction.start_updates(state, now_ms()))


## Returns "" on success, otherwise an error message.
func bid(tid: String) -> String:
	var a := auction()
	if a.get("phase", "") != "bidding":
		return "Bidding closed"
	var amount := Auction.current_next(state)
	var err := Rules.bid_error(team(tid), DB.player(a.get("pid", "")), amount)
	if err != "":
		return err
	return await place_bid(tid, amount)


func place_bid(tid: String, amount: int) -> String:
	var t := team(tid)
	var now := now_ms()
	var timer := Auction.timer_ms(state)
	var ok := await _transact_auction(func(cur):
		return Auction.apply_bid(cur, tid, amount, t, now, timer))
	return "" if ok else "Outbid — try again"


func pass_lot(tid: String) -> void:
	await write({"auction/passes/" + tid: true})


func set_xi(tid: String, xi: Array) -> void:
	await write({"teams/%s/xi" % tid: xi})


func set_ready(ready: bool) -> void:
	await write({"players/%s/ready" % my_uid: ready})


func reset_to_lobby() -> void:
	if not is_host():
		return
	var up := {"meta/status": "lobby", "auction": null, "teams": null, "log": null,
		"meta/seed": randi() % 1000000}
	for uid in state.get("players", {}):
		up["players/%s/ready" % uid] = false
	await write(up)
