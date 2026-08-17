class_name BallLogic
extends RefCounted
## Ball-Wurf-Logik (W13/BALL, EVAL-Restliste #17) — PURE Port der Web-Referenz
## GOOBY/src/home/interactions.js (flickToVelocity/stepBall/maybeFetch) plus
## Tuning aus GOOBY/src/data/constants.js (CARE_TUNING.BALL, INTERACT.BALL_*).
##
## Alles hier ist deterministisch und headless-testbar: keine OS-Uhr (now_ms
## kommt vom Aufrufer), kein Zufall (der Node injiziert seinen RNG nur für
## die Spruch-Auswahl), keine Nodes. Koordinaten sind LOKAL zum Spawn-Anker
## (Web-Konvention) — der Node addiert den Welt-Spawn selbst drauf.
##
## Zustandsmaschine (ein Wurf-Zyklus):
##   RUHT → (werfen) → FLIEGT → (liegt nah genug) → GOOBY_HOLT
##        → (Kopfstoß) → BRINGT_ZURUECK → (liegt) → RUHT
## Liegt der Ball zu weit weg / Cooldown aktiv, geht FLIEGT direkt → RUHT
## (Web: maybeFetch bricht ab, der Ball bleibt einfach liegen).

const Stats := preload("res://scripts/logic/stats.gd")
const WeightLogic := preload("res://scripts/logic/weight.gd")

## Zustände (Strings, damit Tests/Debug sie lesbar sehen).
const RUHT := "RUHT"
const FLIEGT := "FLIEGT"
const GOOBY_HOLT := "GOOBY_HOLT"
const BRINGT_ZURUECK := "BRINGT_ZURUECK"

## Web CARE_TUNING.BALL — Zahlen 1:1 (constants.js).
const GRAVITY := 6.5
const RESTITUTION := 0.55
const FRICTION := 1.6
const RADIUS := 0.11
const FLICK_VEL_SCALE := 0.0035
const MAX_SPEED := 6.0
const BOUND_X := 1.55
const BOUND_Z_MIN := -1.15
const BOUND_Z_MAX := 1.35
const REST_SPEED := 0.18
## Web: vel.y < 0.25 nach dem Bodenkontakt = Mikro-Hopser abschneiden.
const MIN_BOUNCE_VY := 0.25
## Web INTERACT: +3 Spaß pro Apport, 15 s Cooldown zwischen Apports.
const BALL_FUN := 3.0
const BALL_COOLDOWN_SEC := 15
## Web CARE_TUNING.CHASE_MAX_DIST + maybeFetch-Mindestabstand.
const CHASE_MIN_DIST := 0.05
const CHASE_MAX_DIST := 3.2
## Web maybeFetch-Kopfstoß: flickToVelocity({vx: -pos.x*260, vy: -640}).
const RETURN_VX_SCALE := 260.0
const RETURN_VY := -640.0
## Web tick: dt-Deckel 80 ms gegen Tab-Wechsel-Sprünge.
const MAX_DT := 0.08

## Ergebnisse von landung_verarbeiten().
const LANDUNG_APPORT := "apport"
const LANDUNG_LIEGEN := "liegen"
const LANDUNG_HEIM := "heim"

## Knuffige Apport-Sprüche (strings/de/ball.json) — Auswahl via Injektions-RNG.
const SPRUCH_KEYS: Array[String] = ["ball.apport1", "ball.apport2", "ball.apport3"]

var zustand := RUHT
## Position/Geschwindigkeit LOKAL zum Spawn-Anker (Web-Konvention, Meter).
var pos := Vector3(0.0, RADIUS, 0.0)
var vel := Vector3.ZERO
var cooldown_bis_ms := 0


## Screen-Flick (px/s, Screen-Y nach unten) → Abwurf-Geschwindigkeit (m/s).
## Web flickToVelocity: Y immer mindestens 0.8 (auch flache Flicks fliegen
## in einem Bogen), Betrag auf MAX_SPEED geklemmt.
static func flick_to_velocity(flick_px: Vector2) -> Vector3:
	var v := Vector3(
		flick_px.x * FLICK_VEL_SCALE,
		maxf(0.8, -flick_px.y * FLICK_VEL_SCALE),
		-absf(flick_px.y * FLICK_VEL_SCALE) * 0.35
	)
	var mag := v.length()
	if mag > MAX_SPEED:
		v *= MAX_SPEED / mag
	return v


## PURE Apport-Wirkung (Web maybeFetch-Callback): Spaß +3 (geklemmt),
## Gewicht −0.2 (§B5 — beim pummeligen Gooby purzelt so ein Pfund),
## `balls`-Lifetime-Counter +1 (Profil-Statistik + Sticker-Conds).
## Mutiert `state` in place; Rückgabe {fun_gain, balls, weight}.
static func apply_apport_reward(state: Dictionary) -> Dictionary:
	var gooby: Variant = state.get("gooby", {})
	var fun_gain := 0.0
	var weight := WeightLogic.DEFAULT
	if gooby is Dictionary:
		var before: Dictionary = gooby.get("stats", {}) if gooby.get("stats") is Dictionary else {}
		var after := Stats.apply_deltas(before, {"fun": BALL_FUN})
		fun_gain = float(after.get("fun", 0.0)) - Stats.clamp_stat(before.get("fun"))
		gooby["stats"] = after
		weight = WeightLogic.on_ball_fetch(gooby.get("weight", WeightLogic.DEFAULT))
		gooby["weight"] = weight
	var counters := _counters(state)
	counters["balls"] = int(_num(counters.get("balls"))) + 1
	return {"fun_gain": fun_gain, "balls": int(counters["balls"]), "weight": weight}


