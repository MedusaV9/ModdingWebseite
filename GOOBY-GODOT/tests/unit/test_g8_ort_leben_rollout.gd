extends TestCase
## G8-P1 „Jeder Ort lebt“ (Ideen-Doc Welle I, Fix für PT2-B4) — Wachen für
## den OrtLeben-Rollout auf ALLE Stadt-Orte plus die neuen generischen
## Bausteine (Sitzer, Trage-Requisiten, Orts-Momente):
## - Gesamt-Wache: kein betretbarer Stadt-Ort ohne `_leben_konfig()`
##   (Whitelist NUR funkelpark — eigenes Park-Besucher-System, kein
##   OrtScene; die Raumstation hängt bewusst nicht an der city_map und
##   hat ihre eigene Schwebe-Ambience).
## - Konfig-Wache je Ort: ≥2 Besucher-Slots, gültige Spruch-Domains
##   (DE+EN paritätisch), Momente mit bekannten Sounds und EINMAL-Clips
##   (Loop-Clips würden auf Sitzern kleben bleiben), Kappen respektiert.
## - System-Wachen: Sitzer-Pläne deterministisch, Sitzer überleben
##   Reduced Motion, Momente feuern im Takt, Kassen-Piep beim Kauf.

const GoobythekeSzene := preload("res://scenes/city/orte/goobytheke.tscn")

const SEED := 4711

## Orte, die absichtlich OHNE OrtLeben-Konfig bleiben (begründet!):
## funkelpark ist kein OrtScene (extends Node3D) und bringt sein eigenes
## Plaza-Besucher-System mit (Funkelpark._baue_besucher + Fahrgeschäfte).
const LEBEN_WHITELIST: Array[String] = ["funkelpark"]

## Orte mit G8-P1-Momenten (je 2–3, s. Ideen-Doc „ortstypische Würze“).
## rehwei/baumarkt sind G7-P55-Bestand und leben über Kunden + Kasse.
const MOMENTE_ORTE: Array[String] = [
	"goobytheke",
	"post",
	"flughafen",
	"goobyman",
	"pow",
	"autohaus",
	"tierarzt",
	"gouhbus",
	"wochenmarkt",
]

## Erlaubte Moment-Clips: NUR Einmal-Clips aus gooby.glb — ein Loop-Clip
## (z. B. dance-loop) würde in _spiele_clip als „moment“ nie enden und
## Sitzer dauerhaft aus ihrem sit-Loop reißen.
const EINMAL_CLIPS: Array[String] = [
	"hop",
	"wave",
	"celebrate",
	"refuse",
	"tomato_throw",
	"phone_tap",
	"idle_lookaround",
]


## GameState-Double (Muster test_g7_ort_leben): dotted get + update-Pfad.
class FakeGameState:
	extends RefCounted

	signal slice_changed(slice_id: String, data: Variant)

	var daten: Dictionary = {}

	func _init(start: Dictionary = {}) -> void:
		daten = start

	func state() -> Dictionary:
		return daten

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slice_changed.emit(slice_id, daten.get(slice_id))


func _basis_state() -> Dictionary:
	return {
		"economy": {"coins": 500},
		"inventory": {"items": {}, "food": {}},
		"city": {},
	}


## Ort sauber abbauen (Muster test_g7_ort_leben::_ort_abbauen).
func _ort_abbauen(ort: OrtScene) -> void:
	if ort.voice != null and is_instance_valid(ort.voice):
		ort.voice.sagt("")
	await wait_frames(6)
	ort.queue_free()
	await wait_frames(2)


## Konfig eines Orts OHNE Mount holen: Szene instanzieren (kein _ready,
## solange sie nicht in den Baum kommt), `_leben_konfig()` fragen, freigeben.
func _konfig_von(ort_id: String) -> Dictionary:
	var pfad := "res://scenes/city/orte/%s.tscn" % ort_id
	var szene: PackedScene = load(pfad)
	assert_ne(szene, null, "Ort-Szene lädt: %s" % pfad)
	if szene == null:
		return {}
	var ort: Node = szene.instantiate()
	var konfig: Dictionary = ort._leben_konfig()
	ort.free()
	return konfig


