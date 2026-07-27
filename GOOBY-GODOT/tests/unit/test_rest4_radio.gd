extends TestCase
## REST-4 — Radio-Oberfläche (EVAL Rang 10): pure RadioLogic (Sender-/Titel-
## Sperren nach Level, Freischalt-Zähler, Likes-Normalisierung) und die
## RadioSheet-UI headless (An/Aus persistiert, Senderwahl, Like des
## laufenden Titels, Schlösser an gesperrten Sendern).

const SaveSchema := preload("res://scripts/state/save_schema.gd")


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## MusicDirector-Double: nur die vom Sheet benutzte Radio-API.
class FakeMusic:
	extends Node
	signal track_changed(track_id: String)
	var playing := false
	var station := ""
	var track := ""
	var next_calls := 0

	func radio_play(id: String) -> void:
		playing = true
		station = id
		var ids := MusicRegistry.station_track_ids(id)
		track = str(ids[0]) if not ids.is_empty() else ""
		track_changed.emit(track)

	func radio_stop() -> void:
		playing = false
		track = ""

	func radio_next() -> void:
		next_calls += 1
		var ids := MusicRegistry.station_track_ids(station)
		if ids.size() > 1:
			track = str(ids[1])
		track_changed.emit(track)

	func is_radio_playing() -> bool:
		return playing

	func current_track_id() -> String:
		return track


## ------------------------------------------------------ RadioLogic (pur)


func test_sender_sperren_nach_level() -> void:
	var level1 := RadioLogic.sender(1)
	assert_true(level1.size() >= 3, "Registry liefert mehrere Sender")
	for station: Dictionary in level1:
		var erwartet: bool = int(station.get("unlock_level", 1)) > 1
		assert_eq(bool(station["locked"]), erwartet, "Level-1-Sperre falsch: %s" % station["id"])
	for station: Dictionary in RadioLogic.sender(99):
		assert_false(bool(station["locked"]), "Level 99 schaltet alles frei")


func test_titel_sperren_und_zaehler() -> void:
	for station: Dictionary in RadioLogic.sender(1):
		var id := str(station["id"])
		var rows := RadioLogic.titel(id, 1, {})
		var zaehler := RadioLogic.frei_zaehler(id, 1)
		assert_eq(rows.size(), int(zaehler["gesamt"]), "Liste zeigt ALLE Titel: %s" % id)
		var frei := 0
		for row: Dictionary in rows:
			assert_eq(
				bool(row["locked"]),
				int(row["unlock_level"]) > 1,
				"Titel-Sperre falsch: %s" % row["id"]
			)
			if not bool(row["locked"]):
				frei += 1
		assert_eq(frei, int(zaehler["frei"]), "Zähler zählt die offenen Titel: %s" % id)
		var voll := RadioLogic.frei_zaehler(id, 99)
		assert_eq(int(voll["frei"]), int(voll["gesamt"]), "Level 99: alles frei (%s)" % id)


func test_likes_toggle_und_normalisierung() -> void:
	var state := {}
	var track_id := str(MusicRegistry.station_track_ids("gooby-fm")[0])
	assert_true(RadioLogic.toggle_like(state, track_id), "erster Toggle merkt")
	assert_eq(RadioLogic.like_anzahl(state), 1)
	assert_false(RadioLogic.toggle_like(state, track_id), "zweiter Toggle vergisst")
	assert_eq(RadioLogic.like_anzahl(state), 0)
	assert_false(RadioLogic.toggle_like(state, "kein-echter-track"), "unbekannte Id: kein Like")
	var junk := {"radio": {"likes": {"quatsch-id": true, track_id: "ja", 7: true}}}
	assert_eq(RadioLogic.likes_von(junk).size(), 0, "Junk-Likes fallen komplett raus")


## ------------------------------------------------------ RadioSheet (UI)


func test_radio_sheet_an_aus_und_like() -> void:
	var gs := FakeGameState.new()
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	var an_aus: Button = sheet.find_child("AnAus", true, false)
	assert_true(an_aus != null, "An/Aus-Knopf existiert")
	an_aus.pressed.emit()
	assert_true(music.playing, "Radio läuft nach dem Einschalten")
	assert_true(bool(gs.get_value("radio.playing", false)), "playing persistiert")
	assert_false(str(music.track).is_empty(), "ein Titel läuft")
	var like: Button = sheet.find_child("Like", true, false)
	like.pressed.emit()
	assert_true(
		bool(gs.get_value("radio.likes.%s" % music.track, false)),
		"Like des laufenden Titels landet im Save"
	)
	assert_true(gs.slices_notified.has("radio"), "Slice-Notify fürs Radio")
	an_aus.pressed.emit()
	assert_false(music.playing, "Ausschalten stoppt die Wiedergabe")
	assert_false(bool(gs.get_value("radio.playing", true)), "playing=false persistiert")
	sheet.queue_free()
	music.queue_free()
	await wait_frames(1)


func test_radio_sheet_senderwahl_und_schloesser() -> void:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", 1)
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	var gesperrt: Button = sheet.find_child("Sender_game-fm", true, false)
	assert_true(gesperrt != null and gesperrt.disabled, "Level-8-Sender ist gesperrt")
	var offen: Button = sheet.find_child("Sender_gooby-fm", true, false)
	assert_true(offen != null and not offen.disabled, "Level-1-Sender ist offen")
	offen.pressed.emit()
	await wait_frames(1)
	assert_eq(str(gs.get_value("radio.station", "")), "gooby-fm", "Senderwahl persistiert")
	sheet.queue_free()
	music.queue_free()
	await wait_frames(1)
