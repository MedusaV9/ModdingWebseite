class_name GarageProp
extends Node3D
## Garage-Baukörper (W13C, Doc D §7) im Garten: Blender-GLB
## (tools/blender/props/build_garage.py) mit dem ROLLTOR als separatem
## Mesh-Node + dem aktuell gewählten Auto (AutoKatalog.aktives_auto,
## Karosserie-Tint wie im Autohaus) sichtbar geparkt.
##
## Primitive-Fallback ohne GLB (Headless-Tests, kaputter Import) — gleiche
## Hüllmaße, gleicher Rolltor-Pivot. Der Rolltor-Node hängt mit dem Ursprung
## an der OBERKANTE der Öffnung: scale.y 1 → 0.08 rollt das Tor sichtbar
## nach oben auf (die Rest-Skalierung bleibt als Wickelrolle unterm Sturz).

## Auffindbar für GarageAbfahrt (Freie-Fahrt-Hook außerhalb des Gartens).
const GRUPPE := "garage_prop"
## MÜSSEN zu tools/blender/props/build_garage.py passen (2×3-Footprint).
const GLB_PFAD := "res://assets/furniture/garage.glb"
const BREITE := 1.9
const TIEFE := 2.9
const WAND_H := 1.9
const TOR_BREITE := 1.5
const TOR_HOEHE := 1.5
## Front-Ebene des Rolltors (lokal +z, knapp vor der Frontwand).
const TOR_Z := 1.42
## Aufgerollt bleibt eine sichtbare Wickelrolle unter dem Sturz.
const TOR_MIN_SCALE := 0.08
const TOR_DAUER_S := 0.7
## Ziel-Länge des geparkten Autos (passt mit Luft in die 3-m-Tiefe).
const AUTO_LAENGE := 2.2
## Parkposition (lokal): leicht nach hinten versetzt, Nase Richtung Tor.
const AUTO_PARK_Z := -0.25
const ABFAHRT_STRECKE := 3.4
const ABFAHRT_DAUER_S := 1.6

var _rolltor: Node3D
var _auto: Node3D
var _auto_id := ""
var _tor_tween: Tween
var _abfahrt_laeuft := false


## Prop bauen (GLB bzw. Fallback) + aktives Auto hineinstellen.
static func create(gs: Object) -> GarageProp:
	var prop := GarageProp.new()
	prop.name = "Garage"
	prop._build_koerper()
	prop._build_auto(gs)
	return prop


func _enter_tree() -> void:
	add_to_group(GRUPPE)


func rolltor() -> Node3D:
	return _rolltor


func auto_node() -> Node3D:
	return _auto


func auto_id() -> String:
	return _auto_id


func abfahrt_laeuft() -> bool:
	return _abfahrt_laeuft


## Tor sofort auf `anteil` stellen (0 = zu, 1 = aufgerollt) — ohne Animation,
## z. B. nach einem GardenView-Rebuild, der den Prop neu erzeugt hat.
func set_rolltor_anteil(anteil: float) -> void:
	if _rolltor == null:
		return
	if _tor_tween != null and _tor_tween.is_running():
		_tor_tween.kill()
	_rolltor.scale.y = _tor_scale(anteil)


