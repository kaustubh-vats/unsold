extends Node
## Firebase REST backend (Android, desktop). Email/Google auth via Identity Toolkit,
## data via RTDB REST, realtime via Server-Sent Events, transactions via ETags.

const Config := preload("res://scripts/firebase/config.gd")
const SseStream := preload("res://scripts/firebase/sse_stream.gd")
const AUTH_FILE := "user://firebase_auth.cfg"

var id_token := ""
var refresh_token := ""
var token_expires_ms := 0
var uid := ""
var _listeners := {}
var _next_handle := 1


# ---------------------------------------------------------------- HTTP helper

func _http(method: int, url: String, body := "", headers := PackedStringArray()) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return {"code": 0, "body": "", "headers": PackedStringArray()}
	var res: Array = await req.request_completed
	req.queue_free()
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	return {"code": int(res[1]), "body": text, "headers": res[2]}


static func _header(headers: PackedStringArray, name: String) -> String:
	for h in headers:
		var i := h.find(":")
		if i > 0 and h.substr(0, i).strip_edges().to_lower() == name.to_lower():
			return h.substr(i + 1).strip_edges()
	return ""


# ---------------------------------------------------------------- Auth
# Email/password and Google via the Identity Toolkit REST API. Sessions persist
# as a refresh token in user:// (per profile, so tests can run two players).

const IDT := "https://identitytoolkit.googleapis.com/v1/"
var email := ""
var display_name := ""


func _auth_file() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			return "user://firebase_auth_%s.cfg" % a.substr(10).validate_filename()
	return AUTH_FILE


func _idt(endpoint: String, body: Dictionary) -> Dictionary:
	var r := await _http(HTTPClient.METHOD_POST, IDT + endpoint + "?key=" + Config.api_key(),
		JSON.stringify(body), PackedStringArray(["Content-Type: application/json"]))
	if r["code"] == 0:
		return {"ok": false, "error": "NETWORK"}
	var d = JSON.parse_string(r["body"])
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "error": "HTTP_%d" % r["code"]}
	if r["code"] != 200:
		return {"ok": false, "error": str(d.get("error", {}).get("message", "HTTP_%d" % r["code"]))}
	d["ok"] = true
	return d


func _session(d: Dictionary) -> Dictionary:
	email = str(d.get("email", email))
	display_name = str(d.get("displayName", d.get("fullName", display_name)))
	_set_tokens(d["idToken"], d["refreshToken"], int(d["expiresIn"]), d["localId"])
	return {"ok": true, "uid": uid, "email": email, "name": display_name}


func restore_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_auth_file()) != OK:
		return {"ok": false, "error": "NO_SESSION"}
	refresh_token = cfg.get_value("auth", "refresh_token", "")
	email = cfg.get_value("auth", "email", "")
	display_name = cfg.get_value("auth", "name", "")
	if refresh_token == "":
		return {"ok": false, "error": "NO_SESSION"}
	# Retry network failures (slow startup, flaky mobile data); stop if the token is rejected.
	for attempt in 4:
		var code := await _refresh_code()
		if code == 200:
			return {"ok": true, "uid": uid, "email": email, "name": display_name}
		push_warning("Firebase session restore attempt %d failed (HTTP %d)" % [attempt + 1, code])
		if code != 0 and code < 500:
			break
		await get_tree().create_timer(2.0 * (attempt + 1)).timeout
	return {"ok": false, "error": "NO_SESSION"}


func sign_up_email(mail: String, password: String, name: String) -> Dictionary:
	var d := await _idt("accounts:signUp", {"email": mail, "password": password, "returnSecureToken": true})
	if not d["ok"]:
		return d
	if name != "":
		var u := await _idt("accounts:update", {"idToken": d["idToken"], "displayName": name, "returnSecureToken": true})
		if u["ok"]:
			d["displayName"] = name
			d["idToken"] = u.get("idToken", d["idToken"])
			d["refreshToken"] = u.get("refreshToken", d["refreshToken"])
	return _session(d)


func sign_in_email(mail: String, password: String) -> Dictionary:
	var d := await _idt("accounts:signInWithPassword", {"email": mail, "password": password, "returnSecureToken": true})
	if not d["ok"]:
		return d
	return _session(d)


func reset_password(mail: String) -> Dictionary:
	return await _idt("accounts:sendOobCode", {"requestType": "PASSWORD_RESET", "email": mail})


## Native Google account picker (Android plugin) → ID token → Firebase session.
func sign_in_google(web_client_id: String) -> Dictionary:
	if not Engine.has_singleton("GoogleSignIn"):
		return {"ok": false, "error": "GOOGLE_UNAVAILABLE"}
	var plugin = Engine.get_singleton("GoogleSignIn")
	var result := [null]
	var ok_cb := func(token: String, mail: String, name: String): result[0] = {"token": token, "email": mail, "name": name}
	var fail_cb := func(msg: String): result[0] = {"error": msg}
	plugin.sign_in_success.connect(ok_cb)
	plugin.sign_in_failed.connect(fail_cb)
	plugin.signIn(web_client_id)
	while result[0] == null:
		await get_tree().process_frame
	plugin.sign_in_success.disconnect(ok_cb)
	plugin.sign_in_failed.disconnect(fail_cb)
	var g: Dictionary = result[0]
	if g.has("error"):
		return {"ok": false, "error": "cancelled" if g["error"] == "cancelled" else "GOOGLE: " + g["error"]}
	var d := await _idt("accounts:signInWithIdp", {
		"postBody": "id_token=%s&providerId=google.com" % g["token"],
		"requestUri": "http://localhost", "returnSecureToken": true, "returnIdpCredential": true})
	if not d["ok"]:
		return d
	if str(d.get("displayName", "")) == "":
		d["displayName"] = g["name"]
	return _session(d)


