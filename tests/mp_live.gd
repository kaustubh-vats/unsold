extends SceneTree
## Live multiplayer integration test against the real Firebase project.
## Run two processes:
##   godot --headless --path . -s res://tests/mp_live.gd -- --profile=a --role=host  --email=.. --password=.. --codefile=PATH
##   godot --headless --path . -s res://tests/mp_live.gd -- --profile=b --role=guest --email=.. --password=.. --codefile=PATH
## The host leaves mid-auction; the guest must take over as host and the auction must continue.
## Both delete their test account at the end; the last host deletes the room.

var args := {}
var game
var fb


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	_run()


func log_line(s: String) -> void:
	print("[%s %6.1fs] %s" % [args.get("role", "?"), Time.get_ticks_msec() / 1000.0, s])


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _run() -> void:
	game = root.get_node("Game")
	fb = root.get_node("Firebase")
	await _wait(0.5)
	var err: String = await fb.sign_in_email(args["email"], args["password"])
	if err != "":
		err = await fb.sign_up_email(args["email"], args["password"], "Test " + args["role"])
	if err != "":
		log_line("FAIL sign-in: " + err)
		quit(1)
		return
	log_line("signed in uid=%s name=%s offset=%dms" % [fb.uid, fb.display_name, fb.server_offset_ms])
	game.player_name = "Test " + args["role"]
	if args["role"] == "host":
		await _host()
	else:
		await _guest()


func _host() -> void:
	var err: String = await game.create_room()
	if err != "":
		log_line("FAIL create: " + err)
		quit(1)
		return
	var s = game.store
	log_line("room created " + s.room_code)
	var f := FileAccess.open(args["codefile"], FileAccess.WRITE)
	f.store_string(s.room_code)
	f.close()
	await s.choose_team("MUM")
	await s.set_setting("timer", 8)
	# Wait for the guest to join and pick a team.
	for i in 120:
		var players: Dictionary = s.state.get("players", {})
		var ready := players.size() >= 2 and players.values().all(func(p): return p.get("team", "") != "")
		if ready:
			break
		await _wait(0.5)
	log_line("players: %s" % str(s.state.get("players", {}).values().map(func(p): return [p.get("name"), p.get("team")])))
	await s.start_auction()
	log_line("auction started, status=" + s.status())
	var bids := 0
	var last_pid := ""
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(args.get("host_secs", "40")) * 1000:
		var a: Dictionary = s.auction()
		if a.get("phase", "") == "bidding" and a.get("pid", "") != last_pid and a.get("bidder", "") != "MUM":
			last_pid = a["pid"]
			if (await s.bid("MUM")) == "":
				bids += 1
			await s.pass_lot("MUM")
		await _wait(0.3)
	var a2: Dictionary = s.auction()
	log_line("HOST_SUMMARY bids_ok=%d lot_idx=%s log=%d" % [bids, str(a2.get("idx")), s.state.get("log", {}).size()])
	log_line("host leaving mid-auction (simulated crash)")
	await _delete_account()
	quit(0)


func _guest() -> void:
	var code := ""
	for i in 120:
		if FileAccess.file_exists(args["codefile"]):
			code = FileAccess.get_file_as_string(args["codefile"]).strip_edges()
			if code.length() == 6:
				break
		await _wait(0.5)
	var err: String = await game.join_room(code)
	if err != "":
		log_line("FAIL join: " + err)
		quit(1)
		return
	var s = game.store
	log_line("joined room " + code)
	await _wait(1.0)
	await s.choose_team("CHE")
	var bids_ok := 0
	var bids_fail := 0
	var lots := {}
	var last_pid := ""
	var took_host := false
	var host_uid := ""
	var idx_at_takeover := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(args.get("guest_secs", "90")) * 1000:
		if s.status() == "auction":
			var a: Dictionary = s.auction()
			lots[a.get("pid", "")] = true
			if host_uid == "":
				host_uid = s.meta().get("host", "")
			if a.get("phase", "") == "bidding" and a.get("pid", "") != last_pid and a.get("bidder", "") != "CHE":
				last_pid = a["pid"]
				var r: String = await s.bid("CHE")
				if r == "":
					bids_ok += 1
				else:
					bids_fail += 1
				await s.pass_lot("CHE")
			if not took_host and s.is_host():
				took_host = true
				idx_at_takeover = int(a.get("idx", 0))
				log_line("TOOK OVER AS HOST at lot %d" % idx_at_takeover)
			if took_host and int(a.get("idx", 0)) >= idx_at_takeover + 3:
				break
		await _wait(0.3)
	var a3: Dictionary = s.auction()
	var my_team: Dictionary = s.team("CHE")
	log_line("GUEST_SUMMARY bids_ok=%d bids_rejected=%d lots_seen=%d took_host=%s lot_idx_now=%s idx_at_takeover=%d squad=%d purse=%s" % [
		bids_ok, bids_fail, lots.size(), str(took_host), str(a3.get("idx")), idx_at_takeover,
		Rules.squad_count(my_team), str(my_team.get("purse"))])
	var passed: bool = bids_ok > 0 and took_host and int(a3.get("idx", 0)) >= idx_at_takeover + 3
	log_line("RESULT " + ("PASS" if passed else "FAIL"))
	# Cleanup: delete the room (we are host now) and our test account.
	if s.is_host():
		await fb.set_value("rooms/" + s.room_code, null)
		log_line("room deleted")
	await _delete_account()
	quit(0 if passed else 1)


func _delete_account() -> void:
	var be = fb.backend
	var r: Dictionary = await be._idt("accounts:delete", {"idToken": be.id_token})
	log_line("test account deleted: %s" % str(r.get("ok", false)))
	await fb.sign_out()
