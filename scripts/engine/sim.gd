class_name Sim
extends RefCounted
## Ball-by-ball T20 match and season simulator.
##
## Every match is seeded from the room seed, so all devices in a multiplayer
## room compute the identical season; a fresh seed each game gives a different
## season every time.
##
## Per match: venue (home side), pitch type, dew, toss + decision, and a form
## rating for every player on the day. Per ball: the batter's effective rating
## (skill + form + settling in + role/phase fit + home) against the bowler's
## (skill + form + pitch + phase specialism − dew) sets the odds of each outcome
## (dot, 1, 2, 3, 4, 6, wicket) for that phase of the innings, scaled by how hard
## the batting side is pushing (chasing a required rate, wickets in hand, death
## overs). Extras (wides, no-balls with free hits, byes, leg-byes), dismissal
## types with fielders, captain's bowling changes, maidens, fall of wickets,
## over-by-over runs and Super Overs are all simulated.

const VALS := [0, 1, 2, 3, 4, 6, -1]   # outcome index → runs (-1 = wicket)
const WICKET := 6
## Bowling ratings run a little higher than batting ones in the player data;
## this recentres a typical batter-vs-bowler contest on an even footing.
const BAT_EDGE := 8.0

## Base outcome weights per phase: [dot, 1, 2, 3, 4, 6, wicket].
const BASE := {
	"pp":    [0.40, 0.29, 0.06, 0.006, 0.165, 0.055, 0.046],
	"mid":   [0.32, 0.42, 0.08, 0.006, 0.095, 0.058, 0.044],
	"death": [0.26, 0.31, 0.08, 0.006, 0.135, 0.105, 0.078],
}

const PITCHES := {
	"flat":     {"name": "Flat batting deck",   "runs": 1.12, "wkt": 0.9,  "pace": 0.0,  "spin": 0.0},
	"balanced": {"name": "Good cricket wicket", "runs": 1.0,  "wkt": 1.0,  "pace": 0.0,  "spin": 0.0},
	"green":    {"name": "Green seamer",        "runs": 0.93, "wkt": 1.1,  "pace": 7.0,  "spin": -3.0},
	"turner":   {"name": "Dry turner",          "runs": 0.94, "wkt": 1.08, "pace": -3.0, "spin": 8.0},
	"slow":     {"name": "Slow, low pitch",     "runs": 0.86, "wkt": 1.0,  "pace": -1.0, "spin": 3.0},
}
const PITCH_ODDS := [["flat", 3.0], ["balanced", 3.0], ["green", 1.5], ["turner", 1.5], ["slow", 1.0]]


static func _rng(seed_str: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_str)
	return r


# ------------------------------------------------------------------ helpers

static func overs_str(balls: int) -> String:
	return "%d.%d" % [balls / 6, balls % 6] if balls % 6 != 0 else str(balls / 6)


static func score_str(inn: Dictionary) -> String:
	if int(inn["wkts"]) >= int(inn.get("max_wkts", 10)):
		return "%d (%s)" % [inn["runs"], overs_str(inn["balls"])]
	return "%d/%d (%s)" % [inn["runs"], inn["wkts"], overs_str(inn["balls"])]


static func _surname(pid: String) -> String:
	var n: String = DB.player(pid).get("name", "?")
	var parts := n.split(" ", false)
	return parts[parts.size() - 1] if parts.size() > 0 else n


## Scorecard dismissal text, e.g. "c Rahane b Bumrah", "st †Dhoni b Ashwin".
static func how_str(c: Dictionary) -> String:
	if not c.get("out", false):
		return "not out"
	var h: Dictionary = c.get("how", {})
	var bw := _surname(h.get("bw", "")) if h.get("bw", "") != "" else ""
	var f := _surname(h.get("f", "")) if h.get("f", "") != "" else ""
	match h.get("k", ""):
		"b": return "b " + bw
		"lbw": return "lbw b " + bw
		"c": return "c %s b %s" % [f, bw]
		"cwk": return "c †%s b %s" % [f, bw]
		"cb": return "c & b " + bw
		"st": return "st †%s b %s" % [f, bw]
		"ro": return "run out (%s)" % f
		"hw": return "hit wicket b " + bw
	return "out"


static func bowl_type(p: Dictionary) -> String:
	match p.get("role", ""):
		"SPIN": return "spin"
		"PACE": return "pace"
		"AR":
			if p["trait"] in ["pp", "dth"] or int(p["bowl"]) >= 80:
				return "pace"
			return "spin"
	return "spin"   # part-time batters bowl spin


