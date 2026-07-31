class_name DoorTravelFahrt
extends Node3D
## W15/DOORTRAVEL (Doc A §1.4): additive Tür-Fahrt — der Zielraum wird als
## ZWEITE Szene neben dem Quellraum gemountet, die Kamera fährt auf einer
## Path3D-Kurve („CamPath") vom Quell-Blick DURCH den Türrahmen in den
## Ziel-Blick, Gooby läuft sichtbar voraus; danach entlädt der Router den
## Quellraum. Die Fahrt ist eine INNERE Variante von DOOR_TRAVEL im
## SceneRouter — API/Signale/Timeouts des Routers bleiben unangetastet,
## und der bewährte Tür-Wisch bleibt Fallback-Codepfad (Reduced Motion,
## Low-End-Gerät, additive Ladezeit über LADE_BUDGET_MS, fremde Szenen).
##
## Architektur (der Kniff): der ZIELRAUM wird ganz normal an seinem
## endgültigen Platz gemountet (Ursprung des Mounts — HomeCameraRig/GridData
## clampen raumlokal und setzen „Raum am Ursprung" voraus). Stattdessen wird
## der STERBENDE Quellraum als Gast per Tür-Anker-Ausrichtung
## (RoomDefs.door_anker, Tür auf Tür, Innenrichtungen entgegengesetzt) an
## die Ziel-Tür umgesetzt und die Fahrt-Kamera mit derselben
## Starrkörper-Änderung nachgeführt — der Blick auf den Quellraum bleibt
## dadurch pixelidentisch, und nach der Fahrt steht der Zielraum OHNE
## Re-Rooting im kanonischen Zustand. Ziel-Gooby und Ziel-Tür sind während
## der Fahrt verborgen (Doppelgänger/Z-Fighting mit der offenen Quell-Tür);
## die Übergabe stellt beide her und lässt das Türblatt hinter Gooby sanft
## zufallen. Die Kamera bleibt am Türrahmen bewusst UNTER Türsturz (2,0 m)
## und DeckenFade-Schwelle (2,85 m) — die Decke flackert nicht (W14).
##
## Pure Mathe (fallback_grund/ziel_ausrichtung/kamera_kurve/…) ist static
## und headless-testbar (tests/unit/test_w15_doortravel.gd); den Node-Teil
## (vorbereiten/abfahren) ruft ausschließlich der SceneRouter.

## Zeitbudget fürs additive threaded Load (ab Reisebeginn gemessen) —
## darüber übernimmt der Tür-Wisch (der lädt wie bisher fertig).
const LADE_BUDGET_MS := 250
## Fahrtdauer: Kurvenlänge / Tempo, geklemmt auf 0,9–1,2 s (Auftrag §1).
const DAUER_MIN_S := 0.9
const DAUER_MAX_S := 1.2
const TEMPO_M_S := 18.0
## Kamera-/Blickhöhe am Türrahmen: unter Türsturz (2,0 m) und klar unter
## der DeckenFade-Schwelle (HOEHE_FREI_AB_M 2,85) — kein Decken-Flackern.
const KAMERA_TUER_HOEHE_M := 1.45
const BLICK_TUER_HOEHE_M := 1.2
## Gooby-Ziel hinter der Tür = RoomBase-Spawnpunkt (door_pos + inward*0.7).
const SPAWN_ABSTAND_M := 0.7
## Ab diesem Fahrt-Anteil blendet die Fahrt-Kamera auf die LIVE-Zielkamera
## (die dem frisch gespawnten Ziel-Gooby entgegenfährt) — nahtlose Übergabe.
const ANGLEICH_AB := 0.65
## Bezier-Griffweiten der Kurve (Anteil der Segmentlängen).
const START_GRIFF_ANTEIL := 0.3
const TUER_GRIFF_ANTEIL := 0.45
## Gooby läuft der Kamera voraus: sein Schritt dauert diesen Fahrt-Anteil.
const GOOBY_VORLAUF_ANTEIL := 0.6
## Blickweite für Start-/Ziel-Blickpunkte vor der jeweiligen Kamera.
const BLICK_WEITE_M := 6.0

var _quelle: Node3D
var _ziel: Node3D
var _cam: Camera3D
var _ziel_cam: Camera3D
var _ziel_gooby: Node3D
var _ziel_tuer: Node3D
var _pfad: Path3D
var _tuer_welt := Vector3.ZERO
var _richtung := Vector3.FORWARD
var _kaputt := false

## ── Pure Fallback-/Anker-/Kurven-Mathe (testbar) ─────────────────────────────


