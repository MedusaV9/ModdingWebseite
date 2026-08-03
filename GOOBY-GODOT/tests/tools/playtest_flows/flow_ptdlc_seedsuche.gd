extends SceneTree
## PT-DLC Seed-Suche (W18/R3, G8) — OFFLINE-Werkzeug, KEIN Harness-Flow:
## sucht die festen Seeds + Goldwerte, mit denen die flow_ptdlc_*-Flows
## deterministisch spielen (McGooby-Probeschicht + Voll-Plan, Goobye-
## Markttage für Preis-Schieber- und Backstation/Alwin-Flows). Nutzt die
## ECHTEN Spiel-Statics (McGoobySchichtPlan, GoobyeMarkttag, …) — gleiche
## Wahrheit wie das Spiel, null Nachbau-Drift.
##
## Aufruf (headless, unter flock wie alle Godot-Läufe):
##   flock -w 7200 /tmp/gooby_godot_global.lock \
##     tools/ci/run_godot_isolated.sh godot --path GOOBY-GODOT --headless \
##     --script res://tests/tools/playtest_flows/flow_ptdlc_seedsuche.gd
##
## Ausgabe: [SEEDSUCHE]-Zeilen mit Seed-Entscheidungen und Goldwerten —
## die Flows tragen die Zahlen als Konstanten + Kommentar mit Fundstelle.

## Laden-Kundenstrom (GoobyeLadenScene.KUNDEN_MIN/MAX, Welle A: 2–3).
const LADEN_KUNDEN_MIN := 2
const LADEN_KUNDEN_MAX := 3

## Startlager-Slots der Flows (b)/(d): apple 6, carrot 8, bread 5 (+Ofen).
const SHELF_B := [["apple", 6], ["carrot", 8], ["bread", 5]]
const SHELF_D := [["apple", 6], ["carrot", 8], ["bread", 8]]


func _initialize() -> void:
	print("[SEEDSUCHE] Start — Spiel-Statics geladen")
	_mcgooby_suchen()
	_flow_b_suchen()
	_flow_d_suchen()
	_flow_a_suchen()
	print("[SEEDSUCHE] fertig")
	quit(0)


## ------------------------------------------------------------- McGooby (c)


## Sucht S: Probeschicht (Seed S) kurz (2 Bestellungen, ≤ 3 Pattys) UND
## Voll-Plan (Seed S+1, nach Kauf ist _runde == 1) mit Grill-Tap,
## Fritteuse-MIT-Salz und Getränke-Zapfen in ≤ 8 Aufgaben.
func _mcgooby_suchen() -> void:
	var grill_menu := McGoobyKatalog.rezepte_fuer("grill")
	var voll_menu := McGoobyKatalog.rezepte_interaktiv()
	var bal := McGoobyKatalog.balance()
	for s in range(20260900, 20265900):
		var trial := McGoobySchichtLogic.bestell_folge(s, grill_menu, bal)
		if trial.size() != 2:
			continue
		var trial_patties := 0
		for bestellung: Dictionary in trial:
			trial_patties += int(bestellung.get("patties", 1))
		if trial_patties > 3:
			continue
		var voll := McGoobySchichtPlan.plan(s + 1, voll_menu, bal)
		if voll.size() != 3:
			continue
		if not _voll_plan_passt(voll):
			continue
		_mcgooby_drucken(s, trial, voll, bal)
		return
	print("[SEEDSUCHE] MCGOOBY: KEIN Seed gefunden!")


func _voll_plan_passt(voll: Array[Dictionary]) -> bool:
	var grill := 0
	var fritteuse_salz := 0
	var getraenke := 0
	var gesamt := 0
	for bestellung: Dictionary in voll:
		for position: Dictionary in bestellung.get("positionen", []):
			for aufgabe: Dictionary in position.get("aufgaben", []):
				gesamt += 1
				match str(aufgabe.get("station", "")):
					"grill":
						grill += 1
					"fritteuse":
						if bool(aufgabe.get("salz", false)):
							fritteuse_salz += 1
					"getraenke":
						getraenke += 1
	return grill >= 1 and fritteuse_salz >= 1 and getraenke >= 1 and gesamt <= 8


