class_name GyroParallax
extends Node
## W13C FOTOWERK (P1 Punkt 4, Web-Parität gyroParallax.js §C-SYS8):
## Gyro-/Pointer-Parallax für Hintergrund-Ebenen. Auf iOS liefert der
## Beschleunigungssensor die Neigung (Input.get_accelerometer), am Desktop
## fällt die Maus-Position ein (normiert −1…1, wie der Web-Pointer-Pfad).
##
## ADDITIVE Registrierungs-API: Ebenen melden sich mit
## `GyroParallax.registriere(ziel)` an — das Runtime-Node entsteht lazy im
## Baum (KEIN Autoload). Ziele mit `set_parallax_offset(px)` bekommen den
## Offset gepusht (AcWallpaper schiebt damit sein Pattern per Shader-Uniform);
## sonst wird die `position` um den Offset verschoben (Basis gemerkt).
##
## Stärke: Settings-Flag `game.parallax` (AppSettings), Fallback = das
## migrierte `settings.gyro` aus dem GameState (Web-V4-Import). Reduced
## Motion schaltet hart auf 0. Die Mathe-Helfer sind pur und zeitinjiziert
## (dt als Parameter) — headless testbar ohne Sensor.

## Web-Konstanten 1:1 (GYRO_PARALLAX in gyroParallax.js).
const TOTZONE_GRAD := 2.0
const EMPFINDLICHKEIT_M_PRO_GRAD := 0.008
const MAX_X_M := 0.12
const MAX_Y_M := 0.08
const ZEIGER_MAX_M := 0.06
const NEUTRAL_TAU_S := 4.0
const GLAETTUNG_TAU_S := 0.15
## Godot-Zusatz: Meter → Bildschirm-px (subtil: max ±24 px seitlich).
const PX_PRO_M := 200.0
## Beschleunigungs-Betrag, ab dem der Sensor als "vorhanden" gilt.
const SENSOR_MIN_G := 0.5

const RUNTIME_NAME := "GyroParallaxRuntime"

## Geteilte Runtime-Instanz (deferred add_child → Node-Lookup reicht nicht,
## wenn sich zwei Ebenen im selben Frame anmelden).
static var _runtime: GyroParallax = null

## Ziel-Einträge: {ref: WeakRef, staerke: float, basis: Vector2|null}.
var _ziele: Array[Dictionary] = []
var _neutral := Vector2.ZERO
var _neutral_gesetzt := false
var _offset_m := Vector2.ZERO


## Ebene anmelden (idempotent). `staerke` skaliert den Offset pro Ziel.
static func registriere(ziel: CanvasItem, staerke := 1.0) -> void:
	if ziel == null or not ziel.is_inside_tree():
		return
	var runtime := hole(ziel.get_tree())
	runtime.melde_an(ziel, staerke)


## Das geteilte Runtime-Node holen/erzeugen (lazy, unter /root).
static func hole(baum: SceneTree) -> GyroParallax:
	if _runtime != null and is_instance_valid(_runtime):
		return _runtime
	var vorhanden := baum.root.get_node_or_null(RUNTIME_NAME)
	if vorhanden is GyroParallax:
		_runtime = vorhanden
		return _runtime
	_runtime = GyroParallax.new()
	_runtime.name = RUNTIME_NAME
	baum.root.add_child.call_deferred(_runtime)
	return _runtime


# ---------------------------------------------------------- pure Mathe (Web)


## Totzone ohne Sprung bei ±2° (Web deadzoneDegrees).
static func totzone(grad: float) -> float:
	var betrag := absf(grad)
	if betrag <= TOTZONE_GRAD:
		return 0.0
	return signf(grad) * (betrag - TOTZONE_GRAD)


## Neigungswinkel → Meter-Offset, geklemmt (Web parallaxOffset):
## gamma = links/rechts, beta kippt invertiert (Kamera runter bei beta+).
static func offset_m(beta_grad: float, gamma_grad: float, neutral := Vector2.ZERO) -> Vector2:
	return _klemm_offset(beta_grad - neutral.x, gamma_grad - neutral.y, MAX_X_M, MAX_Y_M)


## Zeiger-Fallback (Maus): normiert −1…1 (ny: +1 = oben), gleiche
## Totzone/Empfindlichkeits-Pipeline, geklemmt auf ±0,06 m (Web-Parität).
static func zeiger_offset_m(nx: float, ny: float) -> Vector2:
	var rand_grad := TOTZONE_GRAD + ZEIGER_MAX_M / EMPFINDLICHKEIT_M_PRO_GRAD
	var x := clampf(nx, -1.0, 1.0)
	var y := clampf(ny, -1.0, 1.0)
	return _klemm_offset(-y * rand_grad, x * rand_grad, ZEIGER_MAX_M, ZEIGER_MAX_M)


## Exponentielle Glättung: alpha für Zeitkonstante tau (Web lerpAlpha).
static func glaettungs_alpha(dt_s: float, tau_s: float) -> float:
	var dt := maxf(dt_s, 0.0)
	var tau := maxf(tau_s, 0.000001)
	return 1.0 - exp(-dt / tau)


