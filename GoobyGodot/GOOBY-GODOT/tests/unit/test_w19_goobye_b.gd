extends TestCase
## W19 Welle B „Goo und Bye“ (Doc §4.2–§4.4) — Wächter für Großmarkt-Fahrt,
## Tagesangebot und Kühl-Kapazität:
##   (a) GoobyeTransport: Kofferraum-Stufen, fahrer_sim-Zeitmodell (PURE
##       Funktion der injizierten Uhr), atomare Bestellung + Ausladen,
##   (b) GoobyeAngebot: −15 % Preis, +40 % Griff (nur VERGLEICHE — die
##       Zufallsfolge des Markttags bleibt golden-stabil), 1 Gruppe/Tag,
##   (c) GoobyeKuehl: Planungs-Constraint + atomarer Modul-Kauf,
##   plus Save-Self-Heal (GoobyeState) und die Laden-Szene Ende-zu-Ende
##   (Bestell-Sheet → Fahrt → Ausladen; Angebots-Schild; Kühl-Grenze),
##   plus die W19-Playtest-Layout-Wächter: Slot-Chips + 3D-Anker bleiben
##   in BEIDEN Leitformaten tappbar im Canvas (hochkant schnitt Slot 0 ab)
##   und das Kritzel-Schild hängt ÜBER den Chips (quer hing es dahinter).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")

## Gepinnte Test-Uhr (fixe Epoche — Determinismus-Regel AGENTS.md).
const T0 := 1_750_000_000_000

## Leitformate (physische px, Screen-Scale 3 — Muster test_w18_g5_ui_fixes)
## für die W19-Playtest-Layout-Wächter.
const FORMAT_HOCH := Vector2i(1320, 2868)
const FORMAT_QUER := Vector2i(2868, 1320)
const FORMAT_SCALE := 3.0

var _dir_seq := 0
var _saved_root_size := Vector2i.ZERO


func _fresh_gs(level: int, coins: int) -> Node:
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://goobye_b_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.clock.pin(T0)
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(GoobyeState.SLICE_ID)
	GoobyeState.reset_for_tests()
	GoobyeKatalog.registry_override = null
	GoobyeKatalog.reset_cache()


## ------------------------------------------------------ (a) Transport PURE


func test_transport_kapazitaet() -> void:
	GoobyeKatalog.reset_cache()
	assert_eq(GoobyeTransport.kisten_kapazitaet("sedan"), 12, "Start-Sedan = klein")
	assert_eq(GoobyeTransport.kisten_kapazitaet("hatchback-sports"), 12, "Flitzer = klein")
	assert_eq(GoobyeTransport.kisten_kapazitaet("suv"), 24, "SUV = Kombi-Klasse")
	assert_eq(GoobyeTransport.kisten_kapazitaet("van"), 24, "Van = Kombi-Klasse")
	assert_eq(GoobyeTransport.kisten_kapazitaet("sedan", true), 48, "Lieferwagen schlägt alles")
	var gs := _fresh_gs(12, 0)
	assert_eq(GoobyeTransport.kapazitaet_fuer(gs), 12, "frischer Save fährt den Start-Wagen")
	gs.set_value("city.autos", {"van": "#FFF4E6"})
	gs.set_value("city.aktivesAuto", "van")
	assert_eq(GoobyeTransport.kapazitaet_fuer(gs), 24, "aktives Kombi-Auto zählt")
	assert_false(GoobyeTransport.lieferwagen_frei(gs), "Lieferwagen startet gesperrt")
	GoobyeTransport.lieferwagen_freischalten(gs)
	assert_true(GoobyeTransport.lieferwagen_frei(gs), "Freischaltung landet im Save")
	assert_eq(GoobyeTransport.kapazitaet_fuer(gs), 48, "Lieferwagen übersteuert das Auto")
	_teardown_gs(gs)


