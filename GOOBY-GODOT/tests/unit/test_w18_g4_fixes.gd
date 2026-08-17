extends TestCase
## W18/4 (Fix-Agent G4) — Wächter für die drei Playtest-Befunde der
## Telefon/Sozial-Welle:
## - B7 (Layering-Klasse): ein SPÄTER geöffnetes Overlay (MailSheet) liegt
##   deterministisch ÜBER dem offenen Schalter-PanelSheet des Orts, ist
##   bedienbar und nimmt am Modal-System (G7-P53, PanelStack) teil —
##   nachgestellt in der echten Post-Konstellation (OrtPost).
## - B4 (Router-Disziplin): ein Routenwechsel AUS dem offenen Settings-
##   Overlay heraus (z. B. „Aktionscodes einlösen“ → Route codes) baut das
##   Overlay ab — der Zielscreen mountet nie wieder DAHINTER.
## - B5 (Push-Race): ein MAIL_NEW-Push VOR dem ersten lazy NetMail.attach
##   der UI verpufft nicht mehr — net_client.gd attacht beim Boot eager,
##   die Ungelesen-Kapsel zeigt nach dem UI-attach „1 neu“.

const PostSzene := preload("res://scenes/city/orte/post.tscn")


## GameState-Double im Post-Format (Muster test_g3_post.FakeGameState).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {
		"city": {},
		"vacation": {"postcards": 2},
		"economy": {"coins": 100, "coinsEarned": 0, "coinsSpent": 0},
		"inventory": {"food": {}, "items": {}},
	}

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## ---------------------------------------------------- B7: Sheet über Sheet


## Die echte Post-Konstellation: Schalter-Sheet offen → Briefkasten öffnen.
## Das MailSheet muss ÜBER dem PanelSheet liegen (späteres Geschwister im
## UI-CanvasLayer, Toasts bleiben obenauf), das oberste Panel im Stack sein,
## Taps schlucken (Dim-Tap schließt ES, nicht den Schalter) und die
## Zurück-Geste (PanelStack.close_top) schließt erst Mail, dann Schalter.
func test_b7_mailsheet_liegt_ueber_dem_schalter_sheet() -> void:
	PanelStack.clear()
	var ort := await _post_booten()
	ort.oeffne_laden()
	await wait_frames(2)
	var panel: PanelSheet = ort.get("_sheet")
	assert_true(panel != null and panel.is_open(), "Schalter-Sheet ist offen (Testaufbau)")
	assert_true(PanelStack.is_top(panel), "Schalter-Sheet ist zunächst das oberste Panel")

	var mail := await _briefkasten_oeffnen(ort)
	assert_true(mail != null, "MailSheet ist gemountet")
	if mail == null:
		ort.queue_free()
		await wait_frames(2)
		PanelStack.clear()
		return
	var layer := ort.get_node("UiLayer") as CanvasLayer
	var toast: Node = ort.get("_toast")
	assert_eq(mail.get_parent(), layer, "MailSheet hängt im UI-CanvasLayer (nicht mehr in _ui)")
	assert_true(
		mail.get_index() > panel.get_index(),
		"MailSheet ist SPÄTERES Geschwister als das Schalter-Sheet (rendert davor)"
	)
	assert_true(toast.get_index() > mail.get_index(), "ToastLayer bleibt obenauf")
	assert_eq(PanelStack.count(), 2, "beide Modals stehen im Panel-Stack")
	assert_true(PanelStack.is_top(mail), "das später geöffnete MailSheet ist das oberste Panel")

	# Backdrop-Disziplin: der Schalter-Backdrop schließt NICHT, solange das
	# MailSheet obenauf liegt (Policy: nur das oberste Panel reagiert).
	panel.call("_on_backdrop_input", _klick())
	await wait_frames(1)
	assert_true(panel.is_open(), "Schalter-Sheet bleibt offen — es ist nicht das oberste Panel")
	assert_true(is_instance_valid(mail), "MailSheet lebt weiter")

	# Echter Tap in die Dim-Ecke: er trifft das VORDERE MailSheet (schließt
	# es), nicht das Schalter-Sheet dahinter — vor dem Fix schluckte der
	# Schalter alle Taps (Befund B7).
	_klick_bei(Vector2(8.0, 8.0))
	await wait_frames(3)
	assert_false(is_instance_valid(mail), "Dim-Tap schließt das vordere MailSheet")
	assert_true(panel.is_open(), "…und NUR dieses — der Schalter bleibt offen")
	assert_true(PanelStack.is_top(panel), "Schalter-Sheet ist wieder das oberste Panel")

	# Zurück-Geste (SceneRouter → PanelStack.close_top): erst Mail, dann
	# Schalter — der EINE gemeinsame Pfad des Modal-Systems.
	var mail2 := await _briefkasten_oeffnen(ort)
	assert_true(mail2 != null, "Briefkasten öffnet erneut")
	assert_true(PanelStack.close_top(), "Zurück schließt das oberste Panel (Mail)")
	assert_true(PanelStack.is_top(panel), "danach ist der Schalter sofort wieder oben")
	await wait_frames(3)
	assert_false(is_instance_valid(mail2), "MailSheet ist abgeräumt")
	assert_true(PanelStack.close_top(), "zweites Zurück schließt den Schalter")
	assert_false(panel.is_open(), "Schalter-Sheet ist zu")

	ort.queue_free()
	await wait_frames(2)
	PanelStack.clear()


