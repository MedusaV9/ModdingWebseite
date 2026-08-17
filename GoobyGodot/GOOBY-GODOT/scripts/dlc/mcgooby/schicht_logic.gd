class_name McGoobySchichtLogic
extends RefCounted
## Pure Schicht-Logik des McGooby-DLC (Welle A, Doc §2.2/§4.1): Seed →
## deterministische Bestell-Folge → Timing-Fenster-Bewertung pro Schritt →
## Bot-Zertifizierung. Keine Nodes, keine Autoloads — golden-testbar wie
## `burger_build_logic.gd`. Zahlen kommen IMMER aus dem Balance-Block des
## Menü-Packs (McGoobyKatalog.balance()), nie aus Konstanten hier.
##
## Timing-Modell Grill (Doc §2.2 #1, 3 Zustände): 0..gar_sec = roh →
## gar_sec..gar_sec+fenster_sec = goldbraun (das goldene Fenster, Tap =
## „Perfekt!“) → danach „uups, Kohle-Style“. Zu spät ist NIE verloren:
## der Kohle-Patty wird zum „Röstaroma-Spezial“ mit halben Punkten.

const WERTUNG_ROH := "roh"
const WERTUNG_PERFEKT := "perfekt"
const WERTUNG_ROESTAROMA := "roestaroma"

const ZUSTAND_ROH := "roh"
const ZUSTAND_GOLDBRAUN := "goldbraun"
const ZUSTAND_KOHLE := "kohle"


