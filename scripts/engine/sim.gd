class_name Sim
extends RefCounted
## Deterministic ball-by-ball T20 match and season simulator.
## Given the same seed and XIs, every device produces identical results.


static func _rng(seed_str: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_str)
	return r


## Choose the bowler for an over: powerplay and death specialists in their phases,
## spinners in the middle, max 4 overs each, no consecutive overs.
static func _pick_bowler(attack: Array, overs: Dictionary, over: int, last: String) -> String:
	var best := ""
	var best_k := -1e9
	for id in attack:
		if int(overs.get(id, 0)) >= 4 or id == last:
			continue
		var p := DB.player(id)
		var k := float(p["bowl"])
		if over < 6 and p["trait"] == "pp":
			k += 8
		elif over >= 16 and p["trait"] == "dth":
			k += 10
		elif over >= 6 and over < 16 and p["role"] == "SPIN":
			k += 6
		# Spread the overs so the best bowler is not used up early.
		k -= float(overs.get(id, 0)) * 3.0
		if k > best_k:
			best_k = k
			best = id
	if best == "":
		for id in attack:
			if id != last:
				return id
		return attack[0]
	return best


static func innings(bat_xi: Array, bowl_xi: Array, target: int, rng: RandomNumberGenerator) -> Dictionary:
	var order := XI.order_batting(bat_xi)
	var attack := bowl_xi.duplicate()
	attack.sort_custom(func(a, b): return DB.player(a)["bowl"] > DB.player(b)["bowl"])
	attack = attack.slice(0, mini(7, attack.size()))
	var cards := []
	for id in order:
		cards.append({"id": id, "r": 0, "b": 0, "4s": 0, "6s": 0, "out": false, "bat": false})
	var bowl := {}
	var runs := 0
	var wkts := 0
	var balls := 0
	var striker := 0
	var non := 1
	var next_in := 2
	if cards.size() > 0:
		cards[0]["bat"] = true
	if cards.size() > 1:
		cards[1]["bat"] = true
	var overs := {}
	var last := ""
	var max_wkts := mini(10, order.size() - 1)
	for over in 20:
		if wkts >= max_wkts or (target > 0 and runs >= target):
			break
		var bowler := _pick_bowler(attack, overs, over, last)
		last = bowler
		overs[bowler] = int(overs.get(bowler, 0)) + 1
		if not bowl.has(bowler):
			bowl[bowler] = {"id": bowler, "balls": 0, "r": 0, "w": 0}
		var bp := DB.player(bowler)
		var legal := 0
		while legal < 6:
			if wkts >= max_wkts or (target > 0 and runs >= target):
				break
			# Wides / no-balls.
			if rng.randf() < 0.035:
				runs += 1
				bowl[bowler]["r"] += 1
				continue
			var sp := DB.player(order[striker])
			var d := (float(sp["bat"]) - float(bp["bowl"])) / 100.0
			var agg := 1.0
			if over < 6:
				agg = 1.1
			elif over >= 16:
				agg = 1.3
			else:
				agg = 0.95
			if sp["trait"] == "fin" and over >= 15:
				agg += 0.1
			if target > 0:
				var left := 120 - balls
				var rrr := float(target - runs) / maxf(1.0, left) * 6.0
				if rrr > 10.0:
					agg += minf(0.6, (rrr - 10.0) * 0.08)
				elif rrr < 6.0:
					agg -= 0.15
			var p_out := clampf(0.048 - 0.06 * d + 0.03 * (agg - 1.0), 0.012, 0.17)
			legal += 1
			balls += 1
			bowl[bowler]["balls"] += 1
			cards[striker]["b"] += 1
			if rng.randf() < p_out:
				wkts += 1
				bowl[bowler]["w"] += 1
				cards[striker]["out"] = true
				if next_in < cards.size() and wkts < max_wkts:
					striker = next_in
					cards[striker]["bat"] = true
					next_in += 1
				continue
			var w := [
				maxf(0.05, 0.36 - 0.25 * d - 0.06 * (agg - 1.0)),
				0.36,
				0.07,
				0.006,
				maxf(0.02, 0.12 + 0.12 * d + 0.08 * (agg - 1.0)),
				maxf(0.008, 0.05 + 0.08 * d + 0.07 * (agg - 1.0)),
			]
			var vals := [0, 1, 2, 3, 4, 6]
			var tot := 0.0
			for x in w:
				tot += x
			var r := rng.randf() * tot
			var res := 0
			for i in w.size():
				r -= w[i]
				if r <= 0.0:
					res = vals[i]
					break
			runs += res
			bowl[bowler]["r"] += res
			cards[striker]["r"] += res
			if res == 4:
				cards[striker]["4s"] += 1
			elif res == 6:
				cards[striker]["6s"] += 1
			if res % 2 == 1:
				var t := striker
				striker = non
				non = t
		# End of over: swap strike.
		var t2 := striker
		striker = non
		non = t2
	return {
		"runs": runs, "wkts": wkts, "balls": balls,
		"bat": cards.filter(func(c): return c["bat"]),
		"bowl": bowl.values(),
		"all_out": wkts >= max_wkts,
	}


