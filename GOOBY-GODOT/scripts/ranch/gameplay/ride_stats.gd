class_name RanchRideStats
extends RefCounted
## Stat-Schicht des Reitgefuehls (RW-2, IDEAS-3 Kap. 2.4 + 3) — PURE.
## Uebersetzt die 5 Trainingswerte (1–20, RanchHorseLevels.stats_effektiv)
## + Rassen-Eigenheiten/Charakterzuege in die ride_feel-Physik: Zieltempo,
## Antritts-Kick, Tölt, Lenkung, Ausdauer-Tank, Sprungkraft, Scheuen,
## Untergrund-Malus, Zweiter Wind und Sprung-Timing-Zonen. Konstanten
## (die Doc-Zahlen) leben in RanchRideFeel; hier stehen nur Formeln.
## Der Node-Controller reicht `stats` als Dictionary durch — alles im
## Runner testbar, nichts hier beruehrt Nodes.

const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")

## Schaltfolge mit Tölt (nur fuer Pferde mit der Tölt-Eigenheit).
const GANGARTEN_TOELT: Array[String] = ["stand", "schritt", "trab", "toelt", "galopp"]


## Naechsthoehere Gangart; kann_toelt schaltet die 5. Gangart zwischen
## Trab und Galopp ein (Tölterle-Exklusiv, Kap. 1.1).
static func gangart_hoch(gangart: String, kann_toelt := false) -> String:
	if not kann_toelt:
		return Feel.gangart_hoch("trab" if gangart == "toelt" else gangart)
	var i := GANGARTEN_TOELT.find(gangart)
	return GANGARTEN_TOELT[mini(GANGARTEN_TOELT.size() - 1, maxi(0, i) + 1)]


static func gangart_runter(gangart: String, kann_toelt := false) -> String:
	if not kann_toelt:
		return Feel.gangart_runter("galopp" if gangart == "toelt" else gangart)
	var i := GANGARTEN_TOELT.find(gangart)
	return GANGARTEN_TOELT[maxi(0, (i if i >= 0 else 1) - 1)]


## Galopp-Ziel = 8,5 · (1 + 0,015·(Tempo−10)) · Bindungs-Perk (7,4–9,8 m/s);
## andere Gangarten bleiben Bestand (Tölt fix 5,8).
static func zieltempo(gangart: String, stats: Dictionary, tempo_mult := 1.0) -> float:
	if gangart != "galopp":
		return Feel.zieltempo(gangart)
	var t := _stat(stats, "tempo")
	return float(Feel.TEMPO["galopp"]) * (1.0 + 0.015 * (t - 10.0)) * maxf(0.0, tempo_mult)


## Beschleunigung Richtung Ziel: im Galopp-Antritt KICK_ACCEL solange der
## Kick laeuft, danach Gangart-Antritt (Kap. 3.1).
static func accel_auf(gangart: String, kick_rest_s: float) -> float:
	if gangart == "galopp" and kick_rest_s > 0.0:
		return Feel.KICK_ACCEL
	return float(Feel.ACCEL_JE_GANGART.get(gangart, Feel.ACCEL_AUF))


## Kick-Dauer beim Angaloppieren (Flitzewind: 1,2 s statt 0,8 s).
static func kick_dauer_s(eigenheit_effekte: Dictionary) -> float:
	return _num(eigenheit_effekte.get("kick_dauer_s"), Feel.KICK_DAUER_S)


## Tempo-Integrationsschritt mit explizitem Antritt (Bremsen bleibt
## ACCEL_AB + Rutsch-Stopp-Bonus aus der Bindung).
static func step_tempo(
	tempo: float, ziel: float, dt: float, auf: float, brems_bonus := 0.0
) -> float:
	var accel := auf if tempo < ziel else Feel.ACCEL_AB + maxf(0.0, brems_bonus)
	return tempo + signf(ziel - tempo) * minf(absf(ziel - tempo), accel * dt)


