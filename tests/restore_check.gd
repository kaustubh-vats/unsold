extends SceneTree
## Session restore check. Run once with --email/--password to sign in (saves the
## session), then again without them to verify the session is restored on start.

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var fb = root.get_node("Firebase")
	await create_timer(0.3).timeout
	if args.has("email"):
		print("sign in: '", await fb.sign_in_email(args["email"], args["password"]), "' uid=", fb.uid)
	else:
		var t0 := Time.get_ticks_msec()
		while not fb.is_signed_in() and Time.get_ticks_msec() - t0 < 15000:
			await create_timer(0.2).timeout
		print("restored: ", fb.is_signed_in(), " uid=", fb.uid, " name=", fb.display_name, " after ", Time.get_ticks_msec() - t0, "ms")
	quit(0)
