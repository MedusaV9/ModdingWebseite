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
## Kundenstrom). menu = McGoobyKatalog.rezepte_fuer("grill").
## Rückgabe: [{nr, rezept_id, patties}] — patties = Grill-Schritte des Rezepts.
static func bestell_folge(seed_wert: int, menu: Array, bal: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if menu.is_empty():
		return out
	var rng := GoobyRng.new(seed_wert)
	var lo := maxi(1, int(bal.get("bestellungen_min", 2)))
	var hi := maxi(lo, int(bal.get("bestellungen_max", 4)))
	var anzahl := lo + int(floor(rng.next() * float(hi - lo + 1)))
	for i in anzahl:
		var idx := mini(menu.size() - 1, int(floor(rng.next() * float(menu.size()))))
		var rezept_def: Dictionary = menu[idx]
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


## Anzahl der Grill-Aktionen eines Rezepts (Summe der `anzahl`-Felder der
## Schritte an der Station grill; mindestens 1, sobald Grill dabei ist).
static func grill_schritte(rezept_def: Dictionary) -> int:
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


## Deterministische Bot-Zertifizierung (Doc §10.4): derselbe Seed erzeugt
## dieselbe Bestell-Folge UND dieselben Bot-Taps → exakte Goldwerte.
## menu wie bestell_folge; Rückgabe inkl. Abrechnung (McGoobyAbrechnung).
static func simulate_autoplay(seed_wert: int, menu: Array, bal: Dictionary) -> Dictionary:
	var folge := bestell_folge(seed_wert, menu, bal)
	# Eigener Bot-RNG-Strom, versetzt geseedet — unabhängig von der Folge.
	var rng := GoobyRng.new(seed_wert + 1)
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var ergebnisse: Array[Dictionary] = []
	var perfekt := 0
	var roestaroma := 0
	for bestellung: Dictionary in folge:
		var punkte := 0
		var fehlerfrei := true
		for _i in int(bestellung["patties"]):
			if rng.next() < skill:
				punkte += int(bal.get("punkte_perfekt", 10))
				perfekt += 1
			else:
				punkte += int(bal.get("punkte_roestaroma", 5))
				roestaroma += 1
				fehlerfrei = false
		punkte += int(bal.get("bestellung_fertig_bonus", 15))
		ergebnisse.append({"punkte": punkte, "fehlerfrei": fehlerfrei})
	var kasse := McGoobyAbrechnung.abrechnung(ergebnisse, bal)
	return {
		"seed": seed_wert,
		"bestellungen": folge.size(),
		"perfekt": perfekt,
		"roestaroma": roestaroma,
		"punkte": int(kasse["punkte"]),
		"trinkgeld": int(kasse["trinkgeld"]),
		"muenzen": int(kasse["muenzen"]),
	}
