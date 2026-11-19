@tool
extends EditorPlugin
## Adds the GoogleSignIn Android plugin (bin/GoogleSignIn-release.aar, built from
## /android_plugin) and its Maven dependencies to Gradle-based Android exports.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = AndroidExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AndroidExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "GoogleSignIn"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["google_signin/bin/GoogleSignIn-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([
			"androidx.credentials:credentials:1.3.0",
			"androidx.credentials:credentials-play-services-auth:1.3.0",
			"com.google.android.libraries.identity.googleid:googleid:1.1.1",
			"com.google.android.gms:play-services-auth:21.2.0",
		])
