class_name GoobyeMarkttag
extends RefCounted
## Deterministischer Markttag des „Goo und Bye“ (G5/P24, Doc §6.1/§10.4) —
## PURE + static, ohne GameState, ohne Uhr, ohne Nodes: (Seed, Sortiment,
## Preis-Faktoren) → kompletter Tagesplan mit Kundenstrom und Bon-Liste.
## Gleicher Seed + gleiches Sortiment = EXAKT derselbe Plan — das ist der
## QA-Jackpot (Golden-Tests) und später die Basis für Offline-Kasse und
## Freunde-Sync.
##
## Determinismus-Bauart (Muster MarktSim): die komplette Zufallsfolge wird
## VORAB gezogen — pro Kunde ein fester Block von Losen, unabhängig von
## Preisen und Beständen. Preis-Schieber verändern nur noch VERGLEICHE
## (Griff-Chance), nie die Zufallsfolge; Bestände begrenzen nur, was im Bon
## landet. Billiger ⇒ nie weniger Absatz (Monotonie, beweisbar).
##
## Welle A: 3 Archetypen mit Gag-Vertrag (§6.3) + Familien-Kunde:
##   alwin          — täglich der ERSTE Kunde, kauft GENAU 1 Möhre
##   listen_gooby   — strikte Einkaufsliste (2–6 Artikel, distinct)
##   familie        — 1–4 Artikel + Quengelware aus dem Süß-Regal (§3.3)
##   hamster_gooby  — kauft von EINER Ware den (gedeckelten) Rest-Bestand
##
## Welle B (G6/GOOBYE-B): Tagestrend („Heute lieben alle …!“, §4.4), Duft
## der Backecke (§7.1) und Alwins Sonderwunsch-Gag („heute ZWEI Möhren?!“)
## kommen als OPTIONEN in tag_planen — sie verschieben nur VERGLEICHE
## (Griff-Chance) bzw. eine feste Stückzahl, NIE die Los-Folge. Ohne
## Optionen bleibt der Plan byte-identisch zu Welle A (Golden-Verträge).

const ARCHETYP_ALWIN := "alwin"
const ARCHETYP_LISTE := "listen_gooby"
const ARCHETYP_FAMILIE := "familie"
const ARCHETYP_HAMSTER := "hamster_gooby"

## Öffnungszeit 8–20 Uhr (§2.2) als Minutenachse 0..720; Alwin kommt 9 Uhr.
const TAG_MINUTEN := 720
const ALWIN_MINUTE := 60
const ALWIN_WARE := "carrot"

## Kundenstrom Welle A (Laden-Level 1 „klein, aber meins“).
const KUNDEN_MIN := 3
const KUNDEN_MAX := 5

## Feste Los-Block-Größe pro Kunde: [archetyp, jitter, anzahl] + 8 Paare
## (index, griff) — Positionen sind auf 8 gedeckelt (§6.1: 1–8 Artikel).
const MAX_POSITIONEN := 8

## Hamster-Deckel (damit ein Hamster nicht den ganzen Tag leerkauft).
const HAMSTER_MAX := 4

## Quengelware-Grundchance an der Kasse (§3.3 — 1 bleibt IMMER drin).
const QUENGEL_CHANCE := 0.6

## Welle-B-Boni auf die Griff-Chance (additiv, faktor-unabhängig — die
## Monotonie „billiger ⇒ nie weniger Absatz“ bleibt beweisbar).
const TREND_GRIFF_BONUS := 0.25
const DUFT_GRIFF_BONUS := 0.15

## Alwins Sonderwunsch-Takt: jeder n-te Tages-Seed ist ein
## „heute ZWEI Möhren?!“-Tag (§6.3-Gag, deterministisch).
const ALWIN_SONDERWUNSCH_JEDER := 5


## Stabiler Tages-Seed aus dem Tag-Key ("YYYY-MM-DD").
static func tages_seed(tag_key: String) -> int:
	return tag_key.hash()


## Tagestrend („Heute lieben alle {Gruppe}!“, §4.4): deterministisch über
## den Tages-Seed aus den Katalog-Gruppen gewählt — dieselbe Wahrheit für
## Preis-Sheet, Kassensturz und Sim ("" nur ohne Katalog).
static func tagestrend(seed_wert: int) -> String:
	var gruppen := GoobyeKatalog.gruppen()
	if gruppen.is_empty():
		return ""
	return str((gruppen[posmod(seed_wert, gruppen.size())] as Dictionary).get("id", ""))


