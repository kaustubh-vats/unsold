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


static func role_counts(team: Dictionary) -> Dictionary:
	var c := {"BAT": 0, "WK": 0, "AR": 0, "PACE": 0, "SPIN": 0}
	for pid in team.get("squad", {}):
		c[DB.player(pid)["role"]] += 1
	return c


static func most_needed_role(team: Dictionary) -> String:
	var c := role_counts(team)
	var best := "BAT"
	var gap := -99.0
	for r in TARGET:
		var g: float = float(TARGET[r] - c[r]) / float(TARGET[r])
		if g > gap:
			gap = g
			best = r
	return best


## Team personality: a stable aggression multiplier per team per game.
static func aggression(seed: int, tid: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [seed, tid])
	return rng.randf_range(0.82, 1.22)


## A team's plan for this auction, different every game: which roles it rates
## (one side builds around spin, another hoards pace), whether it chases stars
## or spreads the money, how it treats overseas players, whether it spends
## early or keeps powder dry, and how picky it is.
static func strategy(seed: int, tid: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|plan|%s" % [seed, tid])
	var roles := {}
	for r in TARGET:
		roles[r] = rng.randf_range(0.82, 1.22)
	return {
		"roles": roles,
		"star": rng.randf_range(-0.9, 0.9),     # + = pays up for stars, − = values depth
		"overseas": rng.randf_range(0.85, 1.15),
		"early": rng.randf_range(0.85, 1.15),   # > 1 spends early, < 1 saves for later
		"picky": rng.randf_range(0.6, 1.5),     # scales the chance of sitting a lot out
		"cap_star": rng.randf_range(0.15, 0.27), # most of the purse it will put on one star
		"cap": rng.randf_range(0.11, 0.19),      # ...and on anyone else
	}


## How hot the market is for a player this auction (same for every team):
## some years a player is the talk of the town, other years he goes cheap.
static func hype(seed: int, pid: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|hype|%s" % [seed, pid])
	return clampf(rng.randfn(1.0, 0.2), 0.6, 1.55)


## The maximum this AI team is willing to pay for the player (lakh).
## Deterministic for (seed, team, player, squad state) so a new host behaves the same.
static func valuation(team: Dictionary, tid: String, p: Dictionary, seed: int, lots_left: int, diff := "medium") -> int:
	var lv := level(diff)
	var plan := strategy(seed, tid)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%s" % [seed, tid, p["id"]])
	var v := market_value(p, float(lv["spread"]) - float(plan["star"])) * float(lv["value"])
	v *= hype(seed, p["id"]) * float(plan["roles"][p["role"]])
	if p["overseas"]:
		v *= float(plan["overseas"])
	v *= float(plan["early"]) if lots_left > 120 else 2.0 - float(plan["early"])
	var count := Rules.squad_count(team)
	var counts := role_counts(team)
	var role: String = p["role"]
	# Role need.
	var have: int = counts[role]
	var want: int = TARGET[role]
	if have < want / 2:
		v *= 1.35
	elif have < want:
		v *= 1.1
	elif have == want:
		v *= 0.6
	else:
		v *= 0.3
	# Wicket-keeper essential.
	if role == "WK" and have == 0:
		v *= 1.25
	# Overseas slot pressure.
	if p["overseas"]:
		var os := Rules.overseas_count(team)
		if os >= Rules.MAX_OVERSEAS:
			return 0
		if os >= 6:
			v *= 0.7
	# Squad size pressure.
	if count >= 22:
		v *= 0.45
	elif count >= Rules.MIN_SQUAD:
		v *= 0.75
	# Late auction desperation if short of players.
	var short := Rules.MIN_SQUAD - count
	if short > 0 and lots_left < short * 4:
		v *= 1.3
	# Personality and noise.
	v *= aggression(seed, tid) * rng.randf_range(lv["noise"][0], lv["noise"][1])
	# Budget discipline (applied last): don't blow too much on one player,
	# and never beyond a realistic record price.
	var purse := float(team.get("purse", 0))
	var slots := float(maxi(1, Rules.MIN_SQUAD - count))
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
	var diff := str(state.get("meta", {}).get("settings", {}).get("difficulty", "medium"))
	var candidates := []
	var teams: Dictionary = state.get("teams", {})
	for tid in teams:
		var t: Dictionary = teams[tid]
		if not t.get("ai", false) or a.get("bidder", "") == tid:
			continue
		if not Rules.can_bid(t, p, amount):
			continue
		var val := valuation(t, tid, p, seed, lots_left, diff)
		if val >= amount:
			candidates.append([tid, val])
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
