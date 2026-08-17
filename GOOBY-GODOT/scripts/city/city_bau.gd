class_name CityBau
extends RefCounted
## Statische-Kulissen-Bauer der Stadt (FIX-5, aus CityScene ausgelagert):
## baut Boden/Strassen/Laternen, die Orte-Fassaden samt Schildern und
## Props, Karten-Deko, die dichte CityKulisse (MultiMesh-Gruppen) und
## Ampeln — und animiert die Markisen per `tick()`. Alles LICHT (Sonne/
## Himmel/Wetter, Laternen-Nachtteile, Fensterlichter, Schilder-Glow,
## Vögel) besitzt seit W18/J4 die ausgelagerte CityLicht-Schicht (`licht`),
## die der Tagesrhythmus per `setze_licht_stunde()` umschaltet.
## Gameplay (Auto, Verkehr, Fussgaenger, HUD, Routen) bleibt in CityScene;
## die nutzt hier nur `lade_glb()`/`faerbe()`/`haenge_autolichter()` als
## Mesh-Werkzeuge und liest `colliders`/`ampel_*` als Bau-Ergebnis.

const ASSETS := "res://assets/city"
## Kleinteile (Blumen, Hydranten, Kuebel) blenden ab dieser Distanz aus —
## spart Draw-Calls/Fill, ohne dass die Silhouette der Stadt leidet.
const KLEINTEIL_SICHT_M := 170.0

## W18/4-B12: Halbes Kollider-Mass der Ort-Fassaden-Tiles (m) — vorher ein
## nacktes 7.5 im Bau-Code. Als Konstante benannt, damit der Parkfeld-
## Waechter (test_w18_g6_fixes) JEDES Park-Pad gegen exakt dieses Mass
## prueft (Pad + Auto-Radius muessen AUSSERHALB liegen, sonst Punch).
const ORT_COLLIDER_HALB_M := 7.5

## Distrikt-Grundfarben fuer Boden-Pads unter den Vierteln — bewusst etwas
## dunkler/waermer, damit die Bloecke als Plaster/Gruen lesen statt als
## weisse Leere auszubrennen (FIX-5 Review-Iteration).
const DISTRIKT_FARBEN := {
	"gewerbe": Color(0.70, 0.67, 0.60),
	"zentrum": Color(0.74, 0.69, 0.58),
	"wohnen": Color(0.64, 0.70, 0.54),
	"park": Color(0.55, 0.71, 0.47),
	"flughafen": Color(0.68, 0.68, 0.71),
}

## W14-Fassaden-Varianz (Sicht-Diagnose „weisse Haeuserzeilen"): Kulissen-
## Gebaeude OHNE Tint bekommen deterministisch eine Pastell-Toenung —
## bewusst kurze Liste (jede glb|tint-Sorte ist eine MultiMesh-Gruppe,
## Draw-Call-Budget!), Farben aus den bestehenden Kulissen-Paletten.
const FASSADEN_NACHTINTS: Array[String] = ["#F2C14E", "#8FD0E8", "#FF9E7D", "#B5E48C"]

## Bau-Ergebnisse, die CityScene fuers Gameplay braucht: Auto-Kollisions-
## AABBs, Ampel-Birnen (Instanzfarben) + Achsen/Kreuzungs-Lookup.
var colliders: Array[Dictionary] = []
var ampel_mm: MultiMesh
var ampel_achsen: Array[bool] = []
var ampel_lookup: Dictionary = {}

## W18/J4: die Licht-/Rhythmus-Schicht (Sonne/Wetter/Laternen/Fenster/
## Schilder/Vögel) — teilt sich _fenster_gebaeude per Array-Referenz.
var licht: CityLicht

## W13/WETTER-FX: Tests/Screenshots erzwingen eine Wetterlage ({} = echter
## SoulWetter-Tagesplan, gleiche API wie das Zuhause) — lebt in CityLicht,
## hier nur als stabile Durchreiche für bestehende Aufrufer.
var wetter_override: Dictionary:
	get:
		return licht.wetter_override
	set(wert):
		licht.wetter_override = wert