static func overs_str(balls: int) -> String:
	return "%d.%d" % [balls / 6, balls % 6] if balls % 6 != 0 else str(balls / 6)


static func score_str(inn: Dictionary) -> String:
	return "%d/%d (%s)" % [inn["runs"], inn["wkts"], overs_str(inn["balls"])]


## Simulate one match. Returns a summary plus full innings for scorecards.
static func play_match(a: String, b: String, xi_a: Array, xi_b: Array, seed_str: String) -> Dictionary:
	var rng := _rng(seed_str)
	var toss := a if rng.randf() < 0.5 else b
	var chase := rng.randf() < 0.6
	var first := toss if not chase else (b if toss == a else a)
	var second := b if first == a else a
	var xi := {a: xi_a, b: xi_b}
	var i1 := innings(xi[first], xi[second], -1, rng)
	var i2 := innings(xi[second], xi[first], i1["runs"] + 1, rng)
	var winner := ""
	var margin := ""
	if i2["runs"] > i1["runs"]:
		winner = second
		margin = "by %d wickets" % (mini(10, xi[second].size() - 1) - int(i2["wkts"]))
	elif i1["runs"] > i2["runs"]:
		winner = first
		margin = "by %d runs" % (int(i1["runs"]) - int(i2["runs"]))
	else:
		# Super over: decided by a strength-weighted coin flip.
		var sa := team_strength(xi[first])
		var sb := team_strength(xi[second])
		winner = first if rng.randf() < sa / (sa + sb) else second
		margin = "in the Super Over"
	# Player of the match: best combined impact on the winning side.
	var pom := ""
	var best := -1.0
	for inn in [i1, i2]:
		for c in inn["bat"]:
			var imp: float = c["r"] + (10.0 if c["r"] >= 50 else 0.0)
			if xi[winner].has(c["id"]) and imp > best:
				best = imp
				pom = c["id"]
		for bw in inn["bowl"]:
			var imp2: float = bw["w"] * 20.0 - bw["r"] * 0.3 + 10.0
			if xi[winner].has(bw["id"]) and imp2 > best:
				best = imp2
				pom = bw["id"]
	return {
		"a": a, "b": b, "toss": toss, "first": first, "second": second,
		"i1": i1, "i2": i2, "s1": score_str(i1), "s2": score_str(i2),
		"winner": winner, "margin": margin, "pom": pom,
	}


static func team_strength(xi: Array) -> float:
	var r := Score.rate({"squad": {}, "purse": Rules.PURSE}, xi)
	return maxf(1.0, float(r["batting"]) + float(r["bowling"]))


