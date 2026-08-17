class_name RcompWertungSpringen
extends RefCounted
## Springparcours-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 1) — PURE.
## `Score = 1000 − 40·Abwürfe − 20·Verweigerungen
##          − 5·max(0; Zeit−Richtzeit in s) + 15·Perfekt-Absprünge`
## Sterne: ≥ 900 / ≥ 750 / ≥ 550. Kurse: 8–14 Hindernisse je Klasse.

const BASIS := 1000.0
const ABWURF_MALUS := 40.0
const VERWEIGERUNG_MALUS := 20.0
const ZEIT_MALUS_PRO_S := 5.0
const PERFEKT_BONUS := 15.0
const STERNE_AB: Array[int] = [900, 750, 550]
## Hindernis-Anzahl je Klasse (8–14 laut Doc).
const HINDERNISSE_JE_KLASSE := {
	"holz": 8, "bronze": 9, "silber": 11, "gold": 12, "sternenklasse": 14
}


## Doc-Formel; Score kann nicht unter 0 fallen (Wohlfühlspiel).
static func score(
	abwuerfe: int, verweigerungen: int, zeit_s: float, richtzeit_s: float, perfekte: int
) -> int:
	var wert := (
		BASIS
		- ABWURF_MALUS * maxi(0, abwuerfe)
		- VERWEIGERUNG_MALUS * maxi(0, verweigerungen)
		- ZEIT_MALUS_PRO_S * maxf(0.0, zeit_s - richtzeit_s)
		+ PERFEKT_BONUS * maxi(0, perfekte)
	)
	return maxi(0, int(round(wert)))


## 3/2/1 Sterne ab 900/750/550, darunter 0 (Teilnahme zählt trotzdem).
static func sterne(punkte: int) -> int:
	for i in STERNE_AB.size():
		if punkte >= STERNE_AB[i]:
			return 3 - i
	return 0


static func hindernis_anzahl(klasse: String) -> int:
	return int(HINDERNISSE_JE_KLASSE.get(klasse, 8))
