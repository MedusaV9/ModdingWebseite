class_name CitySkyline
extends Node3D
## Vorstadt-Kulisse im Baumodus (HAUS-SICHT-Umbau des FIX-3-Rings, User:
## „die Stadt drumherum sieht komisch aus"). Der alte Ring — Straße auf
## allen vier Seiten in 4 m Abstand, City-Geschäftsblöcke frontal um den
## Raum — wirkte wie ein Kreisverkehr um eine schwebende Insel. Jetzt:
##
##   - das EIGENE Grundstück im Zentrum: Sockel unterm Raum in der
##     Fassadenfarbe des Spielers, Zaun in seiner Zaunfarbe (beides aus
##     HouseStyleState), Weg zum Gehweg, Garten hinterm Haus,
##   - EINE Straße in richtiger Entfernung (Vorgarten + Gehweg dazwischen),
##     auf der Seite, auf die die Außenwand laut rooms.json zeigt
##     (`walls.N` = strasse ⇒ Straße im Norden; = garten ⇒ im Süden),
##   - Nachbargrundstücke mit Zäunen und Einfamilienhäusern in Spielhaus-
##     Größe (statt Geschäftsblöcken) links, rechts und gegenüber,
##   - Tiefenstaffelung: fernere Häuser werden größer gestreut und in
##     Richtung Horizontfarbe entsättigt, dahinter Baumreihen und Hügel.
##
## BEWUSST BILLIG: aktiv NUR im Baumodus (RoomBase schaltet set_aktiv);
## Wiederhol-Geometrie läuft als MultiMesh (Häuser mit Instanz-Farben!);
## schaut die Kamera senkrecht nach unten auf den Raum, wird alles jenseits
## des Grundstücks versteckt (kulisse_sichtbar). Budget-Tests:
## test_fix3_skyline.gd + test_haussicht_budget.gd, Draw-Calls:
## fix3_perf_probe.gd / haussicht_screens.gd.

const ASSETS := "res://assets/city"
const GOOBY_GLB := "res://assets/character/gooby.glb"
## Kantenlänge einer Straßenkachel (m).
const KACHEL := 3.6
## Grundstücks-Ränder um den Raum (m): Seite, Vorgarten, Garten hinterm Haus.
const SEITEN_RAND := 2.6
const VORGARTEN := 3.4
const GARTEN_TIEFE := 6.2
const GEHWEG := 1.7
## Raumkante → Straßenmitte (Vorgarten + Gehweg + halbe Fahrbahn).
const STRASSE_ABSTAND := VORGARTEN + GEHWEG + 2.0
## Der Garten-Raum trägt das eigene Haus an der Nordkante — die Straße
## liegt dahinter (Schwelle + Haustiefe + Vorgarten + Gehweg + Fahrbahn).
const STRASSE_ABSTAND_GARTEN := 10.9
const AUTO_TEMPO := 3.0
const AUTO_HOEHE := 1.45
const GOOBY_SCALE := 0.95
const ZAUN_HOEHE := 0.55
## Blickt die Kamera steiler als dieser Forward-y nach unten, ist von der
## Welt draußen praktisch nichts im Bild → Fern-Kulisse schlafen legen.
const TOPDOWN_FORWARD_Y := -0.985
## LOD: nahe Deko blendet aus, wenn die Kamera weit draußen ist.
const LOD_DEKO_M := 110.0
const FASSADEN_FARBEN: Array[String] = [
	"creme", "butter", "rose", "himmel", "salbei", "koralle", "mint", "sandstein"
]
const DACH_FARBEN: Array[String] = [
	"ziegelrot", "anthrazit", "tannengruen", "marine", "terracotta", "grau"
]
## Horizontfarbe für die Entsättigung ferner Häuser/Hügel.
const HORIZONT := Color("#C9DFE3")

## Geteiltes Instanzfarben-Material (Häuser/Zäune/Hügel = 1 Material).
static var _instanz_material: StandardMaterial3D

var _room_rect := Rect2()
var _strasse_seite := "N"
var _plot := Rect2()
var _z_strasse := 0.0
var _outdoor := false
var _style: Dictionary = {}
var _tuer_x := 0.0
var _nah: Node3D
var _fern: Node3D
var _autos: Array[Dictionary] = []
var _npcs: Array[Dictionary] = []
var _auto_spanne := Vector2.ZERO
var _zeit := 0.0
var _haus_transforms: Dictionary = {}
var _haus_farben: Dictionary = {}
var _zaun_posten: Array[Transform3D] = []
var _zaun_riegel: Array[Transform3D] = []
var _zaun_farben_posten: Array[Color] = []
var _zaun_farben_riegel: Array[Color] = []


