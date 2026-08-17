extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/3 Playtest Agent 6 — Flow (e) „Profil + Album“, gedacht für den
## HOCHKANT-Lauf (1320x2868): Profil öffnen (Reisepass 2.0 — Karte im
## Canvas, FLIP auf die Stempelseite und zurück, Schmal-Modus staplet die
## Feldzeilen), Erfolge-Screen (Karten sichtbar), Album: Sammlungs-Seite
## mit allen 4 Set-Karten (fish/veggies/landmarks/treats) sichtbar UND im
## Canvas (W14-P0 „Sticker laufen rechts raus“-Regression), eine Sticker-
## Seite mit Karten im Canvas.
## Aufruf: tools/ci/run_playtest.sh flow_w18a6_profil_album 1320x2868

## Tap-Höhe unterhalb der Kartenoberkante — der Kopfbereich der Pass-Karte
## besteht aus Labels (mouse_filter IGNORE), der Tap fällt auf die Karte.
const PASS_TAP_ABSTAND := 14.0


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_profil())
	liste.append_array(_schritte_erfolge())
	liste.append_array(_schritte_album())
	return liste


func _schritte_profil() -> Array[Dictionary]:
	return [
		# Befund B1/B2: verspäteter Tagesbonus + verspätete Tour-Karte
		# abräumen, sonst schlucken sie die folgenden Taps (Test-Staging).
		{
			"name": "spaeter_tagesbonus",
			"aktion": "tipp_falls_da",
			"text": "Abholen!",
			"timeout_s": 45.0,
			"pflicht": false,
		},
		{
			"name": "tour_spaet_beenden",
			"aktion": "tipp_falls_da",
			"node": "GuideBeenden",
			"timeout_s": 30.0,
			"pflicht": false,
		},
		{
			"name": "wasnun_weg",
			"aktion": "tipp_falls_da",
			"node": "WasNunSchliessen",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "profil_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnProfil",
			"erwarte": {"klasse": "ProfilScreen"},
			"timeout_s": 60.0,
		},
		{"name": "profil_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "pass_im_canvas",
			"aktion": "tue",
			"funktion": pruefe_pass_im_canvas,
			"erwartung": "Pass-Karte komplett im Canvas (W14-Hochformat-Fix)",
			"pflicht": false,
		},
		{
			"name": "pass_flip_hin",
			"aktion": "tipp_pos",
			"pos_funktion": pass_tap_pos,
			"erwarte": {"bedingung": pass_seite_ist.bind("hinten")},
			"timeout_s": 15.0,
		},
		{"name": "stempelseite_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "stempelseite_da",
			"aktion": "tue",
			"funktion": pruefe_stempelseite,
			"erwartung": "Rückseite sichtbar (Stempel-Titel + MRZ-Zone)",
			"pflicht": false,
		},
		{
			"name": "pass_flip_zurueck",
			"aktion": "tipp_pos",
			"pos_funktion": pass_tap_pos,
			"erwarte": {"bedingung": pass_seite_ist.bind("vorne")},
			"timeout_s": 15.0,
		},
		{"name": "vorderseite_ansehen", "aktion": "warte", "sekunden": 1.5},
	]


func _schritte_erfolge() -> Array[Dictionary]:
	return [
		{
			"name": "zu_erfolgen_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("ErfolgeBtn"),
			"erwartung": "Erfolge-Knopf im Bild",
		},
		{"name": "scroll_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "erfolge_oeffnen",
			"aktion": "tipp_name",
			"node": "ErfolgeBtn",
			"erwarte": {"klasse": "AchievementsScreen"},
			"timeout_s": 30.0,
		},
		{"name": "erfolge_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "erfolgskarten_da",
			"aktion": "tue",
			"funktion": pruefe_erfolgskarten,
			"erwartung": "Mindestens eine Erfolgs-Karte sichtbar + im Canvas",
			"pflicht": false,
		},
		{
			"name": "erfolge_zurueck",
			"aktion": "tipp_name",
			"node": "BackBtn",
			"erwarte": {"weg_klasse": "AchievementsScreen"},
			"timeout_s": 20.0,
		},
		{"name": "zurueck_settelt", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "profil_verlassen",
			"aktion": "tue",
			"funktion": profil_verlassen,
			"erwartung": "Profil (falls noch offen) geschlossen",
			"pflicht": false,
		},
		{
			"name": "profil_weg",
			"aktion": "warte_bis",
			"bedingung": profil_weg,
			"timeout_s": 20.0,
		},
	]


