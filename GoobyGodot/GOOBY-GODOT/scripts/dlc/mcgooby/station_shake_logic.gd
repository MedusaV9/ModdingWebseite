class_name McGoobyStationShake
extends RefCounted
## Pure Shake-Bar-Logik des McGooby-DLC (Welle C, Doc §2.2 #4): im Takt
## kreisen, bis die Flausch-Krone steht. Anders als Grill/Fritteuse rührt
## sich hier NICHTS von allein — die Rühr-Zeit wächst nur, solange der
## Spieler aktiv kreist (das setzt das Szenen-Glue um; die Jonglage-Würze:
## Pattys/Körbe garen derweil weiter). Aufhören bewertet den Stand:
## zu früh = noch flüssig (0 Punkte, einfach weiterkreisen — nie Strafe,
## §4.2), im goldenen Fenster steht die Krone („Perfekt!“), überdreht
## schäumt der Shake comic-haft über (halbe Punkte + Wischtuch-Gag).
## Jeder Rezept-Schritt an der Station (mixen, flausch_krone …) ist EINE
## Kreis-Runde. Keine Nodes, keine Autoloads — bot-zertifizierbar via
## simulate_autoplay (Doc §10.4). Zahlen IMMER aus dem Balance-Pack.

const STATION_ID := "shake"

const WERTUNG_FLUESSIG := "fluessig"
const WERTUNG_PERFEKT := "perfekt"
const WERTUNG_SCHAUM := "schaum"

const ZUSTAND_FLUESSIG := "fluessig"
const ZUSTAND_KRONE := "krone"
const ZUSTAND_SCHAUM := "schaum"


## Kreis-Runden eines Rezepts an der Shake-Bar: jede Aktion `anzahl`-mal,
## in Schritt-Reihenfolge (["mixen", "flausch_krone"] …); leer = das
## Rezept braucht die Shake-Bar nicht.
static func aktionen_von(rezept_def: Dictionary) -> Array[String]:
	return McGoobyStationFritteuse.aktionen_fuer(rezept_def, STATION_ID)


## Krone-Zustand nach t Sekunden AKTIVEN Kreisens.
static func zustand(t_sec: float, timing: Dictionary) -> String:
	var gar := float(timing.get("gar_sec", 3.5))
	if t_sec < gar:
		return ZUSTAND_FLUESSIG
	if t_sec < gar + float(timing.get("fenster_sec", 1.6)):
		return ZUSTAND_KRONE
	return ZUSTAND_SCHAUM


## Kronen-Füllstand 0..1 fürs Visuelle (1.0 = Ende des goldenen Fensters).
static func fortschritt(t_sec: float, timing: Dictionary) -> float:
	var ende := float(timing.get("gar_sec", 3.5)) + float(timing.get("fenster_sec", 1.6))
	if ende <= 0.0:
		return 1.0
	return clampf(t_sec / ende, 0.0, 1.0)


## Kreis-Stopp werten (Doc §2.2 #4): steht die Krone = volle Punkte,
## überdreht = Schaum mit halben Punkten, davor passiert NICHTS
## (noch flüssig, 0 Punkte — einfach weiterkreisen, keine Strafe).
static func bewerte_stopp(t_sec: float, timing: Dictionary, bal: Dictionary) -> Dictionary:
	match zustand(t_sec, timing):
		ZUSTAND_FLUESSIG:
			return {"wertung": WERTUNG_FLUESSIG, "punkte": 0}
		ZUSTAND_KRONE:
			return {"wertung": WERTUNG_PERFEKT, "punkte": punkte_perfekt(bal)}
		_:
			return {"wertung": WERTUNG_SCHAUM, "punkte": punkte_schaum(bal)}


## Überdreht (weitergekreist bis über den Nachlauf): Schaum, halbe Punkte.
static func bewerte_ueberdreht(bal: Dictionary) -> Dictionary:
	return {"wertung": WERTUNG_SCHAUM, "punkte": punkte_schaum(bal)}


static func punkte_perfekt(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("shake_punkte_perfekt", 10)))


static func punkte_schaum(bal: Dictionary) -> int:
	return maxi(0, int(bal.get("shake_punkte_schaum", 5)))


## Bot-Runde über ALLE Kreis-Runden eines Rezepts auf einem GETEILTEN
## RNG-Strom (Schicht-Zertifizierung hängt sich mit demselben Strom ein).
## Modell wie Grill/Fritteuse: pro Runde ein Wurf; daneben = Schaum
## (halbe Punkte, nicht fehlerfrei).
static func bot_runde(rng: GoobyRng, aktionen: Array, bal: Dictionary, skill: float) -> Dictionary:
	var punkte := 0
	var schaum := 0
	for _aktion: Variant in aktionen:
		if rng.next() < skill:
			punkte += punkte_perfekt(bal)
		else:
			punkte += punkte_schaum(bal)
			schaum += 1
	return {
		"aktionen": aktionen.size(),
		"schaum": schaum,
		"punkte": punkte,
		"fehlerfrei": schaum == 0,
	}


## Deterministische Bot-Zertifizierung der Station allein (Doc §10.4):
## derselbe Seed + dieselben Aktionen → exakt dieselben Goldwerte.
static func simulate_autoplay(seed_wert: int, aktionen: Array, bal: Dictionary) -> Dictionary:
	var skill := clampf(float(bal.get("bot_skill", 0.9)), 0.0, 1.0)
	var ergebnis := bot_runde(GoobyRng.new(seed_wert), aktionen, bal, skill)
	ergebnis["seed"] = seed_wert
	return ergebnis