## Ausdauer-Tank: 100 + 5·(Ausdauer−10) → 55–150.
static func ausdauer_max(stats: Dictionary) -> float:
	return 100.0 + 5.0 * (_stat(stats, "ausdauer") - 10.0)


## Galoppverbrauch: 7 · (1 − 0,01·(Ausdauer−10)) → 7,63–6,3/s.
static func galopp_verbrauch(stats: Dictionary) -> float:
	return Feel.AUSDAUER_GALOPP_PRO_S * (1.0 - 0.01 * (_stat(stats, "ausdauer") - 10.0))


## Ausdauer-Schritt mit Stats: Galopp/Tölt zehren, unterhalb Trab regen
## (regen_mult = Bindungs-Perk × gelassen-Zug). Klemmt auf [0, Tank].
static func step_ausdauer(
	ausdauer: float, gangart: String, dt: float, stats: Dictionary, regen_mult := 1.0
) -> float:
	var a := ausdauer
	if gangart == "galopp":
		a -= galopp_verbrauch(stats) * dt
	elif gangart == "toelt":
		a -= Feel.AUSDAUER_TOELT_PRO_S * dt
	elif gangart != "trab":
		a += Feel.AUSDAUER_REGEN_PRO_S * maxf(0.0, regen_mult) * dt
	return clampf(a, 0.0, ausdauer_max(stats))


## Gangart nach dem Ausdauer-Check (Tölt zaehlt wie Galopp erst ab 20 an).
static func gangart_nach_ausdauer(gewuenscht: String, ausdauer: float, war_schnell: bool) -> String:
	if gewuenscht != "galopp" and gewuenscht != "toelt":
		return gewuenscht
	if ausdauer <= 0.0:
		return Feel.AUSDAUER_LEER_GANGART
	if not war_schnell and ausdauer < Feel.AUSDAUER_GALOPP_AB:
		return "trab"
	return gewuenscht


## Yaw-Rate mit Wendigkeit: STEER_RATE · (1 + 0,02·(W−10)), Daempfung
## 0,3 − 0,006·(W−10); der 100°/s-Deckel bleibt (Kap. 2.4).
static func steer_yaw_rate(smoothed_steer: float, tempo: float, stats: Dictionary) -> float:
	if tempo < 0.2:
		return 0.0
	var w := _stat(stats, "wendigkeit")
	var rate := Feel.STEER_RATE * (1.0 + 0.02 * (w - 10.0))
	var damp_staerke := Feel.STEER_SPEED_DAMP - 0.006 * (w - 10.0)
	var damp := 1.0 - damp_staerke * minf(1.0, tempo / float(Feel.TEMPO["galopp"]))
	return clampf(
		smoothed_steer * rate * damp, -Feel.STEER_RATE_CAP_RAD_S, Feel.STEER_RATE_CAP_RAD_S
	)


## Absprungkraft: 4,8 + 0,06·(Sprungkraft−10) → Sprunghoehe 0,74–1,31 m.
static func sprung_vy(stats: Dictionary) -> float:
	return Feel.SPRUNG_VY + 0.06 * (_stat(stats, "sprungkraft") - 10.0)


## Scheu-Chance an Spuk-Punkten: 15 % · (1 − 0,05·(Gelassenheit−10)) ·
## Zug-Multiplikator (mutig/unerschrocken = 0).
static func scheu_chance(stats: Dictionary, scheu_mult := 1.0) -> float:
	var g := _stat(stats, "gelassenheit")
	return maxf(0.0, 0.15 * (1.0 - 0.05 * (g - 10.0)) * maxf(0.0, scheu_mult))


## Pflegeverfall-Multiplikator im Ritt: 1 − 0,01·(Gelassenheit−10).
static func pflege_verfall_mult(stats: Dictionary) -> float:
	return maxf(0.0, 1.0 - 0.01 * (_stat(stats, "gelassenheit") - 10.0))


