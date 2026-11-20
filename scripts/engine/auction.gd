class_name Auction
extends RefCounted
## Pure auction logic over the shared room state dictionary.
##
## Room state shape (identical locally and in Firebase):
##   meta:    {host, status, settings:{timer, win_mode, ai_fill, difficulty}, seed, created}
##   players: {uid: {name, team, joined, seen}}
##   teams:   {tid: {purse, squad:{pid: price}, ai: bool, xi: [pid]}}
##   auction: {lots:[pid], idx, round, pid, bid, bidder, ends, phase, passes:{tid:true}}
##   log:     {key: {pid, team, price, kind, n}}
## Functions here return *update dictionaries* of the form {"a/b/c": value}
## which stores apply as a multi-path update.

const SETTLE_PAUSE_MS := 1800
const SET_ORDER := ["MARQUEE", "BAT", "WK", "AR", "PACE", "SPIN", "U-BAT", "U-AR", "U-BOWL"]


static func set_of(p: Dictionary) -> String:
	if not p["capped"]:
		match p["role"]:
			"BAT", "WK": return "U-BAT"
			"AR": return "U-AR"
			_: return "U-BOWL"
	return p["role"]


static func set_label(s: String) -> String:
	match s:
		"MARQUEE": return "Marquee Set"
		"BAT": return "Capped Batters"
		"WK": return "Capped Wicket-keepers"
		"AR": return "Capped All-rounders"
		"PACE": return "Capped Fast Bowlers"
		"SPIN": return "Capped Spinners"
		"U-BAT": return "Uncapped Batters"
		"U-AR": return "Uncapped All-rounders"
		"U-BOWL": return "Uncapped Bowlers"
		"ACCEL": return "Accelerated Round"
	return s


