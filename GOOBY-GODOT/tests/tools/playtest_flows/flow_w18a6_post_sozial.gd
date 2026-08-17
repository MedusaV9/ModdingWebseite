extends "res://tests/tools/playtest_flows/flow_basis.gd"
## W18/3 Playtest Agent 6 — Flow (d) „Post: Briefe + Geschenke“: Buddy-
## Freundschaft (beidseitige Anfrage → Server-Auto-Accept; der Buddy-Agent
## schickt danach automatisch einen Brief MIT GESCHENK), Reise zur Post,
## Ungelesen-Kapsel am Brief-Schalter, Briefkasten: ungelesener Brief +
## Geschenk ANNEHMEN, „Brief schreiben“ mit VERWERFEN-NACHFRAGE (erst
## Weiterschreiben, dann echt senden mit Geschenk + Porto), zweiter
## Entwurf wird über die Nachfrage wirklich verworfen.
## Voraussetzung: GOOBY-SERVER auf 127.0.0.1:8765 + buddy_agent.mjs.
##
## V5 (W18/4-Fixes): die Workarounds aus V3/V4 sind RAUS — der echte Weg
## muss grün sein. B7 ist an der Wurzel gefixt (OrtScene.zeige_overlay
## mountet das MailSheet ÜBER dem Schalter-Sheet, MailSheet nimmt am
## PanelStack teil) → kein Backdrop-Tap-Trick mehr, stattdessen die
## Pflicht-Wache `mailsheet_vorn`. B5 ist gefixt (net_client.gd attacht
## NetMail eager beim Boot) → kein `netmail_frueh`-Staging mehr; Pushes
## vor dem ersten UI-attach zählen jetzt von selbst.
## V4 (nach Lauf 3, überholt): Schalter-Deckel per Backdrop-Tap/close().
## V3 (nach Lauf 2, überholt): NetMail früh attachen; „Briefkasten
## öffnen“ liegt unterhalb des Sheet-Folds — vor dem Tap dorthin scrollen.
## Aufruf: tools/ci/run_playtest.sh flow_w18a6_post_sozial

const BUDDY_DIR := "/tmp/gooby-w18/playtest"
## Brieftext des ersten (gesendeten) Briefs.
const BRIEF_TEXT := "Danke fuer die Moehre, Buddy! Gruesse aus dem Playtest."

## Möhren-Stand vor dem Geschenk-Annehmen (fürs Gutschrift-Urteil).
var _moehren_vorher := -1
## Münzstand vor dem Senden (Porto-Urteil).
var _muenzen_vorher := -1


func schritte() -> Array[Dictionary]:
	var liste: Array[Dictionary] = []
	liste.append_array(onboarding_schritte())
	liste.append_array(_schritte_freundschaft())
	liste.append_array(_schritte_zur_post())
	liste.append_array(_schritte_briefkasten())
	liste.append_array(_schritte_brief_schreiben())
	return liste


func _schritte_freundschaft() -> Array[Dictionary]:
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
			"name": "netz_online",
			"aktion": "warte_bis",
			"bedingung": eigener_code_da,
			"timeout_s": 60.0,
		},
		{
			"name": "geschenk_vorrat",
			"aktion": "tue",
			"funktion": moehre_bereitlegen,
			"erwartung": "Eine Möhre liegt zum Verschenken bereit",
		},
		{
			"name": "buddy_anfreunden",
			"aktion": "tue",
			"funktion": buddy_anfreunden,
			"erwartung": "Anfrage an den Buddy ist raus (beidseitig)",
		},
		{
			"name": "freundschaft_steht",
			"aktion": "warte_bis",
			"bedingung": freund_da,
			"timeout_s": 60.0,
		},
		# Lauf 1: der Buddy-Brief kam erst Minuten später an (träges Datei-
		# Polling des Test-Buddys) — großzügig warten, aber nicht abbrechen:
		# die Briefkasten-Schritte prüfen den Eingang ohnehin live.
		{
			"name": "geschenk_brief_kommt",
			"aktion": "warte_bis",
			"bedingung": brief_ungelesen,
			"timeout_s": 240.0,
			"pflicht": false,
		},
	]


