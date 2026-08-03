class_name PassportCard
extends PanelContainer
## Reisepass 2.0 (W13B, Doc H §2.2): die GOOBY-PASS-Karte im Profil als
## interaktive FLIP-KARTE. Tap → 3D-Flip-Tween (Reduced Motion = harter
## Wechsel). VORDERSEITE: Kinderpass-Layout in AC-Token-Farben mit Wappen-
## Glyph + "GOOBY-REPUBLIK", PASSFOTO-Slot (Standard = echtes 3D-Porträt;
## "Foto ändern" öffnet einen Galerie-Picker über der GalerieLogic-API —
## das gewählte Foto wird rund maskiert, −2° "bürokratisch schief" gezeigt
## und ADDITIV unter `profile.passPhoto` persistiert, kein Schema-Edit),
## Spielername, Gooby-Spitzname, "Ausgestellt: <Erststart-Datum>" und eine
## rotierende Gag-Merkmalszeile. RÜCKSEITE: Stempelseite — pro besuchtem
## Urlaubsziel (vacation.visited) ein gedrehter AC-Chip-Stempel mit
## Ziel-Glyph + Datum (Postkarten-Archiv), "5.0 UMZUG"-Sonderstempel bei
## migrierten Saves (meta.importedFrom), MRZ-Gag unten (MrzGag, pur).
##
## Zeit injizierbar über `now_ms` (Merkmals-Rotation); Reduced Motion über
## `reduziert_override` (Tests) bzw. ThemeService. Ableitungen (Stempel,
## Passfoto, Seitenwechsel, Maske) sind statisch/pur und einzeln testbar.

signal seite_gewechselt(seite: String)
signal passfoto_geaendert(pfad: String)

const Leveling := preload("res://scripts/logic/leveling.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")

const SEITE_VORNE := "vorne"
const SEITE_HINTEN := "hinten"
## Halbe Flip-Dauer (zu 0 drehen, Seite tauschen, zurück auf 1).
const FLIP_S := 0.16
## Additiver Save-Pfad des Passfotos (profile-Slice, merge_defaults-sicher).
const PASSFOTO_PFAD := "profile.passPhoto"
## "Bürokratisch schief" aufgeklebt (Doc H §2.2: −2°).
const FOTO_SCHIEF_GRAD := -2.0
## Passfotos werden vor dem Maskieren auf diese Kante gedeckelt (Speicher).
const FOTO_MAX_PX := 256

## Stempel-Glyphen je Reiseziel (Ids = Vacation.CATALOG/ReiseLogic.ZIELE).
const ZIEL_GLYPHEN := {
	"beach": "⛱",
	"harbor": "⚓",
	"meadowTrip": "✿",
	"spookGarden": "👻",
	"bakery": "🥨",
	"bigCity": "🏙",
	"nightSky": "☾",
	"toyRoom": "🧸",
	"space": "🚀",
}
const UMZUG_GLYPH := "📦"
const UMZUG_ID := "umzug"
## W13B (RAUMSTATION-Request): goldener Sonderstempel bei 9/9 Zielen.
const WELTENGOOBY_GLYPH := "🌍"
const WELTENGOOBY_ID := "weltengooby"

static var _mono_cache: Font = null

## GameState (Injektion durch den Profil-Screen bzw. Tests).
var gs: Object = null
## Aktuelle Seite (SEITE_VORNE/SEITE_HINTEN).
var seite := SEITE_VORNE
## Tests: true/false erzwingt Reduced Motion; null = ThemeService fragen.
var reduziert_override: Variant = null
## Injizierbare Uhr (Merkmals-Gag-Rotation).
var now_ms := Callable()
## Der Passfoto-Slot — der Profil-Screen skaliert ihn (Metrics-Hook).
var foto_slot: PanelContainer

var _vorn: VBoxContainer
var _hinten: VBoxContainer
var _flipping := false
var _picker: CanvasLayer
## G3: der "Foto ändern"-Knopf — hält den physischen Touch-Floor selbst
## (der Profil-Screen skaliert nur sein eigenes Chrome).
var _foto_btn: Button
## W14: Schmal-Modus (Hochformat-Telefone) — Feldzeilen stapeln Schlüssel
## über Wert wie die Web-Referenz (.b3-pass-field); breit bleibt einzeilig.
var _schmal := false
var _feld_reihen: Array[BoxContainer] = []