static func _phase(over: int, overs_max: int) -> String:
	if overs_max < 20:
		return "death"
	if over < 6:
		return "pp"
	if over >= 16:
		return "death"
	return "mid"


static func _keeper(xi: Array) -> String:
	for id in xi:
		if DB.player(id)["role"] == "WK":
			return id
	return ""


## The bowlers a captain will use: genuine options first, topped up with the
## best part-timers so there are always at least six (20 overs, 4 each).
static func _attack(xi: Array) -> Array:
	var keeper := _keeper(xi)
	var pool := xi.duplicate()
	pool.sort_custom(func(a, b):
		var ba := int(DB.player(a)["bowl"])
		var bb := int(DB.player(b)["bowl"])
		return ba > bb if ba != bb else a < b)
	var out := []
	for id in pool:
		if int(DB.player(id)["bowl"]) >= XI.BOWL_OPTION:
			out.append(id)
	for id in pool:
		if out.size() >= 6:
			break
		if not out.has(id) and id != keeper:
			out.append(id)
	return out


static func _pick_weighted(w: Array, rng: RandomNumberGenerator) -> int:
	var tot := 0.0
	for x in w:
		tot += x
	var r := rng.randf() * tot
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return w.size() - 1


# ------------------------------------------------------------------ per ball

## How hard the batting side is pushing (1.0 = normal for the phase).
static func _aggression(target: int, runs: int, balls: int, overs_max: int, wkts: int, max_wkts: int, phase: String, trt: String) -> float:
	var agg := 1.0
	var left_w := max_wkts - wkts
	var balls_left := overs_max * 6 - balls
	if target > 0:
		var rrr := float(target - runs) / maxf(1.0, balls_left) * 6.0
		agg = clampf(1.0 + (rrr - 8.8) * 0.06, 0.75, 1.6)
		if left_w <= 3 and rrr < 12.0:
			agg *= 0.88
	else:
		if phase == "death" and left_w >= 4:
			agg = 1.12
		elif left_w <= 3 and balls_left > 24:
			agg = 0.82
		elif phase == "mid" and wkts >= 5:
			agg = 0.9
	if trt == "fin" and phase == "death":
		agg += 0.1
	elif trt == "anc":
		agg -= 0.06
	return agg


static func _weights(phase: String, d: float, agg: float, pitch: Dictionary, trt: String) -> Array:
	var b: Array = BASE[phase]
	var rm := float(pitch["runs"])
	return [
		b[0] * exp(-0.9 * d) / pow(agg, 0.9),
		b[1] * exp(-0.2 * d) / pow(agg, 0.15),
		b[2] * exp(0.3 * d),
		b[3],
		b[4] * exp(1.6 * d) * pow(agg, 1.1) * rm,
		b[5] * exp(2.0 * d) * pow(agg, 1.5) * rm * rm,
		b[6] * exp(-1.4 * d) * pow(agg, 1.9) * float(pitch["wkt"]) * (0.88 if trt == "anc" else 1.0),
	]


## Batters take a few balls to get their eye in, and are dangerous once set.
static func _set_bonus(balls_faced: int) -> float:
	if balls_faced < 3:
		return -10.0
	if balls_faced < 8:
		return -4.0
	if balls_faced >= 20:
		return 3.0
	return 0.0


static func _bat_rating(p: Dictionary, phase: String, faced: int, form: float, home: float) -> float:
	var r := float(p["bat"]) + form + home + _set_bonus(faced)
	match p["trait"]:
		"op":
			if phase == "pp": r += 4.0
		"fin":
			if phase == "death": r += 5.0
		"anc":
			if phase == "mid": r += 3.0
	return r


static func _bowl_rating(p: Dictionary, phase: String, form: float, home: float, pitch: Dictionary, dew: bool) -> float:
	var bt := bowl_type(p)
	var r := float(p["bowl"]) + form + home + float(pitch[bt])
	if p["trait"] == "pp" and phase == "pp":
		r += 6.0
	elif p["trait"] == "dth" and phase == "death":
		r += 7.0
	elif bt == "spin" and phase == "mid":
		r += 3.0
	elif bt == "spin" and phase == "pp":
		r -= 2.0
	elif bt == "pace" and phase == "death":
		r -= 2.0
	if dew:
		r -= 3.0 if bt == "spin" else 1.0
	return r