func _schritte_zur_post() -> Array[Dictionary]:
	return [
		{
			"name": "reise_in_die_stadt",
			"aktion": "tipp_name",
			"node": "BtnReise",
			"erwarte": {"route": "city"},
			"timeout_s": 180.0,
		},
		{"name": "stadt_ankommen", "aktion": "warte", "sekunden": 5.0},
		{
			"name": "vor_der_post_parken",
			"aktion": "tue",
			"funktion": fahre_zur_post,
			"erwartung": "Auto steht am Post-Parkplatz",
		},
		{
			"name": "post_betreten",
			"aktion": "tipp_text",
			"text": "Betreten",
			"erwarte": {"route": "city/ort/post"},
			"timeout_s": 120.0,
		},
		{"name": "post_ankommen", "aktion": "warte", "sekunden": 3.0},
		{
			"name": "bubble_zeile_zeigen",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 15.0,
			"pflicht": false,
		},
		{"name": "bubble_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "bubble_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
			"pflicht": false,
		},
		# Lauf 1: der Brief-Schalter hängt im LADEN-Sheet, das erst über den
		# Pia-Dialog (Effekt `laden`) aufgeht — Option wählen, Antwort-Zeilen
		# durchtippen, dann steht die Schalter-Karte mit dem Briefkasten.
		{
			"name": "paket_option",
			"aktion": "tipp_text",
			"text": "Liegt ein Paket für mich bereit?",
			"timeout_s": 60.0,
		},
		{"name": "antwort_lesen", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "antwort_zeile_zeigen",
			"aktion": "tipp_name",
			"node": "TypewriterTapFang",
			"timeout_s": 20.0,
		},
		{"name": "antwort_pause", "aktion": "warte", "sekunden": 0.6},
		{
			"name": "antwort_weiter",
			"aktion": "tipp_falls_da",
			"node": "TypewriterTapFang",
			"timeout_s": 4.0,
			"pflicht": false,
		},
		{
			"name": "schalter_sheet_da",
			"aktion": "warte_bis",
			"text": "Briefkasten öffnen",
			"timeout_s": 30.0,
		},
		{"name": "schalter_ansehen", "aktion": "warte", "sekunden": 1.5},
		# Lauf 2: die Briefe-Karte liegt unterhalb des Sheet-Folds (Screenshot
		# 034) — erst ins Bild scrollen, sonst geht der Tap ins Leere.
		{
			"name": "zum_briefkasten_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("BriefeOeffnen"),
			"erwartung": "Briefe-Karte im Sichtfenster",
		},
		{"name": "scroll_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "ungelesen_kapsel",
			"aktion": "tue",
			"funktion": pruefe_ungelesen_kapsel,
			"erwartung": "Ungelesen-Kapsel am Brief-Schalter sichtbar",
			"pflicht": false,
		},
	]


