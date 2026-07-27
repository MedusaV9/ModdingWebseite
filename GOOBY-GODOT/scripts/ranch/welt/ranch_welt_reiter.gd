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

## VIS-1 Huf-Clipping: Bodenabtastung an den vier Huf-Punkten (vor/zurück
## × links/rechts, Meter im Pferde-Raum) + kleiner Freigang — der Körper
## steht auf dem HÖCHSTEN Bodenkontakt, kein Huf sinkt in Boden/Planken.
const HUF_VOR_M := 1.05
const HUF_SEITE_M := 0.38
const HUF_FREI_M := 0.05

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
		kandidat.y = RanchGelaende.reit_hoehe(kandidat.x, kandidat.z)
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


## Bodenhöhe + sanfte Hang-Neigung des Pferdes. WELT-1: reit_hoehe statt
## hoehe — über der Schlucht trägt das Hängebrücken-Deck den Reiter.
## VIS-1: statt EINEM Mittelpunkt tasten wir die vier Huf-Punkte ab und
## heben den Körper auf den höchsten Kontakt (+Freigang) — auf Kuppen,
## in Senken und auf den Brücken-Planken sinkt kein Huf mehr ein.
func _am_boden() -> void:
	var vor := -transform.basis.z
	var quer := transform.basis.x
	var vorn := -1000.0
	var hinten := -1000.0
	for seite: float in [-1.0, 1.0]:
		var pv := position + vor * HUF_VOR_M + quer * seite * HUF_SEITE_M
		vorn = maxf(vorn, RanchGelaende.reit_hoehe(pv.x, pv.z))
		var ph := position - vor * HUF_VOR_M + quer * seite * HUF_SEITE_M
		hinten = maxf(hinten, RanchGelaende.reit_hoehe(ph.x, ph.z))
	var mitte := RanchGelaende.reit_hoehe(position.x, position.z)
	var steigung := (vorn - hinten) / (HUF_VOR_M * 2.0)
	var neigung := clampf(-steigung * 0.55, -0.3, 0.3)
	pferd.rotation.x = lerpf(pferd.rotation.x, neigung, 0.2)
	# Die TATSÄCHLICH angewandte Neigung hebt die Berg-Hufe bereits an —
	# nur der Rest muss über die Körperhöhe kommen.
	var hub := -pferd.rotation.x * HUF_VOR_M
	position.y = maxf(mitte, maxf(vorn - hub, hinten + hub)) + HUF_FREI_M


func _stelle_kamera(gewicht: float) -> void:
	var zurueck := transform.basis.z
	var abstand := 9.0 + absf(tempo) * 0.28
	var ziel := position + zurueck * abstand + Vector3(0.0, 4.4, 0.0)
	ziel.y = maxf(ziel.y, RanchGelaende.reit_hoehe(ziel.x, ziel.z) + 1.6)
	cam.position = cam.position.lerp(ziel, gewicht)
	cam.look_at(position + Vector3(0.0, 1.9, 0.0))