func test_transport_zeitmodell_pure() -> void:
	# Fahrzeit = Hinfahrt + Beladen je Kiste + Rückfahrt (§4.2).
	var dauer := GoobyeTransport.fahrzeit_ms(3)
	assert_eq(
		dauer,
		GoobyeTransport.HIN_MS + 3 * GoobyeTransport.BELADEN_JE_KISTE_MS + GoobyeTransport.RUECK_MS
	)
	var ankunft := GoobyeTransport.ankunft_ms(T0, 3)
	assert_eq(ankunft, T0 + dauer, "Ankunft = Bestellzeit + Fahrzeit")
	# Phasen als PURE Funktion der Uhr (fahrer_sim-Muster): gleiche Zeit =
	# gleiche Position, egal wie oft gefragt wird.
	var hinfahrt := GoobyeTransport.status(T0, ankunft, T0 + 1_000)
	assert_eq(str(hinfahrt["phase"]), GoobyeTransport.PHASE_HINFAHRT)
	var beladen := GoobyeTransport.status(T0, ankunft, T0 + GoobyeTransport.HIN_MS + 1_000)
	assert_eq(str(beladen["phase"]), GoobyeTransport.PHASE_BELADEN)
	var rueck := GoobyeTransport.status(T0, ankunft, ankunft - 1_000)
	assert_eq(str(rueck["phase"]), GoobyeTransport.PHASE_RUECKFAHRT)
	var da := GoobyeTransport.status(T0, ankunft, ankunft)
	assert_eq(str(da["phase"]), GoobyeTransport.PHASE_DA)
	assert_eq(int(da["rest_ms"]), 0, "angekommen = kein Rest")
	assert_almost(float(da["fortschritt"]), 1.0)
	# Fortschritt wächst monoton, Rest schrumpft passend.
	assert_true(
		float(hinfahrt["fortschritt"]) < float(beladen["fortschritt"]),
		"Fortschritt wächst mit der Uhr"
	)
	assert_eq(int(hinfahrt["rest_ms"]), ankunft - (T0 + 1_000), "Rest = Ankunft − jetzt")


func test_transport_bestellung_atomar() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 100)
	assert_eq(GoobyeTransport.bestelle(gs, {}), GoobyeTransport.RESULT_LEER, "leerer Korb blockt")
	assert_eq(
		GoobyeTransport.bestelle(gs, {"apple": 0, "quatschware": 5}),
		GoobyeTransport.RESULT_LEER,
		"0-Mengen und Fremd-IDs heilen zum leeren Korb"
	)
	assert_eq(
		GoobyeTransport.bestelle(gs, {"apple": 13}),
		GoobyeTransport.RESULT_ZU_VIEL,
		"13 Kisten passen nicht in den Start-Sedan (12)"
	)
	assert_eq(int(gs.get_value("economy.coins")), 100, "Fehlversuche buchen NICHTS ab")
	assert_true(GoobyeTransport.unterwegs_von(gs).is_empty(), "keine Fahrt angelegt")
	# Erfolgsfall: apple-EK 4 ᴳ ×2 + cheese-EK 7 ᴳ = 15 ᴳ (60 % Richtwert §2.2).
	var korb := {"apple": 2, "cheese": 1}
	assert_eq(GoobyeTransport.kosten(korb), 15, "Einkauf = 60 % des Richtwerts, gerundet")
	assert_eq(GoobyeTransport.bestelle(gs, korb), GoobyeTransport.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins")), 85, "Münzen und Fahrt in EINEM Block")
	var fahrt := GoobyeTransport.unterwegs_von(gs)
	assert_eq(int(fahrt["bestelltAt"]), T0, "Bestellzeit = gepinnte Uhr")
	assert_eq(int(fahrt["ankunftAt"]), GoobyeTransport.ankunft_ms(T0, 3), "Ankunft aus Kisten")
	assert_eq(fahrt["warenkorb"], {"apple": 2, "cheese": 1}, "Korb liegt geheilt im Save")
	assert_eq(
		GoobyeTransport.bestelle(gs, {"apple": 1}),
		GoobyeTransport.RESULT_UNTERWEGS,
		"nur EINE Fahrt gleichzeitig"
	)
	assert_eq(int(gs.get_value("economy.coins")), 85, "Zweit-Bestellung bucht nichts ab")
	_teardown_gs(gs)
	# Zu wenig Münzen: alles bleibt stehen (W18-Geld-Regel).
	var arm := _fresh_gs(12, 3)
	assert_eq(GoobyeTransport.bestelle(arm, {"apple": 1}), GoobyeTransport.RESULT_BROKE)
	assert_eq(int(arm.get_value("economy.coins")), 3, "Pleite-Fall bucht nichts ab")
	assert_true(GoobyeTransport.unterwegs_von(arm).is_empty(), "Pleite-Fall legt keine Fahrt an")
	_teardown_gs(arm)


func test_transport_ausladen_erst_nach_ankunft() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 100)
	assert_eq(GoobyeTransport.bestelle(gs, {"apple": 2, "cheese": 1}), GoobyeTransport.RESULT_OK)
	# Unterwegs: Ausladen blockt, Phase folgt der Uhr (App zu/auf egal).
	var zu_frueh := GoobyeTransport.ausladen(gs)
	assert_false(bool(zu_frueh["ok"]), "vor der Ankunft kein Ausladen")
	assert_eq(str(zu_frueh["grund"]), GoobyeTransport.RESULT_NICHT_DA)
	assert_eq(str(GoobyeTransport.status_von(gs)["phase"]), GoobyeTransport.PHASE_HINFAHRT)
	gs.clock.advance(GoobyeTransport.HIN_MS + 1_000)
	assert_eq(str(GoobyeTransport.status_von(gs)["phase"]), GoobyeTransport.PHASE_BELADEN)
	gs.clock.advance(GoobyeTransport.fahrzeit_ms(3))
	assert_eq(str(GoobyeTransport.status_von(gs)["phase"]), GoobyeTransport.PHASE_DA)
	# Ankunft: Warenkorb wandert KOMPLETT ins Lager, Fahrt ist abgeräumt.
	var ergebnis := GoobyeTransport.ausladen(gs)
	assert_true(bool(ergebnis["ok"]), "nach der Ankunft lädt alles aus")
	assert_eq(int(ergebnis["kisten"]), 3)
	assert_eq(
		gs.get_value("dlc.goobye.lager"), {"apple": 2, "cheese": 1}, "kein Stück geht verloren"
	)
	assert_true(GoobyeTransport.unterwegs_von(gs).is_empty(), "Fahrt abgeräumt")
	assert_false(bool(GoobyeTransport.ausladen(gs)["ok"]), "Doppel-Ausladen blockt")
	_teardown_gs(gs)


