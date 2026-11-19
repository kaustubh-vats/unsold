class_name Score
extends RefCounted
## "Team Score" win mode: rates each squad instantly.

const BAT_W := [1.2, 1.2, 1.15, 1.1, 1.0, 0.9, 0.75, 0.4]


## Returns {total, grade, batting, bowling, balance, depth, value, notes}
static func rate(team: Dictionary, xi: Array) -> Dictionary:
	var squad: Array = team.get("squad", {}).keys()
	if xi.is_empty():
		xi = XI.best_xi(squad)
	if squad.is_empty():
		squad = xi.duplicate()
	var notes := []
	# Batting: top 8 batters by bat rating, weighted.
	var bats := xi.map(func(id): return int(DB.player(id)["bat"]))
	bats.sort()
	bats.reverse()
	var bsum := 0.0
	var wsum := 0.0
	for i in mini(bats.size(), BAT_W.size()):
		bsum += bats[i] * BAT_W[i]
		wsum += BAT_W[i]
	var batting := bsum / wsum if wsum > 0 else 0.0
	# Bowling: best five bowlers, plus a sixth-option bonus.
	var bowls := xi.map(func(id): return int(DB.player(id)["bowl"]))
	bowls.sort()
	bowls.reverse()
	var top5 := 0.0
	for i in mini(5, bowls.size()):
		top5 += bowls[i]
	var bowling := top5 / 5.0
	if bowls.size() >= 6 and bowls[5] >= XI.BOWL_OPTION:
		bowling += 2.0
	# Balance.
	var balance := 10.0
	for pr in XI.problems(xi, squad):
		balance -= 6.0
		notes.append(pr)
	var pace := 0
	var spin := 0
	for id in xi:
		var p := DB.player(id)
		if p["bowl"] >= XI.BOWL_OPTION:
			if p["role"] == "SPIN" or (p["role"] == "AR" and p["trait"] != "pp" and p["trait"] != "dth" and int(p["bowl"]) < 80):
				spin += 1
			else:
				pace += 1
	if pace < 2:
		balance -= 4.0
		notes.append("Short of pace")
	if spin < 1:
		balance -= 3.0
		notes.append("No spinner")
	var has_death := xi.any(func(id): return DB.player(id)["trait"] == "dth")
	if not has_death:
		balance -= 2.0
		notes.append("No death-overs specialist")
	# Depth: bench quality.
	var bench := squad.filter(func(id): return not xi.has(id))
	bench.sort_custom(func(a, b): return DB.player(a)["ovr"] > DB.player(b)["ovr"])
	var depth := 0.0
	for i in mini(5, bench.size()):
		depth += DB.player(bench[i])["ovr"]
	depth = depth / 5.0 if bench.size() > 0 else 0.0
	if squad.size() < Rules.MIN_SQUAD:
		notes.append("Squad below %d" % Rules.MIN_SQUAD)
	# Value: rating bought per crore.
	var spent := Rules.PURSE - int(team.get("purse", Rules.PURSE))
	var ovr_sum := 0.0
	for id in squad:
		ovr_sum += DB.player(id)["ovr"]
	var value := clampf((ovr_sum / maxf(1.0, spent / 100.0)) / 2.0, 0.0, 10.0)
	var total := batting * 0.42 + bowling * 0.42 + balance + depth * 0.06 + value * 0.3
	total = clampf(total, 0.0, 100.0)
	return {
		"total": snappedf(total, 0.1), "grade": grade(total),
		"batting": snappedf(batting, 0.1), "bowling": snappedf(bowling, 0.1),
		"balance": snappedf(balance, 0.1), "depth": snappedf(depth, 0.1),
		"value": snappedf(value, 0.1), "notes": notes,
	}


static func grade(t: float) -> String:
	if t >= 88: return "A+"
	if t >= 84: return "A"
	if t >= 80: return "B+"
	if t >= 76: return "B"
	if t >= 72: return "C+"
	if t >= 68: return "C"
	return "D"


## Ranking of all teams: Array of {team, ...rate}
static func leaderboard(state: Dictionary) -> Array:
	var rows := []
	var teams: Dictionary = state.get("teams", {})
	for tid in teams:
		var r := rate(teams[tid], teams[tid].get("xi", []))
		r["team"] = tid
		rows.append(r)
	rows.sort_custom(func(a, b): return a["total"] > b["total"])
	return rows
