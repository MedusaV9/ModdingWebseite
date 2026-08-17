class_name CityLicht
extends RefCounted
## Tagesrhythmus-Beleuchtung der Stadt (W18/J4, aus CityBau ausgelagert):
## besitzt Sonne/Himmel/Ambient samt Wetter-FX, die Nacht-Teile der Laternen,
## die Fensterlichter, den Schilder-Glow und die Vögel — und schaltet all das
## per `setze_stunde()` OHNE Neubau auf eine neue Uhrzeit um. CityBau baut
## weiterhin die statische Kulisse und MELDET hier nur die Empfänger an
## (melde_laternen/melde_schild); die Fenster-Quellen teilen sich beide als
## EIN Array (CityBau füllt es beim Bau, hier wird daraus lazy das MultiMesh).

## W13/WETTER-FX: Tests/Screenshots erzwingen eine Wetterlage ({} = echter
## SoulWetter-Tagesplan, gleiche API wie das Zuhause).
var wetter_override: Dictionary = {}

var _szene: Node3D
var _karte: CityMap
var _profil: Dictionary
var _stunde := 12.0
var _wetter: Dictionary = {}
var _wetter_fx: WetterFx

## Referenzen der einmal gebauten Licht-Empfänger, damit setze_stunde() sie
## OHNE Neubau umschalten kann. Nacht-Teile (Laternen-Birnen/-Schein,
## Fensterlichter, Vögel) entstehen LAZY beim ersten Bedarf — die Bau-Stunde
## entscheidet also weiter, was beim Aufbau existiert (Tests bauen mit
## stunde_override und sehen das alte Verhalten).
var _env: Environment
var _himmel: GoobyHimmel
var _sonne: DirectionalLight3D
var _laternen_wurzel: Node3D
var _laternen_posten: Array[Transform3D] = []
var _laternen_kopf := 0.0
var _laternen_nacht: Array[Node3D] = []
var _fenster_quellen: Array[Dictionary] = []
var _fenster_mmi: MultiMeshInstance3D
var _schilder: Array[Dictionary] = []
var _neons: Array[Node3D] = []
var _voegel_wurzel: Node3D
var _voegel: Array[Dictionary] = []
var _voegel_zeit := 0.0
var _voegel_reduziert := false
var _licht_q := -1000.0


func _init(
	szene: Node3D,
	karte: CityMap,
	licht_profil: Dictionary,
	stunde: float,
	fenster_quellen: Array[Dictionary]
) -> void:
	_szene = szene
	_karte = karte
	_profil = licht_profil
	_stunde = stunde
	_fenster_quellen = fenster_quellen


## Der echte Stadt-Wetterplan: gleiche API wie das Zuhause (SoulWetter,
## deterministisch aus Datum + Stunde — nichts wird hier gewürfelt).
static func wetter_jetzt(stunde: float, datum := "") -> Dictionary:
	var tag := datum if not datum.is_empty() else RanchWetter.datum_heute()
	return SoulWetter.zustand(tag, stunde)


## Tag/Nacht-Licht (W4-P3 POLISH-8): komplette 24-h-Kurve aus CityAmbiente
## — nachts fahler Mond, dunkler Himmel, Laternen + Autolichter an.
## W13/WETTER-FX: Himmel + Licht folgen dem ECHTEN Tagesplan (SoulWetter,
## wie das Zuhause); dazu hängt die geteilte WetterFx-Komponente in der
## Szene (Regen über der Stadt, Schnee im Winter, Gewitter mit Blitz).
func baue() -> void:
	_wetter = wetter_override if not wetter_override.is_empty() else wetter_jetzt(_stunde)
	var licht := CityAmbiente.wetter_licht_profil(_profil, _wetter)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	# FB-2: prozeduraler GOOBY-Himmel (gleicher Shader wie die Ranch) —
	# einmal zur Bau-Stunde + Bau-Wetterlage einstellen.
	var himmel := GoobyHimmel.new()
	himmel.wende_an(_stunde, WetterFx.himmel_zustand(_wetter))
	e.background_mode = Environment.BG_SKY
	e.sky = himmel.sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = licht["ambient_energie"]
	# EVAL-2026-08 Lens B (Licht-Handover, lichtkalibrierung.md): die Stadt
	# lag mit 0,74 Luma / 8,5 % Clipping über dem Zielfenster — dieselbe
	# Kalibrierkette wie Haus/Garten; der Nebel bindet die Fern-Kulisse an
	# den Himmel und wird in setze_stunde() nachgeführt.
	LichtKalibrierung.anwenden(e, "draussen")
	LichtKalibrierung.nebel_anwenden(e, himmel.horizont_farbe())
	env.environment = e
	_szene.add_child(env)
	var sonne := DirectionalLight3D.new()
	sonne.name = "Sonne"
	sonne.shadow_enabled = true
	# EIN Schatten-Split statt PSSM-4: jede Kaskade zeichnet die Stadt
	# erneut — orthogonal spart ~3 Szenen-Durchläufe (Draw-Call-Budget 400).
	# Reichweite deckt die Chase-Cam-Sicht; weiter weg (Übersichts-/Debug-
	# Kameras) entfällt der Schatten-Pass komplett.
	sonne.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sonne.directional_shadow_max_distance = 175.0
	sonne.rotation_degrees = Vector3(-float(_profil["elevation"]), -35.0, 0.0)
	sonne.light_color = licht["sonnen_farbe"]
	sonne.light_energy = licht["sonnen_energie"]
	_szene.add_child(sonne)
	_haenge_wetter_fx(e, sonne)
	_env = e
	_himmel = himmel
	_sonne = sonne
	_licht_q = roundf(_stunde * 20.0)