## Alwins Möhren-Menge des Tages: GENAU 1 — außer am Sonderwunsch-Tag,
## dann GENAU 2 („Man lebt nur einmal.“). Pure Seed-Funktion, kein Los.
static func alwin_menge(seed_wert: int) -> int:
	return 2 if posmod(seed_wert, ALWIN_SONDERWUNSCH_JEDER) == 0 else 1


## Der ganze Markttag. `sortiment` = gelistete Regal-Zeilen
## [{id, bestand, faktor?}], Waren-Daten kommen aus dem GoobyeKatalog.
## Optionen (Welle B, alle optional — Default = Welle-A-Verhalten):
##   trend_gruppe ("Heute lieben alle …!"), duft_gruppe (Backecke-Duft),
##   alwin_menge (Sonderwunsch-Tag: 2), kunden_min/kunden_max.
## Ergebnis: {kundenzahl, bons[], umsatz, verkauft{}, verpasst}.
## Bon = {kunde, archetyp, minute, positionen: [{ware, preis, quengel?}], summe}.
static func tag_planen(seed_wert: int, sortiment: Array, optionen := {}) -> Dictionary:
	var zeilen := _gueltige_zeilen(sortiment)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var kundenzahl := rng.randi_range(
		int(optionen.get("kunden_min", KUNDEN_MIN)), int(optionen.get("kunden_max", KUNDEN_MAX))
	)
	var lose := _lose_ziehen(rng, kundenzahl)
	var bestand := _bestands_kopie(zeilen)
	var boni := {
		"trend": str(optionen.get("trend_gruppe", "")),
		"duft": str(optionen.get("duft_gruppe", "")),
		"alwin_menge": maxi(1, int(optionen.get("alwin_menge", 1))),
	}
	var bons: Array = []
	var verkauft: Dictionary = {}
	var verpasst := 0
	var umsatz := 0
	for i in kundenzahl:
		var bon := _kunde_einkaufen(i, kundenzahl, lose[i], zeilen, bestand, boni)
		verpasst += int(bon["verpasst"])
		bon.erase("verpasst")
		for position: Dictionary in bon["positionen"]:
			var ware_id := str(position["ware"])
			verkauft[ware_id] = int(verkauft.get(ware_id, 0)) + 1
			umsatz += int(position["preis"])
		bon["summe"] = _bon_summe(bon)
		bons.append(bon)
	return {
		"kundenzahl": kundenzahl,
		"bons": bons,
		"umsatz": umsatz,
		"verkauft": verkauft,
		"verpasst": verpasst,
	}


## Kassen-Melodie eines Bons (§1.2): pro Position die Gebrabbel-Tonhöhe der
## Warengruppe — die UI spielt sie als gepitchte ui_chip-Reihe.
static func melodie(bon: Dictionary) -> Array:
	var toene: Array = []
	for position: Dictionary in bon.get("positionen", []):
		toene.append(GoobyeKatalog.ton_fuer(str(position.get("ware", ""))))
	return toene


## ------------------------------------------------------------ Innenleben


## Nur Zeilen mit bekannter Katalog-Ware zählen (kaputte Ids fliegen raus).
static func _gueltige_zeilen(sortiment: Array) -> Array:
	var out: Array = []
	for zeile: Variant in sortiment:
		if not (zeile is Dictionary):
			continue
		var ware := GoobyeKatalog.ware(str((zeile as Dictionary).get("id", "")))
		if ware.is_empty():
			continue
		(
			out
			. append(
				{
					"id": str(zeile["id"]),
					"ware": ware,
					"bestand": maxi(0, int((zeile as Dictionary).get("bestand", 0))),
					"faktor": float((zeile as Dictionary).get("faktor", 1.0)),
				}
			)
		)
	return out


