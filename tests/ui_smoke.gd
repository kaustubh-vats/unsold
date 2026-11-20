extends SceneTree
## Visual smoke test: drives a single-player game through every screen and
## saves screenshots to user://smoke/. Run WITHOUT --headless:
##   godot --path . -s res://tests/ui_smoke.gd

var main: Control
var out_dir := ""


func _initialize() -> void:
	out_dir = OS.get_user_data_dir() + "/smoke"
	DirAccess.make_dir_recursive_absolute(out_dir)
	UI.set_light(false, false)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out_dir + "/" + name + ".png")
	print("shot ", out_dir + "/" + name + ".png")


func _run() -> void:
	var game = root.get_node("Game")
	await _wait(0.6)
	await _shot("1_home")
	game.goto("roster")
	await _wait(0.6)
	await _shot("1b_roster")
	game.goto("home")
	await _wait(0.3)
	game.player_name = "Tester"
	game.start_single()
	await _wait(0.5)
	var s = game.store
	await s.choose_team("CHE")
	await _wait(0.5)
	await _shot("2_lobby")
	await s.start_auction()
	await _wait(3.5)
	await _shot("3_auction_open")
	# Bid on the current lot as the human.
	await s.bid("CHE")
	await _wait(1.2)
	await _shot("4_auction_bid")
	# Let the live auction settle the lot to capture the SOLD stamp.
	for i in 120:
		if s.auction().get("phase", "") != "bidding":
			break
		await _wait(0.25)
	await _wait(0.5)
	await _shot("4b_sold")
	# Fast-forward a chunk of lots through the engine directly.
	s.auctioneer.set_process(false)
	var rng := RandomNumberGenerator.new()
	var now: int = s.now_ms()
	for i in 600:
		var a: Dictionary = s.state["auction"]
		if s.state["meta"]["status"] != "auction":
			break
		if a["phase"] == "bidding":
			# Human buys some cheap players so the squad screen has content.
			if rng.randf() < 0.25 and a.get("bidder", "") != "CHE" and Rules.can_bid(s.team("CHE"), DB.player(a["pid"]), Auction.current_next(s.state)):
				var n = Auction.apply_bid(a, "CHE", Auction.current_next(s.state), s.team("CHE"), now, 10000)
				if n != null:
					s.state["auction"] = n
					continue
			var c := AI.choose_bidder(s.state, rng)
			if c.is_empty():
				Auction.apply_updates(s.state, Auction.settle_updates(s.state, now))
			else:
				s.state["auction"] = Auction.apply_bid(a, c["team"], c["amount"], s.state["teams"][c["team"]], now, 10000)
		else:
			Auction.apply_updates(s.state, Auction.advance_updates(s.state, now))
		if i == 120:
			s.state["auction"]["ends"] = s.now_ms() + 8000
			s.changed.emit()
			await _wait(0.5)
			await _shot("5_auction_mid")
			var scr = main.screen
			scr._open_sheet("team:CHE")
			await _wait(0.6)
			await _shot("5b_sheet_my_squad")
			scr._open_sheet("teams")
			await _wait(0.4)
			await _shot("5c_sheet_teams")
			scr.sheet_back = ""
			scr._close_sheet()
			UI.set_light(true, false)
			game.theme_changed.emit()
			await _wait(0.6)
			await _shot("5d_auction_light")
			main.screen._open_sheet("team:CHE")
			await _wait(0.6)
			await _shot("5e_sheet_light")
			main.screen.sheet_back = ""
			main.screen._close_sheet()
	# Finish whatever is left.
	while s.state["meta"]["status"] == "auction":
		var a2: Dictionary = s.state["auction"]
		if a2["phase"] == "bidding":
			var c2 := AI.choose_bidder(s.state, rng)
			if c2.is_empty():
				Auction.apply_updates(s.state, Auction.settle_updates(s.state, now))
			else:
				s.state["auction"] = Auction.apply_bid(a2, c2["team"], c2["amount"], s.state["teams"][c2["team"]], now, 10000)
		else:
			Auction.apply_updates(s.state, Auction.advance_updates(s.state, now))
	s.changed.emit()
	s.auctioneer.set_process(true)
	await _wait(0.8)
	await _shot("6_review_light")
	await s.set_xi("CHE", XI.best_xi(s.team("CHE")["squad"].keys()))
	await s.set_ready(true)
	await _wait(1.5)
	await _shot("7_results_light")
	UI.set_light(false, false)
	game.theme_changed.emit()
	await _wait(0.3)
	await _shot("8_results_dark")
	print("SMOKE DONE")
	quit(0)
