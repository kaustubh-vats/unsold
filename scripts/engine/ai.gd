class_name AI
extends RefCounted
## AI franchise bidding behaviour.

## Ideal squad composition by role (sums to ~22).
const TARGET := {"BAT": 6, "WK": 2, "AR": 5, "PACE": 6, "SPIN": 3}
## AI teams never pay more than this (lakh) — roughly the real-world record.
const MAX_PRICE := 2800.0


## Difficulty levels (lobby setting "difficulty"). They only change how the AI
## franchises bid; the rules, the purse and the match engine are the same for all.
##   value:  how much AI teams are willing to pay overall
##   noise:  how erratic their valuations are (easy AI misjudges players)
##   skip:   chance an AI team simply isn't interested in a player
##   spread: how steeply they pay up for stars (hard AI chases quality)
##   pace:   how quickly they answer a human bid (multiplier on think time)
const LEVELS := {
	"easy":   {"value": 0.8,  "noise": [0.65, 1.15], "skip": 0.32, "spread": 10.5, "pace": 1.5},
	"medium": {"value": 1.0,  "noise": [0.8, 1.2],   "skip": 0.18, "spread": 9.5,  "pace": 1.0},
	"hard":   {"value": 1.1,  "noise": [0.92, 1.08], "skip": 0.07, "spread": 8.8,  "pace": 0.75},
}


static func level(state_or_diff) -> Dictionary:
	var d := "medium"
	if typeof(state_or_diff) == TYPE_STRING:
		d = state_or_diff
	elif typeof(state_or_diff) == TYPE_DICTIONARY:
		d = str(state_or_diff.get("meta", {}).get("settings", {}).get("difficulty", "medium"))
	return LEVELS.get(d, LEVELS["medium"])


## Rough market value of a player in lakh, from their overall rating.
static func market_value(p: Dictionary, spread := 9.5) -> float:
	var v := 22.0 * exp((float(p["ovr"]) - 50.0) / spread)
	if p["trait"] in ["dth", "fin"]:
		v *= 1.08
	return maxf(v, float(p["base"]))


## Verdict on a sale: price against the player's market value. Bands follow
## what AI auctions actually pay (median ≈ 1.0× market value; about 1 in 10
## buys go under half of it, about 1 in 14 at over 1.7×).
## Returns {key, label, fair (lakh), ratio}; key is steal|bargain|fair|pricey|overpaid.
static func deal(p: Dictionary, price: int) -> Dictionary:
	# Market value tracks the median sale price at each rating; the very top
	# players top out around ₹25 Cr however good they are.
	var fair := minf(market_value(p), 2500.0)
	var ratio := float(price) / fair
	var at_base := price <= int(p["base"])
	var key := "fair"
	if at_base and fair <= float(p["base"]) * 1.1:
		key = "fair"          # bought at base, and that's all he's worth
	elif ratio < (0.35 if at_base else 0.5):
		key = "steal"         # a base-price pickup has to be a real gem to count
	elif ratio < 0.5:
		key = "bargain"
	elif ratio < 0.8:
		key = "bargain"
	elif ratio <= 1.25:
		key = "fair"
	elif ratio <= 1.7:
		key = "pricey"
	else:
		key = "overpaid"
	var labels := {"steal": "STEAL DEAL", "bargain": "GOOD VALUE", "fair": "FAIR PRICE",
		"pricey": "BIT PRICEY", "overpaid": "OVERPAID"}
	# Round the fair value to a price the auction actually uses (5 L / 25 L steps).
	var step := 25.0 if fair >= 100.0 else 5.0
	return {"key": key, "label": labels[key], "fair": int(roundf(fair / step) * step), "ratio": ratio}


static func role_counts(team: Dictionary) -> Dictionary:
	var c := {"BAT": 0, "WK": 0, "AR": 0, "PACE": 0, "SPIN": 0}
	for pid in team.get("squad", {}):
		c[DB.player(pid)["role"]] += 1
	return c


## Ideal role mix for this team's squad size: TARGET in a full auction,
## scaled down for a mini auction's smaller squads.
static func targets(team: Dictionary) -> Dictionary:
	if not team.has("lim"):
		return TARGET
	var f := (Rules.min_squad(team) + Rules.max_squad(team)) / 2.0 / 21.5
	var out := {}
	for r in TARGET:
		out[r] = maxi(1, roundi(TARGET[r] * f))
	return out


static func most_needed_role(team: Dictionary) -> String:
	var c := role_counts(team)
	var tg := targets(team)
	var best := "BAT"
	var gap := -99.0
	for r in tg:
		var g: float = float(tg[r] - c[r]) / float(tg[r])
		if g > gap:
			gap = g
			best = r
	return best


