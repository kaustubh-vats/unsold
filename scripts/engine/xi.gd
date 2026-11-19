class_name XI
extends RefCounted
## Playing XI selection and validation.

const BOWL_OPTION := 60  # bowl rating needed to count as a bowling option


static func is_bowler(p: Dictionary) -> bool:
	return int(p["bowl"]) >= BOWL_OPTION


static func bowling_options(xi: Array) -> int:
	var n := 0
	for id in xi:
		if is_bowler(DB.player(id)):
			n += 1
	return n


## Overseas players allowed in the XI. Normally 4, but if the squad doesn't have
## enough domestic players to field 11, the shortfall may be filled from overseas.
static func allowed_overseas(squad: Array) -> int:
	var domestic := squad.filter(func(id): return not DB.player(id)["overseas"]).size()
	return maxi(Rules.MAX_OVERSEAS_XI, mini(11, squad.size()) - domestic)


## Returns a list of problems with a proposed XI (empty = valid).
## Requirements are relative to the squad, so a squad without a keeper or with
## few bowlers can still field a (weaker) legal XI instead of getting stuck.
static func problems(xi: Array, squad: Array) -> Array:
	var out := []
	var need := mini(11, squad.size())
	var squad_wk := squad.any(func(id): return DB.player(id)["role"] == "WK")
	var max_os := allowed_overseas(squad)
	var need_bowl := mini(5, bowling_options(squad))
	if xi.size() != need:
		out.append("Pick %d players (have %d)" % [need, xi.size()])
	var os := 0
	var wk := 0
	for id in xi:
		var p := DB.player(id)
		if p["overseas"]:
			os += 1
		if p["role"] == "WK":
			wk += 1
	if os > max_os:
		out.append("Max %d overseas in XI" % max_os)
	if wk == 0 and squad_wk:
		out.append("Need a wicket-keeper")
	if bowling_options(xi) < need_bowl:
		out.append("Need %d bowling options" % need_bowl)
	return out


## Greedy best XI: a keeper, five bowling options, then the best of the rest,
## respecting the overseas limit, followed by a swap-improvement pass.
static func best_xi(squad: Array) -> Array:
	var pool := squad.duplicate()
	pool.sort_custom(func(a, b): return DB.player(a)["ovr"] > DB.player(b)["ovr"])
	var xi := []
	var os := [0]
	var max_os := allowed_overseas(squad)
	var take := func(id) -> bool:
		var p := DB.player(id)
		if xi.has(id) or xi.size() >= 11:
			return false
		if p["overseas"] and os[0] >= max_os:
			return false
		xi.append(id)
		if p["overseas"]:
			os[0] += 1
		return true
	# 1. Best wicket-keeper.
	for id in pool:
		if DB.player(id)["role"] == "WK" and take.call(id):
			break
	# 2. Bowling options: prefer genuine bowlers and all-rounders by bowling rating.
	var bowlers := pool.filter(func(id): return is_bowler(DB.player(id)))
	bowlers.sort_custom(func(a, b): return DB.player(a)["bowl"] > DB.player(b)["bowl"])
	for id in bowlers:
		if bowling_options(xi) >= 5:
			break
		take.call(id)
	# 3. Fill with best overall.
	for id in pool:
		take.call(id)
	_repair_bowling(xi, squad)
	return order_batting(xi)


## If the XI is short of bowling options, swap the weakest non-bowlers for the
## best available bowlers while keeping the keeper and the overseas limit.
static func _repair_bowling(xi: Array, squad: Array) -> void:
	var need := mini(5, bowling_options(squad))
	for attempt in 11:
		if bowling_options(xi) >= need:
			return
		var bench := squad.filter(func(id): return not xi.has(id) and is_bowler(DB.player(id)))
		bench.sort_custom(func(a, b): return DB.player(a)["bowl"] > DB.player(b)["bowl"])
		var os := xi.filter(func(id): return DB.player(id)["overseas"]).size()
		var wk_count := xi.filter(func(id): return DB.player(id)["role"] == "WK").size()
		var done := false
		for cand in bench:
			var cp := DB.player(cand)
			# Who can leave: non-bowlers (keep the only keeper), weakest first.
			var out_opts := xi.filter(func(id):
				var p := DB.player(id)
				if is_bowler(p):
					return false
				if p["role"] == "WK" and wk_count <= 1:
					return false
				if cp["overseas"] and os >= allowed_overseas(squad) and not p["overseas"]:
					return false
				return true)
			if out_opts.is_empty():
				continue
			out_opts.sort_custom(func(a, b): return DB.player(a)["ovr"] < DB.player(b)["ovr"])
			xi.erase(out_opts[0])
			xi.append(cand)
			done = true
			break
		if not done:
			return


## Batting order: openers first, then best batters, all-rounders, bowlers by batting.
static func order_batting(xi: Array) -> Array:
	var keyed := []
	for id in xi:
		var p := DB.player(id)
		var k := float(p["bat"])
		if p["trait"] == "op":
			k += 40
		elif p["trait"] == "anc":
			k += 25
		elif p["trait"] == "fin":
			k -= 8
		if p["role"] in ["PACE", "SPIN"]:
			k -= 60
		keyed.append([k, id])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	return keyed.map(func(k): return k[1])


## Bowlers ordered best first, plus how many overs each may bowl (max 4, total 20).
static func bowling_plan(xi: Array) -> Array:
	var bowlers := xi.duplicate()
	bowlers.sort_custom(func(a, b): return DB.player(a)["bowl"] > DB.player(b)["bowl"])
	return bowlers.slice(0, 6)
