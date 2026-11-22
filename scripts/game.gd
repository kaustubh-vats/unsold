extends Node
## Global game state (autoload "Game"): player profile, current room, navigation.

signal screen_requested(screen: String)
signal theme_changed
signal wishlist_changed

const PROFILE := "user://profile.cfg"
const WISHLIST := "user://wishlist.cfg"

var player_name := ""
var store: RoomStore = null
var results_cache := {}   # memoized season/score results by key
var wishlist := {}        # {pid: true}: players you starred to watch for (this device only)


func _ready() -> void:
	UI.load_theme_choice()
	DB.ensure_loaded()
	randomize()
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE) == OK:
		player_name = cfg.get_value("profile", "name", "")
	var wl := ConfigFile.new()
	if wl.load(WISHLIST) == OK:
		for pid in wl.get_value("wishlist", "players", []):
			if not DB.player(pid).is_empty():
				wishlist[pid] = true
	Firebase.auth_changed.connect(_on_auth_changed)
	# Restore a saved login in the background (no-op if never signed in).
	if Firebase.is_configured():
		Firebase.restore_session()


## Use the account's name as the player name if the player hasn't set one.
func _on_auth_changed() -> void:
	if Firebase.is_signed_in() and player_name == "" and Firebase.display_name != "":
		save_name(Firebase.display_name)


func save_name(n: String) -> void:
	player_name = n.strip_edges().substr(0, 16)
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.save(PROFILE)


func is_wished(pid: String) -> bool:
	return wishlist.has(pid)


## Star or unstar a player; returns whether he's starred now.
func toggle_wish(pid: String) -> bool:
	if wishlist.has(pid):
		wishlist.erase(pid)
	else:
		wishlist[pid] = true
	_save_wishlist()
	return wishlist.has(pid)


func clear_wishlist() -> void:
	wishlist.clear()
	_save_wishlist()


func _save_wishlist() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wishlist", "players", wishlist.keys())
	cfg.save(WISHLIST)
	wishlist_changed.emit()


func toggle_theme() -> void:
	UI.set_light(not UI.light)
	theme_changed.emit()


func goto(screen: String) -> void:
	screen_requested.emit(screen)


func _set_store(s: RoomStore) -> void:
	if store != null and is_instance_valid(store):
		store.leave()
	store = s
	results_cache.clear()
	add_child(s)


func start_single() -> void:
	var s := LocalStore.new()
	s.setup(player_name)
	_set_store(s)
	goto("lobby")


func create_room() -> String:
	var s := RtdbStore.new()
	_set_store(s)
	var err := await s.create(player_name)
	if err != "":
		leave_room()
		return err
	goto("lobby")
	return ""


func join_room(code: String) -> String:
	var s := RtdbStore.new()
	_set_store(s)
	var err := await s.join(code, player_name)
	if err != "":
		leave_room()
		return err
	goto("lobby")
	return ""


func leave_room() -> void:
	if store != null and is_instance_valid(store):
		store.leave()
	store = null
	results_cache.clear()


## Season / score results computed deterministically from the room state.
func results() -> Dictionary:
	var st := store.state
	var key := "%s|%s" % [str(st.get("meta", {}).get("seed", 0)), JSON.stringify(_xis())]
	if results_cache.has(key):
		return results_cache[key]
	var r := {"leaderboard": Score.leaderboard(st)}
	r["season"] = Sim.season(_xis(), int(st.get("meta", {}).get("seed", 1)))
	results_cache = {key: r}
	return r


func _xis() -> Dictionary:
	var out := {}
	var teams: Dictionary = store.state.get("teams", {})
	var ids: Array = teams.keys()
	ids.sort()
	for tid in ids:
		var xi: Array = teams[tid].get("xi", [])
		var squad: Array = teams[tid].get("squad", {}).keys()
		if XI.problems(xi, squad).size() > 0 or xi.is_empty():
			xi = XI.best_xi(squad)
		out[tid] = xi
	return out