func test_state_self_heal_welle_b() -> void:
	# Kaputte Timestamps werden REPARIERT statt gelöscht — eine bezahlte
	# Fahrt darf ihre Ware nie verlieren (§1.4-Geist).
	var heil := (
		GoobyeState
		. normalize_goobye(
			{
				"transport":
				{
					"lieferwagen": 1,
					"unterwegs":
					{
						"bestelltAt": -5,
						"ankunftAt": "quatsch",
						"warenkorb": {"apple": 2, "leer": 0},
					},
				},
				"tagesangebot": ["quatsch"],
				"kuehlModule": -3,
			}
		)
	)
	assert_eq(heil["transport"]["lieferwagen"], true, "truthy → bool")
	assert_eq(heil["transport"]["unterwegs"]["bestelltAt"], 0, "Timestamp repariert")
	assert_eq(heil["transport"]["unterwegs"]["ankunftAt"], 0, "Ankunft ≥ Bestellzeit")
	assert_eq(heil["transport"]["unterwegs"]["warenkorb"], {"apple": 2}, "Korb geheilt")
	assert_eq(heil["tagesangebot"], {"gruppe": "", "tag": ""}, "kaputtes Angebot → leer")
	assert_eq(heil["kuehlModule"], 1, "mindestens die Welle-A-Kühltheke")
	# NUR ein leerer Warenkorb löscht die Fahrt.
	var leer := GoobyeState.normalize_goobye(
		{"transport": {"unterwegs": {"bestelltAt": 5, "ankunftAt": 9, "warenkorb": {}}}}
	)
	assert_eq(leer["transport"]["unterwegs"], {}, "leerer Korb räumt die Fahrt ab")
	# Alt-Saves (Welle A, ohne neue Schlüssel) bekommen die Defaults additiv.
	var alt := GoobyeState.normalize_goobye({"gekauft": true})
	assert_eq(alt["transport"], {"lieferwagen": false, "unterwegs": {}})
	assert_eq(alt["tagesangebot"], {"gruppe": "", "tag": ""})
	assert_eq(alt["kuehlModule"], 1)
	assert_eq(alt["gekauft"], true, "Bestand bleibt")


## ------------------------------------------------------- (b) Tagesangebot


