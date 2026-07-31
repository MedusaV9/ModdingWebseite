class_name InstantGoobyApp
extends VBoxContainer
## InstantGooby (W13C, Doc C §3.9) — Foto-Feed im IGohbie ÜBERM Mail-Backend:
## Karten mit großem Foto (lazy per REST), Autor, Caption, Lokalzeit und
## Möhren-Like-Knopf („Möhre da lassen“ 🥕 — der Server hält 1 Like pro
## Freund pro Post). Refresh-Knopf statt Pull-to-Refresh; „Posten“-Flow:
## Foto aus der Galerie (galerie_logic wird NUR gelesen) → Caption ≤ 120 →
## an ALLE Freunde (Fan-out macht der Server, 1× Tages-Quota). OFFLINE-FIRST:
## post_instant legt ohne Netz einen Outbox-Eintrag an (NetMail-Muster);
## das Ungelesen-Badge am App-Icon baut `unread_badge()` für die PhoneShell.

const APP_ID := "instant"
const FOTO_HOEHE := 220.0
const LISTE_HOEHE := 340.0
const BADGE_FARBE := Color("#E4572E")

var gs: Object

var _service: NetMail
var _feed_box: VBoxContainer
var _compose_box: VBoxContainer
var _liste: VBoxContainer
var _status: Label
var _foto_wahl: OptionButton
var _caption_edit: LineEdit
var _zeichen: Label
var _senden_btn: Button

## ------------------------------------------------ pure Helfer (testbar)


## Fußzeilen-Hinweis, wenn der Ringpuffer voll ist ("" solange Platz ist).
static func cap_hinweis(total: int, cap: int) -> String:
	if total < cap:
		return ""
	return I18nService.t("instant.cap_hinweis", {"n": cap})


## Darf der Betrachter diese Möhre da lassen? (nie beim eigenen Post,
## nie doppelt — der Server hält das ohnehin idempotent.)
static func like_erlaubt(post: Dictionary) -> bool:
	return not bool(post.get("mine", false)) and not bool(post.get("liked", false))


## Beschriftung des Möhren-Knopfs (Zähler inklusive).
static func moehren_text(likes: int) -> String:
	return "🥕 %d" % maxi(0, likes)


## Badge-Text fürs App-Icon ("" = kein Badge).
static func badge_text(unseen: int) -> String:
	if unseen <= 0:
		return ""
	return "9+" if unseen > 9 else str(unseen)


## Ungesehene Freundes-Posts laut NetMail-Service (0 ohne Netz-Client).
static func unseen_count() -> int:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return 0
	var net := (loop as SceneTree).root.get_node_or_null("/root/Net")
	if net == null:
		return 0
	var service := NetMail.attach(net)
	return service.instant_unseen if service != null else 0


## Ungelesen-Badge fürs App-Grid (null = kein Badge nötig) — die PhoneShell
## hängt es additiv an die Kachel dieser App (EINE Aufrufstelle).
static func unread_badge(app_id: String) -> Control:
	if app_id != APP_ID:
		return null
	var text := badge_text(unseen_count())
	if text.is_empty():
		return null
	var badge := Label.new()
	badge.name = "InstantBadge"
	badge.text = text
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color.WHITE)
	var stil := StyleBoxFlat.new()
	stil.bg_color = BADGE_FARBE
	stil.set_corner_radius_all(9)
	stil.content_margin_left = 6.0
	stil.content_margin_right = 6.0
	stil.content_margin_top = 1.0
	stil.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("normal", stil)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = -6.0
	badge.offset_right = 8.0
	return badge


## --------------------------------------------------------------- Aufbau


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	_service = _hole_service()
	_feed_box = VBoxContainer.new()
	_feed_box.add_theme_constant_override("separation", 10)
	add_child(_feed_box)
	_compose_box = VBoxContainer.new()
	_compose_box.add_theme_constant_override("separation", 8)
	add_child(_compose_box)
	_baue_feed()
	_baue_compose()
	if _service != null:
		_service.instant_new.connect(_on_instant_new)
		_service.instant_liked.connect(_on_instant_liked)
	_zeige_feed()