## Each franchise bids like its real-life counterpart. Fixed per team; every
## game adds a little jitter on top (see strategy()), so they're recognisable
## but not predictable to the lakh.
##   mix:       their ideal squad vs TARGET (e.g. +2 spinners, −2 seamers)
##   roles / traits: how much they rate each role and speciality
##   star:      + pays up for stars, − spreads the money for depth
##   overseas:  appetite for overseas players
##   uncapped:  appetite for uncapped (young, unproven) players
##   indian_star: extra for capped Indian stars (ovr ≥ 86)
##   early:     > 1 spends in the first half of the auction, < 1 saves for later
##   accel:     appetite in the accelerated round (late bargains)
##   need:      how strictly they buy for gaps in the squad
##   picky:     chance of sitting a lot out (× difficulty skip)
##   cap_star / cap: most of the purse on one star / on anyone else
##   aggr:      overall willingness to pay
##   war:       stubbornness in a long bidding war (0 calm .. 1 never backs down)
##   erratic:   how far their valuations swing (× difficulty noise)
const PERSONAS := {
	"CHE": {"label": "The Old Guard", "blurb": "Calm, loyal and patient. Builds around spin and all-rounders, trusts experience over potential and rarely panics in a bidding war.",
		"mix": {"SPIN": 2, "AR": 1, "PACE": -2, "BAT": -1}, "roles": {"SPIN": 1.35, "AR": 1.25, "PACE": 0.9}, "traits": {"anc": 1.12, "fin": 1.15},
		"star": 0.1, "uncapped": 0.82, "picky": 0.9, "aggr": 0.96, "war": 0.25, "cap": 0.14},
	"MUM": {"label": "The Talent Scouts", "blurb": "Disciplined and data-driven. Hunts fast bowlers and cheap uncapped Indians, and walks away once the price is wrong.",
		"mix": {"PACE": 2, "SPIN": -1, "AR": -1}, "roles": {"PACE": 1.25}, "traits": {"pp": 1.1, "dth": 1.15},
		"star": 0.2, "uncapped": 1.25, "aggr": 1.0, "war": 0.45, "cap": 0.13, "erratic": 0.8},
	"BLR": {"label": "The Star Chasers", "blurb": "Goes after the biggest names, especially batters. Will put up to a quarter of the purse on one star.",
		"mix": {"BAT": 2, "AR": -1, "SPIN": -1}, "roles": {"BAT": 1.25, "WK": 1.05, "SPIN": 0.9}, "traits": {"anc": 1.08},
		"star": 0.9, "uncapped": 0.85, "aggr": 1.1, "war": 0.7, "cap_star": 0.25},
	"KOL": {"label": "The All-In Gamblers", "blurb": "The boldest room at the table. Loves overseas all-rounders and mystery spin, and drags bidding wars to record prices.",
		"mix": {"AR": 2, "SPIN": 1, "BAT": -2, "PACE": -1}, "roles": {"AR": 1.2, "SPIN": 1.15, "BAT": 0.95}, "overseas": 1.2,
		"star": 0.5, "aggr": 1.2, "war": 0.9, "cap_star": 0.27, "cap": 0.18},
	"HYD": {"label": "The Powerplay Pirates", "blurb": "All about explosive openers and overseas pace. Patient early, then pounces on bargains late and in the accelerated round.",
		"mix": {"BAT": 1, "PACE": 1, "AR": -2}, "roles": {"PACE": 1.1}, "traits": {"op": 1.25, "pp": 1.15}, "overseas": 1.1,
		"early": 0.94, "accel": 1.3, "aggr": 1.0, "war": 0.55},
	"DEL": {"label": "The Rebuilders", "blurb": "Value hunters who back Indian and uncapped talent, spread the money evenly and avoid blowing it on one name.",
		"overseas": 0.9, "uncapped": 1.15, "star": -0.5, "picky": 0.8, "aggr": 0.95, "war": 0.35, "cap_star": 0.17, "cap": 0.13},
	"PUN": {"label": "The Big Spenders", "blurb": "Splashes the cash early and often, sometimes on the wrong player. Unpredictable and hard to outbid when they want someone.",
		"early": 1.2, "accel": 0.8, "star": 0.4, "aggr": 1.15, "war": 0.8, "erratic": 1.6, "picky": 1.2},
	"JAI": {"label": "Moneyball", "blurb": "Analytics first. Backs uncapped youngsters and spinners, avoids overpriced stars and saves money for late bargains.",
		"mix": {"SPIN": 2, "PACE": -1, "BAT": -1}, "roles": {"SPIN": 1.2}, "uncapped": 1.25, "star": -0.7, "early": 0.85, "accel": 1.35,
		"aggr": 0.9, "war": 0.25, "cap_star": 0.16},
	"AHM": {"label": "The Gap Fillers", "blurb": "Plans the XI first, then buys exactly what's missing. Loves bowlers and death specialists and rarely overpays.",
		"mix": {"PACE": 1, "SPIN": 1, "BAT": -2}, "roles": {"PACE": 1.1, "SPIN": 1.1, "BAT": 0.95}, "traits": {"dth": 1.2},
		"star": -0.3, "need": 1.35, "aggr": 0.95, "war": 0.35, "cap": 0.13},
	"LKO": {"label": "The Record Breakers", "blurb": "Willing to break the bank for one Indian star, then stacks all-rounders. Bold and a little erratic.",
		"mix": {"AR": 2, "BAT": -1, "PACE": -1}, "roles": {"AR": 1.15}, "indian_star": 1.25, "star": 0.7, "aggr": 1.05, "war": 0.75,
		"erratic": 1.4, "cap_star": 0.27},
}
const PERSONA_DEFAULT := {"label": "Balanced", "blurb": "No fixed plan: rates every role about the same."}


