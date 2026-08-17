class_name GoobymanSheet
extends VBoxContainer
## GOOBYMAN-Laden-UI (W13C GOOBYMAN, Doc H §6.4): Logo-Karte (prozedural,
## AC-Karte mit Glyph — kein Bild-Asset), Status der aktuellen Zahnbürste,
## dann das Sortiment aus goobyman_sortiment.json (GoobymanKatalog.waren,
## remote-überschreibbar). Kategorien kaufen unterschiedlich:
## zahnbuerste/einmalig → inventory.items (Schlafmaske nur EINMAL),
## pflaster → Sofort-Wirkung mit Cap 1/Tag (Tag injizierbar via
## tag_override — Tests frieren ihn ein). Ab 5 Artikeln in EINEM Besuch
## feuert `umhang_gag` (der Ort spielt die Superhelden-Einlage).

signal gekauft(ware_id: String)
signal umhang_gag

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object
var waren: Array = []
## Erste-Male-Karte zeigen (setzt der Ort beim ersten Besuch).
var erstes_mal := false
## Tests frieren den Tag ein ("" = gs.clock.local_day()).
var tag_override := ""
## Artikel-Zähler dieses Besuchs (Umhang-Gag ab 5, genau einmal).
var im_besuch_gekauft := 0

var _gag_gezeigt := false


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		remove_child(kind)
		kind.queue_free()
	_baue_logo_karte()
	CitySheetBausteine.coins_zeile(self, _coins())
	CitySheetBausteine.label(self, _buerste_status_text(), "CaptionLabel")
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE_KURZ)
	_baue_abschnitt(
		liste,
		I18nService.t("goobyman.laden.abschnitt_zahnbuersten"),
		GoobymanKatalog.nach_kategorie(waren, GoobymanKatalog.KATEGORIE_ZAHNBUERSTE)
	)
	var pflege: Array = []
	pflege.append_array(GoobymanKatalog.nach_kategorie(waren, GoobymanKatalog.KATEGORIE_PFLASTER))
	pflege.append_array(GoobymanKatalog.nach_kategorie(waren, GoobymanKatalog.KATEGORIE_EINMALIG))
	_baue_abschnitt(liste, I18nService.t("goobyman.laden.abschnitt_pflege"), pflege)


## Kauf-Einstieg für alle Kategorien (auch von Tests direkt aufrufbar).
func kaufe(ware: Dictionary) -> bool:
	if gs == null or not kann_kaufen(ware):
		return false
	var ok := false
	match str(ware.get("kategorie", "")):
		GoobymanKatalog.KATEGORIE_PFLASTER:
			ok = _kaufe_pflaster(ware)
		_:
			ok = _kaufe_inventar(ware)
	if not ok:
		return false
	im_besuch_gekauft += 1
	gekauft.emit(str(ware.get("id", "")))
	if not _gag_gezeigt and GoobymanKatalog.umhang_gag_faellig(im_besuch_gekauft):
		_gag_gezeigt = true
		umhang_gag.emit()
	aktualisiere()
	return true


func kann_kaufen(ware: Dictionary) -> bool:
	if gs == null or int(ware.get("preis", 0)) > _coins():
		return false
	match str(ware.get("kategorie", "")):
		GoobymanKatalog.KATEGORIE_PFLASTER:
			return GoobymanKatalog.pflaster_frei(gs.state(), _tag())
		GoobymanKatalog.KATEGORIE_EINMALIG:
			return not _einmalig_gekauft(ware)
		_:
			return true


## ---------------------------------------------------------------- Aufbau


## Prozedurales Logo: AC-Karte mit großem Glyph + Claim (Doc H §6.4 —
## bewusst OHNE Bild-Asset; ein generiertes Emblem bleibt Orchestrator-Kür).
func _baue_logo_karte() -> void:
	var karte := CitySheetBausteine.karte(self)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 10)
	karte.add_child(kopf)
	var glyph := Label.new()
	glyph.text = "🦸🪥"
	glyph.theme_type_variation = "HeadlineLabel"
	kopf.add_child(glyph)
	var titel := Label.new()
	titel.text = I18nService.t("city.ort.goobyman")
	titel.theme_type_variation = "HeadlineLabel"
	kopf.add_child(titel)
	CitySheetBausteine.label(karte, I18nService.t("goobyman.laden.claim"), "CaptionLabel")
	if erstes_mal:
		CitySheetBausteine.label(karte, I18nService.t("goobyman.laden.erstes_mal"), "CaptionLabel")


