extends "res://tests/tools/playtest_flows/flow_basis.gd"
## Gemeinsame PT-4-Sicht-Helfer (Welle H) für die G7-P50/P52/P53/P54-
## Verifikation: HUD-Weiche (weicht das HUD offenen Blättern/dem Baumodus?),
## Blatt-Backdrop-Dim, Griff-Position fürs Runterwischen, Kachel-Label-
## Messung (User-Befund 1.8.: „IGohbi/Garder/Gestalt" abgeschnitten) und
## Sprechblasen-Lage (User-Befund „Ohh, wird das sch"). Die konkreten
## PT-4-Flows (sheets/media/garderobe/quests) erben hiervon.

## HUD-Teile, die die P50-Weiche versteckt (s. hud._baue_sichtbarkeit).
const HUD_TEILE: Array[String] = ["TopBar", "LeftColumn", "PortraitDock", "LandscapeColumn"]
## Alle zehn Aktions-Kacheln (hud.ACTIONS → "Btn" + capitalize).
const HUD_KNOEPFE: Array[String] = [
	"BtnIgohbie",
	"BtnBau",
	"BtnReise",
	"BtnArcade",
	"BtnAlbum",
	"BtnProfil",
	"BtnWardrobe",
	"BtnIkea",
	"BtnGestalten",
	"BtnQuests",
]
## Backdrop gilt als sichtbar ab dieser effektiven Deckkraft (VEIL = 0,35).
const DIM_MIN_ALPHA := 0.2

## Münzstand-Merker für vorher/nachher-Prüfungen.
var muenzen_merker := -1


## Das Haupt-HUD (Gruppe "hud", s. hud.gd _ready) — null, wenn keines lebt.
func hud() -> Control:
	return harness.get_first_node_in_group(&"hud") as Control


func hud_teil(teil_name: String) -> Control:
	var wurzel := hud()
	if wurzel == null:
		return null
	return wurzel.find_child(teil_name, true, false) as Control


## P50: Sind ALLE weichenden HUD-Teile aus dem Bild (Blatt offen/Baumodus)?
func hud_weicht() -> bool:
	var wurzel := hud()
	if wurzel == null or not wurzel.is_visible_in_tree():
		return true
	for teil_name in HUD_TEILE:
		var teil := hud_teil(teil_name)
		if teil != null and teil.is_visible_in_tree():
			return false
	return true


## P50: Ist das HUD zurück (TopBar + mindestens eine Kachel-Leiste)?
func hud_da() -> bool:
	var top := hud_teil("TopBar")
	if top == null or not top.is_visible_in_tree():
		return false
	for leiste in ["PortraitDock", "LandscapeColumn"]:
		var teil := hud_teil(leiste)
		if teil != null and teil.is_visible_in_tree():
			return true
	return false


## User-Befund 1 (1.8.): HUD-Kacheln schnitten Wörter ab („IGohbi"/…) —
## seit G8/IDEA-J2 eine ERFOLGS-Erwartung mit ZWEI Verträgen (die alte
## B4-Sonde): QUER sind die Kacheln ICON-ONLY (kein Text in der Kachel =
## strukturell nichts mehr abschneidbar; die Beschriftung liefern die
## Namensschilder der Icon-Bühne), HOCHKANT gilt der P50-Vertrag weiter
## (Font-Autoshrink OHNE Trimming — nachgemessen wie zuvor).
func hud_labels_vollstaendig() -> bool:
	var wurzel := hud()
	if wurzel == null:
		return false
	var quer: bool = int(wurzel.get("current_layout")) == HudLayoutLogic.Layout.LANDSCAPE
	var alle_ok := true
	var gesehen := 0
	for knopf_name in HUD_KNOEPFE:
		var knopf := hud_teil(knopf_name) as Button
		if knopf == null or not knopf.is_visible_in_tree():
			continue
		gesehen += 1
		var ok := (
			_kachel_iconbuehne_ok(knopf_name, knopf)
			if quer
			else _kachel_label_ok(knopf_name, knopf)
		)
		if not ok:
			alle_ok = false
	return alle_ok and gesehen > 0


