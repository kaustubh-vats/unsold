extends Node
## Firebase backend for web exports: wraps the official Firebase JS SDK via
## JavaScriptBridge and res://web/firebase_bridge.js.

const Config := preload("res://scripts/firebase/config.gd")
const Pending := preload("res://scripts/firebase/pending.gd")

var _fb: JavaScriptObject
var _ready_ok := false
var _keep := []          # keep JS callbacks alive
var _listeners := {}
var _next_handle := 1


func _init_bridge() -> bool:
	if _ready_ok:
		return true
	JavaScriptBridge.eval(FileAccess.get_file_as_string("res://web/firebase_bridge.js"), true)
	_fb = JavaScriptBridge.get_interface("UnsoldFB")
	if _fb == null:
		return false
	var r = await _call("init", [JSON.stringify(Config.as_dict())])
	_ready_ok = r == "ok"
	if not _ready_ok:
		push_error("Firebase JS init failed: %s" % str(r))
	return _ready_ok


## Calls UnsoldFB.<method>(...args, callback) and awaits the callback's first argument.
func _call(method: String, args: Array):
	var p := Pending.new()
	var cb := JavaScriptBridge.create_callback(func(a: Array): p.resolve(a[0] if a.size() > 0 else null))
	_keep.append(cb)
	var full := args.duplicate()
	full.append(cb)
	_fb.callv(method, full)
	var v = await p.done
	_keep.erase(cb)
	return v


func _auth(method: String, args: Array) -> Dictionary:
	if not await _init_bridge():
		return {"ok": false, "error": "NETWORK"}
	var r = JSON.parse_string(str(await _call(method, args)))
	return r if typeof(r) == TYPE_DICTIONARY else {"ok": false, "error": "UNKNOWN"}


func restore_session() -> Dictionary:
	return await _auth("currentUser", [])


func sign_up_email(mail: String, password: String, name: String) -> Dictionary:
	return await _auth("signUpEmail", [mail, password, name])


func sign_in_email(mail: String, password: String) -> Dictionary:
	return await _auth("signInEmail", [mail, password])


func sign_in_google(_web_client_id: String) -> Dictionary:
	return await _auth("signInGoogle", [])


func reset_password(mail: String) -> Dictionary:
	return await _auth("resetPassword", [mail])


func sign_out() -> void:
	if _ready_ok:
		await _call("signOut", [])


func server_offset() -> int:
	# The SDK keeps the offset updated; read it after a short settle.
	await get_tree().create_timer(0.5).timeout
	return int(_fb.offset())


func get_value(path: String):
	return JSON.parse_string(str(await _call("get", [path])))


func set_value(path: String, value) -> bool:
	return str(await _call("set", [path, JSON.stringify(value)])) == "ok"


func update(path: String, updates: Dictionary) -> bool:
	return str(await _call("update", [path, JSON.stringify(updates)])) == "ok"


func transaction(path: String, fn: Callable, max_tries: int) -> Dictionary:
	var cur = await get_value(path)
	for i in max_tries:
		var nv = fn.call(cur)
		if nv == null:
			return {"ok": false, "value": cur}
		var raw = await _call("cas", [path, JSON.stringify(cur), JSON.stringify(nv)])
		var r = JSON.parse_string(str(raw))
		if typeof(r) == TYPE_DICTIONARY and r.get("ok", false):
			return {"ok": true, "value": nv}
		cur = r.get("value") if typeof(r) == TYPE_DICTIONARY else await get_value(path)
	return {"ok": false, "value": cur}


func listen(path: String, cb: Callable) -> int:
	var h := _next_handle
	_next_handle += 1
	var jcb := JavaScriptBridge.create_callback(func(a: Array):
		cb.call("put", "/", JSON.parse_string(str(a[0]))))
	_listeners[h] = jcb
	_fb.listen(path, h, jcb)
	return h


func unlisten(handle: int) -> void:
	if _listeners.has(handle):
		_fb.unlisten(handle)
		_listeners.erase(handle)