func _baue_abschnitt(liste: Control, titel: String, eintraege: Array) -> void:
	if eintraege.is_empty():
		return
	CitySheetBausteine.label(liste, titel, "HeadlineLabel")
	for eintrag: Dictionary in eintraege:
		_baue_zeile(liste, eintrag)


func _baue_zeile(liste: Control, ware: Dictionary) -> void:
	var titel := "%s %s" % [str(ware.get("glyph", "")), str(ware.get("name_de", ware.get("id")))]
	var zusatz := str(ware.get("hinweis_de", ""))
	if str(ware.get("kategorie", "")) == GoobymanKatalog.KATEGORIE_ZAHNBUERSTE:
		var punkte := int(ware.get("haltbarkeit", ZahnbuersteState.HALTBARKEIT_FALLBACK))
		zusatz = I18nService.t("goobyman.laden.haltbarkeit").format({"n": punkte})
	var knopf_text := CitySheetBausteine.preis_text(int(ware.get("preis", 0)))
	var aktiv := kann_kaufen(ware)
	CitySheetBausteine.kauf_zeile(
		liste, titel.strip_edges(), zusatz, knopf_text, aktiv, func() -> void: kaufe(ware)
	)
	if not aktiv and _hinweis_fuer(ware) != "":
		CitySheetBausteine.label(liste, _hinweis_fuer(ware), "CaptionLabel")


## Warum ist eine Zeile gerade gesperrt? ("" = nur Münzen fehlen.)
func _hinweis_fuer(ware: Dictionary) -> String:
	match str(ware.get("kategorie", "")):
		GoobymanKatalog.KATEGORIE_PFLASTER:
			if not GoobymanKatalog.pflaster_frei(gs.state(), _tag()):
				return I18nService.t("goobyman.laden.pflaster_heute")
		GoobymanKatalog.KATEGORIE_EINMALIG:
			if _einmalig_gekauft(ware):
				return I18nService.t("city.laden.im_regal")
	return ""


func _buerste_status_text() -> String:
	if gs == null:
		return ""
	var slice := ZahnbuersteState.slice_of(gs.state())
	var typ := str(slice["typ"])
	var name_key := "goobyman.buerste.%s" % typ
	var name := I18nService.t(name_key) if I18nService.has_key(name_key) else typ
	var zustand := ZahnbuersteState.aktueller_zustand(gs, waren)
	return I18nService.t("goobyman.laden.buerste_status").format(
		{"name": name, "zustand": I18nService.t("goobyman.buerste.zustand_%s" % zustand)}
	)


## ---------------------------------------------------------------- Käufe


func _kaufe_inventar(ware: Dictionary) -> bool:
	var inventar := str(ware.get("inventar", ware.get("id", "")))
	if inventar.is_empty():
		return false
	var ok := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			if not Economy.spend(state["economy"], int(ware.get("preis", 0)), "goobyman"):
				return
			var items: Dictionary = state["inventory"]["items"]
			items[inventar] = int(items.get(inventar, 0)) + 1
			ok["ok"] = true
	)
	return ok["ok"]


func _kaufe_pflaster(ware: Dictionary) -> bool:
	var ok := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			if not GoobymanKatalog.pflaster_frei(state, _tag()):
				return
			if not Economy.spend(state["economy"], int(ware.get("preis", 0)), "goobyman"):
				return
			ok["ok"] = true
	)
	if not ok["ok"]:
		return false
	return GoobymanKatalog.pflaster_anwenden(gs, ware, _tag())


func _einmalig_gekauft(ware: Dictionary) -> bool:
	var inventar := str(ware.get("inventar", ware.get("id", "")))
	return int(gs.get_value("inventory.items.%s" % inventar, 0)) > 0


func _tag() -> String:
	if not tag_override.is_empty():
		return tag_override
	if gs != null and "clock" in gs:
		return str(gs.clock.local_day())
	return ""


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))
