class_name PostSheet
extends VBoxContainer
## Post-Schalter-UI (Doc E §2.3, Doc C §3.7): Paket- und Brief-Schalter plus
## Postkarten-Archiv. Der Multiplayer-Versand ist hier bewusst nur ein HOOK
## („bald“-Hinweis, kein Netzcode): `PostSheet.mp_hook` ist die eine Stelle,
## an der der Netz-Agent später den echten Versand einhängt — ist sie nicht
## gesetzt, bleibt der Knopf freundlich deaktiviert (Offline-Degradation
## statt Fehler).

signal schalter_gewaehlt(schalter: String)

## Optionaler Netz-Hook: `func(schalter: String, gs: Object) -> bool`.
## true = der Versand wurde übernommen (dann zeigt das Sheet keinen
## „bald“-Hinweis mehr).
static var mp_hook := Callable()

var gs: Object


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.label(self, I18nService.t("city.post.titel"), "HeadlineLabel")
	_baue_schalter("paket", "city.post.paket", "city.post.paket_text")
	_baue_schalter("brief", "city.post.brief", "city.post.brief_text")
	_baue_archiv()


func _baue_schalter(id: String, titel_key: String, text_key: String) -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t(titel_key), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t(text_key), "CaptionLabel")
	var btn := Button.new()
	btn.theme_type_variation = "AccentButton"
	btn.text = I18nService.t("city.post.abgeben")
	btn.pressed.connect(func() -> void: _on_schalter(id))
	karte.add_child(btn)


func _baue_archiv() -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("city.post.archiv"), "HeadlineLabel")
	var anzahl := 0
	if gs != null:
		anzahl = int(gs.get_value("vacation.postcards", 0))
	if anzahl <= 0:
		CitySheetBausteine.label(karte, I18nService.t("city.post.archiv_leer"), "CaptionLabel")
		return
	CitySheetBausteine.label(
		karte, I18nService.t("city.post.archiv_zahl").format({"n": anzahl}), "CaptionLabel"
	)
	# REST-4 (P1 „Bald“-Fix, EVAL Rang 15): der Archiv-Klick landet jetzt im
	# echten Postkarten-Archiv statt in einem Platzhalter.
	var btn := Button.new()
	btn.name = "ArchivAnsehen"
	btn.theme_type_variation = "AccentButton"
	btn.text = I18nService.t("postkarten.ansehen")
	btn.pressed.connect(_on_archiv_ansehen)
	karte.add_child(btn)


func _on_archiv_ansehen() -> void:
	PostkartenScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(PostkartenScreen.ROUTE, {})


func _on_schalter(id: String) -> void:
	schalter_gewaehlt.emit(id)
	if mp_hook.is_valid() and bool(mp_hook.call(id, gs)):
		return
	_zeige_toast(I18nService.t("city.post.bald"))


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
