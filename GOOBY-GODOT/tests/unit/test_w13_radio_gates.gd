extends TestCase
## W13/RADIO — Radio 2.0-Regeln (H §6.1): hartes IKEA-Kauf-Gate
## (Besitz-Matrix aus Save-Wert/Möbel, Aktions-Matrix owned × Aktion),
## Bordmusik-Modus (genau EIN Loop-Track, kein Skip), Grandfathering
## (Migrations-Wert bleibt respektiert), „Was läuft?"-Chip (Signal feuert
## bei Trackwechsel, injizierte Zeit blendet aus) und Ticker-Offset pur.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")
const DirectorScript := preload("res://scripts/audio/music_director.gd")


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


## MusicDirector-Double: Radio- UND Bordmusik-API mit Zähler pro Pfad.
class FakeMusic:
	extends Node
	signal track_changed(track_id: String)
	var playing := false
	var station := ""
	var track := ""
	var next_calls := 0
	var radio_play_calls := 0
	var bordmusik_calls := 0

	func radio_play(id: String) -> void:
		radio_play_calls += 1
		playing = true
		station = id
		var ids := MusicRegistry.station_track_ids(id)
		track = str(ids[0]) if not ids.is_empty() else ""
		track_changed.emit(track)

	func bordmusik_play() -> void:
		bordmusik_calls += 1
		playing = true
		station = MusicDirector.BORDMUSIK_STATION
		track = MusicDirector.BORDMUSIK_TRACK
		track_changed.emit(track)

	func radio_stop() -> void:
		playing = false
		station = ""
		track = ""

	func radio_next() -> void:
		next_calls += 1
		track_changed.emit(track)

	func is_radio_playing() -> bool:
		return playing

	func current_track_id() -> String:
		return track

	func radio_station() -> String:
		return station


## ------------------------------------------------------ Gate-Matrix (pur)


func test_besitz_matrix() -> void:
	assert_false(RadioLogic.besitzt_radio({}), "leerer State: kein Radio")
	assert_true(RadioLogic.besitzt_radio({"radio": {"owned": true}}), "Save-Wert zählt")
	assert_false(RadioLogic.besitzt_radio({"radio": {"owned": false}}), "false bleibt false")
	assert_false(
		RadioLogic.besitzt_radio({"radio": {"owned": "ja"}}), "Junk-Wert schaltet nicht frei"
	)
	var im_lager := {
		"radio": {"owned": false},
		"home": {"storage": [{"item": "radio", "variant": "default", "count": 1}]},
	}
	assert_true(RadioLogic.besitzt_radio(im_lager), "IKEA-Kauf im Lager zählt")
	var platziert := {
		"radio": {"owned": false},
		"home": {"rooms": {"living": {"items": [{"item": "radioRetro", "uid": "i-1"}]}}},
	}
	assert_true(RadioLogic.besitzt_radio(platziert), "platziertes Retro-Radio zählt")
	var nur_speaker := {
		"radio": {"owned": false},
		"home":
		{
			"storage": [{"item": "speaker", "count": 1}],
			"rooms": {"living": {"items": [{"item": "speaker", "uid": "i-2"}]}},
		},
	}
	assert_false(RadioLogic.besitzt_radio(nur_speaker), "Lautsprecher ist KEIN Radio")
	var ausverkauft := {"home": {"storage": [{"item": "radio", "count": 0}]}}
	assert_false(RadioLogic.besitzt_radio(ausverkauft), "count 0 = nicht im Besitz")


func test_aktions_matrix() -> void:
	for aktion: String in ["play", "pause"]:
		assert_true(RadioLogic.aktion_erlaubt(false, aktion), "Bordmusik erlaubt %s" % aktion)
		assert_true(RadioLogic.aktion_erlaubt(true, aktion), "Vollradio erlaubt %s" % aktion)
	for aktion: String in ["skip", "sender", "like"]:
		assert_false(RadioLogic.aktion_erlaubt(false, aktion), "ohne Radio verboten: %s" % aktion)
		assert_true(RadioLogic.aktion_erlaubt(true, aktion), "mit Radio erlaubt: %s" % aktion)
	assert_false(RadioLogic.aktion_erlaubt(true, "zaubern"), "Unbekanntes bleibt verboten")


