class_name RcompWertungDressur
extends RefCounted
## Dressur-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 2) — PURE.
## Je Figur: `Punkte = max(0; 100 − 50·(d̄/0,75) − 25·Gangartfehler)`
## (d̄ = mittlere Abweichung von der Ideallinie in m).
## `Gesamt = Ø Figurpunkte + 10 Taktbonus`, wenn ALLE Gangartwechsel im
## Metronom-Fenster ±250 ms liegen.

const FIGUR_MAX := 100.0
const ABWEICHUNG_REFERENZ_M := 0.75
const ABWEICHUNG_MALUS := 50.0
const GANGARTFEHLER_MALUS := 25.0
const TAKT_FENSTER_MS := 250.0
const TAKT_BONUS := 10.0
const STERNE_AB: Array[float] = [85.0, 70.0, 50.0]
## Figurenfolge des Turniers (Doc: Zirkel, Acht, Schlangenlinie, Halten,
## Rückwärtsrichten).
const FIGUREN: Array[String] = ["zirkel", "acht", "schlangenlinie", "halten", "rueckwaerts"]


## Doc-Formel je Figur.
static func figur_punkte(d_mittel_m: float, gangartfehler: int) -> float:
	var wert := (
		FIGUR_MAX
		- ABWEICHUNG_MALUS * (maxf(0.0, d_mittel_m) / ABWEICHUNG_REFERENZ_M)
		- GANGARTFEHLER_MALUS * maxi(0, gangartfehler)
	)
	return maxf(0.0, wert)


## Taktbonus nur, wenn ALLE Wechsel-Abweichungen im ±250-ms-Fenster liegen.
static func takt_ok(wechsel_abweichungen_ms: Array) -> bool:
	for wert: Variant in wechsel_abweichungen_ms:
		if absf(_num(wert, 999.0)) > TAKT_FENSTER_MS:
			return false
	return true


## Gesamt = Durchschnitt der Figurpunkte + 10 Taktbonus (Doc-Formel).
static func gesamt(figur_punkte_liste: Array, mit_taktbonus: bool) -> float:
	if figur_punkte_liste.is_empty():
		return 0.0
	var summe := 0.0
	for wert: Variant in figur_punkte_liste:
		summe += clampf(_num(wert, 0.0), 0.0, FIGUR_MAX)
	var mittel := summe / figur_punkte_liste.size()
	return mittel + (TAKT_BONUS if mit_taktbonus else 0.0)


static func sterne(punkte: float) -> int:
	for i in STERNE_AB.size():
		if punkte >= STERNE_AB[i]:
			return 3 - i
	return 0


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