## Kulisse an einen Raum hängen (RoomBase ruft das im Aufbau). `seed_wert`
## macht das Layout deterministisch, `room_id` liefert Vista + Stil-Anker.
static func attach_to(
	room: Node3D, world_size: Vector2, seed_wert: int, room_id := ""
) -> CitySkyline:
	var skyline := CitySkyline.new()
	skyline.name = "CitySkyline"
	if room.has_method("game_state"):
		skyline._style = HouseStyleState.style(room.call("game_state"))
	skyline.baue(world_size, seed_wert, room_id)
	room.add_child(skyline)
	skyline.set_aktiv(false)
	return skyline


## Punkt auf dem Rechteck-Umfang bei Bogenlänge `t` (wrapt) — pure Mathe,
## bleibt für Ringrouten/Tests erhalten (test_fix3_skyline.gd).
static func ring_punkt(rect: Rect2, t: float) -> Dictionary:
	var b := rect.size.x
	var h := rect.size.y
	var umfang := 2.0 * (b + h)
	var s := fposmod(t, umfang)
	var p := rect.position
	if s < b:
		return {"pos": Vector3(p.x + s, 0.0, p.y), "heading": PI * 0.5}
	s -= b
	if s < h:
		return {"pos": Vector3(p.x + b, 0.0, p.y + s), "heading": PI}
	s -= h
	if s < b:
		return {"pos": Vector3(p.x + b - s, 0.0, p.y + h), "heading": -PI * 0.5}
	s -= b
	return {"pos": Vector3(p.x, 0.0, p.y + h - s), "heading": 0.0}


## Ist die Fern-Kulisse aus dieser Kamerapose überhaupt sichtbar? Pure
## (test_haussicht_budget.gd): nur wenn die Kamera fast senkrecht nach
## unten schaut UND über dem Raum steht, ist draußen nichts im Bild.
static func kulisse_sichtbar(cam_pos: Vector3, forward: Vector3, room_rect: Rect2) -> bool:
	if forward.y > TOPDOWN_FORWARD_Y:
		return true
	return not room_rect.grow(2.0).has_point(Vector2(cam_pos.x, cam_pos.z))


func baue(world_size: Vector2, seed_wert: int, room_id := "") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	_room_rect = Rect2(Vector2.ZERO, world_size)
	_layout_bestimmen(room_id)
	_nah = Node3D.new()
	_nah.name = "Nah"
	add_child(_nah)
	_fern = Node3D.new()
	_fern.name = "Fern"
	add_child(_fern)
	_baue_grund()
	_baue_strasse()
	if not _outdoor:
		_baue_eigenes_grundstueck(rng)
	_baue_nachbarn(rng)
	_zaun_abschliessen()
	_baue_natur(rng)
	_baue_autos(rng)
	_baue_npcs(rng)


## Aktiv = sichtbar + Verkehr läuft. Außerhalb des Baumodus schläft die
## Kulisse komplett (Budget!) — die Fenster-Dioramen übernehmen dort.
func set_aktiv(aktiv: bool) -> void:
	visible = aktiv
	set_process(aktiv)


func _process(delta: float) -> void:
	_kamera_gating()
	if _fern != null and not _fern.visible:
		return
	_zeit += delta
	for auto: Dictionary in _autos:
		var node: Node3D = auto["node"]
		var richtung := float(auto["richtung"])
		node.position.x += AUTO_TEMPO * richtung * delta
		if node.position.x > _auto_spanne.y:
			node.position.x = _auto_spanne.x
		elif node.position.x < _auto_spanne.x:
			node.position.x = _auto_spanne.y
	for npc: Dictionary in _npcs:
		var punkt := _pingpong_punkt(npc, _zeit)
		var node: Node3D = npc["node"]
		node.position = punkt["pos"]
		node.rotation.y = float(punkt["heading"])


## Kamera senkrecht überm Raum? Dann Fern-Kulisse (Straße, Nachbarn,
## Horizont, Verkehr) schlafen legen — sie wäre eh nicht im Bild.
func _kamera_gating() -> void:
	if _fern == null or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_transform.basis.z
	var sichtbar := kulisse_sichtbar(camera.global_position, forward, _room_rect)
	if _fern.visible != sichtbar:
		_fern.visible = sichtbar


## Ping-Pong auf einer Gehweg-Strecke (wie CityFussgaenger, lokal gehalten).
func _pingpong_punkt(route: Dictionary, zeit: float) -> Dictionary:
	var von: Vector3 = route["von"]
	var nach: Vector3 = route["nach"]
	var laenge := maxf(0.001, von.distance_to(nach))
	var t := float(route["phase"]) * 2.0 + zeit * float(route["tempo"]) / laenge
	var zyklus := fposmod(t, 2.0)
	var hin := zyklus < 1.0
	var f := zyklus if hin else 2.0 - zyklus
	var richtung := (nach - von) if hin else (von - nach)
	return {"pos": von.lerp(nach, f), "heading": atan2(richtung.x, richtung.z)}


# ── Layout ───────────────────────────────────────────────────────────────────


