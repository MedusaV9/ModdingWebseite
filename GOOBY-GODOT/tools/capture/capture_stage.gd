extends Node
## Trailer-Capture-Bühne (Agent TRAILER). NUR fürs Aufnehmen von Gameplay-
## Clips für den Update-Trailer — fasst KEINEN Spielcode an, sondern lädt
## Clip-Treiber aus res://tools/capture/clips/<name>.gd, die echte Spiel-
## Szenen mounten und per Eingabe-Injektion steuern.
##
## Aufruf (Movie-Maker-Modus, feste 60-fps-Schrittweite):
##   xvfb-run -a godot --path GOOBY-GODOT \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --resolution 1920x1080 --write-movie /tmp/out.avi --fixed-fps 60 \
##     res://tools/capture/capture_stage.tscn -- --clip=<name>

const CLIP_DIR := "res://tools/capture/clips"


func _ready() -> void:
	var clip_name := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="):
			clip_name = arg.trim_prefix("--clip=")
	if clip_name.is_empty():
		push_error("[capture] --clip=<name> fehlt")
		get_tree().quit(1)
		return
	var path := "%s/%s.gd" % [CLIP_DIR, clip_name]
	if not ResourceLoader.exists(path):
		push_error("[capture] Clip-Treiber fehlt: %s" % path)
		get_tree().quit(1)
		return
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		push_error("[capture] Clip-Skript lädt nicht (Parse-Fehler?): %s" % path)
		get_tree().quit(1)
		return
	var driver_obj: Object = script.new()
	if not (driver_obj is Node):
		push_error("[capture] Clip-Treiber ist kein Node: %s" % path)
		get_tree().quit(1)
		return
	var driver := driver_obj as Node
	driver.name = "ClipDriver"
	add_child(driver)
	print("[capture] Clip '%s' gestartet" % clip_name)