## J2-Quer-Vertrag: Kachel trägt Icon statt Text — kein Ellipsis mehr möglich.
func _kachel_iconbuehne_ok(knopf_name: String, knopf: Button) -> bool:
	var kein_trim := knopf.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
	var ok := knopf.text == "" and kein_trim and knopf.icon != null
	print(
		(
			"[PT4] Kachel %s quer: Text='%s' Icon=%s Trim=%s -> %s"
			% [
				knopf_name,
				knopf.text,
				"da" if knopf.icon != null else "FEHLT",
				"aus" if kein_trim else "ELLIPSIS",
				"icon-only ok" if ok else "VERLETZT",
			]
		)
	)
	return ok


## P50-Hochkant-Vertrag: Text passt bei gesetzter Schriftgröße, Trimming aus.
func _kachel_label_ok(knopf_name: String, knopf: Button) -> bool:
	var breite := HudLabelFit.text_breite(
		knopf.get_theme_font("font"), knopf.text, knopf.get_theme_font_size("font_size")
	)
	var verfuegbar := knopf.size.x
	var stil := knopf.get_theme_stylebox("normal")
	if stil != null:
		verfuegbar -= stil.get_content_margin(SIDE_LEFT) + stil.get_content_margin(SIDE_RIGHT)
	var kein_trim := knopf.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING
	var ok := kein_trim and breite <= verfuegbar + 0.5
	print(
		(
			"[PT4] Kachel %s '%s': Text %.0f px / Platz %.0f px, Trim=%s -> %s"
			% [
				knopf_name,
				knopf.text,
				breite,
				verfuegbar,
				"aus" if kein_trim else "ELLIPSIS",
				"ok" if ok else "ABGESCHNITTEN",
			]
		)
	)
	return ok


## Oberstes offenes PanelSheet im Baum (null = keins sichtbar).
func blatt() -> Control:
	return _suche_blatt(harness.root)


## P53: Backdrop-Dim des offenen Blatts sichtbar (effektive Deckkraft)?
func blatt_dim_sichtbar() -> bool:
	var sheet := blatt()
	if sheet == null:
		print("[PT4] Kein offenes Blatt gefunden")
		return false
	var dim := sheet.find_child("Backdrop", true, false) as ColorRect
	if dim == null:
		print("[PT4] Blatt ohne Backdrop-Node")
		return false
	var alpha := dim.color.a * dim.modulate.a * dim.self_modulate.a
	print("[PT4] Blatt-Dim: sichtbar=%s Alpha=%.2f" % [str(dim.is_visible_in_tree()), alpha])
	return dim.is_visible_in_tree() and alpha > DIM_MIN_ALPHA


## Mitte der Griff-Leiste (GrabHandle) des offenen Blatts — Wisch-Start.
func blatt_griff_pos() -> Vector2:
	var sheet := blatt()
	if sheet == null:
		return harness.root.get_visible_rect().size * 0.5
	var griff := sheet.find_child("GrabHandle", true, false) as Control
	if griff == null:
		return harness.root.get_visible_rect().size * 0.5
	return griff.get_global_rect().get_center()


## Wisch-Ziel: senkrecht unterm Griff, tief genug für die Schließ-Schwelle
## (P53: 25 % der Blatthöhe bzw. 48 px × f).
func blatt_wisch_ziel() -> Vector2:
	var von := blatt_griff_pos()
	var canvas := harness.root.get_visible_rect().size
	return Vector2(von.x, minf(von.y + canvas.y * 0.55, canvas.y - 8.0))


## User-Befund 2 (1.8.): Sprechblase brach mitten im Wort („…wird das sch").
## P51-Fix nachgemessen: die AcBubble-Kapsel liegt KOMPLETT im Canvas und
## der Text bricht höchstens an Wortgrenzen (nie AUTOWRAP_ARBITRARY).
func blase_im_canvas() -> bool:
	var bubble := _suche_klasse(harness.root, "AcBubble") as Control
	if bubble == null:
		print("[PT4] Keine AcBubble sichtbar")
		return false
	var kapsel := bubble.find_child("Kapsel", true, false) as Control
	var label := bubble.find_child("BubbleText", true, false) as Label
	if kapsel == null or label == null:
		return false
	var rect := kapsel.get_global_rect()
	var canvas := Rect2(Vector2.ZERO, harness.root.get_visible_rect().size)
	var drin := canvas.grow(2.0).encloses(rect)
	var wortgrenzen := label.autowrap_mode != TextServer.AUTOWRAP_ARBITRARY
	print(
		(
			"[PT4] Blase '%s': Rect %s im Canvas=%s, Wrap-Modus=%d"
			% [label.text, str(rect), str(drin), label.autowrap_mode]
		)
	)
	return drin and wortgrenzen