## Straßen-Seite + Grundstücks-Rechteck aus rooms.json ableiten: die
## Außenwand N zeigt auf ihre Vista (HouseLayout-Kompass). Garten-Räume
## haben den Garten im Norden ⇒ Straße im Süden; der Garten-RAUM trägt das
## Haus im Norden ⇒ Straße dahinter.
func _layout_bestimmen(room_id: String) -> void:
	var room_def := RoomDefs.room(room_id)
	_outdoor = bool(room_def.get("outdoor", false))
	var vista := str(RoomDefs.exterior_walls(room_def).get("N", "strasse"))
	_strasse_seite = "S" if (vista == "garten" and not _outdoor) else "N"
	var abstand := STRASSE_ABSTAND_GARTEN if _outdoor else STRASSE_ABSTAND
	_z_strasse = _z_ab_kante(_strasse_seite, abstand)
	var front := 0.0 if _outdoor else VORGARTEN
	var hinten := 0.0 if _outdoor else GARTEN_TIEFE
	var oben := front if _strasse_seite == "N" else hinten
	var unten := hinten if _strasse_seite == "N" else front
	_plot = Rect2(
		-SEITEN_RAND, -oben, _room_rect.size.x + 2.0 * SEITEN_RAND, _room_rect.size.y + oben + unten
	)
	_tuer_x = _front_tuer_x(room_def)


## Abstand von der Raumkante nach draußen → Welt-z (Seite N oder S).
func _z_ab_kante(seite: String, abstand: float) -> float:
	if seite == "N":
		return -abstand
	return _room_rect.size.y + abstand


## X der Tür auf der Straßenseite (Gartentor + Weg); ohne Tür: Raummitte.
func _front_tuer_x(room_def: Dictionary) -> float:
	for door_def: Dictionary in room_def.get("doors", []):
		if str(door_def.get("wall", "")) == _strasse_seite:
			return RoomDefs.door_world_pos(room_def, door_def).x
	return _room_rect.size.x * 0.5


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _baue_grund() -> void:
	var gras := MeshInstance3D.new()
	gras.name = "Rasen"
	var plane := PlaneMesh.new()
	plane.size = Vector2(320.0, 320.0)
	gras.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8CBE6B")
	mat.roughness = 1.0
	gras.material_override = mat
	gras.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Knapp unter Boden-Niveau: bei -0.14 „schwebten" Zäune/Beete sichtbar.
	gras.position = Vector3(_room_rect.size.x * 0.5, -0.03, _room_rect.size.y * 0.5)
	_nah.add_child(gras)


## EINE Straße parallel zur Fassade: Kacheln als MultiMesh, Gehwege beid-
## seitig, Laternenreihe auf der Raumseite.
func _baue_strasse() -> void:
	var xc := _room_rect.size.x * 0.5
	var transforms: Array[Transform3D] = []
	var kacheln := 15
	for i in kacheln:
		var x := xc + (i - kacheln * 0.5 + 0.5) * KACHEL
		var basis := Basis(Vector3.UP, 0.0) * Basis.from_scale(Vector3.ONE * KACHEL)
		transforms.append(Transform3D(basis, Vector3(x, 0.0, _z_strasse)))
	HomeProps.multi_glb(_fern, "%s/strassen/road-straight.glb" % ASSETS, transforms, "Strasse")
	var laenge := kacheln * KACHEL
	for seite: float in [-1.0, 1.0]:
		var gehweg := MeshInstance3D.new()
		gehweg.name = "Gehweg"
		var box := BoxMesh.new()
		box.size = Vector3(laenge, 0.14, GEHWEG)
		gehweg.mesh = box
		gehweg.material_override = CustomizeMaterials.flat("grau_hell")
		gehweg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gehweg.position = Vector3(xc, 0.02, _z_strasse + seite * (2.0 + GEHWEG * 0.5))
		_fern.add_child(gehweg)
	var seite_raum := -1.0 if _strasse_seite == "S" else 1.0
	var laternen: Array[Transform3D] = []
	var laterne_hoehe := _glb_hoehe("%s/deko/streetlight.gltf" % ASSETS)
	if laterne_hoehe > 0.0001:
		var skala := 3.2 / laterne_hoehe
		for i in 5:
			var x := xc + (i - 2.0) * 10.0
			var basis := (
				Basis(Vector3.UP, 0.0 if seite_raum > 0.0 else PI)
				* Basis.from_scale(Vector3.ONE * skala)
			)
			var z := _z_strasse + seite_raum * (2.0 + GEHWEG - 0.35)
			laternen.append(Transform3D(basis, Vector3(x, 0.0, z)))
		HomeProps.multi_glb(
			_fern, "%s/deko/streetlight.gltf" % ASSETS, laternen, "Laternen", LOD_DEKO_M
		)