func _schritte_briefkasten() -> Array[Dictionary]:
	return [
		{
			"name": "briefkasten_oeffnen",
			"aktion": "tipp_name",
			"node": "BriefeOeffnen",
			"erwarte": {"klasse": "MailSheet"},
			"timeout_s": 45.0,
		},
		# B7-Wache (W18/4-Fix, PFLICHT): das später geöffnete MailSheet liegt
		# VOR dem Schalter-Sheet und ist das oberste Panel im Modal-Stack —
		# der frühere Backdrop-Tap-Trick ist raus, der echte Weg muss grün sein.
		{
			"name": "mailsheet_vorn",
			"aktion": "tue",
			"funktion": pruefe_mailsheet_vorn,
			"erwartung": "MailSheet vor dem Schalter-Sheet + oberstes Panel",
		},
		{"name": "posteingang_laden", "aktion": "warte", "sekunden": 3.0},
		# Falls der Buddy-Brief noch unterwegs ist: im Sheet nachladen,
		# bis er da ist (Lauf 1 kam er erst Minuten nach der Anfrage an).
		{
			"name": "eingang_nachladen",
			"aktion": "tipp_falls_da",
			"text": "Neu laden",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{
			"name": "brief_da",
			"aktion": "warte_bis",
			"bedingung": brief_ungelesen,
			"timeout_s": 90.0,
			"pflicht": false,
		},
		{
			"name": "eingang_nachladen_2",
			"aktion": "tipp_falls_da",
			"text": "Neu laden",
			"timeout_s": 10.0,
			"pflicht": false,
		},
		{"name": "eingang_settelt", "aktion": "warte", "sekunden": 2.0},
		{
			"name": "ungelesen_punkt",
			"aktion": "tue",
			"funktion": pruefe_ungelesen_punkt,
			"erwartung": "Buddy-Brief mit Ungelesen-Punkt im Eingang",
			"pflicht": false,
		},
		{
			"name": "moehren_merken",
			"aktion": "tue",
			"funktion": merke_moehren,
			"erwartung": "Möhren-Stand notiert",
		},
		# Der Geschenk-Chip kann unterhalb des Listen-Folds liegen.
		{
			"name": "zu_annehmen_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("AnnehmenButton"),
			"erwartung": "Annehmen-Knopf im Bild",
			"pflicht": false,
		},
		{"name": "annehmen_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "geschenk_annehmen",
			"aktion": "tipp_name",
			"node": "AnnehmenButton",
			"erwarte": {"bedingung": moehre_gutgeschrieben},
			"timeout_s": 45.0,
		},
		{"name": "geschenk_gebucht", "aktion": "warte", "sekunden": 1.5},
	]


func _schritte_brief_schreiben() -> Array[Dictionary]:
	return [
		{
			"name": "zu_schreiben_scrollen",
			"aktion": "tue",
			"funktion": scrolle_zu.bind("SchreibenButton"),
			"erwartung": "Schreiben-Knopf im Bild",
			"pflicht": false,
		},
		{"name": "schreiben_settelt", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "brief_schreiben",
			"aktion": "tipp_name",
			"node": "SchreibenButton",
			"timeout_s": 20.0,
		},
		{"name": "compose_da", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "brieftext_tippen",
			"aktion": "tue",
			"funktion": brieftext_setzen.bind(BRIEF_TEXT),
			"erwartung": "Brieftext steht im Feld",
		},
		# G3/P07 Compose-Guard: X mit Entwurf → Verwerfen-Nachfrage.
		{
			"name": "x_mit_entwurf",
			"aktion": "tipp_name",
			"node": "SchliessenButton",
			"erwarte": {"name": "VerwerfenDialog"},
			"timeout_s": 15.0,
		},
		{"name": "nachfrage_ansehen", "aktion": "warte", "sekunden": 1.0},
		{
			"name": "weiterschreiben",
			"aktion": "tipp_name",
			"node": "WeiterschreibenButton",
			"erwarte": {"weg_text": "wegwerfen?"},
			"timeout_s": 15.0,
		},
		{
			"name": "geschenk_waehlen",
			"aktion": "tue",
			"funktion": geschenk_waehlen,
			"erwartung": "Möhre als Geschenk gewählt",
			"pflicht": false,
		},
		{
			"name": "porto_merken",
			"aktion": "tue",
			"funktion": merke_muenzen,
			"erwartung": "Münzstand notiert",
		},
		{
			"name": "brief_senden",
			"aktion": "tipp_name",
			"node": "SendenButton",
			"erwarte": {"bedingung": porto_abgebucht},
			"timeout_s": 30.0,
		},
		{"name": "sende_toast", "aktion": "warte", "sekunden": 2.5},
		# Zweiter Entwurf wird über die Nachfrage WIRKLICH verworfen.
		{
			"name": "zweiter_brief",
			"aktion": "tipp_name",
			"node": "SchreibenButton",
			"timeout_s": 20.0,
		},
		{"name": "compose2_da", "aktion": "warte", "sekunden": 1.5},
		{
			"name": "zweiter_text",
			"aktion": "tue",
			"funktion": brieftext_setzen.bind("Diesen Entwurf werfe ich gleich weg."),
			"erwartung": "Zweiter Entwurf steht im Feld",
		},
		{
			"name": "x_zweiter_entwurf",
			"aktion": "tipp_name",
			"node": "SchliessenButton",
			"erwarte": {"name": "VerwerfenDialog"},
			"timeout_s": 15.0,
		},
		{
			"name": "wirklich_verwerfen",
			"aktion": "tipp_name",
			"node": "VerwerfenButton",
			"erwarte": {"weg_klasse": "MailSheet"},
			"timeout_s": 15.0,
		},
		{"name": "abschluss", "aktion": "warte", "sekunden": 2.0},
	]


## ------------------------------------------------------------- Werkzeuge


func _control(node_name: String) -> Control:
	return harness.root.find_child(node_name, true, false) as Control


func _net() -> Node:
	return harness.root.get_node_or_null("/root/Net")


func _mail_service() -> Object:
	var netz := _net()
	if netz == null:
		return null
	return NetMail.attach(netz)


func eigener_code_da() -> bool:
	var netz := _net()
	return netz != null and str(netz.get("friend_code")).begins_with("GOOBY-")


## Eine Möhre ins Nahrungs-Inventar legen (Geschenk zum Senden).
func moehre_bereitlegen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("inventory") is Dictionary):
				state["inventory"] = {}
			var inventar: Dictionary = state["inventory"]
			if not (inventar.get("food") is Dictionary):
				inventar["food"] = {}
			var essen: Dictionary = inventar["food"]
			essen["carrot"] = int(essen.get("carrot", 0)) + 1
	)
	return int(gs.get_value("inventory.food.carrot", 0)) > 0


