extends TestCase
## RW-5 — die 7 Wertungsformeln der Wettbewerbe (RANCH-DLC-IDEAS-3 Kap. 5.2)
## gegen Beispielwerte aus dem Doc. Alle Module sind PURE (keine Nodes).

const WSpringen := preload("res://scripts/ranch/comp/wertung/wertung_springen.gd")
const WDressur := preload("res://scripts/ranch/comp/wertung/wertung_dressur.gd")
const WGelaende := preload("res://scripts/ranch/comp/wertung/wertung_gelaende.gd")
const WRennen := preload("res://scripts/ranch/comp/wertung/wertung_rennen.gd")
const WTrail := preload("res://scripts/ranch/comp/wertung/wertung_trail.gd")
const WSchau := preload("res://scripts/ranch/comp/wertung/wertung_schau.gd")
const WTonnen := preload("res://scripts/ranch/comp/wertung/wertung_tonnen.gd")


## Nr. 1 Springparcours: 1000 − 40·Abwurf − 20·Verweigerung − 5·Zeitüber
## + 15·Perfekt.
func test_springen_doc_formel() -> void:
	assert_eq(WSpringen.score(0, 0, 60.0, 60.0, 0), 1000, "fehlerfrei in Richtzeit")
	assert_eq(WSpringen.score(1, 0, 60.0, 60.0, 0), 960, "Abwurf −40")
	assert_eq(WSpringen.score(0, 1, 60.0, 60.0, 0), 980, "Verweigerung −20")
	assert_eq(WSpringen.score(0, 0, 70.0, 60.0, 0), 950, "10 s über Richtzeit −50")
	assert_eq(WSpringen.score(0, 0, 55.0, 60.0, 0), 1000, "unter Richtzeit kein Bonus")
	assert_eq(WSpringen.score(0, 0, 60.0, 60.0, 3), 1045, "3 Perfekt-Absprünge +45")
	assert_eq(WSpringen.score(2, 1, 75.0, 60.0, 2), 855, "Doc-Beispielmix")
	assert_eq(WSpringen.score(30, 10, 300.0, 60.0, 0), 0, "nie unter 0")


func test_springen_sterne_und_kursgroesse() -> void:
	assert_eq(WSpringen.sterne(900), 3)
	assert_eq(WSpringen.sterne(899), 2)
	assert_eq(WSpringen.sterne(750), 2)
	assert_eq(WSpringen.sterne(549), 0)
	assert_eq(WSpringen.hindernis_anzahl("holz"), 8, "8–14 Hindernisse laut Doc")
	assert_eq(WSpringen.hindernis_anzahl("sternenklasse"), 14)


## Nr. 2 Dressur: je Figur 100 − 50·(d̄/0,75) − 25·Gangartfehler;
## Gesamt = Ø + 10 Taktbonus.
func test_dressur_doc_formel() -> void:
	assert_almost(WDressur.figur_punkte(0.0, 0), 100.0)
	assert_almost(WDressur.figur_punkte(0.75, 0), 50.0, 1e-6, "d̄ = 0,75 m halbiert")
	assert_almost(WDressur.figur_punkte(0.0, 1), 75.0, 1e-6, "Gangartfehler −25")
	assert_almost(WDressur.figur_punkte(0.3, 1), 55.0)
	assert_almost(WDressur.figur_punkte(3.0, 2), 0.0, 1e-6, "nie unter 0")
	assert_almost(WDressur.gesamt([100.0, 100.0, 100.0, 100.0, 100.0], true), 110.0)
	assert_almost(WDressur.gesamt([80.0, 60.0], false), 70.0)
	assert_almost(WDressur.gesamt([], true), 0.0, 1e-6, "leer = 0")


func test_dressur_taktfenster() -> void:
	assert_true(WDressur.takt_ok([0.0, -250.0, 250.0]), "±250 ms sind drin")
	assert_false(WDressur.takt_ok([0.0, 251.0]), "einer daneben kippt den Bonus")
	assert_true(WDressur.takt_ok([]), "keine Wechsel = Bonus möglich")
	assert_eq(WDressur.FIGUREN.size(), 5, "5 Figuren laut Doc")


## Nr. 3 Geländeritt: Zeit + 8 s je ausgelassenem Tor (kleiner = besser).
func test_gelaende_doc_formel() -> void:
	assert_almost(WGelaende.wertung_s(100.0, 0), 100.0)
	assert_almost(WGelaende.wertung_s(100.0, 2), 116.0, 1e-6, "2 Tore = +16 s")
	assert_eq(WGelaende.sterne(100.0, 100.0), 3)
	assert_eq(WGelaende.sterne(110.0, 100.0), 2)
	assert_eq(WGelaende.sterne(125.0, 100.0), 1)
	assert_eq(WGelaende.sterne(126.0, 100.0), 0)
	assert_eq(WGelaende.tor_anzahl("holz"), 8, "8–15 Tore laut Doc")
	assert_eq(WGelaende.tor_anzahl("sternenklasse"), 15)