func _mcgooby_drucken(s: int, trial: Array[Dictionary], voll: Array[Dictionary], bal) -> void:
	print("[SEEDSUCHE] MCGOOBY Seed=%d (Probeschicht) / %d (Voll-Plan)" % [s, s + 1])
	for bestellung: Dictionary in trial:
		print(
			(
				"[SEEDSUCHE]   Probe-Bestellung %d: %s x%d Patty"
				% [
					int(bestellung.get("nr", 0)),
					str(bestellung.get("rezept_id", "?")),
					int(bestellung.get("patties", 1)),
				]
			)
		)
	var golden_erg: Array[Dictionary] = []
	for bestellung: Dictionary in voll:
		var zeile := "[SEEDSUCHE]   Voll-Bestellung %d:" % int(bestellung.get("nr", 0))
		var punkte := 0
		for position: Dictionary in bestellung.get("positionen", []):
			zeile += " %s(" % str(position.get("rezept_id", "?"))
			for aufgabe: Dictionary in position.get("aufgaben", []):
				var rezept := McGoobyKatalog.rezept(str(position.get("rezept_id", "")))
				var timing := McGoobySchichtPlan.timing_fuer(aufgabe, rezept)
				zeile += (
					" %s/%s%s%s[gar %.2f fenster %.2f]"
					% [
						str(aufgabe.get("station", "?")),
						str(aufgabe.get("art", "?")),
						"+SALZ" if bool(aufgabe.get("salz", false)) else "",
						(
							"+becher:" + str(aufgabe.get("becher", ""))
							if str(aufgabe.get("becher", "")) != ""
							else ""
						),
						float(timing.get("gar_sec", 0.0)),
						float(timing.get("fenster_sec", 0.0)),
					]
				)
				punkte += int(bal.get("punkte_perfekt", 10))
				if bool(aufgabe.get("salz", false)):
					punkte += int(bal.get("punkte_salz", 4))
			zeile += " )"
		punkte += int(bal.get("bestellung_fertig_bonus", 15))
		golden_erg.append({"punkte": punkte, "fehlerfrei": true})
		print(zeile + " -> Bestell-Punkte perfekt: %d" % punkte)
	var buehne := maxi(0, int(bal.get("buehne_trinkgeld", 6)))
	var kasse := McGoobyAbrechnung.abrechnung(golden_erg, bal, buehne)
	print("[SEEDSUCHE]   GOLDEN alles-perfekt + Buehne: %s" % str(kasse))


## ------------------------------------------------------------ Goobye (b)


## Sucht S_B: Trend == gemuese, Tag 1 (Standardpreise) verkauft mehr
## Möhren als Tag 2 (gemuese +30 %) — GLEICHER Seed, gleiche Lose, nur
## der Schieber unterscheidet die Tage (sauberer Monotonie-Beleg).
func _flow_b_suchen() -> void:
	for s in range(1, 250000):
		if GoobyeMarkttag.tagestrend(s) != "gemuese":
			continue
		if GoobyeMarkttag.alwin_menge(s) != 1:
			continue
		var plan1 := GoobyeMarkttag.tag_planen(s, _zeilen(SHELF_B, {}), _optionen(s, ""))
		if int(plan1.get("kundenzahl", 0)) != 3:
			continue
		var v1: Dictionary = plan1.get("verkauft", {})
		var rest := _rest_nach(SHELF_B, v1)
		if int(rest.get("carrot", 0)) < 3:
			continue
		var faktoren := {"carrot": 1.3}
		var plan2 := GoobyeMarkttag.tag_planen(s, _zeilen_rest(rest, faktoren), _optionen(s, ""))
		var v2: Dictionary = plan2.get("verkauft", {})
		if int(v2.get("carrot", 0)) >= int(v1.get("carrot", 0)):
			continue
		if int(v1.get("carrot", 0)) < 3:
			continue
		print("[SEEDSUCHE] FLOW-B Seed=%d (Trend gemuese, 3 Kunden)" % s)
		_tag_drucken("b-Tag1 (Standard)", plan1)
		_tag_drucken("b-Tag2 (gemuese 1.3)", plan2)
		print("[SEEDSUCHE]   Rest nach Tag1: %s" % str(rest))
		return
	print("[SEEDSUCHE] FLOW-B: KEIN Seed gefunden!")


## ------------------------------------------------------------ Goobye (d)