var _szene: Node3D
var _karte: CityMap

var _glb_mesh_cache: Dictionary = {}
var _markisen: Array[Dictionary] = []
var _markisen_zeit := 0.0
var _fenster_gebaeude: Array[Dictionary] = []
## GOOBY-WELT/STADT: baut die unterscheidbare Orts-Architektur (Portale,
## 3D-Logos, Schaufenster, Vorplatz-Requisiten) aus CityOrtArchitektur.
var _ort_bau: CityOrtBau


func _init(szene: Node3D, karte: CityMap, licht_profil: Dictionary, stunde := 12.0) -> void:
	_szene = szene
	_karte = karte
	licht = CityLicht.new(szene, karte, licht_profil, stunde, _fenster_gebaeude)
	_ort_bau = CityOrtBau.new(self)


## Kulissen-/Deko-GLBs liegen normalerweise unter assets/city; die CC0-Pools
## (W18/J4) tragen volle res://-Pfade — die werden unverändert durchgereicht.
static func glb_pfad(glb: String) -> String:
	if glb.begins_with("res://"):
		return glb
	return "%s/%s" % [ASSETS, glb]


## W14-Fassaden-Varianz, pure Funktion (test_w14_camcity.gd): tintlose
## Kulissen-Gebäude/-Häuser bekommen deterministisch je glb-Sorte EINEN
## Pastellton aus FASSADEN_NACHTINTS — gleicher Gruppen-Schlüssel für alle
## Exemplare der Sorte, also KEINE neue MultiMesh-Gruppe (Draw-Call-neutral).
static func fassaden_tint(glb: String, tint: String, kategorie: String) -> String:
	if not tint.is_empty():
		return tint
	if kategorie != "gebaeude" and kategorie != "haus":
		return tint
	return FASSADEN_NACHTINTS[posmod(hash(glb), FASSADEN_NACHTINTS.size())]


## Der echte Stadt-Wetterplan (stabile API für Tests — Impl in CityLicht).
static func wetter_jetzt(stunde: float, datum := "") -> Dictionary:
	return CityLicht.wetter_jetzt(stunde, datum)


## Sanfte Dauer-Animationen der Kulisse (Markisen wehen, Voegel kreisen).
func tick(delta: float) -> void:
	_tick_markisen(delta)
	licht.tick_voegel(delta)


## Tag/Nacht-Licht, Himmel + Wetter-FX — Impl in CityLicht (W18/J4).
func baue_licht() -> void:
	licht.baue()


## W18/J4 „Stadt-Tagesrhythmus": die GEBAUTE Stadt auf eine neue Uhrzeit
## umschalten, ohne irgendetwas neu zu instanzieren — Impl in CityLicht.
func setze_licht_stunde(stunde: float) -> void:
	licht.setze_stunde(stunde)


## Aktuelles (dynamisch nachgeführtes) Licht-Profil — CityScene liest
## lichter_an daraus für Auto-Scheinwerfer.
func licht_profil() -> Dictionary:
	return licht.profil()


## Bau-Wetterlage der Stadt (für Tests/andere Systeme).
func wetter() -> Dictionary:
	return licht.wetter()


## Die eingehängte Wetter-Komponente (für Tests/Debug; null vor baue_licht).
func wetter_fx() -> WetterFx:
	return licht.wetter_fx()


func baue_boden() -> void:
	var boden := MeshInstance3D.new()
	boden.name = "Boden"
	var mesh := PlaneMesh.new()
	var halb := _karte.welt_halb()
	mesh.size = Vector2(halb.x * 2.0 + 80.0, halb.y * 2.0 + 80.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.72, 0.45)
	mesh.material = mat
	boden.mesh = mesh
	_szene.add_child(boden)
	# Dezente Distrikt-Pads unter den Vierteln
	for pad_name: String in _karte.daten.get("distrikte", {}):
		for zone: Array in _karte.daten["distrikte"][pad_name].get("zonen", []):
			var pad := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			var breite := (float(zone[3]) - float(zone[1]) + 1.0) * _karte.tile_m
			var tiefe := (float(zone[2]) - float(zone[0]) + 1.0) * _karte.tile_m
			pm.size = Vector2(breite, tiefe)
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = DISTRIKT_FARBEN.get(pad_name, Color(0.8, 0.8, 0.8))
			pm.material = pmat
			pad.mesh = pm
			pad.position = _karte.welt_von(
				(float(zone[0]) + float(zone[2])) / 2.0, (float(zone[1]) + float(zone[3])) / 2.0
			)
			pad.position.y = 0.05
			_szene.add_child(pad)


