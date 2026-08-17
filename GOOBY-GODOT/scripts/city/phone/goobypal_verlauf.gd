class_name GoobyPalVerlauf
extends RefCounted
## GoobyPal-Verlaufs-Liste (P3 AP-3): rendert die PAL_HISTORY-Einträge des
## Servers ({dir,peer,amount,at}, max 30) als knuffige Liste — Datum lokal
## formatiert, Richtung (geschickt/bekommen) mit Icon + Farbe, Betrag und
## Freundesname. Die Formatierung ist PURE (Zeit + UTC-Offset werden
## injiziert, Tests!); der leere Zustand nutzt die bestehende
## Empty-State-Komponente (FriendListUi.build_empty_state).

const ICON_DIR := "res://assets/ui/icons"
const ICON_GESCHICKT := "arrow_right"
const ICON_BEKOMMEN := "gift"
## Farben wie in FriendListUi: warmes Braun raus, Blattgrün rein.
const FARBE_GESCHICKT := Color(0.62, 0.45, 0.34)
const FARBE_BEKOMMEN := Color(0.35, 0.75, 0.45)
const LISTEN_HOEHE := 190.0
const SEC_PRO_TAG := 86400


## Fertige Verlaufs-Sektion: Überschrift + Scroll-Liste (neueste zuerst)
## ODER der knuffige Leerzustand. `namen`: friendCode → Anzeigename.
## W16/G4 P18: Listenhöhe/Icons skalieren ×f (Gerät wächst mit dem Canvas).
static func build_liste(
	entries: Array, namen: Dictionary, now_unix: int, utc_offset_min: int
) -> Control:
	var f := _faktor()
	var box := VBoxContainer.new()
	box.name = "PalVerlauf"
	box.add_theme_constant_override("separation", 6)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("phone.goobypal.verlauf_titel")
	box.add_child(titel)
	if entries.is_empty():
		box.add_child(
			FriendListUi.build_empty_state(
				"phone.goobypal.verlauf_leer", "phone.goobypal.verlauf_leer"
			)
		)
		return box
	var scroll := ScrollContainer.new()
	scroll.name = "VerlaufScroll"
	scroll.custom_minimum_size = Vector2(0.0, LISTEN_HOEHE * f)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "VerlaufZeilen"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	# Neueste zuerst — der Server hängt chronologisch hinten an.
	for i in range(entries.size() - 1, -1, -1):
		if entries[i] is Dictionary:
			rows.add_child(_zeile(zeile_modell(entries[i], namen, now_unix, utc_offset_min), f))
	return box


## Aktueller UiScale-Faktor des Haupt-Viewports (1,0 ohne Baum).
static func _faktor() -> float:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return 1.0
	return UiScale.for_viewport((loop as SceneTree).root)


## Einen PAL_HISTORY-Eintrag in Anzeige-Felder übersetzen (PURE).
## Unbekannte peer-Codes bleiben als Code sichtbar (Fallback).
static func zeile_modell(
	entry: Dictionary, namen: Dictionary, now_unix: int, utc_offset_min: int
) -> Dictionary:
	var raus := str(entry.get("dir", "")) == "out"
	var peer := str(entry.get("peer", ""))
	var betrag := int(entry.get("amount", 0))
	var richtung_key := (
		"phone.goobypal.verlauf_geschickt" if raus else "phone.goobypal.verlauf_bekommen"
	)
	return {
		"raus": raus,
		"name": str(namen.get(peer, peer)),
		"richtung": I18nService.t(richtung_key),
		"betrag": ("−%d ᴳ" if raus else "+%d ᴳ") % betrag,
		"datum": format_datum(int(entry.get("at", 0)), now_unix, utc_offset_min),
		"icon": ICON_GESCHICKT if raus else ICON_BEKOMMEN,
		"farbe": FARBE_GESCHICKT if raus else FARBE_BEKOMMEN,
	}


## Datum LOKAL formatiert (PURE — `now_unix`/`utc_offset_min` injiziert):
## heute → „heute · HH:MM“, gestern → „gestern · HH:MM“, sonst Datums-Key.
static func format_datum(at_ms: int, now_unix: int, utc_offset_min: int) -> String:
	var lokal := Time.get_datetime_dict_from_unix_time(int(at_ms / 1000.0) + utc_offset_min * 60)
	var heute := Time.get_datetime_dict_from_unix_time(now_unix + utc_offset_min * 60)
	var zeit := "%02d:%02d" % [int(lokal["hour"]), int(lokal["minute"])]
	if _gleicher_tag(lokal, heute):
		return I18nService.t("phone.goobypal.verlauf_heute", {"zeit": zeit})
	var gestern := Time.get_datetime_dict_from_unix_time(
		now_unix + utc_offset_min * 60 - SEC_PRO_TAG
	)
	if _gleicher_tag(lokal, gestern):
		return I18nService.t("phone.goobypal.verlauf_gestern", {"zeit": zeit})
	return (
		I18nService
		. t(
			"phone.goobypal.verlauf_datum",
			{
				"tag": "%02d" % int(lokal["day"]),
				"monat": "%02d" % int(lokal["month"]),
				"jahr": str(int(lokal["year"])),
			}
		)
	)


## friendCode → Anzeigename aus einer Freundesliste (PURE).
static func namen_von(freunde: Array) -> Dictionary:
	var out := {}
	for row: Variant in freunde:
		if not (row is Dictionary):
			continue
		var code := str((row as Dictionary).get("friendCode", ""))
		if code.is_empty():
			continue
		out[code] = str((row as Dictionary).get("name", code))
	return out


## Boundary: Namen aus dem laufenden Netz-Client holen ([] ohne /root/Net).
static func namen_aus_baum(node: Node) -> Dictionary:
	if node == null or not node.is_inside_tree():
		return {}
	var net := node.get_node_or_null("/root/Net")
	if net == null or not ("friends" in net) or net.friends == null:
		return {}
	return namen_von(net.friends.friends)


## Boundary: lokaler UTC-Offset in Minuten (Godot: „bias“).
static func lokaler_offset_min() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))


static func _gleicher_tag(a: Dictionary, b: Dictionary) -> bool:
	return a["year"] == b["year"] and a["month"] == b["month"] and a["day"] == b["day"]


static func _zeile(modell: Dictionary, f := 1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.texture = load("%s/%s.svg" % [ICON_DIR, str(modell["icon"])])
	icon.custom_minimum_size = Vector2(18, 18) * f
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = modell["farbe"]
	row.add_child(icon)
	var mitte := VBoxContainer.new()
	mitte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mitte)
	var name_label := Label.new()
	name_label.name = "ZeileName"
	name_label.text = "%s · %s" % [str(modell["name"]), str(modell["richtung"])]
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mitte.add_child(name_label)
	var datum_label := Label.new()
	datum_label.theme_type_variation = &"CaptionLabel"
	datum_label.text = str(modell["datum"])
	mitte.add_child(datum_label)
	var betrag_label := Label.new()
	betrag_label.name = "ZeileBetrag"
	betrag_label.text = str(modell["betrag"])
	betrag_label.add_theme_color_override("font_color", modell["farbe"])
	betrag_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(betrag_label)
	return row
