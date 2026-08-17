class_name PhoneFriendsApp
extends VBoxContainer
## Freunde-App im IGohbie (W17/G5 P34, P18-Request): ECHTES Telefon-Layout
## über die PhoneShell-Helfer (`richte_app_box_ein`/`app_karte`/`app_label`/
## `app_scroll_liste`) statt des eingebetteten Vollbild-Screens — eigener
## Freundes-Code zum Teilen (Kopieren-Knopf), Freund hinzufügen (Code ODER
## Name), offene Anfragen (annehmen/ablehnen) und die Freundesliste mit
## Presence + Münzen als App-Karten in Gerätebreite. Der frühere Vollbild-
## `FriendsScreen` wurde entfernt (W22/Tech: nie produktiv geroutet) — der
## Vollbild-Sozialweg ist `SocialScreen`;
## Optik-Bausteine (Presence-Icon/-Text, Status-Chip, Leerzustand) kommen
## weiter aus `FriendListUi`. Offline-first: ohne Netz-Client degradiert die
## App freundlich (Code „—“, Senden gesperrt, Hinweis-Zeile) statt zu fehlen.
## Sounds nach W16-Grammatik: Outcome schlägt Press (Netz-Ausgang klingt).

## Höhe der Freundesliste in Design-px (×f skaliert, PhoneShell-Deckel).
const LISTE_HOEHE := 300.0
## Fallback-Anzeige, solange kein Freundes-Code bekannt ist.
const KEIN_CODE := "—"

## Tests/Screenshots: NetClient-Instanz injizieren statt /root/Net.
var net_override: NetClient = null

var _net: NetClient
var _status_chip: Button
var _offline_hinweis: Label
var _code_wert: Label
var _kopieren_btn: Button
var _eingabe: LineEdit
var _senden_btn: Button
var _feedback: Label
var _anfragen_titel: Label
var _anfragen_box: VBoxContainer
var _liste: VBoxContainer


func _ready() -> void:
	# W16/G4 P18: Breite ans REALE Gerät koppeln statt an die 420er-City-
	# Bausteine (Breiten-Kollision, G1 ui-post §4).
	PhoneShell.richte_app_box_ein(self)
	_net = net_override
	if _net == null:
		var candidate := get_node_or_null("/root/Net")
		if candidate is NetClient:
			_net = candidate
	_baue_status()
	_baue_code_karte()
	_baue_hinzufuegen_karte()
	_baue_listen()
	if _net != null:
		_net.status_changed.connect(_on_status_changed)
		if _net.friends != null:
			_net.friends.friends_changed.connect(_render_freunde)
			_net.friends.requests_changed.connect(_render_anfragen)
			_net.friends.friend_code_changed.connect(_on_code_changed)
	_render_alles()


func _hat_service() -> bool:
	return _net != null and _net.friends != null


## --------------------------------------------------------------- Aufbau


func _baue_status() -> void:
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	add_child(zeile)
	# Anzeige-Chip (nicht klickbar) — style_status_chip setzt MOUSE_FILTER_IGNORE.
	_status_chip = Button.new()
	_status_chip.name = "StatusChip"
	zeile.add_child(_status_chip)
	_offline_hinweis = PhoneShell.app_label(
		self, I18nService.t("net.friends.offline_hint"), "CaptionLabel"
	)


func _baue_code_karte() -> void:
	var karte := PhoneShell.app_karte(self)
	PhoneShell.app_label(karte, I18nService.t("net.friends.my_code"), "CaptionLabel")
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	karte.add_child(zeile)
	_code_wert = Label.new()
	_code_wert.name = "CodeWert"
	_code_wert.theme_type_variation = "TitleLabel"
	# Der Code ist der HELD der Karte (Muster des alten Freunde-Screens):
	# 800er in Teal,
	# Größe kommt von der TitleLabel-Variation (Typo-Skala, W21).
	_code_wert.add_theme_font_override("font", ThemeService.font(800))
	_code_wert.add_theme_color_override("font_color", AcTokens.TEAL_DARK)
	_code_wert.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_code_wert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(_code_wert)
	_kopieren_btn = SquishButton.new()
	_kopieren_btn.name = "KopierenButton"
	_kopieren_btn.theme_type_variation = "GhostButton"
	_kopieren_btn.text = I18nService.t("net.friends.copy")
	_kopieren_btn.focus_mode = Control.FOCUS_NONE
	# Kopieren gelingt sofort (Knopf ist ohne Code disabled) → Press klingt.
	_kopieren_btn.pressed.connect(_on_kopieren)
	ScreenShell.touch_target(_kopieren_btn, ScreenShell.metrics(get_viewport()))
	zeile.add_child(_kopieren_btn)