## Straßen als MultiMesh-Gruppen (FIX-5 Draw-Call-Budget): ein Draw-Call je
## Stück-Sorte statt je Tile — Rotation steckt in der Instanz-Transform.
func baue_strassen() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Strassen"
	_szene.add_child(wurzel)
	var gruppen: Dictionary = {}
	for tile in _karte.strassen_tiles():
		var glb: String
		var rot := 0
		if _karte.ist_kreisel(tile):
			glb = "road-roundabout"
		else:
			var stueck := CityMap.road_piece_for(
				_karte.ist_strasse(tile + Vector2i(-1, 0)),
				_karte.ist_strasse(tile + Vector2i(0, 1)),
				_karte.ist_strasse(tile + Vector2i(1, 0)),
				_karte.ist_strasse(tile + Vector2i(0, -1))
			)
			glb = str(stueck["piece"])
			rot = int(stueck["rot_grad"])
		if not gruppen.has(glb):
			gruppen[glb] = [] as Array[Transform3D]
		var basis := Basis(Vector3.UP, deg_to_rad(float(rot))).scaled(Vector3.ONE * _karte.tile_m)
		var liste: Array[Transform3D] = gruppen[glb]
		liste.append(Transform3D(basis, _karte.tile_zu_welt(tile)))
	for glb: String in gruppen:
		_baue_multimesh(wurzel, "%s/strassen/%s.glb" % [ASSETS, glb], gruppen[glb])


## Straßenlaternen (W4-P3 POLISH-8): deterministisch auf jedem 3. Straßen-
## Tile (Kenney streetlight) — als EIN Masten-MultiMesh; bei Dämmerung/Nacht
## kommt EIN Birnen-MultiMesh mit warmem Emissiv dazu (2 Draw-Calls gesamt,
## bewusst OHNE echte OmniLights, Mobile-Budget A §7).
func baue_laternen() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Laternen"
	_szene.add_child(wurzel)
	var posten: Array[Transform3D] = []
	for tile in _karte.strassen_tiles():
		if _karte.ist_kreisel(tile) or (tile.x + tile.y) % 3 != 0:
			continue
		var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * 5.0)
		posten.append(Transform3D(basis, _karte.tile_zu_welt(tile) + Vector3(7.0, 0.4, 7.0)))
	var pfad := "%s/deko/streetlight.gltf" % ASSETS
	_baue_multimesh(wurzel, pfad, posten)
	# Nacht-Teile (Birnen + Lichtkegel) besitzt die Licht-Schicht; die
	# Kopfhöhe ist hier billig (der Mesh-Cache ist durch _baue_multimesh warm).
	licht.melde_laternen(wurzel, posten, _glb_hoehe(pfad) * 0.94 * 5.0)


