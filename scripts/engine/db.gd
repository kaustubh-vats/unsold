class_name DB
extends RefCounted
## Static access to player and team data loaded from res://data.

static var _players: Dictionary = {}   # id -> player dict
static var _order: Array = []          # ids in file order
static var _teams: Array = []          # team dicts
static var _team_by_id: Dictionary = {}


static func ensure_loaded() -> void:
	if not _players.is_empty():
		return
	var pj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/players.json"))
	var i := 0
	for row in pj["players"]:
		var id := "p%03d" % i
		var p := {
			"id": id,
			"name": row[0],
			"country": row[1],
			"overseas": row[1] != "IND",
			"role": row[2],
			"bat": int(row[3]),
			"bowl": int(row[4]),
			"base": int(row[5]),
			"capped": int(row[6]) == 1,
			"trait": row[7],
		}
		p["ovr"] = overall(p)
		_players[id] = p
		_order.append(id)
		i += 1
	_teams = JSON.parse_string(FileAccess.get_file_as_string("res://data/teams.json"))
	for t in _teams:
		t["short"] = t["id"]
		_team_by_id[t["id"]] = t
	_apply_edition_names()
	for id in _players:
		_default_names[id] = _players[id]["name"]
	for t in _teams:
		_default_teams[t["id"]] = {"name": t["name"], "short": t["short"]}
	_load_overrides()


# ------------------------------------------------------------------ roster editor
# Users can rename players and teams on their own device. Overrides live in
# user://roster.json and can be exported/imported as a shareable roster file.
# They are display-only: rooms sync player/team ids, never names.

const ROSTER_FILE := "user://roster.json"
const ROSTER_FORMAT := "unsold-roster-1"
static var _default_names: Dictionary = {}
static var _default_teams: Dictionary = {}
static var _overrides: Dictionary = {"players": {}, "teams": {}}


## Private "Friends" edition: builds exported with the `realnames` feature tag
## bundle res://private/real_roster.json and use it as the default names.
## Public builds exclude the private/ folder entirely.
const EDITION_ROSTER := "res://private/real_roster.json"


static func is_friends_edition() -> bool:
	return OS.has_feature("realnames") or OS.get_cmdline_user_args().has("--realnames")


static func _apply_edition_names() -> void:
	if not is_friends_edition() or not FileAccess.file_exists(EDITION_ROSTER):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(EDITION_ROSTER))
	if typeof(d) != TYPE_DICTIONARY:
		return
	for id in d.get("players", {}):
		if _players.has(id):
			_players[id]["name"] = str(d["players"][id])
	for id in d.get("teams", {}):
		if _team_by_id.has(id):
			_team_by_id[id]["name"] = str(d["teams"][id].get("name", _team_by_id[id]["name"]))
			_team_by_id[id]["short"] = str(d["teams"][id].get("short", id))


static func _load_overrides() -> void:
	if not FileAccess.file_exists(ROSTER_FILE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(ROSTER_FILE))
	if typeof(d) == TYPE_DICTIONARY:
		_apply_roster(d)


static func _apply_roster(d: Dictionary) -> int:
	var n := 0
	var ps = d.get("players", {})
	if typeof(ps) == TYPE_DICTIONARY:
		for id in ps:
			if _players.has(id) and typeof(ps[id]) == TYPE_STRING:
				var name: String = ps[id].strip_edges().substr(0, 32)
				if name != "":
					_players[id]["name"] = name
					_overrides["players"][id] = name
					n += 1
	var ts = d.get("teams", {})
	if typeof(ts) == TYPE_DICTIONARY:
		for id in ts:
			if _team_by_id.has(id) and typeof(ts[id]) == TYPE_DICTIONARY:
				var t: Dictionary = _team_by_id[id]
				var nm := str(ts[id].get("name", "")).strip_edges().substr(0, 32)
				var sh := str(ts[id].get("short", "")).strip_edges().to_upper().substr(0, 4)
				if nm != "":
					t["name"] = nm
				if sh != "":
					t["short"] = sh
				_overrides["teams"][id] = {"name": t["name"], "short": t["short"]}
				n += 1
	return n


