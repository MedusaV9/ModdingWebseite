extends TestCase
## W14/VOICE — Gooby wird gesprächiger: Mini-Dialoge (Antwort-Chips),
## 120 neue Text-Lines mit Anti-Wiederholungs-Gedächtnis, Gebrabbel-
## Melodien. Alles pur getestet (Zufall als roll, keine OS-Uhr):
##  - gespraeche.json ist schema-valide (12 Gespräche, je 2 Antworten,
##    jede Antwort hat Follow-up-Keys in DE UND EN, Anlässe existieren im
##    Soul-Pack, maximal 2 Ebenen tief)
##  - Baum-Navigation pur (fuer_anlass/antworten/folge_key/naechste_ebene)
##  - Anti-Wiederholung: die letzten 5 Lines je Kategorie kommen nicht dran
##  - Kategorie-Auswahl deterministisch über den injizierten Roll
##  - alle 120 Linien-Keys existieren DE/EN-paritätisch
##  - Melodie-Mapping (fragend ↗ / aufgeregt schnell / schläfrig tief+langsam)
##  - Wiedersehen-Staffel (5 Stufen, monoton mit der Lücke)

const GameStateScript := preload("res://scripts/state/game_state.gd")

const GESPRAECHE_PFAD := "res://content/soul/data/gespraeche.json"
const SOUL_PACK_PFAD := "res://content/soul/data/soul.json"

const ERWARTETE_GESPRAECHE := 12
const ERWARTETE_LINES := 120
const NOW_MS := 1768478400000

var _seq := 0


class RoomStub:
	extends Node3D
	## Minimaler RoomBase-Ersatz (Muster test_ef1_idle_streicheln): GameState,
	## Sprech-Protokoll und eine echte ui_layer für die Antwort-Chips.

	var grid: Variant = null
	var gs_ref: Object = null
	var lines: Array = []
	var layer := CanvasLayer.new()

	func _init() -> void:
		add_child(layer)

	func game_state() -> Object:
		return gs_ref

	func gooby() -> Node3D:
		return null

	func say(text: String) -> void:
		lines.append(text)

	func is_build_mode_active() -> bool:
		return false

	func ui_layer() -> CanvasLayer:
		return layer


func _gespraeche() -> Array:
	return GoobyGespraech.lade()


func _pack_moment_ids() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOUL_PACK_PFAD))
	var ids := {}
	if parsed is Dictionary:
		for item: Variant in (parsed as Dictionary).get("items", []):
			if item is Dictionary:
				ids[str((item as Dictionary).get("id", ""))] = true
	return ids


# ── gespraeche.json Schema ────────────────────────────────────────────────────


func test_gespraeche_schema_valide() -> void:
	var gespraeche := _gespraeche()
	assert_eq(gespraeche.size(), ERWARTETE_GESPRAECHE, "12 Gespräche")
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var moment_ids := _pack_moment_ids()
	var seen_ids := {}
	for gespraech: Dictionary in gespraeche:
		var gid := str(gespraech.get("id", ""))
		assert_false(gid.is_empty(), "Gespräch ohne id")
		assert_false(seen_ids.has(gid), "Gespräch-Id doppelt: %s" % gid)
		seen_ids[gid] = true
		var chance := float(gespraech.get("chance", -1.0))
		assert_true(chance > 0.0 and chance <= 1.0, "%s: chance in (0,1]" % gid)
		var anlaesse: Array = gespraech.get("anlass", [])
		assert_true(anlaesse.size() >= 1, "%s: mindestens ein Anlass" % gid)
		for anlass: Variant in anlaesse:
			assert_true(
				moment_ids.has(str(anlass)),
				"%s: Anlass '%s' existiert nicht im Soul-Pack" % [gid, anlass]
			)
		_check_ebene(gespraech, gid, 1, de, en)