func test_angebot_preise_pure() -> void:
	GoobyeKatalog.reset_cache()
	var apple := GoobyeKatalog.ware("apple")
	# apple-Richtwert 6 ᴳ → −15 % = 5.1 → 5 ᴳ (EINE Rundung, nie unter 1).
	assert_eq(GoobyeAngebot.angebots_preis(apple), 5, "−15 % auf den Richtwert")
	assert_eq(
		GoobyeAngebot.preis_fuer_zeile(apple, 1.0, false),
		GoobyePreis.verkaufspreis(apple, 1.0),
		"ohne Flag exakt der Welle-A-Preis"
	)
	assert_eq(GoobyeAngebot.preis_fuer_zeile(apple, 1.0, true), 5, "mit Flag der Angebots-Preis")
	assert_true(
		GoobyeAngebot.angebots_preis(apple, 0.7) >= 1, "Rabatt auf Tiefpreis fällt nie unter 1"
	)
	assert_almost(GoobyeAngebot.GRIFF_BONUS, 0.4, 1e-9, "+40 % Griff-Lust (§4.4)")
	assert_almost(GoobyeAngebot.RABATT, 0.15, 1e-9, "−15 % Preis (§4.4)")


func test_angebot_eine_gruppe_pro_tag() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 0)
	var tag := GoobyeAngebot.tag_key(T0)
	assert_eq(
		GoobyeAngebot.waehle(gs, "quatschgruppe"),
		GoobyeAngebot.RESULT_UNBEKANNT,
		"unbekannte Gruppe blockt"
	)
	assert_eq(GoobyeAngebot.aktive_gruppe_von(gs), "", "frischer Save: kein Angebot")
	assert_eq(GoobyeAngebot.waehle(gs, "obst"), GoobyeAngebot.RESULT_OK)
	assert_eq(gs.get_value("dlc.goobye.tagesangebot"), {"gruppe": "obst", "tag": tag})
	assert_eq(GoobyeAngebot.aktive_gruppe_von(gs), "obst", "heute aktiv")
	assert_eq(
		GoobyeAngebot.waehle(gs, "obst"), GoobyeAngebot.RESULT_OK, "gleiche Wahl = stilles OK"
	)
	assert_eq(
		GoobyeAngebot.waehle(gs, "gemuese"),
		GoobyeAngebot.RESULT_SCHON_GEWAEHLT,
		"nur EINE Gruppe pro Tag"
	)
	assert_eq(GoobyeAngebot.aktive_gruppe_von(gs), "obst", "Erst-Wahl bleibt stehen")
	# Nächster Tag (injizierte Uhr): gestern gilt nicht mehr, neue Wahl frei.
	gs.clock.advance(86_400_000)
	assert_eq(GoobyeAngebot.aktive_gruppe_von(gs), "", "Angebot läuft um Mitternacht aus")
	assert_eq(GoobyeAngebot.waehle(gs, "gemuese"), GoobyeAngebot.RESULT_OK, "morgen wieder")
	# Kritzel-Schild deterministisch aus Tag + Gruppe (0..5, stabil).
	var variante := GoobyeAngebot.schild_variante(tag, "obst")
	assert_true(variante >= 0 and variante < GoobyeAngebot.SCHILD_VARIANTEN, "Variante 0..5")
	assert_eq(
		GoobyeAngebot.schild_variante(tag, "obst"), variante, "gleicher Tag = gleiches Schild"
	)
	_teardown_gs(gs)


