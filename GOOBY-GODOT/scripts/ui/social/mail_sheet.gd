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

signal toast_requested(text: String)
signal closed
## Der Ungelesen-Stand hat sich geändert (Badge am Post-Schalter).
signal unread_changed(unread: int)

const Economy := preload("res://scripts/logic/economy.gd")

## Porto-Gag: jeder Brief kostet 5 Münzen Porto (Frau Zettel stempelt ja auch).
const PORTO := 5
const GESCHENK_MENGE := 1
const THUMB_SIZE := Vector2(96, 96)

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


func setup(net: Node, game_state: Object) -> void:
	_net = net
	gs = game_state
	mail_service = NetMail.attach(net)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(460, 520)
	add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	card.add_child(rows)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mail.titel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
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

	if mail_service != null:
		mail_service.mail_new.connect(_on_mail_new)
		mail_service.unread_changed.connect(func(n: int) -> void: unread_changed.emit(n))
	_zeige_inbox()


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
	var schreiben := Button.new()
	schreiben.name = "SchreibenButton"
	schreiben.theme_type_variation = &"PrimaryButton"
	schreiben.text = I18nService.t("mail.schreiben")
	schreiben.pressed.connect(_zeige_compose)
	kopf.add_child(schreiben)
	var neu_laden := Button.new()
	neu_laden.theme_type_variation = &"GhostButton"
	neu_laden.text = I18nService.t("mail.aktualisieren")
	neu_laden.pressed.connect(func() -> void: _lade_inbox())
	kopf.add_child(neu_laden)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	_inbox_box.add_child(scroll)
	_liste_slot = VBoxContainer.new()
	_liste_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste_slot.add_theme_constant_override("separation", 8)
	scroll.add_child(_liste_slot)


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
		var gelesen := Button.new()
		gelesen.theme_type_variation = &"GhostButton"
		gelesen.text = I18nService.t("mail.gelesen_knopf")
		gelesen.pressed.connect(_on_gelesen.bind(str(mail.get("id", "")), gelesen))
		aktionen.add_child(gelesen)
	var loeschen := Button.new()
	loeschen.theme_type_variation = &"GhostButton"
	loeschen.text = I18nService.t("mail.loeschen")
	loeschen.pressed.connect(_on_loeschen.bind(str(mail.get("id", ""))))
	aktionen.add_child(loeschen)
	return karte


func _baue_foto_thumbnail(photo_id: String) -> Control:
	var rect := TextureRect.new()
	rect.custom_minimum_size = THUMB_SIZE
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
	var knopf := Button.new()
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
## Inventar-Gutschrift (Doppel-Gutschrift ausgeschlossen).
func _on_annehmen(mail_id: String, item: Dictionary, knopf: Button) -> void:
	if mail_service == null or gs == null:
		return
	knopf.disabled = true
	var res: Dictionary = await mail_service.claim_gift(mail_id)
	if not is_instance_valid(self):
		return
	if not bool(res.get("ok", false)):
		toast_requested.emit(I18nService.t(str(res.get("message_key", "mail.err.generic"))))
		knopf.disabled = str(res.get("code", "")) == "ALREADY_CLAIMED"
		return
	var geschenk: Dictionary = res.get("item", item)
	gs.update(func(state: Dictionary) -> void: MailSheet.schreibe_gut(state, geschenk))
	knopf.text = I18nService.t("mail.angenommen")
	toast_requested.emit(
		I18nService.t(
			"mail.toast.geschenk_da",
			{"name": item_name(geschenk), "n": maxi(1, int(geschenk.get("menge", GESCHENK_MENGE)))}
		)
	)


func _on_gelesen(mail_id: String, knopf: Button) -> void:
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
	var zurueck := Button.new()
	zurueck.theme_type_variation = &"GhostButton"
	zurueck.text = I18nService.t("mail.zurueck")
	zurueck.pressed.connect(_zeige_inbox)
	aktionen.add_child(zurueck)
	_send_button = Button.new()
	_send_button.name = "SendenButton"
	_send_button.theme_type_variation = &"PrimaryButton"
	_send_button.text = I18nService.t("mail.compose.senden", {"porto": PORTO})
	_send_button.pressed.connect(_on_senden)
	aktionen.add_child(_send_button)


func _zeige_compose() -> void:
	_inbox_box.visible = false
	_compose_box.visible = true
	_fuelle_freunde()
	_fuelle_fotos()
	_fuelle_geschenke()
	_on_text_changed()
	_aktualisiere_status()


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
func _on_senden() -> void:
	if mail_service == null or gs == null:
		return
	var code := _gewaehlter_freund_code()
	if code.is_empty():
		toast_requested.emit(I18nService.t("mail.compose.kein_freund"))
		return
	var text := _text_edit.text.substr(0, NetMail.TEXT_MAX)
	var foto := _gewaehltes_foto()
	var item := _gewaehltes_geschenk()
	if text.strip_edges().is_empty() and foto.is_empty() and item.is_empty():
		toast_requested.emit(I18nService.t("mail.err.bad_mail"))
		return

	var box := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			box["ok"] = MailSheet.nimm_geschenk_und_porto(state, item, PORTO)
	)
	if not bool(box["ok"]):
		toast_requested.emit(_entnahme_fehler_text(item))
		return

	_send_button.disabled = true
	var res: Dictionary = await mail_service.send_mail(code, text, foto, item)
	if not is_instance_valid(self):
		return
	_send_button.disabled = false
	if bool(res.get("ok", false)):
		toast_requested.emit(
			I18nService.t("mail.toast.gesendet", {"name": _gewaehlter_freund_name()})
		)
	elif bool(res.get("queued", false)):
		toast_requested.emit(I18nService.t("mail.toast.queued"))
	else:
		# Endgültiger Fehlschlag → Porto + Geschenk zurück (Transaktion).
		gs.update(func(state: Dictionary) -> void: MailSheet.gib_zurueck(state, item, PORTO))
		toast_requested.emit(I18nService.t(str(res.get("message_key", "mail.err.generic"))))
		return
	_text_edit.text = ""
	_on_text_changed()
	_zeige_inbox()


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


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		closed.emit()
		queue_free()