## How the batter got out. Returns {k, bw, f, credit}.
static func _dismissal(bowler: String, bowl_xi: Array, keeper: String, phase: String, rng: RandomNumberGenerator) -> Dictionary:
	var spin := bowl_type(DB.player(bowler)) == "spin"
	var ro := 0.06 + (0.03 if phase == "death" else 0.0)
	var kinds := ["b", "lbw", "c", "cwk", "cb", "ro", "hw", "st"]
	var w: Array
	if spin:
		w = [0.15, 0.18, 0.40, 0.04, 0.05, ro, 0.002, 0.10]
	else:
		w = [0.19, 0.12, 0.43, 0.13, 0.02, ro, 0.004, 0.0]
	if keeper == "" or keeper == bowler:
		w[2] += w[3]
		w[3] = 0.0
		w[7] = 0.0
	var k: String = kinds[_pick_weighted(w, rng)]
	var out := {"k": k, "bw": bowler, "f": "", "credit": k != "ro"}
	if k == "cwk" or k == "st":
		out["f"] = keeper
	elif k == "c" or k == "ro":
		var pool := bowl_xi.filter(func(id): return id != bowler and (id != keeper or k == "ro"))
		if pool.is_empty():
			pool = bowl_xi
		out["f"] = pool[rng.randi_range(0, pool.size() - 1)]
	elif k == "cb":
		out["f"] = bowler
	return out


## Captain's choice for the next over: phase specialists, spin through the
## middle, spreading the overs, holding back death bowlers, and taking off
## someone who just went for plenty. A little captain's whim on top.
static func _pick_bowler(attack: Array, bowl_xi: Array, used: Dictionary, over: int, last: String, quota: int,
		overs_max: int, cost: Dictionary, rng: RandomNumberGenerator) -> String:
	var phase := _phase(over, overs_max)
	var best := ""
	var best_k := -1e9
	for id in attack:
		var u := int(used.get(id, 0))
		if u >= quota or id == last:
			continue
		var p := DB.player(id)
		var bt := bowl_type(p)
		var k := float(p["bowl"]) + rng.randf_range(-5.0, 5.0)
		if phase == "pp":
			k += 8.0 if p["trait"] == "pp" else (-4.0 if bt == "spin" else 0.0)
		elif phase == "death":
			k += 10.0 if p["trait"] == "dth" else (-4.0 if bt == "spin" else 0.0)
		else:
			k += 6.0 if bt == "spin" else 0.0
		# Keep two overs of the death specialist for the end.
		if overs_max >= 20 and phase != "death" and p["trait"] == "dth" and u >= quota - 2:
			k -= 15.0
		k -= u * 2.5
		if int(cost.get(id, 0)) >= 15:
			k -= 6.0
		if k > best_k:
			best_k = k
			best = id
	if best != "":
		return best
	# Fallbacks: anyone with overs left, then anyone who didn't bowl the last over.
	var pool := bowl_xi.duplicate()
	pool.sort_custom(func(a, b): return int(DB.player(a)["bowl"]) > int(DB.player(b)["bowl"]))
	for id in pool:
		if int(used.get(id, 0)) < quota and id != last:
			return id
	for id in pool:
		if id != last:
			return id
	return pool[0]


# ------------------------------------------------------------------ innings