func _hole_service() -> NetMail:
	var net := get_node_or_null("/root/Net")
	return NetMail.attach(net) if net != null else null


func _baue_feed() -> void:
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 8)
	_feed_box.add_child(kopf)
	var posten := Button.new()
	posten.name = "PostenButton"
	posten.theme_type_variation = "PrimaryButton"
	posten.text = I18nService.t("instant.posten")
	posten.pressed.connect(_zeige_compose)
	kopf.add_child(posten)
	var neu_laden := Button.new()
	neu_laden.name = "NeuLadenButton"
	neu_laden.theme_type_variation = "GhostButton"
	neu_laden.text = I18nService.t("instant.aktualisieren")
	neu_laden.pressed.connect(func() -> void: _lade_feed())
	kopf.add_child(neu_laden)
	_status = Label.new()
	_status.theme_type_variation = "CaptionLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(CitySheetBausteine.TEXT_BREITE, 0.0)
	_status.size = Vector2(CitySheetBausteine.TEXT_BREITE, 0.0)
	_feed_box.add_child(_status)
	_liste = CitySheetBausteine.scroll_liste(_feed_box, LISTE_HOEHE)


func _zeige_feed() -> void:
	_compose_box.visible = false
	_feed_box.visible = true
	_lade_feed()


## Feed vom Server holen; danach FEED_ACK (Badge aus). Offline degradiert
## die App zu einer freundlichen Karte plus Outbox-Stand.
func _lade_feed() -> void:
	_aktualisiere_status()
	if _service == null or not _service.is_online():
		_render_feed([], 0, NetMail.FEED_CAP)
		return
	var res: Dictionary = await _service.fetch_feed()
	if not is_instance_valid(self):
		return
	if not bool(res.get("ok", false)):
		_render_feed([], 0, NetMail.FEED_CAP)
		return
	var posts: Array = res.get("posts", []) if res.get("posts") is Array else []
	_render_feed(posts, int(res.get("total", 0)), int(res.get("cap", NetMail.FEED_CAP)))
	if _service.instant_unseen > 0:
		await _service.ack_feed()


func _render_feed(posts: Array, total: int, cap: int) -> void:
	for kind in _liste.get_children():
		kind.queue_free()
	if posts.is_empty():
		var leer := CitySheetBausteine.karte(_liste)
		var key := "instant.feed_leer"
		if _service == null or not _service.is_online():
			key = "instant.offline"
		CitySheetBausteine.label(leer, I18nService.t(key), "CaptionLabel")
		return
	for post: Variant in posts:
		if post is Dictionary:
			_baue_post_karte(post)
	var hinweis := cap_hinweis(total, cap)
	if not hinweis.is_empty():
		CitySheetBausteine.label(_liste, hinweis, "CaptionLabel")


func _baue_post_karte(post: Dictionary) -> void:
	var karte := CitySheetBausteine.karte(_liste)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 6)
	karte.add_child(kopf)
	var autor := Label.new()
	autor.theme_type_variation = "HeadlineLabel"
	autor.text = _autor_text(post)
	autor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(autor)
	var zeit := Label.new()
	zeit.theme_type_variation = "CaptionLabel"
	zeit.text = GalerieLogic.datum(int(post.get("at", 0)))
	kopf.add_child(zeit)

	var photo_id := str(post.get("photoId", ""))
	if not photo_id.is_empty():
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(0.0, FOTO_HOEHE)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		karte.add_child(rect)
		_lade_foto(photo_id, rect)

	var caption := str(post.get("caption", ""))
	if not caption.is_empty():
		CitySheetBausteine.label(karte, caption)

	var moehre := Button.new()
	moehre.name = "MoehrenKnopf"
	moehre.theme_type_variation = "GhostButton"
	moehre.text = moehren_text(int(post.get("likes", 0)))
	moehre.tooltip_text = I18nService.t(
		"instant.moehre_gelassen" if bool(post.get("liked", false)) else "instant.moehre"
	)
	moehre.focus_mode = Control.FOCUS_NONE
	moehre.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	moehre.disabled = not like_erlaubt(post)
	moehre.pressed.connect(_on_moehre.bind(str(post.get("id", "")), moehre))
	karte.add_child(moehre)


