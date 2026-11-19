class_name AI
extends RefCounted
## AI franchise bidding behaviour.

## Ideal squad composition by role (sums to ~22).
const TARGET := {"BAT": 6, "WK": 2, "AR": 5, "PACE": 6, "SPIN": 3}
## AI teams never pay more than this (lakh) — roughly the real-world record.
const MAX_PRICE := 2800.0


## Rough market value of a player in lakh, from their overall rating.
static func market_value(p: Dictionary) -> float:
	var v := 22.0 * exp((float(p["ovr"]) - 50.0) / 9.5)
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
	return rng.randf_range(0.85, 1.2)


## The maximum this AI team is willing to pay for the player (lakh).
## Deterministic for (seed, team, player, squad state) so a new host behaves the same.
static func valuation(team: Dictionary, tid: String, p: Dictionary, seed: int, lots_left: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s|%s" % [seed, tid, p["id"]])
	var v := market_value(p)
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
	v *= aggression(seed, tid) * rng.randf_range(0.8, 1.2)
	# Budget discipline (applied last): don't blow too much on one player,
	# and never beyond a realistic record price.
	var purse := float(team.get("purse", 0))
	var slots := float(maxi(1, Rules.MIN_SQUAD - count))
	var cap := purse * (0.21 if p["ovr"] >= 88 else 0.15)
	if slots <= 3:
		cap = purse * 0.6
	cap = minf(cap, MAX_PRICE * rng.randf_range(0.85, 1.0))
	v = minf(v, maxf(cap, float(p["base"])))
	# Sometimes a team simply isn't interested.
	if rng.randf() < 0.18:
		v = 0.0
	return mini(int(v), Rules.max_affordable(team))


## Pick which AI team (if any) bids next on the current lot.
## Returns {"team": tid, "amount": n} or {} if no AI wants to bid.
static func choose_bidder(state: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var a: Dictionary = state.get("auction", {})
	var p := DB.player(a.get("pid", ""))
	if p.is_empty():
		return {}
	var amount := Auction.current_next(state)
	var seed := int(state.get("meta", {}).get("seed", 1))
	var lots_left: int = (a.get("lots", []) as Array).size() - int(a.get("idx", 0))
	var candidates := []
	var teams: Dictionary = state.get("teams", {})
	for tid in teams:
		var t: Dictionary = teams[tid]
		if not t.get("ai", false) or a.get("bidder", "") == tid:
			continue
		if not Rules.can_bid(t, p, amount):
			continue
		var val := valuation(t, tid, p, seed, lots_left)
		if val >= amount:
			candidates.append([tid, val])
	if candidates.is_empty():
		return {}
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
	var has_bidder: bool = a.get("bidder", "") != ""
	while price <= second_val:
		var nxt := Rules.next_bid(price, int(p.get("base", 0)), true)
		if nxt > top_val:
			break
		price = nxt
	price = maxi(price, amount)
	if not Rules.can_bid(teams[lead[0]], p, price):
		price = amount
	return {"team": lead[0], "amount": price}