func test_angebot_markttag_golden_stabil_und_monoton() -> void:
	GoobyeKatalog.reset_cache()
	var opts := {"kunden_min": 3, "kunden_max": 3}
	var sortiment: Array = [{"id": "apple", "bestand": 12, "faktor": 1.3}]
	# Golden-Wache: markieren ohne aktive Gruppe lässt den Plan BIT-IDENTISCH
	# (Welle-A-Golden-Tests bleiben gültig).
	var markiert_leer := GoobyeAngebot.sortiment_markieren(sortiment, "")
	assert_eq(
		GoobyeMarkttag.tag_planen(4711, sortiment, opts).hash(),
		GoobyeMarkttag.tag_planen(4711, markiert_leer, opts).hash(),
		"ohne Angebot bleibt jeder Plan bit-identisch"
	)
	# markieren flaggt NUR die Angebots-Gruppe (tiefe Kopien, Quelle bleibt).
	var gemischt: Array = [
		{"id": "apple", "bestand": 3, "faktor": 1.0},
		{"id": "carrot", "bestand": 3, "faktor": 1.0},
	]
	var markiert := GoobyeAngebot.sortiment_markieren(gemischt, "obst")
	assert_eq(markiert[0].get("angebot"), true, "obst-Zeile geflaggt")
	assert_false((markiert[1] as Dictionary).has("angebot"), "gemuese-Zeile unangetastet")
	assert_false((gemischt[0] as Dictionary).has("angebot"), "Quelle bleibt unverändert")
	# Monotonie (§4.4): +40 % wirken nur auf VERGLEICHE — gleiche Kunden,
	# gleiche Los-Folge, nie WENIGER Verkäufe; über viele Seeds sogar mehr.
	var angebots_zeilen: Array = [{"id": "apple", "bestand": 12, "faktor": 1.3, "angebot": true}]
	var summe_ohne := 0
	var summe_mit := 0
	for seed_wert in range(1, 21):
		var ohne := GoobyeMarkttag.tag_planen(seed_wert, sortiment, opts)
		var mit := GoobyeMarkttag.tag_planen(seed_wert, angebots_zeilen, opts)
		assert_eq(mit["kundenzahl"], ohne["kundenzahl"], "Kundenzahl bleibt (Seed %d)" % seed_wert)
		var archetypen_ohne: Array = []
		var archetypen_mit: Array = []
		for bon: Dictionary in ohne["bons"]:
			archetypen_ohne.append(bon["archetyp"])
		for bon: Dictionary in mit["bons"]:
			archetypen_mit.append(bon["archetyp"])
		assert_eq(archetypen_mit, archetypen_ohne, "Kunden-Folge bleibt (Seed %d)" % seed_wert)
		var apfel_ohne := int((ohne["verkauft"] as Dictionary).get("apple", 0))
		var apfel_mit := int((mit["verkauft"] as Dictionary).get("apple", 0))
		assert_true(apfel_mit >= apfel_ohne, "Angebot verkauft nie weniger (Seed %d)" % seed_wert)
		summe_ohne += apfel_ohne
		summe_mit += apfel_mit
		# Angebots-Positionen zahlen den −15 %-Preis (faktor-bewusst).
		for bon: Dictionary in mit["bons"]:
			for position: Dictionary in bon.get("positionen", []):
				if str(position.get("ware", "")) == "apple":
					assert_eq(
						int(position["preis"]),
						GoobyeAngebot.angebots_preis(GoobyeKatalog.ware("apple"), 1.3),
						"Bon-Preis = Angebots-Preis (Seed %d)" % seed_wert
					)
	assert_true(summe_mit > summe_ohne, "+40 % Griff-Lust ist über 20 Seeds fühlbar")


## ------------------------------------------------------ (c) Kühl-Kapazität


func test_kuehl_constraint_und_modul_kauf() -> void:
	GoobyeKatalog.reset_cache()
	assert_eq(GoobyeKuehl.kapazitaet(1), 8, "1 Modul = 8 Kühlplätze")
	assert_eq(GoobyeKuehl.kapazitaet(3), 24)
	assert_true(GoobyeKuehl.ist_kuehlware("cheese"), "cheese gehört zur Kühlgruppe")
	assert_true(GoobyeKuehl.ist_kuehlware("ice-cream"))
	assert_false(GoobyeKuehl.ist_kuehlware("apple"), "Obst braucht keine Kühlung")
	var regal := GoobyeRegal.neues_regal()
	regal["slots"][0] = {"ware": "cheese", "menge": 6}
	assert_eq(GoobyeKuehl.kuehl_stueck(regal), 6, "Kühlware über alle Slots gezählt")
	assert_eq(GoobyeKuehl.einraeumbar(regal, "ice-cream", 8, 1), 2, "nur noch 2 von 8 frei")
	assert_eq(GoobyeKuehl.einraeumbar(regal, "ice-cream", 8, 2), 8, "2. Modul öffnet den Platz")
	assert_eq(GoobyeKuehl.einraeumbar(regal, "apple", 5, 1), 5, "Trockenware unbegrenzt")
	# Modul-Kauf atomar (W18-Geld-Regel): Münzen runter UND Zähler rauf.
	var gs := _fresh_gs(12, GoobyeKuehl.MODUL_PREIS + 10)
	assert_eq(GoobyeKuehl.module_von(gs), 1, "Start: die Welle-A-Kühltheke")
	assert_eq(GoobyeKuehl.kaufe_modul(gs), GoobyeKuehl.RESULT_OK)
	assert_eq(int(gs.get_value("economy.coins")), 10, "exakt der Modul-Preis abgebucht")
	assert_eq(GoobyeKuehl.module_von(gs), 2)
	assert_eq(GoobyeKuehl.kaufe_modul(gs), GoobyeKuehl.RESULT_BROKE, "Pleite blockt")
	assert_eq(int(gs.get_value("economy.coins")), 10, "Pleite-Fall bucht nichts ab")
	assert_eq(GoobyeKuehl.module_von(gs), 2, "Zähler unangetastet")
	_teardown_gs(gs)