## Simulates one innings. ctx (all optional): pitch, form {pid: float}, dew,
## bat_home, bowl_home, overs (20), quota (4), max_wkts, order (batting order),
## attack (bowlers to use).
static func innings(bat_xi: Array, bowl_xi: Array, target: int, rng: RandomNumberGenerator, ctx := {}) -> Dictionary:
	var order: Array = ctx.get("order", XI.order_batting(bat_xi))
	var overs_max: int = ctx.get("overs", 20)
	var quota: int = ctx.get("quota", maxi(1, ceili(overs_max / 5.0)))
	var pitch: Dictionary = PITCHES[ctx.get("pitch", "balanced")]
	var form: Dictionary = ctx.get("form", {})
	var dew: bool = ctx.get("dew", false)
	var bat_home: float = ctx.get("bat_home", 0.0)
	var bowl_home: float = ctx.get("bowl_home", 0.0)
	var max_wkts: int = ctx.get("max_wkts", mini(10, order.size() - 1))
	var keeper := _keeper(bowl_xi)
	var attack: Array = ctx.get("attack", _attack(bowl_xi))

	var cards := []
	for id in order:
		cards.append({"id": id, "r": 0, "b": 0, "4s": 0, "6s": 0, "out": false, "how": {}, "bat": false})
	var striker := 0
	var non := 1
	var next_in := 2
	if cards.size() > 0:
		cards[0]["bat"] = true
	if cards.size() > 1:
		cards[1]["bat"] = true
	var bowl := {}
	var extras := {"b": 0, "lb": 0, "w": 0, "nb": 0}
	var fow := []
	var over_runs := []
	var over_wkts := []
	var field := {}
	var runs := 0
	var wkts := 0
	var balls := 0
	var used := {}
	var cost := {}
	var last := ""
	var free_hit := false

	for over in overs_max:
		if wkts >= max_wkts or (target > 0 and runs >= target):
			break
		var phase := _phase(over, overs_max)
		var bowler := _pick_bowler(attack, bowl_xi, used, over, last, quota, overs_max, cost, rng)
		last = bowler
		used[bowler] = int(used.get(bowler, 0)) + 1
		if not bowl.has(bowler):
			bowl[bowler] = {"id": bowler, "balls": 0, "r": 0, "w": 0, "m": 0, "wd": 0, "nb": 0, "dots": 0}
		var bc: Dictionary = bowl[bowler]
		var bp := DB.player(bowler)
		var b_rating := _bowl_rating(bp, phase, float(form.get(bowler, 0.0)), bowl_home, pitch, dew)
		var o_conceded := 0   # charged to the bowler (for maidens / bowling changes)
		var o_total := 0
		var o_w := 0
		var legal := 0
		while legal < 6:
			if wkts >= max_wkts or (target > 0 and runs >= target):
				break
			# Wides.
			var wd_p := 0.03 + (0.01 if phase == "death" else 0.0)
			var roll := rng.randf()
			if roll < wd_p:
				var wr := 5 if rng.randf() < 0.03 else 1
				runs += wr
				extras["w"] += wr
				bc["r"] += wr
				bc["wd"] += 1
				o_conceded += wr
				o_total += wr
				continue
			var no_ball := roll < wd_p + 0.006
			var card: Dictionary = cards[striker]
			var sp := DB.player(card["id"])
			var bat_r := _bat_rating(sp, phase, int(card["b"]), float(form.get(card["id"], 0.0)), bat_home)
			var d := (bat_r - b_rating + BAT_EDGE) / 100.0
			var agg := _aggression(target, runs, balls, overs_max, wkts, max_wkts, phase, sp["trait"])
			var w := _weights(phase, d, agg, pitch, sp["trait"])
			if no_ball or free_hit:
				w[WICKET] = 0.0
			var res := _pick_weighted(w, rng)
			card["b"] += 1
			if no_ball:
				# One run for the no-ball, the bat's runs on top, and a free hit next.
				extras["nb"] += 1
				runs += 1
				bc["r"] += 1
				bc["nb"] += 1
				o_conceded += 1
				o_total += 1
				free_hit = true
			else:
				legal += 1
				balls += 1
				bc["balls"] += 1
				free_hit = false
			if res == WICKET:
				var dis := _dismissal(bowler, bowl_xi, keeper, phase, rng)
				var out_idx := striker
				if dis["k"] == "ro" and rng.randf() < 0.4 and non < cards.size():
					out_idx = non
				cards[out_idx]["out"] = true
				cards[out_idx]["how"] = {"k": dis["k"], "bw": bowler, "f": dis["f"]}
				if dis["credit"]:
					bc["w"] += 1
				if dis["f"] != "" and dis["k"] != "cb":
					var fc: Dictionary = field.get(dis["f"], {"ct": 0, "st": 0, "ro": 0})
					var key: String = {"c": "ct", "cwk": "ct", "st": "st", "ro": "ro"}.get(dis["k"], "ct")
					fc[key] += 1
					field[dis["f"]] = fc
				elif dis["k"] == "cb":
					var fc2: Dictionary = field.get(bowler, {"ct": 0, "st": 0, "ro": 0})
					fc2["ct"] += 1
					field[bowler] = fc2
				bc["dots"] += 1
				wkts += 1
				o_w += 1
				fow.append({"w": wkts, "r": runs, "o": overs_str(balls), "id": cards[out_idx]["id"]})
				if wkts < max_wkts and next_in < cards.size():
					cards[next_in]["bat"] = true
					if out_idx == striker:
						striker = next_in
					else:
						non = next_in
					next_in += 1
				continue
			var r: int = VALS[res]
			if r == 0:
				bc["dots"] += 1
				var x := rng.randf()
				if x < 0.05:
					runs += 1
					extras["lb"] += 1
					o_total += 1
					var t := striker
					striker = non
					non = t
				elif x < 0.058:
					runs += 4
					extras["lb"] += 4
					o_total += 4
				elif x < 0.064:
					runs += 1
					extras["b"] += 1
					o_total += 1
					var t2 := striker
					striker = non
					non = t2
				continue
			runs += r
			bc["r"] += r
			card["r"] += r
			o_conceded += r
			o_total += r
			if r == 4:
				card["4s"] += 1
			elif r == 6:
				card["6s"] += 1
			if r % 2 == 1:
				var t3 := striker
				striker = non
				non = t3
		over_runs.append(o_total)
		over_wkts.append(o_w)
		if legal == 6 and o_conceded == 0:
			bc["m"] += 1
		cost[bowler] = o_conceded
		var t4 := striker
		striker = non
		non = t4

	var dnb := []
	for c in cards:
		if not c["bat"]:
			dnb.append(c["id"])
	var bowl_list := []
	for id in bowl:
		bowl_list.append(bowl[id])
	return {
		"runs": runs, "wkts": wkts, "balls": balls, "max_wkts": max_wkts,
		"bat": cards.filter(func(c): return c["bat"]),
		"dnb": dnb,
		"bowl": bowl_list,
		"extras": extras,
		"fow": fow,
		"overs": over_runs,
		"over_wkts": over_wkts,
		"field": field,
		"all_out": wkts >= max_wkts,
	}


