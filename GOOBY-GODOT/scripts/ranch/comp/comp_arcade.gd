class_name RanchCompArcade
extends RefCounted
## Arcade-Leitern der RW-5-Minispiele (ranchTonnen/ranchZeit) — PURE.
## 10 Läufe je Spiel: die Tonnen-Idealzeit sinkt 26 → 17 s (Doc-Spanne
## Kap. 5.2 Nr. 7), das Zeitrennen zieht seine Zielzeit aus der ECHTEN
## Streckenlänge (RcompKurs.zeit_route, fester Seed — nur so bleiben
## Geisterläufe über Sessions vergleichbar). Score/Sterne sind hier,
## damit Tests sie ohne Szene prüfen.

const Kurs := preload("res://scripts/ranch/comp/szene/comp_kurs.gd")
const WTonnen := preload("res://scripts/ranch/comp/wertung/wertung_tonnen.gd")

## == RanchCompState.ARCADE_LEVEL (Sync-Test sichert das).
const LEVEL_ANZAHL := 10
const TONNEN_IDEAL_START_S := 26.0
const TONNEN_IDEAL_SCHRITT_S := 1.0
## Fester Kurs-Seed: Lauf N ist IMMER dieselbe Strecke (Geist-Fairness).
const ZEIT_KURS_SEED := 4242
## Zielzeit = Streckenlänge / Reisetempo + Anlauf-Polster.
const ZEIT_TEMPO_MS := 5.2
const ZEIT_POLSTER_S := 6.0
const SCORE_BASIS := 40
const SCORE_JE_STERN := 25
const SCORE_ZEITBONUS_MAX := 60
const FIRST_CLEAR_BONUS := 30


## Tonnen-Idealzeit von Lauf 1 (26 s) bis Lauf 10 (17 s).
static func tonnen_ideal_s(level: int) -> float:
	return TONNEN_IDEAL_START_S - TONNEN_IDEAL_SCHRITT_S * (clampi(level, 1, LEVEL_ANZAHL) - 1)


## Zeitrennen-Strecke eines Laufs (deterministisch, fester Seed).
static func zeit_route(level: int) -> Array[Dictionary]:
	return Kurs.zeit_route(clampi(level, 1, LEVEL_ANZAHL), ZEIT_KURS_SEED)


## Startpunkt des Zeitrennens (== Ursprung der Route in RcompKurs).
static func zeit_start() -> Vector3:
	return Vector3(0.0, 0.0, 58.0)


## Zielzeit eines Laufs aus der echten Streckenlänge.
static func zeit_ziel_s(level: int) -> float:
	var vorher := zeit_start()
	var laenge := 0.0
	for tor in zeit_route(level):
		var pos: Vector3 = tor["pos"]
		laenge += Vector2(pos.x - vorher.x, pos.z - vorher.z).length()
		vorher = pos
	return snappedf(laenge / ZEIT_TEMPO_MS + ZEIT_POLSTER_S, 0.5)


## Sterne beider Spiele laufen über die Tonnen-Staffel (1,0/1,15/1,35).
static func sterne(wertung_s: float, ziel_s: float) -> int:
	return WTonnen.sterne(wertung_s, ziel_s)


## Arcade-Score eines Laufs: Basis + Sterne + Zeitbonus + First-Clear.
static func score(stars: int, wertung_s: float, ziel_s: float, first_clear: bool) -> int:
	var zeitbonus := clampi(int(round(ziel_s * 1.35 - wertung_s)), 0, SCORE_ZEITBONUS_MAX)
	var summe := SCORE_BASIS + SCORE_JE_STERN * clampi(stars, 0, 3) + zeitbonus
	return summe + (FIRST_CLEAR_BONUS if first_clear else 0)


## Geist-Schlüssel des Zeitrennens je Lauf (Kurse unterscheiden sich!).
static func zeit_geist_key(level: int) -> String:
	return "zeit_k%d" % clampi(level, 1, LEVEL_ANZAHL)
