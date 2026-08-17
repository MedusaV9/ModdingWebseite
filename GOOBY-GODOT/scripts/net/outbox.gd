class_name NetOutbox
extends RefCounted
## Persistente Offline-Queue (Doc C §5, offline-first): Analytics-Batches /
## Redeems überleben App-Neustarts in user://outbox.json (atomar via .tmp +
## rename). Flüchtiges (Presence, POS, SYNC) gehört NIE hier hinein
## (W2c-Protokoll §7). flush() übergibt jeden Eintrag an einen Sender-
## Callable — Fehlschläge bleiben liegen und werden später erneut versucht.

## Kappe gegen unbegrenztes Wachstum (älteste Einträge fliegen zuerst).
const MAX_ENTRIES := 500

var path := "user://outbox.json"

var _entries: Array[Dictionary] = []


func _init(file_path := "user://outbox.json") -> void:
	path = file_path
	_load()


## Neuen Eintrag anhängen (persistiert sofort). Liefert die Eintrags-Id.
func enqueue(kind: String, payload: Dictionary) -> String:
	var id := NetClient.uuid4()
	_entries.append(
		{"id": id, "kind": kind, "at": Time.get_unix_time_from_system(), "payload": payload}
	)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_save()
	return id


## Eintrag mit fester Id ersetzen/anlegen (z. B. laufende Analytics-Session —
## Heartbeats aktualisieren denselben Eintrag, Server dedupet über die Id).
func upsert(kind: String, id: String, payload: Dictionary) -> void:
	for entry in _entries:
		if entry["id"] == id:
			entry["kind"] = kind
			entry["payload"] = payload
			entry["at"] = Time.get_unix_time_from_system()
			_save()
			return
	_entries.append(
		{"id": id, "kind": kind, "at": Time.get_unix_time_from_system(), "payload": payload}
	)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	_save()


func entries(kind := "") -> Array[Dictionary]:
	if kind.is_empty():
		return _entries.duplicate()
	var out: Array[Dictionary] = []
	for entry in _entries:
		if entry["kind"] == kind:
			out.append(entry)
	return out


func size() -> int:
	return _entries.size()


func remove(id: String) -> void:
	for i in _entries.size():
		if _entries[i]["id"] == id:
			_entries.remove_at(i)
			_save()
			return


func clear() -> void:
	_entries.clear()
	_save()


## Alle Einträge an sender übergeben: sender.call(entry) -> bool (true =
## erfolgreich versendet → Eintrag fliegt). Liefert die Anzahl der Erfolge.
func flush(sender: Callable) -> int:
	if _entries.is_empty():
		return 0
	var kept: Array[Dictionary] = []
	var flushed := 0
	for entry in _entries:
		var ok: bool = sender.call(entry) == true
		if ok:
			flushed += 1
		else:
			kept.append(entry)
	_entries = kept
	_save()
	return flushed


func _load() -> void:
	_entries = []
	if not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	var parser := JSON.new()
	if parser.parse(raw) != OK or not (parser.data is Dictionary):
		push_warning("[outbox] %s kaputt — starte leer" % path)
		return
	var list: Variant = (parser.data as Dictionary).get("entries")
	if not (list is Array):
		return
	for entry in list:
		if entry is Dictionary and entry.has("id") and entry.has("kind"):
			_entries.append(entry)


func _save() -> void:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("[outbox] kann %s nicht schreiben" % tmp)
		return
	file.store_string(JSON.stringify({"v": 1, "entries": _entries}))
	file.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null:
		dir.rename(tmp, path)
