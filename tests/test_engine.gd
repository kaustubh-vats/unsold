extends RefCounted

var runner


func ok(cond: bool, msg: String) -> void:
	runner.check(cond, msg)


func test_data_loads() -> void:
	ok(DB.all_ids().size() >= 200, "at least 200 players, got %d" % DB.all_ids().size())
	ok(DB.teams().size() == 10, "10 teams")
	var os := 0
	for id in DB.all_ids():
		if DB.player(id)["overseas"]:
			os += 1
	ok(os >= 60, "enough overseas players (%d)" % os)


func test_increments() -> void:
	ok(Rules.next_bid(0, 200, false) == 200, "opening bid is base price")
	ok(Rules.next_bid(50, 30, true) == 60, "+10 under 1 Cr")
	ok(Rules.next_bid(120, 30, true) == 140, "+20 under 2 Cr")
	ok(Rules.next_bid(400, 30, true) == 425, "+25 under 5 Cr")
	ok(Rules.next_bid(1000, 30, true) == 1050, "+50 under 15 Cr")
	ok(Rules.next_bid(1500, 30, true) == 1600, "+100 above 15 Cr")
	ok(Rules.next_bid(75, 75, true) == 80, "odd base snaps to the ladder")
	ok(Rules.next_bid(190, 30, true) == 200, "ladder crosses 2 Cr cleanly")


func test_purse_reserve_and_caps() -> void:
	var p := DB.player(DB.all_ids()[0])
	var team := {"purse": 1000, "squad": {}}
	# Empty squad must keep 17 * 30 = 510 for the rest.
	ok(Rules.max_affordable(team) == 490, "reserve for remaining slots")
	ok(Rules.can_bid(team, p, 490), "can bid up to reserve")
	ok(not Rules.can_bid(team, p, 500), "cannot exceed reserve")
	var os_team := {"purse": 12000, "squad": {}}
	var overseas := DB.all_ids().filter(func(id): return DB.player(id)["overseas"])
	for i in 8:
		os_team["squad"][overseas[i]] = 30
	ok(not Rules.can_bid(os_team, DB.player(overseas[9]), 100), "overseas cap enforced")
	var full := {"purse": 12000, "squad": {}}
	for i in 25:
		full["squad"][DB.all_ids()[i]] = 30
	ok(not Rules.can_bid(full, p, 100), "squad cap enforced")


func test_apply_bid_validation() -> void:
	var pid: String = DB.all_ids()[0]
	var a := {"pid": pid, "bid": 0, "bidder": "", "phase": "bidding", "ends": 10000, "passes": {}}
	var team := {"purse": 12000, "squad": {}}
	var base := int(DB.player(pid)["base"])
	ok(Auction.apply_bid(a, "MUM", base - 10, team, 5000, 10000) == null, "bid below the next increment rejected")
	var n = Auction.apply_bid(a, "MUM", base, team, 5000, 10000)
	ok(n != null and n["bidder"] == "MUM", "valid opening bid")
	ok(Auction.apply_bid(n, "MUM", Rules.next_bid(base, base, true), team, 5000, 10000) == null, "cannot outbid yourself")
	ok(Auction.apply_bid(a, "MUM", base, team, 20000, 10000) == null, "expired lot rejected")


func test_xi_valid() -> void:
	var squad := DB.all_ids().slice(0, 10) + DB.all_ids().slice(19, 22) + DB.all_ids().slice(28, 36) + DB.all_ids().slice(42, 52)
	var xi := XI.best_xi(squad)
	ok(xi.size() == 11, "XI has 11")
	ok(XI.problems(xi, squad).is_empty(), "XI valid: %s" % str(XI.problems(xi, squad)))