func sign_out() -> void:
	if Engine.has_singleton("GoogleSignIn"):
		Engine.get_singleton("GoogleSignIn").signOut()
	for h in _listeners.keys():
		unlisten(h)
	id_token = ""
	refresh_token = ""
	uid = ""
	email = ""
	display_name = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_auth_file()))


func _refresh() -> bool:
	return await _refresh_code() == 200


## Exchanges the refresh token for a new ID token. Returns the HTTP code (0 = network error).
func _refresh_code() -> int:
	var url := "https://securetoken.googleapis.com/v1/token?key=" + Config.api_key()
	var body := "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode()
	var r := await _http(HTTPClient.METHOD_POST, url, body,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]))
	if r["code"] != 200:
		return int(r["code"])
	var d: Dictionary = JSON.parse_string(r["body"])
	_set_tokens(d["id_token"], d["refresh_token"], int(d["expires_in"]), d["user_id"])
	return 200


func _set_tokens(idt: String, rt: String, expires_in: int, user_id: String) -> void:
	id_token = idt
	refresh_token = rt
	uid = user_id
	token_expires_ms = Time.get_ticks_msec() + (expires_in - 120) * 1000
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", rt)
	cfg.set_value("auth", "email", email)
	cfg.set_value("auth", "name", display_name)
	cfg.save(_auth_file())

func _ensure_token() -> void:
	if Time.get_ticks_msec() > token_expires_ms and refresh_token != "":
		await _refresh()


func _url(path: String, extra := "") -> String:
	var p := path.strip_edges().trim_prefix("/").trim_suffix("/")
	return "%s/%s.json?auth=%s%s" % [Config.database_url().trim_suffix("/"), p, id_token, extra]


# ---------------------------------------------------------------- Data

func server_offset() -> int:
	await _ensure_token()
	var t0 := Time.get_unix_time_from_system() * 1000.0
	var r := await _http(HTTPClient.METHOD_PUT, _url("time_probe/" + uid), '{".sv":"timestamp"}')
	var t1 := Time.get_unix_time_from_system() * 1000.0
	if r["code"] != 200:
		return 0
	var server = JSON.parse_string(r["body"])
	if typeof(server) != TYPE_FLOAT and typeof(server) != TYPE_INT:
		return 0
	return int(float(server) - (t0 + t1) / 2.0)


func get_value(path: String):
	await _ensure_token()
	var r := await _http(HTTPClient.METHOD_GET, _url(path))
	if r["code"] != 200:
		return null
	return JSON.parse_string(r["body"])


func set_value(path: String, value) -> bool:
	await _ensure_token()
	var r := await _http(HTTPClient.METHOD_PUT, _url(path, "&print=silent"), JSON.stringify(value))
	return r["code"] == 200 or r["code"] == 204


func update(path: String, updates: Dictionary) -> bool:
	await _ensure_token()
	var r := await _http(HTTPClient.METHOD_PATCH, _url(path, "&print=silent"), JSON.stringify(updates))
	if r["code"] != 200 and r["code"] != 204:
		push_warning("Firebase update failed (%d): %s" % [r["code"], r["body"]])
	return r["code"] == 200 or r["code"] == 204


func transaction(path: String, fn: Callable, max_tries: int) -> Dictionary:
	for i in max_tries:
		await _ensure_token()
		var g := await _http(HTTPClient.METHOD_GET, _url(path),
			"", PackedStringArray(["X-Firebase-ETag: true"]))
		if g["code"] != 200:
			return {"ok": false, "value": null}
		var etag := _header(g["headers"], "ETag")
		var cur = JSON.parse_string(g["body"])
		var nv = fn.call(cur)
		if nv == null:
			return {"ok": false, "value": cur}
		var p := await _http(HTTPClient.METHOD_PUT, _url(path), JSON.stringify(nv),
			PackedStringArray(["if-match: " + etag]))
		if p["code"] == 200:
			return {"ok": true, "value": nv}
		if p["code"] != 412:
			return {"ok": false, "value": cur}
	return {"ok": false, "value": null}


# ---------------------------------------------------------------- Realtime

func listen(path: String, cb: Callable) -> int:
	var h := _next_handle
	_next_handle += 1
	var s: Node = SseStream.new()
	s.url_provider = func():
		await _ensure_token()
		return _url(path)
	s.event.connect(func(kind: String, data: Dictionary):
		if kind == "put" or kind == "patch":
			cb.call(kind, data.get("path", "/"), data.get("data")))
	add_child(s)
	s.start()
	_listeners[h] = s
	return h


func unlisten(handle: int) -> void:
	if _listeners.has(handle):
		_listeners[handle].stop()
		_listeners[handle].queue_free()
		_listeners.erase(handle)
