class_name OrtLeben
extends Node3D
## G7-P55 „Läden lebendig“ — wiederverwendbares Ambient-Leben für die
## Stadt-Orte (User-Feedback: „Läden sind einfach LEER statt richtige
## Orte“). Pro Ort spawnen N Besucher-Goobys, die deterministisch (Tages-
## Seed) auf einfachen Wegpunkt-Schleifen schlendern, an den Punkten die
## Regale anschauen (umsehen/greifen), zufällige Fell-/Hut-Varianten
## tragen und ab und zu einen kurzen Spruch über die AcBubble-API machen.
##
## Anschluss für neue Orte = ~15 Zeilen: `OrtScene._leben_konfig()`
## überschreiben und ein Dictionary liefern:
##   {"besucher": 3, "punkte": [Vector3, …], "sprueche": "laden",
##    "gemurmel": true, "tuer_glocke": true, "kasse": true}
## Sprüche leben in strings/<locale>/city_leben.json unter
## `city_leben.sprueche.<domain>` (DE führend, EN paritätisch).
##
## Performance (iPhone-Budget, Muster CityScene-Fußgänger): Besucher sind
## das ROHE gooby.glb + AnimationPlayer (keine GoobyRig-Maschinerie),
## Tints und Hut-Materialien kommen aus GETEILTEN Caches, Bewegung ist
## reine Wegpunkt-Interpolation ohne Physik. Reduced Motion: halbe
## Besucherzahl und alle stehen statisch (kein _update pro Frame).

const GOOBY_GLB := "res://assets/character/gooby.glb"
## Schlender-Tempo (m/s) — im Laden noch gemütlicher als auf der Straße.
const TEMPO_MIN := 0.45
const TEMPO_MAX := 0.85
## Regal-Schau-Pause an jedem Wegpunkt (s).
const PAUSE_MIN_S := 2.5
const PAUSE_MAX_S := 6.0
## Anteil der Besucher mit Hut; Anteil der Regal-Greifer je Pause.
const HUT_ANTEIL := 0.6
const GREIFER_ANTEIL := 0.5
## Spruch-Takt: erster Spruch nach START + i·VERSATZ, danach alle ALLE_S.
const SPRUCH_START_S := 6.0
const SPRUCH_VERSATZ_S := 9.0
const SPRUCH_ALLE_S := 24.0
const SPRUCH_DAUER_S := 3.2
## Tür-Glöckchen = helles Bestands-Bell-Sample, hochgestimmt.
const GLOCKE_ID := "gvz_wave"
const GLOCKE_PITCH := 1.35
## Leises Marktgemurmel (Bestands-Loop aus der Ranch-Familie, −10 dB).
const GEMURMEL_ID := "ranch_menge_gemurmel"
## Hut-Palette (AC-Pastell, bewusst ≠ Fellfarben).
const HUT_FARBEN: Array[String] = ["#E8524A", "#4E79D6", "#3E8E5A", "#F2A03D"]
## Seitlicher Zufalls-Versatz je Wegpunkt (m) — Besucher stapeln sich nie.
const PUNKT_JITTER_M := 0.35

## Geteilte Material-Caches (über alle Orte hinweg): Fell-Tints je
## (Basismaterial, Farbe) und Hut-Materialien je Farbe.
static var _tint_cache: Dictionary = {}
static var _hut_mat_cache: Dictionary = {}
## Spruch-Rotation je Domain (Muster UrlaubsSprueche: nichts wiederholt
## sich, bevor alle Zeilen dran waren).
static var _spruch_zaehler: Dictionary = {}

## Konfig (s. Klassen-Docstring) — VOR add_child setzen.
var konfig: Dictionary = {}
## UI-Layer für die AcBubble-Sprüche (null = stumm, z. B. in Purzeltests).
var ui_layer: Control
## Test-Hooks: fester Seed statt Tages-Seed, Reduced-Motion erzwingen,
## Zeit von Hand füttern (auto_zeit = false + advance_zeit, Muster AcBubble).
var seed_override := -1
var reduced_override := -1
var auto_zeit := true
## Test-Hook: true = Glocke/Gemurmel nicht STARTEN (die Samples klingen
## beim Headless-Runner-Exit sonst nach → ObjectDB-Leak-Warnung). Die
## Verdrahtung selbst prüfen Tests über die Konfig-Flags.
var stumm := false

