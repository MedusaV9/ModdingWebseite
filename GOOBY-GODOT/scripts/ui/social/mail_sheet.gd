class_name MailSheet
extends Control
## Briefkasten-Sheet der Post (W13B, Doc C §3.7): Posteingang (Absender,
## lokales Datum, Ungelesen-Punkt, Foto-Thumbnail lazy per REST, Geschenk-Chip
## mit einmaligem Server-Claim) + „Brief schreiben“-Flow (Freund wählen, Text
## bis 500 Zeichen, optional Foto aus der Galerie — galerie_logic wird NUR
## gelesen —, optional Geschenk aus dem Inventar, Porto-Gag 5 Münzen).
## OFFLINE-FIRST: Senden legt ohne Netz einen Outbox-Eintrag an („wird
## zugestellt, sobald du online bist“); Porto + Geschenk werden transaktional
## über gs.update() VOR dem Senden entnommen und bei einem endgültigen
## Sende-Fehlschlag zurückgebucht (Web-Ökonomie ist client-autoritativ).
## Netz: NetMail (scripts/net/net_mail.gd) über /root/Net; Texte: mail.json.
##
## G3/P07 UI-POST: Karte skaliert über ScreenShell (card_width/×f/Touch-
## Floor + scale_fonts), expliziter Schließen-Knopf, Compose-Guard gegen
## Dim-Tap-Datenverlust (Nachfrage-Karte statt Sofort-queue_free) und
## Sounds nach Sound-Fixliste F7 (Outcome schlägt Press).
##
## W18/B7: das Sheet nimmt am Modal-System (G7-P53) teil — es meldet sich
## im PanelStack an/ab und bietet `close()` für den EINEN Zurück-Pfad
## (SceneRouter.handle_back_request → PanelStack.close_top; der Compose-
## Guard bleibt dabei gewahrt). Der Dim-Tap schließt nur, wenn das Sheet
## das OBERSTE Panel ist (Backdrop-Dismiss-Policy wie PanelSheet). Gemountet
## wird es im Ort über `OrtScene.zeige_overlay()` — deterministisch ÜBER
## einem offenen Schalter-PanelSheet.

signal toast_requested(text: String)
signal closed
## Der Ungelesen-Stand hat sich geändert (Badge am Post-Schalter).
signal unread_changed(unread: int)

const Economy := preload("res://scripts/logic/economy.gd")

## Porto-Gag: jeder Brief kostet 5 Münzen Porto (Frau Zettel stempelt ja auch).
const PORTO := 5
const GESCHENK_MENGE := 1
const THUMB_SIZE := Vector2(96, 96)
## G3/P07: Design-Basis der zentrierten Karte (Breite/Höhe) — zur Laufzeit
## über ScreenShell.card_width/card_max_height ×f skaliert + Safe-geklemmt.
const CARD_BASIS := Vector2(520.0, 520.0)
const LISTE_BASIS_HOEHE := 320.0
const TEXT_BASIS_HOEHE := 140.0

var mail_service: NetMail
var gs: Object

var _net: Node
var _inbox_box: VBoxContainer
var _compose_box: VBoxContainer
var _liste_slot: VBoxContainer
var _status_label: Label
var _freund_wahl: OptionButton
var _text_edit: TextEdit
var _zeichen_label: Label
var _foto_wahl: OptionButton
var _geschenk_wahl: OptionButton
var _send_button: Button
var _card: PanelContainer
var _scroll: ScrollContainer
var _verwerfen_dialog: PanelContainer
## Zuletzt eingesammelte ScreenShell-Metriken (für Spät-Bauten wie
## Brief-Zeilen/Nachfrage-Karte, ohne pro Node neu zu messen).
var _metrics: Dictionary = {}


func setup(net: Node, game_state: Object) -> void:
	_net = net
	gs = game_state
	mail_service = NetMail.attach(net)


