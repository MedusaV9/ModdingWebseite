extends "res://tests/tools/playtest_flows/flow_basis.gd"
## PT-2-Helfer-Schicht (Welle H, G8) — UI-Sucher, Gesten-Anker und Termin-
## Bausteine für die Stadt-/Läden-Flows. Von flow_pt2_basis.gd geerbt
## (Split wegen gdlint max-public-methods, Muster settings_rows_basis).

## ---------------------------------------------------------------- Suchen


## Sichtbaren Button in der ZEILE eines Labels finden (Kauf-Listen, in
## denen mehrere Knöpfe denselben Preis-Text tragen). Läuft den Baum ab,
## sucht das Label mit `label_text` (Teilstring) und gibt die Mitte des
## ersten Buttons im selben Zeilen-Container zurück (Vector2.ZERO = Fehl).
func knopf_neben_label(label_text: String) -> Vector2:
	var label := _finde_sichtbares_label(harness.root, label_text)
	if label == null:
		print("[PT2] knopf_neben_label: Label '%s' nicht gefunden" % label_text)
		return Vector2.ZERO
	var zeile: Node = label.get_parent()
	for _stufe in 3:
		if zeile == null:
			break
		var knopf := _finde_knopf_unter(zeile, label)
		if knopf != null:
			# Clip-Schutz (Lauf pt2_c1): weggescrollte Zeilen haben ihr
			# Global-Rect AUSSERHALB des Scroll-Fensters — dort zu tippen
			# trifft daneben und SCHLIESST das Sheet. Vorher rolle_zu_text!
			if not _im_scroll_fenster(knopf):
				print("[PT2] Knopf neben '%s' ist weggescrollt — kein Tipp" % label_text)
				return Vector2.ZERO
			print("[PT2] Knopf neben '%s': %s" % [label_text, knopf.text])
			return knopf.get_global_rect().get_center()
		zeile = zeile.get_parent()
	print("[PT2] knopf_neben_label: kein Knopf neben '%s'" % label_text)
	return Vector2.ZERO


## Mitte eines (sichtbaren) Controls per Node-Namen (für tipp_pos-Fabriken).
func control_mitte(node_name: String) -> Vector2:
	var node := _finde_sichtbares_control(harness.root, node_name)
	if node == null:
		print("[PT2] control_mitte: '%s' nicht sichtbar/gefunden" % node_name)
		return Vector2.ZERO
	return node.get_global_rect().get_center()


## Mitte NUR wenn sie auch im Canvas liegt (sonst ZERO — Liste erst scrollen).
func sichtbare_mitte(node_name: String) -> Vector2:
	var mitte := control_mitte(node_name)
	if mitte == Vector2.ZERO:
		return mitte
	if not harness.root.get_visible_rect().has_point(mitte):
		print("[PT2] sichtbare_mitte: '%s' liegt außerhalb des Canvas" % node_name)
		return Vector2.ZERO
	return mitte


## Mitte des ersten tippbaren Knopfs UNTER einem benannten Container —
## für Phone-Kacheln (KachelGooberando) und DLC-Karten (DlcKarte_<id>),
## deren innerer Knopf keinen eigenen Namen trägt.
func knopf_in(node_name: String) -> Vector2:
	var halter := _finde_sichtbares_control(harness.root, node_name)
	if halter == null:
		print("[PT2] knopf_in: '%s' nicht sichtbar/gefunden" % node_name)
		return Vector2.ZERO
	var knopf := _finde_knopf_unter(halter, null)
	if knopf == null:
		print("[PT2] knopf_in: kein tippbarer Knopf unter '%s'" % node_name)
		return Vector2.ZERO
	print("[PT2] knopf_in '%s': %s" % [node_name, knopf.text])
	return knopf.get_global_rect().get_center()


