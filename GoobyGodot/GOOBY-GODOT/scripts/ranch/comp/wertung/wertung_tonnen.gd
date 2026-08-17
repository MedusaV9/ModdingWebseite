class_name RcompWertungTonnen
extends RefCounted
## Tonnenrennen-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 7) — PURE.
## Kleeblatt um 3 Tonnen, fliegender Start.
## `Wertung = Zeit + 5 s je umgeworfener Tonne` (kleiner = besser).
## Idealzeit ~24 s (Holz) bis ~17 s (Sternenklasse) — der
## "noch ein Versuch!"-Kick: Läufe dauern < 30 s.

const TONNEN_ANZAHL := 3
const TONNE_STRAFE_S := 5.0
const IDEALZEIT_S := {
	"holz": 24.0, "bronze": 22.0, "silber": 20.0, "gold": 18.5, "sternenklasse": 17.0
}
const STERNE_MULT: Array[float] = [1.0, 1.15, 1.35]


## Doc-Formel: Zeit + 5 s je umgeworfener Tonne.
static func wertung_s(zeit_s: float, umgeworfen: int) -> float:
	return maxf(0.0, zeit_s) + TONNE_STRAFE_S * maxi(0, umgeworfen)


static func idealzeit(klasse: String) -> float:
	return float(IDEALZEIT_S.get(klasse, 24.0))


## 3 Sterne ≤ Idealzeit, 2 ≤ 115 %, 1 ≤ 135 %, sonst 0.
static func sterne(wertung: float, ideal_s: float) -> int:
	if ideal_s <= 0.0:
		return 0
	for i in STERNE_MULT.size():
		if wertung <= ideal_s * STERNE_MULT[i]:
			return 3 - i
	return 0
