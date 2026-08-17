class_name RanchHorseBond
extends RefCounted
## Bindungs-Level 1–10 mit Freischaltungen (RW-2, RANCH-DLC-IDEAS-1 A1 +
## IDEAS-3 Kap. 1.4) — PURE. Die bestehende `bindung` (0–100,
## RanchHorseCare) wird in 10 Level uebersetzt; JEDES Level schaltet
## etwas SPUERBARES frei (RDR2-/SSO-Vorbild): vom Steigen-Emote bis zur
## Seelenpferd-Aura. Die Stufen-Ids von RanchHorseCare.BINDUNG_STUFEN
## bleiben unberuehrt — dieses Modul ergaenzt nur die Freischalt-Achse.

## 10 Punkte Bindung je Level: 0–9 = L1, …, 90–100 = L10.
const PUNKTE_JE_LEVEL := 10.0
const LEVEL_MAX := 10

## Freischaltungen je Level (Level 1 = nichts, das Kennenlernen).
## Ids konsumieren ride_controller/HUD/Hof-Szene; Texte: rpferd.bindung.*.
const FREISCHALTUNGEN := {
	2: "maennchen",
	3: "rutsch_stopp",
	4: "pfiff",
	5: "konfetti_drift",
	6: "zweiter_wind_plus",
	7: "autopilot",
	8: "kopf_dreht",
	9: "emotes",
	10: "seelenpferd_aura",
}

## Rueckruf-Pfiff (ab L4): Reichweite waechst mit der Bindung weiter.
const PFIFF_BASIS_M := 20.0
const PFIFF_PRO_BINDUNG_M := 0.6
## Rutsch-Stopp (ab L3): williger bremsen (+m/s² auf ACCEL_AB).
const RUTSCH_STOPP_BONUS := 1.5
## Zweiter Wind: +25 Basis (ride_feel), ab L6 +35.
const ZWEITER_WIND_PLUS := 35.0
## Besondere Emotes (ab L9) — Simon-Says der Schau nutzt dieselben Ids.
const EMOTES: Array[String] = ["verbeugen", "drehen", "steigen", "kompliment", "kuss"]


## Bindungs-Level 1–10 fuer einen Bindungswert 0–100.
static func level_fuer_bindung(bindung: float) -> int:
	return clampi(1 + int(floor(maxf(0.0, bindung) / PUNKTE_JE_LEVEL)), 1, LEVEL_MAX)


## Alle bis `level` freigeschalteten Ids (in Level-Reihenfolge).
static func freischaltungen_bis(level: int) -> Array:
	var out: Array = []
	for l in range(2, clampi(level, 1, LEVEL_MAX) + 1):
		if FREISCHALTUNGEN.has(l):
			out.append(FREISCHALTUNGEN[l])
	return out


## Ist eine Freischaltung bei dieser Bindung aktiv?
static func ist_frei(bindung: float, id: String) -> bool:
	return freischaltungen_bis(level_fuer_bindung(bindung)).has(id)


## Rueckruf-Reichweite in Metern (0 = Pfiff noch nicht freigeschaltet).
static func pfiff_reichweite_m(bindung: float) -> float:
	if not ist_frei(bindung, "pfiff"):
		return 0.0
	return PFIFF_BASIS_M + clampf(bindung, 0.0, 100.0) * PFIFF_PRO_BINDUNG_M


## Zweiter-Wind-Bonus: Basis aus ride_feel, ab L6 der Plus-Wert.
static func zweiter_wind_bonus(bindung: float, basis: float) -> float:
	return ZWEITER_WIND_PLUS if ist_frei(bindung, "zweiter_wind_plus") else basis


## Brems-Zuschlag (m/s²) durch den Rutsch-Stopp.
static func brems_bonus(bindung: float) -> float:
	return RUTSCH_STOPP_BONUS if ist_frei(bindung, "rutsch_stopp") else 0.0


## Naechste Freischaltung fuer die UI: {"level", "id", "fehlt"} —
## leer ({}), wenn alles offen ist.
static func naechste_freischaltung(bindung: float) -> Dictionary:
	var level := level_fuer_bindung(bindung)
	for l in range(level + 1, LEVEL_MAX + 1):
		if FREISCHALTUNGEN.has(l):
			var noetig := float(l - 1) * PUNKTE_JE_LEVEL
			return {
				"level": l,
				"id": FREISCHALTUNGEN[l],
				"fehlt": maxf(0.0, noetig - clampf(bindung, 0.0, 100.0)),
			}
	return {}