## Gravitationsvektor → (beta, gamma) in Grad: beta = Kippen vor/zurück,
## gamma = Rollen links/rechts (Portrait-Ruhelage: a ≈ (0, −g, 0)).
static func neigung_grad(beschleunigung: Vector3) -> Vector2:
	var beta := rad_to_deg(atan2(-beschleunigung.z, -beschleunigung.y))
	var gamma := rad_to_deg(atan2(beschleunigung.x, -beschleunigung.y))
	return Vector2(beta, gamma)


## Settings-Auflösung (pur, Duck-Typing): explizites `game.parallax` aus
## AppSettings gewinnt, sonst das migrierte `settings.gyro` (GameState).
static func setting_aktiv(app: Object, game_state: Object) -> bool:
	if app != null and app.has_method("get_setting"):
		var wert: Variant = app.get_setting("game.parallax", null)
		if wert != null:
			return bool(wert)
	if game_state != null and game_state.has_method("get_value"):
		return bool(game_state.get_value("settings.gyro", false))
	return false


static func _klemm_offset(
	beta_grad: float, gamma_grad: float, max_x: float, max_y: float
) -> Vector2:
	var dx := totzone(gamma_grad) * EMPFINDLICHKEIT_M_PRO_GRAD
	var dy := totzone(beta_grad) * EMPFINDLICHKEIT_M_PRO_GRAD
	return Vector2(clampf(dx, -max_x, max_x), clampf(-dy, -max_y, max_y))


# ------------------------------------------------------------------ Runtime


func _ready() -> void:
	# Ohne registrierte Ziele schläft der Frame-Tick (die Runtime lebt
	# dauerhaft unter /root — melde_an/melde_ab schalten ihn an/aus).
	# Aus _ziele abgeleitet, weil melde_an schon VOR dem (deferred)
	# Baum-Eintritt laufen kann.
	set_process(not _ziele.is_empty())


func melde_an(ziel: CanvasItem, staerke: float) -> void:
	set_process(true)
	for eintrag in _ziele:
		if (eintrag["ref"] as WeakRef).get_ref() == ziel:
			eintrag["staerke"] = staerke
			return
	_ziele.append({"ref": weakref(ziel), "staerke": staerke, "basis": null})


func melde_ab(ziel: CanvasItem) -> void:
	for i in range(_ziele.size() - 1, -1, -1):
		if (_ziele[i]["ref"] as WeakRef).get_ref() == ziel:
			_ziele.remove_at(i)
	set_process(not _ziele.is_empty())


func ziel_anzahl() -> int:
	return _ziele.size()


func _process(delta: float) -> void:
	var ziel_m := _ziel_offset_m(delta)
	var alpha := glaettungs_alpha(delta, GLAETTUNG_TAU_S)
	_offset_m += (ziel_m - _offset_m) * alpha
	_verteile(_offset_m * PX_PRO_M)


## Ziel-Offset dieses Frames: aus → 0, sonst Sensor (Neutral-Adaption τ=4 s)
## oder Maus-Fallback. Öffentlich, damit Tests den Schritt injizieren können.
func _ziel_offset_m(dt_s: float) -> Vector2:
	if not _ist_aktiv():
		_neutral_gesetzt = false
		return Vector2.ZERO
	var beschleunigung := Input.get_accelerometer()
	if beschleunigung.length() >= SENSOR_MIN_G:
		var winkel := neigung_grad(beschleunigung)
		if not _neutral_gesetzt:
			_neutral = winkel
			_neutral_gesetzt = true
		else:
			var alpha := glaettungs_alpha(dt_s, NEUTRAL_TAU_S)
			_neutral += (winkel - _neutral) * alpha
		return offset_m(winkel.x, winkel.y, _neutral)
	return _maus_offset_m()


func _maus_offset_m() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var groesse := viewport.get_visible_rect().size
	if groesse.x < 1.0 or groesse.y < 1.0:
		return Vector2.ZERO
	var maus := viewport.get_mouse_position()
	var nx := clampf(maus.x / groesse.x * 2.0 - 1.0, -1.0, 1.0)
	var ny := clampf(-(maus.y / groesse.y * 2.0 - 1.0), -1.0, 1.0)
	return zeiger_offset_m(nx, ny)


func _ist_aktiv() -> bool:
	if ThemeService.is_reduced_motion(self):
		return false
	return setting_aktiv(get_node_or_null("/root/AppSettings"), get_node_or_null("/root/GameState"))


func _verteile(offset_px: Vector2) -> void:
	for i in range(_ziele.size() - 1, -1, -1):
		var eintrag := _ziele[i]
		var ziel: Object = (eintrag["ref"] as WeakRef).get_ref()
		if ziel == null or not is_instance_valid(ziel):
			_ziele.remove_at(i)
			continue
		var anteil := offset_px * float(eintrag["staerke"])
		if ziel.has_method("set_parallax_offset"):
			ziel.set_parallax_offset(anteil)
		elif ziel is CanvasItem and "position" in ziel:
			if eintrag["basis"] == null:
				eintrag["basis"] = ziel.position
			ziel.position = (eintrag["basis"] as Vector2) + anteil
	# Leichen ausgeräumt und nichts mehr übrig → Tick schlafen legen.
	if _ziele.is_empty():
		set_process(false)