func _ready() -> void:
	# W18/B7: als Modal am G7-P53-Stack anmelden — Backdrop-/Zurück-
	# Disziplin (nur das oberste Panel schließt) gilt damit auch hier.
	PanelStack.push(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_card = PanelContainer.new()
	_card.name = "MailKarte"
	_card.theme_type_variation = &"AcCard"
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_card.add_child(rows)

	var kopf_zeile := HBoxContainer.new()
	kopf_zeile.add_theme_constant_override("separation", 8)
	rows.add_child(kopf_zeile)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mail.titel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf_zeile.add_child(title)
	# G3/P07: expliziter Schließen-Knopf — Dim-Tap ist nicht mehr der
	# einzige (und im Compose-Fall datenvernichtende) Ausgang.
	var schliessen := SquishButton.new()
	schliessen.name = "SchliessenButton"
	schliessen.theme_type_variation = &"GhostButton"
	schliessen.text = "✕"
	schliessen.pressed.connect(_schliesse_angefragt)
	kopf_zeile.add_child(schliessen)
	_status_label = Label.new()
	_status_label.theme_type_variation = &"CaptionLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_status_label)

	_inbox_box = VBoxContainer.new()
	_inbox_box.add_theme_constant_override("separation", 8)
	_inbox_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_inbox_box)
	_compose_box = VBoxContainer.new()
	_compose_box.add_theme_constant_override("separation", 8)
	_compose_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_compose_box)
	_baue_inbox()
	_baue_compose()
	get_viewport().size_changed.connect(_relayout)
	_relayout()

	if mail_service != null:
		mail_service.mail_new.connect(_on_mail_new)
		mail_service.unread_changed.connect(func(n: int) -> void: unread_changed.emit(n))
	_zeige_inbox()
	# Eigenbau-Overlay (kein PanelSheet) → Öffnen klingt selbst (§3-Grammatik);
	# der „Briefkasten öffnen“-Knopf im Ort bleibt deshalb stumm.
	AudioDirector.try_play(self, "ui_open")


## W18/B7-Sicherheitsnetz: verlässt das Sheet den Baum an `_schliesse()`
## vorbei (Szenenwechsel, Eltern-queue_free), räumt es seinen Stack-
## Eintrag trotzdem ab — kein toter Top-Eintrag im Modal-System.
func _exit_tree() -> void:
	PanelStack.remove(self)


## G3/P07: Karte/Liste/Textfeld auf ×f-Skalierung + Safe-Klemmung heben,
## alle Tippflächen auf den Touch-Floor, Theme-Schriften ×f — wird bei
## size_changed und nach jedem Listen-/Compose-Rebuild erneut angewendet.
func _relayout() -> void:
	if not is_inside_tree() or _card == null:
		return
	_metrics = ScreenShell.metrics(get_viewport())
	var f: float = _metrics["f"]
	var max_hoehe := ScreenShell.card_max_height(_metrics)
	_card.custom_minimum_size = Vector2(
		ScreenShell.card_width(_metrics, CARD_BASIS.x), minf(CARD_BASIS.y * f, max_hoehe)
	)
	if _scroll != null:
		_scroll.custom_minimum_size = Vector2(0.0, minf(LISTE_BASIS_HOEHE * f, max_hoehe * 0.6))
	if _text_edit != null:
		var canvas: Vector2 = _metrics["canvas"]
		# Deckel gegen die iOS-Tastatur im Querformat: nie höher als ¼ Canvas.
		_text_edit.custom_minimum_size = Vector2(0.0, minf(TEXT_BASIS_HOEHE * f, canvas.y * 0.25))
		# ScreenShell.scale_fonts kennt nur Label/Button/LineEdit — den
		# Brieftext (TextEdit) von Hand von der Design-Basis aus skalieren.
		if not _text_edit.has_meta("g3_font_basis"):
			_text_edit.set_meta("g3_font_basis", _text_edit.get_theme_font_size("font_size"))
		var basis := int(_text_edit.get_meta("g3_font_basis"))
		_text_edit.add_theme_font_size_override("font_size", int(maxf(roundf(basis * f), 10.0)))
	for btn: Node in find_children("*", "Button", true, false):
		ScreenShell.touch_target(btn, _metrics)
	ScreenShell.scale_fonts(self, f)


# ---- Transaktions-Logik (pure statics — direkt testbar) ----


## Porto + Geschenk VOR dem Senden entnehmen (mutiert den Save-Draft;
## innerhalb von gs.update() rufen). false = nichts angefasst.
static func nimm_geschenk_und_porto(state: Dictionary, item: Dictionary, porto: int) -> bool:
	var econ: Variant = state.get("economy")
	if not (econ is Dictionary) or not Economy.can_afford(econ, porto):
		return false
	var menge := maxi(1, int(item.get("menge", GESCHENK_MENGE))) if not item.is_empty() else 0
	if not item.is_empty() and _vorrat(state, item) < menge:
		return false
	Economy.spend(econ, porto, "mailPorto")
	if not item.is_empty():
		_buche(state, item, -menge)
	return true