func _baue_hinzufuegen_karte() -> void:
	var karte := PhoneShell.app_karte(self)
	PhoneShell.app_label(karte, I18nService.t("net.friends.add_title"), "HeadlineLabel")
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	karte.add_child(zeile)
	var m := ScreenShell.metrics(get_viewport())
	_eingabe = LineEdit.new()
	_eingabe.name = "CodeEingabe"
	_eingabe.placeholder_text = I18nService.t("net.friends.add_placeholder")
	_eingabe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eingabe.text_submitted.connect(_on_eingabe_submitted)
	ScreenShell.touch_target(_eingabe, m)
	zeile.add_child(_eingabe)
	_senden_btn = SquishButton.new()
	_senden_btn.name = "AnfrageSenden"
	_senden_btn.theme_type_variation = "PrimaryButton"
	_senden_btn.text = I18nService.t("net.friends.add_button")
	_senden_btn.focus_mode = Control.FOCUS_NONE
	# W16 F13 (Outcome schlägt Press): der Netz-AUSGANG klingt in _on_senden.
	_senden_btn.pressed.connect(_on_senden)
	ScreenShell.touch_target(_senden_btn, m)
	zeile.add_child(_senden_btn)
	_feedback = PhoneShell.app_label(karte, "", "CaptionLabel")
	_feedback.visible = false


func _baue_listen() -> void:
	_anfragen_titel = PhoneShell.app_label(
		self, I18nService.t("net.friends.requests_title"), "HeadlineLabel"
	)
	_anfragen_box = VBoxContainer.new()
	_anfragen_box.name = "AnfragenBox"
	_anfragen_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anfragen_box.add_theme_constant_override("separation", 8)
	add_child(_anfragen_box)
	PhoneShell.app_label(self, I18nService.t("net.friends.list_title"), "HeadlineLabel")
	_liste = PhoneShell.app_scroll_liste(self, LISTE_HOEHE)


## --------------------------------------------------------------- Render


func _render_alles() -> void:
	_on_status_changed(_net.status if _net != null else NetClient.Status.OFFLINE)
	_render_anfragen(_net.friends.requests if _hat_service() else [])
	_render_freunde(_net.friends.friends if _hat_service() else [])


func _render_code() -> void:
	var code := _net.friend_code if _net != null else ""
	_code_wert.text = code if not code.is_empty() else KEIN_CODE
	_kopieren_btn.disabled = code.is_empty()


func _render_anfragen(requests: Array) -> void:
	for kind in _anfragen_box.get_children():
		_anfragen_box.remove_child(kind)
		kind.queue_free()
	_anfragen_titel.visible = not requests.is_empty()
	_anfragen_box.visible = _anfragen_titel.visible
	for row: Variant in requests:
		if row is Dictionary:
			_baue_anfrage_karte(row)
	PhoneShell.app_fonts_skalieren(self)


func _baue_anfrage_karte(row: Dictionary) -> void:
	var karte := PhoneShell.app_karte(_anfragen_box)
	PhoneShell.app_label(
		karte,
		I18nService.t(
			"net.friends.request_from",
			{"name": str(row.get("name", "?")), "gooby": str(row.get("goobyName", "Gooby"))}
		)
	)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	karte.add_child(zeile)
	var m := ScreenShell.metrics(get_viewport())
	var from_code := str(row.get("from", ""))
	var annehmen := SquishButton.new()
	annehmen.name = "Annehmen"
	annehmen.theme_type_variation = "BtnTeal"
	annehmen.text = I18nService.t("net.friends.accept")
	annehmen.focus_mode = Control.FOCUS_NONE
	annehmen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Netz-Call: der Ausgang klingt (_on_annehmen), der Druck bleibt stumm.
	annehmen.pressed.connect(_on_annehmen.bind(from_code))
	ScreenShell.touch_target(annehmen, m)
	zeile.add_child(annehmen)
	var ablehnen := SquishButton.new()
	ablehnen.name = "Ablehnen"
	ablehnen.theme_type_variation = "GhostButton"
	ablehnen.text = I18nService.t("net.friends.decline")
	ablehnen.focus_mode = Control.FOCUS_NONE
	ablehnen.pressed.connect(_on_ablehnen.bind(from_code))
	ScreenShell.touch_target(ablehnen, m)
	zeile.add_child(ablehnen)