## Deterministische Bestell-Folge (Doc §4.1: gleicher Seed = gleicher
## Kundenstrom). menu = McGoobyKatalog.rezepte() — seit Welle C ziehen die
## Bestellungen aus ALLEN Stationen. Faire Mischung: Bestellung 1 ist
## IMMER ein Signature-Burger (Grill+Belegen — der erste Kunde des Tages
## will den Klassiker), Bestellung 2 kommt IMMER vom neuen Tresen
## (Fritteuse/Shake), ab Bestellung 3 zieht der volle Zufall — so hat
## JEDE Schicht garantiert Burger UND neue Stationen. Leere Gruppen
## (z. B. Grill-only-Menü der Welle-A-Goldens) fallen aufs volle Menü
## zurück; der RNG-Verbrauch (1 Wurf Anzahl + 1 Wurf pro Bestellung)
## bleibt dabei exakt der alte.
## Rückgabe: [{nr, rezept_id, patties}] — patties = Grill-Schritte des Rezepts.
static func bestell_folge(seed_wert: int, menu: Array, bal: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if menu.is_empty():
		return out
	var rng := GoobyRng.new(seed_wert)
	var lo := maxi(1, int(bal.get("bestellungen_min", 2)))
	var hi := maxi(lo, int(bal.get("bestellungen_max", 4)))
	var anzahl := lo + int(floor(rng.next() * float(hi - lo + 1)))
	var burger := rezepte_mit_station(menu, "grill")
	var tresen := rezepte_ohne_station(menu, "grill")
	for i in anzahl:
		var topf := menu
		if i == 0 and not burger.is_empty():
			topf = burger
		elif i == 1 and not tresen.is_empty():
			topf = tresen
		var idx := mini(topf.size() - 1, int(floor(rng.next() * float(topf.size()))))
		var rezept_def: Dictionary = topf[idx]
		(
			out
			. append(
				{
					"nr": i + 1,
					"rezept_id": str(rezept_def.get("id", "")),
					"patties": grill_schritte(rezept_def),
				}
			)
		)
	return out


## Teilmenü: Rezepte MIT einer Station (Menü-Reihenfolge bleibt erhalten).
static func rezepte_mit_station(menu: Array, station: String) -> Array:
	var out: Array = []
	for kandidat: Variant in menu:
		if not (kandidat is Dictionary):
			continue
		var stationen: Variant = (kandidat as Dictionary).get("stationen", [])
		if stationen is Array and (stationen as Array).has(station):
			out.append(kandidat)
	return out


## Teilmenü: Rezepte OHNE eine Station (der „neue Tresen“ = alles ohne Grill).
static func rezepte_ohne_station(menu: Array, station: String) -> Array:
	var out: Array = []
	for kandidat: Variant in menu:
		if not (kandidat is Dictionary):
			continue
		var stationen: Variant = (kandidat as Dictionary).get("stationen", [])
		if not (stationen is Array) or not (stationen as Array).has(station):
			out.append(kandidat)
	return out


## Stations-Phasen einer Bestellung in Arbeits-Reihenfolge (Welle C):
## exakt das `stationen`-Feld des Rezepts (["grill", "belegen"],
## ["fritteuse"], …) — Szene und Bot laufen denselben Plan.
static func phasen_von(rezept_def: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for station: Variant in rezept_def.get("stationen", []):
		out.append(str(station))
	return out


## Anzahl der Grill-Aktionen eines Rezepts (Summe der `anzahl`-Felder der
## Schritte an der Station grill; mindestens 1, sobald Grill dabei ist —
## Rezepte OHNE Grill-Station liefern 0, Welle C).
static func grill_schritte(rezept_def: Dictionary) -> int:
	var stationen: Variant = rezept_def.get("stationen", [])
	if not (stationen is Array) or not (stationen as Array).has("grill"):
		return 0
	var summe := 0
	for schritt: Variant in rezept_def.get("schritte", []):
		if schritt is Dictionary and str((schritt as Dictionary).get("station", "")) == "grill":
			summe += maxi(1, int((schritt as Dictionary).get("anzahl", 1)))
	return maxi(1, summe)


## Patty-Zustand zum Zeitpunkt t (Sekunden seit Auflegen).
static func zustand(t_sec: float, timing: Dictionary) -> String:
	var gar := float(timing.get("gar_sec", 4.0))
	if t_sec < gar:
		return ZUSTAND_ROH
	if t_sec < gar + float(timing.get("fenster_sec", 1.4)):
		return ZUSTAND_GOLDBRAUN
	return ZUSTAND_KOHLE


## Brat-Fortschritt 0..1 fürs Visuelle (1.0 = Ende des goldenen Fensters).
static func fortschritt(t_sec: float, timing: Dictionary) -> float:
	var ende := float(timing.get("gar_sec", 4.0)) + float(timing.get("fenster_sec", 1.4))
	if ende <= 0.0:
		return 1.0
	return clampf(t_sec / ende, 0.0, 1.0)


## „Perfekt!“-Fenster-Bewertung eines Taps (Doc §2.2): im goldenen Fenster =
## volle Punkte, danach Röstaroma-Spezial = halbe Punkte, davor passiert
## NICHTS (roh, 0 Punkte — der Patty brät weiter, keine Strafe).
static func bewerte_tap(t_sec: float, timing: Dictionary, bal: Dictionary) -> Dictionary:
	match zustand(t_sec, timing):
		ZUSTAND_ROH:
			return {"wertung": WERTUNG_ROH, "punkte": 0}
		ZUSTAND_GOLDBRAUN:
			return {"wertung": WERTUNG_PERFEKT, "punkte": int(bal.get("punkte_perfekt", 10))}
		_:
			return {"wertung": WERTUNG_ROESTAROMA, "punkte": int(bal.get("punkte_roestaroma", 5))}


## Liegengelassene Pattys werten wie ein später Tap (Röstaroma, halbe Punkte).
static func bewerte_liegengelassen(bal: Dictionary) -> Dictionary:
	return {"wertung": WERTUNG_ROESTAROMA, "punkte": int(bal.get("punkte_roestaroma", 5))}


## ---- Timing-Runden-Dispatch (Welle C): EINE Anlaufstelle der Szene für
## Grill/Fritteuse/Shake — der Grill wohnt hier, die neuen Stationen in
## ihren eigenen pure-Logik-Dateien (McGoobyStationFritteuse/…Shake).


## Zustand der Runde einer Station zum Zeitpunkt t.
static func runde_zustand(phase: String, t_sec: float, timing: Dictionary) -> String:
	match phase:
		"fritteuse":
			return McGoobyStationFritteuse.zustand(t_sec, timing)
		"shake":
			return McGoobyStationShake.zustand(t_sec, timing)
		_:
			return zustand(t_sec, timing)


## Tap/Loslassen/Stopp der Runde einer Station werten.
static func runde_bewerten(
	phase: String, t_sec: float, timing: Dictionary, bal: Dictionary
) -> Dictionary:
	match phase:
		"fritteuse":
			return McGoobyStationFritteuse.bewerte_zug(t_sec, timing, bal)
		"shake":
			return McGoobyStationShake.bewerte_stopp(t_sec, timing, bal)
		_:
			return bewerte_tap(t_sec, timing, bal)


## Vergessene/überdrehte Runde nach dem Nachlauf werten (halbe Punkte).
static func runde_vergessen(phase: String, bal: Dictionary) -> Dictionary:
	match phase:
		"fritteuse":
			return McGoobyStationFritteuse.bewerte_vergessen(bal)
		"shake":
			return McGoobyStationShake.bewerte_ueberdreht(bal)
		_:
			return bewerte_liegengelassen(bal)


## Fortschritt 0..1 der Runde einer Station fürs Visuelle.
static func runde_fortschritt(phase: String, t_sec: float, timing: Dictionary) -> float:
	match phase:
		"fritteuse":
			return McGoobyStationFritteuse.fortschritt(t_sec, timing)
		"shake":
			return McGoobyStationShake.fortschritt(t_sec, timing)
		_:
			return fortschritt(t_sec, timing)


## Rezept-Definition zu einer Bestellung aus dem übergebenen Menü ({} = weg).
static func rezept_aus_menu(menu: Array, rezept_id: String) -> Dictionary:
	for kandidat: Variant in menu:
		if kandidat is Dictionary and str((kandidat as Dictionary).get("id", "")) == rezept_id:
			return kandidat
	return {}


## Deterministische Bot-Zertifizierung (Doc §10.4): derselbe Seed erzeugt
## dieselbe Bestell-Folge UND dieselben Bot-Aktionen → exakte Goldwerte.
## Welle C: pro Bestellung laufen die Stations-Phasen des Rezepts in
## Arbeits-Reihenfolge (phasen_von) — Grill-Taps, Belegstation, Fritteuse,
## Shake-Bar, ALLE auf DEMSELBEN RNG-Strom (exakt die Spielreihenfolge der
## Szene; Rezepte ohne eine Station verbrauchen dort keine Würfe, die
## Welle-A/B-Goldens mit Grill-only-Menü bleiben gültig). menu wie
## bestell_folge; Rückgabe inkl. Abrechnung (McGoobyAbrechnung).
static func simulate_autoplay(seed_wert: int, menu: Array, bal: Dictionary) -> Dictionary:
	var folge := bestell_folge(seed_wert, menu, bal)
	# Eigener Bot-RNG-Strom, versetzt geseedet — unabhängig von der Folge.
	var rng := GoobyRng.new(seed_wert + 1)
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var ergebnisse: Array[Dictionary] = []
	var zaehler := {"perfekt": 0, "roestaroma": 0, "fehlgriffe": 0, "dunkel": 0, "schaum": 0}
	for bestellung: Dictionary in folge:
		var rezept_def := rezept_aus_menu(menu, str(bestellung["rezept_id"]))
		var runde := _bot_bestellung(rng, rezept_def, bestellung, bal, skill, zaehler)
		ergebnisse.append(runde)
	var kasse := McGoobyAbrechnung.abrechnung(ergebnisse, bal)
	return {
		"seed": seed_wert,
		"bestellungen": folge.size(),
		"perfekt": int(zaehler["perfekt"]),
		"roestaroma": int(zaehler["roestaroma"]),
		"fehlgriffe": int(zaehler["fehlgriffe"]),
		"dunkel": int(zaehler["dunkel"]),
		"schaum": int(zaehler["schaum"]),
		"punkte": int(kasse["punkte"]),
		"trinkgeld": int(kasse["trinkgeld"]),
		"muenzen": int(kasse["muenzen"]),
	}


## EINE Bot-Bestellung über alle Stations-Phasen des Rezepts (geteilter
## RNG-Strom, zaehler wird in-place fortgeschrieben). Rückgabe:
## {punkte, fehlerfrei} für die Abrechnung.
static func _bot_bestellung(
	rng: GoobyRng,
	rezept_def: Dictionary,
	bestellung: Dictionary,
	bal: Dictionary,
	skill: float,
	zaehler: Dictionary
) -> Dictionary:
	var punkte := 0
	var fehlerfrei := true
	for phase: String in phasen_von(rezept_def):
		match phase:
			"grill":
				for _i in int(bestellung.get("patties", 0)):
					if rng.next() < skill:
						punkte += int(bal.get("punkte_perfekt", 10))
						zaehler["perfekt"] = int(zaehler["perfekt"]) + 1
					else:
						punkte += int(bal.get("punkte_roestaroma", 5))
						zaehler["roestaroma"] = int(zaehler["roestaroma"]) + 1
						fehlerfrei = false
			"belegen":
				var ticket := McGoobyStationBelegen.ticket_von(rezept_def)
				if ticket.is_empty():
					continue
				var belegt := McGoobyStationBelegen.bot_runde(rng, ticket, bal, skill)
				punkte += int(belegt["punkte"])
				zaehler["fehlgriffe"] = int(zaehler["fehlgriffe"]) + int(belegt["fehlgriffe"])
				fehlerfrei = fehlerfrei and bool(belegt["fehlerfrei"])
			"fritteuse":
				var koerbe := McGoobyStationFritteuse.aktionen_von(rezept_def)
				if koerbe.is_empty():
					continue
				var frittiert := McGoobyStationFritteuse.bot_runde(rng, koerbe, bal, skill)
				punkte += int(frittiert["punkte"])
				zaehler["perfekt"] = (
					int(zaehler["perfekt"]) + koerbe.size() - int(frittiert["dunkel"])
				)
				zaehler["dunkel"] = int(zaehler["dunkel"]) + int(frittiert["dunkel"])
				fehlerfrei = fehlerfrei and bool(frittiert["fehlerfrei"])
			"shake":
				var kreise := McGoobyStationShake.aktionen_von(rezept_def)
				if kreise.is_empty():
					continue
				var gemixt := McGoobyStationShake.bot_runde(rng, kreise, bal, skill)
				punkte += int(gemixt["punkte"])
				zaehler["perfekt"] = int(zaehler["perfekt"]) + kreise.size() - int(gemixt["schaum"])
				zaehler["schaum"] = int(zaehler["schaum"]) + int(gemixt["schaum"])
				fehlerfrei = fehlerfrei and bool(gemixt["fehlerfrei"])
	punkte += int(bal.get("bestellung_fertig_bonus", 15))
	return {"punkte": punkte, "fehlerfrei": fehlerfrei}