static func save_roster() -> void:
	var f := FileAccess.open(ROSTER_FILE, FileAccess.WRITE)
	if f:
		f.store_string(export_roster())


static func set_player_name(id: String, name: String) -> void:
	ensure_loaded()
	name = name.strip_edges().substr(0, 32)
	if name == "" or name == _default_names.get(id, ""):
		_players[id]["name"] = _default_names[id]
		_overrides["players"].erase(id)
	else:
		_players[id]["name"] = name
		_overrides["players"][id] = name
	save_roster()


static func set_team_names(id: String, name: String, short: String) -> void:
	ensure_loaded()
	var t: Dictionary = _team_by_id[id]
	var def: Dictionary = _default_teams[id]
	t["name"] = name.strip_edges().substr(0, 32) if name.strip_edges() != "" else def["name"]
	t["short"] = short.strip_edges().to_upper().substr(0, 4) if short.strip_edges() != "" else def["short"]
	if t["name"] == def["name"] and t["short"] == def["short"]:
		_overrides["teams"].erase(id)
	else:
		_overrides["teams"][id] = {"name": t["name"], "short": t["short"]}
	save_roster()


static func default_player_name(id: String) -> String:
	ensure_loaded()
	return _default_names.get(id, "")


static func default_team(id: String) -> Dictionary:
	ensure_loaded()
	return _default_teams.get(id, {})


static func is_renamed(id: String) -> bool:
	return _overrides["players"].has(id) or _overrides["teams"].has(id)


static func override_count() -> int:
	return _overrides["players"].size() + _overrides["teams"].size()


static func export_roster() -> String:
	ensure_loaded()
	return JSON.stringify({"format": ROSTER_FORMAT, "players": _overrides["players"], "teams": _overrides["teams"]}, "  ")


## Import a roster file's text. Returns {ok, count, error}.
static func import_roster(text: String) -> Dictionary:
	ensure_loaded()
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != ROSTER_FORMAT:
		return {"ok": false, "count": 0, "error": "Not an Unsold roster file"}
	var n := _apply_roster(d)
	save_roster()
	return {"ok": true, "count": n, "error": ""}


static func reset_roster() -> void:
	ensure_loaded()
	for id in _default_names:
		_players[id]["name"] = _default_names[id]
	for id in _default_teams:
		_team_by_id[id]["name"] = _default_teams[id]["name"]
		_team_by_id[id]["short"] = _default_teams[id]["short"]
	_overrides = {"players": {}, "teams": {}}
	save_roster()


## Display code for a team (user may have renamed it).
static func team_short(id: String) -> String:
	ensure_loaded()
	return _team_by_id.get(id, {}).get("short", id)


static func overall(p: Dictionary) -> int:
	var bat: int = p["bat"]
	var bowl: int = p["bowl"]
	match p["role"]:
		"BAT":
			return bat
		"WK":
			return mini(99, bat + 2)
		"AR":
			return mini(99, int(round(maxi(bat, bowl) * 0.6 + mini(bat, bowl) * 0.4 + 6)))
		_:
			return bowl


static func player(id: String) -> Dictionary:
	ensure_loaded()
	return _players.get(id, {})


static func all_ids() -> Array:
	ensure_loaded()
	return _order.duplicate()


static func teams() -> Array:
	ensure_loaded()
	return _teams


static func team(id: String) -> Dictionary:
	ensure_loaded()
	return _team_by_id.get(id, {})


static func team_ids() -> Array:
	ensure_loaded()
	var ids := []
	for t in _teams:
		ids.append(t["id"])
	return ids


static func role_label(role: String) -> String:
	match role:
		"BAT": return "Batter"
		"WK": return "Wicket-keeper"
		"AR": return "All-rounder"
		"PACE": return "Fast bowler"
		"SPIN": return "Spinner"
	return role


## Prices are stored in lakh. 100 lakh = 1 crore.
static func fmt_price(lakh: int) -> String:
	if lakh >= 100:
		var cr := lakh / 100.0
		if is_equal_approx(cr, round(cr)):
			return "₹%d Cr" % int(cr)
		return "₹%s Cr" % String.num(cr, 2).trim_suffix("0")
	return "₹%d L" % lakh