## Scroll-Ahnen bitten, das Ziel ins Bild zu holen (deterministische
## Ergänzung zum echten Wisch — ein Spieler scrollt, bis es sichtbar ist).
func rolle_zu(node_name: String) -> bool:
	var ziel := harness.root.find_child(node_name, true, false)
	if not (ziel is Control):
		print("[PT2] rolle_zu: '%s' nicht im Baum" % node_name)
		return false
	var ahn: Node = ziel.get_parent()
	while ahn != null and not (ahn is ScrollContainer):
		ahn = ahn.get_parent()
	if ahn == null:
		print("[PT2] rolle_zu: kein ScrollContainer über '%s'" % node_name)
		return true
	(ahn as ScrollContainer).ensure_control_visible(ziel)
	print("[PT2] rolle_zu: '%s' ins Bild geholt" % node_name)
	return true


## Control mit `text` (Label ODER Knopf, Teilstring) in ALLEN Scroll-Ahnen
## sichtbar machen (PanelSheets clippen doppelt: innere Warenliste UND das
## höhen-gedeckelte %SheetScroll). tipp_pos/tipp_text tappen stur aufs
## Global-Rect — bei weggescrollten Zeilen ginge der Tipp daneben und der
## Backdrop SCHLIESST das Sheet (Lauf pt2_c1/c2!). Nutzung über
## rolle_schritte(): zweimal rollen, weil verschachtelte Scroller erst
## nach einem Layout-Frame endgültig sitzen.
func rolle_zu_text(text: String) -> bool:
	var ziel := _finde_text_control(harness.root, text)
	if ziel == null:
		print("[PT2] rolle_zu_text: '%s' nicht gefunden" % text)
		return false
	var gerollt := _rolle_alle_scroller(ziel)
	if gerollt > 0:
		print("[PT2] rolle_zu_text: '%s' über %d Scroller geholt" % [text, gerollt])
	return true