## Sucht A/B/C für die Backstation-Story: A normal (wenig Möhren-Bedarf),
## B Sonderwunsch-Tag (2 Möhren) MIT messbarem Duft-Unterschied bei
## Backwaren +30 %, C normaler Streak-Belohnungs-Tag. Duft ist an ALLEN
## Tagen aktiv (Ofen-Tagesdeckel hängt am ECHTEN Datum, nicht am
## Feierabend — im selben Lauf bleibt der Duft an).
func _flow_d_suchen() -> void:
	var seed_a := _suche_a()
	if seed_a == 0:
		print("[SEEDSUCHE] FLOW-D: kein Tag-A-Seed!")
		return
	var plan_a := GoobyeMarkttag.tag_planen(
		seed_a, _zeilen(SHELF_D, {}), _optionen(seed_a, "backwaren")
	)
	var rest_a := _rest_nach(SHELF_D, plan_a.get("verkauft", {}))
	# Morgen Tag 2: 3. Ofen-Charge (+3 Brot ins Lager), Slot-2-Nachfüllung
	# auf 8 (Lager-Brot reicht: 5 + 6 − 8 + 3 ≥ Bedarf, s. Flow-Kommentar).
	var shelf_b := {
		"apple": int(rest_a.get("apple", 0)),
		"carrot": int(rest_a.get("carrot", 0)),
		"bread": 8,
	}
	var seed_b := _suche_b(shelf_b)
	if seed_b == 0:
		print("[SEEDSUCHE] FLOW-D: kein Tag-B-Seed!")
		return
	var faktoren := {"bread": 1.3}
	var plan_b := GoobyeMarkttag.tag_planen(
		seed_b, _zeilen_rest(shelf_b, faktoren), _optionen(seed_b, "backwaren", 2)
	)
	var rest_b := _rest_nach_dict(shelf_b, plan_b.get("verkauft", {}))
	var seed_c := _suche_c(rest_b)
	var plan_c := GoobyeMarkttag.tag_planen(
		seed_c, _zeilen_rest(rest_b, faktoren), _optionen(seed_c, "backwaren")
	)
	print("[SEEDSUCHE] FLOW-D Seeds A=%d B=%d C=%d" % [seed_a, seed_b, seed_c])
	_tag_drucken("d-Tag1 (A, Duft an)", plan_a)
	print("[SEEDSUCHE]   Rest nach Tag1: %s" % str(rest_a))
	_tag_drucken("d-Tag2 (B, Sonderwunsch, backwaren 1.3)", plan_b)
	print("[SEEDSUCHE]   Regal Tag2: %s — Rest: %s" % [str(shelf_b), str(rest_b)])
	var ohne_duft := GoobyeMarkttag.tag_planen(
		seed_b, _zeilen_rest(shelf_b, faktoren), _optionen(seed_b, "", 2)
	)
	print(
		(
			"[SEEDSUCHE]   Duft-Messung Tag2: MIT %d vs OHNE %d Umsatz"
			% [int(plan_b.get("umsatz", 0)), int(ohne_duft.get("umsatz", 0))]
		)
	)
	_tag_drucken("d-Tag3 (C, Streak-Belohnung)", plan_c)


func _suche_a() -> int:
	for s in range(2, 250000):
		if GoobyeMarkttag.alwin_menge(s) != 1:
			continue
		var plan := GoobyeMarkttag.tag_planen(s, _zeilen(SHELF_D, {}), _optionen(s, "backwaren"))
		if int(plan.get("kundenzahl", 0)) != 3:
			continue
		var v: Dictionary = plan.get("verkauft", {})
		if int(v.get("carrot", 0)) > 3 or int(v.get("carrot", 0)) < 1:
			continue
		if int(v.get("bread", 0)) < 1:
			continue
		if int(plan.get("umsatz", 0)) <= 0:
			continue
		return s
	return 0


## Tag B: Sonderwunsch (posmod 5 == 0) + Duft macht bei Backwaren 1.3
## einen MESSBAREN Umsatz-Unterschied + Möhren reichen für 2 + Rest.
func _suche_b(shelf: Dictionary) -> int:
	var faktoren := {"bread": 1.3}
	for s in range(5, 250000, 5):
		if GoobyeMarkttag.alwin_menge(s) != 2:
			continue
		if int(shelf.get("carrot", 0)) < 3:
			return 0
		var mit := GoobyeMarkttag.tag_planen(
			s, _zeilen_rest(shelf, faktoren), _optionen(s, "backwaren", 2)
		)
		var ohne := GoobyeMarkttag.tag_planen(s, _zeilen_rest(shelf, faktoren), _optionen(s, "", 2))
		if int(mit.get("umsatz", 0)) <= int(ohne.get("umsatz", 0)):
			continue
		var v: Dictionary = mit.get("verkauft", {})
		if int(v.get("carrot", 0)) < 2:
			continue
		if int(shelf.get("carrot", 0)) - int(v.get("carrot", 0)) < 1:
			continue
		return s
	return 0


