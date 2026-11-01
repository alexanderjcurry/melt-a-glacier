extends SceneTree
## Store builds run this first and stop if anything is still a placeholder:
##   godot --headless -s res://tests/release_check.gd -- Android   (or iOS)
## Lists every missing id (see docs/LAUNCH.md for where each one comes from).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var os_name: String = args[0] if args.size() > 0 else "Android"
	var Config = load("res://scripts/monetization/store_config.gd")
	var missing: PackedStringArray = Config.missing_for_release(os_name)
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	for section in presets.get_sections():
		if presets.get_value(section, "platform", "") == os_name \
				and str(presets.get_value(section, "custom_features", "")).contains("playtest"):
			missing.append("export preset %s still has the 'playtest' feature (dev menu)" % os_name)
	var policy := FileAccess.get_file_as_string("res://docs/privacy.html")
	if policy.contains("CONTACT_EMAIL"):
		missing.append("docs/privacy.html: a contact email instead of CONTACT_EMAIL")
	if missing.is_empty():
		print("Release check (%s): everything is filled in." % os_name)
		quit(0)
		return
	print("Release check (%s) FAILED. Still to fill in:" % os_name)
	for m in missing:
		print("  - " + m)
	quit(1)
