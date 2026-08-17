extends RefCounted
## W20/P4 „Pillar-Behandlung" + W21/P4 „Bühne statt Farbnebel" — Bühnen-
## Chrome des MinigameHost, ausgelagert (max-file-lines-Deckel des Hosts):
##
##   baue_backdrop(id)  GESTALTETE Kulisse der Pillar-/Letterbox-Flächen:
##     Verlauf im Themen-Mood des Spiels (Kategorie → Wallpaper-Kontext,
##     s. REIHE_KONTEXT), dezente Muster-Kachel desselben Kontexts und
##     eine Papier-Vorhang-Vignette im Akzentton — EIN statischer
##     Shader-Pass (llvmpipe-billig) statt nacktem Verlauf.
##   baue_schild(titel) Spielname-Schild fürs Pillar-Band (Papier-Karte
##     mit Akzent-Rand) — layout_deko platziert es OBEN im breitesten
##     freien Band und versteckt es, wenn die Bühne keinen Platz hat.
##   baue_gooby_silhouette()  wartende Gooby-Silhouette (Ink-Ton, leise)
##     am Bühnenrand gegenüber dem Schild.
##   baue_top_bar(cb)   EIN Host-Chrome oben: Score-Frost-Kapsel +
##     Geist-Chip + Zeit-Chip + Pause (W21/P4 (b) — der Zeit-Chip
##     etabliert den Rahmen-Standard, Spiele-HUDs bleiben unangetastet).
##   baue_stage_frame() Paper-Rahmen-Karte HINTER dem letterboxten
##     Spielfeld — das Spiel liest sich als Karte im Raum.
##   layout()/layout_deko()/aktualisiere_backdrop()  positionieren Rahmen,
##     Top-Bar, Schild, Silhouette und Muster-Kachelung bei JEDER
##     Resize-Runde am SPIELFELD statt an den Canvas-Ecken.
##   score_float()      dezenter ±Delta-Float unter der Score-Kapsel
##     (MotionKit-Grammatik, Reduced-Motion-gated).

const PAD_PX := 10.0
## Silhouetten-Durchmesser in Design-px (×f) + Deckkraft (leise Präsenz;
## wirkt auf die EXTRAHIERTE Ink-Form, der Motiv-Grund ist im Shader weg).
const GOOBY_PX := 88.0
const SILHOUETTE_ALPHA := 0.3
## Papier-Vorhang-Vignette: Deckkraft des Akzent-Randes.
const VORHANG_ALPHA := 0.16
## Muster hinter dem Spiel bewusst LEISER als auf Menü-Wallpapern.
const MUSTER_DAEMPFUNG := 0.6
## Score-Delta-Float: Standzeit, bevor er nach oben verabschiedet wird.
const FLOAT_HALTE_SEC := 0.9
## DERSELBE Mini-Gooby wie Lade-Karte/Pregame/Results (EINE Figur).
const MOTIV_PFAD := "res://assets/acui/gooby_loading_motif.png"
## Kategorie (ArcadeFortschritt.reihe_von) → Wallpaper-Kontext der Bühne:
## das Themen-Mood des Spiels kommt aus DERSELBEN Quelle wie die Screens
## (AcWallpaper.CONTEXTS — Wash/Akzente/Muster, Web-V6-Themenblock).
const REIHE_KONTEXT := {
	"geschick": "quest",
	"action": "arcade",
	"fahren": "city",
	"denken": "blueprint",
	"ranch": "ranch",
	"ruhig": "passport",
}


## Themen-Stimmung der Bühne eines Spiels (pur, testbar): Wallpaper-
## Kontext-Key + Wash/Akzent-Trio + Muster-Name/-Deckkraft.
static func stage_stimmung(game_id: String) -> Dictionary:
	var ctx: String = str(REIHE_KONTEXT.get(ArcadeFortschritt.reihe_von(game_id), "arcade"))
	var key := AcWallpaper.resolve_context(ctx)
	var info: Dictionary = AcWallpaper.CONTEXTS[key]
	return {
		"kontext": key,
		"wash": info["wash"],
		"accent": info["accent"],
		"accent_dark": info["accent_dark"],
		"soft": info["soft"],
		"pattern": str(info["pattern"]),
		"opacity": float(info["opacity"]) * MUSTER_DAEMPFUNG,
	}