## W18/J4 „Stadt-Tagesrhythmus": die GEBAUTE Stadt auf eine neue Uhrzeit
## umschalten, ohne irgendetwas neu zu instanzieren — Sonne/Himmel/Ambient
## folgen der 24-h-Kurve, Laternen + Lichtkegel, Fensterlichter, Schilder-
## Glow und Vögel toggeln (Nacht-Teile entstehen lazy beim ersten Bedarf).
## Quantisiert auf 3-Minuten-Schritte: die Uhr kriecht, ein Re-Apply pro
## Tick wäre Verschwendung (Low-End-Budget).
func setze_stunde(stunde: float) -> void:
	var q := roundf(fposmod(stunde, 24.0) * 20.0)
	if q == _licht_q:
		return
	_licht_q = q
	_stunde = stunde
	_profil = CityAmbiente.licht_profil(stunde)
	if wetter_override.is_empty():
		var neu := wetter_jetzt(stunde)
		if neu != _wetter:
			_wetter = neu
			if _wetter_fx != null:
				_wetter_fx.wende_zustand_an(_wetter)
	var licht := CityAmbiente.wetter_licht_profil(_profil, _wetter)
	if _himmel != null:
		_himmel.wende_an(stunde, WetterFx.himmel_zustand(_wetter))
	if _env != null:
		_env.ambient_light_energy = licht["ambient_energie"]
		if _himmel != null:
			LichtKalibrierung.nebel_anwenden(_env, _himmel.horizont_farbe())
	if _sonne != null:
		_sonne.rotation_degrees = Vector3(-float(_profil["elevation"]), -35.0, 0.0)
		_sonne.light_color = licht["sonnen_farbe"]
		_sonne.light_energy = licht["sonnen_energie"]
	var an := bool(_profil["lichter_an"])
	_setze_laternen_nacht(an)
	_setze_fenster(an, CityRhythmus.fenster_anteil(stunde))
	_setze_schilder(an)
	_setze_neons(an)
	_setze_voegel(not bool(_profil["ist_nacht"]))


## Aktuelles (dynamisch nachgeführtes) Licht-Profil — CityScene liest
## lichter_an daraus für Auto-Scheinwerfer.
func profil() -> Dictionary:
	return _profil


## Bau-Wetterlage der Stadt (für Tests/andere Systeme).
func wetter() -> Dictionary:
	return _wetter.duplicate()


## Die eingehängte Wetter-Komponente (für Tests/Debug; null vor baue()).
func wetter_fx() -> WetterFx:
	return _wetter_fx


## CityBau meldet die gebauten Laternen an (Wurzel + Masten-Transforms +
## Kopfhöhe in Welt-Metern); bei Dämmerung/Nacht entstehen die Nacht-Teile
## sofort, sonst lazy beim ersten setze_stunde()-Einschalten.
func melde_laternen(wurzel: Node3D, posten: Array[Transform3D], kopf_hoehe: float) -> void:
	_laternen_wurzel = wurzel
	_laternen_posten = posten
	_laternen_kopf = kopf_hoehe
	if bool(_profil["lichter_an"]):
		_baue_laternen_nacht()


## CityBau meldet ein Namensschild an — gestylt wird sofort (Bau-Stunde)
## und später bei jedem Rhythmus-Umschalten erneut.
func melde_schild(schild: OrtSchild, tint: String) -> void:
	_schilder.append({"schild": schild, "tint": tint})
	_style_schild(schild, tint, bool(_profil["lichter_an"]))


## GOOBY-WELT/STADT: Neon-Leiste eines Ladenportals (CityOrtBau) anmelden —
## leuchtet nur bei Dämmerung/Nacht (Emissiv-Quad, kein echtes Licht).
func melde_neon(neon: Node3D) -> void:
	_neons.append(neon)
	neon.visible = bool(_profil["lichter_an"])


