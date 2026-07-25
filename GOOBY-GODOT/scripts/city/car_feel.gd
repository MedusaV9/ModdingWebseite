class_name CityCarFeel
extends RefCounted
## Fahrgefühl-Mathematik (W3a CITY) — 1:1-Port von GOOBY/src/city/carFeel.js
## (§C7.2-Zahlen VERBATIM) + den fürs Fahren nötigen DRIVE/DRIVE_TUNING-Werten
## aus GOOBY/src/data/constants.js. PURE (keine Nodes) — testbar im Runner.
## NEU gegenüber Web (M1-Auftrag): Rückwärtsgang (REVERSE_*) — das Web-Spiel
## hatte nur den Stuck-Watchdog; Zahlen hier geeicht, nicht aus der Referenz.

## Lenk-Tiefpass-Zeitkonstante τ = 120 ms (carFeel.FEEL.STEER_SMOOTH_TAU_S).
const STEER_SMOOTH_TAU_S := 0.12
## Yaw-Raten-Deckel: 90°/s (FEEL.STEER_RATE_CAP_RAD_S).
const STEER_RATE_CAP_RAD_S := 90.0 * PI / 180.0
## Spur-Assist: max. 8°/s Richtung Fahrbahn-Kardinale (FEEL.ASSIST_MAX_RATE_RAD_S).
const ASSIST_MAX_RATE_RAD_S := 8.0 * PI / 180.0
## Assist blendet linear auf 0 bei 25° Spieler-Absicht (FEEL.ASSIST_FADE_END_RAD).
const ASSIST_FADE_END_RAD := 25.0 * PI / 180.0
## Assist hart AUS ab 40 % Lenk-Auslenkung (FEEL.ASSIST_OFF_DEFLECTION).
const ASSIST_OFF_DEFLECTION := 0.4
## Chase-Cam: gedämpftes Positions-Follow k = 4.0/s (FEEL.CAM_POS_LERP_K).
const CAM_POS_LERP_K := 4.0
## Chase-Cam: Look-Ahead 6 m vor dem Auto (FEEL.CAM_LOOKAHEAD_M).
const CAM_LOOKAHEAD_M := 6.0
## FOV 55° → 60° über Tempo 9 → 13 m/s (FEEL.FOV_*).
const FOV_MIN_DEG := 55.0
const FOV_MAX_DEG := 60.0
const FOV_SPEED_FROM_MS := 9.0
const FOV_SPEED_TO_MS := 13.0

## Auto-Throttle: Basis 9 m/s, Rampe auf 13 (DRIVE.BASE_SPEED/MAX_SPEED).
const BASE_SPEED := 9.0
const MAX_SPEED := 13.0
## Sekunden sauberen Fahrens für die BASE→MAX-Rampe (DRIVE_TUNING.SPEED_RAMP_SEC).
const SPEED_RAMP_SEC := 22.0
## Yaw-Rate bei Voll-Lenkung (rad/s, DRIVE_TUNING.STEER_RATE).
const STEER_RATE := 1.9
## Bremsknopf: Verzögerung + Kriech-Minimum (DRIVE_TUNING.BRAKE_*).
const BRAKE_DECEL := 12.0
const BRAKE_MIN_SPEED := 1.2
## Beschleunigung Richtung Zieltempo: 5.5 m/s² rauf, 9 runter (carController update()).
const ACCEL_UP := 5.5
const ACCEL_DOWN := 9.0
## Weiche Wand-Kollision: Tempoverlust (DRIVE_TUNING.WALL_SPEED_MULT).
const WALL_SPEED_MULT := 0.55
## Spieler-Kollisionsradius vs. Wände (DRIVE_TUNING.CAR_RADIUS_M).
const CAR_RADIUS_M := 1.5
## Fahrbahnhöhe über Grund (DRIVE_TUNING.ROAD_Y) + Kamera-Offsets (CAM_BACK/HEIGHT).
const ROAD_Y := 0.4
const CAM_BACK := 10.5
const CAM_HEIGHT := 5.6
## Spurmitte-Abstand von der Straßenmitte (DRIVE_TUNING.LANE_OFFSET_M, Rechtsverkehr).
const LANE_OFFSET_M := 2.5
## Laterale Assist-Ease-Rate (DRIVE_TUNING.LANE_SNAP_LATERAL_RATE, 1/s).
const LANE_LATERAL_RATE := 1.8
## Modell-Skalierung Kenney-car-kit → Weltmeter (DRIVE_TUNING.CAR_SCALE).
const CAR_SCALE := 1.8
## Ambient-Verkehr (DRIVE_TUNING.TRAFFIC_SPEED m/s).
const TRAFFIC_SPEED := 6.5