## Beidseitige Anfrage: eigenen Code für den Buddy hinterlegen UND selbst
## eine Anfrage an den Buddy-Code schicken → Server-Auto-Accept.
func buddy_anfreunden() -> bool:
	var netz := _net()
	if netz == null:
		return false
	var code := str(netz.get("friend_code"))
	if not code.begins_with("GOOBY-"):
		return false
	var datei := FileAccess.open("%s/player_code_post.txt" % BUDDY_DIR, FileAccess.WRITE)
	if datei != null:
		datei.store_string(code)
		datei.flush()
	var buddy := FileAccess.open("%s/buddy_code.txt" % BUDDY_DIR, FileAccess.READ)
	if buddy == null:
		print("[A6] buddy_code.txt fehlt")
		return false
	var buddy_code := buddy.get_as_text().strip_edges()
	var freunde_service: Variant = netz.get("friends")
	if freunde_service == null:
		return false
	freunde_service.call("add_friend", buddy_code)
	print("[A6] Anfrage an %s raus, eigener Code %s hinterlegt" % [buddy_code, code])
	return true


func freund_da() -> bool:
	var netz := _net()
	if netz == null:
		return false
	var freunde_service: Variant = netz.get("friends")
	if freunde_service == null:
		return false
	var freunde: Variant = freunde_service.get("friends")
	return freunde is Array and not (freunde as Array).is_empty()


func brief_ungelesen() -> bool:
	var service := _mail_service()
	return service != null and int(service.get("unread")) > 0


## Auto direkt an den Post-Parkplatz stellen (Fahr-Skill ist nicht
## Testziel) — Muster aus flow_w18_rehwei.fahre_vor.
func fahre_zur_post() -> bool:
	var szene := aktuelle_szene()
	if not (szene is CityScene):
		return false
	var stadt: CityScene = szene
	if stadt.karte == null or stadt.auto == null:
		return false
	stadt.set("_ausparken", null)
	stadt.auto.position = stadt.karte.parkplatz_welt("post")
	stadt.auto.speed = 0.0
	return true