## The franchise's real-life style (label + blurb for the UI).
static func persona(tid: String) -> Dictionary:
	return PERSONAS.get(tid, PERSONA_DEFAULT)


## Team personality: a stable aggression multiplier per team per game.
static func aggression(seed: int, tid: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [seed, tid])
	return float(persona(tid).get("aggr", 1.0)) * rng.randf_range(0.94, 1.06)


static func _jit(pr: Dictionary, k: String, d: float, spread: float, rng: RandomNumberGenerator) -> float:
	return float(pr.get(k, d)) * rng.randf_range(1.0 - spread, 1.0 + spread)


## A team's plan for this auction: its persona plus a little per-game jitter.
static func strategy(seed: int, tid: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|plan|%s" % [seed, tid])
	var pr := persona(tid)
	var pr_roles: Dictionary = pr.get("roles", {})
	var roles := {}
	for r in TARGET:
		roles[r] = float(pr_roles.get(r, 1.0)) * rng.randf_range(0.94, 1.06)
	return {
		"roles": roles,
		"traits": pr.get("traits", {}),
		"star": clampf(float(pr.get("star", 0.0)) + rng.randf_range(-0.15, 0.15), -0.95, 0.95),
		"overseas": _jit(pr, "overseas", 1.0, 0.04, rng),
		"uncapped": _jit(pr, "uncapped", 1.0, 0.04, rng),
		"indian_star": float(pr.get("indian_star", 1.0)),
		"early": _jit(pr, "early", 1.0, 0.03, rng),
		"accel": _jit(pr, "accel", 1.0, 0.05, rng),
		"need": float(pr.get("need", 1.0)),
		"picky": _jit(pr, "picky", 1.0, 0.15, rng),
		"cap_star": _jit(pr, "cap_star", 0.21, 0.08, rng),
		"cap": _jit(pr, "cap", 0.15, 0.08, rng),
		"war": float(pr.get("war", 0.5)),
		"erratic": float(pr.get("erratic", 1.0)),
	}


## How hot the market is for a player this auction (same for every team):
## some years a player is the talk of the town, other years he goes cheap.
static func hype(seed: int, pid: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|hype|%s" % [seed, pid])
	return clampf(rng.randfn(1.0, 0.2), 0.6, 1.55)


## The maximum this AI team is willing to pay for the player (lakh).
## Deterministic for (seed, team, player, squad state) so a new host behaves the same.
static func valuation(team: Dictionary, tid: String, p: Dictionary, seed: int, lots_left: int, diff := "medium", rnd := 1, lots_total := 214) -> int:
	var lv := level(diff)
	var plan := strategy(seed, tid)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%s" % [seed, tid, p["id"]])
	var v := market_value(p, float(lv["spread"]) - float(plan["star"])) * float(lv["value"])
	v *= hype(seed, p["id"]) * float(plan["roles"][p["role"]])
	v *= float(plan["traits"].get(p["trait"], 1.0))
	if p["overseas"]:
		v *= float(plan["overseas"])
	elif p["ovr"] >= 86 and p["capped"]:
		v *= float(plan["indian_star"])
	if not p["capped"]:
		v *= float(plan["uncapped"])
	if rnd >= 2:
		v *= float(plan["accel"])
	else:
		v *= float(plan["early"]) if lots_left > lots_total * 0.56 else 2.0 - float(plan["early"])
	var count := Rules.squad_count(team)
	var counts := role_counts(team)
	var role: String = p["role"]
	# Role need.
	var have: int = counts[role]
	var tg := targets(team)
	var mixv := int(persona(tid).get("mix", {}).get(role, 0))
	if team.has("lim"):
		mixv = roundi(mixv * float(tg[role]) / float(TARGET[role]))
	var want: int = maxi(1, tg[role] + mixv)
	var need := float(plan["need"])   # gap fillers lean harder into squad needs
	if have < want / 2:
		v *= 1.0 + 0.35 * need
	elif have < want:
		v *= 1.0 + 0.1 * need
	elif have == want:
		v *= pow(0.6, need)
	else:
		v *= pow(0.3, need)
	# Wicket-keeper essential.
	if role == "WK" and have == 0:
		v *= 1.25
	# Overseas slot pressure.
	if p["overseas"]:
		var os := Rules.overseas_count(team)
		if os >= Rules.max_overseas(team):
			return 0
		if os >= Rules.max_overseas(team) - 2:
			v *= 0.7
	# Squad size pressure.
	if count >= Rules.max_squad(team) - 3:
		v *= 0.45
	elif count >= Rules.min_squad(team):
		v *= 0.75
	# Late auction desperation if short of players.
	var short := Rules.min_squad(team) - count
	if short > 0 and lots_left < short * 4:
		v *= 1.3
	# Personality and noise.
	var er := float(plan["erratic"])
	v *= aggression(seed, tid) * (1.0 + (rng.randf_range(lv["noise"][0], lv["noise"][1]) - 1.0) * er)
	# Budget discipline (applied last): don't blow too much on one player,
	# and never beyond a realistic record price.
	var purse := float(team.get("purse", 0))
	var slots := float(maxi(1, Rules.min_squad(team) - count))
	var cap := purse * (float(plan["cap_star"]) if p["ovr"] >= 88 else float(plan["cap"]))
	if slots <= 3:
		cap = purse * 0.6
	cap = minf(cap, MAX_PRICE * rng.randf_range(0.85, 1.0))
	v = minf(v, maxf(cap, float(p["base"])))
	# Sometimes a team simply isn't interested.
	if rng.randf() < float(lv["skip"]) * float(plan["picky"]):
		v = 0.0
	return mini(int(v), Rules.max_affordable(team))


## Pick which AI team (if any) bids next on the current lot.
## Returns {"team": tid, "amount": n} or {} if no AI wants to bid.
## While a human is still in the bidding (`jump` false) the AI raises one
## increment at a time, like paddles in a real auction room, so the human
## always gets a turn to respond. Once every human is out, AI-vs-AI wars are
## settled in a single jump to save time (and writes, online).
static func choose_bidder(state: Dictionary, rng: RandomNumberGenerator, jump := true) -> Dictionary:
	var a: Dictionary = state.get("auction", {})
	var p := DB.player(a.get("pid", ""))
	if p.is_empty():
		return {}
	var amount := Auction.current_next(state)
	var seed := int(state.get("meta", {}).get("seed", 1))
	var lots_left: int = (a.get("lots", []) as Array).size() - int(a.get("idx", 0))
	var lots_total: int = Auction.pool_ids(state).size()
	var diff := str(state.get("meta", {}).get("settings", {}).get("difficulty", "medium"))
	var rnd := int(a.get("round", 1))
	var n := int(a.get("n", 0))
	var candidates := []
	var teams: Dictionary = state.get("teams", {})
	for tid in teams:
		var t: Dictionary = teams[tid]
		if not t.get("ai", false) or a.get("bidder", "") == tid:
			continue
		if not Rules.can_bid(t, p, amount):
			continue
		var val := valuation(t, tid, p, seed, lots_left, diff, rnd, lots_total)
		if val >= amount:
			candidates.append([tid, val])
		elif val > 0 and n >= 3:
			# Caught up in a bidding war: stubborn rooms go a step past their limit.
			var war := float(strategy(seed, tid)["war"])
			if float(val) * (1.0 + 0.15 * war) >= amount and rng.randf() < war * 0.6:
				candidates.append([tid, amount])
	if candidates.is_empty():
		return {}
	if not jump:
		# One paddle goes up: a random interested team raises by one increment.
		var pick: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
		return {"team": pick[0], "amount": amount}
	if candidates.size() == 1:
		return {"team": candidates[0][0], "amount": amount}
	# Several AI teams want the player: resolve their bidding war in one jump.
	# The team with the highest valuation bids just above the runner-up's limit
	# (an English auction's outcome), so online games need one write, not dozens.
	candidates.sort_custom(func(x, y): return x[1] > y[1])
	var top_val: int = candidates[0][1]
	var second_val: int = candidates[1][1]
	# Small chance the runner-up ends up leading (bidding wars are noisy).
	var lead: Array = candidates[0]
	if rng.randf() < 0.15 and second_val > amount:
		lead = candidates[1]
		top_val = second_val
		second_val = mini(second_val - 1, candidates[0][1])
	var price := amount
	while price <= second_val:
		var nxt := Rules.next_bid(price, int(p.get("base", 0)), true)
		if nxt > top_val:
			break
		price = nxt
	price = maxi(price, amount)
	if not Rules.can_bid(teams[lead[0]], p, price):
		price = amount
	return {"team": lead[0], "amount": price}