func baue_orte() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Orte"
	_szene.add_child(wurzel)
	for eintrag: Dictionary in _karte.orte():
		var fassade: Dictionary = eintrag.get("fassade", {})
		var tiles: Array = eintrag.get("tiles", [[0, 0]])
		var erste := CityMap._tile_von(tiles[0])
		var strasse := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		var mitte := _karte.tile_zu_welt(erste)
		var glb := str(fassade.get("glb", "building-a"))
		# Leeres glb = Ort unter freiem Himmel (Wochenmarkt) — der steht als
		# Marktstand-Deko in der Karte, hier gibt es kein Gebäude zu laden.
		var gebaeude: Node3D = null
		if not glb.is_empty():
			gebaeude = lade_glb("%s/gebaeude/%s.glb" % [ASSETS, glb], 10.0)
		if gebaeude != null:
			gebaeude.position = mitte
			# Gebäude stehen NEBEN den 0,4 m dicken Straßenplatten auf dem
			# Distrikt-Pad (y=0,05) — nicht auf Straßenhöhe (schwebt sonst).
			gebaeude.position.y = 0.05
			gebaeude.rotation.y = _rot_zu(erste, strasse)
			# W14: tintlose Orte-Fassaden bekommen den Pastell-Nachtint.
			_tinte(gebaeude, fassaden_tint(glb, str(fassade.get("tint", "")), "gebaeude"))
			wurzel.add_child(gebaeude)
			(
				_fenster_gebaeude
				. append(
					{
						"glb": "gebaeude/%s.glb" % glb,
						"pos": gebaeude.position,
						"rot_grad": rad_to_deg(gebaeude.rotation.y),
						"scale": 10.0,
					}
				)
			)
			if bool(fassade.get("awning", false)):
				var markise := lade_glb("%s/gebaeude/detail-awning-wide.glb" % ASSETS, 10.0)
				if markise != null:
					markise.position = mitte + Vector3(0, 0.05, 0)
					markise.rotation.y = _rot_zu(erste, strasse)
					markise.translate_object_local(Vector3(0, 0.32, 0.52))
					wurzel.add_child(markise)
					_markisen.append({"node": markise, "basis_rot": markise.rotation})
		# Namensschild überm Eingang (nachts leuchtend, s. CityLicht.melde_schild)
		var zur_strasse := _karte.tile_zu_welt(strasse) - mitte
		# GOOBY-WELT/STADT (EVAL B §2 „übergroße Labels statt Architektur"):
		# Schilder hängen jetzt KLEIN und niedrig an der Fassade — die
		# Wiedererkennung übernimmt die Orts-Architektur. Nachbarblöcke
		# bleiben leicht versetzt (sonst Buchstabensalat aus der Ferne).
		var hoehe := 5.6 + float(erste.x % 2) * 0.8
		_haenge_schild(
			wurzel,
			I18nService.t(str(eintrag.get("name_key", ""))),
			mitte,
			zur_strasse,
			hoehe,
			str(fassade.get("tint", ""))
		)
		var richtung_schild := zur_strasse
		richtung_schild.y = 0.0
		if richtung_schild.length() < 0.01:
			richtung_schild = Vector3.BACK
		var neon := _ort_bau.baue(
			wurzel, str(eintrag.get("id", "")), mitte, richtung_schild.normalized()
		)
		if neon != null:
			licht.melde_neon(neon)
		# Kollisions-AABBs für alle Ort-Tiles
		for tile_raw: Array in tiles:
			_collider_fuer_tile(CityMap._tile_von(tile_raw), ORT_COLLIDER_HALB_M)


## Namensschild über einem Eingang (VIS-2 lesbar, GOOBY-WELT/STADT klein/
## diegetisch): OrtSchild-Billboard mit Mindest-Bildschirmgröße (wächst ab
## 40 m mit der Entfernung), weichem Fern-Ausblenden und IMMER einer
## Kontrast-Tafel — tagsüber Creme hinter der Tinten-Schrift, nachts der
## warme Glow (CityLicht._lass_schild_leuchten). Seit dem Architektur-Pass
## hängt es KLEIN direkt über dem Portal statt riesig überm Dach.
func _haenge_schild(
	wurzel: Node3D, text: String, mitte: Vector3, zur_strasse: Vector3, hoehe: float, tint: String
) -> void:
	var an: bool = licht.profil()["lichter_an"]
	var schild := OrtSchild.new()
	schild.text = text
	schild.font_size = 104
	schild.pixel_size = 0.013
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	schild.modulate = CityAmbiente.schild_farbe(an)
	schild.outline_size = 22
	# Beide sind kamerazugewandte Billboards und damit koplanar — ohne feste
	# Sortierung z-fightet die Tafel mit der Schrift (halbe Buchstaben weg).
	schild.render_priority = 1
	schild.outline_render_priority = 0
	# Über dem EINGANG, nicht über der Tile-Mitte: mittig verschluckt die
	# Fassade (und der Nachbarblock) die halbe Schrift.
	var richtung := zur_strasse
	richtung.y = 0.0
	if richtung.length() < 0.01:
		richtung = Vector3.BACK
	schild.position = mitte + richtung.normalized() * 6.6 + Vector3(0, hoehe, 0)
	wurzel.add_child(schild)
	licht.melde_schild(schild, tint)