## Warum kein Fahrt-Start? "" = Fahrt erlaubt; sonst "reduced_motion" |
## "low_end" | "ladezeit" (Wisch-Fallback, kein Regression-Risiko).
static func fallback_grund(
	reduced: bool, low_end: bool, lade_ms: int, budget_ms := LADE_BUDGET_MS
) -> String:
	if reduced:
		return "reduced_motion"
	if low_end:
		return "low_end"
	if lade_ms > budget_ms:
		return "ladezeit"
	return ""


## Low-End-Gerät? Duck-typed über das Quality-Autoload (RW-7): Fahrt nur,
## wenn das wirksame Grafik-Bündel NICHT die „niedrig"-Stufe ist.
static func ist_low_end(wurzel: Node) -> bool:
	var quality := wurzel.get_node_or_null("Quality")
	if quality == null or not quality.has_method("applied_bundle"):
		return false
	return QualityProfiles.stufe_von(quality.applied_bundle()) == "niedrig"


## Transform, der Raum B (Anker-Pos/Innenrichtung raumlokal) so an Raum A
## ansetzt, dass beide Türmitten aufeinanderliegen und die Innenrichtungen
## entgegengesetzt zeigen (Rückseite an Rückseite durch dieselbe Öffnung).
static func ziel_ausrichtung(
	a_pos: Vector3, a_inward: Vector3, b_pos: Vector3, b_inward: Vector3
) -> Transform3D:
	var winkel := b_inward.signed_angle_to(-a_inward, Vector3.UP)
	var basis := Basis(Vector3.UP, winkel)
	return Transform3D(basis, a_pos - basis * b_pos)


## Kamerakurve Start → Türrahmen → Ziel: die Türrahmen-Griffe liegen exakt
## auf der Durchgangsrichtung — die Kamera passiert den Rahmen senkrecht.
static func kamera_kurve(
	start: Vector3, tuer: Vector3, richtung: Vector3, ende: Vector3
) -> Curve3D:
	var kurve := Curve3D.new()
	var r := richtung.normalized()
	var griff := minf((tuer - start).length(), (ende - tuer).length()) * TUER_GRIFF_ANTEIL
	kurve.add_point(start, Vector3.ZERO, (tuer - start) * START_GRIFF_ANTEIL)
	kurve.add_point(tuer, -r * griff, r * griff)
	kurve.add_point(ende, (tuer - ende) * START_GRIFF_ANTEIL, Vector3.ZERO)
	return kurve


## Fahrtdauer aus der Kurvenlänge (geklemmt 0,9–1,2 s).
static func fahrt_dauer(kurven_laenge_m: float) -> float:
	return clampf(kurven_laenge_m / TEMPO_M_S, DAUER_MIN_S, DAUER_MAX_S)


## Blickpunkt der Fahrt (quadratische Bezier Start-Blick → Tür → Ziel-Blick).
static func blick_punkt(t: float, start: Vector3, tuer: Vector3, ende: Vector3) -> Vector3:
	var u := clampf(t, 0.0, 1.0)
	return start.lerp(tuer, u).lerp(tuer.lerp(ende, u), u)


## Ease der Fahrt (sanft rein + raus).
static func ease_fahrt(t: float) -> float:
	return smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))


## Gewicht der Angleichung an die Live-Zielkamera (0 bis ANGLEICH_AB, dann
## weich auf 1 — bei t=1 ist die Fahrt-Kamera exakt die Zielkamera).
static func angleich_gewicht(t: float, ab := ANGLEICH_AB) -> float:
	return smoothstep(ab, 1.0, clampf(t, 0.0, 1.0))


## Fahrt-Plan aus Quellszene + Router-Ziel + goto-Params — {} wenn die
## Reise nicht fahrbar ist (fremde Szene, kein Raum-Ziel, Tür unbekannt,
## Tür führt woandershin). Duck-typing statt RoomBase-Import: der Router
## bleibt von Home-Interna entkoppelt, Fixtures fallen auf den Wisch zurück.
static func fahrt_plan(quelle: Node, target: StringName, params: Dictionary) -> Dictionary:
	if not (quelle is Node3D):
		return {}
	for methode in ["gooby", "camera_rig", "room_def"]:
		if not quelle.has_method(methode):
			return {}
	var rig: Variant = quelle.call("camera_rig")
	if rig == null or not (rig.get("camera") is Camera3D):
		return {}
	if not String(target).begins_with(RoomDefs.ROUTE_PREFIX):
		return {}
	var ziel_raum := String(target).trim_prefix(RoomDefs.ROUTE_PREFIX)
	var ziel_tuer_id := str(params.get("door_id", ""))
	var ziel_tuer_def := RoomDefs.door(ziel_raum, ziel_tuer_id)
	if str(ziel_tuer_def.get("to", "")) != str(quelle.get("room_id")):
		return {}
	var quell_tuer_id := str(ziel_tuer_def.get("to_door", ""))
	var quell_anker := RoomDefs.door_anker(str(quelle.get("room_id")), quell_tuer_id)
	var ziel_anker := RoomDefs.door_anker(ziel_raum, ziel_tuer_id)
	if quell_anker.is_empty() or ziel_anker.is_empty():
		return {}
	return {
		"quell_anker": quell_anker,
		"ziel_anker": ziel_anker,
		"quell_tuer_name": "Door_%s" % quell_tuer_id,
		"ziel_tuer_name": "Door_%s" % ziel_tuer_id,
	}