## ------------------------------------------------------ Laden-Szene (Glue)


func test_szene_grossmarkt_fahrt_ende_zu_ende() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis() + 100)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 12345
	szene.tempo = 0.05
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	# Leisten-Knopf öffnet das Bestell-Sheet (frisches PanelSheet).
	var knopf: Button = szene.find_child("Grossmarkt", true, false)
	assert_true(knopf != null and not knopf.disabled, "Großmarkt-Knopf aktiv beim Einräumen")
	knopf.pressed.emit()
	await wait_frames(2)
	assert_true(szene.grossmarkt.sheet != null, "Bestell-Sheet offen")
	var plus: Button = szene.find_child("Plus_apple", true, false)
	assert_true(plus != null, "±-Stepper je Ware vorhanden")
	plus.pressed.emit()
	plus.pressed.emit()
	await wait_frames(1)
	assert_eq(szene.grossmarkt.korb, {"apple": 2}, "Korb zählt die Taps")
	var anzahl: Label = szene.find_child("Anzahl_apple", true, false)
	assert_eq(anzahl.text, "2", "Zeile zeigt die Stückzahl")
	var coins_vorher := int(gs.get_value("economy.coins"))
	var losfahren: Button = szene.find_child("Losfahren", true, false)
	losfahren.pressed.emit()
	await wait_frames(2)
	assert_eq(int(gs.get_value("economy.coins")), coins_vorher - 8, "2 Äpfel à EK 4 ᴳ bezahlt")
	var fahrt := GoobyeTransport.unterwegs_von(gs)
	assert_eq(fahrt["warenkorb"], {"apple": 2}, "Fahrt liegt im Save")
	assert_true(knopf.disabled, "unterwegs: Knopf zeigt Status, nicht klickbar")
	# Uhr vorspulen (fahrer_sim: Position = Funktion der Uhr) → Ankunft.
	gs.clock.advance(GoobyeTransport.fahrzeit_ms(2) + 1_000)
	szene.grossmarkt.aktualisiere()
	assert_false(knopf.disabled, "angekommen: Knopf wird zum Ausladen")
	assert_eq(knopf.text, I18nService.t("dlc_goobye.grossmarkt.ausladen"))
	knopf.pressed.emit()
	await wait_frames(2)
	assert_eq(int(gs.get_value("dlc.goobye.lager.apple", 0)), 8, "6 Start-Äpfel + 2 ausgeladen")
	assert_true(GoobyeTransport.unterwegs_von(gs).is_empty(), "Fahrt abgeräumt")
	# Verlassen: die Szenen-Lagerkopie kennt die Ankunft — nichts geht
	# verloren, wenn _bestand_sichern zurückschreibt (§1.4).
	szene.queue_free()
	await wait_frames(2)
	assert_eq(int(gs.get_value("dlc.goobye.lager.apple", 0)), 8, "Ausladen überlebt das Verlassen")
	_teardown_gs(gs)


func test_szene_tagesangebot_schild_und_markttag() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis() + 100)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 777
	szene.tempo = 0.05
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(
		szene.find_child("AngebotsSchild", true, false) == null, "ohne Angebot hängt kein Schild"
	)
	var knopf: Button = szene.find_child("Tagesangebot", true, false)
	assert_true(knopf != null and not knopf.disabled, "Angebots-Knopf aktiv beim Einräumen")
	knopf.pressed.emit()
	await wait_frames(2)
	var wahl: Button = szene.find_child("Angebot_obst", true, false)
	assert_true(wahl != null, "Gruppen-Knopf im Auswahl-Sheet")
	wahl.pressed.emit()
	await wait_frames(2)
	assert_eq(
		gs.get_value("dlc.goobye.tagesangebot"),
		{"gruppe": "obst", "tag": GoobyeAngebot.tag_key(T0)},
		"Wahl liegt mit Tages-Stempel im Save"
	)
	assert_true(szene.find_child("AngebotsSchild", true, false) != null, "Kritzel-Schild hängt")
	# Markttag mit Angebot: die Szene übergibt das MARKIERTE Sortiment —
	# der Umsatz entspricht exakt dem nachgerechneten Angebots-Plan (−15 %).
	szene.slot_tippen(0)
	await wait_frames(1)
	szene.laden_oeffnen()
	var fertig := await wait_until(
		func() -> bool: return szene.phase == GoobyeLadenScene.PHASE_ABSCHLUSS, 20000
	)
	assert_true(fertig, "Markttag läuft bis zur Abschluss-Karte durch")
	var plan := GoobyeMarkttag.tag_planen(
		777,
		[{"id": "apple", "bestand": 6, "faktor": 1.0, "angebot": true}],
		{"kunden_min": GoobyeLadenScene.KUNDEN_MIN, "kunden_max": GoobyeLadenScene.KUNDEN_MAX}
	)
	var erwartet := 0
	for bon: Dictionary in plan["bons"]:
		for position: Dictionary in bon.get("positionen", []):
			erwartet += int(position["preis"])
	assert_true(erwartet > 0, "Testtag verkauft etwas (Seed 777)")
	assert_eq(szene.umsatz_heute, erwartet, "Szene rechnet mit dem Angebots-Sortiment")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


