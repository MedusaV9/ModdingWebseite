class_name BaumarktSheet
extends VBoxContainer
## Baumarkt-UI (Doc D §5 / Doc E §2.3): zwei Abteilungen — Material
## (stapelbar) und Baupläne (einmalig). Gekauftes landet in inventory.items;
## das CRAFTING selbst gehört der Werkstatt (Haus-Agent), die die Baupläne
## über `BaumarktKatalog.freigeschaltete_rezepte(gs)` liest.

signal gekauft(ware_id: String)

const Economy := preload("res://scripts/logic/economy.gd")

var gs: Object


func _ready() -> void:
	CitySheetBausteine.richte_box_ein(self)
	aktualisiere()


func aktualisiere() -> void:
	for kind in get_children():
		kind.queue_free()
	CitySheetBausteine.coins_zeile(self, _coins())
	var liste := CitySheetBausteine.scroll_liste(self, CitySheetBausteine.LISTE_HOEHE)
	CitySheetBausteine.label(liste, I18nService.t("city.baumarkt.material"), "HeadlineLabel")
	for eintrag: Dictionary in BaumarktKatalog.materialien():
		_baue_zeile(liste, eintrag, _vorrat_text(eintrag))
	CitySheetBausteine.label(liste, I18nService.t("city.baumarkt.bauplaene"), "HeadlineLabel")
	CitySheetBausteine.label(liste, I18nService.t("city.baumarkt.werkstatt"), "CaptionLabel")
	for eintrag: Dictionary in BaumarktKatalog.bauplaene():
		_baue_zeile(liste, eintrag, str(eintrag.get("material_de", "")))


func _baue_zeile(liste: Control, eintrag: Dictionary, zusatz: String) -> void:
	var schon := BaumarktKatalog.schon_gekauft(gs, eintrag)
	var knopf := (
		I18nService.t("city.baumarkt.gekauft")
		if schon
		else CitySheetBausteine.preis_text(int(eintrag.get("preis", 0)))
	)
	CitySheetBausteine.kauf_zeile(
		liste,
		str(eintrag.get("name_de", "?")),
		zusatz,
		knopf,
		BaumarktKatalog.kann_kaufen(gs, eintrag),
		func() -> void: _kaufe(eintrag)
	)


func _vorrat_text(eintrag: Dictionary) -> String:
	var key := str(eintrag.get("inventar", ""))
	var vorrat := 0
	if gs != null:
		vorrat = int(gs.get_value("inventory.items.%s" % key, 0))
	var spruch := str(eintrag.get("spruch_de", ""))
	if vorrat <= 0:
		return spruch
	return "%s · %s" % [spruch, I18nService.t("city.baumarkt.vorrat").format({"n": vorrat})]


func _kaufe(eintrag: Dictionary) -> void:
	if not BaumarktKatalog.kann_kaufen(gs, eintrag):
		return
	var preis := int(eintrag.get("preis", 0))
	var key := str(eintrag.get("inventar", eintrag.get("id", "")))
	var menge := maxi(1, int(eintrag.get("menge", 1)))
	# GDScript-Lambdas capturen lokale Werte PER KOPIE — ein bool käme nie
	# zurück (Signal/Refresh liefen nie). Dictionary teilt die Referenz.
	var zahlung := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			zahlung["ok"] = Economy.spend(state["economy"], preis, "baumarkt")
			if bool(zahlung["ok"]):
				var items: Dictionary = state["inventory"]["items"]
				items[key] = int(items.get(key, 0)) + menge
	)
	if not bool(zahlung["ok"]):
		return
	gekauft.emit(str(eintrag.get("id", "")))
	aktualisiere()


func _coins() -> int:
	if gs == null:
		return 0
	return int(gs.get_value("economy.coins", 0))