## Das eigene Grundstück (nur Innenräume — der Garten-Raum IST es schon):
## Sockel in der Fassadenfarbe, Zaun in der Zaunfarbe, Weg zum Gehweg,
## Beete + Wäscheleine hinterm Haus.
func _baue_eigenes_grundstueck(rng: RandomNumberGenerator) -> void:
	var haus: Dictionary = _style.get("haus", CustomizeCatalog.default_haus())
	var grund: Dictionary = _style.get("grundstueck", CustomizeCatalog.default_grundstueck())
	var fassade := CustomizeMaterials.farbe(str(haus.get("fassade", "creme"))).darkened(0.08)
	_baue_sockel(fassade)
	var zaun_farbe := CustomizeMaterials.farbe(str(grund.get("zaunFarbe", "eiche")))
	var tor_halb := 0.9
	_zaun_rechteck(_plot, zaun_farbe, _strasse_seite, _tuer_x - tor_halb, _tuer_x + tor_halb)
	_baue_weg()
	_baue_garten_deko(rng)


## Sockel-Schürze rund um den Raum — erdet ihn als „das Haus" auf dem
## Grundstück (Fassadenfarbe aus dem Gestalten-Modus).
func _baue_sockel(farbe: Color) -> void:
	var w := _room_rect.size.x
	var h := _room_rect.size.y
	var dicke := 0.16
	var hoehe := 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.95
	var seiten: Array = [
		[Vector3(w + 0.5, hoehe, dicke), Vector3(w * 0.5, 0.0, -dicke * 0.5 - 0.1)],
		[Vector3(w + 0.5, hoehe, dicke), Vector3(w * 0.5, 0.0, h + dicke * 0.5 + 0.1)],
		[Vector3(dicke, hoehe, h + 0.5), Vector3(-dicke * 0.5 - 0.1, 0.0, h * 0.5)],
		[Vector3(dicke, hoehe, h + 0.5), Vector3(w + dicke * 0.5 + 0.1, 0.0, h * 0.5)],
	]
	for eintrag: Array in seiten:
		var mesh := MeshInstance3D.new()
		mesh.name = "Sockel"
		var box := BoxMesh.new()
		box.size = eintrag[0]
		mesh.mesh = box
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.position = (eintrag[1] as Vector3) + Vector3(0.0, hoehe * 0.5 - 0.36, 0.0)
		_nah.add_child(mesh)


func _baue_weg() -> void:
	var weg := MeshInstance3D.new()
	weg.name = "Weg"
	var box := BoxMesh.new()
	var laenge := VORGARTEN + GEHWEG * 0.5
	box.size = Vector3(1.3, 0.06, laenge)
	weg.mesh = box
	weg.material_override = HouseExterior.teil_material("weg", _style)
	if weg.material_override == null:
		weg.material_override = CustomizeMaterials.surface("platten", "sandstein")
	weg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mitte := _z_ab_kante(_strasse_seite, laenge * 0.5)
	weg.position = Vector3(_tuer_x, 0.01, mitte)
	_nah.add_child(weg)


## Beete + Blumen im Gartenstreifen hinter dem Raum.
func _baue_garten_deko(rng: RandomNumberGenerator) -> void:
	var garten_seite := "S" if _strasse_seite == "N" else "N"
	var xc := _room_rect.size.x * 0.5
	for i in 2:
		var beet := HomeProps.box(Vector3(1.4, 0.16, 0.9), "holz_dunkel")
		beet.name = "Beet"
		var z := _z_ab_kante(garten_seite, 2.2 + 0.4 * i)
		beet.position = Vector3(xc - 2.2 + i * 4.4, 0.05, z)
		_nah.add_child(beet)
	var blumen: Array[Transform3D] = []
	for i in 8:
		var x := xc - 3.5 + i * 1.0
		var z := _z_ab_kante(garten_seite, GARTEN_TIEFE - 0.7)
		var basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * 0.6)
		blumen.append(Transform3D(basis, Vector3(x, 0.0, z)))
	HomeProps.multi_glb(
		_nah, "%s/natur/flower_purpleA.glb" % ASSETS, blumen, "Gartenblumen", LOD_DEKO_M
	)


