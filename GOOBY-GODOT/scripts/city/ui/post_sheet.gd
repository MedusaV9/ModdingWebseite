class_name PostSheet
extends VBoxContainer
## Post-Schalter-UI (Doc E §2.3): Tagespaket-Schalter plus Postkarten-Archiv.
## FERTIG-1: der alte Paket-/Brief-„Versand an Freunde kommt bald“-Hook
## (Multiplayer ohne Netzcode) ist GESTRICHEN — stattdessen liegt hier pro
## Lokaltag ein echtes Tagespaket (PostLogic, 15–40 Münzen, seeded) bereit.
## Ein künftiger Netz-Versand bekommt wieder einen eigenen Schalter.

signal schalter_gewaehlt(schalter: String)

var gs: Object


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.label(self, I18nService.t("city.post.titel"), "HeadlineLabel")
	_baue_paket_schalter()
	_baue_archiv()


## Tagespaket: einmal pro Lokaltag abholbar; danach ist der Knopf ehrlich
## deaktiviert („Morgen wieder“) statt einen „bald“-Toast zu zeigen.
func _baue_paket_schalter() -> void:
	var karte := CitySheetBausteine.karte(self)
	CitySheetBausteine.label(karte, I18nService.t("city.post.paket"), "HeadlineLabel")
	CitySheetBausteine.label(karte, I18nService.t("city.post.paket_text"), "CaptionLabel")
	var btn := Button.new()
	btn.name = "PaketHolen"
	btn.theme_type_variation = "AccentButton"
	var offen := gs != null and PostLogic.verfuegbar(gs.state(), _local_day())
	if offen:
		btn.text = I18nService.t("city.post.paket_holen")
		btn.pressed.connect(_on_paket_holen)
	else:
		btn.text = I18nService.t("city.post.paket_geholt")
		btn.disabled = true
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


func _on_paket_holen() -> void:
	if gs == null:
		return
	var tag := _local_day()
	var box := {"res": {}}
	gs.update(func(state: Dictionary) -> void: box["res"] = PostLogic.hole_paket(state, tag))
	var res: Dictionary = box["res"]
	if not bool(res.get("ok", false)):
		aktualisiere()
		return
	gs.notify_slice_changed("city")
	schalter_gewaehlt.emit("paket")
	_zeige_toast(I18nService.t("city.post.paket_toast", {"n": int(res.get("coins", 0))}))
	aktualisiere()


func _local_day() -> String:
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)
