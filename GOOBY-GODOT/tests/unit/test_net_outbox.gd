extends TestCase
## NetOutbox: Persistenz über Neustarts (zweite Instanz auf derselben Datei),
## upsert-Semantik (Analytics-Heartbeat), flush-Vertrag (Erfolg fliegt,
## Fehlschlag bleibt), Kappe und kaputte Dateien.


func test_enqueue_persistiert_und_ueberlebt_neustart() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	var id := box.enqueue("analytics_session", {"minutes": 3.5})
	box.enqueue("redeem", {"code": "SOMMER26"})
	assert_eq(box.size(), 2)

	# „App-Neustart“: frische Instanz auf derselben Datei.
	var reborn := NetOutbox.new(path)
	assert_eq(reborn.size(), 2, "Einträge müssen den Neustart überleben")
	var entry: Dictionary = reborn.entries()[0]
	assert_eq(entry["id"], id)
	assert_eq(entry["kind"], "analytics_session")
	assert_eq((entry["payload"] as Dictionary).get("minutes"), 3.5)
	_cleanup(path)


func test_upsert_ersetzt_gleiche_id_statt_zu_wachsen() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	box.upsert("analytics_session", "sess-1", {"minutes": 1.0})
	box.upsert("analytics_session", "sess-1", {"minutes": 2.0})
	box.upsert("analytics_session", "sess-1", {"minutes": 3.0})
	assert_eq(box.size(), 1, "Heartbeats aktualisieren denselben Eintrag")
	var payload: Dictionary = box.entries()[0]["payload"]
	assert_eq(payload.get("minutes"), 3.0)
	_cleanup(path)


func test_entries_filtert_nach_kind() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	box.enqueue("analytics_session", {})
	box.enqueue("redeem", {})
	box.enqueue("analytics_session", {})
	assert_eq(box.entries("analytics_session").size(), 2)
	assert_eq(box.entries("redeem").size(), 1)
	assert_eq(box.entries().size(), 3)
	_cleanup(path)


func test_flush_erfolg_entfernt_fehlschlag_bleibt() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	box.enqueue("a", {"n": 1})
	var keep_id := box.enqueue("b", {"n": 2})
	box.enqueue("a", {"n": 3})

	# Sender: nur kind=="a" gelingt.
	var flushed := box.flush(func(entry: Dictionary) -> bool: return entry["kind"] == "a")
	assert_eq(flushed, 2)
	assert_eq(box.size(), 1)
	assert_eq(box.entries()[0]["id"], keep_id, "Fehlschläge bleiben für später liegen")

	# Persistenz nach flush: Neustart sieht denselben Rest.
	var reborn := NetOutbox.new(path)
	assert_eq(reborn.size(), 1)
	_cleanup(path)


func test_remove_und_clear() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	var id := box.enqueue("a", {})
	box.enqueue("b", {})
	box.remove(id)
	assert_eq(box.size(), 1)
	box.clear()
	assert_eq(box.size(), 0)
	assert_eq(NetOutbox.new(path).size(), 0, "clear() persistiert")
	_cleanup(path)


func test_kappe_wirft_aelteste_eintraege() -> void:
	var path := _temp_path()
	var box := NetOutbox.new(path)
	for i in NetOutbox.MAX_ENTRIES + 5:
		box.upsert("a", "id-%d" % i, {"n": i})
	assert_eq(box.size(), NetOutbox.MAX_ENTRIES)
	assert_eq(box.entries()[0]["id"], "id-5", "die ältesten 5 sind geflogen")
	_cleanup(path)


func test_kaputte_datei_startet_leer() -> void:
	var path := _temp_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{kaputt!!")
	file.close()
	var box := NetOutbox.new(path)
	assert_eq(box.size(), 0, "kaputtes JSON darf nicht crashen")
	box.enqueue("a", {})
	assert_eq(NetOutbox.new(path).size(), 1, "danach normal benutzbar")
	_cleanup(path)


func _temp_path() -> String:
	return "user://test_outbox_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000]


func _cleanup(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