## Nachbarhäuser: Einfamilienhäuser in Spielhaus-Größe als MultiMesh mit
## Instanz-Farben — links/rechts, gegenüber der Straße und als entsättigte
## Fern-Staffeln bis zum Horizont.
func _baue_nachbarn(rng: RandomNumberGenerator) -> void:
	var xc := _room_rect.size.x * 0.5
	# Gedecktes Creme statt Reinweiß — weniger Kontrast-Flimmern im Grün.
	var zaun_nachbar := CustomizeMaterials.farbe("creme").darkened(0.06)
	var haus_yaw := PI if _strasse_seite == "N" else 0.0
	# Links + rechts: je ein Nachbargrundstück mit Zaun und Haus.
	for seite: float in [-1.0, 1.0]:
		var x := xc + seite * (_room_rect.size.x * 0.5 + SEITEN_RAND + 5.4)
		var z := _z_ab_kante(_strasse_seite, -_room_rect.size.y * 0.18)
		_haus_hinzu(rng, Vector3(x, 0.0, z), haus_yaw, 1.0, false)
		var breite := 9.6
		var plot := Rect2(x - breite * 0.5, _plot.position.y, breite, _plot.size.y)
		_zaun_rechteck(plot, zaun_nachbar, _strasse_seite, x - 0.8, x + 0.8)
	# Gegenüber: drei Häuser mit Vorgärten hinter der Straße.
	var gegen_yaw := 0.0 if _strasse_seite == "N" else PI
	var abstand := (STRASSE_ABSTAND_GARTEN if _outdoor else STRASSE_ABSTAND) + 2.0 + GEHWEG + 3.4
	for i in 3:
		var x := xc + (i - 1.0) * 10.5 + rng.randf_range(-0.8, 0.8)
		var z := _z_ab_kante(_strasse_seite, abstand + 2.2)
		_haus_hinzu(rng, Vector3(x, 0.0, z), gegen_yaw, 1.0, false)
		var von_x := x - 4.4
		var bis_x := x + 4.4
		var zaun_z := _z_ab_kante(_strasse_seite, abstand - 3.0)
		_zaun_lauf(Vector3(von_x, 0.0, zaun_z), Vector3(bis_x, 0.0, zaun_z), zaun_nachbar, x, 0.8)
	# Fern-Staffeln: gestreute Häuser, Richtung Horizont entsättigt. Skala
	# bleibt nah an Spielhaus-Größe — riesige Fern-Klötze wirkten „komisch".
	var mitte := Vector3(xc, 0.0, _room_rect.size.y * 0.5)
	for i in 9:
		var winkel := rng.randf() * TAU
		var radius := rng.randf_range(26.0, 40.0)
		var pos := mitte + Vector3(cos(winkel) * radius, 0.0, sin(winkel) * radius)
		if _zu_nah_an_strasse(pos) or _plot.grow(6.0).has_point(Vector2(pos.x, pos.z)):
			continue
		_haus_hinzu(rng, pos, rng.randf() * TAU, rng.randf_range(1.0, 1.15), true)
	for i in 7:
		var winkel := rng.randf() * TAU
		var radius := rng.randf_range(46.0, 60.0)
		var pos := mitte + Vector3(cos(winkel) * radius, 0.0, sin(winkel) * radius)
		_haus_hinzu(rng, pos, rng.randf() * TAU, rng.randf_range(1.1, 1.25), true)
	_haeuser_abschliessen()


## Beschreibung EINES Nachbarhauses in die MultiMesh-Listen legen.
func _haus_hinzu(
	rng: RandomNumberGenerator, pos: Vector3, yaw: float, skala: float, fern: bool
) -> void:
	var breite := rng.randf_range(5.2, 6.6) * skala
	var tiefe := rng.randf_range(4.0, 4.6) * skala
	var hoehe := rng.randf_range(2.4, 2.9) * skala
	var dach_hoehe := rng.randf_range(1.2, 1.6) * skala
	var wand := CustomizeMaterials.farbe(
		FASSADEN_FARBEN[rng.randi_range(0, FASSADEN_FARBEN.size() - 1)]
	)
	var dach := CustomizeMaterials.farbe(DACH_FARBEN[rng.randi_range(0, DACH_FARBEN.size() - 1)])
	var tuer := CustomizeMaterials.farbe(["walnuss", "teal", "marine"][rng.randi_range(0, 2)])
	var fenster := Color("#FFF3C9")
	if fern:
		var nebel := clampf((pos.length() - 20.0) / 55.0, 0.25, 0.72)
		wand = wand.lerp(HORIZONT, nebel)
		dach = dach.lerp(HORIZONT, nebel)
		tuer = tuer.lerp(HORIZONT, nebel)
		fenster = fenster.lerp(HORIZONT, nebel)
	var wurzel := Transform3D(Basis(Vector3.UP, yaw), pos)
	_teil_hinzu(
		"korpus", wurzel, Vector3(breite, hoehe, tiefe), Vector3(0.0, hoehe * 0.5, 0.0), wand
	)
	var dach_basis := (
		Basis(Vector3.UP, PI * 0.5)
		* Basis.from_scale(Vector3(tiefe + 0.5, dach_hoehe, breite + 0.4))
	)
	var dach_lokal := Transform3D(dach_basis, Vector3(0.0, hoehe + dach_hoehe * 0.5, 0.0))
	_haus_liste("dach").append(wurzel * dach_lokal)
	_farb_liste("dach").append(dach)
	_teil_hinzu(
		"tuer",
		wurzel,
		Vector3(0.9, 1.7, 0.12),
		Vector3(-breite * 0.22, 0.85, tiefe * 0.5 + 0.05),
		tuer
	)
	for dx: float in [breite * 0.16, breite * 0.36]:
		_teil_hinzu(
			"fenster",
			wurzel,
			Vector3(0.85, 0.8, 0.1),
			Vector3(dx, 1.35, tiefe * 0.5 + 0.04),
			fenster
		)
	_teil_hinzu(
		"schornstein",
		wurzel,
		Vector3(0.45, 1.1, 0.45),
		Vector3(breite * 0.28, hoehe + dach_hoehe * 0.55, 0.0),
		dach.darkened(0.15)
	)