## Rekursive Ebenen-Prüfung: 2 Antworten, jede mit Label + Follow-up(s) in
## BEIDEN Sprachen; "weiter" nur bis MAX_EBENEN (Ebene-2-Antworten sind Blätter).
func _check_ebene(
	ebene: Dictionary, gid: String, tiefe: int, de: Dictionary, en: Dictionary
) -> void:
	var antworten := GoobyGespraech.antworten(ebene)
	assert_eq(antworten.size(), 2, "%s Ebene %d: genau 2 Antwort-Chips" % [gid, tiefe])
	for antwort: Dictionary in antworten:
		var aid := "%s/%s" % [gid, str(antwort.get("id", ""))]
		var label := str(antwort.get("label_key", ""))
		assert_true(de.has(label), "%s: Label-Key fehlt in DE: %s" % [aid, label])
		assert_true(en.has(label), "%s: Label-Key fehlt in EN: %s" % [aid, label])
		var folgen: Array = antwort.get("folge_keys", [])
		assert_true(folgen.size() >= 1, "%s: jede Antwort hat ein Follow-up" % aid)
		for key: Variant in folgen:
			assert_true(de.has(str(key)), "%s: Follow-up fehlt in DE: %s" % [aid, key])
			assert_true(en.has(str(key)), "%s: Follow-up fehlt in EN: %s" % [aid, key])
		assert_true(
			["gooby", "witz"].has(str(antwort.get("stil", "gooby"))),
			"%s: stil ist gooby|witz (AcBubble-Vertrag)" % aid
		)
		var weiter := GoobyGespraech.naechste_ebene(antwort)
		if weiter.is_empty():
			continue
		assert_true(
			tiefe < GoobyGespraech.MAX_EBENEN,
			(
				"%s: weiter unterhalb Ebene %d verboten (max %d)"
				% [aid, tiefe, GoobyGespraech.MAX_EBENEN]
			)
		)
		_check_ebene(weiter, gid, tiefe + 1, de, en)


func test_mindestens_zwei_gespraeche_mit_ebene_zwei() -> void:
	var tiefe_zwei := 0
	for gespraech: Dictionary in _gespraeche():
		for antwort: Dictionary in GoobyGespraech.antworten(gespraech):
			if not GoobyGespraech.naechste_ebene(antwort).is_empty():
				tiefe_zwei += 1
	assert_true(tiefe_zwei >= 2, "mindestens 2 Antworten führen in Ebene 2 (%d)" % tiefe_zwei)


# ── Baum-Navigation pur ───────────────────────────────────────────────────────


func test_baum_navigation_pur() -> void:
	var gespraeche := _gespraeche()
	assert_true(GoobyGespraech.fuer_anlass(gespraeche, "gibt_es_nicht").is_empty())
	var gewitter := GoobyGespraech.fuer_anlass(gespraeche, "wetter_gewitter")
	assert_eq(str(gewitter.get("id", "")), "gewitter", "Anlass wetter_gewitter dockt an")
	var antworten := GoobyGespraech.antworten(gewitter)
	assert_eq(antworten.size(), 2, "Ebene 1 hat 2 Chips")
	var troesten: Dictionary = antworten[0]
	assert_eq(str(troesten.get("id", "")), "troesten")
	# folge_key deterministisch: roll unter 0.5 nimmt Variante 1, darüber 2.
	assert_eq(GoobyGespraech.folge_key(troesten, 0.0), "gespraech.gewitter.troesten.f1")
	assert_eq(GoobyGespraech.folge_key(troesten, 0.9), "gespraech.gewitter.troesten.f2")
	assert_eq(GoobyGespraech.folge_key(troesten, 0.0), GoobyGespraech.folge_key(troesten, 0.49))
	# Ebene 2: weiter-Knoten hat wieder 2 Antworten, die Blätter sind.
	var weiter := GoobyGespraech.naechste_ebene(troesten)
	assert_false(weiter.is_empty(), "troesten führt in Ebene 2")
	for blatt: Dictionary in GoobyGespraech.antworten(weiter):
		assert_true(
			GoobyGespraech.naechste_ebene(blatt).is_empty(),
			"Ebene-2-Antwort '%s' ist ein Blatt" % blatt.get("id", "")
		)
	# mutig hat KEINE zweite Ebene.
	assert_true(GoobyGespraech.naechste_ebene(antworten[1]).is_empty())


