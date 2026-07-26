class_name RanchWeltReiter
extends Node3D
## Freier Reiter der Ranch-Region (RW-1): RanchPferd + Kamera + Steuerung
## (ui_-Aktionen: hoch = antraben, runter = bremsen, links/rechts = lenken;
## Galopp über das HUD). Bodenhöhe kommt IMMER aus RanchGelaende, Bewegung
## wird von RanchKarte.ist_begehbar geklammert (Wasser nur an Furt/Brücke).
## Meldet Zonen-Wechsel für Entdeckungs-Toasts + HUD.

signal zone_gewechselt(zone_id: String)

const TEMPO_SCHRITT := 3.6
const TEMPO_TRAB := 8.0
const TEMPO_GALOPP := 14.5
const DREH_TEMPO := 1.9

## HUD-Schalter: Galopp statt Trab als Reisetempo.
var galopp := false
## Steuerung aus (Screenshot-Fahrten setzen die Position direkt).
var steuerung_aktiv := true

var pferd: RanchPferd
var cam: Camera3D
var tempo := 0.0

var _zone_akt := ""
var _zonen_timer := 0.0


func _ready() -> void:
	pferd = RanchPferd.neu(RanchPferd.FELL["palomino"][0], RanchPferd.FELL["palomino"][1])
	add_child(pferd)
	cam = Camera3D.new()
	cam.name = "ReiterKamera"
	cam.top_level = true
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	_stelle_kamera(1.0)


func _process(delta: float) -> void:
	if steuerung_aktiv:
		_steuere(delta)
	_am_boden()
	_stelle_kamera(minf(1.0, delta * 4.0))
	_zonen_timer -= delta
	if _zonen_timer <= 0.0:
		_zonen_timer = 0.4
		var zone := RanchKarte.zone_bei(position)
		if not zone.is_empty() and zone != _zone_akt:
			_zone_akt = zone
			zone_gewechselt.emit(zone)


## Reiter versetzen (Spawn/Screenshots) — Kamera springt sofort mit.
func springe_zu(punkt: Vector3, blick_rad := 0.0) -> void:
	position = punkt
	rotation.y = blick_rad
	_am_boden()
	_stelle_kamera(1.0)


func aktuelle_zone() -> String:
	return _zone_akt


## ------------------------------------------------------------- intern


func _steuere(delta: float) -> void:
	var lenken := Input.get_axis("ui_left", "ui_right")
	rotation.y -= lenken * DREH_TEMPO * delta * (0.55 if tempo > TEMPO_TRAB else 1.0)
	var ziel_tempo := 0.0
	if Input.is_action_pressed("ui_up"):
		ziel_tempo = TEMPO_GALOPP if galopp else TEMPO_TRAB
	elif Input.is_action_pressed("ui_down"):
		ziel_tempo = -TEMPO_SCHRITT * 0.5
	tempo = move_toward(tempo, ziel_tempo, delta * 9.0)
	if absf(tempo) > 0.05:
		var vor := -transform.basis.z
		var kandidat := position + vor * tempo * delta
		kandidat.y = RanchGelaende.hoehe(kandidat.x, kandidat.z)
		if RanchKarte.ist_begehbar(kandidat):
			position = kandidat
		else:
			tempo = 0.0
	_setze_gangart()


func _setze_gangart() -> void:
	var t := absf(tempo)
	if t < 0.4:
		pferd.set_gangart(RanchPferd.GANG_IDLE)
	elif t < TEMPO_SCHRITT + 0.8:
		pferd.set_gangart(RanchPferd.GANG_SCHRITT)
	elif t < TEMPO_TRAB + 1.5:
		pferd.set_gangart(RanchPferd.GANG_TRAB)
	else:
		pferd.set_gangart(RanchPferd.GANG_GALOPP)


## Bodenhöhe + sanfte Hang-Neigung des Pferdes.
func _am_boden() -> void:
	position.y = RanchGelaende.hoehe(position.x, position.z)
	var vor := -transform.basis.z
	var voraus := position + vor * 1.6
	var steigung := RanchGelaende.hoehe(voraus.x, voraus.z) - position.y
	pferd.rotation.x = lerpf(pferd.rotation.x, clampf(-steigung * 0.35, -0.3, 0.3), 0.2)


func _stelle_kamera(gewicht: float) -> void:
	var zurueck := transform.basis.z
	var abstand := 9.0 + absf(tempo) * 0.28
	var ziel := position + zurueck * abstand + Vector3(0.0, 4.4, 0.0)
	ziel.y = maxf(ziel.y, RanchGelaende.hoehe(ziel.x, ziel.z) + 1.6)
	cam.position = cam.position.lerp(ziel, gewicht)
	cam.look_at(position + Vector3(0.0, 1.9, 0.0))