## Kompletten Los-Vorrat VORAB ziehen (fester Block pro Kunde) — Preise und
## Bestände dürfen die Zufallsfolge NIE beeinflussen (Monotonie-Beweis).
static func _lose_ziehen(rng: RandomNumberGenerator, kundenzahl: int) -> Array:
	var lose: Array = []
	for _i in kundenzahl:
		var block := {
			"archetyp": rng.randf(),
			"jitter": rng.randf(),
			"anzahl": rng.randf(),
			"quengel": rng.randf(),
			"positionen": []
		}
		for _p in MAX_POSITIONEN:
			block["positionen"].append([rng.randf(), rng.randf()])
		lose.append(block)
	return lose


static func _bestands_kopie(zeilen: Array) -> Dictionary:
	var bestand: Dictionary = {}
	for zeile: Dictionary in zeilen:
		bestand[str(zeile["id"])] = int(zeile["bestand"])
	return bestand


## Ein Kunde läuft seine Liste ab. Gibt den Bon inkl. `verpasst`-Zähler
## (leere Regal-Griffe — Nachfüll-Hinweis, keine Strafe) zurück.
static func _kunde_einkaufen(
	index: int, kundenzahl: int, lose: Dictionary, zeilen: Array, bestand: Dictionary, boni := {}
) -> Dictionary:
	var archetyp := _archetyp_fuer(index, float(lose["archetyp"]))
	var minute := _minute_fuer(index, kundenzahl, float(lose["jitter"]))
	var positionen: Array = []
	var verpasst := 0
	match archetyp:
		ARCHETYP_ALWIN:
			minute = ALWIN_MINUTE
			for _n in maxi(1, int(boni.get("alwin_menge", 1))):
				verpasst += _greife(ALWIN_WARE, zeilen, bestand, 0.0, positionen)
		ARCHETYP_HAMSTER:
			verpasst += _hamster_einkauf(lose, zeilen, bestand, positionen)
		_:
			verpasst += _listen_einkauf(archetyp, lose, zeilen, bestand, positionen, boni)
	return {
		"kunde": index,
		"archetyp": archetyp,
		"minute": minute,
		"positionen": positionen,
		"verpasst": verpasst,
	}


## Kunde 0 ist IMMER Alwin (Gag-Vertrag §6.3), danach würfelt das Los.
static func _archetyp_fuer(index: int, los: float) -> String:
	if index == 0:
		return ARCHETYP_ALWIN
	if los < 0.45:
		return ARCHETYP_LISTE
	if los < 0.85:
		return ARCHETYP_FAMILIE
	return ARCHETYP_HAMSTER


static func _minute_fuer(index: int, kundenzahl: int, jitter: float) -> int:
	var roh := (float(index) + jitter) * float(TAG_MINUTEN) / float(maxi(1, kundenzahl))
	return clampi(int(roh), 0, TAG_MINUTEN - 1)


## Listen-/Familien-Einkauf: distinct Wunschliste, Griff-Los je Position,
## Familie greift an der Kasse zusätzlich zur Quengelware (§3.3).
static func _listen_einkauf(
	archetyp: String,
	lose: Dictionary,
	zeilen: Array,
	bestand: Dictionary,
	positionen: Array,
	boni := {}
) -> int:
	if zeilen.is_empty():
		return 1
	var deckel := 6 if archetyp == ARCHETYP_LISTE else 4
	var minimum := 2 if archetyp == ARCHETYP_LISTE else 1
	var maximal := mini(deckel, zeilen.size())
	var anzahl := clampi(
		minimum + int(float(lose["anzahl"]) * float(maximal)), minimum, maxi(minimum, maximal)
	)
	var verpasst := 0
	var gewaehlt: Array = []
	for p in anzahl:
		var paar: Array = lose["positionen"][p]
		var idx := _distinct_index(float(paar[0]), zeilen.size(), gewaehlt)
		if idx < 0:
			break
		gewaehlt.append(idx)
		var zeile: Dictionary = zeilen[idx]
		var chance := GoobyePreis.griff_chance(float(zeile["faktor"]))
		chance += GoobyePreis.spontan_bonus(float(zeile["faktor"]))
		chance += _gruppen_bonus(zeile, boni)
		if float(paar[1]) < chance:
			verpasst += _greife(str(zeile["id"]), zeilen, bestand, 0.0, positionen)
	if archetyp == ARCHETYP_FAMILIE:
		verpasst += _quengelware(lose, zeilen, bestand, positionen)
	return verpasst