func _init() -> void:
	# Slot schon im _init anlegen: der Profil-Screen greift direkt nach
	# new() darauf zu (Metrics), der Inhalt kommt in _ready().
	foto_slot = PanelContainer.new()
	foto_slot.name = "FotoSlot"


func _ready() -> void:
	theme_type_variation = &"AcCardLg"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vorn = _baue_vorderseite()
	add_child(_vorn)
	_hinten = _baue_rueckseite()
	_hinten.visible = false
	add_child(_hinten)
	_wende_floors_an()
	get_viewport().size_changed.connect(_on_viewport_groesse)


func _exit_tree() -> void:
	_schliesse_picker()


func _gui_input(event: InputEvent) -> void:
	var maus := event as InputEventMouseButton
	if maus != null and maus.pressed and maus.button_index == MOUSE_BUTTON_LEFT:
		flip()
		accept_event()
		return
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		flip()
		accept_event()


## ---------------------------------------------------------------- Flip


## Pure Zustandsmaschine des Flips (Test-Kontrakt).
static func naechste_seite(aktuell: String) -> String:
	return SEITE_HINTEN if aktuell == SEITE_VORNE else SEITE_VORNE


func flip() -> void:
	if _flipping or _vorn == null:
		return
	seite = naechste_seite(seite)
	AudioDirector.try_play(self, "ui_click")
	if _ist_reduziert():
		_zeige_seite()
		seite_gewechselt.emit(seite)
		return
	_flipping = true
	pivot_offset = size / 2.0
	var tween := create_tween()
	var zu := tween.tween_property(self, "scale:x", 0.0, FLIP_S)
	zu.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_zeige_seite)
	var auf := tween.tween_property(self, "scale:x", 1.0, FLIP_S)
	auf.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_flip_fertig)


func _zeige_seite() -> void:
	_vorn.visible = seite == SEITE_VORNE
	_hinten.visible = seite == SEITE_HINTEN


func _flip_fertig() -> void:
	_flipping = false
	seite_gewechselt.emit(seite)


func _ist_reduziert() -> bool:
	if reduziert_override is bool:
		return reduziert_override
	return ThemeService.is_reduced_motion(self)


## ---------------------------------------------------------------- Passfoto


## Passfoto-Pfad aus dem Save ("" = keins gesetzt → 3D-Porträt).
static func passfoto_von(state: Dictionary) -> String:
	var profil: Variant = state.get("profile")
	if not (profil is Dictionary):
		return ""
	var pfad: Variant = (profil as Dictionary).get("passPhoto", "")
	return pfad if pfad is String else ""


## Passfoto ADDITIV im profile-Slice persistieren ("" = zurück zum Porträt).
static func setze_passfoto(game_state: Object, pfad: String) -> void:
	if game_state == null:
		return
	game_state.set_value(PASSFOTO_PFAD, pfad)
	if game_state.has_method("notify_slice_changed"):
		game_state.notify_slice_changed("profile")


## Quadratischer Center-Crop + runde Alpha-Maske (Passfoto-Look, pur).
static func runde_maske(bild: Image) -> Image:
	var kante := mini(bild.get_width(), bild.get_height())
	var quell := bild.get_region(
		Rect2i((bild.get_width() - kante) / 2, (bild.get_height() - kante) / 2, kante, kante)
	)
	if kante > FOTO_MAX_PX:
		quell.resize(FOTO_MAX_PX, FOTO_MAX_PX, Image.INTERPOLATE_BILINEAR)
		kante = FOTO_MAX_PX
	quell.convert(Image.FORMAT_RGBA8)
	var mitte := kante / 2.0
	var radius := kante / 2.0
	for y in kante:
		for x in kante:
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(mitte, mitte)) > radius:
				quell.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return quell


## ---------------------------------------------------------------- Stempel


