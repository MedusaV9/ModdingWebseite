class_name RanchRideFeel
extends RefCounted
## Reitgefühl-Mathematik (RANCH-2) — PURE (keine Nodes), Handschrift wie
## scripts/city/car_feel.gd: ein sanftes "Fahrzeug" mit drei Gangarten
## (Schritt/Trab/Galopp), Tiefpass-Lenkung, asymmetrischer Beschleunigung,
## Sprungphysik, Ausdauer und Kopfnicken. Der Node-Controller
## (ride_controller.gd) und der Parcours konsumieren NUR diese Funktionen —
## alles hier ist im Runner testbar.
##
## RW-2-DLC (IDEAS-3 Kap. 2.4 + 3): die ZAHLEN des Ausbaus (Antritts-Kick,
## Tölt, Untergrund, Erschoepfung/Zweiter Wind, Sprung-Zonen, Kamera-Kicks)
## leben als Konstanten HIER; die zugehoerigen Stat-Formeln stehen im
## Schwester-Modul ride_stats.gd (RanchRideStats), weil dieser Kern sein
## 20-Methoden-Lint-Budget bereits ausschoepft.

## Gangarten in Schalt-Reihenfolge; Zieltempo in m/s. Tölt (5,8 m/s) ist
## die exklusive 5. Gangart des Tölterle — sie steht NICHT in GANGARTEN
## (Bestands-Schaltfolge bleibt), RanchRideStats.gangart_hoch schaltet
## sie fuer berechtigte Pferde zwischen Trab und Galopp ein.
const GANGARTEN: Array[String] = ["stand", "schritt", "trab", "galopp"]
const TEMPO := {"stand": 0.0, "schritt": 1.7, "trab": 4.2, "galopp": 8.5, "toelt": 5.8}

## Beschleunigung Richtung Zieltempo: sanft rauf, williger runter (m/s²).
const ACCEL_AUF := 3.0
const ACCEL_AB := 5.5
## DLC-Antritt je Gangart (IDEAS-3 Kap. 3.1); Galopp-Wert gilt NACH dem Kick.
const ACCEL_JE_GANGART := {"schritt": 2.0, "trab": 2.8, "galopp": 3.0, "toelt": 3.0}
## Antritts-Kick beim Angaloppieren: 0,8 s lang ACCEL_AUF·1,5 (Flitzewind 1,2 s).
const KICK_ACCEL := 4.5
const KICK_DAUER_S := 0.8

## Lenk-Tiefpass τ = 140 ms — Pferde lenken weicher als Autos.
const STEER_SMOOTH_TAU_S := 0.14
## Yaw-Rate bei Voll-Lenkung (rad/s) + harter Deckel.
const STEER_RATE := 1.7
const STEER_RATE_CAP_RAD_S := 100.0 * PI / 180.0
## Tempo-Dämpfung der Lenkung: bei Galopp lenkt es sich träger.
const STEER_SPEED_DAMP := 0.3

## Sprung: semi-implizites Euler, Boden bei y=0.
const SPRUNG_VY := 4.8
const GRAVITATION := -11.5
## Springen geht erst ab Trab-Tempo (m/s).
const SPRUNG_MIN_TEMPO := 3.0

## Ausdauer: Galopp zehrt, unterhalb Trab regeneriert sie.
const AUSDAUER_MAX := 100.0
const AUSDAUER_GALOPP_PRO_S := 7.0
const AUSDAUER_REGEN_PRO_S := 9.0
## Tölt traegt weiter als der Galopp (−3/s statt −7/s).
const AUSDAUER_TOELT_PRO_S := 3.0
## Leergaloppierte Pferde fallen in den Trab zurück.
const AUSDAUER_LEER_GANGART := "trab"
## Erst ab dieser Ausdauer darf wieder angaloppiert werden.
const AUSDAUER_GALOPP_AB := 20.0

## Erschoepfungsmoment (Tank = 0, IDEAS-3 Kap. 3.4): Schnauben + Kamera
## sackt ab; bei Laune < 40 kostet jede Erschoepfung 1 Bindung (max 3/Tag).
const ERSCHOEPFT_SCHNAUBEN_S := 2.0
const ERSCHOEPFT_KAMERA_SACK_M := 0.1
const ERSCHOEPFT_BINDUNG_MALUS := 1.0
const ERSCHOEPFT_MALUS_MAX_TAG := 3.0
const ERSCHOEPFT_LAUNE_UNTER := 40.0
## Zweiter Wind: 1×/Ritt bei Tank < 10 anhalten + streicheln → +25 sofort.
const ZWEITER_WIND_AB := 10.0
const ZWEITER_WIND_BONUS := 25.0
const ZWEITER_WIND_MAX_TEMPO := 0.2

## Sprung-Timing (IDEAS-3 Kap. 3.5): Absprungzonen VOR dem Hindernis (m).
const SPRUNG_PERFEKT_VON_M := 0.9
const SPRUNG_PERFEKT_BIS_M := 1.3
const SPRUNG_GUT_VON_M := 0.5
const SPRUNG_GUT_BIS_M := 1.9
const SPRUNG_PERFEKT_PUNKTE := 15
const SPRUNG_STANGE_CHANCE := 0.6

