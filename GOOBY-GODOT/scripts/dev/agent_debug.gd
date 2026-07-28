class_name AgentDebug
extends RefCounted
## Session-Debug-Logger (NDJSON) fuer Debug-Mode-Instrumentierung.
## Schreibt nach res://../debug-61ebfd.log (Repo-Root) und faellt auf
## user://debug-61ebfd.log zurueck.

const SESSION := "61ebfd"
const LOG_NAME := "debug-61ebfd.log"


static func log(
	hypothesis_id: String, location: String, message: String, data: Dictionary = {}
) -> void:
	var payload := {
		"sessionId": SESSION,
		"hypothesisId": hypothesis_id,
		"location": location,
		"message": message,
		"data": data,
		"timestamp": Time.get_unix_time_from_system() * 1000.0,
		"runId": "post-fix",
	}
	var line := JSON.stringify(payload)
	var path := _resolve_path()
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()


static func _resolve_path() -> String:
	# Repo-Root = Parent von GOOBY-GODOT (project root).
	var project := ProjectSettings.globalize_path("res://").rstrip("/").rstrip("\\")
	var root := project.get_base_dir()
	var candidate := root.path_join(LOG_NAME)
	if DirAccess.open(root) != null:
		return candidate
	return "user://%s" % LOG_NAME
