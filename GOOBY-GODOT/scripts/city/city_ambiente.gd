class_name CityAmbiente
extends RefCounted
## Tag/Nacht-Lichtkurve + Ambient-Regeln der Stadt (W4-P3 POLISH-8, Doc E
## §1.4). PURE + headless-testbar — CityScene wendet das Profil auf
## Environment/Sonne/Laternen/Autolichter an. Ambient-SFX (Hupe/Vogel)
## werden hier nur GEPLANT; abgespielt wird über den AudioDirector von
## W4-P1 (Fallback ohne Autoload: leiser Verzicht).

## Laternen/Autolichter gehen in der Dämmerung an, nicht erst bei Nacht —
## W18/J4: Schwelle auf die goldene Stunde gelegt (an ab ~18:55, morgens
## aus ab ~07:15), damit der Abend-Rhythmus „golden + Laternen an" trägt.
const LICHTER_AN_UNTER := 0.66

## Ambient-SFX-Planung: zufällige Pausen zwischen Hupe/Vogel-Momenten.
const SFX_PAUSE_MIN_S := 18.0
const SFX_PAUSE_MAX_S := 45.0

## Beinahe-Unfall (M3-Vorgriff „Hupe-Reaktionen/Near-Miss“): so nah darf ein
## Verkehrs-Gooby am Spielerauto vorbei, bevor er hupt …
const NEAR_MISS_M := 7.0
## … und so schnell muss der Spieler dabei mindestens sein (m/s).
const NEAR_MISS_TEMPO := 4.0
## Sperrzeit nach einer Hupe (s) — sonst hupt der ganze Block im Chor.
const NEAR_MISS_PAUSE_S := 4.0

## Laternen-Lichtkegel (W14, Sicht-Diagnose „Nacht-Beleuchtungsluecken"):
## Kegel-Radius am Boden + Durchmesser des warmen Lichtflecks (Meter).
const KEGEL_RADIUS_M := 2.6
const KEGEL_SPITZE_M := 0.35
const FLECK_M := 5.2

## Geteilter Glow-Verlauf aller Ladenschilder (s. glow_textur()).
static var _glow_tex: GradientTexture2D = null

## Geteilter Vertikal-Verlauf der Laternen-Lichtkegel (s. kegel_textur()).
static var _kegel_tex: GradientTexture2D = null


## Tageslicht 0..1 über die Uhrzeit (weiche Rampen morgens/abends).
static func tageslicht(stunde: float) -> float:
	var s := fposmod(stunde, 24.0)
	var auf := smoothstep(5.5, 8.0, s)
	var ab := 1.0 - smoothstep(18.0, 20.5, s)
	return clampf(minf(auf, ab), 0.0, 1.0)


static func ist_nacht(stunde: float) -> bool:
	return tageslicht(stunde) < 0.5


## Laternen + Autolichter an? (Dämmerung zählt schon.)
static func lichter_an(stunde: float) -> bool:
	return tageslicht(stunde) < LICHTER_AN_UNTER


## W13/WETTER-FX: Licht-Profil vom Wetter gedimmt/entsättigt (pur
## destilliert aus RanchWetterController._wende_licht_an) — Regen/Wolken
## nehmen der Sonne Energie und ziehen ihre Farbe Richtung Grau. Schnee
## dimmt wie ein bedeckter Tag (die Basis-Tabellen kennen keinen Schnee).
static func wetter_licht_profil(profil: Dictionary, zustand: Dictionary) -> Dictionary:
	var typ := str(zustand.get("typ", "sonne"))
	if typ == "schnee":
		typ = "wolken"
	var faktor := float(RanchWetter.LICHT_FAKTOR.get(typ, 1.0))
	var grau := float(RanchWetter.BEWOELKUNG.get(typ, 0.0)) * 0.55
	var out := profil.duplicate()
	out["sonnen_energie"] = float(profil["sonnen_energie"]) * lerpf(1.0, faktor, 0.85)
	out["sonnen_farbe"] = (profil["sonnen_farbe"] as Color).lerp(Color(0.82, 0.84, 0.88), grau)
	out["ambient_energie"] = float(profil["ambient_energie"]) * lerpf(1.0, faktor, 0.75)
	return out


