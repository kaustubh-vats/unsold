extends Node
## Firebase client for Godot (autoload "Firebase"): Auth + Realtime Database.
##
## Web exports use the official Firebase JS SDK through JavaScriptBridge.
## Android / desktop use the REST APIs (Identity Toolkit + RTDB + SSE streaming).
## Google sign-in on Android uses the native GoogleSignIn plugin (Credential Manager).
##
## Auth:  restore_session(), sign_up_email(), sign_in_email(), sign_in_google(),
##        reset_password(), sign_out()  →  "" on success, otherwise a readable error.
## Data:  get_value, set_value, update, transaction, listen/unlisten, server_now.

signal auth_changed

const Config := preload("res://scripts/firebase/config.gd")
const RestBackend := preload("res://scripts/firebase/rest_backend.gd")
const JsBackend := preload("res://scripts/firebase/js_backend.gd")

## Use as a value to write the server's current time.
const TIMESTAMP := {".sv": "timestamp"}

const ERRORS := {
	"EMAIL_EXISTS": "An account with this email already exists — sign in instead.",
	"auth/email-already-in-use": "An account with this email already exists — sign in instead.",
	"EMAIL_NOT_FOUND": "Wrong email or password.",
	"INVALID_PASSWORD": "Wrong email or password.",
	"INVALID_LOGIN_CREDENTIALS": "Wrong email or password.",
	"auth/invalid-credential": "Wrong email or password.",
	"auth/invalid-login-credentials": "Wrong email or password.",
	"auth/wrong-password": "Wrong email or password.",
	"auth/user-not-found": "Wrong email or password.",
	"WEAK_PASSWORD": "Password must be at least 6 characters.",
	"auth/weak-password": "Password must be at least 6 characters.",
	"INVALID_EMAIL": "Enter a valid email address.",
	"auth/invalid-email": "Enter a valid email address.",
	"MISSING_PASSWORD": "Enter your password.",
	"auth/missing-password": "Enter your password.",
	"USER_DISABLED": "This account has been disabled.",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "Too many attempts — please try again later.",
	"auth/too-many-requests": "Too many attempts — please try again later.",
	"auth/popup-closed-by-user": "cancelled",
	"auth/cancelled-popup-request": "cancelled",
	"auth/popup-blocked": "The browser blocked the Google popup — allow popups and try again.",
	"auth/network-request-failed": "No internet connection.",
	"NETWORK": "No internet connection.",
	"OPERATION_NOT_ALLOWED": "This sign-in method is not enabled.",
	"auth/operation-not-allowed": "This sign-in method is not enabled.",
	"GOOGLE_UNAVAILABLE": "Google sign-in is available in the Android app and on the web.",
}

var uid := ""
var email := ""
var display_name := ""
var server_offset_ms := 0
var backend: Node
var _restoring := false


func _ready() -> void:
	if OS.has_feature("web"):
		backend = JsBackend.new()
	else:
		backend = RestBackend.new()
	backend.name = "Backend"
	add_child(backend)


func is_configured() -> bool:
	return Config.is_configured()


func is_signed_in() -> bool:
	return uid != ""


func google_available() -> bool:
	return OS.has_feature("web") or Engine.has_singleton("GoogleSignIn")


static func friendly_error(code: String) -> String:
	if code == "":
		return ""
	for k in ERRORS:
		if code == k or code.begins_with(k + " ") or code.begins_with(k + ":"):
			return ERRORS[k]
	return "Sign-in failed (%s)" % code


# ------------------------------------------------------------------ auth

## Restores a saved session on startup. Returns true if signed in.
func restore_session() -> bool:
	if not is_configured() or _restoring:
		return is_signed_in()
	_restoring = true
	var r: Dictionary = await backend.restore_session()
	_restoring = false
	return await _apply_auth(r) == ""


func sign_up_email(mail: String, password: String, name: String) -> String:
	return await _apply_auth(await backend.sign_up_email(mail.strip_edges(), password, name.strip_edges()))


func sign_in_email(mail: String, password: String) -> String:
	return await _apply_auth(await backend.sign_in_email(mail.strip_edges(), password))


func sign_in_google() -> String:
	if not google_available():
		return friendly_error("GOOGLE_UNAVAILABLE")
	return await _apply_auth(await backend.sign_in_google(Config.google_web_client_id()))


func reset_password(mail: String) -> String:
	var r: Dictionary = await backend.reset_password(mail.strip_edges())
	return "" if r.get("ok", false) else friendly_error(str(r.get("error", "")))


func sign_out() -> void:
	await backend.sign_out()
	uid = ""
	email = ""
	display_name = ""
	auth_changed.emit()


func _apply_auth(r: Dictionary) -> String:
	if not r.get("ok", false):
		return friendly_error(str(r.get("error", "")))
	uid = str(r.get("uid", ""))
	email = str(r.get("email", ""))
	display_name = str(r.get("name", ""))
	if display_name == "" and email != "":
		display_name = email.split("@")[0]
	server_offset_ms = await backend.server_offset()
	auth_changed.emit()
	return ""


func server_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + server_offset_ms


# ------------------------------------------------------------------ data

func get_value(path: String):
	return await backend.get_value(path)


func set_value(path: String, value) -> bool:
	return await backend.set_value(path, clean(value))


func update(path: String, updates: Dictionary) -> bool:
	return await backend.update(path, clean(updates))


## Optimistic transaction: fn(current) returns the new value, or null to abort.
func transaction(path: String, fn: Callable, max_tries := 8) -> Dictionary:
	return await backend.transaction(path, func(cur):
		var n = fn.call(cur)
		return null if n == null else clean(n), max_tries)


func listen(path: String, cb: Callable) -> int:
	return backend.listen(path, cb)


func unlisten(handle: int) -> void:
	backend.unlisten(handle)


## Firebase stores integers; Godot parses JSON numbers as floats. Convert integral
## floats back to ints so values serialize cleanly (no "1.7e+12" or "120.0").
static func clean(v):
	match typeof(v):
		TYPE_FLOAT:
			if is_finite(v) and v == floor(v) and absf(v) < 9.0e15:
				return int(v)
			return v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = clean(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(clean(x))
			return a
	return v


static func to_json(v) -> String:
	return JSON.stringify(clean(v))