## Straßenbild-Extras (GOOBY-WELT/STADT, EVAL B §2): Zebrastreifen,
## Mülltonnen-Vielfalt, Bushaltestellen, Tauben-Grüppchen und die
## Café-Terrasse am Stadtpark — Plan in CityStrassenDeko (pur),
## Nodes in CityStrassenDekoBau (MultiMesh, ~20 Draw-Calls gesamt).
func baue_strassenbild() -> void:
	CityStrassenDekoBau.new(self).baue(_szene, _karte)


func baue_deko() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Deko"
	_szene.add_child(wurzel)
	for eintrag: Dictionary in _karte.deko():
		var tile: Array = eintrag.get("tile", [0, 0])
		var node := lade_glb(
			glb_pfad(str(eintrag.get("glb", ""))), float(eintrag.get("scale", 10.0))
		)
		if node == null:
			continue
		node.position = _karte.welt_von(float(tile[0]), float(tile[1]))
		node.position.y = 0.05
		node.rotation_degrees.y = float(eintrag.get("rot", 0))
		var glb_name := str(eintrag.get("glb", ""))
		# W14: tintlose Deko-Gebäude (Türme) pastellig nachtönen — Markisen/
		# Kisten (kein Gebäude-Pfad) bleiben unangetastet. W18/J4: die CC0-
		# Vorstadt-Häuser (haus_a…f, spielerhaus) zählen als Kategorie "haus".
		var ist_vorstadt := glb_name.begins_with(CityKulisse.CC0_VORSTADT)
		var kategorie := ""
		if ist_vorstadt:
			kategorie = "haus"
		elif glb_name.begins_with("gebaeude/"):
			kategorie = "gebaeude"
		_tinte(node, fassaden_tint(glb_name, str(eintrag.get("tint", "")), kategorie))
		wurzel.add_child(node)
		if not kategorie.is_empty():
			# CC0-Häuser sind breiter als die 1er-Kenney-Würfel (Fußabdruck
			# ~1,3 Modelleinheiten) — Collider entsprechend größer.
			var halb := float(eintrag.get("scale", 10.0)) * (0.6 if ist_vorstadt else 0.5)
			_collider_bei(node.position, halb)
			if glb_name.find("building") >= 0 and glb_name.find("low-detail") < 0:
				(
					_fenster_gebaeude
					. append(
						{
							"glb": glb_name,
							"pos": node.position,
							"rot_grad": float(eintrag.get("rot", 0)),
							"scale": float(eintrag.get("scale", 10.0)),
						}
					)
				)
		# Deko mit Namensschild (IKEA): gleiche Schild-Mechanik wie die Orte,
		# damit auch die „nur gucken"-Gebäude lesbar sind.
		var name_key := str(eintrag.get("name_key", ""))
		if not name_key.is_empty():
			var strasse := CityMap._tile_von(eintrag.get("schild_strasse", [0, 0]))
			var zur_strasse := _karte.tile_zu_welt(strasse) - node.position
			var hoehe := float(eintrag.get("scale", 10.0)) * 0.85
			_haenge_schild(
				wurzel,
				I18nService.t(name_key),
				node.position,
				zur_strasse,
				hoehe,
				str(eintrag.get("schild_tint", ""))
			)


