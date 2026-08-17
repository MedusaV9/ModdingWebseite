class_name RanchRideTouch
extends RefCounted
## Touch-Steuerungs-Mathematik fuers Reiten (RW-2, IDEAS-3 Kap. 3.6) —
## PURE: Punkte/Zeiten rein, Werte raus; das HUD (ride_hud.gd) ist nur
## Verdrahtung. Alles ist mit EINEM Daumen bedienbar; Masse in dp,
## der Aufrufer liefert die dp→px-Skala (Content-Scale des Viewports).
##
## Standard-Layout "Zwei Daumen": links Floating-Stick (nur X lenkt),
## rechts Gangart-Wische (hoch/runter) + Sprung-Button.
## Alternative "Zuegel-Modus" (eine Hand): Auto-Vorwaerts im Schritt,
## Tippen-und-Halten = schneller, Loslassen = eine Gangart runter,
## Lenken per Gyro ODER Wischen.

## Floating-Stick: Radius 64 dp, Deadzone 12 %, nur X-Achse lenkt.
const STICK_RADIUS_DP := 64.0
const STICK_DEADZONE := 0.12

## Gangart-Wisch: Mindestweg 24 dp innerhalb 250 ms.
const WISCH_MIN_DP := 24.0
const WISCH_MAX_MS := 250.0

## Sprung-Button 72 dp; skalierbar 64–96 dp (Bedienhilfe).
const SPRUNG_BUTTON_DP := 72.0
const BUTTON_MIN_DP := 64.0
const BUTTON_MAX_DP := 96.0

## Zuegel-Modus: Halten 0–0,4 s = Trab, laenger = Galopp.
const ZUEGEL_TRAB_BIS_S := 0.4

## Gyro-Lenkung: ±15° = Vollausschlag, Deadzone 3°.
const GYRO_VOLL_GRAD := 15.0
const GYRO_DEADZONE_GRAD := 3.0


## Stick-Auslenkung → Lenk-Eingabe (−1..1): Der Stick erscheint am
## Aufsetzpunkt ("floating"); nur die X-Achse lenkt, 12 % Deadzone,
## dahinter linear bis zum Radius.
static func stick_lenkung(start_px: Vector2, aktuell_px: Vector2, dp_skala: float) -> float:
	var radius := STICK_RADIUS_DP * maxf(0.001, dp_skala)
	var anteil := clampf((aktuell_px.x - start_px.x) / radius, -1.0, 1.0)
	if absf(anteil) < STICK_DEADZONE:
		return 0.0
	var nutz := (absf(anteil) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
	return signf(anteil) * clampf(nutz, 0.0, 1.0)


## Wisch-Erkennung: "hoch" | "runter" | "" (kein gueltiger Wisch).
## Vertikaler Weg >= 24 dp innerhalb 250 ms, sonst nichts.
static func wisch_richtung(
	start_px: Vector2, ende_px: Vector2, dauer_ms: float, dp_skala: float
) -> String:
	if dauer_ms > WISCH_MAX_MS or dauer_ms < 0.0:
		return ""
	var weg := (ende_px.y - start_px.y) / maxf(0.001, dp_skala)
	if absf(weg) < WISCH_MIN_DP:
		return ""
	return "hoch" if weg < 0.0 else "runter"


## Zuegel-Modus: Gangart-Wunsch waehrend des Haltens (Halten unter 0,4 s
## = Trab, darueber Galopp); vor dem Tippen gilt Auto-Schritt.
static func zuegel_gangart(halte_s: float) -> String:
	if halte_s <= 0.0:
		return "schritt"
	return "trab" if halte_s <= ZUEGEL_TRAB_BIS_S else "galopp"


## Zuegel-Modus: eine Gangart runter beim Loslassen.
static func zuegel_loslassen(gangart: String, kann_toelt := false) -> String:
	return RanchRideStats.gangart_runter(gangart, kann_toelt)


## Gyro-Lenkung (−1..1): ±15° Neigung = Vollausschlag, 3° Deadzone.
static func gyro_lenkung(neigung_grad: float) -> float:
	if absf(neigung_grad) < GYRO_DEADZONE_GRAD:
		return 0.0
	var nutz := (absf(neigung_grad) - GYRO_DEADZONE_GRAD) / (GYRO_VOLL_GRAD - GYRO_DEADZONE_GRAD)
	return signf(neigung_grad) * clampf(nutz, 0.0, 1.0)


## Button-Groesse (dp) auf das Bedienhilfen-Band 64–96 klemmen.
static func button_dp(wunsch_dp: float) -> float:
	return clampf(wunsch_dp, BUTTON_MIN_DP, BUTTON_MAX_DP)


## Linkshaender-Spiegelung: X-Koordinate an der Viewport-Mitte spiegeln.
static func spiegel_x(x_px: float, breite_px: float, linkshaender: bool) -> float:
	return breite_px - x_px if linkshaender else x_px


## Pulsiert der Sprung-Button? (Absprungzone naht: Distanz in m.)
static func sprung_button_pulsiert(dist_zum_hindernis_m: float) -> bool:
	return dist_zum_hindernis_m > 0.0 and dist_zum_hindernis_m <= 6.0