## Doppel-Roll-Baustein für Flows: Ziel-Text zweimal ins Bild rollen (mit
## Setz-Pausen), danach ist ein tipp_text/knopf_neben_label-Tipp sicher.
func rolle_schritte(text: String, prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 2:
		(
			out
			. append(
				{
					"name": "%s_rollen_%d" % [prefix, i + 1],
					"aktion": "tue",
					"funktion": rolle_zu_text.bind(text),
					"pflicht": false,
				}
			)
		)
		out.append(
			{"name": "%s_roll_pause_%d" % [prefix, i + 1], "aktion": "warte", "sekunden": 0.5}
		)
	return out


## Property auf der aktuellen Router-Szene setzen (tempo, seed_override …).
func szene_prop(prop: String, wert: Variant) -> bool:
	var szene := aktuelle_szene()
	if szene == null:
		print("[PT2] szene_prop: keine aktive Szene")
		return false
	szene.set(prop, wert)
	print("[PT2] szene_prop: %s.%s = %s" % [szene.name, prop, str(wert)])
	return true


## Punkt AUF dem ersten sichtbaren HSlider (rel −0.5…0.5 der Breite) —
## für echte Preis-Schieber-Drags per Wisch. Holt den Slider vorher in
## allen Scroll-Ahnen ins Bild (lange Sheets clippen die Slot-Zeilen).
func slider_punkt(rel_x: float) -> Vector2:
	var slider := _finde_ersten_slider(harness.root)
	if slider == null:
		print("[PT2] slider_punkt: kein sichtbarer HSlider")
		return Vector2.ZERO
	_rolle_alle_scroller(slider)
	var rect := slider.get_global_rect()
	return rect.get_center() + Vector2(rect.size.x * rel_x, 0.0)


## Für warte_bis-{"bedingung": …}: sichtbares Control mit Node-Namen da?
## (Der erwarte-Key "name" kollidiert mit dem Schritt-Namen — deshalb
## IMMER diese Bedingung binden, wenn auf einen Node-Namen gewartet wird.)
func control_da(node_name: String) -> bool:
	return _finde_sichtbares_control(harness.root, node_name) != null


## Ziel in ALLEN ScrollContainer-Ahnen sichtbar rollen (innen → außen).
## Rückgabe: Anzahl gerollter Scroller.
func _rolle_alle_scroller(ziel: Control) -> int:
	var gerollt := 0
	var ahn: Node = ziel.get_parent()
	while ahn != null:
		if ahn is ScrollContainer:
			(ahn as ScrollContainer).ensure_control_visible(ziel)
			gerollt += 1
		ahn = ahn.get_parent()
	return gerollt


## Liegt die Mitte eines Controls in den Fenstern ALLER Scroll-Ahnen?
## Weggescrollte Zeilen sind visible_in_tree, aber geclippt — ein Tipp
## dort trifft den Backdrop und schließt das Sheet.
func _im_scroll_fenster(ziel: Control) -> bool:
	var mitte := ziel.get_global_rect().get_center()
	var ahn: Node = ziel.get_parent()
	while ahn != null:
		if ahn is ScrollContainer:
			if not (ahn as ScrollContainer).get_global_rect().has_point(mitte):
				return false
		ahn = ahn.get_parent()
	return true


## Sichtbares Control, dessen text-Property `text` enthält (Label/Button).
func _finde_text_control(wurzel: Node, text: String) -> Control:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Label or aktuell is Button:
			var t := str(aktuell.get("text"))
			if not t.is_empty() and t.to_lower().contains(nadel):
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _finde_ersten_slider(wurzel: Node) -> HSlider:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is HSlider:
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _finde_sichtbares_label(wurzel: Node, text: String) -> Label:
	var nadel := text.to_lower()
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and not (aktuell as Control).is_visible_in_tree():
			continue
		if aktuell is Label and (aktuell as Label).text.to_lower().contains(nadel):
			return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _finde_knopf_unter(wurzel: Node, ausser: Node) -> BaseButton:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is BaseButton and aktuell != ausser:
			if (aktuell as Control).is_visible_in_tree() and not (aktuell as BaseButton).disabled:
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


func _finde_sichtbares_control(wurzel: Node, node_name: String) -> Control:
	var stapel: Array[Node] = [wurzel]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		if aktuell is Control and aktuell.name == node_name:
			if (aktuell as Control).is_visible_in_tree():
				return aktuell
		for kind in aktuell.get_children():
			stapel.append(kind)
	return null


## ---------------------------------------------------------------- Wische


## Wisch-Anker fürs Scrollen von Listen (Canvas-Mitte, hoch = Inhalt runter).
func canvas_punkt(rel: Vector2) -> Vector2:
	return harness.root.get_visible_rect().size * rel


func wisch_mitte_unten() -> Vector2:
	return canvas_punkt(Vector2(0.5, 0.72))


func wisch_mitte_oben() -> Vector2:
	return canvas_punkt(Vector2(0.5, 0.3))


## ---------------------------------------------------------------- Termine


## Unix-Zeit des nächsten Markt-Samstags um `stunde` Uhr (der Anker, den
## MarktStandSheet.zeit_override fürs Markttag-Replay braucht).
func naechster_samstag_unix(stunde: int) -> int:
	var jetzt := int(Time.get_unix_time_from_system())
	var tag := MarktStand.naechster_markt_tag(jetzt)
	return int(Time.get_unix_time_from_datetime_string("%sT%02d:00:00" % [tag, stunde]))


## Standard-Baustein: Dialog-Bubble eines Orts durchtippen (Typewriter-
## Fänger). `anzahl` Taps, jeder optional — überschüssige verpuffen leise.
func dialog_taps(anzahl: int, prefix: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in anzahl:
		(
			out
			. append(
				{
					"name": "%s_dialog_tap_%d" % [prefix, i + 1],
					"aktion": "tipp_falls_da",
					"node": "TypewriterTapFang",
					"timeout_s": 8.0,
					"pflicht": false,
				}
			)
		)
	return out