## Kulissen-Dichte (FIX-5 Kern): den CityKulisse-Plan als MultiMesh-Gruppen
## einhängen — Häuserzeilen/Gärten/Park/Straßenmöbel/Bordstein-Parker.
## Kleinteile bekommen einen Sichtbarkeitsbereich (Quadranten-Bündel).
func baue_kulisse() -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Kulisse"
	_szene.add_child(wurzel)
	var plaene := CityKulisse.plaene(_karte, _karte.deko_seed())
	# FB-2 Stadt-Grün: Straßenbäume/Hecken/Blumenkästen/Efeu/Blumenampeln
	# in DENSELBEN Plan mischen — gleiche glb|tint-Sorten teilen sich das
	# MultiMesh, das Grün kostet also kaum zusätzliche Draw-Calls.
	plaene.append_array(CityGruen.plaene(_karte, _karte.deko_seed() + 917))
	# W14-Fassaden-Varianz: tintlose Gebäude nachtönen (Gruppen-neutral).
	for eintrag: Dictionary in plaene:
		eintrag["tint"] = fassaden_tint(
			str(eintrag.get("glb", "")),
			str(eintrag.get("tint", "")),
			str(eintrag.get("kategorie", ""))
		)
	var gruppen := CityKulisse.gruppen(plaene)
	var schluessel: Array = gruppen.keys()
	schluessel.sort()
	for key: String in schluessel:
		var gruppe: Dictionary = gruppen[key]
		var pfad := glb_pfad(str(gruppe["glb"]))
		var sicht := KLEINTEIL_SICHT_M if bool(gruppe["klein"]) else 0.0
		_baue_multimesh(wurzel, pfad, gruppe["transforms"], str(gruppe["tint"]), sicht)
	# Kollisionen + Nachtfenster aus dem Plan (Gebäude blocken, Parker auch).
	for eintrag: Dictionary in plaene:
		match str(eintrag.get("kategorie", "")):
			"gebaeude", "haus":
				_collider_bei(eintrag["pos"], float(eintrag["scale"]) * 0.45)
				if str(eintrag["glb"]).find("low-detail") < 0:
					(
						_fenster_gebaeude
						. append(
							{
								"glb": str(eintrag["glb"]),
								"pos": eintrag["pos"],
								"rot_grad": float(eintrag.get("rot_grad", 0.0)),
								"scale": float(eintrag["scale"]),
							}
						)
					)
			"parkauto":
				_collider_bei(eintrag["pos"], 1.7)
			_:
				pass


## Ampeln an den echten Kreuzungen (FIX-5 „Leben"): Masten als MultiMesh,
## alle Birnen in EINEM MultiMesh mit Instanzfarben — tags rot/grün im
## CityVerkehr-Takt, nachts gelbes Kleinstadt-Blinken. 3 Draw-Calls gesamt.
func baue_ampeln() -> void:
	var tiles := CityVerkehr.ampel_tiles(_karte)
	ampel_lookup.clear()
	for tile in tiles:
		ampel_lookup[tile] = true
	if tiles.is_empty():
		return
	var wurzel := Node3D.new()
	wurzel.name = "Ampeln"
	_szene.add_child(wurzel)
	var masten: Array[Transform3D] = []
	var birnen: Array[Vector3] = []
	ampel_achsen.clear()
	var pfad := "%s/strassen/light-curved.glb" % ASSETS
	var kopf_hoehe := _glb_hoehe(pfad) * 7.0
	for tile in tiles:
		var mitte := _karte.tile_zu_welt(tile)
		# Zwei Masten je Kreuzung, diagonal — einer zeigt die N/S-, einer
		# die O/W-Phase (stilisiert, lesbar, billig).
		for ecke: Array in [[Vector3(7.2, 0.0, 7.2), false], [Vector3(-7.2, 0.0, -7.2), true]]:
			var offset: Vector3 = ecke[0]
			var zur_mitte := -offset.normalized()
			var rot := atan2(-zur_mitte.x, -zur_mitte.z)
			var basis := Basis(Vector3.UP, rot).scaled(Vector3.ONE * 7.0)
			masten.append(Transform3D(basis, mitte + offset + Vector3(0.0, 0.4, 0.0)))
			birnen.append(
				mitte + offset + zur_mitte * 1.5 + Vector3(0.0, kopf_hoehe * 0.92 + 0.4, 0.0)
			)
			ampel_achsen.append(bool(ecke[1]))
	_baue_multimesh(wurzel, pfad, masten)
	var kugel := SphereMesh.new()
	kugel.radius = 0.34
	kugel.height = 0.68
	kugel.radial_segments = 8
	kugel.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	kugel.material = mat
	ampel_mm = MultiMesh.new()
	ampel_mm.transform_format = MultiMesh.TRANSFORM_3D
	ampel_mm.use_colors = true
	ampel_mm.mesh = kugel
	ampel_mm.instance_count = birnen.size()
	for i in birnen.size():
		ampel_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, birnen[i]))
		ampel_mm.set_instance_color(i, CityVerkehr.FARBE_ROT)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "AmpelBirnen"
	mmi.multimesh = ampel_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## Nachts leuchten Fenster — Impl in CityLicht (Quellen: _fenster_gebaeude).