## Rückbuchung bei endgültigem Sende-Fehlschlag (Porto + Geschenk zurück).
static func gib_zurueck(state: Dictionary, item: Dictionary, porto: int) -> void:
	var econ: Variant = state.get("economy")
	if econ is Dictionary:
		Economy.award(econ, porto, "mailPorto")
	if not item.is_empty():
		_buche(state, item, maxi(1, int(item.get("menge", GESCHENK_MENGE))))


## Empfangenes Geschenk ins Inventar buchen (nach ok vom Server-Claim).
static func schreibe_gut(state: Dictionary, item: Dictionary) -> void:
	if not item.is_empty():
		_buche(state, item, maxi(1, int(item.get("menge", GESCHENK_MENGE))))


## Anzeigename eines Geschenks: Essen über den FoodCatalog, Sonstiges über
## `mail.item.<id>` (Fallback: die Id selbst, hübsch kapitalisiert).
static func item_name(item: Dictionary) -> String:
	var id := str(item.get("id", ""))
	if str(item.get("typ", "")) == "food":
		return FoodCatalog.display_name(id)
	var key := "mail.item.%s" % id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return id.capitalize()


static func _vorrat(state: Dictionary, item: Dictionary) -> int:
	var inv: Variant = state.get("inventory")
	if not (inv is Dictionary):
		return 0
	var slot: Variant = (inv as Dictionary).get(str(item.get("typ", "")))
	if not (slot is Dictionary):
		return 0
	return int((slot as Dictionary).get(str(item.get("id", "")), 0))


static func _buche(state: Dictionary, item: Dictionary, delta: int) -> void:
	var inv: Variant = state.get("inventory")
	if not (inv is Dictionary):
		inv = {}
		state["inventory"] = inv
	var typ := str(item.get("typ", "items"))
	var slot: Variant = (inv as Dictionary).get(typ)
	if not (slot is Dictionary):
		slot = {}
		(inv as Dictionary)[typ] = slot
	var id := str(item.get("id", ""))
	(slot as Dictionary)[id] = maxi(0, int((slot as Dictionary).get(id, 0)) + delta)


# ---- Posteingang ----


func _baue_inbox() -> void:
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	_inbox_box.add_child(kopf)
	var schreiben := SquishButton.new()
	schreiben.name = "SchreibenButton"
	schreiben.theme_type_variation = &"PrimaryButton"
	schreiben.text = I18nService.t("mail.schreiben")
	schreiben.pressed.connect(_on_schreiben)
	kopf.add_child(schreiben)
	var neu_laden := SquishButton.new()
	neu_laden.theme_type_variation = &"GhostButton"
	neu_laden.text = I18nService.t("mail.aktualisieren")
	neu_laden.pressed.connect(_on_aktualisieren)
	kopf.add_child(neu_laden)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inbox_box.add_child(_scroll)
	_liste_slot = VBoxContainer.new()
	_liste_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste_slot.add_theme_constant_override("separation", 8)
	_scroll.add_child(_liste_slot)


## F7: Ansichtswechsel Inbox → Compose klingt als Chip.
func _on_schreiben() -> void:
	AudioDirector.try_play(self, "ui_chip")
	_zeige_compose()


func _on_aktualisieren() -> void:
	AudioDirector.try_play(self, "ui_click")
	_lade_inbox()


func _zeige_inbox() -> void:
	_compose_box.visible = false
	_inbox_box.visible = true
	_lade_inbox()


func _lade_inbox() -> void:
	if mail_service == null:
		return
	_aktualisiere_status()
	if not mail_service.is_online():
		_render_liste([])
		return
	var res: Dictionary = await mail_service.fetch_inbox()
	if not is_instance_valid(self):
		return
	if not bool(res.get("ok", false)):
		_render_liste([])
		return
	var mails: Array = res.get("mails", []) if res.get("mails") is Array else []
	_render_liste(mails)


func _render_liste(mails: Array) -> void:
	for child in _liste_slot.get_children():
		child.queue_free()
	if mails.is_empty():
		var leer := Label.new()
		leer.theme_type_variation = &"CaptionLabel"
		leer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		leer.text = I18nService.t("mail.leer")
		_liste_slot.add_child(leer)
		return
	for mail: Variant in mails:
		if mail is Dictionary:
			_liste_slot.add_child(_baue_brief_zeile(mail))
	# Frisch gebaute Zeilen-Knöpfe auf Floor/×f heben.
	_relayout()