func _schritte_album() -> Array[Dictionary]:
	return [
		# W20 P1 (HUD-Slimming): Album ist Sekundär-Kachel — im Quer-
		# Cockpit erst das Mehr-Cluster aufklappen (gepollte Bedingung,
		# Helfer unten; wartet auch ein busy-Router-Fenster nach der
		# Profil-Heimkehr weg — Lauf 1 traf genau dieses Fenster).
		{
			"name": "album_freilegen",
			"aktion": "warte_bis",
			"bedingung": album_freilegen,
			"timeout_s": 30.0,
		},
		{
			"name": "album_oeffnen",
			"aktion": "tipp_name",
			"node": "BtnAlbum",
			"erwarte": {"klasse": "AlbumScreen"},
			"timeout_s": 60.0,
		},
		{"name": "album_ansehen", "aktion": "warte", "sekunden": 2.5},
		{
			"name": "sammlungen_oeffnen",
			"aktion": "tipp_name",
			"node": "PageChip___sammlungen__",
			"erwarte": {"bedingung": sammlungen_sichtbar},
			"timeout_s": 20.0,
		},
		{"name": "sammlungen_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "sammlungen_4_4",
			"aktion": "tue",
			"funktion": pruefe_sammlungen,
			"erwartung": "Alle 4 Set-Karten sichtbar und horizontal im Canvas",
			"pflicht": false,
		},
		{
			"name": "sticker_seite_oeffnen",
			"aktion": "tipp_pos",
			"pos_funktion": erste_sticker_seite_pos,
			"erwarte": {"bedingung": sticker_karten_da},
			"timeout_s": 20.0,
		},
		{"name": "sticker_ansehen", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "sticker_im_canvas",
			"aktion": "tue",
			"funktion": pruefe_sticker_karten,
			"erwartung": "Sticker-Karten sichtbar, keine läuft rechts raus",
			"pflicht": false,
		},
		{
			"name": "album_zurueck",
			"aktion": "tipp_text",
			"text": "Zurück",
			"erwarte": {"weg_klasse": "AlbumScreen"},
			"timeout_s": 20.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Werkzeuge


## W20 P1 Nachfix (HUD-Slimming): die Album-Kachel lebt im Quer-Cockpit
## eingeklappt hinter der Mehr-Kachel — gepollte warte_bis-Bedingung
## (idempotent: höchstens EIN „Mehr“-Druck pro Poll; apply_layout schaltet
## synchron sichtbar, der Recheck verhindert Doppel-Drücke; hochkant
## zeigt alle 10 Kacheln = sofort true).
func album_freilegen() -> bool:
	var kachel := harness.root.find_child("BtnAlbum", true, false) as Control
	if kachel != null and kachel.is_visible_in_tree():
		return true
	var mehr := harness.root.find_child("BtnMehr", true, false) as Button
	if mehr == null or not mehr.is_visible_in_tree():
		return false
	mehr.pressed.emit()
	kachel = harness.root.find_child("BtnAlbum", true, false) as Control
	return kachel != null and kachel.is_visible_in_tree()


func _control(node_name: String) -> Control:
	return harness.root.find_child(node_name, true, false) as Control


func _pass_card() -> Control:
	return _control("PassCard")


## Tap knapp unter die Kartenoberkante (Labels dort ignorieren die Maus,
## Karte fängt den Tap und flippt).
func pass_tap_pos() -> Vector2:
	var karte := _pass_card()
	if karte == null:
		return harness.root.get_visible_rect().size * 0.5
	var rect := karte.get_global_rect()
	return Vector2(rect.get_center().x, rect.position.y + PASS_TAP_ABSTAND)


func pass_seite_ist(soll: String) -> bool:
	var karte := _pass_card()
	return karte != null and str(karte.get("seite")) == soll


## Pass-Karte komplett im Canvas (W14: Hochformat drückte die Karte raus).
func pruefe_pass_im_canvas() -> bool:
	var karte := _pass_card()
	if karte == null or not karte.is_visible_in_tree():
		print("[A6] PassCard fehlt")
		return false
	var sicht := harness.root.get_visible_rect()
	var rect := karte.get_global_rect()
	var drin := sicht.grow(2.0).encloses(rect)
	print("[A6] PassCard rect=%s canvas=%s drin=%s" % [str(rect), str(sicht), drin])
	return drin


func pruefe_stempelseite() -> bool:
	var titel := _control("StempelTitel")
	var mrz := _control("MrzZone")
	var titel_da := titel != null and titel.is_visible_in_tree()
	var mrz_da := mrz != null and mrz.is_visible_in_tree()
	print("[A6] Stempelseite: titel=%s mrz=%s" % [titel_da, mrz_da])
	return titel_da and mrz_da


## Mind. eine Erfolgs-Karte (Erfolg_*) sichtbar und horizontal im Canvas.
func pruefe_erfolgskarten() -> bool:
	var karten := _finde_mit_prefix("Erfolg_")
	if karten.is_empty():
		print("[A6] Keine Erfolg_-Karten gefunden")
		return false
	var sicht := harness.root.get_visible_rect()
	for karte in karten:
		var rect := karte.get_global_rect()
		if rect.position.x < -2.0 or rect.end.x > sicht.size.x + 2.0:
			print("[A6] Erfolgskarte %s läuft raus: %s" % [karte.name, str(rect)])
			return false
	print("[A6] %d Erfolgskarten, alle horizontal im Canvas" % karten.size())
	return true


## Profil-Screen (falls nach dem Erfolge-Zurück wieder offen) verlassen.
func profil_verlassen() -> bool:
	if harness.root.find_child("PassCard", true, false) == null:
		return true
	var zurueck := _control("BackBtn")
	if zurueck == null or not zurueck.is_visible_in_tree():
		return false
	(zurueck as Button).pressed.emit()
	return true


func profil_weg() -> bool:
	return harness.root.find_child("PassCard", true, false) == null


func sammlungen_sichtbar() -> bool:
	var view := _control("CollectionsView")
	return view != null and view.is_visible_in_tree()


## Alle 4 Set-Karten (aus CollectionsLogic.SETS) sichtbar + im Canvas.
func pruefe_sammlungen() -> bool:
	var sicht := harness.root.get_visible_rect()
	var fehlend: Array[String] = []
	var raus: Array[String] = []
	for set_def: Dictionary in CollectionsLogic.SETS:
		var set_id := str(set_def["id"])
		var karte := _control("SetCard_%s" % set_id)
		if karte == null or not karte.is_visible_in_tree():
			fehlend.append(set_id)
			continue
		var rect := karte.get_global_rect()
		if rect.position.x < -2.0 or rect.end.x > sicht.size.x + 2.0:
			raus.append("%s rect=%s" % [set_id, str(rect)])
	print("[A6] Sammlungen fehlend=%s raus=%s" % [str(fehlend), str(raus)])
	return fehlend.is_empty() and raus.is_empty()


## Erste echte Sticker-Seite in der Rail: ERSTER Chip in Leserichtung, der
## EFFEKTIV sichtbar ist — komplett im Canvas UND im Clip-Ausschnitt aller
## clippenden Vorfahren. Die Rail ist ein ScrollContainer (quer vertikal,
## hochkant horizontal): rausgescrollte Chips bleiben is_visible_in_tree(),
## ein Tap auf ihre „Mitte“ geht aber ins Leere (Lauf 1 hochkant traf so
## einen rausgescrollten Chip, Lauf 2 quer PageChip_jahreszeiten UNTER dem
## Rail-Ausschnitt — die reine Canvas-x-Prüfung reichte nicht).
func erste_sticker_seite_pos() -> Vector2:
	var bester: Control = null
	for chip in _finde_mit_prefix("PageChip_"):
		if chip.name == "PageChip___sammlungen__" or not _effektiv_sichtbar(chip):
			continue
		if bester == null or _liegt_davor(chip, bester):
			bester = chip
	if bester == null:
		print("[A6] Kein voll sichtbarer Sticker-PageChip")
		return harness.root.get_visible_rect().size * 0.5
	print("[A6] Sticker-Seite via %s" % bester.name)
	return bester.get_global_rect().get_center()


## Komplett im Canvas UND im Ausschnitt aller clippenden Vorfahren
## (ScrollContainer clippt per Default) — mit 2-px-Toleranz an den Kanten.
func _effektiv_sichtbar(ctl: Control) -> bool:
	var rect := ctl.get_global_rect()
	var ausschnitt := harness.root.get_visible_rect()
	var n: Node = ctl.get_parent()
	while n != null:
		var eltern := n as Control
		if eltern != null and eltern.clip_contents:
			ausschnitt = ausschnitt.intersection(eltern.get_global_rect())
		n = n.get_parent()
	return ausschnitt.grow(2.0).encloses(rect)


## true, wenn `a` in Leserichtung vor `b` liegt (erst oben, dann links) —
## quer ist die Rail eine Spalte (y entscheidet), hochkant eine Zeile (x).
func _liegt_davor(a: Control, b: Control) -> bool:
	var ra := a.get_global_rect()
	var rb := b.get_global_rect()
	if absf(ra.position.y - rb.position.y) > 1.0:
		return ra.position.y < rb.position.y
	return ra.position.x < rb.position.x


## Mindestens eine Sticker-Karte im Baum sichtbar (Seite ist umgeschaltet).
func sticker_karten_da() -> bool:
	return not _finde_mit_prefix("Sticker_").is_empty()


## Sticker-Karten (Sticker_*) sichtbar, keine läuft rechts aus dem Canvas
## (W14-P0-Regression).
func pruefe_sticker_karten() -> bool:
	var karten := _finde_mit_prefix("Sticker_")
	if karten.is_empty():
		print("[A6] Keine Sticker_-Karten gefunden")
		return false
	var sicht := harness.root.get_visible_rect()
	for karte in karten:
		var rect := karte.get_global_rect()
		if rect.end.x > sicht.size.x + 2.0:
			print("[A6] Sticker %s läuft rechts raus: %s" % [karte.name, str(rect)])
			return false
	print("[A6] %d Sticker-Karten, alle im Canvas" % karten.size())
	return true


## Sichtbare Controls, deren Name mit dem Prefix beginnt.
func _finde_mit_prefix(prefix: String) -> Array[Control]:
	var treffer: Array[Control] = []
	var stapel: Array[Node] = [harness.root]
	while not stapel.is_empty():
		var aktuell: Node = stapel.pop_back()
		var ctl := aktuell as Control
		if ctl != null and str(ctl.name).begins_with(prefix) and ctl.is_visible_in_tree():
			treffer.append(ctl)
		for kind in aktuell.get_children():
			stapel.append(kind)
	return treffer


## Ziel-Control in seinem ScrollContainer ins Bild holen.
func scrolle_zu(node_name: String) -> bool:
	var ziel := _control(node_name)
	if ziel == null:
		print("[A6] scrolle_zu: %s fehlt" % node_name)
		return false
	var scroll: ScrollContainer = null
	var n: Node = ziel.get_parent()
	while n != null:
		if n is ScrollContainer:
			scroll = n
			break
		n = n.get_parent()
	if scroll == null:
		print("[A6] scrolle_zu: kein ScrollContainer über %s" % node_name)
		return false
	var delta := ziel.get_global_rect().position.y - scroll.get_global_rect().position.y
	scroll.scroll_vertical += int(delta - scroll.get_global_rect().size.y * 0.35)
	return true