## Ungelesen-Kapsel am Brief-Schalter: NetMail.unread > 0 UND das
## StatusCapsule-Badge (UngelesenBadge) sichtbar (0 = unsichtbar by design).
func pruefe_ungelesen_kapsel() -> bool:
	var service := _mail_service()
	var unread := int(service.get("unread")) if service != null else 0
	var badge := _control("UngelesenBadge")
	var badge_da := badge != null and badge.is_visible_in_tree()
	print("[A6] NetMail.unread=%d badge_sichtbar=%s" % [unread, badge_da])
	return unread > 0 and badge_da


func pruefe_ungelesen_punkt() -> bool:
	var punkt := _control("UngelesenPunkt")
	var da := punkt != null and punkt.is_visible_in_tree()
	print("[A6] UngelesenPunkt sichtbar=%s" % da)
	return da


func merke_moehren() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_moehren_vorher = int(gs.get_value("inventory.food.carrot", 0))
	return true


func moehre_gutgeschrieben() -> bool:
	var gs := game_state()
	if gs == null or _moehren_vorher < 0:
		return false
	return int(gs.get_value("inventory.food.carrot", 0)) > _moehren_vorher


## Brieftext direkt setzen (TextEdit — die eingabe-Aktion kann nur
## LineEdits) + text_changed für den Zeichen-Zähler feuern.
func brieftext_setzen(text: String) -> bool:
	var feld := _control("BriefText") as TextEdit
	if feld == null or not feld.is_visible_in_tree():
		print("[A6] BriefText fehlt")
		return false
	feld.text = text
	feld.text_changed.emit()
	return true


## Möhre als Geschenk wählen (OptionButton-Popup ist für die Harness
## nicht tippbar — Auswahl programmatisch, Handler läuft mit).
func geschenk_waehlen() -> bool:
	var wahl := _control("GeschenkWahl") as OptionButton
	if wahl == null or wahl.item_count < 2:
		print("[A6] GeschenkWahl leer (item_count=%d)" % (wahl.item_count if wahl != null else -1))
		return false
	wahl.select(1)
	wahl.item_selected.emit(1)
	var meta: Variant = wahl.get_item_metadata(1)
	print("[A6] Geschenk gewählt: %s" % str(meta))
	return meta is Dictionary and not (meta as Dictionary).is_empty()


func merke_muenzen() -> bool:
	var gs := game_state()
	if gs == null:
		return false
	_muenzen_vorher = int(gs.get_value("economy.coins", 0))
	return true


## Senden verbucht: Porto (5 ᴳ) ist abgebucht (Geschenk-Entnahme läuft in
## derselben Transaktion).
func porto_abgebucht() -> bool:
	var gs := game_state()
	if gs == null or _muenzen_vorher < 0:
		return false
	return int(gs.get_value("economy.coins", 0)) < _muenzen_vorher


## B7-Wache (W18/4-Fix): das später geöffnete MailSheet ist VORN — späteres
## Geschwister als das Schalter-PanelSheet im selben CanvasLayer UND das
## oberste Panel im Modal-Stack (G7-P53). Vor dem Fix mountete es dahinter
## und der Schalter schluckte alle Taps.
func pruefe_mailsheet_vorn() -> bool:
	var mail := _finde_klasse_instanz("MailSheet")
	if mail == null:
		print("[A6] mailsheet_vorn: MailSheet fehlt")
		return false
	var panel := _finde_klasse_instanz("PanelSheet")
	var vorn := true
	if panel != null and mail.get_parent() == panel.get_parent():
		vorn = mail.get_index() > panel.get_index()
	var oberstes := PanelStack.is_top(mail as Control)
	print("[A6] B7-Wache: vorn=%s oberstes_panel=%s" % [vorn, oberstes])
	return vorn and oberstes


func _finde_klasse_instanz(klasse: String) -> Node:
	return _suche_klasse(harness.root, klasse)


func _suche_klasse(node: Node, klasse: String) -> Node:
	var skript := node.get_script() as Script
	if skript != null and str(skript.get_global_name()) == klasse:
		return node
	for kind in node.get_children():
		var gefunden := _suche_klasse(kind, klasse)
		if gefunden != null:
			return gefunden
	return null


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
