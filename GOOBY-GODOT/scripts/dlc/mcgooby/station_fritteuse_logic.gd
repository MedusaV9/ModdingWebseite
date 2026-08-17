class_name McGoobyStationFritteuse
extends RefCounted
## Pure Fritteusen-Logik des McGooby-DLC (Welle C, Doc §2.2 #3): Korb
## halten, Blubber-Intensität + Farbton zeigen den Gargrad, im goldenen
## Fenster loslassen. Jeder Rezept-Schritt an der Station (frittieren,
## salz, wolken_dip …) ist EINE Halte-Runde mit demselben Fenster —
## Möhren-Pommes verengen es per `fenster_mult` (knackig!, Rezept-Gefühl
## durch Timing). Zu früh gezogen ist NIE verloren: der Korb taucht
## einfach wieder ein (0 Punkte, weiterbraten — Grill-Grammatik §4.2);
## zu spät gibt es das „Knusper-Deluxe“ mit halben Punkten. Keine Nodes,
## keine Autoloads — bot-zertifizierbar via simulate_autoplay (Doc §10.4).
## Zahlen kommen IMMER aus dem Balance-Block des Menü-Packs.

const STATION_ID := "fritteuse"

const WERTUNG_BLASS := "blass"
const WERTUNG_PERFEKT := "perfekt"
const WERTUNG_DUNKEL := "dunkel"

const ZUSTAND_BLASS := "blass"
const ZUSTAND_GOLDGELB := "goldgelb"
const ZUSTAND_DUNKEL := "dunkel"


## Halte-Runden eines Rezepts an der Fritteuse: jede Aktion `anzahl`-mal,
## in Schritt-Reihenfolge (["frittieren", "glitzersalz"] …); leer = das
## Rezept braucht die Fritteuse nicht.
static func aktionen_von(rezept_def: Dictionary) -> Array[String]:
	return aktionen_fuer(rezept_def, STATION_ID)


## Geteilter Helfer (auch die Shake-Bar nutzt ihn): alle Aktionen eines
## Rezepts an EINER Station, `anzahl`-fach ausgerollt.
static func aktionen_fuer(rezept_def: Dictionary, station: String) -> Array[String]:
	var out: Array[String] = []
	for schritt: Variant in rezept_def.get("schritte", []):
		if not (schritt is Dictionary):
			continue
		var zeile: Dictionary = schritt
		if str(zeile.get("station", "")) != station:
			continue
		for _i in maxi(1, int(zeile.get("anzahl", 1))):
			out.append(str(zeile.get("aktion", "")))
	return out


## Korb-Zustand zum Zeitpunkt t (Sekunden seit dem Eintauchen).
static func zustand(t_sec: float, timing: Dictionary) -> String:
	var gar := float(timing.get("gar_sec", 5.0))
	if t_sec < gar:
		return ZUSTAND_BLASS
	if t_sec < gar + float(timing.get("fenster_sec", 1.2)):
		return ZUSTAND_GOLDGELB
	return ZUSTAND_DUNKEL


## Blubber-Fortschritt 0..1 fürs Visuelle (1.0 = Ende des goldenen Fensters).
static func fortschritt(t_sec: float, timing: Dictionary) -> float:
	var ende := float(timing.get("gar_sec", 5.0)) + float(timing.get("fenster_sec", 1.2))
	if ende <= 0.0:
		return 1.0
	return clampf(t_sec / ende, 0.0, 1.0)


## Loslassen/Korb-Zug werten (Doc §2.2 #3): im goldenen Fenster = volle
## Punkte, danach „Knusper-Deluxe“ = halbe Punkte, davor passiert NICHTS
## (blass, 0 Punkte — der Korb taucht wieder ein, keine Strafe).
static func bewerte_zug(t_sec: float, timing: Dictionary, bal: Dictionary) -> Dictionary:
	match zustand(t_sec, timing):
		ZUSTAND_BLASS:
			return {"wertung": WERTUNG_BLASS, "punkte": 0}
		ZUSTAND_GOLDGELB:
			return {"wertung": WERTUNG_PERFEKT, "punkte": punkte_perfekt(bal)}
		_:
			return {"wertung": WERTUNG_DUNKEL, "punkte": punkte_dunkel(bal)}


## Vergessene Körbe werten wie ein später Zug (Knusper-Deluxe, halbe Punkte).
static func bewerte_vergessen(bal: Dictionary) -> Dictionary:
	return {"wertung": WERTUNG_DUNKEL, "punkte": punkte_dunkel(bal)}


static func punkte_perfekt(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("fritteuse_punkte_perfekt", 10)))


static func punkte_dunkel(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("fritteuse_punkte_dunkel", 5)))


## Bot-Runde über ALLE Halte-Runden eines Rezepts auf einem GETEILTEN
## RNG-Strom — die Schicht-Zertifizierung (McGoobySchichtLogic) hängt sich
## mit demselben Strom hier ein. Modell wie am Grill: pro Runde würfelt
## der Bot einmal; daneben = Knusper-Deluxe (halbe Punkte, nicht fehlerfrei).
static func bot_runde(rng: GoobyRng, aktionen: Array, bal: Dictionary, skill: float) -> Dictionary:
	var punkte := 0
	var dunkel := 0
	for _aktion: Variant in aktionen:
		if rng.next() < skill:
			punkte += punkte_perfekt(bal)
		else:
			punkte += punkte_dunkel(bal)
			dunkel += 1
	return {
		"aktionen": aktionen.size(),
		"dunkel": dunkel,
		"punkte": punkte,
		"fehlerfrei": dunkel == 0,
	}


## Deterministische Bot-Zertifizierung der Station allein (Doc §10.4):
## derselbe Seed + dieselben Aktionen → exakt dieselben Goldwerte.
static func simulate_autoplay(seed_wert: int, aktionen: Array, bal: Dictionary) -> Dictionary:
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var ergebnis := bot_runde(GoobyRng.new(seed_wert), aktionen, bal, skill)
	ergebnis["seed"] = seed_wert
	return ergebnis