## Kopfzeile einer Feed-Karte: eigener Post oder „Name · Gooby“.
func _autor_text(post: Dictionary) -> String:
	if bool(post.get("mine", false)):
		return I18nService.t("instant.dein_post")
	return "%s · %s" % [str(post.get("fromName", "?")), str(post.get("fromGooby", "Gooby"))]


## Feed-Foto lazy nachladen (REST) und in die Karte hängen.
func _lade_foto(photo_id: String, rect: TextureRect) -> void:
	if _service == null:
		return
	var res: Dictionary = await _service.fetch_instant_photo(photo_id)
	if not is_instance_valid(rect):
		return
	if not bool(res.get("ok", false)):
		return
	var bytes := Marshalls.base64_to_raw(str(res.get("photo_b64", "")))
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK and image.load_jpg_from_buffer(bytes) != OK:
		return
	rect.texture = ImageTexture.create_from_image(image)


## Möhre da lassen — der Knopf sperrt sofort; bei Fehlern (außer already)
## geht er wieder auf, damit der Tipp wiederholbar bleibt.
func _on_moehre(post_id: String, knopf: Button) -> void:
	if _service == null:
		return
	knopf.disabled = true
	var res: Dictionary = await _service.like_post(post_id)
	if not is_instance_valid(knopf):
		return
	if bool(res.get("ok", false)):
		knopf.text = moehren_text(int(res.get("likes", 0)))
		knopf.tooltip_text = I18nService.t("instant.moehre_gelassen")
		return
	_zeige_toast(I18nService.t(str(res.get("message_key", "instant.err.generic"))))
	knopf.disabled = false


## ---------------------------------------------------------- Posten-Flow


func _baue_compose() -> void:
	var titel := Label.new()
	titel.theme_type_variation = "HeadlineLabel"
	titel.text = I18nService.t("instant.compose.titel")
	_compose_box.add_child(titel)

	var foto_zeile := HBoxContainer.new()
	foto_zeile.add_theme_constant_override("separation", 8)
	_compose_box.add_child(foto_zeile)
	var foto_label := Label.new()
	foto_label.theme_type_variation = "CaptionLabel"
	foto_label.text = I18nService.t("instant.compose.foto")
	foto_zeile.add_child(foto_label)
	_foto_wahl = OptionButton.new()
	_foto_wahl.name = "FotoWahl"
	_foto_wahl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foto_zeile.add_child(_foto_wahl)

	_caption_edit = LineEdit.new()
	_caption_edit.name = "CaptionEdit"
	_caption_edit.placeholder_text = I18nService.t("instant.compose.caption_hint")
	_caption_edit.max_length = NetMail.CAPTION_MAX
	_caption_edit.text_changed.connect(func(_neu: String) -> void: _on_caption_changed())
	_compose_box.add_child(_caption_edit)
	_zeichen = Label.new()
	_zeichen.theme_type_variation = "CaptionLabel"
	_zeichen.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_compose_box.add_child(_zeichen)

	var aktionen := HBoxContainer.new()
	aktionen.add_theme_constant_override("separation", 8)
	_compose_box.add_child(aktionen)
	var zurueck := Button.new()
	zurueck.theme_type_variation = "GhostButton"
	zurueck.text = I18nService.t("instant.compose.zurueck")
	zurueck.pressed.connect(_zeige_feed)
	aktionen.add_child(zurueck)
	_senden_btn = Button.new()
	_senden_btn.name = "SendenButton"
	_senden_btn.theme_type_variation = "PrimaryButton"
	_senden_btn.text = I18nService.t("instant.compose.senden")
	_senden_btn.pressed.connect(_on_posten)
	aktionen.add_child(_senden_btn)