## Welle-B-Boni (Trend §4.4, Backecken-Duft §7.1) auf die Griff-Chance der
## Warengruppe — faktor-unabhängig, damit die Monotonie hält.
static func _gruppen_bonus(zeile: Dictionary, boni: Dictionary) -> float:
	if boni.is_empty():
		return 0.0
	var gruppe := str((zeile.get("ware", {}) as Dictionary).get("gruppe", ""))
	if gruppe.is_empty():
		return 0.0
	var bonus := 0.0
	if gruppe == str(boni.get("trend", "")):
		bonus += TREND_GRIFF_BONUS
	if gruppe == str(boni.get("duft", "")):
		bonus += DUFT_GRIFF_BONUS
	return bonus


## Hamster kauft von EINER Ware den Rest-Bestand (gedeckelt) leer (§6.3).
static func _hamster_einkauf(
	lose: Dictionary, zeilen: Array, bestand: Dictionary, positionen: Array
) -> int:
	if zeilen.is_empty():
		return 1
	var paar: Array = lose["positionen"][0]
	var idx := clampi(int(float(paar[0]) * float(zeilen.size())), 0, zeilen.size() - 1)
	var zeile: Dictionary = zeilen[idx]
	var id := str(zeile["id"])
	var menge := mini(HAMSTER_MAX, int(bestand.get(id, 0)))
	if menge <= 0:
		return 1
	var verpasst := 0
	for _n in menge:
		verpasst += _greife(id, zeilen, bestand, 0.0, positionen)
	return verpasst


## Quengelware: das günstigste gelistete Süß-Regal-Stück wandert mit der
## Quengel-Chance (+Spontankauf-Bonus) zusätzlich in den Wagen.
static func _quengelware(
	lose: Dictionary, zeilen: Array, bestand: Dictionary, positionen: Array
) -> int:
	var beste: Dictionary = {}
	var bester_preis := 0
	for zeile: Dictionary in zeilen:
		if str((zeile["ware"] as Dictionary).get("gruppe", "")) != "suesses":
			continue
		var preis := GoobyePreis.verkaufspreis(zeile["ware"], float(zeile["faktor"]))
		if beste.is_empty() or preis < bester_preis:
			beste = zeile
			bester_preis = preis
	if beste.is_empty():
		return 0
	var chance := QUENGEL_CHANCE + GoobyePreis.spontan_bonus(float(beste["faktor"]))
	if float(lose["quengel"]) >= chance:
		return 0
	var vorher := positionen.size()
	var verpasst := _greife(str(beste["id"]), zeilen, bestand, 0.0, positionen)
	if positionen.size() > vorher:
		positionen[positionen.size() - 1]["quengel"] = true
	return verpasst


## Einen Artikel aus dem Regal nehmen: Bestand runter + Bon-Position, sonst
## `1` verpasster Griff (trauriges Häkchen — Nachfüll-Kompass, §6.3).
static func _greife(
	ware_id: String, zeilen: Array, bestand: Dictionary, _reserve: float, positionen: Array
) -> int:
	var zeile := _zeile_von(zeilen, ware_id)
	if zeile.is_empty() or int(bestand.get(ware_id, 0)) <= 0:
		return 1
	bestand[ware_id] = int(bestand[ware_id]) - 1
	(
		positionen
		. append(
			{
				"ware": ware_id,
				"preis": GoobyePreis.verkaufspreis(zeile["ware"], float(zeile["faktor"])),
			}
		)
	)
	return 0


static func _zeile_von(zeilen: Array, ware_id: String) -> Dictionary:
	for zeile: Dictionary in zeilen:
		if str(zeile["id"]) == ware_id:
			return zeile
	return {}


## Distinct-Index aus einem Los: bei Kollision deterministisch weiterrücken
## (modulo), −1 wenn alles schon gewählt ist.
static func _distinct_index(los: float, groesse: int, gewaehlt: Array) -> int:
	if gewaehlt.size() >= groesse:
		return -1
	var idx := clampi(int(los * float(groesse)), 0, groesse - 1)
	for _schritt in groesse:
		if not gewaehlt.has(idx):
			return idx
		idx = (idx + 1) % groesse
	return -1


static func _bon_summe(bon: Dictionary) -> int:
	var summe := 0
	for position: Dictionary in bon["positionen"]:
		summe += int(position["preis"])
	return summe