func test_merke_antwort_ist_pur_und_zaehlt() -> void:
	var antwort := {"id": "troesten", "erinnerung": "getroestet"}
	var vorher: Dictionary = {}
	var nachher := GoobyGespraech.merke_antwort(vorher, "gewitter", antwort, 1000)
	assert_true(vorher.is_empty(), "Eingabe-Map bleibt unangetastet (pur)")
	assert_eq(str(nachher["gewitter"]["antwort"]), "troesten")
	assert_eq(str(nachher["gewitter"]["erinnerung"]), "getroestet")
	assert_eq(int(nachher["gewitter"]["anzahl"]), 1)
	var dritte := GoobyGespraech.merke_antwort(
		GoobyGespraech.merke_antwort(nachher, "gewitter", antwort, 2000), "gewitter", antwort, 3000
	)
	assert_eq(int(dritte["gewitter"]["anzahl"]), 3, "Wiederholungen zählen hoch")
	assert_eq(int(dritte["gewitter"]["beiMs"]), 3000, "letzter Zeitpunkt gewinnt")


# ── Linien: Bestand, Determinismus, Anti-Wiederholung ─────────────────────────


func test_alle_120_lines_de_en_paritaetisch() -> void:
	assert_eq(SoulLinien.gesamt_anzahl(), ERWARTETE_LINES, "genau 120 neue Lines")
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for kategorie: String in SoulLinien.KATEGORIEN:
		var keys := SoulLinien.keys_of(kategorie)
		assert_true(keys.size() >= 1, "Kategorie leer: %s" % kategorie)
		for key in keys:
			assert_true(de.has(key), "DE fehlt: %s" % key)
			assert_true(en.has(key), "EN fehlt: %s" % key)


func test_fridge_schnittstelle_fuettern_keys() -> void:
	# Vereinbartes Key-Schema für W14/FRIDGE: fuettern.kommentar.<kategorie>.<n>
	for kategorie in ["obst", "gemuese", "suess", "deftig"]:
		var keys := SoulLinien.keys_of("fuettern." + kategorie)
		assert_eq(keys.size(), 4, "fuettern.%s hat 4 Sprüche" % kategorie)
		assert_eq(keys[0], "fuettern.kommentar.%s.1" % kategorie, "Key-Schema stabil")


func test_auswahl_deterministisch_ueber_roll() -> void:
	var leer: Dictionary = {}
	assert_eq(
		SoulLinien.waehle("selbstgespraech", leer, 0.2),
		SoulLinien.waehle("selbstgespraech", leer, 0.2),
		"gleicher Roll + gleiches Gedächtnis = gleiche Line"
	)
	assert_eq(SoulLinien.waehle("selbstgespraech", leer, 0.0), "soul.linie.selbstgespraech.1")
	assert_eq(SoulLinien.waehle("selbstgespraech", leer, 0.999), "soul.linie.selbstgespraech.15")
	assert_eq(SoulLinien.waehle("gibt_es_nicht", leer, 0.5), "", "unbekannte Kategorie = leer")


func test_anti_wiederholung_letzte_fuenf() -> void:
	# 15er-Pool: 10 Züge hintereinander mit Roll 0 — innerhalb jedes
	# 6er-Fensters darf sich kein Key wiederholen (letzte 5 gesperrt).
	var gedaechtnis: Dictionary = {}
	var gezogen: Array[String] = []
	for i in 10:
		var key := SoulLinien.waehle("selbstgespraech", gedaechtnis, 0.0)
		assert_false(key.is_empty(), "Zug %d liefert eine Line" % i)
		var start := maxi(0, gezogen.size() - SoulLinien.GEDAECHTNIS_MAX)
		for j in range(start, gezogen.size()):
			assert_ne(key, gezogen[j], "Zug %d wiederholt Line aus dem 5er-Fenster" % i)
		gezogen.append(key)
		gedaechtnis = SoulLinien.merke(gedaechtnis, "selbstgespraech", key)
	assert_true(
		(gedaechtnis["selbstgespraech"] as Array).size() <= SoulLinien.GEDAECHTNIS_MAX,
		"Gedächtnis bleibt bei maximal 5 Einträgen"
	)