var _besucher: Array[Dictionary] = []
var _zeit := 0.0
var _statisch := false
var _gemurmel_an := false


func _ready() -> void:
	var basis_seed := seed_override
	if basis_seed < 0:
		basis_seed = tages_seed(str(konfig.get("ort_id", name)))
	var alle := plaene(konfig, basis_seed)
	if _reduziert():
		_statisch = true
		alle = alle.slice(0, maxi(1, alle.size() / 2))
	_spawne_besucher(alle)
	if bool(konfig.get("tuer_glocke", false)) and not stumm:
		AudioDirector.try_play(self, GLOCKE_ID, GLOCKE_PITCH)
	if bool(konfig.get("gemurmel", false)) and not stumm:
		AudioDirector.try_start_loop(self, GEMURMEL_ID)
		_gemurmel_an = true
	_update_besucher()
	set_process(not _besucher.is_empty())


func _exit_tree() -> void:
	if _gemurmel_an:
		AudioDirector.try_stop_loop(self, GEMURMEL_ID)
		_gemurmel_an = false


func _process(delta: float) -> void:
	if auto_zeit:
		advance_zeit(delta)


## Zeit hereinreichen (vom _process ODER von Tests): Schlendern und
## Spruch-Takt laufen über DIESEN Takt; statische Besucher (Reduced
## Motion) bleiben stehen, sprechen aber weiter.
func advance_zeit(delta: float) -> void:
	_zeit += delta
	if not _statisch:
		_update_besucher()
	_update_sprueche(delta)


## ------------------------------------------------------------ Pure Planung


## Deterministischer Tages-Seed: gleicher Tag + gleicher Ort ⇒ gleiche
## Besucherschar (Muster MarktSim/RanchWetter).
static func tages_seed(ort_id: String) -> int:
	var d := Time.get_date_dict_from_system()
	var tag := "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
	return int(hash("%s|%s" % [tag, ort_id])) & 0x7FFFFFFF