static func baue_backdrop(game_id := "") -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "PillarBackdrop"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stimmung := stage_stimmung(game_id)
	var wash: Color = stimmung["wash"]
	bg.color = wash
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = _backdrop_shader()
	bg_mat.set_shader_parameter("oben", wash.lerp(AcTokens.WHITE, 0.22))
	bg_mat.set_shader_parameter("unten", wash.lerp(AcTokens.PAPER_SHADE, 0.5))
	bg_mat.set_shader_parameter("rand", Color(stimmung["accent_dark"] as Color, VORHANG_ALPHA))
	var muster_pfad := "%spattern_%s.png" % [AcWallpaper.PATTERN_DIR, stimmung["pattern"]]
	if ResourceLoader.exists(muster_pfad):
		bg_mat.set_shader_parameter("muster", load(muster_pfad))
		bg_mat.set_shader_parameter("muster_opacity", float(stimmung["opacity"]))
	bg.material = bg_mat
	return bg


## Spielname-Schild: Papier-Karte mit Akzent-Rand im Themen-Mood — hängt
## im Pillar-Band statt dass der Name nur im Pregame lebte. layout_deko
## zeigt/versteckt es je nach Bühnenplatz.
static func baue_schild(titel: String, game_id := "") -> PanelContainer:
	var schild := PanelContainer.new()
	schild.name = "StageSchild"
	schild.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stimmung := stage_stimmung(game_id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PAPER
	sb.set_corner_radius_all(AcTokens.RADIUS_ROW)
	sb.border_color = stimmung["soft"]
	sb.set_border_width_all(2)
	sb.shadow_color = AcTokens.SHADOW_SOFT_COLOR
	sb.shadow_size = AcTokens.SHADOW_SOFT_SIZE
	sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_SOFT_OFFSET_Y)
	sb.content_margin_left = float(AcTokens.SPACE_M)
	sb.content_margin_right = float(AcTokens.SPACE_M)
	sb.content_margin_top = float(AcTokens.SPACE_S)
	sb.content_margin_bottom = float(AcTokens.SPACE_S)
	schild.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.name = "SchildTitel"
	label.theme_type_variation = &"SoftLabel"
	label.text = titel
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	schild.add_child(label)
	schild.hide()
	return schild


## Wartende Gooby-Silhouette (Ink-Ton, leise) — dieselbe Motiv-Figur wie
## Lade-Karte/Pregame/Results, hier als stiller Bühnen-Bewohner. Das Motiv
## hat einen OPAKEN Papier-Grund; der Silhouetten-Shader macht ihn
## transparent (Helligkeit → Deckkraft), sonst stünde ein Kasten im Band.
static func baue_gooby_silhouette() -> TextureRect:
	var gooby := TextureRect.new()
	gooby.name = "StageGooby"
	gooby.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gooby.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gooby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MOTIV_PFAD):
		gooby.texture = load(MOTIV_PFAD)
	var mat := ShaderMaterial.new()
	mat.shader = _silhouette_shader()
	mat.set_shader_parameter("ink", Color(AcTokens.INK))
	gooby.material = mat
	gooby.self_modulate = Color(1.0, 1.0, 1.0, SILHOUETTE_ALPHA)
	gooby.hide()
	return gooby