## Stempel-Ableitung (pur): pro besuchtem Ziel ein Eintrag in UI-Reihenfolge
## (ReiseLogic.ZIELE), Datum = jüngste Postkarten-Archiv-Karte des Ziels
## (0 = ohne Datum), dazu der "5.0 UMZUG"-Sonderstempel bei migrierten Saves.
static func stempel_von(state: Dictionary) -> Array:
	var v := Vacation.slice_of(state)
	var visited: Dictionary = v["visited"]
	var archiv: Array = v["archive"]
	var out: Array = []
	for ziel_id: String in ReiseLogic.ZIELE:
		if not (visited.get(ziel_id, false) is bool and bool(visited.get(ziel_id, false))):
			continue
		(
			out
			. append(
				{
					"id": ziel_id,
					"glyph": ZIEL_GLYPHEN.get(ziel_id, "✈"),
					"name_key": "travel.ziel.%s" % ziel_id,
					"at_ms": _juengste_karte_ms(archiv, ziel_id),
					"drehung": stempel_drehung(ziel_id),
					"farbe": stempel_farbe(ziel_id),
				}
			)
		)
	# W13B (RAUMSTATION-Request): goldener WELTENGOOBY-Stempel, sobald
	# reise_logic.abholen den 9/9-Titel gelatcht hat (Vacation.weltengooby).
	if Vacation.weltengooby(v):
		(
			out
			. append(
				{
					"id": WELTENGOOBY_ID,
					"glyph": WELTENGOOBY_GLYPH,
					"name_key": "reisepass.stempel_weltengooby",
					"at_ms": int(v["weltengoobyAt"]),
					"drehung": stempel_drehung(WELTENGOOBY_ID),
					"farbe": AcTokens.YELLOW_DARK,
				}
			)
		)
	var meta: Variant = state.get("meta")
	var importiert := ""
	var importiert_ms := 0
	if meta is Dictionary:
		var roh: Variant = (meta as Dictionary).get("importedFrom", "")
		importiert = roh if roh is String else ""
		importiert_ms = _ms((meta as Dictionary).get("importedAt"))
	if not importiert.is_empty():
		(
			out
			. append(
				{
					"id": UMZUG_ID,
					"glyph": UMZUG_GLYPH,
					"name_key": "reisepass.stempel_umzug",
					"at_ms": importiert_ms,
					"drehung": stempel_drehung(UMZUG_ID),
					"farbe": AcTokens.DANGER,
				}
			)
		)
	return out


## Deterministische Stempel-Drehung: −6°..+6° aus der Ziel-Id.
static func stempel_drehung(ziel_id: String) -> float:
	return float(MrzGag.hash_of(ziel_id) % 13 - 6)


## Deterministische Stempel-Farbe — NUR AC-Tokens.
static func stempel_farbe(ziel_id: String) -> Color:
	var pool: Array[Color] = [
		AcTokens.TEAL_DARK, AcTokens.PINK_DARK, AcTokens.LEAF_DARK, AcTokens.YELLOW_DARK
	]
	return pool[MrzGag.hash_of("stempel|" + ziel_id) % pool.size()]


## Merkmals-Gag: deterministische Rotation (Spitzname + Tag) über n Texte.
static func merkmal_index(spitzname: String, tag_index: int, anzahl: int) -> int:
	if anzahl <= 0:
		return 0
	return (MrzGag.hash_of(spitzname) + tag_index) % anzahl


static func _juengste_karte_ms(archiv: Array, ziel_id: String) -> int:
	var best := 0
	for eintrag: Variant in archiv:
		if not (eintrag is Dictionary):
			continue
		if str((eintrag as Dictionary).get("destId", "")) != ziel_id:
			continue
		best = maxi(best, _ms((eintrag as Dictionary).get("atMs")))
	return best


static func _ms(wert: Variant) -> int:
	match typeof(wert):
		TYPE_INT, TYPE_FLOAT:
			return int(wert)
		_:
			return 0


static func _mono_font() -> Font:
	if _mono_cache == null:
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(
			["JetBrains Mono", "DejaVu Sans Mono", "Menlo", "Consolas", "monospace"]
		)
		_mono_cache = sys
	return _mono_cache


## ---------------------------------------------------------------- Vorderseite


