extends TestCase
## W14/UIKERN — Kern-Bausteine: Haptik-Gate + Impulspläne (pur),
## AcBubble-Warteschlange (pur, max. 2 gleichzeitig), UiAnchors-Ausweich-
## Geometrie (pur) und Node-Smokes für AcBubble (Zeit INJIZIERT, kein
## OS-Takt), Notify-Banner-Zone und SquishButton-Press-Scale.


## Settings-Double fürs Haptik-Gate (get_setting/value_of wie AppSettings).
class SettingsDouble:
	extends RefCounted

	var werte: Dictionary = {}
	var stufe := "normal"

	func get_setting(key: String, default_value: Variant = null) -> Variant:
		return werte.get(key, default_value)

	func value_of(_key: String) -> Variant:
		return stufe


func test_haptik_plaene_pur() -> void:
	assert_eq(Haptics.plan("tap"), [10] as Array[int], "tap = 10 ms")
	assert_eq(Haptics.plan("success"), [8, 8] as Array[int], "success = Doppelimpuls 8+8 ms")
	assert_eq(Haptics.plan("warn"), [40] as Array[int], "warn = 40 ms")
	assert_eq(Haptics.plan("unbekannt"), [10] as Array[int], "Fallback = tap")
	# W16 F11: Stärke-Stufen dezent/stark skalieren die Impulsdauern.
	assert_eq(Haptics.plan("tap", "dezent"), [6] as Array[int], "dezent = Faktor 0.6")
	assert_eq(Haptics.plan("warn", "stark"), [64] as Array[int], "stark = Faktor 1.6")
	assert_eq(Haptics.plan("success", "stark"), [13, 13] as Array[int], "stark = beide Impulse")
	assert_eq(Haptics.plan("success", "dezent"), [5, 5] as Array[int], "dezent = beide Impulse")
	assert_eq(Haptics.plan("tap", "normal"), [10] as Array[int], "normal = Faktor 1.0")
	assert_eq(Haptics.plan("tap", "mondphase"), [10] as Array[int], "unbekannte Stufe = 1.0")


func test_haptik_gate_pur() -> void:
	var s := SettingsDouble.new()
	assert_true(Haptics.is_enabled(s), "game.haptik fehlt = Default AN")
	s.werte[Haptics.SETTING_KEY] = false
	assert_false(Haptics.is_enabled(s), "game.haptik = false blockt")
	s.werte[Haptics.SETTING_KEY] = true
	assert_true(Haptics.is_enabled(s), "game.haptik = true erlaubt")
	s.stufe = "aus"
	assert_false(Haptics.is_enabled(s), "Alt-Stufe controls.haptics=aus bleibt still")


func test_bubble_warteschlange_pur() -> void:
	var q := AcBubble.Warteschlange.new()
	assert_true(q.anmelden("a"), "1. Blase zeigt sofort")
	assert_true(q.anmelden("b"), "2. Blase zeigt sofort (max 2)")
	assert_false(q.anmelden("c"), "3. Blase wartet")
	assert_eq(q.aktiv.size(), 2, "zwei aktiv")
	assert_eq(q.wartend.size(), 1, "eine wartet")
	assert_eq(q.abmelden("a"), "c", "Nachrücker kommt in Reihenfolge")
	assert_eq(q.aktiv.size(), 2, "Slot bleibt voll besetzt")
	assert_eq(q.abmelden("fremd"), null, "Unbekannte abmelden fördert nichts")
	assert_eq(q.abmelden("b"), null, "keine Wartenden mehr")
	assert_eq(q.abmelden("c"), null)
	assert_eq(q.aktiv.size(), 0, "alles abgemeldet")


func test_anker_dodge_pur() -> void:
	var frei := UiAnchors.dodge(Rect2(0, 500, 100, 40), [], UiAnchors.ZONE_BOTTOM)
	assert_eq(frei.position.y, 500.0, "ohne Blocker unverändert")
	var blocker := Rect2(0, 480, 200, 60)
	var drueber := UiAnchors.dodge(Rect2(0, 500, 100, 40), [blocker], UiAnchors.ZONE_BOTTOM)
	assert_almost(drueber.position.y, 480.0 - 8.0 - 40.0, 1e-4, "bottom rutscht ÜBERS Rect (+8)")
	var drunter := UiAnchors.dodge(Rect2(0, 470, 100, 40), [blocker], UiAnchors.ZONE_TOP)
	assert_almost(drunter.position.y, 540.0 + 8.0, 1e-4, "top rutscht UNTERS Rect (+8)")
	var kein_schnitt := UiAnchors.dodge(Rect2(0, 100, 100, 40), [blocker], UiAnchors.ZONE_BOTTOM)
	assert_eq(kein_schnitt.position.y, 100.0, "kein Schnitt = keine Bewegung")
	var zwei := [Rect2(0, 400, 200, 40), Rect2(0, 340, 200, 40)]
	var gestapelt := UiAnchors.dodge(Rect2(0, 410, 100, 30), zwei, UiAnchors.ZONE_BOTTOM)
	assert_true(gestapelt.position.y < 340.0 - 30.0, "mehrere Blocker werden ALLE übersprungen")


func test_anker_reserve_release() -> void:
	UiAnchors.reset_for_tests()
	var a := Control.new()
	var b := Control.new()
	UiAnchors.reserve("top", a)
	UiAnchors.reserve("top", a)
	UiAnchors.reserve("top", b)
	assert_eq(UiAnchors.occupants("top").size(), 2, "reserve ist idempotent")
	UiAnchors.release("top", a)
	assert_eq(UiAnchors.occupants("top").size(), 1, "release trägt aus")
	b.free()
	assert_eq(UiAnchors.occupants("top").size(), 0, "tote Nodes werden geprunt")
	a.free()
	UiAnchors.reset_for_tests()