## W21/P4 (b) — EIN Host-Chrome oben: Score-Frost-Kapsel, Geist-Chip,
## Zeit-Chip, Pause. Liefert die Teile als Dictionary (der Host hält die
## Referenzen; Chip-Gating/Disable-Regeln bleiben Host-Sache).
static func baue_top_bar(on_pause: Callable) -> Dictionary:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16.0
	bar.offset_right = -16.0
	bar.offset_top = 10.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", AcTokens.SPACE_S)
	var kapsel := PanelContainer.new()
	kapsel.name = "ScoreKapsel"
	kapsel.theme_type_variation = &"StatusCapsuleMini"
	kapsel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(kapsel)
	var score := Label.new()
	score.name = "ScoreLabel"
	score.theme_type_variation = &"HeadlineLabel"
	score.text = I18nService.t("mg.host.score", {"score": 0})
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	kapsel.add_child(score)
	var geist := GeistChip.new()
	bar.add_child(geist)
	var zeit := ZeitChip.new()
	bar.add_child(zeit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	var pause := Button.new()
	pause.name = "PauseButton"
	pause.theme_type_variation = &"GhostButton"
	pause.text = I18nService.t("mg.host.pause")
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(on_pause)
	pause.disabled = true
	bar.add_child(pause)
	return {
		"bar": bar,
		"score_kapsel": kapsel,
		"score": score,
		"geist": geist,
		"zeit": zeit,
		"pause": pause,
	}


## POLISH-E/W13B-Teleport-Veil (aus dem Host hierher verschoben — Chrome-
## Aufbau, max-file-lines-Deckel): Abdunkelung + Titel/Text/Zähler über dem
## eingefrorenen letzten Spielbild. Node-Namen sind Test-Vertrag (w13b).
static func baue_strike_veil(strikes: int) -> Control:
	var veil := Control.new()
	veil.name = "StrikeVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.16, 0.12, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.add_child(dim)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 10)
	rows.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rows.grow_horizontal = Control.GROW_DIRECTION_BOTH
	rows.grow_vertical = Control.GROW_DIRECTION_BOTH
	veil.add_child(rows)
	var title := Label.new()
	title.name = "StrikeTitle"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = I18nService.t("mg.host.strike_title")
	rows.add_child(title)
	var text := Label.new()
	text.name = "StrikeText"
	text.theme_type_variation = &"HeadlineLabel"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(320.0, 0.0)
	text.text = I18nService.t("mg.host.strike_teleport")
	rows.add_child(text)
	var count := Label.new()
	count.name = "StrikeCount"
	count.theme_type_variation = &"CaptionLabel"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.text = I18nService.t(
		"mg.host.strike_count", {"n": strikes, "max": MinigameFrameworkLogic.STRIKES_FOR_TELEPORT}
	)
	rows.add_child(count)
	return veil


static func baue_stage_frame() -> Panel:
	var frame := Panel.new()
	frame.name = "StageFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PAPER
	sb.set_corner_radius_all(AcTokens.RADIUS_CARD)
	sb.shadow_color = AcTokens.SHADOW_COLOR
	sb.shadow_size = AcTokens.SHADOW_SIZE
	sb.shadow_offset = Vector2(0.0, AcTokens.SHADOW_OFFSET_Y)
	frame.add_theme_stylebox_override("panel", sb)
	return frame


## Rahmen-Karte + Top-Bar dem Spielfeld nachführen (Befunde B1 + C6
## „Score/Pause kleben in den Canvas-Ecken"). `container` = letterboxter
## SubViewportContainer, `host_size` = Host-Canvas, `insets` = Safe-Insets.
static func layout(
	frame: Panel,
	top_bar: Control,
	container: Control,
	host_size: Vector2,
	fitted: Vector2,
	f: float,
	insets: Dictionary
) -> void:
	var pad := PAD_PX * f
	if frame != null:
		# W21: Karte nie hinter die Top-Bar schieben — vorher ragte der
		# Paper-Rand ~4·f px unter Score/Pause (Clipping, quer wie hochkant).
		var frame_top_min := 0.0
		if top_bar != null:
			frame_top_min = (top_bar.offset_top + top_bar.get_combined_minimum_size().y + 2.0 * f)
		var frame_pos := container.position - Vector2(pad, pad)
		frame_pos = Vector2(maxf(frame_pos.x, 0.0), maxf(frame_pos.y, frame_top_min))
		var frame_size := container.position + fitted + Vector2(pad, pad) - frame_pos
		frame.position = frame_pos
		frame.size = Vector2(
			minf(frame_size.x, host_size.x - frame_pos.x),
			minf(frame_size.y, host_size.y - frame_pos.y)
		)
	if top_bar == null:
		return
	var safe_l := float(insets["left"]) + 6.0 * f
	var safe_r := host_size.x - float(insets["right"]) - 6.0 * f
	if safe_r <= safe_l:
		return
	var mitte := container.position.x + fitted.x * 0.5
	var breite := maxf(fitted.x + pad * 2.0, top_bar.get_combined_minimum_size().x)
	breite = minf(breite, safe_r - safe_l)
	var links := clampf(mitte - breite * 0.5, safe_l, maxf(safe_r - breite, safe_l))
	top_bar.offset_left = links
	top_bar.offset_right = -(host_size.x - (links + breite))


## W21/P4 (a): Schild + Gooby-Silhouette in die FREIEN Bühnen-Bänder legen
## (Pillar links/rechts bzw. Letterbox oben/unten) — das Schild OBEN im
## breitesten Band, der Gooby unten im gegenüberliegenden. Ohne echten
## Bühnenplatz (Orientierung passt) verschwindet die Deko komplett.
static func layout_deko(
	schild: Control,
	gooby: Control,
	container: Control,
	host_size: Vector2,
	fitted: Vector2,
	f: float,
	insets: Dictionary
) -> void:
	var pad := PAD_PX * f
	var safe_l := float(insets["left"])
	var safe_r := host_size.x - float(insets["right"])
	var safe_b := host_size.y - float(insets["bottom"])
	var links := Rect2(safe_l, container.position.y, container.position.x - safe_l, fitted.y)
	var rechts_x := container.position.x + fitted.x
	var rechts := Rect2(rechts_x, container.position.y, safe_r - rechts_x, fitted.y)
	var unten_y := container.position.y + fitted.y
	var unten := Rect2(safe_l, unten_y, safe_r - safe_l, safe_b - unten_y)
	if schild != null:
		ScreenShell.scale_fonts(schild, f)
		var brauch := schild.get_combined_minimum_size()
		schild.size = brauch
		var platz := _schild_platz(links, rechts, unten, brauch, pad)
		schild.visible = platz.x >= 0.0
		if schild.visible:
			schild.position = platz
	if gooby != null:
		var d := GOOBY_PX * f
		gooby.size = Vector2(d, d)
		var platz := _gooby_platz(links, rechts, unten, d, pad)
		gooby.visible = platz.x >= 0.0
		if gooby.visible:
			gooby.position = platz


## Muster-Kachelung + Aspect des Backdrop-Shaders der Canvas-Größe
## nachführen (Kachel-Periode Web-treu 384 Design-px, ×f — wie AcWallpaper).
static func aktualisiere_backdrop(backdrop: ColorRect, host_size: Vector2, f: float) -> void:
	if backdrop == null or not (backdrop.material is ShaderMaterial):
		return
	var mat := backdrop.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", host_size)
	mat.set_shader_parameter(
		"tile_count", maxf(host_size.x / (AcWallpaper.TILE_DESIGN_PX * maxf(f, 0.01)), 0.5)
	)


## W21: Countdown-Label (grow BOTH) auf die SPIELFELD-Mitte verankern statt
## auf die Canvas-Mitte — bei Pillar-/Letterbox stand die Ziffer sonst halb
## auf der Kulisse (Creme-Outline auf Creme-Backdrop unsichtbar) und
## kollidierte mit In-Game-Texten außerhalb der Bühne.
static func zentriere_countdown(
	label: Control, stage_pos: Vector2, fitted: Vector2, host_size: Vector2
) -> void:
	if label == null:
		return
	var mitte := stage_pos + fitted * 0.5
	label.anchor_left = mitte.x / maxf(host_size.x, 1.0)
	label.anchor_right = label.anchor_left
	label.anchor_top = mitte.y / maxf(host_size.y, 1.0)
	label.anchor_bottom = label.anchor_top
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = 0.0
	label.offset_bottom = 0.0


## W21/P4 (b): dezenter Score-Delta-Float unter der Score-Kapsel — EIN
## wiederverwendetes Label (kein Stapeln), Pop-In beim ersten Zeigen, Puls
## bei Folge-Deltas, nach FLOAT_HALTE_SEC Abgang nach OBEN (alles
## MotionKit-Grammatik, Reduced-Motion-gated). Liefert das Label zurück
## (der Host hält die Referenz über die Runde).
static func score_float(
	label: Label, overlay: Control, anker: Control, delta: int, f: float
) -> Label:
	if delta == 0 or overlay == null or anker == null:
		return label
	var float_label := label
	if float_label == null or not is_instance_valid(float_label):
		float_label = Label.new()
		float_label.name = "ScoreDeltaFloat"
		float_label.theme_type_variation = &"CaptionLabel"
		float_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(float_label)
	float_label.text = ("+%d" % delta) if delta > 0 else str(delta)
	float_label.add_theme_color_override(
		"font_color", GeistChip.FARBE_VORN if delta > 0 else GeistChip.FARBE_HINTEN
	)
	ScreenShell.scale_fonts(float_label, f)
	var frisch := not float_label.visible
	float_label.modulate.a = 1.0
	float_label.show()
	var basis := anker.get_global_rect()
	float_label.global_position = Vector2(
		basis.position.x + basis.size.x * 0.5 - float_label.get_combined_minimum_size().x * 0.5,
		basis.position.y + basis.size.y + 2.0 * f
	)
	if frisch:
		MotionKit.pop_in(float_label)
	else:
		MotionKit.puls(float_label)
	var token := int(float_label.get_meta(&"p4_float_token", 0)) + 1
	float_label.set_meta(&"p4_float_token", token)
	var tree := overlay.get_tree()
	if tree != null:
		# Kurzlebige Labels nur schwach binden: wird die Bühne vor dem Timer
		# abgebaut, darf der Callback keine bereits freigegebene Instanz
		# typprüfen (Godot loggt dabei sonst einen SCRIPT ERROR).
		tree.create_timer(FLOAT_HALTE_SEC, true, false, true).timeout.connect(
			_score_float_weg.bind(weakref(float_label), token)
		)
	return float_label


## Schild-Platz: breitestes Seitenband zuerst (oben angedockt), sonst das
## Letterbox-Band unter dem Feld — (-1,-1) = kein Platz, Schild weg.
static func _schild_platz(
	links: Rect2, rechts: Rect2, unten: Rect2, brauch: Vector2, pad: float
) -> Vector2:
	var band := links if links.size.x >= rechts.size.x else rechts
	if band.size.x >= brauch.x + pad * 2.0 and band.size.y >= brauch.y:
		return Vector2(band.position.x + (band.size.x - brauch.x) * 0.5, band.position.y + pad)
	if unten.size.y >= brauch.y + pad * 2.0 and unten.size.x >= brauch.x:
		return Vector2(unten.position.x + (unten.size.x - brauch.x) * 0.5, unten.position.y + pad)
	return Vector2(-1.0, -1.0)


## Gooby-Platz: das Band GEGENÜBER dem Schild (unten angedockt — er
## „wartet" am Bühnenfuß), sonst rechts im Letterbox-Band.
static func _gooby_platz(
	links: Rect2, rechts: Rect2, unten: Rect2, d: float, pad: float
) -> Vector2:
	var band := rechts if links.size.x >= rechts.size.x else links
	if band.size.x >= d + pad * 2.0 and band.size.y >= d:
		return Vector2(
			band.position.x + (band.size.x - d) * 0.5, band.position.y + band.size.y - d - pad
		)
	if unten.size.y >= d + pad * 2.0 and unten.size.x >= d * 2.0 + pad * 4.0:
		return Vector2(unten.position.x + unten.size.x - d - pad * 2.0, unten.position.y + pad)
	return Vector2(-1.0, -1.0)


## Score-Float-Abgang (gebundene statische Methode): nur der JÜNGSTE
## Zeige-Aufruf darf verabschieden (Token-Wächter gegen Timer-Rennen).
static func _score_float_weg(label_ref: WeakRef, token: int) -> void:
	var label: Variant = label_ref.get_ref()
	if label == null or not is_instance_valid(label):
		return
	var l := label as Label
	if l == null:
		return
	if int(l.get_meta(&"p4_float_token", 0)) != token or not l.visible:
		return
	var tween := MotionKit.blatt_slide_out(l, -MotionKit.BLATT_OFFSET)
	if tween != null:
		await tween.finished
	if is_instance_valid(l) and int(l.get_meta(&"p4_float_token", 0)) == token:
		l.hide()


## Themen-Kulisse: vertikaler Verlauf im Spiel-Mood + dezente Muster-
## Kachel + Papier-Vorhang-Vignette. Farben als Uniforms aus AcTokens/
## AcWallpaper (keine Freihand-Farben im Shader), EIN statischer Pass.
## Motiv → Ink-Silhouette: dunkle Zeichnung bleibt als leiser Stempel,
## der helle Papier-Grund des Motivs verschwindet (ein statischer Pass,
## llvmpipe-billig). Stärke steuert self_modulate.a (SILHOUETTE_ALPHA).
static func _silhouette_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 ink : source_color = vec4(0.25, 0.22, 0.2, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	// Boden bei 0.05: der Papier-Grund (lum ~0.97) faellt komplett raus.
	float form = smoothstep(0.05, 0.55, 1.0 - lum);
	COLOR = vec4(ink.rgb, COLOR.a * form);
}
"""
	return shader


static func _backdrop_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 oben : source_color = vec4(1.0);
uniform vec4 unten : source_color = vec4(1.0);
uniform vec4 rand : source_color = vec4(0.0);
uniform sampler2D muster : repeat_enable, filter_linear_mipmap;
uniform float muster_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float tile_count = 3.0;
uniform vec2 rect_size = vec2(1280.0, 720.0);
void fragment() {
	vec3 grund = mix(oben.rgb, unten.rgb, smoothstep(0.0, 1.0, UV.y));
	float aspect = rect_size.y / max(rect_size.x, 1.0);
	vec4 glyph = texture(muster, UV * tile_count * vec2(1.0, aspect));
	grund = mix(grund, glyph.rgb, glyph.a * muster_opacity);
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(0.3, 0.85, length(d) * 1.35);
	COLOR = vec4(mix(grund, rand.rgb, edge * rand.a), 1.0);
}
"""
	return shader
