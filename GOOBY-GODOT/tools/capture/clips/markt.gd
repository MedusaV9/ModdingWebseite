extends "res://tools/capture/clip_driver.gd"
## Clip: Wochenmarkt-Eigenstand (W15/MARKT) — der eigene Stand ist bestückt
## (Ware liegt sichtbar auf dem Tisch, Stand-Gooby mit Schürze dahinter,
## Kunden-Goobys davor), dann öffnet „Mein Stand“ mit dem Verkaufs-Replay:
## Plings + Münz-Floats im Sheet, draußen hüpfen die Kunden zu jedem
## Verkauf mit, am Ende feiert der Stand-Gooby die Abrechnungs-Karte.
## Regie-Trick: bestückt wird mit dem Zeitstempel des LETZTEN Samstags 7:00
## — der Markttag ist damit „fertig“ und das deterministische Replay steht
## sofort bereit (MarktSim, echte Spiellogik, nichts gemockt).

## Waren + Preisfaktoren fürs Schaufenster (alle mit Essen-GLB → sichtbar).
const WAREN := {"carrot": 6, "tomato": 4, "watermelon": 3}
const FAKTOREN := {"carrot": 1.15, "tomato": 1.0, "watermelon": 0.9}

var ort: Node3D


func _setup() -> void:
	duration = 17.0
	_stand_vorbereiten()
	var packed: PackedScene = load("res://scenes/city/orte/wochenmarkt.tscn")
	ort = packed.instantiate()
	add_child(ort)
	# Kino-Shot: der Händler-Dialog bleibt aus — der Stand ist der Star.
	schedule(0.2, func() -> void: ort.dialog.visible = false)
	schedule(3.2, func() -> void: ort.oeffne_laden())
	schedule(4.2, _eigenstand_tab)
	schedule(5.0, _replay_starten)


## Lager füllen und den Stand für den LETZTEN Samstag bestücken — Status
## ist damit „fertig“, Deko/Kunden stehen ab dem ersten Frame.
func _stand_vorbereiten() -> void:
	var gs: Object = get_node_or_null("/root/GameState")
	if gs == null:
		return
	gs.update(
		func(state: Dictionary) -> void:
			for ware: String in WAREN:
				MarktWaren.zurueck(state, ware, int(WAREN[ware]))
	)
	var samstag := _letzter_samstag_frueh()
	for ware: String in WAREN:
		MarktStand.bestuecke(gs, samstag, ware, int(WAREN[ware]), float(FAKTOREN[ware]))


## Unix-Zeit des letzten Samstags um 7:00 (vor Marktbeginn 8–14 Uhr).
func _letzter_samstag_frueh() -> int:
	var jetzt := int(Time.get_unix_time_from_system())
	var datum := Time.get_datetime_dict_from_unix_time(jetzt)
	var zurueck := posmod(int(datum["weekday"]) - MarktStand.SAMSTAG, 7)
	if zurueck == 0:
		zurueck = 7
	var tag := jetzt - zurueck * 86400
	var tag_datum := Time.get_datetime_dict_from_unix_time(tag)
	var sekunden_seit_mitternacht := (
		int(tag_datum["hour"]) * 3600 + int(tag_datum["minute"]) * 60 + int(tag_datum["second"])
	)
	return tag - sekunden_seit_mitternacht + 7 * 3600


## „Mein Stand“-Tab im Sheet drücken (Knopf per Beschriftung finden —
## die Tabs entstehen erst in oeffne_laden()).
func _eigenstand_tab() -> void:
	var ziel := I18nService.t("markt.tab.eigenstand")
	for knopf in ort._sheet.find_children("*", "Button", true, false):
		if knopf is Button and (knopf as Button).text == ziel:
			(knopf as Button).pressed.emit()
			return


## Verkaufs-Replay starten (Zuschauen-Pfad; endet selbst in der Abrechnung).
func _replay_starten() -> void:
	var sheet := _finde_stand_sheet(ort._sheet)
	if sheet != null:
		sheet._starte_replay()


func _finde_stand_sheet(node: Node) -> MarktStandSheet:
	if node is MarktStandSheet:
		return node
	for kind in node.get_children():
		var fund := _finde_stand_sheet(kind)
		if fund != null:
			return fund
	return null