func muenzen() -> int:
	var gs := game_state()
	if gs == null:
		return -1
	return int(gs.get_value("economy.coins", -1))


func merke_muenzen() -> bool:
	muenzen_merker = muenzen()
	print("[PT4] Münzstand gemerkt: %d" % muenzen_merker)
	return muenzen_merker >= 0


## Einen benannten Eintrag einer Scroll-Liste in Sicht holen (wie ein
## Spieler, der scrollt — nur ohne Wisch-Raterei bei langen Listen).
func liste_anscrollen(scroll_name: String, ziel_name: String) -> bool:
	var scroll := harness.root.find_child(scroll_name, true, false) as ScrollContainer
	var ziel := harness.root.find_child(ziel_name, true, false) as Control
	if scroll == null or ziel == null:
		print("[PT4] liste_anscrollen: %s/%s nicht gefunden" % [scroll_name, ziel_name])
		return false
	scroll.ensure_control_visible(ziel)
	return true


## Kein Blatt (mehr) offen — Nachbedingung für Dim-Tap/Wisch-Schließen.
func kein_blatt_offen() -> bool:
	return blatt() == null


## Zustand des obersten Blatts in den Lauf-Log schreiben (immer ok) —
## Beleg-Helfer für den G8-Befund „Wieder-Öffnen bringt leeres Blatt".
func blatt_zustand_loggen() -> bool:
	var sheet := blatt()
	if sheet == null:
		print("[PT4] Blatt-Zustand: KEIN offenes Blatt")
		return true
	var body := sheet.find_child("SheetBody", true, false)
	var kinder: Array[String] = []
	if body != null:
		for kind in body.get_children():
			kinder.append("%s(%s)" % [kind.name, str(kind.get_class())])
	print(
		(
			"[PT4] Blatt-Zustand: offen=%s sichtbar=%s Inhalt=%s"
			% [str(sheet.call("is_open")), str(sheet.is_visible_in_tree()), str(kinder)]
		)
	)
	return true


## ── Bett-Bauquest (Erste-Male, Doc D §3.1) ──────────────────────────────
## Der ERSTE Baumodus-Besuch startet automatisch den Bett-Geist (bedSingle,
## 2×3, aus dem Start-Lager) — und `close()` VERWEIGERT „Fertig", solange
## das Bett nicht steht. Diese Bausteine setzen den Geist auf die freien
## Zellen (1,4)–(2,6) links vom Teppich (Start-Layout s.
## scripts/home/data/default_layouts.json) und platzieren ihn.


## GridMount des aktuellen Raums (Zellen-Ursprung fürs tipp_3d-Unprojizieren).
func wohnzimmer_grid() -> Node3D:
	var szene := aktuelle_szene()
	if szene == null:
		return null
	return szene.find_child("GridMount", true, false) as Node3D


## „Platzieren"-Knopf (ActionBar-Kind 1, s. build_ui_dock) tippbar?
func platzieren_aktiv() -> bool:
	var leiste := harness.root.find_child("ActionBar", true, false)
	if leiste == null or leiste.get_child_count() < 2:
		return false
	var knopf := leiste.get_child(1) as Button
	if knopf == null:
		return false
	var bereit := knopf.is_visible_in_tree() and not knopf.disabled
	print("[PT4] Platzieren-Knopf: sichtbar=%s disabled=%s" % [str(knopf.visible), knopf.disabled])
	return bereit


func bett_platziert() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	return bool(gs.get_value("home.flags.bedPlaced", false))


