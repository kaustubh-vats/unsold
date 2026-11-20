class_name Rules
extends RefCounted
## Auction rules. All money values are in lakh (100 lakh = 1 crore).

const PURSE := 12000          # 120 crore
const MIN_SQUAD := 18
const MAX_SQUAD := 25
const MAX_OVERSEAS := 8
const MIN_PRICE := 30         # cheapest possible signing, used for the purse reserve
const MAX_OVERSEAS_XI := 4


## Bid increment ladder based on the current bid.
static func increment(current: int) -> int:
	if current < 100:
		return 10
	if current < 200:
		return 20
	if current < 500:
		return 25
	if current < 1500:
		return 50
	return 100


## The next valid bid for a lot. If nobody has bid yet, the opening bid is the base price.
static func next_bid(current: int, base: int, has_bidder: bool) -> int:
	if not has_bidder:
		return base
	# Snap to the clean ladder (…80, 90, 1 Cr, 1.2 Cr…) so a ₹75 L base goes 75 → 80 → 90.
	var step := increment(current)
	return (current / step + 1) * step


static func squad_count(team: Dictionary) -> int:
	return (team.get("squad", {}) as Dictionary).size()


static func overseas_count(team: Dictionary) -> int:
	var n := 0
	for pid in team.get("squad", {}):
		if DB.player(pid).get("overseas", false):
			n += 1
	return n


## The most a team may bid while still keeping enough money to reach MIN_SQUAD.
static func max_affordable(team: Dictionary) -> int:
	var count := squad_count(team)
	var slots_after := maxi(0, MIN_SQUAD - count - 1)
	return int(team.get("purse", 0)) - slots_after * MIN_PRICE


## Returns "" if the bid is allowed, otherwise a human-readable reason.
static func bid_error(team: Dictionary, player: Dictionary, amount: int) -> String:
	if squad_count(team) >= MAX_SQUAD:
		return "Squad full (%d)" % MAX_SQUAD
	if player.get("overseas", false) and overseas_count(team) >= MAX_OVERSEAS:
		return "Overseas limit reached (%d)" % MAX_OVERSEAS
	if amount > int(team.get("purse", 0)):
		return "Not enough purse"
	if amount > max_affordable(team):
		return "Must keep money to complete squad"
	return ""


static func can_bid(team: Dictionary, player: Dictionary, amount: int) -> bool:
	return bid_error(team, player, amount) == ""