## ------------------------------------------------------ Gesamt-Wache B4


func test_kein_stadt_ort_ohne_leben_konfig() -> void:
	var ids := OrtKatalog.betretbare_ids()
	assert_true(ids.size() >= 12, "Karte kennt alle betretbaren Orte")
	for weiss in LEBEN_WHITELIST:
		assert_true(ids.has(weiss), "Whitelist-Eintrag existiert: %s" % weiss)
	# Die Raumstation hängt BEWUSST nicht an der city_map (GOOB-1-Shuttle
	# im Flughafen) und behält ihre eigene Schwebe-Ambience.
	assert_false(ids.has("raumstation"), "Raumstation bleibt außerhalb der city_map")
	for ort_id in ids:
		if LEBEN_WHITELIST.has(ort_id):
			continue
		var konfig := _konfig_von(ort_id)
		assert_false(konfig.is_empty(), "PT2-B4: %s hat keine _leben_konfig()" % ort_id)
		assert_true(
			OrtLeben.besucher_slots(konfig) >= 2, "%s hat <2 Besucher-Slots (Geher+Sitzer)" % ort_id
		)


## --------------------------------------------------- Konfig-Wachen je Ort


func test_konfig_wachen_momente_sounds_clips() -> void:
	for ort_id in MOMENTE_ORTE:
		var konfig := _konfig_von(ort_id)
		var momente: Array = konfig.get("momente", [])
		assert_true(
			momente.size() >= 2 and momente.size() <= 3,
			"%s braucht 2–3 ortstypische Momente (hat %d)" % [ort_id, momente.size()]
		)
		for moment: Dictionary in momente:
			var sound := str(moment.get("sound", ""))
			assert_false(
				SfxMap.entry(sound).is_empty(),
				"%s: Moment-Sound fehlt in SfxMap: %s" % [ort_id, sound]
			)
			var clip := str(moment.get("clip", ""))
			assert_true(
				EINMAL_CLIPS.has(clip), "%s: Moment-Clip ist kein Einmal-Clip: %s" % [ort_id, clip]
			)
			assert_true(
				float(moment.get("alle_s", 0.0)) >= OrtLeben.MOMENT_MIN_TAKT_S,
				"%s: Moment-Takt unter MOMENT_MIN_TAKT_S" % ort_id
			)
			var domain := str(moment.get("sprueche", ""))
			assert_true(
				I18nService.has_key("city_leben.sprueche.%s" % domain),
				"%s: Moment-Spruch-Domain fehlt: %s" % [ort_id, domain]
			)
		var walk_domain := str(konfig.get("sprueche", ""))
		assert_true(
			I18nService.has_key("city_leben.sprueche.%s" % walk_domain),
			"%s: Spruch-Domain fehlt: %s" % [ort_id, walk_domain]
		)
		var requisit := str(konfig.get("requisit", ""))
		if not requisit.is_empty():
			assert_true(
				OrtLeben.REQUISIT_FARBEN.has(requisit),
				"%s: unbekanntes Trage-Requisit: %s" % [ort_id, requisit]
			)
		var sitze: Array = konfig.get("sitze", [])
		assert_true(sitze.size() <= OrtLeben.SITZE_MAX, "%s: zu viele Sitzer" % ort_id)
		for sitz: Dictionary in sitze:
			assert_true(sitz.has("pos"), "%s: Sitz ohne Position" % ort_id)
			var sitz_req := str(sitz.get("requisit", ""))
			if not sitz_req.is_empty():
				assert_true(
					OrtLeben.REQUISIT_FARBEN.has(sitz_req),
					"%s: unbekanntes Sitz-Requisit: %s" % [ort_id, sitz_req]
				)