## Tor animiert auf `ziel_anteil` fahren. Liefert den Tween (der Aufrufer
## hängt sich an `finished`, um den Zustands-Endpunkt zu setzen) — ein
## erneuter Aufruf mitten in der Fahrt kehrt die Richtung einfach um.
func rolltor_fahren(ziel_anteil: float) -> Tween:
	if _rolltor == null:
		return null
	if _tor_tween != null and _tor_tween.is_running():
		_tor_tween.kill()
	AudioDirector.try_play(self, "gvz_mower")
	_tor_tween = create_tween()
	(
		_tor_tween
		. tween_property(_rolltor, "scale:y", _tor_scale(ziel_anteil), TOR_DAUER_S)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	return _tor_tween


## Abfahrt-Sequenz (Doc D §7, „Freie Fahrt“): Tor rollt auf, das Auto fährt
## mit Anlauf raus. Awaitbar; `reduziert` (Reduced Motion) kürzt alles ab.
func abfahrt_spielen(reduziert := false) -> void:
	_abfahrt_laeuft = true
	if reduziert or _auto == null:
		set_rolltor_anteil(1.0)
		if _auto != null:
			_auto.position.z += ABFAHRT_STRECKE
		_abfahrt_laeuft = false
		return
	rolltor_fahren(1.0)
	await get_tree().create_timer(TOR_DAUER_S + 0.1).timeout
	AudioDirector.try_play(self, "travel_whoosh_auf")
	var fahrt := create_tween()
	(
		fahrt
		. tween_property(_auto, "position:z", AUTO_PARK_Z + ABFAHRT_STRECKE, ABFAHRT_DAUER_S)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	await get_tree().create_timer(ABFAHRT_DAUER_S + 0.1).timeout
	_abfahrt_laeuft = false


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _tor_scale(anteil: float) -> float:
	return lerpf(1.0, TOR_MIN_SCALE, clampf(anteil, 0.0, 1.0))


func _build_koerper() -> void:
	if ResourceLoader.exists(GLB_PFAD):
		var szene: PackedScene = load(GLB_PFAD)
		if szene != null:
			var modell: Node3D = szene.instantiate()
			modell.name = "GarageGlb"
			add_child(modell)
			var treffer := modell.find_children("GarageRolltor*", "", true, false)
			if not treffer.is_empty() and treffer[0] is Node3D:
				_rolltor = treffer[0]
				return
			# GLB ohne Rolltor-Node (Import-Schaden): weich degradieren.
			modell.queue_free()
	_build_fallback()


## Primitive-Fallback: Korpus mit Tor-Öffnung + Rolltor-Node (Pivot oben).
func _build_fallback() -> void:
	var wand_seite := (BREITE - TOR_BREITE) * 0.5
	var korpus := Node3D.new()
	korpus.name = "GarageKorpus"
	add_child(korpus)
	var boden := HomeProps.box(Vector3(BREITE, 0.08, TIEFE), "holz_dunkel")
	boden.position.y = 0.04
	korpus.add_child(boden)
	var hinten := HomeProps.box(Vector3(BREITE, WAND_H, 0.1), "anstrich")
	hinten.position = Vector3(0.0, WAND_H * 0.5, -TIEFE * 0.5 + 0.05)
	korpus.add_child(hinten)
	for seite: float in [-1.0, 1.0]:
		var wand := HomeProps.box(Vector3(0.1, WAND_H, TIEFE), "anstrich")
		wand.position = Vector3(seite * (BREITE * 0.5 - 0.05), WAND_H * 0.5, 0.0)
		korpus.add_child(wand)
		var pfosten := HomeProps.box(Vector3(wand_seite, WAND_H, 0.1), "anstrich")
		pfosten.position = Vector3(
			seite * (BREITE - wand_seite) * 0.5, WAND_H * 0.5, TIEFE * 0.5 - 0.05
		)
		korpus.add_child(pfosten)
	var sturz := HomeProps.box(Vector3(BREITE, WAND_H - TOR_HOEHE, 0.1), "anstrich")
	sturz.position = Vector3(0.0, (WAND_H + TOR_HOEHE) * 0.5, TIEFE * 0.5 - 0.05)
	korpus.add_child(sturz)
	var dach := HomeProps.box(Vector3(BREITE + 0.3, 0.14, TIEFE + 0.3), "dach")
	dach.position.y = WAND_H + 0.07
	korpus.add_child(dach)
	_rolltor = Node3D.new()
	_rolltor.name = "GarageRolltor"
	_rolltor.position = Vector3(0.0, TOR_HOEHE, TOR_Z)
	add_child(_rolltor)
	var blatt := HomeProps.box(Vector3(TOR_BREITE, TOR_HOEHE, 0.06), "metall")
	blatt.position.y = -TOR_HOEHE * 0.5
	_rolltor.add_child(blatt)
	for i in 4:
		var lamelle := HomeProps.box(Vector3(TOR_BREITE, 0.03, 0.07), "rahmen")
		lamelle.position.y = -TOR_HOEHE * (0.2 + 0.2 * i)
		_rolltor.add_child(lamelle)


## Das aktive Auto (Autohaus-Besitz) sichtbar hineinstellen, Karosserie-Tint
## wie OrtAutohaus._lackiere. Ohne Auto-GLB steht ein Klötzchen-Wagen drin.
func _build_auto(gs: Object) -> void:
	var eintrag := AutoKatalog.aktives_auto(gs)
	if eintrag.is_empty():
		return
	_auto_id = str(eintrag.get("id", ""))
	var pfad := AutoKatalog.glb_pfad(_auto_id)
	_auto = _auto_modell(pfad)
	_auto.name = "GarageAuto"
	_auto.position = Vector3(0.0, 0.08, AUTO_PARK_Z)
	add_child(_auto)
	_lackiere(_auto, str(eintrag.get("farbe", "")))


func _auto_modell(pfad: String) -> Node3D:
	if ResourceLoader.exists(pfad):
		var szene: PackedScene = load(pfad)
		if szene != null:
			var wurzel := Node3D.new()
			var modell: Node3D = szene.instantiate()
			wurzel.add_child(modell)
			var aabb := HomeProps.merged_aabb(modell, Transform3D.IDENTITY)
			var laenge := maxf(aabb.size.x, aabb.size.z)
			if laenge > 0.0001:
				var s := AUTO_LAENGE / laenge
				modell.scale = Vector3.ONE * s
				var center := aabb.get_center()
				modell.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
			return wurzel
	var fallback := Node3D.new()
	var karosse := HomeProps.box(Vector3(1.0, 0.5, AUTO_LAENGE), "akzent")
	karosse.position.y = 0.35
	fallback.add_child(karosse)
	var kabine := HomeProps.box(Vector3(0.8, 0.35, 1.0), "glas")
	kabine.position.y = 0.75
	fallback.add_child(kabine)
	return fallback


## Karosserie-Tint (Muster OrtAutohaus._lackiere / CityScene._tinte).
func _lackiere(node: Node3D, hex: String) -> void:
	if hex.is_empty():
		return
	var farbe := Color.from_string(hex, Color.WHITE)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.6)
				mi.set_surface_override_material(i, kopie)