# ------------------------------------------------------------------ match

static func _pick_pitch(rng: RandomNumberGenerator) -> String:
	var w := []
	for p in PITCH_ODDS:
		w.append(p[1])
	return PITCH_ODDS[_pick_weighted(w, rng)][0]


## One Super Over: the three best batters in today's form against the best
## death bowler. The Super Over side's wickets end at 2.
static func _super_over(bat_xi: Array, bowl_xi: Array, target: int, rng: RandomNumberGenerator, form: Dictionary, pitch: String) -> Dictionary:
	var bats := bat_xi.duplicate()
	bats.sort_custom(func(a, b):
		return float(DB.player(a)["bat"]) + float(form.get(a, 0.0)) > float(DB.player(b)["bat"]) + float(form.get(b, 0.0)))
	var bowlers := bowl_xi.duplicate()
	bowlers.sort_custom(func(a, b):
		var pa := DB.player(a)
		var pb := DB.player(b)
		var ka := float(pa["bowl"]) + float(form.get(a, 0.0)) + (8.0 if pa["trait"] == "dth" else 0.0)
		var kb := float(pb["bowl"]) + float(form.get(b, 0.0)) + (8.0 if pb["trait"] == "dth" else 0.0)
		return ka > kb)
	return innings(bat_xi, bowl_xi, target, rng, {"overs": 1, "quota": 1, "max_wkts": 2,
		"order": bats.slice(0, 3), "attack": [bowlers[0]], "pitch": pitch, "form": form})


static func bat_impact(c: Dictionary) -> float:
	var r := float(c["r"])
	var imp := r + (10.0 if r >= 50 else 0.0) + (15.0 if r >= 100 else 0.0)
	if int(c["b"]) >= 8:
		imp += (r * 100.0 / float(c["b"]) - 135.0) * float(c["b"]) / 150.0
	return imp


static func bowl_impact(bw: Dictionary) -> float:
	var overs := float(bw["balls"]) / 6.0
	var econ := float(bw["r"]) / maxf(overs, 0.1)
	return float(bw["w"]) * 22.0 + (10.0 if int(bw["w"]) >= 3 else 0.0) + (8.0 - econ) * overs * 1.8 + float(bw["m"]) * 10.0


static func _player_of_match(innings_list: Array, winner_xi: Array) -> String:
	var score := {}
	for inn in innings_list:
		for c in inn["bat"]:
			score[c["id"]] = float(score.get(c["id"], 0.0)) + bat_impact(c)
		for bw in inn["bowl"]:
			score[bw["id"]] = float(score.get(bw["id"], 0.0)) + bowl_impact(bw)
		for fid in inn["field"]:
			var f: Dictionary = inn["field"][fid]
			score[fid] = float(score.get(fid, 0.0)) + 6.0 * (f["ct"] + f["st"] + f["ro"])
	var best := ""
	var best_v := -1e9
	var ids: Array = score.keys()
	ids.sort()
	for id in ids:
		var v: float = score[id] * (1.25 if winner_xi.has(id) else 1.0)
		if v > best_v:
			best_v = v
			best = id
	return best