func test_anti_wiederholung_kleiner_pool_wird_nie_stumm() -> void:
	# wetter.nebel hat nur 2 Keys — auch mit vollem Gedächtnis kommt immer
	# eine Line (die am längsten nicht gezeigte), nie "".
	var gedaechtnis: Dictionary = {}
	var erster := SoulLinien.waehle("wetter.nebel", gedaechtnis, 0.0)
	gedaechtnis = SoulLinien.merke(gedaechtnis, "wetter.nebel", erster)
	var zweiter := SoulLinien.waehle("wetter.nebel", gedaechtnis, 0.0)
	assert_ne(zweiter, erster, "zweite Line ist die andere Variante")
	gedaechtnis = SoulLinien.merke(gedaechtnis, "wetter.nebel", zweiter)
	var dritter := SoulLinien.waehle("wetter.nebel", gedaechtnis, 0.0)
	assert_eq(dritter, erster, "voller Kleiner-Pool: ältester Eintrag wird wieder frei")


func test_merke_ist_pur() -> void:
	var vorher: Dictionary = {"selbstgespraech": ["a"]}
	var nachher := SoulLinien.merke(vorher, "selbstgespraech", "b")
	assert_eq((vorher["selbstgespraech"] as Array).size(), 1, "Eingabe bleibt unangetastet")
	assert_eq(nachher["selbstgespraech"] as Array, ["a", "b"], "neuer Key hinten angefügt")


func test_plauder_kategorie() -> void:
	assert_eq(SoulLinien.plauder_kategorie("gewitter", 0.0), "wetter.gewitter")
	assert_eq(SoulLinien.plauder_kategorie("gewitter", 0.9), "selbstgespraech")
	assert_eq(
		SoulLinien.plauder_kategorie("wolken", 0.0), "selbstgespraech", "Wolken sind kein Anlass"
	)
	assert_eq(
		SoulLinien.plauder_kategorie("unbekannt", 0.0),
		"selbstgespraech",
		"unbekanntes Wetter fällt aufs Selbstgespräch zurück"
	)


func test_wiedersehen_staffel_monoton() -> void:
	var stunde := 3_600_000
	assert_eq(SoulLinien.wiedersehen_key(2 * stunde), "", "unter 6 h keine Staffel-Zeile")
	assert_eq(SoulLinien.wiedersehen_key(7 * stunde), "soul.linie.wiedersehen.1")
	assert_eq(SoulLinien.wiedersehen_key(30 * stunde), "soul.linie.wiedersehen.2")
	assert_eq(SoulLinien.wiedersehen_key(60 * stunde), "soul.linie.wiedersehen.3")
	assert_eq(SoulLinien.wiedersehen_key(200 * stunde), "soul.linie.wiedersehen.4")
	assert_eq(SoulLinien.wiedersehen_key(800 * stunde), "soul.linie.wiedersehen.5")


# ── Melodien ──────────────────────────────────────────────────────────────────


func test_melodie_mapping() -> void:
	assert_eq(GoobyVoice.melodie_fuer(60.0, "neutral", "Was ist das?"), "fragend")
	assert_eq(GoobyVoice.melodie_fuer(60.0, "ecstatic", "Juhu!"), "aufgeregt")
	assert_eq(
		GoobyVoice.melodie_fuer(90.0, "neutral", "Toll."), "aufgeregt", "beste Laune plappert"
	)
	assert_eq(GoobyVoice.melodie_fuer(60.0, "sleepy", "Gähn."), "schlaefrig")
	assert_eq(
		GoobyVoice.melodie_fuer(10.0, "neutral", "Och."), "schlaefrig", "elend = tief+langsam"
	)
	assert_eq(
		GoobyVoice.melodie_fuer(10.0, "ecstatic", "Oh."), "schlaefrig", "müde schlägt hibbelig"
	)
	assert_eq(
		GoobyVoice.melodie_fuer(60.0, "neutral", "Hallo."), "", "Normalfall bleibt wie vor W14"
	)