## ── Fahrt-Ablauf (ruft der SceneRouter) ──────────────────────────────────────


## Direkt nach dem additiven Mount des Ziels aufrufen (gleicher Frame!):
## richtet den Quellraum als Gast an der Ziel-Tür aus, übernimmt die Sicht
## mit einer nachgeführten Fahrt-Kamera und verbirgt die Ziel-Doppelgänger.
func vorbereiten(quelle: Node3D, ziel: Node3D, plan: Dictionary) -> void:
	_quelle = quelle
	_ziel = ziel
	var quell_anker: Dictionary = plan["quell_anker"]
	var ziel_anker: Dictionary = plan["ziel_anker"]
	var ziel_pos: Vector3 = ziel_anker["pos"]
	var ziel_inward: Vector3 = ziel_anker["inward"]
	var zt := ziel.global_transform
	_tuer_welt = zt * ziel_pos
	_richtung = (zt.basis * ziel_inward).normalized()
	var quell_cam := _kamera_von(quelle)
	_ziel_cam = _kamera_von(ziel)
	if quell_cam == null or _ziel_cam == null:
		_kaputt = true
	# Quellraum als Gast Tür-auf-Tür an den Zielraum setzen; sein Rig
	# einfrieren (dessen Clamp-Rechtecke gelten nur am Raum-Ursprung).
	var quell_alt := quelle.global_transform
	var quell_neu := (
		zt * ziel_ausrichtung(ziel_pos, ziel_inward, quell_anker["pos"], quell_anker["inward"])
	)
	quelle.global_transform = quell_neu
	var quell_rig: Variant = quelle.call("camera_rig") if quelle.has_method("camera_rig") else null
	if quell_rig is Node:
		(quell_rig as Node).set_process(false)
		(quell_rig as Node).set_process_unhandled_input(false)
	# Ziel-Doppelgänger verbergen: Gooby wartet unsichtbar am Spawn, die
	# Ziel-Tür (deckungsgleich mit der offenen Quell-Tür) bleibt weg.
	if ziel.has_method("gooby"):
		_ziel_gooby = ziel.gooby()
	if _ziel_gooby != null:
		_ziel_gooby.visible = false
		if _ziel_gooby.has_method("set_wander_enabled"):
			_ziel_gooby.set_wander_enabled(false)
	_ziel_tuer = ziel.get_node_or_null(str(plan["ziel_tuer_name"]))
	if _ziel_tuer != null:
		_ziel_tuer.visible = false
	# Fahrt-Kamera: übernimmt die Quellsicht pixelidentisch (Starrkörper-
	# Nachführung der Gast-Umsetzung), Input ruht solange (Blocker).
	_cam = Camera3D.new()
	_cam.name = "FahrtKamera"
	add_child(_cam)
	if quell_cam != null:
		_cam.fov = quell_cam.fov
		_cam.near = quell_cam.near
		_cam.far = quell_cam.far
		_cam.global_transform = quell_neu * quell_alt.affine_inverse() * quell_cam.global_transform
	_cam.make_current()
	_pfad = Path3D.new()
	_pfad.name = "CamPath"
	var tuer_cam := _tuer_welt + Vector3.UP * KAMERA_TUER_HOEHE_M
	var ende := _ziel_cam.global_position if _ziel_cam != null else tuer_cam
	_pfad.curve = kamera_kurve(_cam.global_position, tuer_cam, _richtung, ende)
	add_child(_pfad)
	_blocker_bauen()