static func _boundaries(inn: Dictionary) -> int:
	var n := 0
	for c in inn["bat"]:
		n += int(c["4s"]) + int(c["6s"])
	return n


## Simulate one match. a is the home side unless opts.home says otherwise.
static func play_match(a: String, b: String, xi_a: Array, xi_b: Array, seed_str: String, opts := {}) -> Dictionary:
	var rng := _rng(seed_str)
	var home: String = opts.get("home", a)
	var pitch := _pick_pitch(rng)
	var dew := rng.randf() < 0.35
	# Form on the day: most players near their rating, a few on fire or off-colour.
	var form := {}
	for id in xi_a + xi_b:
		form[id] = clampf(rng.randfn(0.0, 5.5), -13.0, 13.0)
	var toss := a if rng.randf() < 0.5 else b
	var chase_p := 0.55 + (0.25 if dew else 0.0) + (0.05 if pitch == "flat" else 0.0) - (0.15 if pitch in ["turner", "slow"] else 0.0)
	var decision := "bowl" if rng.randf() < chase_p else "bat"
	var other := b if toss == a else a
	var first := toss if decision == "bat" else other
	var second := other if first == toss else toss
	var xi := {a: xi_a, b: xi_b}
	var hb := {a: 2.0 if home == a else 0.0, b: 2.0 if home == b else 0.0}
	var i1 := innings(xi[first], xi[second], -1, rng,
		{"pitch": pitch, "form": form, "bat_home": hb[first], "bowl_home": hb[second]})
	var i2 := innings(xi[second], xi[first], int(i1["runs"]) + 1, rng,
		{"pitch": pitch, "form": form, "dew": dew, "bat_home": hb[second], "bowl_home": hb[first]})
	var winner := ""
	var margin := ""
	var supers := []
	if i2["runs"] > i1["runs"]:
		winner = second
		var wl := int(i2["max_wkts"]) - int(i2["wkts"])
		var bl := 120 - int(i2["balls"])
		margin = "by %d wicket%s" % [wl, "" if wl == 1 else "s"]
		if bl > 0:
			margin += " (%d ball%s left)" % [bl, "" if bl == 1 else "s"]
	elif i1["runs"] > i2["runs"]:
		winner = first
		var rm := int(i1["runs"]) - int(i2["runs"])
		margin = "by %d run%s" % [rm, "" if rm == 1 else "s"]
	else:
		# Tie: Super Overs until there's a winner (the side batting second goes first).
		var bf := second
		for k in 4:
			var bs := first if bf == second else second
			var s1 := _super_over(xi[bf], xi[bs], -1, rng, form, pitch)
			var s2 := _super_over(xi[bs], xi[bf], int(s1["runs"]) + 1, rng, form, pitch)
			supers.append({"first": bf, "second": bs, "i1": s1, "i2": s2})
			if s1["runs"] != s2["runs"]:
				winner = bf if s1["runs"] > s2["runs"] else bs
				break
			bf = bs
		if winner == "":
			var bnd1 := _boundaries(i1)
			var bnd2 := _boundaries(i2)
			winner = first if bnd1 >= bnd2 else second
			margin = "on boundary count"
		else:
			margin = "in the Super Over" if supers.size() == 1 else "after %d Super Overs" % supers.size()
	var all_inns := [i1, i2]
	return {
		"a": a, "b": b, "home": home, "pitch": pitch, "dew": dew,
		"toss": toss, "decision": decision, "first": first, "second": second,
		"i1": i1, "i2": i2, "s1": score_str(i1), "s2": score_str(i2),
		"supers": supers,
		"winner": winner, "margin": margin,
		"pom": _player_of_match(all_inns, xi[winner]),
	}


static func result_str(m: Dictionary) -> String:
	return "%s won %s" % [DB.team(m["winner"]).get("name", m["winner"]), m["margin"]]


static func toss_str(m: Dictionary) -> String:
	return "%s won the toss and chose to %s" % [DB.team_short(m["toss"]), m["decision"]]


static func team_strength(xi: Array) -> float:
	var r := Score.rate({"squad": {}, "purse": Rules.PURSE}, xi)
	return maxf(1.0, float(r["batting"]) + float(r["bowling"]))


# ------------------------------------------------------------------ season