func baue_fenster() -> void:
	licht.baue_fenster()


## Vögel überm Park (tagsüber, im Spar-Modus aus) — Impl in CityLicht.
func baue_voegel(reduziert: bool) -> void:
	licht.baue_voegel(reduziert)


## Scheinwerfer-Paar (POLISH-8): zwei warme Emissiv-Kugeln an der Front
## (lokale Model-Einheiten — der Wagen-Root ist bereits skaliert).
## W18/J4: sitzt in einem eigenen "Autolichter"-Container, den der
## Rhythmus-Tick per Sichtbarkeit schaltet (bei Dämmerung an, morgens aus).
func haenge_autolichter(wagen: Node3D, an := true) -> Node3D:
	var front := _aabb_grenze_z(wagen)
	var lichter := Node3D.new()
	lichter.name = "Autolichter"
	lichter.visible = an
	wagen.add_child(lichter)
	for seite: float in [-1.0, 1.0]:
		var licht := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.05
		kugel.height = 0.1
		kugel.radial_segments = 8
		kugel.rings = 4
		licht.mesh = kugel
		licht.material_override = CityAmbiente.leuchten_material(Color(1.0, 0.95, 0.75), 2.2)
		licht.position = Vector3(seite * 0.22, 0.25, front)
		lichter.add_child(licht)
	return lichter


## Markisen wehen sacht (FIX-5 „Liebe zum Detail") — nur die 9 Orts-
## Markisen sind eigene Nodes, die Kulissen-Markisen bleiben statisch.
func _tick_markisen(delta: float) -> void:
	_markisen_zeit += delta
	for i in _markisen.size():
		var eintrag: Dictionary = _markisen[i]
		var node: Node3D = eintrag["node"]
		var basis_rot: Vector3 = eintrag["basis_rot"]
		node.rotation.x = basis_rot.x + sin(_markisen_zeit * 1.3 + float(i) * 1.7) * 0.035


## Vorderkante (+Z, lokale Model-Einheiten) des Wagens.
func _aabb_grenze_z(node: Node3D) -> float:
	var kante := 0.6
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var aabb := mi.get_aabb()
		kante = maxf(kante, mi.position.z + aabb.position.z + aabb.size.z)
	return kante


func _collider_fuer_tile(tile: Vector2i, halb: float) -> void:
	_collider_bei(_karte.tile_zu_welt(tile), halb)


func _collider_bei(mitte: Vector3, halb: float) -> void:
	(
		colliders
		. append(
			{
				"min_x": mitte.x - halb,
				"max_x": mitte.x + halb,
				"min_z": mitte.z - halb,
				"max_z": mitte.z + halb,
			}
		)
	)


## GLB/GLTF instanzieren + uniform skalieren (null bei Fehlpfad).
func lade_glb(pfad: String, groesse: float) -> Node3D:
	if not ResourceLoader.exists(pfad):
		push_warning("Asset fehlt: %s" % pfad)
		return null
	var szene: PackedScene = load(pfad)
	if szene == null:
		return null
	var node: Node3D = szene.instantiate()
	node.scale = Vector3.ONE * groesse
	return node