## Nr. 4 Grasbahn-Rennen: Zielreihenfolge + Windschatten (+3 % für 3 s
## nach 1 s Aufbau in < 2 m Abstand).
func test_rennen_reihenfolge_und_dnf() -> void:
	var sortiert := (
		WRennen
		. reihenfolge(
			[
				{"id": "a", "zeit_s": 81.0},
				{"id": "b", "zeit_s": 79.5},
				{"id": "dnf", "zeit_s": 0.0},
				{"id": "c", "zeit_s": 80.0},
			]
		)
	)
	assert_eq(str((sortiert[0] as Dictionary)["id"]), "b")
	assert_eq(str((sortiert[1] as Dictionary)["id"]), "c")
	assert_eq(str((sortiert[3] as Dictionary)["id"]), "dnf", "DNF landet hinten")
	assert_eq(WRennen.platz_von(sortiert, "a"), 3)
	assert_eq(WRennen.platz_von(sortiert, "nix"), 0)


func test_rennen_windschatten() -> void:
	var zustand := WRennen.neuer_zustand()
	zustand = WRennen.step_windschatten(zustand, true, 0.5)
	assert_almost(WRennen.tempo_mult(zustand), 1.0, 1e-6, "Aufbau noch nicht voll")
	zustand = WRennen.step_windschatten(zustand, true, 0.6)
	assert_almost(WRennen.tempo_mult(zustand), 1.03, 1e-6, "+3 % nach 1 s Aufbau")
	zustand = WRennen.step_windschatten(zustand, false, 2.9)
	assert_almost(WRennen.tempo_mult(zustand), 1.03, 1e-6, "Boost hält 3 s")
	zustand = WRennen.step_windschatten(zustand, false, 0.2)
	assert_almost(WRennen.tempo_mult(zustand), 1.0, 1e-6, "danach vorbei")
	assert_true(WRennen.im_fenster(1.5, 0.5), "< 2 m dahinter zählt")
	assert_false(WRennen.im_fenster(2.5, 0.0), "zu weit weg")
	assert_false(WRennen.im_fenster(1.0, 2.0), "seitlich daneben")
	assert_false(WRennen.im_fenster(-0.5, 0.0), "vor dem Pferd gibt es nichts")


## Nr. 5 Westerntrail: 6 Aufgaben à 0–10 P (Berührung −2) + Zeitbonus
## max(0; 20 − ⌈Zeit−90 s⌉); Maximum 80.
func test_trail_doc_formel() -> void:
	assert_eq(WTrail.aufgabe_punkte(0, false), 10)
	assert_eq(WTrail.aufgabe_punkte(1, false), 8, "Berührung −2")
	assert_eq(WTrail.aufgabe_punkte(6, false), 0, "nie negativ")
	assert_eq(WTrail.aufgabe_punkte(0, true), 0, "ausgelassen = 0")
	assert_eq(WTrail.zeitbonus(90.0), 20, "bis 90 s voller Bonus")
	assert_eq(WTrail.zeitbonus(95.5), 14, "⌈5,5⌉ = 6 Abzug")
	assert_eq(WTrail.zeitbonus(200.0), 0)
	assert_eq(WTrail.gesamt([10, 10, 10, 10, 10, 10], 80.0), 80, "Maximum 80")
	assert_eq(WTrail.gesamt([8, 10, 6, 0, 10, 10], 100.0), 54, "44 P + Bonus 10")
	assert_eq(WTrail.AUFGABEN.size(), 6, "6 Aufgaben laut Doc")
	assert_eq(WTrail.sterne(70), 3)
	assert_eq(WTrail.sterne(39), 0)


## Nr. 6 Schau: 0,4·Pflege + 0,3·Stil + 0,3·Kür (je 0–100).
func test_schau_doc_formel() -> void:
	assert_almost(WSchau.pflege(80.0, 60.0), 70.0)
	assert_almost(WSchau.pflege(120.0, -10.0), 50.0, 1e-6, "Eingaben geklemmt")
	var stil := WSchau.stil(["legendaer", "episch", "selten"], true, true)
	assert_almost(stil, 59.0, 1e-6, "16+11+7 +10 Set +15 Thema")
	assert_almost(WSchau.stil([], false, false, 1.1), 0.0, 1e-6, "Mult ohne Punkte = 0")
	assert_true(WSchau.kuer_treffer(-300.0))
	assert_false(WSchau.kuer_treffer(301.0))
	assert_almost(WSchau.kuer(5), 100.0, 1e-6, "5 Treffer à 20 P")
	assert_almost(WSchau.gesamt(100.0, 100.0, 100.0), 100.0)
	assert_almost(WSchau.gesamt(70.0, 59.0, 60.0), 63.7, 1e-6, "Doc-Gewichte 0,4/0,3/0,3")
	assert_eq(WSchau.KOMMANDOS.size(), 5, "5 Kür-Kommandos")


## Nr. 7 Tonnenrennen: Zeit + 5 s je umgeworfener Tonne; Ideal 24→17 s.
func test_tonnen_doc_formel() -> void:
	assert_almost(WTonnen.wertung_s(20.0, 0), 20.0)
	assert_almost(WTonnen.wertung_s(20.0, 1), 25.0, 1e-6, "Tonne = +5 s")
	assert_almost(WTonnen.idealzeit("holz"), 24.0, 1e-6, "Doc: 24 s Holz")
	assert_almost(WTonnen.idealzeit("sternenklasse"), 17.0, 1e-6, "Doc: 17 s Sternenklasse")
	assert_eq(WTonnen.sterne(24.0, 24.0), 3)
	assert_eq(WTonnen.sterne(27.59, 24.0), 2)
	assert_eq(WTonnen.sterne(32.39, 24.0), 1)
	assert_eq(WTonnen.sterne(33.0, 24.0), 0)
	assert_eq(WTonnen.TONNEN_ANZAHL, 3, "Kleeblatt um 3 Tonnen")