func _teil_hinzu(
	teil: String, wurzel: Transform3D, groesse: Vector3, mitte: Vector3, farbe: Color
) -> void:
	var lokal := Transform3D(Basis.from_scale(groesse), mitte)
	_haus_liste(teil).append(wurzel * lokal)
	_farb_liste(teil).append(farbe)


func _haus_liste(teil: String) -> Array:
	if not _haus_transforms.has(teil):
		_haus_transforms[teil] = []
	return _haus_transforms[teil]


func _farb_liste(teil: String) -> Array:
	if not _haus_farben.has(teil):
		_haus_farben[teil] = []
	return _haus_farben[teil]


## Alle gesammelten Haus-Teile als je EIN MultiMesh (Instanz-Farben) bauen.
func _haeuser_abschliessen() -> void:
	var meshes := {
		"korpus": BoxMesh.new(),
		"dach": PrismMesh.new(),
		"tuer": BoxMesh.new(),
		"fenster": BoxMesh.new(),
		"schornstein": BoxMesh.new(),
	}
	for teil: String in meshes:
		var transforms: Array = _haus_transforms.get(teil, [])
		if transforms.is_empty():
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = meshes[teil]
		(multi.mesh as PrimitiveMesh).material = _instanzfarben_material()
		multi.instance_count = transforms.size()
		var farben: Array = _haus_farben.get(teil, [])
		for i in transforms.size():
			multi.set_instance_transform(i, transforms[i])
			multi.set_instance_color(i, farben[i])
		var instanz := MultiMeshInstance3D.new()
		instanz.name = "Haeuser_%s" % teil
		instanz.multimesh = multi
		instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fern.add_child(instanz)


static func _instanzfarben_material() -> StandardMaterial3D:
	if _instanz_material == null:
		_instanz_material = StandardMaterial3D.new()
		_instanz_material.vertex_color_use_as_albedo = true
		_instanz_material.roughness = 0.95
	return _instanz_material


# ── Zäune ────────────────────────────────────────────────────────────────────


## Zaun um ein Rechteck, mit Tor-Lücke [tor_von..tor_bis] auf `tor_seite`.
func _zaun_rechteck(
	rect: Rect2, farbe: Color, tor_seite: String, tor_von: float, tor_bis: float
) -> void:
	var p := rect.position
	var e := rect.end
	var laeufe: Array = [
		["N", Vector3(p.x, 0.0, p.y), Vector3(e.x, 0.0, p.y)],
		["S", Vector3(p.x, 0.0, e.y), Vector3(e.x, 0.0, e.y)],
		["W", Vector3(p.x, 0.0, p.y), Vector3(p.x, 0.0, e.y)],
		["E", Vector3(e.x, 0.0, p.y), Vector3(e.x, 0.0, e.y)],
	]
	for lauf: Array in laeufe:
		if str(lauf[0]) == tor_seite:
			_zaun_lauf(lauf[1], Vector3(tor_von, 0.0, (lauf[1] as Vector3).z), farbe, INF, 0.0)
			_zaun_lauf(Vector3(tor_bis, 0.0, (lauf[1] as Vector3).z), lauf[2], farbe, INF, 0.0)
		else:
			_zaun_lauf(lauf[1], lauf[2], farbe, INF, 0.0)


## Ein gerader Zaunlauf von `von` nach `nach` in die MultiMesh-Listen —
## optional mit Tor-Lücke um `tor_x` (± tor_halb). EIN durchgehendes Brett
## pro Lauf statt dünner Doppel-Riegel: aus Baumodus-Distanz lasen die
## 5-cm-Riegel als „weißes Konfetti", ein solides Brett liest als Zaun.
func _zaun_lauf(von: Vector3, nach: Vector3, farbe: Color, tor_x: float, tor_halb: float) -> void:
	var laenge := von.distance_to(nach)
	if laenge < 0.4:
		return
	var richtung := (nach - von) / laenge
	var yaw := atan2(richtung.x, richtung.z) + PI * 0.5
	var posten := int(laenge / 1.7)
	for i in posten + 1:
		var pos := von + richtung * (laenge * i / maxf(1.0, float(posten)))
		if tor_halb > 0.0 and absf(pos.x - tor_x) < tor_halb:
			continue
		var basis := Basis(Vector3.UP, yaw)
		_zaun_posten.append(Transform3D(basis, pos + Vector3(0.0, ZAUN_HOEHE * 0.5, 0.0)))
		_zaun_farben_posten.append(farbe)
	if tor_halb > 0.0:
		for teil: Array in _lauf_teile(von, nach, tor_x, tor_halb):
			_riegel_hinzu(teil[0], teil[1], yaw, farbe)
	else:
		_riegel_hinzu(von, nach, yaw, farbe)