func _baue_brief_zeile(mail: Dictionary) -> Control:
	var karte := PanelContainer.new()
	karte.theme_type_variation = &"AcCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	karte.add_child(box)

	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 6)
	box.add_child(kopf)
	if not bool(mail.get("read", false)):
		var punkt := Label.new()
		punkt.name = "UngelesenPunkt"
		punkt.text = "●"
		punkt.add_theme_color_override("font_color", Color("#E4572E"))
		kopf.add_child(punkt)
	var absender := Label.new()
	absender.theme_type_variation = &"HeadlineLabel"
	absender.text = I18nService.t("mail.von", {"name": _absender_name(mail)})
	absender.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(absender)
	var datum := Label.new()
	datum.theme_type_variation = &"CaptionLabel"
	datum.text = GalerieLogic.datum(int(mail.get("at", 0)))
	kopf.add_child(datum)

	var text := str(mail.get("text", ""))
	if not text.is_empty():
		var text_label := Label.new()
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.text = text
		box.add_child(text_label)

	var photo_id := str(mail.get("photoId", ""))
	if not photo_id.is_empty():
		box.add_child(_baue_foto_thumbnail(photo_id))

	var item: Variant = mail.get("item")
	if item is Dictionary and not (item as Dictionary).is_empty():
		box.add_child(_baue_geschenk_chip(mail, item))

	var aktionen := HBoxContainer.new()
	aktionen.add_theme_constant_override("separation", 6)
	box.add_child(aktionen)
	if not bool(mail.get("read", false)):
		var gelesen := SquishButton.new()
		gelesen.theme_type_variation = &"GhostButton"
		gelesen.text = I18nService.t("mail.gelesen_knopf")
		gelesen.pressed.connect(_on_gelesen.bind(str(mail.get("id", "")), gelesen))
		aktionen.add_child(gelesen)
	var loeschen := SquishButton.new()
	loeschen.theme_type_variation = &"GhostButton"
	loeschen.text = I18nService.t("mail.loeschen")
	loeschen.pressed.connect(_on_loeschen.bind(str(mail.get("id", ""))))
	aktionen.add_child(loeschen)
	return karte


func _baue_foto_thumbnail(photo_id: String) -> Control:
	var rect := TextureRect.new()
	rect.custom_minimum_size = THUMB_SIZE * float(_metrics.get("f", 1.0))
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.tooltip_text = I18nService.t("mail.foto_laedt")
	_lade_foto(photo_id, rect)
	return rect


## Foto lazy nachladen (REST) und ins Thumbnail hängen.
func _lade_foto(photo_id: String, rect: TextureRect) -> void:
	if mail_service == null:
		return
	var res: Dictionary = await mail_service.fetch_photo(photo_id)
	if not is_instance_valid(rect):
		return
	if not bool(res.get("ok", false)):
		rect.tooltip_text = I18nService.t("mail.foto_fehlt")
		return
	var bytes := Marshalls.base64_to_raw(str(res.get("photo_b64", "")))
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK and image.load_jpg_from_buffer(bytes) != OK:
		rect.tooltip_text = I18nService.t("mail.foto_fehlt")
		return
	rect.texture = ImageTexture.create_from_image(image)


func _baue_geschenk_chip(mail: Dictionary, item: Dictionary) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = I18nService.t(
		"mail.geschenk",
		{"name": item_name(item), "n": maxi(1, int(item.get("menge", GESCHENK_MENGE)))}
	)
	chip.add_child(label)
	var knopf := SquishButton.new()
	knopf.name = "AnnehmenButton"
	knopf.theme_type_variation = &"AccentButton"
	if bool(mail.get("claimed", false)):
		knopf.text = I18nService.t("mail.angenommen")
		knopf.disabled = true
	else:
		knopf.text = I18nService.t("mail.annehmen")
		knopf.pressed.connect(_on_annehmen.bind(str(mail.get("id", "")), item, knopf))
	chip.add_child(knopf)
	return chip


