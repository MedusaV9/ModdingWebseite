class_name RcompGeist
extends Node3D
## Geisterlauf-Wiedergabe (RW-5, Kap. 5.3): der beste eigene Lauf reitet
## als durchsichtiges Pferd mit — Grundlage des asynchronen Mehrspieler-
## Vergleichs (IDEAS-4). Daten kommen aus RanchCompState (Base64),
## Format/Interpolation aus RanchCompGhost (PURE, getestet).

const Ghost := preload("res://scripts/ranch/comp/ghost/comp_ghost.gd")

const TRANSPARENZ := 0.62
const GEIST_FARBE := Color(0.72, 0.86, 0.98)

var geist: Dictionary = {}
var zeit := 0.0
var laeuft := false

var _pferd: RanchPferd


## Base64 aus dem Save laden; false = kein/kaputter Geist.
func lade(b64: String) -> bool:
	geist = Ghost.from_b64(b64)
	if not bool(geist.get("ok", false)):
		return false
	if _pferd == null:
		# Konvention wie RanchWeltReiter/RideController: Modell schaut
		# unrotiert in Fahrtrichtung (-z), rotation.y = heading am Wurzel.
		_pferd = RanchPferd.neu(GEIST_FARBE, GEIST_FARBE.darkened(0.25))
		add_child(_pferd)
		_mache_durchsichtig.call_deferred()
	visible = false
	return true


func starte() -> void:
	if geist.is_empty() or not bool(geist.get("ok", false)):
		return
	zeit = 0.0
	laeuft = true
	visible = true
	_setze_zustand(Ghost.zustand_bei(geist, 0.0))


func stoppe() -> void:
	laeuft = false
	visible = false


func _process(delta: float) -> void:
	if not laeuft:
		return
	zeit += delta
	var zustand := Ghost.zustand_bei(geist, zeit)
	_setze_zustand(zustand)
	if _pferd != null:
		_pferd.tick(delta)
	# Am Ende sanft verschwinden.
	if zeit > float(geist.get("dauer_s", 0.0)) + 1.5:
		stoppe()


func _setze_zustand(zustand: Dictionary) -> void:
	position = zustand.get("pos", Vector3.ZERO)
	rotation.y = float(zustand.get("heading", 0.0))
	if _pferd != null:
		_pferd.set_gait(str(zustand.get("gangart", "stand")))


## Alle Meshes des Geist-Pferds halbtransparent + ohne Schatten.
func _mache_durchsichtig() -> void:
	var stapel: Array[Node] = [self]
	while not stapel.is_empty():
		var node: Node = stapel.pop_back()
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).transparency = TRANSPARENZ
			(node as GeometryInstance3D).cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
		for kind in node.get_children():
			stapel.append(kind)