func test_melodie_params() -> void:
	var aufgeregt := GoobyVoice.melodie_params("aufgeregt")
	assert_true(float(aufgeregt["tempo"]) > 1.0, "aufgeregt brabbelt schneller")
	assert_true(float(aufgeregt["pitch"]) > 1.0, "aufgeregt brabbelt heller")
	var schlaefrig := GoobyVoice.melodie_params("schlaefrig")
	assert_true(float(schlaefrig["tempo"]) < 1.0, "schläfrig brabbelt langsamer")
	assert_true(float(schlaefrig["pitch"]) < 1.0, "schläfrig brabbelt tiefer")
	assert_eq(str(GoobyVoice.melodie_params("fragend")["bogen"]), "rauf")
	assert_eq(GoobyVoice.melodie_params(""), GoobyVoice.MELODIE_NEUTRAL, "leer = neutral")
	assert_eq(GoobyVoice.melodie_params("quatsch"), GoobyVoice.MELODIE_NEUTRAL)


func test_melodie_bogen() -> void:
	# "" reproduziert das bisherige Verhalten (letzte 3 Silben, '?' hebt).
	assert_almost(GoobyVoice.melodie_bogen("", 0, 10, false), 1.0)
	assert_almost(GoobyVoice.melodie_bogen("", 9, 10, false), 1.0 - 3 * 0.06)
	assert_almost(GoobyVoice.melodie_bogen("", 9, 10, true), 1.0 + 3 * 0.06)
	# fragend: erste Hälfte flach, danach stetig rauf bis +BOGEN_RAUF.
	assert_almost(GoobyVoice.melodie_bogen("rauf", 0, 11, false), 1.0)
	assert_almost(GoobyVoice.melodie_bogen("rauf", 10, 11, false), 1.0 + GoobyVoice.BOGEN_RAUF)
	assert_true(
		(
			GoobyVoice.melodie_bogen("rauf", 10, 11, false)
			> GoobyVoice.melodie_bogen("rauf", 7, 11, false)
		),
		"fragend steigt zum Ende hin"
	)
	# schläfrig: sinkt gleichmäßig über den ganzen Satz.
	assert_almost(GoobyVoice.melodie_bogen("tief", 0, 11, false), 1.0)
	assert_almost(GoobyVoice.melodie_bogen("tief", 10, 11, false), 1.0 - GoobyVoice.BOGEN_TIEF)
	# aufgeregt: fällt am Satzende IMMER (auch bei Fragen — Plapper-Modus).
	assert_almost(GoobyVoice.melodie_bogen("runter", 9, 10, true), 1.0 - 3 * 0.06)
	# Ein-Silben-Satz crasht nie.
	assert_almost(GoobyVoice.melodie_bogen("rauf", 0, 1, false), 1.0)


func test_sagt_mit_melodie_laeuft_und_endet() -> void:
	var voice := GoobyVoice.new()
	tree.root.add_child(voice)
	await wait_frames(1)
	var done := {"fertig": false}
	voice.fertig.connect(func() -> void: done["fertig"] = true)
	voice.sagt("Nochmal! Nochmal!", "ecstatic", "aufgeregt")
	assert_true(voice.ist_am_reden(), "sagt() mit Melodie startet Gebrabbel")
	var finished := await wait_until(func() -> bool: return done["fertig"], 8000)
	assert_true(finished, "fertig-Signal kam nicht (Melodie-Pfad)")
	voice.queue_free()


