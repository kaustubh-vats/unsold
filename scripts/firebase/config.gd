extends RefCounted
## Firebase settings loader. Real values live in `config.local.gd` (git-ignored);
## if it's missing, the placeholder template `config.example.gd` is used and
## online play is disabled. See README.md → "Firebase setup".

const LOCAL_PATH := "res://scripts/firebase/config.local.gd"
const EXAMPLE_PATH := "res://scripts/firebase/config.example.gd"

static var _cfg: GDScript


static func _c() -> GDScript:
	if _cfg == null:
		_cfg = load(LOCAL_PATH) if ResourceLoader.exists(LOCAL_PATH) else load(EXAMPLE_PATH)
	return _cfg


static func _val(key: String) -> String:
	return str(_c().get_script_constant_map().get(key, ""))


static func api_key() -> String:
	return _val("API_KEY")


static func database_url() -> String:
	return _val("DATABASE_URL")


static func google_web_client_id() -> String:
	return _val("GOOGLE_WEB_CLIENT_ID")


static func is_configured() -> bool:
	return not api_key().begins_with("YOUR_") and api_key() != "" and not database_url().contains("YOUR_PROJECT_ID")


static func as_dict() -> Dictionary:
	return {
		"apiKey": api_key(), "authDomain": _val("AUTH_DOMAIN"), "databaseURL": database_url(),
		"projectId": _val("PROJECT_ID"), "appId": _val("APP_ID"),
	}