## DE und EN führen dieselben Spruch-Domains mit denselben Zeilen-Zahlen
## (Ideen-Doc: „deutsche NPC-Momente-Texte DE+EN paritätisch“).
func test_spruch_domains_de_en_paritaetisch() -> void:
	var de := _sprueche_aus("res://strings/de/city_leben.json")
	var en := _sprueche_aus("res://strings/en/city_leben.json")
	assert_true(de.size() >= 20, "DE-Domains vollständig (Rollout + Momente)")
	assert_eq(de.size(), en.size(), "gleich viele Spruch-Domains in DE und EN")
	for domain: String in de:
		assert_true(en.has(domain), "EN-Domain fehlt: %s" % domain)
		if not en.has(domain):
			continue
		assert_eq(
			(de[domain] as Array).size(),
			(en[domain] as Array).size(),
			"Zeilen-Parität verletzt in Domain: %s" % domain
		)
		assert_true((de[domain] as Array).size() >= 2, "Domain zu dünn: %s" % domain)


func _sprueche_aus(pfad: String) -> Dictionary:
	var datei := FileAccess.open(pfad, FileAccess.READ)
	assert_ne(datei, null, "Strings-Datei lädt: %s" % pfad)
	if datei == null:
		return {}
	var wurzel: Variant = JSON.parse_string(datei.get_as_text())
	if not (wurzel is Dictionary):
		fail_test("Strings-Datei ist kein JSON-Objekt: %s" % pfad)
		return {}
	var leben: Dictionary = wurzel.get("city_leben", {})
	return leben.get("sprueche", {})


## ------------------------------------------------- Sitzer + Requisiten


func test_plaene_mit_sitzern_deterministisch_und_gekappt() -> void:
	var konfig := {
		"besucher": 99,
		"punkte": [Vector3.ZERO, Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.0, 2.0)],
		"requisit": "koffer",
		"sitze":
		[
			{"pos": Vector3(1.0, 0.4, 1.0), "requisit": "paket"},
			{"pos": Vector3(2.0, 0.4, 1.0)},
			{"pos": Vector3(3.0, 0.4, 1.0)},
			{"pos": Vector3(4.0, 0.4, 1.0)},
		],
	}
	var a := OrtLeben.plaene(konfig, SEED)
	var b := OrtLeben.plaene(konfig, SEED)
	assert_eq(
		a.size(),
		OrtLeben.BESUCHER_MAX + OrtLeben.SITZE_MAX,
		"Kappen: mehr Geher/Sitzer bewilligt das System nicht"
	)
	assert_eq(OrtLeben.besucher_slots(konfig), a.size(), "besucher_slots zählt wie plaene")
	for i in a.size():
		assert_eq(a[i]["tint"], b[i]["tint"], "Plan %d deterministisch (Tint)" % i)
		assert_eq(a[i]["requisit"], b[i]["requisit"], "Plan %d deterministisch (Requisit)" % i)
	var sitzer := a[OrtLeben.BESUCHER_MAX] as Dictionary
	assert_true(bool(sitzer.get("sitzt", false)), "Sitz-Plan trägt das sitzt-Flag")
	assert_eq(str(sitzer["requisit"]), "paket", "Sitzer-Requisit exakt laut Konfig")
	assert_eq(float(sitzer["tempo"]), 0.0, "Sitzer bewegen sich nicht")


func test_zustand_einzelplatz_bleibt_sitzen() -> void:
	var plan := {
		"punkte": [Vector3(2.0, 0.4, 1.0)],
		"blick": Vector3(2.0, 0.0, -3.0),
	}
	var frueh := OrtLeben.zustand(plan, 0.0)
	var spaet := OrtLeben.zustand(plan, 99.0)
	assert_eq(frueh["pos"], Vector3(2.0, 0.4, 1.0), "Sitzer sitzt auf seinem Platz")
	assert_eq(frueh["pos"], spaet["pos"], "Sitzer bleibt über Zeit sitzen")
	assert_true(bool(frueh["steht"]), "Sitzer zählt als stehend (Moment-Darsteller)")
	assert_almost(float(frueh["heading"]), atan2(0.0, -4.0), 0.001, "Blick zum Blickpunkt")


## ------------------------------------------------------- Momente-System