## NEU (Godot-M1): Rückwärtsgang — Bremse GEDRÜCKT HALTEN im Stand legt den
## Rückwärtsgang ein (max. 3 m/s, direkte Lenkung ohne Assist).
const REVERSE_SPEED := 3.0
const REVERSE_ACCEL := 4.0

## Stuck-Watchdog (carController.js STUCK_*): Throttle drückt, Position steht.
const STUCK_MIN_CMD_SPEED := 2.0
const STUCK_MAX_MOVE_SPEED := 0.55
const STUCK_TRIGGER_SEC := 2.6


## Winkel nach (-PI, PI] wickeln (carController.wrapAngle).
static func wrap_angle(a: float) -> float:
	while a > PI:
		a -= TAU
	while a <= -PI:
		a += TAU
	return a


## Ein Tiefpass-Schritt der Lenk-Eingabe (τ = 120 ms, frameratenunabhängig):
## `smoothed` schließt (1 − e^(−dt/τ)) der Lücke pro Schritt.
static func smooth_steer(smoothed: float, target: float, dt: float) -> float:
	if not (dt > 0.0):
		return smoothed
	return smoothed + (target - smoothed) * (1.0 - exp(-dt / STEER_SMOOTH_TAU_S))


## Kommandierte Yaw-Rate (rad/s) aus der gefilterten Lenkung — Deckel 90°/s.
## Vorzeichen-erhaltend (positiv rein ⇒ positiv raus); die EINE Negation für
## „rechts auf dem Schirm = heading −“ sitzt im car_controller (Web-Kontrakt).
static func steer_yaw_rate(smoothed_steer: float, steer_rate: float, damp: float) -> float:
	var raw := smoothed_steer * steer_rate * damp
	return clampf(raw, -STEER_RATE_CAP_RAD_S, STEER_RATE_CAP_RAD_S)


## Tempo-Dämpfung der Lenkung (carController: 1 − 0.25·min(1, v/MAX)).
static func speed_damp(speed: float) -> float:
	return 1.0 - 0.25 * minf(1.0, speed / MAX_SPEED)


## Assist-Fade-Faktor 1 → 0 über 0° → 25° Absichtswinkel.
static func assist_fade(intent_rad: float) -> float:
	return maxf(0.0, 1.0 - absf(intent_rad) / ASSIST_FADE_END_RAD)


## Spur-Assist-Feder: Korrektur-Rate (rad/s, SIGNIERT Richtung Spur-Kardinale).
## Hart 0 bei ≥ 40 % Auslenkung — der Assist kämpft nie gegen den Daumen.
static func assist_rate(intent_rad: float, deflection: float) -> float:
	if absf(deflection) >= ASSIST_OFF_DEFLECTION:
		return 0.0
	return signf(intent_rad) * ASSIST_MAX_RATE_RAD_S * assist_fade(intent_rad)


## Frameratenunabhängiger Chase-Cam-Follow-Faktor (k = 4.0/s).
static func cam_follow_factor(dt: float) -> float:
	return 1.0 - exp(-CAM_POS_LERP_K * maxf(0.0, dt))


## Chase-Cam-FOV fürs Tempo: 55° bei ≤ 9 m/s → 60° bei ≥ 13 m/s, linear.
static func chase_fov(speed: float) -> float:
	var f := (speed - FOV_SPEED_FROM_MS) / (FOV_SPEED_TO_MS - FOV_SPEED_FROM_MS)
	return FOV_MIN_DEG + (FOV_MAX_DEG - FOV_MIN_DEG) * clampf(f, 0.0, 1.0)


## Auto-Throttle-Zieltempo bei Rampenzeit t (BASE 9 → MAX 13 über 22 s).
static func target_speed(ramp_time: float) -> float:
	var ramp := clampf(ramp_time / SPEED_RAMP_SEC, 0.0, 1.0)
	return BASE_SPEED + (MAX_SPEED - BASE_SPEED) * ramp


## Ein Tempo-Integrationsschritt (carController update(): Bremse 12 m/s² bis
## Kriechminimum, sonst asymmetrisch 5.5/9 m/s² Richtung Ziel).
static func step_speed(speed: float, target: float, braking: bool, dt: float) -> float:
	if braking:
		return maxf(BRAKE_MIN_SPEED, speed - BRAKE_DECEL * dt)
	var accel := ACCEL_UP if speed < target else ACCEL_DOWN
	return speed + signf(target - speed) * minf(absf(target - speed), accel * dt)