## Der Zurück-Pfad über close() respektiert den Compose-Guard (G3/P07):
## mit Entwurf erscheint die Nachfrage-Karte statt Datenverlust; erst das
## bewusste Wegwerfen schließt und räumt den Stack-Eintrag ab.
func test_b7_close_respektiert_compose_guard() -> void:
	PanelStack.clear()
	var sheet := MailSheet.new()
	tree.root.add_child(sheet)
	await wait_frames(2)
	assert_true(PanelStack.is_top(sheet), "MailSheet meldet sich am Modal-Stack an")
	var geschlossen := [0]
	sheet.closed.connect(func() -> void: geschlossen[0] += 1)
	sheet._zeige_compose()
	await wait_frames(1)
	var text: TextEdit = sheet.find_child("BriefText", true, false)
	text.text = "Entwurf in Arbeit"
	assert_true(PanelStack.close_top(), "Zurück-Geste findet das oberste Panel")
	await wait_frames(1)
	assert_true(
		sheet.find_child("VerwerfenDialog", true, false) != null,
		"Nachfrage-Karte statt Datenverlust"
	)
	assert_eq(geschlossen[0], 0, "Sheet lebt weiter")
	assert_true(PanelStack.is_top(sheet), "bleibt bis zur Entscheidung das oberste Panel")
	var verwerfen: Button = sheet.find_child("VerwerfenButton", true, false)
	verwerfen.pressed.emit()
	await wait_frames(2)
	assert_eq(geschlossen[0], 1, "bewusstes Wegwerfen schließt den Briefkasten")
	assert_eq(PanelStack.count(), 0, "Stack-Eintrag ist abgeräumt")
	PanelStack.clear()


## ------------------------------------------------ B4: Settings → Route


## Reiseantritt aus dem offenen Settings-Overlay (Codes/Übernahme): der
## travel_started-Hook von HomeEntry baut das Overlay ab, BEVOR der
## Zielscreen aufgedeckt wird — nichts schluckt mehr dessen Taps.
func test_b4_reise_aus_settings_baut_overlay_ab() -> void:
	var entry := HomeEntry.new()
	var settings: Control = (
		(load("res://scripts/ui/settings_screen.tscn") as PackedScene).instantiate()
	)
	tree.root.add_child(settings)
	await wait_frames(2)
	entry.set("_settings", settings)
	entry.call("_on_travel_started", &"codes", 0)
	assert_true(entry.get("_settings") == null, "HomeEntry-Referenz ist abgeräumt")
	assert_true(settings.is_queued_for_deletion(), "Overlay ist zum Abbau markiert")
	await wait_frames(2)
	assert_false(is_instance_valid(settings), "Settings-Screen ist wirklich weg")
	entry.free()


## ------------------------------------------------ B5: Push vor attach