## ------------------------------------------- Layout-Wächter (W19-Playtest)


func test_chip_reihe_in_grenzen_pure() -> void:
	# Reihe passt → unangetastet (Chips bleiben an den Anker-Mitten).
	var frei: Array[float] = [200.0, 300.0, 400.0]
	assert_eq(GoobyeLadenUiTeile.reihe_in_grenzen(frei, 50.0, 0.0, 600.0), frei)
	# Links übergestanden (der Hochkant-Blocker: Slot-0-Tap ging ins
	# Leere): die GANZE Reihe rückt rein, die Abstände bleiben.
	var links_raus: Array[float] = [-20.0, 130.0, 280.0]
	assert_eq(
		GoobyeLadenUiTeile.reihe_in_grenzen(links_raus, 66.0, 0.0, 1320.0),
		[66.0, 216.0, 366.0],
		"links: Chip 0 sitzt mit halber Breite exakt am Rand"
	)
	# Rechts übergestanden: Reihe rückt nach links.
	assert_eq(
		GoobyeLadenUiTeile.reihe_in_grenzen([1200.0, 1300.0], 66.0, 0.0, 1320.0),
		[1154.0, 1254.0],
		"rechts: letzter Chip sitzt mit halber Breite am Rand"
	)
	# Breiter als der Canvas: der LINKE Rand gewinnt (Slot 0 zuerst).
	assert_eq(
		GoobyeLadenUiTeile.reihe_in_grenzen([0.0, 700.0], 66.0, 0.0, 600.0),
		[66.0, 766.0],
		"zu breit: Slot 0 bleibt erreichbar"
	)
	var leer: Array[float] = []
	assert_eq(GoobyeLadenUiTeile.reihe_in_grenzen(leer, 66.0, 0.0, 600.0), [])


func test_kamera_z_fuer_punkte_pure() -> void:
	# Ohne Neigung, Punkt auf Kamera-Höhe: |x| 2 bei tan ½ → Tiefe 4,
	# Kamera-Z = punkt.z + 4 = 3 (reine Strahlensatz-Gegenprobe).
	var punkt_flach: Array[Vector3] = [Vector3(-2.0, 2.0, -1.0)]
	assert_almost(GoobyeLadenUiTeile.kamera_z_fuer_punkte(2.0, 0.0, 0.5, punkt_flach, 0.0), 3.0)
	# Laden-Setup hochkant (Pitch −12°, FOV 75° KEEP_HEIGHT): das Z stellt
	# den Slot-0-Anker (+ Rand) EXAKT an den FOV-Rand — nachgerechnet über
	# die Projektions-Gleichung. Das alte feste Z 6.0 war zu nah (Blocker).
	var pitch := deg_to_rad(-12.0)
	var tan_halb_h := tan(deg_to_rad(75.0) * 0.5) * (1320.0 / 2868.0)
	var anker := Vector3(-2.64, 1.0, -1.2)
	var kamera_z := GoobyeLadenUiTeile.kamera_z_fuer_punkte(2.0, pitch, tan_halb_h, [anker], 0.6)
	var tiefe := (anker.y - 2.0) * sin(pitch) - (anker.z - kamera_z) * cos(pitch)
	assert_almost(tiefe * tan_halb_h, absf(anker.x) + 0.6, 1e-4, "Anker + Rand am FOV-Rand")
	assert_true(kamera_z > 6.0, "hochkant braucht MEHR Abstand als das alte feste 6.0")