# ── Ende-zu-Ende: Chips → Antwort → Laune/Slice/Follow-up ─────────────────────


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w14_voice/gs_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_gespraech_chips_ende_zu_ende() -> void:
	var gs := _fresh_gs()
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	var seele: SeeleRunner = runner.get_node("SeeleRunner")
	var gespraech: GoobyGespraech = seele.get_node("GoobyGespraech")
	# Anlass mit chance 1.0 → deterministisch ohne rng-Seed.
	assert_true(gespraech.starte("gruss_eingeschnappt"), "Gespräch dockt am Gruß an")
	assert_true(gespraech.aktiv(), "Chips stehen")
	await wait_frames(1)
	var panel: Control = room.layer.get_node("GoobyGespraechChips")
	var row: HBoxContainer = panel.get_child(0)
	assert_eq(row.get_child_count(), 2, "zwei Antwort-Chips")
	var chip: Button = row.get_child(0)
	assert_eq(chip.text, I18nService.t("gespraech.eingeschnappt.entschuldigen.label"), "Chip-Label")
	var wert0 := seele.wert()
	var lines0 := room.lines.size()
	chip.pressed.emit()
	await wait_frames(2)
	assert_true(seele.wert() > wert0, "Antwort stupst die Laune (+3 entschuldigen)")
	assert_true(room.lines.size() > lines0, "Follow-up-Line wird gesprochen")
	var eintrag: Dictionary = SoulState.slice_of(gs)["gespraeche"].get("eingeschnappt", {})
	assert_eq(str(eintrag.get("antwort", "")), "entschuldigen", "Antwort landet im Soul-Slice")
	assert_eq(int(eintrag.get("anzahl", 0)), 1, "Zähler startet bei 1")
	assert_false(gespraech.aktiv(), "eingeschnappt hat keine Ebene 2 — Gespräch zu Ende")
	room.queue_free()
	gs.queue_free()
	await wait_frames(1)


func test_kommentar_api_spricht_und_merkt_sich_lines() -> void:
	var gs := _fresh_gs()
	var room := RoomStub.new()
	room.gs_ref = gs
	tree.root.add_child(room)
	var runner := GoobyReactions.new()
	runner.name = "GoobyReactions"
	runner.now_ms_override = NOW_MS
	runner.visuals_enabled = false
	room.add_child(runner)
	runner.setup(room)
	var seele: SeeleRunner = runner.get_node("SeeleRunner")
	# 91 s nach dem Betreten-Moment ist die Seelen-Bremse wieder frei.
	runner.now_ms_override = NOW_MS + 91_000
	var lines0 := room.lines.size()
	var key := seele.kommentar("w13.ball")
	assert_true(key.begins_with("soul.linie.w13.ball."), "Ball-Kommentar kommt (%s)" % key)
	assert_true(room.lines.size() > lines0, "Line wird gesprochen")
	var gedaechtnis: Dictionary = SoulState.slice_of(gs)["linien"]
	assert_eq(gedaechtnis.get("w13.ball", []) as Array, [key], "Anti-Wiederholung gebucht")
	# Direkt danach hält die 90-s-Bremse (kein Zutexten).
	assert_eq(seele.kommentar("w13.ball"), "", "ambient-Bremse hält")
	room.queue_free()
	gs.queue_free()
	await wait_frames(1)


# ── Slice: neue Felder überleben normalize ────────────────────────────────────


func test_soul_slice_gespraeche_und_linien_normalisieren() -> void:
	var defaults := SoulState.default_slice()
	assert_true(defaults.has("gespraeche"), "Slice-Default gespraeche")
	assert_true(defaults.has("linien"), "Slice-Default linien")
	var roh := defaults.duplicate(true)
	roh["gespraeche"] = {"gewitter": {"antwort": "troesten", "anzahl": 2}}
	roh["linien"] = {"selbstgespraech": ["soul.linie.selbstgespraech.3"]}
	var normalisiert := SoulState.normalize_slice(roh)
	assert_eq(
		str(normalisiert["gespraeche"]["gewitter"]["antwort"]),
		"troesten",
		"gespraeche überlebt normalize"
	)
	assert_eq(
		(normalisiert["linien"]["selbstgespraech"] as Array).size(),
		1,
		"linien-Gedächtnis überlebt normalize"
	)
	assert_eq(
		SoulState.normalize_slice({"linien": "kaputt"})["linien"],
		{},
		"kaputte Typen fallen auf Default"
	)