func _zeige_compose() -> void:
	_feed_box.visible = false
	_compose_box.visible = true
	_fuelle_fotos()
	_on_caption_changed()


## Galerie-Auswahl (galerie_logic NUR lesen — Format „Datum · Ort“).
func _fuelle_fotos() -> void:
	_foto_wahl.clear()
	var fotos: Array = []
	if gs != null and gs.has_method("state"):
		fotos = GalerieLogic.fotos_von(gs.state())
	if fotos.is_empty():
		_foto_wahl.add_item(I18nService.t("instant.compose.galerie_leer"))
		_foto_wahl.set_item_metadata(0, "")
		_foto_wahl.disabled = true
		_foto_wahl.select(0)
		return
	_foto_wahl.disabled = false
	for foto: Variant in fotos:
		if not (foto is Dictionary):
			continue
		var beschriftung := (
			"%s · %s"
			% [
				GalerieLogic.datum(int((foto as Dictionary).get("at", 0))),
				GalerieLogic.ort_name(str((foto as Dictionary).get("ort", ""))),
			]
		)
		_foto_wahl.add_item(beschriftung)
		_foto_wahl.set_item_metadata(
			_foto_wahl.item_count - 1, str((foto as Dictionary).get("pfad", ""))
		)
	_foto_wahl.select(0)


func _on_caption_changed() -> void:
	_zeichen.text = I18nService.t(
		"instant.compose.zeichen", {"n": _caption_edit.text.length(), "max": NetMail.CAPTION_MAX}
	)


## Posten: Foto ist Pflicht; offline landet der Post in der Outbox
## (NetMail flusht beim nächsten Online-Gehen — clientId dedupet).
func _on_posten() -> void:
	if _service == null:
		_zeige_toast(I18nService.t("instant.err.offline"))
		return
	var foto := _gewaehltes_foto()
	if foto.is_empty():
		_zeige_toast(I18nService.t("instant.err.no_photo"))
		return
	_senden_btn.disabled = true
	var res: Dictionary = await _service.post_instant(_caption_edit.text, foto)
	if not is_instance_valid(self):
		return
	_senden_btn.disabled = false
	if bool(res.get("ok", false)):
		_zeige_toast(I18nService.t("instant.toast.gepostet", {"n": int(res.get("recipients", 0))}))
	elif bool(res.get("queued", false)):
		_zeige_toast(I18nService.t("instant.toast.queued"))
	else:
		_zeige_toast(I18nService.t(str(res.get("message_key", "instant.err.generic"))))
		return
	_caption_edit.text = ""
	_zeige_feed()


func _gewaehltes_foto() -> String:
	var idx := _foto_wahl.selected
	if idx < 0:
		return ""
	return str(_foto_wahl.get_item_metadata(idx))


## -------------------------------------------------------------- Signale


func _on_instant_new(_post: Dictionary) -> void:
	if _feed_box != null and _feed_box.visible:
		_lade_feed()


func _on_instant_liked(data: Dictionary) -> void:
	_zeige_toast(I18nService.t("instant.toast.moehre_da", {"name": str(data.get("byName", "?"))}))


func _aktualisiere_status() -> void:
	if _service == null:
		_status.text = I18nService.t("instant.offline")
		return
	var teile := PackedStringArray()
	if not _service.is_online():
		teile.append(I18nService.t("instant.offline"))
	if _service.instant_outbox_count() > 0:
		teile.append(I18nService.t("instant.outbox", {"n": _service.instant_outbox_count()}))
	_status.text = " · ".join(teile)
	_status.visible = not _status.text.is_empty()


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