func _render_freunde(friends: Array) -> void:
	for kind in _liste.get_children():
		_liste.remove_child(kind)
		kind.queue_free()
	if friends.is_empty():
		var f: float = ScreenShell.metrics(get_viewport())["f"]
		_liste.add_child(
			FriendListUi.build_empty_state("net.friends.empty_art", "net.friends.empty", f)
		)
		PhoneShell.app_fonts_skalieren(self)
		return
	for row: Variant in friends:
		if row is Dictionary:
			_baue_freund_karte(row)
	PhoneShell.app_fonts_skalieren(self)


func _baue_freund_karte(row: Dictionary) -> void:
	var karte := PhoneShell.app_karte(_liste)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	karte.add_child(zeile)
	var f: float = ScreenShell.metrics(get_viewport())["f"]
	var icon := FriendListUi.presence_icon(row)
	icon.custom_minimum_size = Vector2(20.0, 20.0) * f
	zeile.add_child(icon)
	var online: bool = row.get("online", false) == true
	var namen := VBoxContainer.new()
	namen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zeile.add_child(namen)
	var name_label := Label.new()
	name_label.theme_type_variation = "HeadlineLabel"
	name_label.text = ("%s · %s" % [str(row.get("name", "?")), str(row.get("goobyName", "Gooby"))])
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	namen.add_child(name_label)
	var status_label := Label.new()
	status_label.theme_type_variation = "CaptionLabel"
	status_label.text = FriendListUi.presence_text(row)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not online:
		status_label.add_theme_color_override("font_color", FriendListUi.COLOR_OFFLINE)
	namen.add_child(status_label)
	var coins := Label.new()
	coins.theme_type_variation = "HeadlineLabel"
	coins.text = I18nService.t("net.friends.coins", {"coins": int(row.get("coins", 0))})
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeile.add_child(coins)


## -------------------------------------------------------------- Actions


func _on_status_changed(status: int) -> void:
	var online := status == NetClient.Status.ONLINE
	_offline_hinweis.visible = not online
	_senden_btn.disabled = not online
	FriendListUi.style_status_chip(_status_chip, status)
	_render_code()
	PhoneShell.app_fonts_skalieren(self)


func _on_code_changed(_code: String) -> void:
	_render_code()


func _on_kopieren() -> void:
	var code := _net.friend_code if _net != null else ""
	if code.is_empty():
		return
	AudioDirector.try_play(self, "ui_click")
	DisplayServer.clipboard_set(code)
	_kopieren_btn.text = I18nService.t("net.friends.copied")
	# Methoden-Callable statt Lambda (REST5, B2): schließt das Handy vor dem
	# Timeout, trennt Godot die Verbindung automatisch.
	get_tree().create_timer(1.4).timeout.connect(_reset_kopieren_text)


func _reset_kopieren_text() -> void:
	_kopieren_btn.text = I18nService.t("net.friends.copy")


func _on_eingabe_submitted(_text: String) -> void:
	_on_senden()


func _on_senden() -> void:
	var wert := _eingabe.text.strip_edges()
	if wert.is_empty():
		return
	if not _hat_service() or not _net.is_online():
		AudioDirector.try_play(self, "ui_error")
		_zeige_feedback(NetErrorText.for_code("OFFLINE", "net.friends.add_error"), false)
		return
	_eingabe.editable = false
	_senden_btn.disabled = true
	var res: Dictionary = await _net.friends.add_friend(wert)
	if not is_instance_valid(self):
		return
	_eingabe.editable = true
	_senden_btn.disabled = not _net.is_online()
	if bool(res.get("ok", false)):
		AudioDirector.try_play(self, "ui_confirm")
		_eingabe.text = ""
		_zeige_feedback(I18nService.t("net.friends.add_sent"), true)
	else:
		AudioDirector.try_play(self, "ui_error")
		_zeige_feedback(
			NetErrorText.for_code(str(res.get("code", "?")), "net.friends.add_error"), false
		)


func _on_annehmen(from_code: String) -> void:
	if not _hat_service():
		return
	var res: Dictionary = await _net.friends.accept(from_code)
	if not is_instance_valid(self):
		return
	AudioDirector.try_play(self, "ui_confirm" if bool(res.get("ok", false)) else "ui_error")


func _on_ablehnen(from_code: String) -> void:
	if not _hat_service():
		return
	var res: Dictionary = await _net.friends.decline(from_code)
	if not is_instance_valid(self):
		return
	AudioDirector.try_play(self, "ui_back" if bool(res.get("ok", false)) else "ui_error")


func _zeige_feedback(text: String, ok: bool) -> void:
	_feedback.text = text
	_feedback.visible = true
	_feedback.add_theme_color_override(
		"font_color", Color(0.24, 0.6, 0.35) if ok else Color(0.75, 0.35, 0.3)
	)