## Nachts leuchten Fenster (FIX-5 „Liebe zum Detail"): warme Quads auf den
## Straßenfassaden ALLER Gebäude — ein MultiMesh, EIN Draw-Call.
func baue_fenster() -> void:
	if not bool(_profil["lichter_an"]):
		return
	_baue_fenster_mmi()


## Ein paar Vögel ziehen Kreise überm Park (FIX-5 „Liebe zum Detail") —
## dunkle Mini-Quads, tagsüber, im Spar-Modus aus.
func baue_voegel(reduziert: bool) -> void:
	_voegel_reduziert = reduziert
	if bool(_profil["ist_nacht"]) or reduziert:
		return
	_baue_voegel_nodes()


func tick_voegel(delta: float) -> void:
	_voegel_zeit += delta
	for vogel in _voegel:
		var winkel := _voegel_zeit * float(vogel["tempo"]) + float(vogel["phase"])
		var zentrum: Vector3 = vogel["zentrum"]
		var radius := float(vogel["radius"])
		var node: Node3D = vogel["node"]
		node.position = (
			zentrum
			+ Vector3(
				cos(winkel) * radius,
				float(vogel["hoehe"]) + sin(_voegel_zeit * 1.7 + float(vogel["phase"])) * 1.5,
				sin(winkel) * radius
			)
		)
		node.rotation.y = -winkel
		# Flügelschlag: die beiden Quads wippen gegengleich.
		var schlag := sin(_voegel_zeit * 9.0 + float(vogel["phase"])) * 0.55
		var kinder := node.get_children()
		if kinder.size() >= 2:
			(kinder[0] as Node3D).rotation.z = schlag
			(kinder[1] as Node3D).rotation.z = -schlag


## Geteilte WetterFx-Komponente über der Stadt: folgt der Kamera, schreibt
## Nebel ins Environment und blitzt über die Szenen-Sonne (Budget: ein
## GPUParticles3D pro Effekt, skaliert über Quality.particle_factor()).
func _haenge_wetter_fx(e: Environment, sonne: DirectionalLight3D) -> void:
	_wetter_fx = WetterFx.new()
	_wetter_fx.name = "WetterFx"
	_wetter_fx.extents = Vector3(46.0, 3.0, 46.0)
	_wetter_fx.hoehe = 24.0
	_wetter_fx.folge_kamera = true
	_wetter_fx.seed_wert = _karte.deko_seed()
	_wetter_fx.env = e
	_wetter_fx.sonne = sonne
	_szene.add_child(_wetter_fx)
	_wetter_fx.wende_zustand_an(_wetter)


## Birnen + Lichtkegel/-flecken der Laternen (nachts) — einmal gebaut,
## danach schaltet _setze_laternen_nacht() nur noch die Sichtbarkeit.
func _baue_laternen_nacht() -> void:
	if not _laternen_nacht.is_empty() or _laternen_posten.is_empty():
		return
	var kugel := SphereMesh.new()
	kugel.radius = 0.45
	kugel.height = 0.9
	kugel.radial_segments = 8
	kugel.rings = 4
	kugel.material = CityAmbiente.leuchten_material(Color(1.0, 0.85, 0.55))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = kugel
	mm.instance_count = _laternen_posten.size()
	for i in _laternen_posten.size():
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY, _laternen_posten[i].origin + Vector3(0.0, _laternen_kopf, 0.0)
			)
		)
	var birnen := MultiMeshInstance3D.new()
	birnen.name = "Birnen"
	birnen.multimesh = mm
	birnen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laternen_wurzel.add_child(birnen)
	CityAmbiente.laternen_schein(_laternen_wurzel, _laternen_posten, _laternen_kopf)
	_laternen_nacht.append(birnen)
	for kind_name: String in ["Lichtkegel", "Lichtflecken"]:
		var kind := _laternen_wurzel.get_node_or_null(kind_name)
		if kind is Node3D:
			_laternen_nacht.append(kind)


func _setze_laternen_nacht(an: bool) -> void:
	if an and _laternen_nacht.is_empty():
		_baue_laternen_nacht()
	for node in _laternen_nacht:
		node.visible = an


## Tages-/Nacht-Look eines Schilds (wird beim Bau UND vom Rhythmus-Umschalten
## angewandt — setze_tafel ersetzt eine vorhandene Tafel sauber).
func _style_schild(schild: OrtSchild, tint: String, an: bool) -> void:
	schild.modulate = CityAmbiente.schild_farbe(an)
	if an:
		_lass_schild_leuchten(schild, tint)
	else:
		schild.outline_modulate = Color(1.0, 0.98, 0.92)
		schild.setze_tafel(Color(1.0, 0.97, 0.9, 0.85), 0.25, true)