func _baue_vorderseite() -> VBoxContainer:
	_feld_reihen.clear()
	var box := VBoxContainer.new()
	box.name = "Vorderseite"
	box.add_theme_constant_override("separation", 8)

	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 10)
	kopf.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(kopf)
	var wappen := Label.new()
	wappen.name = "Wappen"
	wappen.text = I18nService.t("reisepass.wappen")
	kopf.add_child(wappen)
	var kopf_spalte := VBoxContainer.new()
	kopf_spalte.add_theme_constant_override("separation", 0)
	kopf.add_child(kopf_spalte)
	var republik := Label.new()
	republik.name = "PassRepublik"
	republik.theme_type_variation = &"HeadlineLabel"
	republik.text = I18nService.t("reisepass.republik")
	republik.add_theme_color_override("font_color", AcTokens.PINK_DARK)
	kopf_spalte.add_child(republik)
	var wort := Label.new()
	wort.name = "PassWort"
	wort.theme_type_variation = &"SoftLabel"
	wort.text = I18nService.t("reisepass.dokument")
	wort.uppercase = true
	kopf_spalte.add_child(wort)

	var reihe := HBoxContainer.new()
	reihe.add_theme_constant_override("separation", 16)
	box.add_child(reihe)
	reihe.add_child(foto_slot)
	_baue_foto_slot()

	var felder := VBoxContainer.new()
	felder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	felder.alignment = BoxContainer.ALIGNMENT_CENTER
	felder.add_theme_constant_override("separation", 6)
	reihe.add_child(felder)

	var name_label := Label.new()
	name_label.name = "GoobyName"
	name_label.theme_type_variation = &"TitleLabel"
	name_label.text = str(_wert("meta.goobyNickname", "Gooby"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	felder.add_child(name_label)
	felder.add_child(
		_field_row("SpielerName", I18nService.t("reisepass.name"), _spieler_name_text())
	)
	var ausgestellt := Label.new()
	ausgestellt.name = "DabeiSeit"
	ausgestellt.theme_type_variation = &"SoftLabel"
	ausgestellt.text = I18nService.t("reisepass.ausgestellt", {"date": _ausstellungs_datum()})
	ausgestellt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	felder.add_child(ausgestellt)
	felder.add_child(_baue_level_row())
	felder.add_child(_field_row("Spielzeit", I18nService.t("profil.spielzeit"), _spielzeit_text()))
	felder.add_child(
		_field_row(
			"Serie",
			I18nService.t("profil.serie"),
			I18nService.t("profil.serie_wert", {"n": int(_wert("daily.streak", 0))})
		)
	)
	felder.add_child(_field_row("Merkmale", I18nService.t("reisepass.merkmale"), _merkmal_text()))

	var fuss := HBoxContainer.new()
	fuss.add_theme_constant_override("separation", 10)
	box.add_child(fuss)
	var foto_btn := SquishButton.new()
	foto_btn.name = "FotoAendernBtn"
	foto_btn.theme_type_variation = &"BtnTeal"
	foto_btn.text = I18nService.t("reisepass.foto_aendern")
	foto_btn.focus_mode = Control.FOCUS_NONE
	# G3: Grundmaß bleibt 48 Design-px — den physischen Touch-Floor legt
	# _wende_floors_an nach dem Einhängen obendrauf (fix 48 px ≈ 15 pt hoch).
	foto_btn.custom_minimum_size = Vector2(0.0, 48.0)
	foto_btn.pressed.connect(_on_foto_aendern)
	fuss.add_child(foto_btn)
	_foto_btn = foto_btn
	var hinweis := Label.new()
	hinweis.name = "FlipHinweis"
	hinweis.theme_type_variation = &"CaptionLabel"
	hinweis.text = I18nService.t("reisepass.flip_hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hinweis.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hinweis.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fuss.add_child(hinweis)
	return box


## Foto-Slot füllen: gesetztes Passfoto (rund maskiert, −2° schief) ODER
## das echte 3D-Porträt (GoobyPreview mit den Save-Morphs, drehbar).
func _baue_foto_slot() -> void:
	for kind in foto_slot.get_children():
		foto_slot.remove_child(kind)
		kind.queue_free()
	var pfad := passfoto_von(_state())
	if not pfad.is_empty():
		var bild := Image.new()
		if bild.load(pfad) == OK:
			# Plain-Control-Rahmen dazwischen: Container.fit_child_in_rect
			# setzt die rotation DIREKTER Container-Kinder beim Sortieren auf
			# 0 zurück — nur so bleibt das Foto dauerhaft schief aufgeklebt.
			var rahmen := Control.new()
			rahmen.name = "FotoRahmen"
			var rect := TextureRect.new()
			rect.name = "PassFoto"
			rect.texture = ImageTexture.create_from_image(runde_maske(bild))
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			rect.rotation_degrees = FOTO_SCHIEF_GRAD
			rect.resized.connect(func() -> void: rect.pivot_offset = rect.size / 2.0)
			rahmen.add_child(rect)
			foto_slot.add_child(rahmen)
			return
	var preview := GoobyPreview.new()
	preview.name = "PassPortrait"
	var morphs: Variant = _wert("meta.charMorphs", {})
	if morphs is Dictionary and not (morphs as Dictionary).is_empty():
		preview.set_morphs(morphs)
	foto_slot.add_child(preview)


func _baue_level_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "LevelRow"
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"HeadlineLabel"
	label.text = I18nService.t("profil.level_von", {"level": _level(), "max": Leveling.MAX_LEVEL})
	row.add_child(label)
	if _level() >= Leveling.MAX_LEVEL:
		var voll := Label.new()
		voll.name = "LevelMax"
		voll.theme_type_variation = &"SoftLabel"
		voll.text = I18nService.t("profil.level_max")
		voll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(voll)
		return row
	var bar := ProgressBar.new()
	bar.name = "XpBar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = _xp_ratio()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, 12.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row


## ---------------------------------------------------------------- Rückseite


func _baue_rueckseite() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Rueckseite"
	box.add_theme_constant_override("separation", 8)
	var titel := Label.new()
	titel.name = "StempelTitel"
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("reisepass.stempel_titel")
	titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(titel)
	var liste := stempel_von(_state())
	# W18/R3 Level-Reise: Meilenstein-Stempel (Level 5/10/… — Torte, L40 die
	# Goldene Möhre) ADDITIV hinter den Reise-Stempeln; rückwirkend still
	# gestempelte tragen at_ms 0 und damit kein Datum.
	liste.append_array(LevelReiseLogic.meilenstein_stempel(_state()))
	if liste.is_empty():
		var leer := Label.new()
		leer.name = "StempelLeer"
		leer.theme_type_variation = &"SoftLabel"
		leer.text = I18nService.t("reisepass.stempel_leer")
		leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(leer)
	else:
		var flow := HFlowContainer.new()
		flow.name = "StempelFlow"
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 12)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(flow)
		for eintrag: Dictionary in liste:
			flow.add_child(_stempel_chip(eintrag))
	box.add_child(_baue_mrz())
	var zurueck := Label.new()
	zurueck.name = "ZurueckHinweis"
	zurueck.theme_type_variation = &"CaptionLabel"
	zurueck.text = I18nService.t("reisepass.zurueck_hinweis")
	zurueck.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(zurueck)
	return box


## Ein prozeduraler Stempel: gedrehter Rahmen-Chip (AC-Farbe) mit Glyph,
## Zielname und Datum — wie mit wackliger Hand in den Pass gedrückt.
## Rückgabe ist ein plain-Control-Rahmen: der HFlowContainer würde die
## rotation direkter Kinder beim Sortieren auf 0 zurücksetzen.
func _stempel_chip(eintrag: Dictionary) -> Control:
	var rahmen := Control.new()
	rahmen.name = "StempelRahmen_%s" % str(eintrag["id"])
	var chip := PanelContainer.new()
	chip.name = "Stempel_%s" % str(eintrag["id"])
	var farbe: Color = eintrag["farbe"]
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.set_border_width_all(2)
	sb.border_color = farbe
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	chip.add_theme_stylebox_override("panel", sb)
	chip.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.rotation_degrees = float(eintrag["drehung"])
	chip.resized.connect(func() -> void: chip.pivot_offset = chip.size / 2.0)
	rahmen.add_child(chip)
	# Der Rahmen reserviert im Flow die Chip-Mindestgröße (Fonts kommen erst
	# im Baum an — minimum_size_changed zieht nach).
	chip.minimum_size_changed.connect(
		func() -> void: rahmen.custom_minimum_size = chip.get_combined_minimum_size()
	)
	rahmen.custom_minimum_size = chip.get_combined_minimum_size()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	chip.add_child(box)
	var zeile := Label.new()
	zeile.name = "StempelName"
	zeile.theme_type_variation = &"SoftLabel"
	# W18/R3: Einträge mit vor-lokalisiertem `label` (Meilenstein-Stempel
	# „Level {n}“ — der Platzhalter braucht Args) nutzen diesen direkt,
	# klassische Einträge weiter ihren name_key.
	var stempel_text := str(eintrag.get("label", ""))
	if stempel_text.is_empty():
		stempel_text = I18nService.t(str(eintrag["name_key"]))
	zeile.text = "%s %s" % [str(eintrag["glyph"]), stempel_text]
	zeile.add_theme_color_override("font_color", farbe)
	box.add_child(zeile)
	var at_ms := int(eintrag["at_ms"])
	if at_ms > 0:
		var datum := Label.new()
		datum.name = "StempelDatum"
		datum.theme_type_variation = &"CaptionLabel"
		datum.text = I18nService.t("reisepass.stempel_datum", {"date": _datum_text(at_ms)})
		datum.add_theme_color_override("font_color", farbe)
		box.add_child(datum)
	return rahmen


func _baue_mrz() -> Control:
	var zone := PanelContainer.new()
	zone.name = "MrzZone"
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PAPER_SHADE
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	zone.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	zone.add_child(box)
	var mrz := MrzGag.zeilen(
		str(_wert("meta.playerName", "")), str(_wert("meta.goobyNickname", "Gooby"))
	)
	for i in mrz.size():
		var label := Label.new()
		label.name = "MrzZeile%d" % (i + 1)
		label.text = str(mrz[i])
		label.add_theme_font_override("font", _mono_font())
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", AcTokens.INK)
		label.clip_text = true
		box.add_child(label)
	return zone


## ---------------------------------------------------------------- Picker


## G3 (HOCH-Fix ui-profil §2): physischer Touch-Floor auf den Foto-Knopf —
## beim Einhängen und nach Rotation/Resize (touch_target wächst monoton).
func _wende_floors_an() -> void:
	if not is_inside_tree() or _foto_btn == null or not is_instance_valid(_foto_btn):
		return
	ScreenShell.touch_target(_foto_btn, ScreenShell.metrics(get_viewport()))


func _on_viewport_groesse() -> void:
	if is_inside_tree():
		_wende_floors_an()


## Galerie-Picker: Fotos aus dem FotoModus-Index (GalerieLogic-API, nur
## LESEND) als Kachel-Raster; Tap klebt das Foto in den Pass.
## G3: Karte/Raster/Knöpfe skalieren jetzt mit den ScreenShell-Metrics
## (vorher feste Design-px — auf Retina eine Briefmarke in Bildmitte).
func _on_foto_aendern() -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	_picker = CanvasLayer.new()
	_picker.name = "PassFotoPicker"
	get_tree().root.add_child(_picker)
	var wurzel := Control.new()
	wurzel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	wurzel.theme = ThemeService.theme()
	_picker.add_child(wurzel)
	var schleier := ColorRect.new()
	schleier.color = AcTokens.VEIL
	schleier.set_anchors_preset(Control.PRESET_FULL_RECT)
	schleier.gui_input.connect(_on_picker_backdrop)
	wurzel.add_child(schleier)
	var karte := PanelContainer.new()
	karte.name = "PickerKarte"
	karte.theme_type_variation = &"AcCard"
	karte.set_anchors_preset(Control.PRESET_CENTER)
	karte.grow_horizontal = Control.GROW_DIRECTION_BOTH
	karte.grow_vertical = Control.GROW_DIRECTION_BOTH
	wurzel.add_child(karte)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	karte.add_child(box)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("reisepass.picker_titel")
	box.add_child(titel)
	var fotos := GalerieLogic.fotos_von(_state())
	if fotos.is_empty():
		var leer := Label.new()
		leer.name = "PickerLeer"
		leer.theme_type_variation = &"SoftLabel"
		leer.text = I18nService.t("reisepass.picker_leer")
		leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leer.custom_minimum_size = Vector2(320.0 * f, 0.0)
		box.add_child(leer)
	else:
		box.add_child(_baue_picker_raster(fotos, m))
	var leiste := HBoxContainer.new()
	leiste.add_theme_constant_override("separation", 10)
	box.add_child(leiste)
	if not passfoto_von(_state()).is_empty():
		var standard := SquishButton.new()
		standard.name = "PickerStandard"
		standard.theme_type_variation = &"BtnYellow"
		standard.text = I18nService.t("reisepass.picker_standard")
		standard.custom_minimum_size = Vector2(0.0, 48.0 * f)
		standard.focus_mode = Control.FOCUS_NONE
		standard.pressed.connect(_on_picker_standard)
		ScreenShell.touch_target(standard, m)
		leiste.add_child(standard)
	var abbrechen := SquishButton.new()
	abbrechen.name = "PickerAbbrechen"
	abbrechen.theme_type_variation = &"BtnGhost"
	abbrechen.text = I18nService.t("reisepass.picker_abbrechen")
	abbrechen.custom_minimum_size = Vector2(0.0, 48.0 * f)
	abbrechen.focus_mode = Control.FOCUS_NONE
	abbrechen.pressed.connect(_schliesse_picker)
	ScreenShell.touch_target(abbrechen, m)
	leiste.add_child(abbrechen)
	# Picker hängt am CanvasLayer — die Font-Skalierung des Profil-Screens
	# erreicht ihn nicht, also hier selbst skalieren.
	ScreenShell.scale_fonts(wurzel, f)
	UiMotion.pop_in(karte)


## G3: Raster-Breite an ScreenShell.card_width gekoppelt (statt fixer
## 420×260), Spaltenzahl aus der Breite (2–4 statt fix 3), Kacheln ×f.
func _baue_picker_raster(fotos: Array, m: Dictionary) -> Control:
	var f: float = m["f"]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	var breite := minf(420.0 * f, ScreenShell.card_width(m, 520.0) - 40.0 * f)
	var hoehe := minf(
		260.0 * f, maxf(ScreenShell.card_max_height(m) - 3.2 * float(m["floor_px"]), 160.0)
	)
	scroll.custom_minimum_size = Vector2(breite, hoehe)
	var raster := GridContainer.new()
	raster.name = "PickerRaster"
	raster.columns = clampi(int(breite / (140.0 * f)), 2, 4)
	raster.add_theme_constant_override("h_separation", 10)
	raster.add_theme_constant_override("v_separation", 10)
	raster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(raster)
	for foto: Dictionary in fotos:
		raster.add_child(_picker_kachel(str(foto["pfad"]), f))
	return scroll


func _picker_kachel(pfad: String, f: float) -> Control:
	var karte := Button.new()
	karte.name = "FotoWahl_%s" % pfad.get_file().get_basename()
	karte.theme_type_variation = &"AcCard"
	karte.custom_minimum_size = Vector2(128.0, 96.0) * f
	karte.focus_mode = Control.FOCUS_NONE
	karte.clip_contents = true
	karte.pressed.connect(_on_foto_gewaehlt.bind(pfad))
	var bild := Image.new()
	if not pfad.is_empty() and bild.load(pfad) == OK:
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(bild)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		karte.add_child(rect)
	return karte


func _on_foto_gewaehlt(pfad: String) -> void:
	setze_passfoto(gs, pfad)
	_schliesse_picker()
	_baue_foto_slot()
	_zeige_toast(I18nService.t("reisepass.foto_gesetzt"))
	passfoto_geaendert.emit(pfad)


func _on_picker_standard() -> void:
	setze_passfoto(gs, "")
	_schliesse_picker()
	_baue_foto_slot()
	_zeige_toast(I18nService.t("reisepass.foto_standard_gesetzt"))
	passfoto_geaendert.emit("")


func _on_picker_backdrop(event: InputEvent) -> void:
	var maus := event as InputEventMouseButton
	if maus != null and maus.pressed:
		_schliesse_picker()


func _schliesse_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


## ---------------------------------------------------------------- Werte


func _state() -> Dictionary:
	if gs == null or not gs.has_method("state"):
		return {}
	return gs.state()


func _wert(pfad: String, standard: Variant) -> Variant:
	if gs == null or not gs.has_method("get_value"):
		return standard
	return gs.get_value(pfad, standard)


func _level() -> int:
	return int(_wert("progression.level", 1))


func _xp_ratio() -> float:
	if gs != null and gs.has_method("xp_ratio"):
		return clampf(float(gs.xp_ratio()), 0.0, 1.0)
	return 0.0


func _spieler_name_text() -> String:
	var name_wert := str(_wert("meta.playerName", "")).strip_edges()
	return name_wert if not name_wert.is_empty() else I18nService.t("reisepass.name_leer")


func _spielzeit_text() -> String:
	var minuten := int(_wert("profile.playtimeMin", 0))
	@warning_ignore("integer_division")
	return I18nService.t(
		"profil.spielzeit_wert", {"h": minuten / 60, "mm": "%02d" % (minuten % 60)}
	)


func _merkmal_text() -> String:
	var texte := I18nService.items("reisepass.merkmale_liste")
	if texte.is_empty():
		return ""
	@warning_ignore("integer_division")
	var tag := _jetzt_ms() / 86400000
	var idx := merkmal_index(str(_wert("meta.goobyNickname", "Gooby")), int(tag), texte.size())
	return str(texte[idx])


func _ausstellungs_datum() -> String:
	var created_ms := int(_wert("meta.createdAt", 0))
	if created_ms <= 0:
		created_ms = _jetzt_ms()
	return _datum_text(created_ms)


func _datum_text(at_ms: int) -> String:
	@warning_ignore("integer_division")
	var d := Time.get_datetime_dict_from_unix_time(at_ms / 1000)
	if I18nService.get_locale() == "de":
		return "%02d.%02d.%04d" % [d.day, d.month, d.year]
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _jetzt_ms() -> int:
	if now_ms.is_valid():
		return int(now_ms.call())
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _field_row(zeilen_name: String, key_text: String, value_text: String) -> Control:
	var row := BoxContainer.new()
	row.name = "Row%s" % zeilen_name
	row.add_theme_constant_override("separation", 8)
	var key := Label.new()
	key.theme_type_variation = &"SoftLabel"
	key.text = key_text
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key)
	var value := Label.new()
	value.name = "Wert"
	value.theme_type_variation = &"HeadlineLabel"
	value.text = value_text
	# W14: lange Werte (z. B. Merkmale) umbrechen statt die Karte im
	# Hochformat übers Canvas zu drücken — kurze Werte bleiben unverändert
	# rechtsbündig am Zeilenende.
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_stretch_ratio = 1.6
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_feld_reihen.append(row)
	_wende_schmal_an(row)
	return row


## Vom Profil-Screen (Metrics-Hook) gerufen: schmale Formate stapeln die
## Feldzeilen vertikal (Schlüssel über Wert, Web-Referenz .b3-pass-field)
## und lassen den Foto-Slot quadratisch oben statt zeilenhoch mitwachsen.
func setze_schmal(schmal: bool) -> void:
	if _schmal == schmal:
		return
	_schmal = schmal
	foto_slot.size_flags_vertical = (Control.SIZE_SHRINK_BEGIN if schmal else Control.SIZE_FILL)
	for row in _feld_reihen:
		if is_instance_valid(row):
			_wende_schmal_an(row)


func _wende_schmal_an(row: BoxContainer) -> void:
	row.vertical = _schmal
	var value := row.find_child("Wert", true, false) as Label
	if value != null:
		value.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT if _schmal else HORIZONTAL_ALIGNMENT_RIGHT
		)


func _zeige_toast(text: String) -> void:
	ToastLayer.zeige(self, text)
