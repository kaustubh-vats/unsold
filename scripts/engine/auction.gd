class_name Auction
extends RefCounted
## Pure auction logic over the shared room state dictionary.
##
## Room state shape (identical locally and in Firebase):
##   meta:    {host, status, settings:{timer, win_mode, ai_fill, difficulty, mode, mini_n},
##            seed, created, pool:[pid] (mini auction only)}
##   players: {uid: {name, team, joined, seen}}
##   teams:   {tid: {purse, squad:{pid: price}, ai: bool, xi: [pid], lim (mini only)}}
##   auction: {lots:[pid], idx, round, pid, bid, bidder, ends, phase, passes:{tid:true}}
##   log:     {key: {pid, team, price, kind, n}}
## Functions here return *update dictionaries* of the form {"a/b/c": value}
## which stores apply as a multi-path update.

const SETTLE_PAUSE_MS := 1800
const SET_ORDER := ["MARQUEE", "BAT", "WK", "AR", "PACE", "SPIN", "U-BAT", "U-AR", "U-BOWL"]

## Mini auction ("quick play"): the host picks how many players go under the
## hammer; the algorithm draws them at random and sizes everything else.
const MINI_MIN := 50
const MINI_MAX := 150
const MINI_STEP := 10
const MINI_DEFAULT := 80


static func is_mini(state: Dictionary) -> bool:
	return state.get("meta", {}).get("settings", {}).get("mode", "full") == "mini"


## Smallest pool that still gives every human franchise a real squad.
static func mini_min(humans: int) -> int:
	return clampi(ceili(humans * 14 / float(MINI_STEP)) * MINI_STEP, MINI_MIN, MINI_MAX)


## Everything the algorithm decides for a mini auction of n players:
## {n, teams, min, max, os, purse}. With bots on, fewer franchises take part so
## each still gets ~15 players to choose from; squads shrink to 11-18 and the
## purse and overseas cap shrink with them.
static func mini_plan(n: int, humans: int, ai_fill: bool) -> Dictionary:
	n = clampi(n, mini_min(humans), MINI_MAX)
	var t := humans
	if ai_fill:
		t = clampi(roundi(n / 16.0), maxi(4, humans), 10)
	t = maxi(t, 1)
	var per := float(n) / t
	var mn := 11
	var mx := clampi(int(per * 1.15), 13, 18)
	var os := clampi(roundi(mx * 0.32), 4, 8)
	var purse := roundi(Rules.PURSE * (mn + mx) / 2.0 / 21.5 / 500.0) * 500
	return {"n": n, "teams": t, "min": mn, "max": mx, "os": os, "purse": purse}


## The mini plan for this room as it stands (humans with a franchise picked).
static func plan_for(state: Dictionary) -> Dictionary:
	var st: Dictionary = state.get("meta", {}).get("settings", {})
	var ai_fill: bool = st.get("ai_fill", true)
	if not state.get("meta", {}).get("online", false):
		ai_fill = true
	return mini_plan(int(st.get("mini_n", MINI_DEFAULT)), maxi(1, human_teams(state).size()), ai_fill)