## Full season. teams: {tid: xi}. Returns {table, matches, playoffs, champion, runner_up}.
static func season(teams: Dictionary, seed: int) -> Dictionary:
	var ids: Array = teams.keys()
	ids.sort()
	var table := {}
	for t in ids:
		table[t] = {"team": t, "p": 0, "w": 0, "l": 0, "pts": 0, "rf": 0, "bf": 0, "ra": 0, "ba": 0}
	var fixtures := []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			fixtures.append([ids[i], ids[j]])
	if ids.size() <= 4:
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				fixtures.append([ids[j], ids[i]])
	# Shuffle fixtures deterministically so the season feels like a calendar.
	var rng := _rng("%d|fixtures" % seed)
	for i in range(fixtures.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = fixtures[i]
		fixtures[i] = fixtures[j]
		fixtures[j] = tmp
	var matches := []
	var n := 0
	for f in fixtures:
		var m := play_match(f[0], f[1], teams[f[0]], teams[f[1]], "%d|m%d" % [seed, n])
		m["stage"] = "League %d" % (n + 1)
		matches.append(m)
		_record(table, m)
		n += 1
	var rows := table.values()
	for r in rows:
		r["nrr"] = nrr(r)
	rows.sort_custom(func(x, y):
		if x["pts"] != y["pts"]:
			return x["pts"] > y["pts"]
		return x["nrr"] > y["nrr"])
	var playoffs := []
	var champion := ""
	var runner := ""
	if rows.size() >= 4:
		var t1: String = rows[0]["team"]
		var t2: String = rows[1]["team"]
		var t3: String = rows[2]["team"]
		var t4: String = rows[3]["team"]
		var q1 := play_match(t1, t2, teams[t1], teams[t2], "%d|q1" % seed)
		q1["stage"] = "Qualifier 1"
		var el := play_match(t3, t4, teams[t3], teams[t4], "%d|el" % seed)
		el["stage"] = "Eliminator"
		var q1_loser: String = q1["a"] if q1["winner"] == q1["b"] else q1["b"]
		var q2 := play_match(q1_loser, el["winner"], teams[q1_loser], teams[el["winner"]], "%d|q2" % seed)
		q2["stage"] = "Qualifier 2"
		var fin := play_match(q1["winner"], q2["winner"], teams[q1["winner"]], teams[q2["winner"]], "%d|final" % seed)
		fin["stage"] = "Final"
		playoffs = [q1, el, q2, fin]
		champion = fin["winner"]
		runner = fin["a"] if champion == fin["b"] else fin["b"]
	elif rows.size() >= 2:
		var f1: String = rows[0]["team"]
		var f2: String = rows[1]["team"]
		var fin2 := play_match(f1, f2, teams[f1], teams[f2], "%d|final" % seed)
		fin2["stage"] = "Final"
		playoffs = [fin2]
		champion = fin2["winner"]
		runner = f2 if champion == f1 else f1
	elif rows.size() == 1:
		champion = rows[0]["team"]
	return {"table": rows, "matches": matches, "playoffs": playoffs, "champion": champion, "runner_up": runner}


static func _record(table: Dictionary, m: Dictionary) -> void:
	var first: String = m["first"]
	var second: String = m["second"]
	var i1: Dictionary = m["i1"]
	var i2: Dictionary = m["i2"]
	# NRR rule: an all-out side counts as having faced the full 20 overs.
	var b1: int = 120 if i1["all_out"] else int(i1["balls"])
	var b2: int = 120 if i2["all_out"] else int(i2["balls"])
	table[first]["rf"] += i1["runs"]
	table[first]["bf"] += b1
	table[first]["ra"] += i2["runs"]
	table[first]["ba"] += b2
	table[second]["rf"] += i2["runs"]
	table[second]["bf"] += b2
	table[second]["ra"] += i1["runs"]
	table[second]["ba"] += b1
	for t in [first, second]:
		table[t]["p"] += 1
		if m["winner"] == t:
			table[t]["w"] += 1
			table[t]["pts"] += 2
		else:
			table[t]["l"] += 1


static func nrr(r: Dictionary) -> float:
	if r["bf"] == 0 or r["ba"] == 0:
		return 0.0
	return snappedf(float(r["rf"]) / (r["bf"] / 6.0) - float(r["ra"]) / (r["ba"] / 6.0), 0.001)