## A squad short of domestic players must still be able to field a legal XI.
func test_overseas_heavy_squad_can_field_xi() -> void:
	var os_ids := DB.all_ids().filter(func(id): return DB.player(id)["overseas"])
	var dom_ids := DB.all_ids().filter(func(id): return not DB.player(id)["overseas"])
	var squad: Array = os_ids.slice(0, 9) + dom_ids.slice(0, 4)
	var xi := XI.best_xi(squad)
	ok(xi.size() == 11, "fields 11 (got %d)" % xi.size())
	ok(XI.allowed_overseas(squad) == 7, "allows 7 overseas when only 4 domestic")
	ok(XI.problems(xi, squad).is_empty(), "valid: %s" % str(XI.problems(xi, squad)))


func test_set_path() -> void:
	var s := {}
	Auction.apply_updates(s, {"teams/MUM/purse": 100, "teams/MUM/squad/p001": 50, "auction": {"idx": 2}})
	ok(s["teams"]["MUM"]["squad"]["p001"] == 50, "nested set")
	Auction.apply_updates(s, {"teams/MUM/squad/p001": null})
	ok(s["teams"]["MUM"]["squad"].is_empty(), "null deletes")
	ok(Auction.read_path(s, "auction/idx") == 2, "get_path")


## Run a full auction with only AI teams and check every squad is legal.
func test_full_ai_auction() -> void:
	var state := {"meta": {"host": "x", "status": "lobby", "seed": 42,
		"settings": {"timer": 10, "ai_fill": true, "win_mode": "season"}}, "players": {}}
	var now := 0
	Auction.apply_updates(state, Auction.start_updates(state, now))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var guard := 0
	while state["meta"]["status"] == "auction" and guard < 20000:
		guard += 1
		var a: Dictionary = state["auction"]
		if a["phase"] == "bidding":
			var c := AI.choose_bidder(state, rng)
			if c.is_empty():
				now = int(a["ends"])
				Auction.apply_updates(state, Auction.settle_updates(state, now))
			else:
				now += 500
				var n = Auction.apply_bid(a, c["team"], c["amount"], state["teams"][c["team"]], now, 10000)
				ok(n != null, "AI bid accepted")
				if n == null:
					break
				state["auction"] = n
		else:
			now = int(a["ends"])
			Auction.apply_updates(state, Auction.advance_updates(state, now))
	ok(state["meta"]["status"] == "review", "auction finished")
	var sold := 0
	for tid in state["teams"]:
		var t: Dictionary = state["teams"][tid]
		var n := Rules.squad_count(t)
		sold += n
		ok(n >= Rules.MIN_SQUAD and n <= Rules.MAX_SQUAD, "%s squad size %d" % [tid, n])
		ok(int(t["purse"]) >= 0, "%s purse non-negative" % tid)
		ok(Rules.overseas_count(t) <= Rules.MAX_OVERSEAS, "%s overseas" % tid)
		ok(XI.problems(t["xi"], t["squad"].keys()).is_empty(), "%s XI valid %s" % [tid, str(XI.problems(t["xi"], t["squad"].keys()))])
	print("        AI auction: %d players sold, %d steps" % [sold, guard])
	var top := Score.leaderboard(state)
	print("        Score leader: %s %.1f (%s), last %.1f" % [top[0]["team"], top[0]["total"], top[0]["grade"], top[-1]["total"]])
	var xis := {}
	for tid in state["teams"]:
		xis[tid] = state["teams"][tid]["xi"]
	var s := Sim.season(xis, 42)
	ok(s["champion"] != "", "season has a champion")
	ok(s["matches"].size() == 45, "45 league matches")


## Several seeds: every auction must finish with legal squads and XIs.
func test_many_auctions_valid() -> void:
	for seed in [1, 2, 3, 5, 8, 13]:
		_ai_auction(seed, ["easy", "medium", "hard"][seed % 3])


## Difficulty: harder AI pays more for players and leaves fewer bargains.
func test_difficulty_levels() -> void:
	var spent := {}
	for d in ["easy", "medium", "hard"]:
		var total := 0
		for seed in [4, 7]:
			var state := _ai_auction(seed, d)
			for tid in state["teams"]:
				total += Rules.PURSE - int(state["teams"][tid]["purse"])
		spent[d] = total / 2
		print("      %s: avg ₹%.0f Cr spent across 10 teams" % [d, spent[d] / 100.0])
	ok(spent["easy"] < spent["medium"] and spent["medium"] < spent["hard"], "easy < medium < hard spending")