func _riegel_hinzu(von: Vector3, nach: Vector3, yaw: float, farbe: Color) -> void:
	var laenge := von.distance_to(nach)
	if laenge < 0.3:
		return
	var mitte := (von + nach) * 0.5 + Vector3(0.0, ZAUN_HOEHE * 0.52, 0.0)
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 1.0, laenge))
	_zaun_riegel.append(Transform3D(basis, mitte))
	_zaun_farben_riegel.append(farbe)


## Lauf in Teilstücke links/rechts einer Tor-Lücke zerlegen (nur X-Läufe).
func _lauf_teile(von: Vector3, nach: Vector3, tor_x: float, tor_halb: float) -> Array:
	var links := minf(von.x, nach.x)
	var rechts := maxf(von.x, nach.x)
	var out: Array = []
	if tor_x - tor_halb > links:
		out.append([Vector3(links, 0.0, von.z), Vector3(tor_x - tor_halb, 0.0, von.z)])
	if tor_x + tor_halb < rechts:
		out.append([Vector3(tor_x + tor_halb, 0.0, von.z), Vector3(rechts, 0.0, von.z)])
	return out


## Alle gesammelten Zaun-Posten/-Bretter als zwei MultiMeshes bauen.
func _zaun_abschliessen() -> void:
	var posten_mesh := BoxMesh.new()
	posten_mesh.size = Vector3(0.11, ZAUN_HOEHE, 0.08)
	_zaun_multimesh(posten_mesh, _zaun_posten, _zaun_farben_posten, "ZaunPosten")
	var riegel_mesh := BoxMesh.new()
	riegel_mesh.size = Vector3(0.055, ZAUN_HOEHE * 0.68, 1.0)
	_zaun_multimesh(riegel_mesh, _zaun_riegel, _zaun_farben_riegel, "ZaunRiegel")


func _zaun_multimesh(
	mesh: BoxMesh, transforms: Array[Transform3D], farben: Array[Color], mm_name: String
) -> void:
	if transforms.is_empty():
		return
	mesh.material = _instanzfarben_material()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_color(i, farben[i])
	var instanz := MultiMeshInstance3D.new()
	instanz.name = mm_name
	instanz.multimesh = multi
	instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fern.add_child(instanz)


# ── Natur & Verkehr ──────────────────────────────────────────────────────────


func _baue_natur(rng: RandomNumberGenerator) -> void:
	var baum_pfad := "%s/natur/tree_default.glb" % ASSETS
	var baum_hoehe := _glb_hoehe(baum_pfad)
	if baum_hoehe > 0.0001:
		var mitte := Vector3(_room_rect.size.x * 0.5, 0.0, _room_rect.size.y * 0.5)
		var nah: Array[Transform3D] = []
		for _i in 16:
			var winkel := rng.randf() * TAU
			var radius := rng.randf_range(9.0, 24.0)
			var pos := mitte + Vector3(cos(winkel) * radius, 0.0, sin(winkel) * radius)
			if _zu_nah_an_strasse(pos) or _plot.grow(1.0).has_point(Vector2(pos.x, pos.z)):
				continue
			var basis := (
				Basis(Vector3.UP, rng.randf() * TAU)
				* Basis.from_scale(Vector3.ONE * (rng.randf_range(2.8, 4.4) / baum_hoehe))
			)
			nah.append(Transform3D(basis, pos))
		HomeProps.multi_glb(_fern, baum_pfad, nah, "Baeume", 0.0)
		var fern: Array[Transform3D] = []
		for _i in 18:
			var winkel := rng.randf() * TAU
			var radius := rng.randf_range(44.0, 72.0)
			var pos := mitte + Vector3(cos(winkel) * radius, 0.0, sin(winkel) * radius)
			var basis := (
				Basis(Vector3.UP, rng.randf() * TAU)
				* Basis.from_scale(Vector3.ONE * (rng.randf_range(5.0, 7.5) / baum_hoehe))
			)
			fern.append(Transform3D(basis, pos))
		HomeProps.multi_glb(_fern, baum_pfad, fern, "BaeumeFern", 0.0)
	var busch_pfad := "%s/natur/plant_bush.glb" % ASSETS
	var bueshe: Array[Transform3D] = []
	for _i in 10:
		var x := _plot.position.x + rng.randf() * _plot.size.x
		var z := _z_ab_kante(_strasse_seite, VORGARTEN * rng.randf_range(0.25, 0.8))
		var basis := (
			Basis(Vector3.UP, rng.randf() * TAU)
			* Basis.from_scale(Vector3.ONE * rng.randf_range(0.7, 1.1))
		)
		bueshe.append(Transform3D(basis, Vector3(x, 0.0, z)))
	HomeProps.multi_glb(_fern, busch_pfad, bueshe, "Buesche", LOD_DEKO_M)
	_baue_huegel(rng)