## Die eigentliche Fahrt (awaitbar). `sofort` (Force-Reveal/Hard-Timeout)
## springt direkt zur Übergabe — nie Deadlock, Router-Semantik unverändert.
func abfahren(sofort := false) -> void:
	if sofort or _kaputt or not is_instance_valid(_ziel_cam):
		_uebergabe()
		return
	var laenge := _pfad.curve.get_baked_length()
	var dauer := fahrt_dauer(laenge)
	_gooby_vorauslaufen(dauer * GOOBY_VORLAUF_ANTEIL)
	var blick_start := _cam.global_position - _cam.global_basis.z * BLICK_WEITE_M
	var blick_tuer := _tuer_welt + Vector3.UP * BLICK_TUER_HOEHE_M
	var t := 0.0
	while t < 1.0:
		await get_tree().process_frame
		if not is_instance_valid(_ziel_cam) or not is_inside_tree():
			break
		t = minf(t + get_process_delta_time() / dauer, 1.0)
		var e := ease_fahrt(t)
		_cam.global_position = _pfad.curve.sample_baked(e * laenge)
		var blick_ende := _ziel_cam.global_position - _ziel_cam.global_basis.z * BLICK_WEITE_M
		var blick := blick_punkt(e, blick_start, blick_tuer, blick_ende)
		if _cam.global_position.distance_squared_to(blick) > 0.0001:
			_cam.look_at(blick)
		# Endanflug: weich auf die LIVE-Zielkamera (folgt ihrem Gooby) —
		# bei t=1 exakt deckungsgleich, die Übergabe ist unsichtbar.
		var w := angleich_gewicht(t)
		if w > 0.0:
			_cam.global_position = _cam.global_position.lerp(_ziel_cam.global_position, w)
			var q := Quaternion(_cam.global_basis).slerp(Quaternion(_ziel_cam.global_basis), w)
			_cam.global_basis = Basis(q)
	_uebergabe()


## ── intern ───────────────────────────────────────────────────────────────────


## Gooby läuft der Kamera voraus durch den Rahmen zum RoomBase-Spawnpunkt
## des Zielraums — dort steht (noch unsichtbar) bereits sein Ziel-Double.
func _gooby_vorauslaufen(dauer_s: float) -> void:
	if not _quelle.has_method("gooby"):
		return
	var gooby: Variant = _quelle.gooby()
	if not (gooby is Node3D) or not is_instance_valid(gooby):
		return
	if gooby.has_method("cancel_walk"):
		gooby.cancel_walk()
	if gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(false)
	var rig: Variant = gooby.get("rig")
	if rig is Node3D:
		var lokal := _quelle.global_basis.inverse() * _richtung
		(rig as Node3D).rotation.y = atan2(lokal.x, lokal.z)
		if rig.has_method("set_locomotion"):
			rig.set_locomotion(1.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var ziel_punkt := _tuer_welt + _richtung * SPAWN_ABSTAND_M
	tween.tween_property(gooby, "global_position", ziel_punkt, dauer_s)
	var schritt_aus := func() -> void:
		if is_instance_valid(gooby) and rig is Node3D and rig.has_method("set_locomotion"):
			rig.set_locomotion(0.0)
	tween.finished.connect(schritt_aus)


## Übergabe an den Zielraum: Zielkamera übernimmt, Quellraum verschwindet
## (der Router gibt ihn frei), Ziel-Gooby und Ziel-Tür kehren zurück, das
## Türblatt fällt sanft hinter Gooby zu.
func _uebergabe() -> void:
	if is_instance_valid(_ziel_cam):
		_ziel_cam.make_current()
	if is_instance_valid(_quelle):
		_quelle.visible = false
	if is_instance_valid(_ziel_tuer):
		_ziel_tuer.visible = true
		if _ziel_tuer.has_method("set_offen_sofort"):
			_ziel_tuer.set_offen_sofort()
		if _ziel_tuer.has_method("schliesse_sanft"):
			_ziel_tuer.schliesse_sanft()
	if is_instance_valid(_ziel_gooby):
		_ziel_gooby.visible = true
		if _ziel_gooby.has_method("set_wander_enabled"):
			_ziel_gooby.set_wander_enabled(true)


## Vollflächiger Input-Deckel für die Fahrtdauer — dieselbe Semantik wie
## der Veil-Blocker des Wisch-Pfads (keine Tür-Taps in den Gastraum).
func _blocker_bauen() -> void:
	var schicht := CanvasLayer.new()
	schicht.name = "FahrtBlocker"
	schicht.layer = 99
	var deckel := Control.new()
	deckel.set_anchors_preset(Control.PRESET_FULL_RECT)
	deckel.mouse_filter = Control.MOUSE_FILTER_STOP
	schicht.add_child(deckel)
	add_child(schicht)


static func _kamera_von(szene: Node) -> Camera3D:
	if szene == null or not szene.has_method("camera_rig"):
		return null
	var rig: Variant = szene.camera_rig()
	if rig == null:
		return null
	var cam: Variant = rig.get("camera")
	return cam if cam is Camera3D else null
