class_name RcompWertungTrail
extends RefCounted
## Westerntrail-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 5) — PURE.
## 6 Präzisionsaufgaben à 0–10 P (Berührung −2, Auslassen 0);
## `Zeitbonus = max(0; 20 − ⌈max(0; Zeit−90 s)⌉)` → Maximum 80 Punkte.

const AUFGABEN_ANZAHL := 6
const AUFGABE_MAX := 10
const BERUEHRUNG_MALUS := 2
const ZEITBONUS_MAX := 20
const ZEITBONUS_AB_S := 90.0
const MAXIMUM := 80
const STERNE_AB: Array[int] = [70, 55, 40]
## Die 6 Aufgaben des Doc-Kurses (Tor, Rückwärts-L, Stangen-Slalom,
## Brücke, Planen-Feld, 360°-Kreisel).
const AUFGABEN: Array[String] = ["tor", "rueckwaerts_l", "slalom", "bruecke", "plane", "kreisel"]


## Punkte einer Aufgabe: 10 − 2·Berührungen, ausgelassen = 0.
static func aufgabe_punkte(beruehrungen: int, ausgelassen: bool) -> int:
	if ausgelassen:
		return 0
	return clampi(AUFGABE_MAX - BERUEHRUNG_MALUS * maxi(0, beruehrungen), 0, AUFGABE_MAX)


## Doc-Formel: max(0; 20 − ⌈max(0; Zeit−90 s)⌉).
static func zeitbonus(zeit_s: float) -> int:
	return maxi(0, ZEITBONUS_MAX - int(ceil(maxf(0.0, zeit_s - ZEITBONUS_AB_S))))


## Gesamt = Σ Aufgabenpunkte + Zeitbonus (Deckel 80).
static func gesamt(aufgaben_punkte: Array, zeit_s: float) -> int:
	var summe := 0
	for wert: Variant in aufgaben_punkte:
		summe += clampi(int(_num(wert, 0.0)), 0, AUFGABE_MAX)
	return mini(MAXIMUM, summe + zeitbonus(zeit_s))


static func sterne(punkte: int) -> int:
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