## Besucher-Pläne würfeln (PURE, headless testbar). Je Besucher: eigene
## 3-Punkte-Schleife aus den Konfig-Wegpunkten (mit Jitter), Schlender-
## Tempo, Schau-Pause, Startphase, Fellfarbe, Hut und Greif-Flag.
static func plaene(plan_konfig: Dictionary, seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var punkte_raw: Variant = plan_konfig.get("punkte", [])
	var punkte: Array = punkte_raw if punkte_raw is Array else []
	var anzahl := int(plan_konfig.get("besucher", 0))
	if punkte.size() < 2 or anzahl <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	for i in anzahl:
		var eigene: Array[Vector3] = []
		var idx := i % punkte.size()
		for _schritt in mini(3, punkte.size()):
			var jitter := Vector3(
				rng.randf_range(-PUNKT_JITTER_M, PUNKT_JITTER_M),
				0.0,
				rng.randf_range(-PUNKT_JITTER_M, PUNKT_JITTER_M)
			)
			eigene.append(Vector3(punkte[idx]) + jitter)
			idx = (idx + 1 + rng.randi_range(0, punkte.size() - 2)) % punkte.size()
		var felle := CityFussgaenger.FELLE
		(
			out
			. append(
				{
					"punkte": eigene,
					"tempo": rng.randf_range(TEMPO_MIN, TEMPO_MAX),
					"pause_s": rng.randf_range(PAUSE_MIN_S, PAUSE_MAX_S),
					"phase": rng.randf(),
					"tint": Color(felle[rng.randi_range(0, felle.size() - 1)]),
					"hut":
					rng.randi_range(0, HUT_FARBEN.size() - 1) if rng.randf() < HUT_ANTEIL else -1,
					"greift": rng.randf() < GREIFER_ANTEIL,
					"blick": Vector3(plan_konfig.get("blick", Vector3(0.0, 0.0, -4.0))),
				}
			)
		)
	return out


## Zustand eines Besuchers nach `sekunden` (PURE): läuft die eigene
## Punkt-Schleife ab, pausiert an jedem Punkt (Regal anschauen) und kehrt
## zum Start zurück. Rückgabe: {pos, heading, steht, pause_frac}.
static func zustand(plan: Dictionary, sekunden: float) -> Dictionary:
	var punkte_raw: Variant = plan.get("punkte", [])
	var punkte: Array = punkte_raw if punkte_raw is Array else []
	if punkte.is_empty():
		return {"pos": Vector3.ZERO, "heading": 0.0, "steht": true, "pause_frac": 0.0}
	if punkte.size() < 2:
		return {"pos": punkte[0], "heading": 0.0, "steht": true, "pause_frac": 0.0}
	var tempo := maxf(0.05, float(plan.get("tempo", TEMPO_MIN)))
	var pause := maxf(0.0, float(plan.get("pause_s", PAUSE_MIN_S)))
	var laengen: Array[float] = []
	var zyklus := 0.0
	for i in punkte.size():
		var teil := Vector3(punkte[i]).distance_to(Vector3(punkte[(i + 1) % punkte.size()]))
		laengen.append(maxf(teil, 0.001))
		zyklus += laengen[i] / tempo + pause
	var t := fposmod(sekunden + float(plan.get("phase", 0.0)) * zyklus, zyklus)
	for i in punkte.size():
		var von := Vector3(punkte[i])
		var nach := Vector3(punkte[(i + 1) % punkte.size()])
		var gehzeit := laengen[i] / tempo
		if t < gehzeit:
			var richtung := nach - von
			return {
				"pos": von.lerp(nach, t / gehzeit),
				"heading": atan2(richtung.x, richtung.z),
				"steht": false,
				"pause_frac": 0.0,
			}
		t -= gehzeit
		if t < pause:
			var blick := Vector3(plan.get("blick", Vector3(0.0, 0.0, -4.0))) - nach
			return {
				"pos": nach,
				"heading": atan2(blick.x, blick.z),
				"steht": true,
				"pause_frac": t / maxf(pause, 0.001),
			}
		t -= pause
	return {"pos": punkte[0], "heading": 0.0, "steht": true, "pause_frac": 0.0}


## Nächste Spruch-Zeile einer Domain (Rotation, Muster UrlaubsSprueche).
## "" bei unbekannter Domain — has_key-Guard gegen push_error-Rauschen.
static func naechster_spruch(domain: String) -> String:
	var key := "city_leben.sprueche." + domain
	if not I18nService.has_key(key):
		return ""
	var liste := I18nService.items(key)
	if liste.is_empty():
		return ""
	var index := int(_spruch_zaehler.get(domain, 0)) % liste.size()
	_spruch_zaehler[domain] = index + 1
	return String(liste[index])


## Nur für Tests: Spruch-Rotation zurücksetzen.
static func reset_sprueche_fuer_tests() -> void:
	_spruch_zaehler.clear()


## ------------------------------------------------------------- Test-API


func besucher_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for eintrag in _besucher:
		out.append(eintrag["node"])
	return out


func ist_statisch() -> bool:
	return _statisch


## ---------------------------------------------------------------- intern


func _reduziert() -> bool:
	if reduced_override >= 0:
		return reduced_override == 1
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


## Besucher als ROHES GLB instanzieren (billig, s. Klassen-Docstring).
func _spawne_besucher(alle: Array[Dictionary]) -> void:
	if alle.is_empty() or not ResourceLoader.exists(GOOBY_GLB):
		return
	var szene: PackedScene = load(GOOBY_GLB)
	if szene == null:
		return
	for i in alle.size():
		var plan := alle[i]
		var node: Node3D = szene.instantiate()
		node.name = "Besucher%d" % i
		add_child(node)
		_faerbe_geteilt(node, plan["tint"])
		var hut_index := int(plan.get("hut", -1))
		if hut_index >= 0:
			node.add_child(_baue_hut(Color(HUT_FARBEN[hut_index % HUT_FARBEN.size()])))
		(
			_besucher
			. append(
				{
					"plan": plan,
					"node": node,
					"player": node.find_child("AnimationPlayer", true, false),
					"anim": "",
					"spruch_cd": SPRUCH_START_S + float(i) * SPRUCH_VERSATZ_S,
				}
			)
		)


func _update_besucher() -> void:
	for eintrag in _besucher:
		var bei := zustand(eintrag["plan"], _zeit)
		var node: Node3D = eintrag["node"]
		node.position = bei["pos"]
		node.rotation.y = float(bei["heading"])
		_spiele_clip(eintrag, bei)


## Clip-Wahl: gehen = walk-Loop; Pause = einmal umsehen (idle_lookaround),
## Greifer heben in der zweiten Pausenhälfte kurz den Arm (wave liest als
## Regal-Griff), danach zurück in den idle-Loop.
func _spiele_clip(eintrag: Dictionary, bei: Dictionary) -> void:
	var player: AnimationPlayer = eintrag.get("player")
	if player == null:
		return
	if not bool(bei["steht"]):
		_starte_anim(eintrag, player, ["walk", "idle"], "walk")
		return
	var greift := bool((eintrag["plan"] as Dictionary).get("greift", false))
	if greift and float(bei["pause_frac"]) >= 0.55 and str(eintrag["anim"]) != "griff":
		_starte_anim(eintrag, player, ["wave", "idle"], "griff")
		return
	if str(eintrag["anim"]) == "":
		_starte_anim(eintrag, player, ["idle", "walk"], "schaut")
		return
	if str(eintrag["anim"]) in ["walk", "griff_fertig"]:
		_starte_anim(eintrag, player, ["idle_lookaround", "idle"], "schaut")
		return
	# Einmal-Clips (umsehen/greifen) sind durch → weiter im idle-Loop.
	if not player.is_playing():
		var fertig := "griff_fertig" if str(eintrag["anim"]) == "griff" else "schaut_fertig"
		_starte_anim(eintrag, player, ["idle"], fertig)


## Erste vorhandene Animation aus `kandidaten` spielen (Importer strippt
## teils das "-loop"-Suffix — beide Namen zulassen, Muster CityScene).
func _starte_anim(
	eintrag: Dictionary, player: AnimationPlayer, kandidaten: Array, merkname: String
) -> void:
	if str(eintrag["anim"]) == merkname:
		return
	for wunsch: String in kandidaten:
		for anim_name: String in [wunsch, wunsch + "-loop"]:
			if player.has_animation(anim_name):
				player.play(anim_name)
				eintrag["anim"] = merkname
				return


func _update_sprueche(delta: float) -> void:
	var domain := str(konfig.get("sprueche", ""))
	if domain.is_empty() or ui_layer == null or not is_instance_valid(ui_layer):
		return
	for eintrag in _besucher:
		eintrag["spruch_cd"] = float(eintrag["spruch_cd"]) - delta
		if float(eintrag["spruch_cd"]) > 0.0:
			continue
		eintrag["spruch_cd"] = SPRUCH_ALLE_S
		var text := naechster_spruch(domain)
		if text.is_empty():
			return
		AcBubble.show_bubble(
			ui_layer, text, {"speaker_3d": eintrag["node"], "dauer_s": SPRUCH_DAUER_S}
		)
		return


## Fell-Tint über den GETEILTEN Material-Cache: gleiche Farbe + gleiches
## Basismaterial = ein einziges Material für alle Besucher aller Orte.
func _faerbe_geteilt(node: Node3D, farbe: Color) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		for i in mi.get_surface_override_material_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if not (mat is StandardMaterial3D):
				continue
			var key := "%d|%s" % [mat.get_instance_id(), farbe.to_html(false)]
			if not _tint_cache.has(key):
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.55)
				_tint_cache[key] = kopie
			mi.set_surface_override_material(i, _tint_cache[key])