## Lot order: a marquee set of the top-rated players, then sets by role.
## Within a set, stronger players tend to come first but with some shuffle.
static func build_lots(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ids := DB.all_ids()
	ids.sort_custom(func(a, b): return DB.player(a)["ovr"] > DB.player(b)["ovr"])
	var marquee := ids.slice(0, 12)
	var sets := {}
	for s in SET_ORDER:
		sets[s] = []
	for id in ids:
		if id in marquee:
			continue
		sets[set_of(DB.player(id))].append(id)
	sets["MARQUEE"] = marquee
	var lots := []
	for s in SET_ORDER:
		var arr: Array = sets[s]
		var keyed := []
		for id in arr:
			keyed.append([DB.player(id)["ovr"] + rng.randf_range(-8.0, 8.0), id])
		keyed.sort_custom(func(a, b): return a[0] > b[0])
		for k in keyed:
			lots.append(k[1])
	return lots


static func lot_set(state: Dictionary) -> String:
	var a: Dictionary = state.get("auction", {})
	if int(a.get("round", 1)) == 2:
		return "ACCEL"
	var pid: String = a.get("pid", "")
	if pid == "":
		return ""
	var lots: Array = a.get("lots", [])
	if lots.slice(0, 12).has(pid):
		return "MARQUEE"
	return set_of(DB.player(pid))


static func human_teams(state: Dictionary) -> Array:
	var out := []
	for uid in state.get("players", {}):
		var t: String = state["players"][uid].get("team", "")
		if t != "" and not out.has(t):
			out.append(t)
	return out


static func sold_ids(state: Dictionary) -> Dictionary:
	var sold := {}
	var teams: Dictionary = state.get("teams", {})
	for tid in teams:
		for pid in teams[tid].get("squad", {}):
			sold[pid] = tid
	return sold


## Initial team and auction nodes when the host starts the auction.
static func start_updates(state: Dictionary, now: int) -> Dictionary:
	var meta: Dictionary = state.get("meta", {})
	var seed: int = int(meta.get("seed", 1))
	var humans := human_teams(state)
	var ai_fill: bool = meta.get("settings", {}).get("ai_fill", true)
	var up := {}
	for tid in DB.team_ids():
		var active := ai_fill or humans.has(tid)
		if not active:
			continue
		up["teams/" + tid] = {"purse": Rules.PURSE, "ai": not humans.has(tid), "squad": {}}
	var lots := build_lots(seed)
	up["auction"] = {
		"lots": lots, "idx": 0, "round": 1, "pid": lots[0], "bid": 0, "bidder": "",
		"ends": now + timer_ms(state), "phase": "bidding", "passes": {}, "n": 0,
	}
	up["log"] = {}
	up["meta/status"] = "auction"
	return up


static func timer_ms(state: Dictionary) -> int:
	return int(state.get("meta", {}).get("settings", {}).get("timer", 10)) * 1000


## Humans are "done" with a lot when every human team has passed or is the top bidder.
## In online rooms, players who disconnected (no heartbeat for 15s) are ignored.
static func humans_done(state: Dictionary, now := 0) -> bool:
	var a: Dictionary = state.get("auction", {})
	var passes: Dictionary = a.get("passes", {})
	var teams: Dictionary = state.get("teams", {})
	var offline := {}
	if now > 0 and state.get("meta", {}).get("online", false):
		var players: Dictionary = state.get("players", {})
		for uid in players:
			if now - int(players[uid].get("seen", 0)) > 15000:
				offline[players[uid].get("team", "")] = true
	for tid in human_teams(state):
		if not teams.has(tid) or offline.has(tid):
			continue
		if passes.has(tid) or a.get("bidder", "") == tid:
			continue
		if not Rules.can_bid(teams[tid], DB.player(a.get("pid", "")), current_next(state)):
			continue  # cannot bid anyway
		return false
	return true


## True while at least one (online) human team is still in the bidding for
## this lot: it leads, or it hasn't passed and can afford the next bid.
static func humans_in_play(state: Dictionary, now := 0) -> bool:
	var a: Dictionary = state.get("auction", {})
	var passes: Dictionary = a.get("passes", {})
	var teams: Dictionary = state.get("teams", {})
	var offline := _offline_teams(state, now)
	var p := DB.player(a.get("pid", ""))
	for tid in human_teams(state):
		if not teams.has(tid) or offline.has(tid):
			continue
		if a.get("bidder", "") == tid:
			return true
		if passes.has(tid):
			continue
		if Rules.can_bid(teams[tid], p, current_next(state)):
			return true
	return false


static func _offline_teams(state: Dictionary, now: int) -> Dictionary:
	var offline := {}
	if now > 0 and state.get("meta", {}).get("online", false):
		var players: Dictionary = state.get("players", {})
		for uid in players:
			if now - int(players[uid].get("seen", 0)) > 15000:
				offline[players[uid].get("team", "")] = true
	return offline


static func current_next(state: Dictionary) -> int:
	var a: Dictionary = state.get("auction", {})
	var p := DB.player(a.get("pid", ""))
	return Rules.next_bid(int(a.get("bid", 0)), int(p.get("base", 0)), a.get("bidder", "") != "")


## Applies a bid to an auction node copy. Returns the new node or null if invalid.
## Used inside transactions, so it must only depend on the node and the team.
static func apply_bid(a, tid: String, amount: int, team: Dictionary, now: int, timer: int):
	if a == null or typeof(a) != TYPE_DICTIONARY:
		return null
	if a.get("phase", "") != "bidding" or a.get("bidder", "") == tid:
		return null
	if now > int(a.get("ends", 0)) + 300:
		return null
	var p := DB.player(a.get("pid", ""))
	var expected := Rules.next_bid(int(a.get("bid", 0)), int(p.get("base", 0)), a.get("bidder", "") != "")
	# At least the next increment (AI may jump-bid to settle a bidding war at once).
	if amount < expected:
		return null
	if not Rules.can_bid(team, p, amount):
		return null
	var n: Dictionary = a.duplicate(true)
	n["bid"] = amount
	n["bidder"] = tid
	n["ends"] = maxi(int(a.get("ends", 0)), now + timer)
	n["n"] = int(a.get("n", 0)) + 1
	var passes: Dictionary = n.get("passes", {})
	passes.erase(tid)
	n["passes"] = passes
	return n


## Close the current lot as sold or unsold.
static func settle_updates(state: Dictionary, now: int) -> Dictionary:
	var a: Dictionary = state["auction"]
	var pid: String = a["pid"]
	var bidder: String = a.get("bidder", "")
	var up := {}
	var key := "e%04d" % (state.get("log", {}).size())
	if bidder != "":
		var price := int(a["bid"])
		var team: Dictionary = state["teams"][bidder]
		up["teams/%s/purse" % bidder] = int(team["purse"]) - price
		up["teams/%s/squad/%s" % [bidder, pid]] = price
		up["log/" + key] = {"pid": pid, "team": bidder, "price": price, "kind": "sold"}
		up["auction/phase"] = "sold"
	else:
		up["log/" + key] = {"pid": pid, "team": "", "price": 0, "kind": "unsold"}
		up["auction/phase"] = "unsold"
	up["auction/ends"] = now + SETTLE_PAUSE_MS
	return up


## Move on after a settled lot: next lot, accelerated round, or end of auction.
static func advance_updates(state: Dictionary, now: int) -> Dictionary:
	var a: Dictionary = state["auction"]
	var lots: Array = a.get("lots", [])
	var idx := int(a.get("idx", 0)) + 1
	var rnd := int(a.get("round", 1))
	var sold := sold_ids(state)
	# Skip players nobody can still buy (e.g. all squads full).
	if not any_team_needs(state):
		return finish_updates(state)
	if idx < lots.size():
		return open_lot(state, lots, idx, rnd, now)
	if rnd == 1:
		var accel := accelerated_pool(state, sold)
		if accel.size() > 0:
			return open_lot(state, accel, 0, 2, now)
	return finish_updates(state)


static func open_lot(state: Dictionary, lots: Array, idx: int, rnd: int, now: int) -> Dictionary:
	return {"auction": {
		"lots": lots, "idx": idx, "round": rnd, "pid": lots[idx], "bid": 0, "bidder": "",
		"ends": now + timer_ms(state), "phase": "bidding", "passes": {}, "n": 0,
	}}


static func any_team_needs(state: Dictionary) -> bool:
	for tid in state.get("teams", {}):
		if Rules.squad_count(state["teams"][tid]) < Rules.MAX_SQUAD:
			return true
	return false


## Unsold players worth a second look, best first, capped to keep the round short.
static func accelerated_pool(state: Dictionary, sold: Dictionary) -> Array:
	var need := 0
	for tid in state.get("teams", {}):
		need += maxi(0, Rules.MIN_SQUAD - Rules.squad_count(state["teams"][tid]))
	var pool := []
	for id in DB.all_ids():
		if not sold.has(id):
			pool.append(id)
	pool.sort_custom(func(x, y): return DB.player(x)["ovr"] > DB.player(y)["ovr"])
	return pool.slice(0, mini(pool.size(), clampi(need + 10, 10, 40)))


## End of auction: fill short squads at base price from the leftover pool.
static func finish_updates(state: Dictionary) -> Dictionary:
	var up := {}
	var teams: Dictionary = state["teams"].duplicate(true)
	var sold := sold_ids(state)
	var pool := []
	for id in DB.all_ids():
		if not sold.has(id):
			pool.append(id)
	pool.sort_custom(func(x, y): return DB.player(x)["ovr"] > DB.player(y)["ovr"])
	var tids: Array = teams.keys()
	tids.sort()
	var changed := true
	while changed:
		changed = false
		for tid in tids:
			var t: Dictionary = teams[tid]
			if Rules.squad_count(t) >= Rules.MIN_SQUAD:
				continue
			var role := AI.most_needed_role(t)
			var pick := ""
			for id in pool:
				var p := DB.player(id)
				if int(p["base"]) > int(t["purse"]):
					continue
				if p["overseas"] and Rules.overseas_count(t) >= Rules.MAX_OVERSEAS:
					continue
				if pick == "" or p["role"] == role:
					pick = id
					if p["role"] == role:
						break
			if pick == "":
				continue
			var price := int(DB.player(pick)["base"])
			if not t.has("squad"):
				t["squad"] = {}
			t["squad"][pick] = price
			t["purse"] = int(t["purse"]) - price
			pool.erase(pick)
			up["teams/%s/squad/%s" % [tid, pick]] = price
			up["teams/%s/purse" % tid] = t["purse"]
			changed = true
	for tid in tids:
		up["teams/%s/xi" % tid] = XI.best_xi(teams[tid].get("squad", {}).keys())
	up["auction/phase"] = "done"
	up["meta/status"] = "review"
	return up


## Apply a multi-path update dictionary to a state dictionary in place.
## Null values delete. Used by the local store and to mirror Firebase events.
static func apply_updates(state: Dictionary, updates: Dictionary) -> void:
	for path in updates:
		put_path(state, path, updates[path])


static func put_path(root: Dictionary, path: String, value) -> void:
	var parts := Array(path.strip_edges().trim_prefix("/").trim_suffix("/").split("/", false))
	if parts.is_empty():
		root.clear()
		if typeof(value) == TYPE_DICTIONARY:
			root.merge(value.duplicate(true), true)
		return
	var node = root
	for i in parts.size() - 1:
		var k = parts[i]
		var nxt = _child(node, k)
		if typeof(nxt) != TYPE_DICTIONARY and typeof(nxt) != TYPE_ARRAY:
			nxt = {}
			_set_child(node, k, nxt)
		node = nxt
	var last = parts[parts.size() - 1]
	if value == null:
		if typeof(node) == TYPE_DICTIONARY:
			node.erase(last)
		elif typeof(node) == TYPE_ARRAY and last.is_valid_int() and int(last) < node.size():
			node[int(last)] = null
	else:
		_set_child(node, last, value.duplicate(true) if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY] else value)


static func _child(node, k: String):
	if typeof(node) == TYPE_DICTIONARY:
		return node.get(k)
	if typeof(node) == TYPE_ARRAY and k.is_valid_int() and int(k) < node.size():
		return node[int(k)]
	return null


static func _set_child(node, k: String, v) -> void:
	if typeof(node) == TYPE_DICTIONARY:
		node[k] = v
	elif typeof(node) == TYPE_ARRAY and k.is_valid_int():
		var i := int(k)
		while node.size() <= i:
			node.append(null)
		node[i] = v


static func read_path(root, path: String):
	var node = root
	for k in path.trim_prefix("/").split("/", false):
		node = _child(node, k)
		if node == null:
			return null
	return node
