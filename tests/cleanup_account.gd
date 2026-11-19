extends SceneTree
## Deletes a throwaway test account and any rooms it hosts.
## godot --headless --path . -s res://tests/cleanup_account.gd -- --email=.. --password=.. [--room=CODE]

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
	var err: String = await fb.sign_in_email(args.get("email", ""), args.get("password", ""))
	if err != "":
		print("sign-in failed: ", err)
		quit(1)
		return
	if args.has("room"):
		var ok: bool = await fb.set_value("rooms/" + args["room"], null)
		print("room ", args["room"], " deleted: ", ok)
	var be = fb.backend
	var r: Dictionary = await be._idt("accounts:delete", {"idToken": be.id_token})
	print("account deleted: ", r.get("ok", false))
	await fb.sign_out()
	quit(0)