## Geschenk annehmen: erst der einmalige Server-Claim, DANN die lokale
## Inventar-Gutschrift (Doppel-Gutschrift ausgeschlossen). F7: Druck bleibt
## stumm (Netz-Ausgang), der AUSGANG klingt — Belohnung als ui_sticker.
func _on_annehmen(mail_id: String, item: Dictionary, knopf: Button) -> void:
	if mail_service == null or gs == null:
		return
	knopf.disabled = true
	var res: Dictionary = await mail_service.claim_gift(mail_id)
	if not is_instance_valid(self):
		return
	if not bool(res.get("ok", false)):
		AudioDirector.try_play(self, "ui_error")
		toast_requested.emit(I18nService.t(str(res.get("message_key", "mail.err.generic"))))
		knopf.disabled = str(res.get("code", "")) == "ALREADY_CLAIMED"
		return
	var geschenk: Dictionary = res.get("item", item)
	gs.update(func(state: Dictionary) -> void: MailSheet.schreibe_gut(state, geschenk))
	knopf.text = I18nService.t("mail.angenommen")
	AudioDirector.try_play(self, "ui_sticker")
	Haptics.success(self)
	toast_requested.emit(
		I18nService.t(
			"mail.toast.geschenk_da",
			{"name": item_name(geschenk), "n": maxi(1, int(geschenk.get("menge", GESCHENK_MENGE)))}
		)
	)


func _on_gelesen(mail_id: String, knopf: Button) -> void:
	AudioDirector.try_play(self, "ui_click")
	if mail_service == null:
		return
	knopf.disabled = true
	var res: Dictionary = await mail_service.ack(mail_id)
	if not is_instance_valid(self):
		return
	if bool(res.get("ok", false)):
		_lade_inbox()
	else:
		knopf.disabled = false


func _on_loeschen(mail_id: String) -> void:
	AudioDirector.try_play(self, "ui_click")
	if mail_service == null:
		return
	var res: Dictionary = await mail_service.delete_mail(mail_id)
	if not is_instance_valid(self):
		return
	if bool(res.get("ok", false)):
		_lade_inbox()
	else:
		toast_requested.emit(I18nService.t(str(res.get("message_key", "mail.err.generic"))))


func _on_mail_new(_mail: Dictionary) -> void:
	if _inbox_box.visible:
		_lade_inbox()


# ---- Brief schreiben ----


func _baue_compose() -> void:
	var an_zeile := HBoxContainer.new()
	an_zeile.add_theme_constant_override("separation", 8)
	_compose_box.add_child(an_zeile)
	var an_label := Label.new()
	an_label.theme_type_variation = &"HeadlineLabel"
	an_label.text = I18nService.t("mail.compose.an")
	an_zeile.add_child(an_label)
	_freund_wahl = OptionButton.new()
	_freund_wahl.name = "FreundWahl"
	_freund_wahl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	an_zeile.add_child(_freund_wahl)

	_text_edit = TextEdit.new()
	_text_edit.name = "BriefText"
	_text_edit.placeholder_text = I18nService.t("mail.compose.text_hint")
	_text_edit.custom_minimum_size = Vector2(0, 140)
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.text_changed.connect(_on_text_changed)
	_compose_box.add_child(_text_edit)
	_zeichen_label = Label.new()
	_zeichen_label.theme_type_variation = &"CaptionLabel"
	_zeichen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_compose_box.add_child(_zeichen_label)

	var foto_zeile := HBoxContainer.new()
	foto_zeile.add_theme_constant_override("separation", 8)
	_compose_box.add_child(foto_zeile)
	var foto_label := Label.new()
	foto_label.theme_type_variation = &"HeadlineLabel"
	foto_label.text = I18nService.t("mail.compose.foto")
	foto_zeile.add_child(foto_label)
	_foto_wahl = OptionButton.new()
	_foto_wahl.name = "FotoWahl"
	_foto_wahl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foto_zeile.add_child(_foto_wahl)

	var geschenk_zeile := HBoxContainer.new()
	geschenk_zeile.add_theme_constant_override("separation", 8)
	_compose_box.add_child(geschenk_zeile)
	var geschenk_label := Label.new()
	geschenk_label.theme_type_variation = &"HeadlineLabel"
	geschenk_label.text = I18nService.t("mail.compose.geschenk")
	geschenk_zeile.add_child(geschenk_label)
	_geschenk_wahl = OptionButton.new()
	_geschenk_wahl.name = "GeschenkWahl"
	_geschenk_wahl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	geschenk_zeile.add_child(_geschenk_wahl)

	var aktionen := HBoxContainer.new()
	aktionen.add_theme_constant_override("separation", 8)
	_compose_box.add_child(aktionen)
	var zurueck := SquishButton.new()
	zurueck.theme_type_variation = &"GhostButton"
	zurueck.text = I18nService.t("mail.zurueck")
	zurueck.pressed.connect(_on_compose_zurueck)
	aktionen.add_child(zurueck)
	# F7: der Senden-Druck bleibt stumm — der AUSGANG klingt (_on_senden).
	_send_button = SquishButton.new()
	_send_button.name = "SendenButton"
	_send_button.theme_type_variation = &"PrimaryButton"
	_send_button.text = I18nService.t("mail.compose.senden", {"porto": PORTO})
	_send_button.pressed.connect(_on_senden)
	aktionen.add_child(_send_button)