## Kleines Käppchen (Zylinder + Krempe) mit geteiltem Material — sitzt am
## Wurzel-Node (Muster Wochenmarkt-Schürze), kein Bone-Attachment nötig.
func _baue_hut(farbe: Color) -> Node3D:
	var hut := Node3D.new()
	hut.name = "Hut"
	hut.position = Vector3(0.0, 1.01, 0.02)
	hut.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	var kappe := MeshInstance3D.new()
	var kappe_mesh := CylinderMesh.new()
	kappe_mesh.top_radius = 0.085
	kappe_mesh.bottom_radius = 0.105
	kappe_mesh.height = 0.085
	kappe.mesh = kappe_mesh
	kappe.material_override = _hut_material(farbe)
	kappe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hut.add_child(kappe)
	var krempe := MeshInstance3D.new()
	var krempe_mesh := CylinderMesh.new()
	krempe_mesh.top_radius = 0.155
	krempe_mesh.bottom_radius = 0.155
	krempe_mesh.height = 0.018
	krempe.mesh = krempe_mesh
	krempe.material_override = _hut_material(farbe)
	krempe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	krempe.position = Vector3(0.0, -0.045, 0.0)
	hut.add_child(krempe)
	return hut


static func _hut_material(farbe: Color) -> StandardMaterial3D:
	var key := farbe.to_html(false)
	if not _hut_mat_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = farbe
		mat.roughness = 0.8
		_hut_mat_cache[key] = mat
	return _hut_mat_cache[key]
