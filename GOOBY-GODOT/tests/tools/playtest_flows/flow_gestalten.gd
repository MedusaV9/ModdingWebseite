extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Flow „Gestalten“: Screen öffnen, Kategorie auf „Boden“ wechseln, eine
## Options-Kachel antippen (Vormerkung ODER Sofort-Anwendung), eine
## Palettenfarbe wählen (Vorschau reagiert), Kauf falls vorgemerkt,
## dann Kategorie-Liste ans Scroll-Ende: ist „Briefkasten“ sichtbar und
## tippbar (Audit-Frage) — Kategorie wechselt, Optionen erscheinen.
## Format: HOCH 1320x2868 (BxH beim Aufruf zwingend mitgeben).
## Aufruf: tools/ci/run_playtest.sh flow_gestalten 1320x2868

var _option_ziel := ""
var _farbe_ziel := ""


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_boden_und_farbe())
	liste.append_array(_schritte_briefkasten())
	return liste


func _schritte_boden_und_farbe() -> Array[Dictionary]:
	return [
		{
			"name": "gestalten_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnGestalten",
			"erwarte": {"route": "gestalten"},
			"timeout_s": 45.0,
		},
		{"name": "gestalten_ansehen", "aktion": "warte", "sekunden": 1.5},
		{"name": "muenzen_auffuellen", "aktion": "tue", "funktion": muenzen_auffuellen},
		{
			"name": "kategorie_boden",
			"aktion": "tipp_name",
			"node": "Kat_boden",
			"erwarte": {"bedingung": kategorie_ist_boden},
			"timeout_s": 10.0,
		},
		{"name": "boden_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "option_waehlen",
			"aktion": "tipp_pos",
			"pos_funktion": zweite_option_pos,
			"erwarte": {"bedingung": option_reagiert},
			"timeout_s": 10.0,
			"erwartung": "Angetippte Boden-Kachel wird vorgemerkt oder sofort angewandt",
		},
		{
			"name": "farbe_waehlen",
			"aktion": "tipp_pos",
			"pos_funktion": zweite_farbe_pos,
			"erwarte": {"bedingung": farbe_reagiert},
			"timeout_s": 10.0,
			"pflicht": false,
			"erwartung": "Angetippter Farb-Swatch wird übernommen (Vorschau tönt um)",
		},
		{"name": "vorschau_ansehen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "kauf_falls_vorgemerkt",
			"aktion": "tipp_falls_da",
			"node": "KaufButton",
			"timeout_s": 6.0,
			"pflicht": false,
		},
		{"name": "nach_kauf_ansehen", "aktion": "warte", "sekunden": 1.0},
	]


func _schritte_briefkasten() -> Array[Dictionary]:
	return [
		{"name": "kat_liste_ans_ende", "aktion": "tue", "funktion": scrolle_kategorien_ans_ende},
		{"name": "scroll_setzen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "briefkasten_sichtbar",
			"aktion": "warte_bis",
			"bedingung": briefkasten_kat_sichtbar,
			"timeout_s": 5.0,
			"erwartung": "Kategorie „Briefkasten“ ist am Scroll-Ende komplett sichtbar",
		},
		{
			"name": "briefkasten_waehlen",
			"aktion": "tipp_name",
			"node": "Kat_briefkasten",
			"erwarte": {"bedingung": kategorie_ist_briefkasten},
			"timeout_s": 10.0,
		},
		{"name": "briefkasten_optionen", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "briefkasten_kacheln_da",
			"aktion": "warte_bis",
			"bedingung": briefkasten_optionen_da,
			"timeout_s": 5.0,
			"erwartung": "Briefkasten-Optionen (standard/kugel/holz/modern) sind aufgebaut",
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 1.0},
	]


# ── Zustand ──────────────────────────────────────────────────────────────────


func _screen() -> Node:
	return aktuelle_szene()


func muenzen_auffuellen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.set_value("economy.coins", 2000)
	return true


func _kategorie_id() -> String:
	var screen := _screen()
	if screen == null:
		return ""
	var kat: Variant = screen.get("_kategorie")
	return str((kat as Dictionary).get("id", "")) if kat is Dictionary else ""


func kategorie_ist_boden() -> bool:
	return _kategorie_id() == "boden"


func kategorie_ist_briefkasten() -> bool:
	return _kategorie_id() == "briefkasten"


# ── Option + Farbe ───────────────────────────────────────────────────────────


func _kinder_mit_praefix(container: Node, praefix: String) -> Array[Control]:
	var treffer: Array[Control] = []
	if container == null:
		return treffer
	for kind in container.get_children():
		if kind is Control and str(kind.name).begins_with(praefix):
			treffer.append(kind as Control)
	return treffer


## Zweite Boden-Kachel (die erste ist meist die aktive Standard-Option).
func zweite_option_pos() -> Vector2:
	var screen := _screen()
	if screen == null:
		return Vector2(200.0, 200.0)
	var optionen := _kinder_mit_praefix(screen.get("_optionen") as Node, "Option_")
	if optionen.size() < 2:
		return Vector2(200.0, 200.0)
	var kachel := optionen[1]
	_option_ziel = str(kachel.name).trim_prefix("Option_")
	return kachel.get_global_rect().get_center()


func option_reagiert() -> bool:
	var screen := _screen()
	if screen == null or _option_ziel == "":
		return false
	if str(screen.get("_pending_id")) == _option_ziel:
		return true
	return str(screen.call("_aktuelle_id")) == _option_ziel


func zweite_farbe_pos() -> Vector2:
	var screen := _screen()
	if screen == null:
		return Vector2(200.0, 200.0)
	var swatches := _kinder_mit_praefix(screen.get("_farben") as Node, "Farbe_")
	if swatches.is_empty():
		return Vector2(200.0, 200.0)
	var wahl := swatches[1] if swatches.size() > 1 else swatches[0]
	_farbe_ziel = str(wahl.name).trim_prefix("Farbe_")
	return wahl.get_global_rect().get_center()


func farbe_reagiert() -> bool:
	var screen := _screen()
	if screen == null or _farbe_ziel == "":
		return false
	if str(screen.get("_pending_farbe")) == _farbe_ziel:
		return true
	return str(screen.call("_aktuelle_farbe")) == _farbe_ziel


# ── Briefkasten am Scroll-Ende ───────────────────────────────────────────────


func _kat_scroll() -> ScrollContainer:
	var screen := _screen()
	if screen == null:
		return null
	var liste: Variant = screen.get("_kategorie_liste")
	if not (liste is Node):
		return null
	var eltern: Node = (liste as Node).get_parent()
	while eltern != null and not (eltern is ScrollContainer):
		eltern = eltern.get_parent()
	return eltern as ScrollContainer


func scrolle_kategorien_ans_ende() -> bool:
	var scroll := _kat_scroll()
	if scroll == null:
		return false
	scroll.scroll_vertical = 999999
	return true


func briefkasten_kat_sichtbar() -> bool:
	var knopf := harness.root.find_child("Kat_briefkasten", true, false)
	var scroll := _kat_scroll()
	if not (knopf is Control) or scroll == null:
		return false
	var control := knopf as Control
	if not control.is_visible_in_tree():
		return false
	return scroll.get_global_rect().encloses(control.get_global_rect().grow(-1.0))


func briefkasten_optionen_da() -> bool:
	var screen := _screen()
	if screen == null:
		return false
	var kacheln := _kinder_mit_praefix(screen.get("_optionen") as Node, "Option_")
	return kacheln.size() >= 4