func test_grandfathering_migration() -> void:
	# Web-v4-Saves hatten das Radio geschenkt — die Migration setzt
	# radio.owned und das Gate respektiert den Wert dauerhaft.
	var res: Dictionary = MigrationV4.migrate_any({"v": 4}, 1700000000000)
	assert_true(bool(res["ok"]), "v4-Minimal-Save migriert")
	var state: Dictionary = res["state"]
	assert_true(bool(state["radio"]["owned"]), "Grandfathering: owned=true aus Migration")
	assert_true(RadioLogic.besitzt_radio(state), "Gate respektiert den Migrations-Wert")
	var nur_save_wert := {"radio": {"owned": true}, "home": {"storage": [], "rooms": {}}}
	assert_true(
		RadioLogic.besitzt_radio(nur_save_wert), "Save-Wert reicht auch ohne Möbel (verkauft)"
	)


func test_cover_fuer_alle_sender() -> void:
	for station: Dictionary in MusicRegistry.stations():
		var cover := RadioLogic.cover(str(station.get("id", "")))
		assert_false(str(cover["glyph"]).is_empty(), "Glyph fehlt: %s" % station.get("id"))
		assert_true(cover["farbe"] is Color, "Cover-Farbe fehlt: %s" % station.get("id"))
	assert_eq(str(RadioLogic.cover("piraten-fm")["glyph"]), "♪", "Fallback-Cover greift")


## ------------------------------------------------------ Bordmusik (Motor)


func test_bordmusik_track_definition() -> void:
	var entry := MusicRegistry.entry(MusicDirector.BORDMUSIK_TRACK)
	assert_false(entry.is_empty(), "Bordmusik-Track steht in der Registry")
	assert_eq(str(entry.get("category", "")), "Bordmusik", "Kategorie passt")
	assert_eq(int(entry.get("unlock_level", 99)), 1, "ab Level 1 hörbar")
	assert_false(MusicRegistry.is_stinger(MusicDirector.BORDMUSIK_TRACK), "kein Stinger")
	assert_true(
		FileAccess.file_exists(MusicRegistry.path(MusicDirector.BORDMUSIK_TRACK)),
		"Track-Datei existiert"
	)


func test_bordmusik_genau_ein_track_kein_skip() -> void:
	var director: MusicDirector = DirectorScript.new()
	tree.root.add_child(director)
	director.bordmusik_play()
	assert_true(director.is_radio_playing(), "Bordmusik zählt als laufende Wiedergabe")
	assert_true(director.is_bordmusik_mode(), "Bordmusik-Modus aktiv")
	assert_eq(director.current_track_id(), MusicDirector.BORDMUSIK_TRACK, "DER eine Loop läuft")
	director.radio_next()
	assert_eq(
		director.current_track_id(),
		MusicDirector.BORDMUSIK_TRACK,
		"kein Skip: die Bordmusik-Queue hat genau 1 Track"
	)
	director.set_context("home")
	assert_eq(
		director.current_track_id(),
		MusicDirector.BORDMUSIK_TRACK,
		"Bordmusik ersetzt die Kontextmusik (wie das Radio)"
	)
	director.radio_stop()
	assert_false(director.is_radio_playing(), "Stop blendet zurück")
	assert_false(director.is_bordmusik_mode(), "Modus endet mit Stop")
	director.queue_free()
	await wait_frames(1)


## ------------------------------------------------------ RadioSheet (Gate)


func test_ohne_besitz_bordmusik_und_gates() -> void:
	var gs := FakeGameState.new()  # v5-Neusave: radio.owned=false
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	assert_true(sheet.find_child("KaufHinweis", true, false) != null, "IKEA-Kauf-Hinweis da")
	assert_true(sheet.find_child("SenderChips", true, false) == null, "keine Senderwahl")
	assert_true(sheet.find_child("TitelListe", true, false) == null, "keine Titelliste")
	var next: Button = sheet.find_child("Naechster", true, false)
	assert_true(next != null and next.disabled, "Skip ist gesperrt")
	assert_false(str(next.tooltip_text).is_empty(), "Skip erklärt sich per Tooltip")
	var an_aus: Button = sheet.find_child("AnAus", true, false)
	an_aus.pressed.emit()
	assert_eq(music.bordmusik_calls, 1, "Einschalten startet die Bordmusik")
	assert_eq(music.radio_play_calls, 0, "kein Vollradio ohne Besitz")
	assert_true(bool(gs.get_value("radio.playing", false)), "playing persistiert")
	assert_false(
		bool(gs.get_value("radio.owned", true)), "KAUF-GATE HART: Einschalten setzt owned NICHT"
	)
	next.pressed.emit()
	assert_eq(music.next_calls, 0, "Skip-Guard hält auch gegen synthetische Klicks")
	var like: Button = sheet.find_child("Like", true, false)
	assert_true(like != null and like.disabled, "Like ist gesperrt")
	like.pressed.emit()
	assert_eq(RadioLogic.like_anzahl(gs.state()), 0, "Like ohne Radio wird verworfen")
	var chip: NowPlayingChip = sheet.find_child("WasLaeuft", true, false)
	var titel := str(MusicRegistry.entry(MusicDirector.BORDMUSIK_TRACK).get("title", ""))
	assert_true(
		chip != null and chip.ticker_text().contains(titel), "Ticker zeigt den Bordmusik-Loop"
	)
	an_aus.pressed.emit()
	assert_false(music.playing, "Pause geht immer (Bordmusik-Matrix)")
	sheet.queue_free()
	music.queue_free()
	await wait_frames(1)