func _on_compose_zurueck() -> void:
	AudioDirector.try_play(self, "ui_back")
	_zeige_inbox()


func _zeige_compose() -> void:
	_inbox_box.visible = false
	_compose_box.visible = true
	_fuelle_freunde()
	_fuelle_fotos()
	_fuelle_geschenke()
	_on_text_changed()
	_aktualisiere_status()
	_relayout()


func _fuelle_freunde() -> void:
	_freund_wahl.clear()
	for freund: Dictionary in _freunde():
		_freund_wahl.add_item(
			"%s · %s" % [str(freund.get("name", "?")), str(freund.get("goobyName", "Gooby"))]
		)
		_freund_wahl.set_item_metadata(
			_freund_wahl.item_count - 1, str(freund.get("friendCode", ""))
		)
	if _freund_wahl.item_count == 0:
		_freund_wahl.add_item(I18nService.t("mail.compose.kein_freund"))
		_freund_wahl.set_item_metadata(0, "")
		_freund_wahl.disabled = true
	else:
		_freund_wahl.disabled = false
	_freund_wahl.select(0)


func _fuelle_fotos() -> void:
	_foto_wahl.clear()
	_foto_wahl.add_item(I18nService.t("mail.compose.kein_foto"))
	_foto_wahl.set_item_metadata(0, "")
	if gs == null or not gs.has_method("state"):
		return
	for foto: Variant in GalerieLogic.fotos_von(gs.state()):
		if not (foto is Dictionary):
			continue
		var pfad := str((foto as Dictionary).get("pfad", ""))
		var beschriftung := (
			"%s · %s"
			% [
				GalerieLogic.datum(int((foto as Dictionary).get("at", 0))),
				GalerieLogic.ort_name(str((foto as Dictionary).get("ort", ""))),
			]
		)
		_foto_wahl.add_item(beschriftung)
		_foto_wahl.set_item_metadata(_foto_wahl.item_count - 1, pfad)
	_foto_wahl.select(0)


func _fuelle_geschenke() -> void:
	_geschenk_wahl.clear()
	_geschenk_wahl.add_item(I18nService.t("mail.compose.kein_geschenk"))
	_geschenk_wahl.set_item_metadata(0, {})
	if gs == null or not gs.has_method("state"):
		return
	var state: Dictionary = gs.state()
	for eintrag: Dictionary in FoodCatalog.inventory_entries(state):
		_fuege_geschenk_hinzu("food", str(eintrag["id"]), int(eintrag["count"]))
	var inv: Variant = state.get("inventory")
	var items: Variant = (inv as Dictionary).get("items") if inv is Dictionary else null
	if items is Dictionary:
		for id: Variant in items as Dictionary:
			var anzahl := int((items as Dictionary).get(id, 0))
			if anzahl > 0:
				_fuege_geschenk_hinzu("items", str(id), anzahl)
	_geschenk_wahl.select(0)


func _fuege_geschenk_hinzu(typ: String, id: String, anzahl: int) -> void:
	var item := {"typ": typ, "id": id, "menge": GESCHENK_MENGE}
	_geschenk_wahl.add_item("%s (×%d)" % [item_name(item), anzahl])
	_geschenk_wahl.set_item_metadata(_geschenk_wahl.item_count - 1, item)


func _on_text_changed() -> void:
	if _text_edit.text.length() > NetMail.TEXT_MAX:
		_text_edit.text = _text_edit.text.substr(0, NetMail.TEXT_MAX)
		_text_edit.set_caret_column(_text_edit.get_line(_text_edit.get_caret_line()).length())
	_zeichen_label.text = I18nService.t(
		"mail.compose.zeichen", {"n": _text_edit.text.length(), "max": NetMail.TEXT_MAX}
	)