## Scheu-Moment (Kap. 1.3/2.4): kurzer Seitwaertshopser, Tempo −30 % fuer 2 s.
const SCHEU_DAUER_S := 0.5
const SCHEU_HOPS_M := 0.6
const SCHEU_TEMPO_MULT := 0.7
const SCHEU_TEMPO_S := 2.0

## Untergrund (Kap. 3.3): Tempo-Malus + Hufschlag-Charakter je Boden.
## sound-Ids zeigen auf assets/ranch/audio/sfx/<id>.ogg.
const UNTERGRUND := {
	"wiese": {"tempo_mult": 1.0, "sound": "huf_gras", "vol_db": -6.0, "pitch": 0.9},
	"sand": {"tempo_mult": 1.0, "sound": "huf_sand", "vol_db": -4.0, "pitch": 1.0},
	"holz": {"tempo_mult": 1.0, "sound": "huf_holz", "vol_db": 3.0, "pitch": 1.05},
	"stein": {"tempo_mult": 1.0, "sound": "huf_stein", "vol_db": 0.0, "pitch": 1.1},
	"wasser": {"tempo_mult": 0.85, "sound": "huf_sand", "vol_db": 0.0, "pitch": 1.0},
	"matsch": {"tempo_mult": 0.9, "sound": "huf_sand", "vol_db": -2.0, "pitch": 0.8},
	"schnee": {"tempo_mult": 1.0, "sound": "huf_gras", "vol_db": -9.0, "pitch": 0.85},
}

## Kopfnicken: Frequenz (Hz) und Amplitude (m) je Gangart; stand = Atmen.
## Tölt "schwebt": 2,8 Hz bei Amplitude 0,012 — fast glatt.
const NICK_HZ := {"stand": 0.35, "schritt": 1.4, "trab": 2.4, "galopp": 1.9, "toelt": 2.8}
const NICK_AMP := {"stand": 0.006, "schritt": 0.022, "trab": 0.045, "galopp": 0.07, "toelt": 0.012}

## Kamera: gedämpftes Follow + Blickwinkel-Kick über das Tempoband.
const CAM_POS_LERP_K := 4.5
const CAM_BACK := 5.4
const CAM_HEIGHT := 2.7
const FOV_MIN_DEG := 58.0
const FOV_MAX_DEG := 66.0
const FOV_TEMPO_VON := 4.2
const FOV_TEMPO_BIS := 8.5
## DLC-Kamera (Kap. 3.2): Landungs-Kick nach dem Sprung; das Galopp-
## Wippen ist eine OPT-IN-Option (Standard AUS — kein Screenshake beim
## Reiten, Bedienhilfen-Grundsatz).
const LANDUNGS_KICK_M := 0.06
const LANDUNGS_KICK_S := 0.15
const GALOPP_WIPP_AMP_M := 0.03
const GALOPP_WIPP_HZ := 7.0

## Staubpartikel-Anteil (0..1) je Gangart — Galopp wirbelt richtig.
const STAUB := {"stand": 0.0, "schritt": 0.0, "trab": 0.35, "galopp": 1.0, "toelt": 0.5}