## Horizont-Hügel: weiche, entsättigte Kuppen als EIN MultiMesh — die
## Kulisse endet nicht mehr an einer Rasenkante.
func _baue_huegel(rng: RandomNumberGenerator) -> void:
	var mitte := Vector3(_room_rect.size.x * 0.5, 0.0, _room_rect.size.y * 0.5)
	var kugel := SphereMesh.new()
	kugel.radius = 1.0
	kugel.height = 2.0
	kugel.material = _instanzfarben_material()
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = kugel
	var transforms: Array[Transform3D] = []
	var farben: Array[Color] = []
	for i in 8:
		var winkel := TAU * (i + rng.randf() * 0.5) / 8.0
		var radius := rng.randf_range(110.0, 150.0)
		var pos := mitte + Vector3(cos(winkel) * radius, -2.5, sin(winkel) * radius)
		var skala := Vector3(
			rng.randf_range(34.0, 52.0), rng.randf_range(5.5, 8.5), rng.randf_range(34.0, 52.0)
		)
		transforms.append(Transform3D(Basis.from_scale(skala), pos))
		farben.append(Color("#9CC48B").lerp(HORIZONT, rng.randf_range(0.55, 0.78)))
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		multi.set_instance_color(i, farben[i])
	var instanz := MultiMeshInstance3D.new()
	instanz.name = "Huegel"
	instanz.multimesh = multi
	instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fern.add_child(instanz)


func _zu_nah_an_strasse(pos: Vector3) -> bool:
	return absf(pos.z - _z_strasse) < 4.4


## 3 Autos pendeln auf der Straße (zwei Spuren, Wrap an den Enden).
func _baue_autos(rng: RandomNumberGenerator) -> void:
	var xc := _room_rect.size.x * 0.5
	_auto_spanne = Vector2(xc - 26.0, xc + 26.0)
	var glbs: Array[String] = ["sedan", "taxi", "hatchback-sports"]
	for i in glbs.size():
		var node := HomeProps.modell_glb("%s/autos/%s.glb" % [ASSETS, glbs[i]], AUTO_HOEHE)
		if node == null:
			continue
		var richtung := 1.0 if i % 2 == 0 else -1.0
		node.position = Vector3(
			xc + rng.randf_range(-20.0, 20.0), 0.03, _z_strasse + richtung * 0.85
		)
		node.rotation.y = PI * 0.5 if richtung > 0.0 else -PI * 0.5
		_fern.add_child(node)
		_autos.append({"node": node, "richtung": richtung})
	_process(0.0)


## Gooby-Passanten schlendern auf dem Gehweg (Ping-Pong).
func _baue_npcs(rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(GOOBY_GLB):
		return
	var szene: PackedScene = load(GOOBY_GLB)
	if szene == null:
		return
	var xc := _room_rect.size.x * 0.5
	var seite_raum := -1.0 if _strasse_seite == "S" else 1.0
	var gehweg_z := _z_strasse + seite_raum * (2.0 + GEHWEG * 0.5)
	for i in 2:
		var node: Node3D = szene.instantiate()
		node.name = "PassantGooby%d" % i
		node.scale = Vector3.ONE * GOOBY_SCALE * rng.randf_range(0.85, 1.1)
		_fern.add_child(node)
		var player: AnimationPlayer = node.find_child("AnimationPlayer", true, false)
		if player != null:
			for kandidat: String in ["walk", "walk-loop"]:
				if player.has_animation(kandidat):
					player.play(kandidat)
					break
		(
			_npcs
			. append(
				{
					"node": node,
					"von": Vector3(xc - 11.0 + i * 3.0, 0.0, gehweg_z),
					"nach": Vector3(xc + 11.0 - i * 2.0, 0.0, gehweg_z),
					"tempo": rng.randf_range(0.8, 1.3),
					"phase": rng.randf(),
				}
			)
		)
	_process(0.0)


# ── GLB-Helfer ───────────────────────────────────────────────────────────────


## AABB-Höhe eines GLB in Kit-Einheiten (für MultiMesh-Normalisierung).
func _glb_hoehe(pfad: String) -> float:
	if not ResourceLoader.exists(pfad):
		push_warning("Skyline-Asset fehlt: %s" % pfad)
		return 0.0
	var szene: PackedScene = load(pfad)
	if szene == null:
		return 0.0
	var node: Node3D = szene.instantiate()
	var aabb := HomeProps.merged_aabb(node, Transform3D.IDENTITY)
	node.free()
	return aabb.size.y