## Spruch-Key für den Apport-Moment — Zufall NUR über den injizierten RNG.
static func spruch_key(rng: RandomNumberGenerator) -> String:
	return SPRUCH_KEYS[rng.randi_range(0, SPRUCH_KEYS.size() - 1)]


## Wurf starten (nur aus RUHT — Doppel-Wurf während FLIEGT/Apport ist tabu).
func werfen(flick_px: Vector2) -> bool:
	if zustand != RUHT:
		return false
	vel = flick_to_velocity(flick_px)
	zustand = FLIEGT
	return true


## Ein ballistischer Integrationsschritt (Web stepBall 1:1): Schwerkraft,
## Bodenaufprall mit Dämpfung + Reibung, Wand-Klemmen relativ zum Spawn.
## Rückgabe {bounced, resting}; außerhalb von Flug-Zuständen ein No-op.
func step(dt: float) -> Dictionary:
	if zustand != FLIEGT and zustand != BRINGT_ZURUECK:
		return {"bounced": false, "resting": false}
	var t := minf(dt, MAX_DT)
	var bounced := false
	vel.y -= GRAVITY * t
	pos += vel * t
	if pos.y < RADIUS:
		pos.y = RADIUS
		if vel.y < 0.0:
			vel.y = -vel.y * RESTITUTION
			if vel.y < MIN_BOUNCE_VY:
				vel.y = 0.0
			else:
				bounced = true
		var drag := maxf(0.0, 1.0 - FRICTION * t)
		vel.x *= drag
		vel.z *= drag
	if absf(pos.x) > BOUND_X:
		pos.x = signf(pos.x) * BOUND_X
		vel.x = -vel.x * RESTITUTION
		bounced = true
	if pos.z < BOUND_Z_MIN:
		pos.z = BOUND_Z_MIN
		vel.z = -vel.z * RESTITUTION
		bounced = true
	elif pos.z > BOUND_Z_MAX:
		pos.z = BOUND_Z_MAX
		vel.z = -vel.z * RESTITUTION
		bounced = true
	var on_floor := pos.y - RADIUS < 0.02
	var resting := on_floor and vel.length() < REST_SPEED
	if resting:
		vel = Vector3.ZERO
	return {"bounced": bounced, "resting": resting}


## Der Ball liegt: entscheiden, was passiert (Web maybeFetch-Gates).
## dist_zu_gooby = horizontale Distanz Gooby↔Ball in Metern.
func landung_verarbeiten(dist_zu_gooby: float, now_ms: int) -> String:
	if zustand == BRINGT_ZURUECK:
		zustand = RUHT
		return LANDUNG_HEIM
	if zustand != FLIEGT:
		return LANDUNG_LIEGEN
	var zu_frueh := now_ms < cooldown_bis_ms
	var ausser_reichweite := dist_zu_gooby < CHASE_MIN_DIST or dist_zu_gooby > CHASE_MAX_DIST
	if zu_frueh or ausser_reichweite:
		zustand = RUHT
		return LANDUNG_LIEGEN
	zustand = GOOBY_HOLT
	return LANDUNG_APPORT


## Gooby ist da und stupst den Ball mit dem Kopf zurück Richtung Spawn
## (Web: flickToVelocity({vx: -pos.x*260, vy: -640})). Setzt den Cooldown
## und startet den Rückflug; Rückgabe = neue Geschwindigkeit.
func kopfstoss(now_ms: int) -> Vector3:
	if zustand != GOOBY_HOLT:
		return Vector3.ZERO
	vel = flick_to_velocity(Vector2(-pos.x * RETURN_VX_SCALE, RETURN_VY))
	zustand = BRINGT_ZURUECK
	cooldown_bis_ms = now_ms + BALL_COOLDOWN_SEC * 1000
	return vel


## Gooby kann gerade nicht kommen (beschäftigt/Baumodus/kein Runner) —
## der Ball bleibt einfach liegen (Web: maybeFetch bricht bei goobyBusy ab).
func apport_abgebrochen() -> void:
	if zustand == GOOBY_HOLT:
		zustand = RUHT


## Zurück auf Anfang (Raumwechsel/Abbruch) — Cooldown bleibt bewusst stehen.
func reset() -> void:
	zustand = RUHT
	pos = Vector3(0.0, RADIUS, 0.0)
	vel = Vector3.ZERO


static func _counters(state: Dictionary) -> Dictionary:
	if not (state.get("achievements") is Dictionary):
		state["achievements"] = {"counters": {}}
	var achievements: Dictionary = state["achievements"]
	if not (achievements.get("counters") is Dictionary):
		achievements["counters"] = {}
	return achievements["counters"]


static func _num(value: Variant) -> float:
	return float(value) if (value is int or value is float) else 0.0
