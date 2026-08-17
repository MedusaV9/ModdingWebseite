extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „IKEA-Katalog“: Shop öffnen, Kategorie-Chip wechseln (Filter
## greift), Liste blättern (Touch-Pan), eine Möbel-Zeile antippen
## (Schaufenster/Showcase zeigt das Item), Farbvariante über die
## Muster-Swatches wechseln (Vitrine tönt um) und das Schaufenster in
## Ruhe ablichten.
## Format: quer 2868x1320 (Leitformat, Default).
## Aufruf: tools/ci/run_playtest.sh flow_ikea

var _chip_ziel := ""
var _row_ziel := ""
var _variante_vorher := ""
var _variante_ziel := ""


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_katalog())
	return liste


func _schritte_katalog() -> Array[Dictionary]:
	return [
		# W20 P1 (HUD-Slimming): Möbel/IKEA ist Sekundär-Kachel — im Quer-
		# Cockpit erst das Mehr-Cluster aufklappen (gepollte Bedingung,
		# Helfer unten; wartet auch ein busy-Router-Fenster weg).
		{
			"name": "ikea_freilegen",
			"aktion": "warte_bis",
			"bedingung": ikea_freilegen,
			"timeout_s": 30.0,
		},
		{
			"name": "ikea_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnIkea",
			"erwarte": {"route": "ikea"},
			"timeout_s": 45.0,
		},
		{"name": "schaufenster_ankommen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "chip_wechseln",
			"aktion": "tipp_pos",
			"pos_funktion": zweiter_chip_pos,
			"erwarte": {"bedingung": chip_uebernommen},
			"timeout_s": 10.0,
			"erwartung": "Kategorie-Chip filtert die Liste",
		},
		{"name": "filter_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "liste_blaettern",
			"aktion": "wisch",
			"von_funktion": liste_wisch_von,
			"nach_funktion": liste_wisch_nach,
			"dauer_s": 0.5,
		},
		{"name": "blaettern_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "row_waehlen",
			"aktion": "tipp_pos",
			"pos_funktion": erste_row_pos,
			"erwarte": {"bedingung": row_uebernommen},
			"timeout_s": 10.0,
			"erwartung": "Angetippte Möbel-Zeile landet im Schaufenster",
		},
		{"name": "schaufenster_ansehen", "aktion": "warte", "sekunden": 2.0},
		{"name": "variante_merken", "aktion": "tue", "funktion": merke_variante},
		{
			"name": "variante_wechseln",
			"aktion": "tipp_pos",
			"pos_funktion": zweite_swatch_pos,
			"erwarte": {"bedingung": variante_uebernommen},
			"timeout_s": 10.0,
			"pflicht": false,
			"erwartung": "Muster-Swatch wechselt die Farbvariante in der Vitrine",
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


# ── Helfer ───────────────────────────────────────────────────────────────────


## W20 P1 Nachfix (HUD-Slimming): die IKEA-Kachel lebt im Quer-Cockpit
## eingeklappt hinter der Mehr-Kachel — gepollte warte_bis-Bedingung
## (idempotent: höchstens EIN „Mehr“-Druck pro Poll; apply_layout schaltet
## synchron sichtbar, der Recheck verhindert Doppel-Drücke).
func ikea_freilegen() -> bool:
	var kachel := harness.root.find_child("BtnIkea", true, false) as Control
	if kachel != null and kachel.is_visible_in_tree():
		return true
	var mehr := harness.root.find_child("BtnMehr", true, false) as Button
	if mehr == null or not mehr.is_visible_in_tree():
		return false
	mehr.pressed.emit()
	kachel = harness.root.find_child("BtnIkea", true, false) as Control
	return kachel != null and kachel.is_visible_in_tree()


func _screen() -> Node:
	return aktuelle_szene()


func _kinder_mit_praefix(container: Node, praefix: String) -> Array[Control]:
	var treffer: Array[Control] = []
	if container == null:
		return treffer
	for kind in container.get_children():
		if kind is Control and str(kind.name).begins_with(praefix):
			treffer.append(kind as Control)
	return treffer


## Zweiter Chip (erster ist „Alle“) — Ziel-Kategorie wird gemerkt.
func zweiter_chip_pos() -> Vector2:
	var screen := _screen()
	if screen == null:
		return Vector2(200.0, 200.0)
	var chips := _kinder_mit_praefix(screen.get("_chips") as Node, "Chip_")
	if chips.size() < 2:
		return Vector2(200.0, 200.0)
	var chip := chips[1]
	_chip_ziel = str(chip.name).trim_prefix("Chip_")
	return chip.get_global_rect().get_center()


func chip_uebernommen() -> bool:
	var screen := _screen()
	if screen == null or _chip_ziel == "":
		return false
	return str(screen.get("_kategorie")) == _chip_ziel


func _liste_node() -> Control:
	var screen := _screen()
	if screen == null:
		return null
	var liste: Variant = screen.get("_list")
	return liste if liste is Control else null


func liste_wisch_von() -> Vector2:
	var liste := _liste_node()
	if liste == null:
		return Vector2(400.0, 800.0)
	var rect := liste.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + minf(rect.size.y * 0.7, 500.0))


func liste_wisch_nach() -> Vector2:
	var liste := _liste_node()
	if liste == null:
		return Vector2(400.0, 300.0)
	var rect := liste.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + 60.0)


## Erste sichtbare Möbel-Zeile antippen — Ziel-Id wird gemerkt.
func erste_row_pos() -> Vector2:
	var screen := _screen()
	if screen == null:
		return Vector2(300.0, 400.0)
	var rows := _kinder_mit_praefix(screen.get("_list") as Node, "Row_")
	for row in rows:
		if not row.is_visible_in_tree():
			continue
		var mitte := row.get_global_rect().get_center()
		if mitte.y < 0.0 or mitte.y > harness.root.get_visible_rect().size.y:
			continue
		_row_ziel = str(row.name).trim_prefix("Row_")
		return mitte
	return Vector2(300.0, 400.0)


func row_uebernommen() -> bool:
	var screen := _screen()
	if screen == null or _row_ziel == "":
		return false
	return str(screen.get("_selected")) == _row_ziel


func merke_variante() -> bool:
	var screen := _screen()
	if screen == null:
		return false
	_variante_vorher = str(screen.get("_variant"))
	return true


func zweite_swatch_pos() -> Vector2:
	var screen := _screen()
	if screen == null:
		return Vector2(300.0, 500.0)
	var swatches := _kinder_mit_praefix(screen.get("_swatches") as Node, "Swatch_")
	for swatch in swatches:
		var id := str(swatch.name).trim_prefix("Swatch_")
		if id != _variante_vorher:
			_variante_ziel = id
			return swatch.get_global_rect().get_center()
	return Vector2(300.0, 500.0)


func variante_uebernommen() -> bool:
	var screen := _screen()
	if screen == null or _variante_ziel == "":
		return false
	return str(screen.get("_variant")) == _variante_ziel