## Alle Meshes eines GLBs mit ihrer Transform relativ zur GLB-Wurzel
## (gecacht — die Kulisse fragt dieselben Kits oft).
func _glb_meshes(pfad: String) -> Array[Dictionary]:
	if _glb_mesh_cache.has(pfad):
		return _glb_mesh_cache[pfad]
	var teile: Array[Dictionary] = []
	if not ResourceLoader.exists(pfad):
		push_warning("Asset fehlt: %s" % pfad)
		_glb_mesh_cache[pfad] = teile
		return teile
	var szene: PackedScene = load(pfad)
	if szene != null:
		var proto: Node3D = szene.instantiate()
		for mesh in proto.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = mesh
			var rel := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != proto:
				if n is Node3D:
					rel = (n as Node3D).transform * rel
				n = n.get_parent()
			teile.append({"mesh": mi.mesh, "xform": rel})
		proto.free()
	_glb_mesh_cache[pfad] = teile
	return teile


## Höhe (lokale Model-Einheiten) des höchsten Meshes eines GLBs.
func _glb_hoehe(pfad: String) -> float:
	var top := 0.8
	for teil in _glb_meshes(pfad):
		var mesh: Mesh = teil["mesh"]
		var xform: Transform3D = teil["xform"]
		var aabb: AABB = xform * mesh.get_aabb()
		top = maxf(top, aabb.position.y + aabb.size.y)
	return top


## N Instanzen eines GLBs als MultiMesh-Knoten (einer je Mesh im GLB):
## kostet so viele Draw-Calls wie EIN Exemplar. Optional getönt und mit
## Sichtbarkeits-Ende (Kleinteile) — der Knoten-Ursprung liegt im
## Schwerpunkt der Instanzen, damit das Distanz-Culling fair misst.
func _baue_multimesh(
	wurzel: Node3D, pfad: String, transforms: Array[Transform3D], tint := "", sicht_ende := 0.0
) -> void:
	if transforms.is_empty():
		return
	var teile := _glb_meshes(pfad)
	if teile.is_empty():
		return
	var mitte := Vector3.ZERO
	for t in transforms:
		mitte += t.origin
	mitte /= float(transforms.size())
	for teil: Dictionary in teile:
		var mesh: Mesh = teil["mesh"]
		if not tint.is_empty():
			mesh = _getoentes_mesh(mesh, Color.from_string(tint, Color.WHITE))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		var rel: Transform3D = teil["xform"]
		for i in transforms.size():
			var welt: Transform3D = transforms[i] * rel
			welt.origin -= mitte
			mm.set_instance_transform(i, welt)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % pfad.get_file().get_basename()
		mmi.position = mitte
		mmi.multimesh = mm
		if sicht_ende > 0.0:
			mmi.visibility_range_end = sicht_ende
			# Kleinteile werfen keine Schatten — halbiert ihre Draw-Calls.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(mmi)


## Mesh-Kopie mit getönten Material-Duplikaten (fürs MultiMesh — dort gibt
## es keine Surface-Overrides pro Instanz, die Gruppe teilt sich die Tönung).
func _getoentes_mesh(mesh: Mesh, farbe: Color) -> Mesh:
	var kopie: Mesh = mesh.duplicate()
	for i in kopie.get_surface_count():
		var mat: Material = kopie.surface_get_material(i)
		if mat is StandardMaterial3D:
			var neu: StandardMaterial3D = mat.duplicate()
			neu.albedo_color = neu.albedo_color.lerp(farbe, 0.65)
			kopie.surface_set_material(i, neu)
	return kopie


## Fassaden-/Deko-Tint: alle Mesh-Materialien duplizieren + einfärben.
func _tinte(node: Node3D, hex: String) -> void:
	if hex.is_empty():
		return
	faerbe(node, Color.from_string(hex, Color.WHITE), 0.65)


func faerbe(node: Node3D, farbe: Color, staerke: float) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, staerke)
				mi.set_surface_override_material(i, kopie)


## Rotation, damit die geauthorte Front (+Z) zum Straßen-Tile zeigt.
func _rot_zu(von: Vector2i, nach: Vector2i) -> float:
	var richtung := Vector2(float(nach.y - von.y), float(nach.x - von.x))
	return atan2(richtung.x, richtung.y)