## MAIL_NEW trifft ein, BEVOR irgendeine UI NetMail.attach gerufen hat —
## dank Eager-Attach beim Boot (net_client.gd) zählt der Push trotzdem;
## der spätere UI-attach liefert dieselbe Instanz mit unread=1 und die
## Ungelesen-Kapsel am Post-Schalter zeigt „1 neu“.
func test_b5_mail_new_push_vor_ui_attach_zaehlt() -> void:
	var stempel := "%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	var identity_pfad := "user://test_w18g4_netid_%s.json" % stempel
	var outbox_pfad := "user://test_w18g4_outbox_%s.json" % stempel
	var net := NetClient.new()
	net.auto_connect = false
	net.build_services = true
	net.identity_path = identity_pfad
	net.outbox_path = outbox_pfad
	net.user_override_path = "user://test_w18g4_override_%s.json" % stempel
	net.config_override = {"host": "fake.test", "port": 1, "tls": false}
	var links: Array[FakeWsLink] = []
	net.link_factory = func() -> FakeWsLink:
		var link := FakeWsLink.new()
		links.append(link)
		return link
	tree.root.add_child(net)
	await wait_frames(1)
	assert_true(
		net.has_meta(NetMail.META_KEY), "NetMail hängt EAGER am Net-Node (Boot, kein UI nötig)"
	)

	net.connect_now()
	links.back().open()
	await wait_frames(3)
	links.back().respond_to("HELLO", "WELCOME", {"friendCode": "GOOBY-B5", "heartbeatSec": 20})
	await wait_frames(3)
	assert_true(net.is_online(), "Handshake fertig (Testaufbau)")

	# Der Buddy-Brief kommt als Push — VOR jedem UI-attach.
	(
		links
		. back()
		. push_server(
			{
				"v": 1,
				"t": "MAIL_NEW",
				"ts": 0,
				"d":
				{
					"mail": {"id": "mail-b5", "from": "GOOBY-B5", "read": false},
					"unread": 1,
				},
			}
		)
	)
	await wait_frames(2)

	# JETZT attacht die UI lazy (Post-Schalter/Telefon) → selbe Instanz.
	var service := NetMail.attach(net)
	assert_true(
		service == net.get_meta(NetMail.META_KEY), "UI-attach liefert die Boot-Instanz zurück"
	)
	assert_eq(service.unread, 1, "MAIL_NEW vor dem UI-attach ist NICHT verpufft")
	var badge := OrtPost.baue_ungelesen_badge(service.unread)
	assert_true(badge.visible, "Ungelesen-Kapsel zeigt den Brief („1 neu“)")
	badge.free()

	net.queue_free()
	await wait_frames(2)
	for pfad: String in [identity_pfad, outbox_pfad]:
		if FileAccess.file_exists(pfad):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(pfad))


## ------------------------------------------------------------- Helfer


func _post_booten() -> OrtPost:
	var ort: OrtPost = PostSzene.instantiate()
	ort.ort_id = "post"
	ort.game_state_override = FakeGameState.new()
	ort.leben_stumm_override = true
	ort.leben_seed_override = 7
	tree.root.add_child(ort)
	await wait_frames(3)
	return ort


## Briefkasten über den echten Schalter-Knopf öffnen und das frisch
## gemountete MailSheet aus dem UI-CanvasLayer fischen.
func _briefkasten_oeffnen(ort: OrtPost) -> MailSheet:
	var knopf := ort.find_child("BriefeOeffnen", true, false) as BaseButton
	assert_true(knopf != null, "Briefkasten-Knopf steht im Schalter-Sheet")
	if knopf == null:
		return null
	knopf.pressed.emit()
	await wait_frames(2)
	var layer := ort.get_node("UiLayer") as CanvasLayer
	for kind in layer.get_children():
		if kind is MailSheet:
			return kind
	return null


func _klick() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


## Echter Klick über den GUI-Weg (root.push_input) an einer Canvas-Position.
func _klick_bei(pos: Vector2) -> void:
	var runter := _klick()
	runter.position = pos
	runter.global_position = pos
	tree.root.push_input(runter, true)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	tree.root.push_input(hoch, true)