func test_mit_besitz_vollradio() -> void:
	var gs := FakeGameState.new()
	gs.set_value("radio.owned", true)
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	assert_true(sheet.find_child("SenderChips", true, false) != null, "Senderwahl offen")
	assert_true(sheet.find_child("KaufHinweis", true, false) == null, "kein Kauf-Hinweis mehr")
	assert_true(sheet.find_child("TitelListe", true, false) != null, "Titelliste da")
	var an_aus: Button = sheet.find_child("AnAus", true, false)
	an_aus.pressed.emit()
	assert_eq(music.radio_play_calls, 1, "Vollradio spielt den Sender")
	assert_eq(music.bordmusik_calls, 0, "keine Bordmusik-Schleife mit Besitz")
	var next: Button = sheet.find_child("Naechster", true, false)
	assert_true(next != null and not next.disabled, "Skip ist offen")
	next.pressed.emit()
	assert_eq(music.next_calls, 1, "Skip wirkt (Regression Vollradio)")
	sheet.queue_free()
	music.queue_free()
	await wait_frames(1)


func test_moebelkauf_schaltet_frei_und_heilt_save() -> void:
	var gs := FakeGameState.new()
	# IKEA-Kauf: Radio liegt im Lager, der Save-Wert ist noch false.
	gs.set_value("home.storage", [{"item": "radio", "variant": "default", "count": 1}])
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var sheet := RadioSheet.new()
	sheet.gs = gs
	sheet.music = music
	tree.root.add_child(sheet)
	await wait_frames(2)
	assert_true(bool(gs.get_value("radio.owned", false)), "Self-Heal: Kauf wird im Save verewigt")
	assert_true(sheet.find_child("SenderChips", true, false) != null, "Vollradio offen")
	sheet.queue_free()
	music.queue_free()
	await wait_frames(1)


## ------------------------------------------------------ „Was läuft?"-Chip


func test_chip_zeigt_trackwechsel_und_blendet_aus() -> void:
	var music := FakeMusic.new()
	tree.root.add_child(music)
	var chip := NowPlayingChip.install_floating(tree.root, music)
	assert_true(NowPlayingChip.install_floating(tree.root, music) == chip, "install ist idempotent")
	var zeit := {"ms": 100000}
	chip.now_ms = func() -> int: return int(zeit["ms"])
	await wait_frames(1)
	assert_false(chip.visible, "Chip startet unsichtbar")
	var gezeigt: Array = []
	chip.chip_gezeigt.connect(func(text: String) -> void: gezeigt.append(text))
	music.bordmusik_play()
	assert_true(chip.visible, "Chip blendet bei Trackstart ein")
	assert_eq(gezeigt.size(), 1, "Ticker-Signal feuert bei Trackwechsel")
	var titel := str(MusicRegistry.entry(MusicDirector.BORDMUSIK_TRACK).get("title", ""))
	assert_true(String(gezeigt[0]).contains(titel), "Chip nennt den Songtitel")
	zeit["ms"] += NowPlayingChip.ANZEIGE_MS + 1000
	await wait_frames(2)
	assert_false(chip.visible, "Chip blendet nach kurzer Zeit wieder aus")
	music.playing = false
	music.track_changed.emit("room-blubberbad")
	await wait_frames(1)
	assert_false(chip.visible, "Kontextmusik (kein Radio) weckt den Chip nicht")
	chip.queue_free()
	music.queue_free()
	await wait_frames(1)


func test_ticker_offset_pur() -> void:
	assert_eq(NowPlayingChip.ticker_offset(3.0, 100.0, 200.0), 0.0, "kurzer Text steht still")
	var a := NowPlayingChip.ticker_offset(1.0, 400.0, 200.0)
	var b := NowPlayingChip.ticker_offset(2.0, 400.0, 200.0)
	assert_true(a < 0.0, "läuft nach links")
	assert_true(b < a, "läuft weiter nach links")
	var periode := (400.0 + NowPlayingChip.TICKER_LUECKE_PX) / NowPlayingChip.SCROLL_PX_PRO_S
	assert_almost(
		NowPlayingChip.ticker_offset(periode, 400.0, 200.0), 0.0, 0.001, "wickelt sauber um"
	)