## Komplettes Licht-Profil der Stadt zur Stunde (0..24, Bruchteile ok).
static func licht_profil(stunde: float) -> Dictionary:
	var licht := tageslicht(stunde)
	var nacht := 1.0 - licht
	var t := clampf((fposmod(stunde, 24.0) - 6.0) / 12.0, 0.0, 1.0)
	# Tag: Sonnenhöhe folgt der Uhrzeit; Nacht: Mond steht fest und fahl.
	var elevation := lerpf(34.0, lerpf(15.0, 55.0, sin(t * PI)), licht)
	var tag_farbe := Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.75, 0.55), absf(t - 0.5) * 2.0)
	var mond_farbe := Color(0.6, 0.68, 0.92)
	return {
		"sonnen_energie": lerpf(0.12, 1.0, licht),
		"sonnen_farbe": tag_farbe.lerp(mond_farbe, nacht),
		"elevation": elevation,
		"ambient_energie": lerpf(0.4, 1.1, licht),
		"himmel_oben": Color(0.35, 0.55, 0.85).lerp(Color(0.04, 0.06, 0.14), nacht),
		"himmel_horizont": Color(0.72, 0.83, 0.95).lerp(Color(0.12, 0.14, 0.26), nacht),
		"boden_horizont": Color(0.71, 0.82, 0.62).lerp(Color(0.1, 0.12, 0.18), nacht),
		"boden_unten": Color(0.46, 0.6, 0.4).lerp(Color(0.06, 0.08, 0.12), nacht),
		"lichter_an": lichter_an(stunde),
		"ist_nacht": ist_nacht(stunde),
	}


## Nächste Ambient-SFX-Pause in Sekunden (roll = injizierter Zufall 0..1).
static func sfx_pause_s(roll: float) -> float:
	return lerpf(SFX_PAUSE_MIN_S, SFX_PAUSE_MAX_S, clampf(roll, 0.0, 1.0))


## Welcher Ambient-SFX passt zur Stunde? Vögel nur am Tag, Hupen immer
## (roll = injizierter Zufall 0..1). Rückgabe: "vogel" | "hupe".
static func sfx_wahl(stunde: float, roll: float) -> String:
	if ist_nacht(stunde):
		return "hupe"
	return "vogel" if roll < 0.6 else "hupe"


## Schrift-/Leuchtfarbe der Ladenschilder: tagsüber Theme-Tinte, nachts das
## warme Neon über der Markise (W4-P3-Ambiente „Glow bei Ladenschildern“).
static func schild_farbe(lichter_an: bool) -> Color:
	return Color(1.0, 0.94, 0.76) if lichter_an else AcTokens.INK


## Beinahe-Unfall? Ein Verkehrs-Gooby hupt nur, wenn er wirklich knapp dran
## war UND der Spieler in Fahrt ist — Schrittgeschwindigkeit ist kein Drama.
static func ist_beinahe(abstand_m: float, tempo: float) -> bool:
	return abstand_m <= NEAR_MISS_M and absf(tempo) >= NEAR_MISS_TEMPO


## Warmes Emissiv-Material für Laternen-Birnen/Autolichter (unshaded, damit
## es auch ohne Glow-Postprocess nachts „leuchtet“).
static func leuchten_material(farbe: Color, energie := 1.6) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = farbe
	mat.emission_enabled = true
	mat.emission = farbe
	mat.emission_energy_multiplier = energie
	return mat