## Senden — transaktional: Porto + Geschenk werden VOR dem Request entnommen;
## bei endgültigem Fehlschlag wird beides zurückgebucht. QUEUED (offline)
## zählt als „unterwegs“ — die Outbox stellt zu, sobald Netz da ist.
## F7 (Outcome schlägt Press): Erfolg/Queued → ui_confirm + Haptics.success,
## jeder Fehlerausgang → ui_error + Haptics.warn; der Druck selbst ist stumm.
func _on_senden() -> void:
	if mail_service == null or gs == null:
		return
	var code := _gewaehlter_freund_code()
	if code.is_empty():
		_melde_sende_fehler(I18nService.t("mail.compose.kein_freund"))
		return
	var text := _text_edit.text.substr(0, NetMail.TEXT_MAX)
	var foto := _gewaehltes_foto()
	var item := _gewaehltes_geschenk()
	if text.strip_edges().is_empty() and foto.is_empty() and item.is_empty():
		_melde_sende_fehler(I18nService.t("mail.err.bad_mail"))
		return

	var box := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			box["ok"] = MailSheet.nimm_geschenk_und_porto(state, item, PORTO)
	)
	if not bool(box["ok"]):
		_melde_sende_fehler(_entnahme_fehler_text(item))
		return

	_send_button.disabled = true
	var res: Dictionary = await mail_service.send_mail(code, text, foto, item)
	if not is_instance_valid(self):
		return
	_send_button.disabled = false
	if bool(res.get("ok", false)):
		AudioDirector.try_play(self, "ui_confirm")
		Haptics.success(self)
		toast_requested.emit(
			I18nService.t("mail.toast.gesendet", {"name": _gewaehlter_freund_name()})
		)
	elif bool(res.get("queued", false)):
		# Offline-first: der Brief IST angenommen (Outbox) — Erfolgsmoment.
		AudioDirector.try_play(self, "ui_confirm")
		Haptics.success(self)
		toast_requested.emit(I18nService.t("mail.toast.queued"))
	else:
		# Endgültiger Fehlschlag → Porto + Geschenk zurück (Transaktion).
		gs.update(func(state: Dictionary) -> void: MailSheet.gib_zurueck(state, item, PORTO))
		_melde_sende_fehler(I18nService.t(str(res.get("message_key", "mail.err.generic"))))
		return
	_text_edit.text = ""
	_on_text_changed()
	_zeige_inbox()


## Fehler-Ausgang des Sende-Flows: EIN Klang + Warn-Haptik + Toast.
func _melde_sende_fehler(text: String) -> void:
	AudioDirector.try_play(self, "ui_error")
	Haptics.warn(self)
	toast_requested.emit(text)


func _entnahme_fehler_text(item: Dictionary) -> String:
	if not item.is_empty() and gs != null and gs.has_method("state"):
		if _vorrat(gs.state(), item) < maxi(1, int(item.get("menge", GESCHENK_MENGE))):
			return I18nService.t("mail.toast.kein_item")
	return I18nService.t("mail.toast.kein_porto", {"porto": PORTO})


func _gewaehlter_freund_code() -> String:
	var idx := _freund_wahl.selected
	if idx < 0:
		return ""
	return str(_freund_wahl.get_item_metadata(idx))


func _gewaehlter_freund_name() -> String:
	var idx := _freund_wahl.selected
	return _freund_wahl.get_item_text(idx) if idx >= 0 else "?"


func _gewaehltes_foto() -> String:
	var idx := _foto_wahl.selected
	if idx < 0:
		return ""
	return str(_foto_wahl.get_item_metadata(idx))


func _gewaehltes_geschenk() -> Dictionary:
	var idx := _geschenk_wahl.selected
	if idx < 0:
		return {}
	var meta: Variant = _geschenk_wahl.get_item_metadata(idx)
	return meta if meta is Dictionary else {}


# ---- Gemeinsames ----


func _freunde() -> Array:
	if _net == null:
		return []
	var friends_service: Variant = _net.get("friends")
	if friends_service == null:
		return []
	var liste: Variant = friends_service.get("friends")
	return liste if liste is Array else []


func _absender_name(mail: Dictionary) -> String:
	var name := str(mail.get("fromName", ""))
	return name if not name.is_empty() else str(mail.get("from", "?"))


