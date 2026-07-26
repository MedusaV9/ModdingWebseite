class_name RcompWertungSchau
extends RefCounted
## Schau-Wertung (RW-5, IDEAS-3 Kap. 5.2 Nr. 6) — PURE. DER Cosmetics-
## Showcase: `Wertung = 0,4·Pflege + 0,3·Stil + 0,3·Kür` (je 0–100).
## Pflege = (sauberkeit + Laune) / 2; Stil = min(100; Raritätspunkte +
## Setbonus + Themenbonus); Kür = Simon-Says, 5 Kommandos à 20 P
## (Timing-Treffer ±300 ms). Stat-unabhängig — Level-1-Pferde können
## gewinnen (Miniknopf/eitel glänzen: +10 % Stil).

const GEWICHT_PFLEGE := 0.4
const GEWICHT_STIL := 0.3
const GEWICHT_KUER := 0.3
const RARITAET_PUNKTE := {"gewoehnlich": 4, "selten": 7, "episch": 11, "legendaer": 16}
const SET_BONUS := 10
const THEMA_BONUS := 15
const KUER_KOMMANDOS := 5
const KUER_PUNKTE_JE_TREFFER := 20.0
const KUER_FENSTER_MS := 300.0
const STERNE_AB: Array[float] = [85.0, 70.0, 50.0]
## Die 5 Kür-Kommandos (Verbeugen, Drehen, Steigen, Kompliment, Kuss).
const KOMMANDOS: Array[String] = ["verbeugen", "drehen", "steigen", "kompliment", "kuss"]


## Pflege = (sauberkeit + Laune) / 2 — direkter Payoff des Pflegesystems.
static func pflege(sauberkeit: float, laune: float) -> float:
	return clampf((clampf(sauberkeit, 0.0, 100.0) + clampf(laune, 0.0, 100.0)) / 2.0, 0.0, 100.0)


## Stil = min(100; Σ Raritätspunkte + Setbonus + Themenbonus) · Bonus-Mult
## (Miniknopf/eitel: stil_mult 1,1 — Deckel bleibt 100).
static func stil(
	raritaeten: Array, set_komplett: bool, thema_getroffen: bool, stil_mult := 1.0
) -> float:
	var punkte := 0.0
	for eintrag: Variant in raritaeten:
		punkte += float(RARITAET_PUNKTE.get(str(eintrag), 0))
	if set_komplett:
		punkte += SET_BONUS
	if thema_getroffen:
		punkte += THEMA_BONUS
	return clampf(punkte * maxf(0.0, stil_mult), 0.0, 100.0)


## Ein Kür-Kommando trifft, wenn die Tipp-Abweichung ≤ ±300 ms liegt.
static func kuer_treffer(abweichung_ms: float) -> bool:
	return absf(abweichung_ms) <= KUER_FENSTER_MS


## Kür = 20 P je Timing-Treffer (max 5 Kommandos).
static func kuer(treffer: int) -> float:
	return clampf(KUER_PUNKTE_JE_TREFFER * clampi(treffer, 0, KUER_KOMMANDOS), 0.0, 100.0)


## Doc-Formel: 0,4·Pflege + 0,3·Stil + 0,3·Kür.
static func gesamt(pflege_wert: float, stil_wert: float, kuer_wert: float) -> float:
	return (
		GEWICHT_PFLEGE * clampf(pflege_wert, 0.0, 100.0)
		+ GEWICHT_STIL * clampf(stil_wert, 0.0, 100.0)
		+ GEWICHT_KUER * clampf(kuer_wert, 0.0, 100.0)
	)


static func sterne(punkte: float) -> int:
	for i in STERNE_AB.size():
		if punkte >= STERNE_AB[i]:
			return 3 - i
	return 0