func test_momente_feuern_im_takt() -> void:
	var leben := OrtLeben.new()
	leben.konfig = {
		"ort_id": "test",
		"momente": [{"alle_s": 8.0, "versatz_s": 2.0, "sound": "", "clip": ""}],
	}
	leben.seed_override = SEED
	leben.reduced_override = 0
	leben.auto_zeit = false
	leben.stumm = true
	tree.root.add_child(leben)
	await wait_frames(1)
	leben.advance_zeit(1.9)
	assert_eq(leben.momente_gefeuert, 0, "vor versatz_s feuert nichts")
	leben.advance_zeit(0.2)
	assert_eq(leben.momente_gefeuert, 1, "erster Schuss nach versatz_s")
	leben.advance_zeit(7.9)
	assert_eq(leben.momente_gefeuert, 1, "dann gilt der alle_s-Takt")
	leben.advance_zeit(0.2)
	assert_eq(leben.momente_gefeuert, 2, "zweiter Schuss nach alle_s")
	leben.queue_free()
	await wait_frames(1)


## ------------------------------------------- Ort-Mount GOOBYTHEKE (neu)


func test_goobytheke_sitzer_requisiten_und_moment() -> void:
	var gs := FakeGameState.new(_basis_state())
	var ort: OrtGoobytheke = GoobythekeSzene.instantiate()
	ort.game_state_override = gs
	ort.leben_seed_override = SEED
	ort.leben_stumm_override = true
	tree.root.add_child(ort)
	await wait_frames(3)
	assert_ne(ort.leben, null, "GOOBYTHEKE hat Ambient-Leben")
	assert_eq(ort.leben.besucher_nodes().size(), 4, "2 Stöberer + 2 Wartebank-Gäste")
	assert_eq(ort.leben.sitzer_anzahl(), 2, "beide Wartebank-Plätze besetzt")
	assert_true(ort.leben.requisit_anzahl() >= 1, "mind. das Taschentuch ist unterwegs")
	assert_ne(ort.kassen_npc, null, "Hilde hat das Tresen-Verhalten")
	# Erster Moment (Niesen: alle_s 19, versatz 6) über die Zeit-Injektion.
	ort.leben.auto_zeit = false
	ort.leben.advance_zeit(6.2)
	assert_eq(ort.leben.momente_gefeuert, 1, "Nies-Moment feuert nach versatz_s")
	assert_eq(str(ort.leben.letzter_moment.get("sound", "")), "pet_squish", "Nies-Sound gewählt")
	await _ort_abbauen(ort)


func test_goobytheke_reduced_motion_behaelt_sitzer() -> void:
	var gs := FakeGameState.new(_basis_state())
	var ort: OrtGoobytheke = GoobythekeSzene.instantiate()
	ort.game_state_override = gs
	ort.leben_seed_override = SEED
	ort.leben_reduced_override = 1
	ort.leben_stumm_override = true
	tree.root.add_child(ort)
	await wait_frames(3)
	assert_true(ort.leben.ist_statisch(), "Reduced Motion ⇒ statisch")
	assert_eq(ort.leben.besucher_nodes().size(), 3, "1 halbierter Geher + 2 Sitzer")
	assert_eq(ort.leben.sitzer_anzahl(), 2, "Sitzer überleben Reduced Motion")
	await _ort_abbauen(ort)


func test_goobytheke_kasse_piept_beim_kauf() -> void:
	var gs := FakeGameState.new(_basis_state())
	var ort: OrtGoobytheke = GoobythekeSzene.instantiate()
	ort.game_state_override = gs
	ort.leben_seed_override = SEED
	ort.leben_stumm_override = true
	tree.root.add_child(ort)
	await wait_frames(3)
	assert_eq(ort.kassen_npc.piep_zaehler, 0, "noch kein Kunde")
	ort._on_kunde_zahlt("gooby_tropfen")
	assert_eq(ort.kassen_npc.piep_zaehler, 1, "Kauf piept an Hildes Tresen")
	await _ort_abbauen(ort)