func _suche_c(shelf: Dictionary) -> int:
	var faktoren := {"bread": 1.3}
	for s in range(3, 250000):
		if GoobyeMarkttag.alwin_menge(s) != 1:
			continue
		if posmod(s, 5) == 0:
			continue
		var plan := GoobyeMarkttag.tag_planen(
			s, _zeilen_rest(shelf, faktoren), _optionen(s, "backwaren")
		)
		var v: Dictionary = plan.get("verkauft", {})
		if int(v.get("carrot", 0)) < 1:
			continue
		return s
	return 0


## ------------------------------------------------------------ Goobye (a)


## Flow (a) prüft den Markttag zur Laufzeit nach (Sortiment hängt vom
## Rampen-Tagesangebot ab) — hier nur ein Seed mit 3 Kunden inkl.
## Hamster-Gooby (Schau-Wert) und Alwin-Menge 1.
func _flow_a_suchen() -> void:
	var shelf := [["apple", 8], ["carrot", 8], ["bread", 15], ["cookie", 5]]
	for s in range(4, 250000):
		if GoobyeMarkttag.alwin_menge(s) != 1:
			continue
		var plan := GoobyeMarkttag.tag_planen(s, _zeilen(shelf, {}), _optionen(s, ""))
		if int(plan.get("kundenzahl", 0)) != 3:
			continue
		var hamster := false
		for bon: Dictionary in plan.get("bons", []):
			if str(bon.get("archetyp", "")) == GoobyeMarkttag.ARCHETYP_HAMSTER:
				hamster = true
		if not hamster:
			continue
		print("[SEEDSUCHE] FLOW-A Seed=%d (3 Kunden, mit Hamster)" % s)
		_tag_drucken("a-Markttag (Beispiel-Regal)", plan)
		return
	print("[SEEDSUCHE] FLOW-A: KEIN Seed gefunden!")


## ---------------------------------------------------------------- Helfer


func _optionen(seed_wert: int, duft: String, alwin := 0) -> Dictionary:
	return {
		"kunden_min": LADEN_KUNDEN_MIN,
		"kunden_max": LADEN_KUNDEN_MAX,
		"trend_gruppe": GoobyeMarkttag.tagestrend(seed_wert),
		"duft_gruppe": duft,
		"alwin_menge": alwin if alwin > 0 else GoobyeMarkttag.alwin_menge(seed_wert),
	}


func _zeilen(shelf: Array, faktoren: Dictionary) -> Array:
	var out: Array = []
	for paar: Array in shelf:
		var id := str(paar[0])
		out.append({"id": id, "bestand": int(paar[1]), "faktor": float(faktoren.get(id, 1.0))})
	return out


func _zeilen_rest(rest: Dictionary, faktoren: Dictionary) -> Array:
	var out: Array = []
	for id: Variant in rest:
		if int(rest[id]) <= 0:
			continue
		(
			out
			. append(
				{
					"id": str(id),
					"bestand": int(rest[id]),
					"faktor": float(faktoren.get(str(id), 1.0)),
				}
			)
		)
	return out


func _rest_nach(shelf: Array, verkauft: Dictionary) -> Dictionary:
	var rest: Dictionary = {}
	for paar: Array in shelf:
		rest[str(paar[0])] = int(paar[1]) - int(verkauft.get(str(paar[0]), 0))
	return rest


func _rest_nach_dict(shelf: Dictionary, verkauft: Dictionary) -> Dictionary:
	var rest: Dictionary = {}
	for id: Variant in shelf:
		rest[str(id)] = int(shelf[id]) - int(verkauft.get(str(id), 0))
	return rest


func _tag_drucken(titel: String, plan: Dictionary) -> void:
	var archetypen: Array[String] = []
	for bon: Dictionary in plan.get("bons", []):
		archetypen.append(
			(
				"%s(%d Pos)"
				% [str(bon.get("archetyp", "?")), (bon.get("positionen", []) as Array).size()]
			)
		)
	print(
		(
			"[SEEDSUCHE]   %s: Kunden %d [%s], Umsatz %d, verkauft %s, verpasst %d"
			% [
				titel,
				int(plan.get("kundenzahl", 0)),
				", ".join(archetypen),
				int(plan.get("umsatz", 0)),
				str(plan.get("verkauft", {})),
				int(plan.get("verpasst", 0)),
			]
		)
	)