func test_acbubble_queue_und_autohide_mit_injizierter_zeit() -> void:
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var layer := Control.new()
	layer.size = Vector2(1280, 720)
	tree.root.add_child(layer)
	var b1 := AcBubble.show_bubble(layer, "Hallo!", {"dauer_s": 1.0, "tail": false})
	b1.auto_zeit = false
	var b2 := AcBubble.show_bubble(layer, "Zweite Blase", {"dauer_s": 9.0})
	b2.auto_zeit = false
	var b3 := AcBubble.show_bubble(layer, "Dritte Blase", {"stil": "witz", "dauer_s": 9.0})
	b3.auto_zeit = false
	assert_true(b1.is_active(), "Blase 1 aktiv")
	assert_eq(b1.current_line(), "Hallo!", "current_line = voller Text")
	assert_true(b2.is_active(), "Blase 2 aktiv (max 2 gleichzeitig)")
	assert_false(b3.is_active(), "Blase 3 wartet")
	assert_false(b3.visible, "wartende Blase bleibt unsichtbar")
	# Zeit injizieren: Typewriter zu Ende tippen + Standzeit überschreiten.
	for _i in 80:
		b1.advance_time(0.1)
	assert_false(b1.is_active(), "Blase 1 blendet nach dauer_s aus")
	assert_true(b3.is_active(), "Blase 3 rückt sofort nach")
	assert_true(b3.visible, "Nachrücker wird sichtbar")
	layer.queue_free()
	await wait_frames(2)
	UiAnchors.reset_for_tests()
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func test_acbubble_typewriter_tippt_zeichenweise() -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var layer := Control.new()
	layer.size = Vector2(1280, 720)
	tree.root.add_child(layer)
	var bubble := AcBubble.show_bubble(layer, "Zwölf Zeichen", {"dauer_s": 9.0})
	bubble.auto_zeit = false
	var label := bubble.get_node("Kapsel/BubbleText") as Label
	assert_eq(label.visible_characters, 0, "Typewriter startet bei 0 Zeichen")
	# 1 Tick à 1/RATE = exakt 1 Zeichen (DialogTypewriter-Kontrakt, W13B).
	bubble.advance_time(1.0 / GoobyVoice.RATE)
	assert_eq(label.visible_characters, 1, "ein Tick = ein Zeichen")
	bubble.advance_time(60.0)
	assert_eq(label.visible_characters, -1, "fertig getippt = alles sichtbar")
	layer.queue_free()
	await wait_frames(2)
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func test_acbubble_ersetze_text_statt_stapeln() -> void:
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var layer := Control.new()
	layer.size = Vector2(1280, 720)
	tree.root.add_child(layer)
	var bubble := AcBubble.show_bubble(layer, "Erster Spruch", {"dauer_s": 2.0})
	bubble.auto_zeit = false
	bubble.advance_time(5.0)  # Typewriter fertig
	bubble.advance_time(1.9)  # 1.9 s Standzeit — kurz vor dem Auto-Hide
	var kinder := layer.get_child_count()
	assert_true(bubble.ersetze_text("Zweiter Spruch"), "lebende Blase nimmt neuen Text")
	assert_eq(layer.get_child_count(), kinder, "ersetze_text erzeugt KEINEN neuen Node")
	assert_eq(bubble.current_line(), "Zweiter Spruch", "Text ist ersetzt")
	bubble.advance_time(5.0)  # neuer Typewriter fertig
	bubble.advance_time(0.3)  # erst 0.3 s Standzeit — alte 1.9 s zählen NICHT
	assert_true(bubble.is_active(), "Standzeit wurde beim Ersetzen zurückgesetzt")
	bubble.advance_time(60.0)
	assert_false(bubble.is_active(), "ersetzt + Standzeit voll = blendet aus")
	assert_false(bubble.ersetze_text("Dritter"), "ausblendende Blase lehnt ab")
	layer.queue_free()
	await wait_frames(2)
	AcBubble.warteschlange = AcBubble.Warteschlange.new()


func test_notify_banner_reserviert_top_zone() -> void:
	UiAnchors.reset_for_tests()
	var svc := NotificationService.new()
	tree.root.add_child(svc)
	await tree.process_frame
	svc.show_banner("Titel", "Text")
	assert_true(svc.is_banner_visible(), "Banner steht")
	assert_eq(UiAnchors.occupants("top").size(), 1, "Banner belegt die top-Zone")
	svc.free()
	assert_eq(UiAnchors.occupants("top").size(), 0, "Zone nach Banner-Ende frei")
	UiAnchors.reset_for_tests()


func test_squish_button_press_und_release() -> void:
	var knopf := SquishButton.new()
	tree.root.add_child(knopf)
	await tree.process_frame
	knopf.button_down.emit()
	var gedrueckt := await wait_until(
		func() -> bool: return knopf.scale.x <= AcTokens.PRESS_SCALE + 0.005, 3000
	)
	assert_true(gedrueckt, "Press erreicht PRESS_SCALE (0.94)")
	knopf.button_up.emit()
	var zurueck := await wait_until(func() -> bool: return absf(knopf.scale.x - 1.0) < 0.02, 3000)
	assert_true(zurueck, "Release federt (mit Overshoot) auf 1.0 zurück")
	knopf.queue_free()
	await wait_frames(2)