## Sprung-Timing (Kap. 3.5): Abstand zum Hindernis beim Absprung →
## "perfekt" | "gut" | "daneben". bonus_ms (Federsprung +50, mutig +30)
## weitet NUR das Perfekt-Fenster, symmetrisch, tempoabhaengig.
static func sprung_wertung(dist_m: float, tempo: float, bonus_ms := 0.0) -> String:
	var extra := maxf(0.0, tempo) * maxf(0.0, bonus_ms) / 1000.0 * 0.5
	if dist_m >= Feel.SPRUNG_PERFEKT_VON_M - extra and dist_m <= Feel.SPRUNG_PERFEKT_BIS_M + extra:
		return "perfekt"
	if dist_m >= Feel.SPRUNG_GUT_VON_M and dist_m <= Feel.SPRUNG_GUT_BIS_M:
		return "gut"
	return "daneben"


## Untergrund-Eintrag (Sound/Pitch/Lautstaerke) — unbekannt faellt auf Wiese.
static func untergrund_info(untergrund: String) -> Dictionary:
	var raw: Variant = Feel.UNTERGRUND.get(untergrund, Feel.UNTERGRUND["wiese"])
	return raw if raw is Dictionary else {}


## Tempo-Multiplikator des Untergrunds; malus_mult 0,5 = Moosmaehne
## (Malus halbiert: Matsch ×0,9 → ×0,95).
static func untergrund_tempo_mult(untergrund: String, malus_mult := 1.0) -> float:
	var basis := _num(untergrund_info(untergrund).get("tempo_mult"), 1.0)
	return 1.0 - (1.0 - basis) * clampf(malus_mult, 0.0, 1.0)


## Zweiter Wind (Kap. 3.4): 1×/Ritt, Tank < 10, (fast) angehalten.
static func zweiter_wind_moeglich(ausdauer: float, tempo: float, schon_benutzt: bool) -> bool:
	return (
		not schon_benutzt
		and ausdauer < Feel.ZWEITER_WIND_AB
		and absf(tempo) <= Feel.ZWEITER_WIND_MAX_TEMPO
	)


## Bindungs-Malus einer Erschoepfung: nur bei Laune < 40, max 3/Tag.
static func erschoepfung_bindung_malus(laune: float, malus_heute: float) -> float:
	if laune >= Feel.ERSCHOEPFT_LAUNE_UNTER:
		return 0.0
	return minf(
		Feel.ERSCHOEPFT_BINDUNG_MALUS, maxf(0.0, Feel.ERSCHOEPFT_MALUS_MAX_TAG - malus_heute)
	)


## Lenkassistent (Barrierearmut, 0–30 %): zieht die Eingabe Richtung
## Ideallinie. delta_ideal = gewuenschte Lenkung der Ideallinie (−1..1).
static func lenkassistent(steer: float, delta_ideal: float, staerke: float) -> float:
	var s := clampf(staerke, 0.0, 0.3)
	return clampf(lerpf(steer, delta_ideal, s), -1.0, 1.0)


## Kamera-Hoehenversatz (Kap. 3.2): Landungs-Kick klingt in 0,15 s aus,
## Erschoepfung sackt 0,1 m, optionales Galopp-Wippen (Standard AUS).
static func kamera_y_offset(
	erschoepft: bool, landung_rest_s: float, wippen_an: bool, gangart: String, zeit_s: float
) -> float:
	var y := 0.0
	if erschoepft:
		y -= Feel.ERSCHOEPFT_KAMERA_SACK_M
	if landung_rest_s > 0.0:
		y -= Feel.LANDUNGS_KICK_M * clampf(landung_rest_s / Feel.LANDUNGS_KICK_S, 0.0, 1.0)
	if wippen_an and gangart == "galopp":
		y += sin(zeit_s * TAU * Feel.GALOPP_WIPP_HZ) * Feel.GALOPP_WIPP_AMP_M
	return y


static func _stat(stats: Dictionary, key: String) -> float:
	return clampf(_num(stats.get(key), 10.0), 1.0, 20.0)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