## Winkel nach (-PI, PI] wickeln (carFeel-Muster).
static func wrap_angle(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a


## Nächsthöhere/-tiefere Gangart (an den Enden geklemmt).
static func gangart_hoch(gangart: String) -> String:
	var i := GANGARTEN.find(gangart)
	return GANGARTEN[mini(GANGARTEN.size() - 1, maxi(0, i) + 1)]


static func gangart_runter(gangart: String) -> String:
	var i := GANGARTEN.find(gangart)
	return GANGARTEN[maxi(0, (i if i >= 0 else 1) - 1)]


## Zieltempo einer Gangart; hohe Bindung galoppiert bis zu 6 % schneller
## (Perk aus RanchHorseCare.reit_perks).
static func zieltempo(gangart: String, tempo_mult := 1.0) -> float:
	var basis := float(TEMPO.get(gangart, 0.0))
	return basis * tempo_mult if gangart == "galopp" else basis


## Ein Tempo-Integrationsschritt Richtung Ziel (asymmetrisch, wie carFeel).
static func step_tempo(tempo: float, ziel: float, dt: float) -> float:
	var accel := ACCEL_AUF if tempo < ziel else ACCEL_AB
	return tempo + signf(ziel - tempo) * minf(absf(ziel - tempo), accel * dt)


## Ein Tiefpass-Schritt der Lenk-Eingabe (frameratenunabhängig).
static func smooth_steer(smoothed: float, target: float, dt: float) -> float:
	if not (dt > 0.0):
		return smoothed
	return smoothed + (target - smoothed) * (1.0 - exp(-dt / STEER_SMOOTH_TAU_S))


## Tempo-Dämpfung der Lenkung (1 − 0.3·min(1, v/Galopp)).
static func speed_damp(tempo: float) -> float:
	return 1.0 - STEER_SPEED_DAMP * minf(1.0, tempo / float(TEMPO["galopp"]))


## Kommandierte Yaw-Rate (rad/s) aus der gefilterten Lenkung, gedeckelt.
## Im Stand dreht kein Pferd auf der Stelle.
static func steer_yaw_rate(smoothed_steer: float, tempo: float) -> float:
	if tempo < 0.2:
		return 0.0
	var raw := smoothed_steer * STEER_RATE * speed_damp(tempo)
	return clampf(raw, -STEER_RATE_CAP_RAD_S, STEER_RATE_CAP_RAD_S)


## Darf aus diesem Zustand abgesprungen werden?
static func kann_springen(tempo: float, y: float) -> bool:
	return tempo >= SPRUNG_MIN_TEMPO and y <= 0.001


## Ein Sprungphysik-Schritt {y, vy}; am Boden geklemmt (y=0, vy=0).
static func step_sprung(state: Dictionary, dt: float) -> Dictionary:
	var vy := float(state["vy"]) + GRAVITATION * dt
	var y := float(state["y"]) + vy * dt
	if y <= 0.0:
		return {"y": 0.0, "vy": 0.0}
	return {"y": y, "vy": vy}


## Kenndaten eines vollen Sprungs bei Tempo v: {"flugzeit_s", "hoehe_m",
## "weite_m"} — Parcours-Fenster und Tests rechnen damit.
static func sprung_daten(tempo: float) -> Dictionary:
	var flugzeit := 2.0 * SPRUNG_VY / -GRAVITATION
	return {
		"flugzeit_s": flugzeit,
		"hoehe_m": SPRUNG_VY * SPRUNG_VY / (2.0 * -GRAVITATION),
		"weite_m": maxf(0.0, tempo) * flugzeit,
	}


## Ein Ausdauer-Schritt: Galopp zehrt, unterhalb Trab regeneriert
## (regen_mult = Bindungs-Perk). 0..100.
static func step_ausdauer(ausdauer: float, gangart: String, dt: float, regen_mult := 1.0) -> float:
	var a := ausdauer
	if gangart == "galopp":
		a -= AUSDAUER_GALOPP_PRO_S * dt
	elif gangart != "trab":
		a += AUSDAUER_REGEN_PRO_S * maxf(0.0, regen_mult) * dt
	return clampf(a, 0.0, AUSDAUER_MAX)


## Gangart nach dem Ausdauer-Check: leerer Tank zwingt in den Trab,
## Angaloppieren braucht mindestens AUSDAUER_GALOPP_AB.
static func gangart_nach_ausdauer(gewuenscht: String, ausdauer: float, war_galopp: bool) -> String:
	if gewuenscht != "galopp":
		return gewuenscht
	if ausdauer <= 0.0:
		return AUSDAUER_LEER_GANGART
	if not war_galopp and ausdauer < AUSDAUER_GALOPP_AB:
		return "trab"
	return "galopp"


## Kopfnick-Versatz (m) bei Schrittphase phase01 (0..1) und Gangart.
static func kopfnicken(phase01: float, gangart: String) -> float:
	var amp := float(NICK_AMP.get(gangart, 0.0))
	return -absf(sin(phase01 * PI)) * amp * 2.0 + amp


## Schrittfrequenz (Hz) einer Gangart — treibt Phase, Beine und Hufschläge.
static func schritt_hz(gangart: String) -> float:
	return float(NICK_HZ.get(gangart, 0.0))


## Anzahl Hufschlag-Momente zwischen zwei Phasenständen (je halbe Phase einer).
static func hufschlaege(phase_vorher: float, phase_nachher: float) -> int:
	if phase_nachher <= phase_vorher:
		return 0
	return int(floor(phase_nachher * 2.0)) - int(floor(phase_vorher * 2.0))


## Frameratenunabhängiger Kamera-Follow-Faktor.
static func cam_follow_factor(dt: float) -> float:
	return 1.0 - exp(-CAM_POS_LERP_K * maxf(0.0, dt))


## Blickwinkel fürs Tempo: 58° bis Trab, 66° im vollen Galopp, linear.
static func fov_fuer_tempo(tempo: float) -> float:
	var f := (tempo - FOV_TEMPO_VON) / (FOV_TEMPO_BIS - FOV_TEMPO_VON)
	return FOV_MIN_DEG + (FOV_MAX_DEG - FOV_MIN_DEG) * clampf(f, 0.0, 1.0)


## Staub-Anteil (0..1) je Gangart.
static func staub_anteil(gangart: String) -> float:
	return float(STAUB.get(gangart, 0.0))


## Position (x,z) weich in ein Rechteck klemmen (Koppel-Grenzen; RANCH-1
## setzt center/half über RanchRideController.set_bounds).
static func clamp_bounds(pos: Vector2, center: Vector2, half: Vector2, rand := 0.6) -> Vector2:
	var hx := maxf(0.5, half.x - rand)
	var hz := maxf(0.5, half.y - rand)
	return Vector2(
		clampf(pos.x, center.x - hx, center.x + hx), clampf(pos.y, center.y - hz, center.y + hz)
	)