func _aktualisiere_status() -> void:
	if mail_service == null:
		_status_label.text = ""
		return
	if mail_service.is_online():
		var wartend := mail_service.outbox_count()
		_status_label.text = (
			I18nService.t("mail.schalter.outbox", {"n": wartend}) if wartend > 0 else ""
		)
		return
	var teile := PackedStringArray([I18nService.t("mail.schalter.offline")])
	if mail_service.outbox_count() > 0:
		teile.append(I18nService.t("mail.schalter.outbox", {"n": mail_service.outbox_count()}))
	_status_label.text = " · ".join(teile)


## W18/B7: Dim-Tap schließt NUR das oberste Panel (Backdrop-Dismiss-Policy
## des Modal-Systems G7-P53) — liegt ein weiteres Modal über dem Sheet,
## gehört der Tap diesem.
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and PanelStack.is_top(self):
		_schliesse_angefragt()


## W18/B7: der EINE Zurück-Pfad aller Modals (PanelStack.close_top via
## SceneRouter.handle_back_request) — respektiert den Compose-Guard: mit
## Entwurf erscheint erst die Nachfrage-Karte statt Datenverlust.
func close() -> void:
	_schliesse_angefragt()


## G3/P07 Compose-Guard: ein angefangener Brief geht beim Daneben-Tippen
## nicht mehr verloren — im Compose-Zustand mit Text erscheint erst eine
## Nachfrage-Karte (Muster: LoeschDialog der Galerie).
func _schliesse_angefragt() -> void:
	var entwurf := (
		_compose_box != null
		and _compose_box.visible
		and _text_edit != null
		and not _text_edit.text.strip_edges().is_empty()
	)
	if entwurf:
		_zeige_verwerfen_dialog()
		return
	_schliesse()


func _schliesse() -> void:
	# Eigenbau-Overlay → Schließen klingt selbst (§3-Grammatik).
	AudioDirector.try_play(self, "ui_close")
	# W18/B7: sofort vom Panel-Stack abmelden (nicht erst beim queue_free-
	# Frame-Ende) — das darunterliegende Panel ist SOFORT wieder das oberste.
	PanelStack.remove(self)
	closed.emit()
	queue_free()


func _zeige_verwerfen_dialog() -> void:
	if _verwerfen_dialog != null and is_instance_valid(_verwerfen_dialog):
		return
	var f := float(_metrics.get("f", 1.0))
	_verwerfen_dialog = PanelContainer.new()
	_verwerfen_dialog.name = "VerwerfenDialog"
	_verwerfen_dialog.theme_type_variation = &"AcCard"
	_verwerfen_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_verwerfen_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_verwerfen_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_verwerfen_dialog.add_child(box)
	var frage := Label.new()
	frage.text = I18nService.t("mail.compose.verwerfen_frage")
	frage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frage.custom_minimum_size = Vector2(320.0 * f, 0.0)
	box.add_child(frage)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	box.add_child(zeile)
	var weiter := SquishButton.new()
	weiter.name = "WeiterschreibenButton"
	weiter.theme_type_variation = &"PrimaryButton"
	weiter.text = I18nService.t("mail.compose.weiterschreiben")
	weiter.pressed.connect(_on_weiterschreiben)
	zeile.add_child(weiter)
	var verwerfen := SquishButton.new()
	verwerfen.name = "VerwerfenButton"
	verwerfen.theme_type_variation = &"GhostButton"
	verwerfen.text = I18nService.t("mail.loeschen")
	verwerfen.pressed.connect(_on_entwurf_verwerfen)
	zeile.add_child(verwerfen)
	add_child(_verwerfen_dialog)
	if not _metrics.is_empty():
		ScreenShell.touch_target(weiter, _metrics)
		ScreenShell.touch_target(verwerfen, _metrics)
		ScreenShell.scale_fonts(_verwerfen_dialog, f)


func _on_weiterschreiben() -> void:
	AudioDirector.try_play(self, "ui_back")
	if _verwerfen_dialog != null and is_instance_valid(_verwerfen_dialog):
		_verwerfen_dialog.queue_free()
	_verwerfen_dialog = null


## Bewusstes Wegwerfen des Entwurfs — destruktive Aktion → Warn-Haptik (§3).
func _on_entwurf_verwerfen() -> void:
	Haptics.warn(self)
	_schliesse()
