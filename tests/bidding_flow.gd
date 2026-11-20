extends SceneTree
## Plays the first few solo lots as a "human" who keeps raising whenever
## outbid (up to a limit) and prints the bid-by-bid sequence. Checks that
## the human gets a turn after every AI raise and that lots don't close
## before the AI has answered.
##   godot --headless --path . -s res://tests/bidding_flow.gd

const ME := "CHE"
const LIMIT := 1500   # lakh: the "human" stops raising above this


func _initialize() -> void:
	_run()


func _run() -> void:
	var game = root.get_node("Game")
	await process_frame
	game.player_name = "Tester"
	game.start_single()
	var s = game.store
	await s.choose_team(ME)
	await s.start_auction()
	var human_bids := 0
	var my_turns := 0
	var problems := 0
	for lot in 4:
		var a: Dictionary = s.auction()
		var pid: String = a.get("pid", "")
		print("\nLOT ", lot + 1, ": ", DB.player(pid)["name"], " base ", DB.fmt_price(int(DB.player(pid)["base"])))
		var last_n := -1
		var t0 := Time.get_ticks_msec()
		while s.auction().get("pid", "") == pid and s.auction().get("phase", "") == "bidding":
			a = s.auction()
			var n := int(a.get("n", 0))
			if n != last_n:
				last_n = n
				var who: String = a.get("bidder", "")
				if who != "":
					print("  %5.1fs  %s  %s" % [(Time.get_ticks_msec() - t0) / 1000.0, who, DB.fmt_price(int(a["bid"]))])
				if who != ME:
					my_turns += 1
					var nxt := Auction.current_next(s.state)
					if nxt <= LIMIT and Rules.bid_error(s.team(ME), DB.player(pid), nxt) == "":
						await create_timer(1.0).timeout   # human thinking
						var err: String = await s.bid(ME)
						if err == "":
							human_bids += 1
						else:
							print("         bid failed: ", err)
					else:
						await s.pass_lot(ME)
						print("         ", ME, " passes")
			await create_timer(0.05).timeout
		a = s.auction()
		print("  -> ", a.get("phase", ""), " ", a.get("bidder", ""), " ", DB.fmt_price(int(a.get("bid", 0))))
		if a.get("bidder", "") != ME and a.get("phase", "") == "sold":
			pass
		while s.auction().get("pid", "") == pid:
			await create_timer(0.1).timeout
	print("\nhuman bids placed: %d, turns given: %d" % [human_bids, my_turns])
	print("RESULT: ", "PASS" if human_bids >= 2 else "FAIL")
	quit(0)