## Round-robin calendar (circle method): every team plays once per round,
## home and away alternate; rounds and the order within them are shuffled.
## Small leagues (≤ 6 teams) play each other twice.
static func schedule(ids: Array, rng: RandomNumberGenerator) -> Array:
	var t := ids.duplicate()
	if t.size() % 2 == 1:
		t.append("")
	var n := t.size()
	var rounds := []
	for r in n - 1:
		var games := []
		for i in n / 2:
			var x: String = t[i]
			var y: String = t[n - 1 - i]
			if x == "" or y == "":
				continue
			games.append([x, y] if (r + i) % 2 == 0 else [y, x])
		rounds.append(games)
		var last_t: String = t.pop_back()
		t.insert(1, last_t)
	if ids.size() <= 6:
		var legs := []
		for g in rounds:
			legs.append(g.map(func(m): return [m[1], m[0]]))
		rounds += legs
	_shuffle(rounds, rng)
	var out := []
	for g in rounds:
		_shuffle(g, rng)
		out += g
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Full season. teams: {tid: xi}.
## Returns {table, matches, playoffs, champion, runner_up, stats}.
static func season(teams: Dictionary, seed: int) -> Dictionary:
	var ids: Array = teams.keys()
	ids.sort()
	var table := {}
	for t in ids:
		table[t] = {"team": t, "p": 0, "w": 0, "l": 0, "pts": 0, "rf": 0, "bf": 0, "ra": 0, "ba": 0, "form": []}
	var fixtures := schedule(ids, _rng("%d|fixtures" % seed))
	var matches := []
	var n := 0
	for f in fixtures:
		var m := play_match(f[0], f[1], teams[f[0]], teams[f[1]], "%d|m%d" % [seed, n], {"home": f[0]})
		m["stage"] = "Match %d" % (n + 1)
		m["idx"] = n
		matches.append(m)
		_record(table, m)
		n += 1
	var rows := table.values()
	for r in rows:
		r["nrr"] = nrr(r)
	rows.sort_custom(func(x, y):
		if x["pts"] != y["pts"]:
			return x["pts"] > y["pts"]
		if x["nrr"] != y["nrr"]:
			return x["nrr"] > y["nrr"]
		return x["team"] < y["team"])
	var playoffs := []
	var champion := ""
	var runner := ""
	var add := func(t1: String, t2: String, key: String, stage: String) -> Dictionary:
		var m := play_match(t1, t2, teams[t1], teams[t2], "%d|%s" % [seed, key], {"home": t1})
		m["stage"] = stage
		m["idx"] = matches.size() + playoffs.size()
		playoffs.append(m)
		return m
	if rows.size() >= 4:
		var t1: String = rows[0]["team"]
		var t2: String = rows[1]["team"]
		var t3: String = rows[2]["team"]
		var t4: String = rows[3]["team"]
		var q1: Dictionary = add.call(t1, t2, "q1", "Qualifier 1")
		var el: Dictionary = add.call(t3, t4, "el", "Eliminator")
		var q1_loser: String = q1["a"] if q1["winner"] == q1["b"] else q1["b"]
		var q2: Dictionary = add.call(q1_loser, el["winner"], "q2", "Qualifier 2")
		var fin: Dictionary = add.call(q1["winner"], q2["winner"], "final", "Final")
		champion = fin["winner"]
		runner = fin["a"] if champion == fin["b"] else fin["b"]
	elif rows.size() >= 2:
		var f1: String = rows[0]["team"]
		var f2: String = rows[1]["team"]
		var fin2: Dictionary = add.call(f1, f2, "final", "Final")
		champion = fin2["winner"]
		runner = f2 if champion == f1 else f1
	elif rows.size() == 1:
		champion = rows[0]["team"]
	return {"table": rows, "matches": matches, "playoffs": playoffs, "champion": champion,
		"runner_up": runner, "stats": season_stats(matches + playoffs)}


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
		var won: bool = m["winner"] == t
		if won:
			table[t]["w"] += 1
			table[t]["pts"] += 2
		else:
			table[t]["l"] += 1
		table[t]["form"].append("W" if won else "L")


static func nrr(r: Dictionary) -> float:
	if r["bf"] == 0 or r["ba"] == 0:
		return 0.0
	return snappedf(float(r["rf"]) / (r["bf"] / 6.0) - float(r["ra"]) / (r["ba"] / 6.0), 0.001)


