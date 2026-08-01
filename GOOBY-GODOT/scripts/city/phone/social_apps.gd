class_name PhoneSocialApps
extends RefCounted
## Andockstelle für die BESTEHENDEN Social-Screens im IGohbie (W3c VISIT):
## „Freunde“ hängt den echten `SocialScreen` in die Handy-Fläche, „GoobyPal“
## eine Freundesliste, aus der das echte `GoobyPalSheet` aufgeht.
## Beide degradieren offline zu einer freundlichen Karte statt zu Fehlern —
## der Netz-Client ist optional (Doc C §3.7).
##
## W16/G4 P18: Breiten/Höhen koppeln an die reale Gerätebreite
## (`PhoneShell`-Bausteine statt der 420er-City-Bausteine) und skalieren ×f.

const SOCIAL_SCENE := "res://scripts/ui/social/social_screen.tscn"


## Freunde-Screen als Handy-Inhalt (null = Szene fehlt).
static func freunde(host: Node) -> Control:
	if not ResourceLoader.exists(SOCIAL_SCENE):
		return _hinweis_karte("phone.freunde.fehlt")
	var szene: PackedScene = load(SOCIAL_SCENE)
	var screen: Control = szene.instantiate()
	screen.custom_minimum_size = Vector2(0.0, 380.0 * _faktor())
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if "auto_navigate" in screen:
		screen.auto_navigate = host != null
	return screen


## Freundesliste für GoobyPal — jede Zeile öffnet das echte Sheet.
static func goobypal(gs: Object, bei_wahl: Callable) -> Control:
	var box := VBoxContainer.new()
	PhoneShell.richte_app_box_ein(box)
	var freunde_liste := freunde_zeilen()
	var karte := PhoneShell.app_karte(box)
	PhoneShell.app_label(karte, I18nService.t("phone.goobypal.titel"), "HeadlineLabel")
	PhoneShell.app_label(karte, I18nService.t("phone.goobypal.text"), "CaptionLabel")
	if gs != null:
		PhoneShell.app_label(
			karte,
			I18nService.t("city.laden.coins").format(
				{"coins": int(gs.get_value("economy.coins", 0))}
			),
			"CaptionLabel"
		)
	if freunde_liste.is_empty():
		PhoneShell.app_label(box, I18nService.t("phone.goobypal.offline"), "CaptionLabel")
		return box
	var liste := PhoneShell.app_scroll_liste(box, 260.0)
	for freund: Dictionary in freunde_liste:
		# Senden-Zeile, kein Kauf → ui_click statt des ui_buy-Defaults (W16 F1).
		var zeile := CitySheetBausteine.kauf_zeile(
			liste,
			"%s · %s" % [str(freund.get("name", "?")), str(freund.get("goobyName", "Gooby"))],
			"",
			I18nService.t("phone.goobypal.senden"),
			true,
			func() -> void: bei_wahl.call(freund),
			"ui_click"
		)
		_kuerze_zeile(zeile)
	return box


## Bekannte Freunde des Netz-Clients ([] = offline/kein Client).
static func freunde_zeilen() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return out
	var net := (loop as SceneTree).root.get_node_or_null("/root/Net")
	if net == null or net.friends == null:
		return out
	for row: Dictionary in net.friends.friends:
		out.append(row)
	return out


## Das echte GoobyPal-Sheet für einen Freund (null ohne Pal-Service).
static func pal_sheet(host: Node, freund: Dictionary) -> Control:
	var services := SocialServices.get_or_create(host)
	if services == null or services.pal == null:
		return _hinweis_karte("phone.goobypal.offline")
	var sheet := GoobyPalSheet.new()
	sheet.setup(services.pal, freund)
	sheet.custom_minimum_size = Vector2(0.0, 360.0 * _faktor())
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return sheet


static func _hinweis_karte(text_key: String) -> Control:
	var box := VBoxContainer.new()
	PhoneShell.richte_app_box_ein(box)
	var karte := PhoneShell.app_karte(box)
	PhoneShell.app_label(karte, I18nService.t(text_key), "CaptionLabel")
	return box


## Aktueller UiScale-Faktor des Haupt-Viewports (1,0 ohne Baum).
static func _faktor() -> float:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return 1.0
	return UiScale.for_viewport((loop as SceneTree).root)


## kauf_zeile-Labels (Fixbreite 240 aus den City-Bausteinen) auf die reale
## Gerätebreite einkürzen, damit der Senden-Knopf rechts sichtbar bleibt.
static func _kuerze_zeile(zeile: HBoxContainer) -> void:
	var ziel := maxf(PhoneShell.text_breite() - 140.0 * _faktor(), 96.0)
	for texte in zeile.get_children():
		if not (texte is VBoxContainer):
			continue
		for label in (texte as VBoxContainer).get_children():
			if label is Label and (label as Label).custom_minimum_size.x > ziel:
				(label as Label).custom_minimum_size = Vector2(ziel, 0.0)
				(label as Label).size = Vector2(ziel, 0.0)