func _setze_schilder(an: bool) -> void:
	for eintrag in _schilder:
		var schild: OrtSchild = eintrag["schild"]
		if is_instance_valid(schild):
			_style_schild(schild, str(eintrag["tint"]), an)


func _setze_neons(an: bool) -> void:
	for neon in _neons:
		if is_instance_valid(neon):
			neon.visible = an


## Nacht-Glow am Ladenschild (W4-P3-Ambiente): eine unshaded Emissiv-Tafel
## HINTER der Schrift in der Fassadenfarbe. Bewusst KEIN Environment-Glow-
## Pass und kein zusätzliches Licht — das wäre auf dem Handy ein Fullscreen-
## Blur bzw. ein Licht pro Laden; so ist es ein Quad (Doc A §7 Licht-Budget).
## VIS-2: die Tafel hängt jetzt IM Schild (setze_tafel) und macht dessen
## Entfernungs-Skalierung und Fern-Ausblenden automatisch mit.
func _lass_schild_leuchten(schild: OrtSchild, hex: String) -> void:
	schild.outline_modulate = AcTokens.INK
	var farbe := Color(hex) if not hex.is_empty() else AcTokens.YELLOW
	schild.setze_tafel(farbe.lerp(AcTokens.WHITE, 0.55), 1.1)


## Fenster-MultiMesh einmal bauen (lazy). Die Transforms werden vorab
## deterministisch GEMISCHT: tief in der Nacht dimmt _setze_fenster über
## visible_instance_count auf einen Teil — durch das Mischen wirkt der
## Rest wie zufällig verteilte Nachtschwärmer-Fenster statt wie ein Block.
func _baue_fenster_mmi() -> void:
	if _fenster_mmi != null:
		return
	var transforms := CityKulisse.fenster_transforms(_fenster_quellen, _karte.deko_seed())
	if transforms.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _karte.deko_seed() + 331
	for i in range(transforms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tausch := transforms[i]
		transforms[i] = transforms[j]
		transforms[j] = tausch
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = CityAmbiente.leuchten_material(Color(1.0, 0.87, 0.55), 1.2)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Fensterlichter"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_szene.add_child(mmi)
	_fenster_mmi = mmi


## Fensterlichter zur Stunde: aus am Tag, voll am Abend, tief in der Nacht
## nur noch `anteil` (visible_instance_count — kein Rebuild, kein Material).
func _setze_fenster(an: bool, anteil: float) -> void:
	if an and _fenster_mmi == null:
		_baue_fenster_mmi()
	if _fenster_mmi == null:
		return
	_fenster_mmi.visible = an and anteil > 0.0
	var gesamt := _fenster_mmi.multimesh.instance_count
	var sichtbar := clampi(roundi(float(gesamt) * clampf(anteil, 0.0, 1.0)), 0, gesamt)
	_fenster_mmi.multimesh.visible_instance_count = sichtbar if sichtbar < gesamt else -1


## Vögel zur Tageszeit toggeln (Rhythmus): nachts schlafen sie, morgens
## kreisen sie wieder — lazy gebaut, falls die Szene nachts startete.
func _setze_voegel(tag: bool) -> void:
	if _voegel_reduziert:
		return
	if tag and _voegel_wurzel == null:
		_baue_voegel_nodes()
	if _voegel_wurzel != null:
		_voegel_wurzel.visible = tag


func _baue_voegel_nodes() -> void:
	if _voegel_wurzel != null:
		return
	var wurzel := Node3D.new()
	wurzel.name = "Voegel"
	_szene.add_child(wurzel)
	_voegel_wurzel = wurzel
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.18, 0.18, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var zentrum := _karte.tile_zu_welt(Vector2i(8, 8))
	for i in 3:
		var vogel := Node3D.new()
		for seite: float in [-1.0, 1.0]:
			var fluegel := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.9, 0.28)
			quad.material = mat
			fluegel.mesh = quad
			fluegel.position = Vector3(seite * 0.42, 0.0, 0.0)
			fluegel.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			vogel.add_child(fluegel)
		wurzel.add_child(vogel)
		(
			_voegel
			. append(
				{
					"node": vogel,
					"zentrum": zentrum + Vector3(float(i) * 14.0 - 14.0, 0.0, float(i) * 8.0),
					"radius": 22.0 + float(i) * 7.0,
					"hoehe": 20.0 + float(i) * 4.0,
					"tempo": 0.35 + float(i) * 0.08,
					"phase": float(i) * 2.1,
				}
			)
		)