func _ai_auction(seed: int, diff: String) -> Dictionary:
	if true:
		var state := {"meta": {"host": "x", "status": "lobby", "seed": seed,
			"settings": {"timer": 10, "ai_fill": true, "win_mode": "score", "difficulty": diff}}, "players": {}}
		var now := 0
		Auction.apply_updates(state, Auction.start_updates(state, now))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var guard := 0
		while state["meta"]["status"] == "auction" and guard < 20000:
			guard += 1
			var a: Dictionary = state["auction"]
			if a["phase"] == "bidding":
				var c := AI.choose_bidder(state, rng)
				if c.is_empty():
					Auction.apply_updates(state, Auction.settle_updates(state, now))
				else:
					now += 400
					state["auction"] = Auction.apply_bid(a, c["team"], c["amount"], state["teams"][c["team"]], now, 10000)
			else:
				now = int(a["ends"])
				Auction.apply_updates(state, Auction.advance_updates(state, now))
		ok(state["meta"]["status"] == "review", "seed %d finished" % seed)
		var top := 0
		for tid in state["teams"]:
			var t: Dictionary = state["teams"][tid]
			var n := Rules.squad_count(t)
			ok(n >= Rules.MIN_SQUAD and n <= Rules.MAX_SQUAD, "seed %d %s squad %d" % [seed, tid, n])
			ok(XI.problems(t["xi"], t["squad"].keys()).is_empty(), "seed %d %s XI %s" % [seed, tid, str(XI.problems(t["xi"], t["squad"].keys()))])
			for pid in t["squad"]:
				top = maxi(top, int(t["squad"][pid]))
		ok(top >= 1200 and top <= 3500, "seed %d (%s) top price realistic (%s)" % [seed, diff, DB.fmt_price(top)])
		return state
	return {}


func test_season_deterministic() -> void:
	var ids := DB.all_ids()
	var xis := {"A": XI.best_xi(ids.slice(0, 22)), "B": XI.best_xi(ids.slice(22, 44)),
		"C": XI.best_xi(ids.slice(44, 66)), "D": XI.best_xi(ids.slice(66, 88))}
	var s1 := Sim.season(xis, 99)
	var s2 := Sim.season(xis, 99)
	ok(JSON.stringify(s1) == JSON.stringify(s2), "same seed → same season")
	var s3 := Sim.season(xis, 100)
	ok(JSON.stringify(s1) != JSON.stringify(s3), "different seed → different season")


func test_scores_realistic() -> void:
	var ids := DB.all_ids()
	var xi := XI.best_xi(ids.slice(0, 40))
	var total := 0
	var wk := 0
	var n := 200
	for i in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var inn := Sim.innings(xi, xi, -1, rng)
		total += inn["runs"]
		wk += inn["wkts"]
	var avg := total / float(n)
	print("        avg first-innings score %.1f, avg wickets %.1f" % [avg, wk / float(n)])
	ok(avg > 140 and avg < 215, "average T20 score realistic (%.1f)" % avg)


func test_stronger_team_wins_more() -> void:
	var ids := DB.all_ids()
	ids.sort_custom(func(a, b): return DB.player(a)["ovr"] > DB.player(b)["ovr"])
	var strong := XI.best_xi(ids.slice(0, 30))
	var weak := XI.best_xi(ids.slice(ids.size() - 40, ids.size()))
	var wins := 0
	for i in 100:
		var m := Sim.play_match("S", "W", strong, weak, "t%d" % i)
		if m["winner"] == "S":
			wins += 1
	print("        strong beat weak %d/100" % wins)
	ok(wins >= 70, "stronger XI wins most matches (%d)" % wins)
	var s := Score.rate({"squad": {}, "purse": 0}, strong)
	var w := Score.rate({"squad": {}, "purse": 0}, weak)
	ok(s["total"] > w["total"], "team score ranks strong above weak")