## Schritte NACH dem Baumodus-Öffnen: Bett-Geist auf freie Zellen setzen →
## Platzieren → Fertig (geht erst JETZT — die Bauquest blockt close() bis
## das Bett steht). ZIEL-WAHL (zweifach verbrannt, darum ausführlich):
## (1) Die Bau-UI (Aktions-Chips, Ebenen-Leiste, Lager-Tray) deckt die
## Bildmitte ab und frisst Taps. (2) Vor jeder Tür liegt eine 2×2-
## Freihaltezone (RoomDefs DOOR_WIDTH/DEPTH) — der erste Versuch (at 1,4)
## lag in der WEST-Tür-Zone (0-1,4-5) → Geist rot. Freie 2×3-Flächen mit
## GUI-freier Projektion (oberes Band, rechts der „Was nun?"-Karte):
## Tipp-Zelle (9,2) → at (8,1), Zellen (8,1)-(9,3) — das Regal (8-10,0)
## endet in Zeile 0; Ausweich-Zelle (7,2) → at (6,1), Zellen (6,1)-(7,3) —
## der TV-Schrank (5-7,0) endet ebenfalls in Zeile 0.
func bett_platzieren_schritte() -> Array[Dictionary]:
	return [
		{
			"name": "bett_spot_waehlen",
			"aktion": "tipp_3d",
			"finder": wohnzimmer_grid,
			"offset": Vector3(4.75, 0.0, 1.25),
			"timeout_s": 20.0,
		},
		{
			"name": "platzieren_bereit_erster_spot",
			"aktion": "warte_bis",
			"bedingung": platzieren_aktiv,
			"timeout_s": 6.0,
			"pflicht": false,
		},
		{
			"name": "bett_spot_ausweichen",
			"aktion": "tipp_3d",
			"finder": wohnzimmer_grid,
			"offset": Vector3(3.75, 0.0, 1.25),
			"timeout_s": 20.0,
		},
		{
			"name": "platzieren_bereit",
			"aktion": "warte_bis",
			"bedingung": platzieren_aktiv,
			"timeout_s": 10.0,
		},
		# Goobys ANTWORT-CHIPS („Raus da!"/„Ok, du bist ein Möbel") können
		# GENAU über der Aktionsleiste hängen und den Platzieren-Tap
		# schlucken (Geschichten-Lauf 1: Gooby stand beim Geist, der Chip-
		# Stapel deckte die Leiste — der Tap traf den Chip). Erst wegtippen
		# (falls da), dann platzieren; danach eine Falls-da-Wiederholung —
		# nach GEGLÜCKTEM Platzieren ist der Knopf weg und sie springt über.
		{
			"name": "gooby_wegschicken",
			"aktion": "tipp_falls_da",
			"text": "Raus da!",
			"timeout_s": 2.0,
			"pflicht": false,
		},
		{"name": "chips_abklingen", "aktion": "warte", "sekunden": 0.8},
		{
			"name": "bett_platzieren",
			"aktion": "tipp_text",
			"text": "Platzieren",
			"erwarte": {"bedingung": bett_platziert},
			"timeout_s": 12.0,
			"pflicht": false,
		},
		{
			"name": "gooby_wegschicken_2",
			"aktion": "tipp_falls_da",
			"text": "Raus da!",
			"timeout_s": 2.0,
			"pflicht": false,
		},
		{
			"name": "bett_platzieren_sicher",
			"aktion": "tipp_falls_da",
			"text": "Platzieren",
			"erwarte": {"bedingung": bett_platziert},
			"timeout_s": 6.0,
		},
		{
			"name": "baumodus_fertig",
			"aktion": "tipp_text",
			"text": "Fertig",
			"erwarte": {"bedingung": hud_da},
			"timeout_s": 30.0,
		},
	]


func _suche_blatt(node: Node) -> Control:
	if node is PanelSheet and (node as Control).is_visible_in_tree():
		if bool(node.call("is_open")):
			return node
	for kind in node.get_children():
		var treffer := _suche_blatt(kind)
		if treffer != null:
			return treffer
	return null


## Sichtbaren Node per Script-Klassenname finden (Spiegel der Harness-Suche).
func _suche_klasse(node: Node, klasse: String) -> Node:
	var skript: Script = node.get_script()
	if skript != null and skript.get_global_name() == StringName(klasse):
		if not (node is Control) or (node as Control).is_visible_in_tree():
			return node
	for kind in node.get_children():
		var treffer := _suche_klasse(kind, klasse)
		if treffer != null:
			return treffer
	return null