## Der W19-Playtest-Blocker als Szenen-Wächter: in BEIDEN Leitformaten
## liegen alle 5 Slot-Chips KOMPLETT im Canvas (hochkant war Slot 0
## abgeschnitten — Taps gingen ins Leere), die 3D-Slot-Anker stehen im
## Sichtfeld (Kamera-Z), und das Kritzel-Schild hängt ÜBER den Chips
## statt dahinter (quer war es fast komplett verdeckt).
func test_szene_slots_und_schild_in_beiden_leitformaten() -> void:
	GoobyeKatalog.reset_cache()
	for format: Vector2i in [FORMAT_HOCH, FORMAT_QUER]:
		await _pin(format, FORMAT_SCALE)
		var gs := _fresh_gs(12, 500)
		gs.set_value("dlc.goobye.erstbesuchGesehen", true)
		var szene: GoobyeLadenScene = LadenSzene.instantiate()
		szene.game_state_override = gs
		szene.auto_navigate = false
		tree.root.add_child(szene)
		await wait_frames(3)
		var sicht := (szene.get_viewport() as Viewport).get_visible_rect()
		var cams := szene.find_children("*", "Camera3D", true, false)
		assert_true(not cams.is_empty(), "%s: Diorama-Kamera vorhanden" % format)
		var cam: Camera3D = cams[0]
		for i in GoobyeRegal.SLOTS:
			var knopf: Button = szene.find_child("Slot%d" % i, true, false)
			var rect := knopf.get_global_rect()
			assert_true(rect.position.x >= sicht.position.x, "%s: Slot %d links raus" % [format, i])
			assert_true(rect.end.x <= sicht.end.x, "%s: Slot %d rechts raus" % [format, i])
			var anker: Node3D = szene.find_child("SlotAnker%d" % i, true, false)
			var projiziert := cam.unproject_position(anker.global_position)
			assert_true(
				projiziert.x >= sicht.position.x and projiziert.x <= sicht.end.x,
				"%s: Slot-Anker %d außerhalb des Sichtfelds" % [format, i]
			)
		# Kritzel-Schild anhängen: seine UNTERKANTE projiziert oberhalb der
		# obersten Chip-Kante — sonst läge es wieder hinter den Chips.
		assert_eq(GoobyeAngebot.waehle(gs, "gemuese"), GoobyeAngebot.RESULT_OK)
		szene.angebot.schild_aktualisieren()
		await wait_frames(1)
		assert_true(szene.angebot.schild != null, "%s: Kritzel-Schild hängt" % format)
		var unterkante := cam.unproject_position(
			szene.angebot.schild.global_position + Vector3(0.0, -0.3, 0.0)
		)
		var chip_oberkante := INF
		for i in GoobyeRegal.SLOTS:
			var knopf: Button = szene.find_child("Slot%d" % i, true, false)
			chip_oberkante = minf(chip_oberkante, knopf.get_global_rect().position.y)
		assert_true(
			unterkante.y <= chip_oberkante + 1.0,
			"%s: Schild-Unterkante hängt hinter/unter den Chips" % format
		)
		szene.queue_free()
		await wait_frames(2)
		_teardown_gs(gs)
	await _unpin()


## Viewport-Pin fürs Leitformat (Muster test_w18_g5_ui_fixes._pin).
func _pin(size: Vector2i, screen_scale := 0.0) -> void:
	if _saved_root_size == Vector2i.ZERO:
		_saved_root_size = tree.root.size
	UiScale.screen_scale_override = screen_scale
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


func _unpin() -> void:
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		_saved_root_size = Vector2i.ZERO
	tree.root.size_changed.emit()
	await wait_frames(2)


func test_szene_kuehl_grenze_beim_einraeumen() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 200)
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	gs.set_value("dlc.goobye.lager", {"ice-cream": 10})
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	# 1 Modul = 8 Plätze: Slot 0 füllt bis zur Kühl-Grenze …
	szene.slot_tippen(0)
	await wait_frames(1)
	var slot0: Button = szene.find_child("Slot0", true, false)
	assert_eq(slot0.text, "×8", "Kühl-Kapazität deckelt bei 8")
	# … Slot 1 blockt (kein Platz), bis ein Kühlmodul dazukommt.
	szene.slot_tippen(1)
	await wait_frames(1)
	var slot1: Button = szene.find_child("Slot1", true, false)
	assert_eq(slot1.text, "+", "ohne freie Kühlplätze bleibt Slot 1 leer")
	assert_eq(GoobyeKuehl.kaufe_modul(gs), GoobyeKuehl.RESULT_OK, "Modul-Nachkauf")
	szene.slot_tippen(1)
	await wait_frames(1)
	assert_eq(slot1.text, "×2", "mit 2. Modul passen die Rest-Eiskugeln")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)
