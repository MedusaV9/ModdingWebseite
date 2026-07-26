class_name RcompWertungGelaende
extends RefCounted
## Geländeritt-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 3) — PURE.
## `Wertung = Zeit + 8 s je ausgelassenem Tor` (kleiner = besser).
## Sterne: ≤ Richtzeit / ≤ 110 % / ≤ 125 %. 8–15 Flaggentore je Kurs.

const TOR_STRAFE_S := 8.0
const STERNE_MULT: Array[float] = [1.0, 1.1, 1.25]
const TORE_JE_KLASSE := {"holz": 8, "bronze": 10, "silber": 12, "gold": 13, "sternenklasse": 15}


## Doc-Formel: Zeit + 8 s je ausgelassenem Tor.
static func wertung_s(zeit_s: float, tore_verpasst: int) -> float:
	return maxf(0.0, zeit_s) + TOR_STRAFE_S * maxi(0, tore_verpasst)


## 3 Sterne ≤ Richtzeit, 2 ≤ 110 %, 1 ≤ 125 %, sonst 0.
static func sterne(wertung: float, richtzeit_s: float) -> int:
	if richtzeit_s <= 0.0:
		return 0
	for i in STERNE_MULT.size():
		if wertung <= richtzeit_s * STERNE_MULT[i]:
			return 3 - i
	return 0


static func tor_anzahl(klasse: String) -> int:
	return int(TORE_JE_KLASSE.get(klasse, 8))