## Weicher radialer Alpha-Verlauf, EINMAL gebaut und von allen Schildern
## geteilt — der Ersatz für einen Fullscreen-Glow-Pass (mobil-Budget).
static func glow_textur() -> GradientTexture2D:
	if _glow_tex == null:
		var verlauf := Gradient.new()
		verlauf.set_offset(0, 0.0)
		verlauf.set_color(0, Color(1, 1, 1, 1))
		verlauf.set_offset(1, 1.0)
		verlauf.set_color(1, Color(1, 1, 1, 0))
		verlauf.add_point(0.45, Color(1, 1, 1, 0.72))
		var tex := GradientTexture2D.new()
		tex.gradient = verlauf
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex = tex
	return _glow_tex


## Material der Leucht-Tafel hinter einem Ladenschild: unshaded, radial
## ausblendend und OHNE Tiefenschreiben, damit die Schrift davor sauber
## bleibt (sonst z-fightet der Billboard-Quad mit dem Label3D).
static func schild_glow_material(farbe: Color) -> StandardMaterial3D:
	var mat := leuchten_material(farbe, 1.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = glow_textur()
	mat.emission_texture = glow_textur()
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.render_priority = -1
	return mat


## Vertikaler Alpha-Verlauf der Lichtkegel (oben an der Birne voll, unten
## am Boden aus) — EINMAL gebaut, von allen Kegeln geteilt.
static func kegel_textur() -> GradientTexture2D:
	if _kegel_tex == null:
		var verlauf := Gradient.new()
		verlauf.set_offset(0, 0.0)
		verlauf.set_color(0, Color(1, 1, 1, 1))
		verlauf.set_offset(1, 1.0)
		verlauf.set_color(1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = verlauf
		tex.width = 8
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_LINEAR
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		_kegel_tex = tex
	return _kegel_tex


## W14 (Sicht-Diagnose „Nacht-Beleuchtungslücken"): unter jeder brennenden
## Laterne ein warmer Lichtkegel (Birne→Boden) + ein weicher Lichtfleck auf
## dem Asphalt — 2 MultiMeshes = 2 Draw-Calls für ALLE Laternen, unshaded,
## weiterhin ohne echte OmniLights (Mobile-Budget A §7).
static func laternen_schein(wurzel: Node3D, posten: Array[Transform3D], kopf_hoehe: float) -> void:
	if posten.is_empty():
		return
	var warm := Color(1.0, 0.85, 0.55)
	var kegel_mesh := CylinderMesh.new()
	kegel_mesh.top_radius = KEGEL_SPITZE_M
	kegel_mesh.bottom_radius = KEGEL_RADIUS_M
	kegel_mesh.height = kopf_hoehe
	kegel_mesh.radial_segments = 10
	kegel_mesh.rings = 1
	# Ohne Deckel: sonst zeichnen Boden-/Deckkreis harte Ring-Silhouetten.
	kegel_mesh.cap_top = false
	kegel_mesh.cap_bottom = false
	var kegel_mat := StandardMaterial3D.new()
	kegel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kegel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Vertikaler Verlauf (Birne hell → Boden aus), damit der Kegel weich
	# ausläuft statt an der Unterkante hart abzuschneiden.
	kegel_mat.albedo_texture = kegel_textur()
	kegel_mat.albedo_color = Color(warm.r, warm.g, warm.b, 0.22)
	kegel_mesh.material = kegel_mat
	var fleck_mesh := PlaneMesh.new()
	fleck_mesh.size = Vector2(FLECK_M, FLECK_M)
	var fleck_mat := StandardMaterial3D.new()
	fleck_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fleck_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fleck_mat.albedo_texture = glow_textur()
	fleck_mat.albedo_color = Color(warm.r, warm.g, warm.b, 0.55)
	fleck_mesh.material = fleck_mat
	for paar: Array in [
		[kegel_mesh, Vector3(0.0, kopf_hoehe * 0.5, 0.0), "Lichtkegel"],
		[fleck_mesh, Vector3(0.0, 0.07, 0.0), "Lichtflecken"],
	]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = paar[0]
		mm.instance_count = posten.size()
		for i in posten.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, posten[i].origin + paar[1]))
		var instanz := MultiMeshInstance3D.new()
		instanz.name = str(paar[2])
		instanz.multimesh = mm
		instanz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(instanz)