## Season leaders. MVP points follow the league's formula: 2.5 per four,
## 3.5 per six, 3.5 per wicket, 1 per dot ball, 2.5 per catch/stumping/run out.
static func season_stats(all: Array) -> Dictionary:
	var P := {}
	var inns := []
	var figs := []
	var entry := func(pid: String, tid: String) -> Dictionary:
		if not P.has(pid):
			P[pid] = {"id": pid, "team": tid, "m": 0, "inn": 0, "r": 0, "b": 0, "no": 0, "hs": 0, "hs_no": false,
				"50": 0, "100": 0, "4s": 0, "6s": 0, "wk": 0, "bb": 0, "rc": 0, "dots": 0, "best_w": 0, "best_r": 0,
				"ct": 0, "st": 0, "ro": 0, "mvp": 0.0}
		return P[pid]
	for m in all:
		for side in [[m["first"], m["i1"], m["second"]], [m["second"], m["i2"], m["first"]]]:
			var bt: String = side[0]
			var inn: Dictionary = side[1]
			var ft: String = side[2]
			for c in inn["bat"]:
				var s: Dictionary = entry.call(c["id"], bt)
				s["m"] += 1
				s["inn"] += 1
				s["r"] += c["r"]
				s["b"] += c["b"]
				s["4s"] += c["4s"]
				s["6s"] += c["6s"]
				if not c["out"]:
					s["no"] += 1
				if c["r"] >= 100:
					s["100"] += 1
				elif c["r"] >= 50:
					s["50"] += 1
				if c["r"] > s["hs"] or (c["r"] == s["hs"] and not c["out"]):
					s["hs"] = c["r"]
					s["hs_no"] = not c["out"]
				inns.append({"id": c["id"], "team": bt, "vs": ft, "r": c["r"], "b": c["b"], "out": c["out"], "m": m["idx"]})
			for pid in inn["dnb"]:
				entry.call(pid, bt)["m"] += 1
			for bw in inn["bowl"]:
				var s2: Dictionary = entry.call(bw["id"], ft)
				s2["wk"] += bw["w"]
				s2["bb"] += bw["balls"]
				s2["rc"] += bw["r"]
				s2["dots"] += bw["dots"]
				if bw["w"] > s2["best_w"] or (bw["w"] == s2["best_w"] and bw["r"] < s2["best_r"]):
					s2["best_w"] = bw["w"]
					s2["best_r"] = bw["r"]
				figs.append({"id": bw["id"], "team": ft, "vs": bt, "w": bw["w"], "r": bw["r"], "balls": bw["balls"], "m": m["idx"]})
			for fid in inn["field"]:
				var s3: Dictionary = entry.call(fid, ft)
				var f: Dictionary = inn["field"][fid]
				s3["ct"] += f["ct"]
				s3["st"] += f["st"]
				s3["ro"] += f["ro"]
	for pid in P:
		var s: Dictionary = P[pid]
		s["mvp"] = s["4s"] * 2.5 + s["6s"] * 3.5 + s["wk"] * 3.5 + s["dots"] * 1.0 + (s["ct"] + s["st"] + s["ro"]) * 2.5
	var all_p: Array = P.values()
	var top := func(key: Callable) -> Array:
		var arr := all_p.duplicate()
		arr.sort_custom(func(x, y):
			var kx: Array = key.call(x)
			var ky: Array = key.call(y)
			for i in kx.size():
				if kx[i] != ky[i]:
					return kx[i] > ky[i]
			return x["id"] < y["id"])
		return arr.slice(0, 5).map(func(s): return s["id"])
	inns.sort_custom(func(x, y):
		if x["r"] != y["r"]:
			return x["r"] > y["r"]
		if x["b"] != y["b"]:
			return x["b"] < y["b"]
		return x["m"] < y["m"])
	figs.sort_custom(func(x, y):
		if x["w"] != y["w"]:
			return x["w"] > y["w"]
		if x["r"] != y["r"]:
			return x["r"] < y["r"]
		return x["m"] < y["m"])
	return {
		"players": P,
		"orange": top.call(func(s): return [s["r"], -s["b"]]),
		"purple": top.call(func(s): return [s["wk"], -float(s["rc"]) / maxf(1.0, s["bb"])]),
		"mvp": top.call(func(s): return [s["mvp"], s["r"]]),
		"sixes": top.call(func(s): return [s["6s"], s["r"]]),
		"best_inns": inns.slice(0, 5),
		"best_figs": figs.slice(0, 5),
	}