## Random but balanced draw of n players: each role keeps its share of the full
## pool (with enough keepers to go round), and within a role one player is drawn
## from each band of ratings, so there are stars, solid pros and fringe picks.
static func mini_pool(seed: int, n: int, teams: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|pool" % seed)
	var all := DB.all_ids()
	var by := {"BAT": [], "WK": [], "AR": [], "PACE": [], "SPIN": []}
	for id in all:
		by[DB.player(id)["role"]].append(id)
	var quota := {}
	var sum := 0
	for r in by:
		quota[r] = mini(by[r].size(), maxi(1, roundi(float(n) * by[r].size() / all.size())))
		sum += quota[r]
	var wk_min := mini(by["WK"].size(), ceili(teams * 1.5))
	if quota["WK"] < wk_min:
		sum += wk_min - quota["WK"]
		quota["WK"] = wk_min
	var order := ["PACE", "BAT", "AR", "SPIN", "WK"]
	var i := 0
	while sum < n and i < 1000:
		var r: String = order[i % order.size()]
		if quota[r] < by[r].size():
			quota[r] += 1
			sum += 1
		i += 1
	i = 0
	while sum > n and i < 1000:
		var r2: String = order[i % order.size()]
		if quota[r2] > (wk_min if r2 == "WK" else 1):
			quota[r2] -= 1
			sum -= 1
		i += 1
	var out := []
	for r in by:
		var arr: Array = by[r].duplicate()
		arr.sort_custom(func(x, y): return DB.player(x)["ovr"] > DB.player(y)["ovr"])
		var q: int = quota[r]
		for k in q:
			var lo: int = k * arr.size() / q
			var hi: int = maxi(lo, (k + 1) * arr.size() / q - 1)
			out.append(arr[rng.randi_range(lo, hi)])
	return out


## Every player in this auction: the mini pool, or the whole database.
static func pool_ids(state: Dictionary) -> Array:
	var pool = state.get("meta", {}).get("pool", null)
	if typeof(pool) == TYPE_ARRAY and not pool.is_empty():
		return pool
	return DB.all_ids()


## How many lots open the auction as the marquee set: 12 in a full auction,
## fewer in a mini one.
static func marquee_n(total: int) -> int:
	return mini(12, maxi(4, total / 16))


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
static func build_lots(seed: int, pool := []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ids: Array = (pool if not pool.is_empty() else DB.all_ids()).duplicate()
	ids.sort_custom(func(a, b): return DB.player(a)["ovr"] > DB.player(b)["ovr"])
	# The marquee set is 12 of the top ~22 players (fewer in a mini auction),
	# different every auction.
	var mq := marquee_n(ids.size())
	var cands := ids.slice(0, roundi(mq * 1.8))
	var keyed_m := []
	for id in cands:
		keyed_m.append([DB.player(id)["ovr"] + rng.randf_range(-7.0, 7.0), id])
	keyed_m.sort_custom(func(a, b): return a[0] > b[0])
	var marquee := keyed_m.slice(0, mq).map(func(k): return k[1])
	_shuffle(marquee, rng)
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
		if s == "MARQUEE":
			lots += arr
			continue
		var keyed := []
		for id in arr:
			keyed.append([DB.player(id)["ovr"] + rng.randf_range(-14.0, 14.0), id])
		keyed.sort_custom(func(a, b): return a[0] > b[0])
		for k in keyed:
			lots.append(k[1])
	return lots


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func lot_set(state: Dictionary) -> String:
	var a: Dictionary = state.get("auction", {})
	if int(a.get("round", 1)) == 2:
		return "ACCEL"
	var pid: String = a.get("pid", "")
	if pid == "":
		return ""
	var lots: Array = a.get("lots", [])
	if lots.slice(0, marquee_n(lots.size())).has(pid):
		return "MARQUEE"
	return set_of(DB.player(pid))


## The set of the lot at index i ("MARQUEE", "BAT", … or "ACCEL" in round 2).
static func set_at(lots: Array, i: int, rnd: int) -> String:
	if rnd == 2:
		return "ACCEL"
	if i < 0 or i >= lots.size():
		return ""
	if i < marquee_n(lots.size()):
		return "MARQUEE"
	return set_of(DB.player(lots[i]))


## True when the current lot is the first of its set (time to announce it).
static func set_starts(state: Dictionary) -> bool:
	var a: Dictionary = state.get("auction", {})
	var lots: Array = a.get("lots", [])
	var idx := int(a.get("idx", 0))
	var rnd := int(a.get("round", 1))
	return idx == 0 or set_at(lots, idx, rnd) != set_at(lots, idx - 1, rnd)


## Every player in the current set, in lot order, with where each one stands:
## [{pid, status: "sold"|"unsold"|"live"|"next", team, price}].
static func set_players(state: Dictionary) -> Array:
	var a: Dictionary = state.get("auction", {})
	var lots: Array = a.get("lots", [])
	var idx := int(a.get("idx", 0))
	var rnd := int(a.get("round", 1))
	var cur := set_at(lots, idx, rnd)
	var sold := sold_ids(state)
	var prices := {}
	for tid in state.get("teams", {}):
		var sq: Dictionary = state["teams"][tid].get("squad", {})
		for pid in sq:
			prices[pid] = int(sq[pid])
	var phase: String = a.get("phase", "")
	var out := []
	for i in lots.size():
		if set_at(lots, i, rnd) != cur:
			continue
		var pid: String = lots[i]
		var st := "next"
		if sold.has(pid):
			st = "sold"
		elif i < idx or (i == idx and phase == "unsold"):
			st = "unsold"
		elif i == idx:
			st = "live"
		out.append({"pid": pid, "status": st, "team": sold.get(pid, ""), "price": prices.get(pid, 0)})
	return out


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
	var pool := []
	if is_mini(state):
		# Quick play: the humans plus a random few AI franchises, a random
		# pool, and squad limits / purse sized to fit.
		var plan := plan_for(state)
		var lim := {"purse": plan["purse"], "min": plan["min"], "max": plan["max"], "os": plan["os"]}
		var picked: Array = humans.duplicate()
		var others: Array = DB.team_ids().filter(func(t): return not humans.has(t))
		var trng := RandomNumberGenerator.new()
		trng.seed = hash("%d|teams" % seed)
		_shuffle(others, trng)
		while picked.size() < int(plan["teams"]) and not others.is_empty():
			picked.append(others.pop_back())
		for tid in picked:
			up["teams/" + tid] = {"purse": plan["purse"], "ai": not humans.has(tid), "squad": {}, "lim": lim}
		pool = mini_pool(seed, int(plan["n"]), picked.size())
		up["meta/pool"] = pool
	else:
		up["meta/pool"] = null
		for tid in DB.team_ids():
			var active := ai_fill or humans.has(tid)
			if not active:
				continue
			up["teams/" + tid] = {"purse": Rules.PURSE, "ai": not humans.has(tid), "squad": {}}
	var lots := build_lots(seed, pool)
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


## Multiplayer fast-forward vote: [votes, needed]. Every human team that is
## still connected has to tap ▶▶ before the lot skips to its final bid.
static func ff_votes(state: Dictionary, now := 0) -> Array:
	var votes: Dictionary = state.get("auction", {}).get("ff", {})
	var teams: Dictionary = state.get("teams", {})
	var offline := _offline_teams(state, now)
	var have := 0
	var need := 0
	for tid in human_teams(state):
		if not teams.has(tid) or offline.has(tid):
			continue
		need += 1
		if votes.has(tid):
			have += 1
	return [have, need]


static func ff_agreed(state: Dictionary, now := 0) -> bool:
	var v := ff_votes(state, now)
	return v[1] > 0 and v[0] >= v[1]


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
		if Rules.squad_count(state["teams"][tid]) < Rules.max_squad(state["teams"][tid]):
			return true
	return false


## Unsold players worth a second look, best first, capped to keep the round short.
static func accelerated_pool(state: Dictionary, sold: Dictionary) -> Array:
	var need := 0
	for tid in state.get("teams", {}):
		need += maxi(0, Rules.min_squad(state["teams"][tid]) - Rules.squad_count(state["teams"][tid]))
	var pool := []
	for id in pool_ids(state):
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
	for id in pool_ids(state):
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
			if Rules.squad_count(t) >= Rules.min_squad(t):
				continue
			var role := AI.most_needed_role(t)
			var pick := ""
			for id in pool:
				var p := DB.player(id)
				if int(p["base"]) > int(t["purse"]):
					continue
				if p["overseas"] and Rules.overseas_count(t) >= Rules.max_overseas(t):
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
