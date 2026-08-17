extends TestCase
## W13C FOTOWERK: Fotomodus-Werkzeuge (Pose/Emotion/Rahmen — Kataloge,
## Rotation, Clip-Fallback, Metadaten im Album-Eintrag, Rig-Anwendung über
## die öffentliche API), prozedurale Rahmen-Geometrie (pur), Gyro-Parallax-
## Mathe (Web-Parität gyroParallax.js: Totzone→Offset geklemmt, Zeiger-
## Fallback, Reduced-Motion=0, Settings-Auflösung) und „Snap A Gooby“
## (Countdown-Statemaschine zeitinjiziert, Besuchs-Selfie schickt das
## Mail-Foto über den W13B-Vertrag — FakeLink + poster-Seam).

## 2026-07-25 12:00:00 UTC — fixer Testzeitpunkt (Zeit IMMER injiziert).
const JETZT_S := 1784980800


## GameState-Double (Muster test_w13b_raumstation): dotted get + update.
class FakeGameState:
	extends RefCounted
	var daten: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init(start: Dictionary = {}) -> void:
		daten = start

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = daten
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(daten)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## Rig-Double: nur die öffentliche Pose/Emotion-API (Duck-Typing wie im
## Fotomodus), zeichnet alle Aufrufe auf.
class FakeRig:
	extends Node3D
	var clips: Array = ["idle", "wave", "hop", "sleep"]
	var gespielt: Array[String] = []
	var override_gesichter: Array = []
	var override_geloescht := 0

	func clip_names() -> Array:
		return clips

	func play_clip(clip: String) -> void:
		gespielt.append(clip)

	func set_expression_override(gesicht: Dictionary, _pose: Dictionary) -> void:
		override_gesichter.append(gesicht)

	func clear_expression_override() -> void:
		override_geloescht += 1


## AppSettings-Double (nur get_setting) für die Settings-Auflösung.
class FakeApp:
	extends Node
	var werte: Dictionary = {}

	func get_setting(key: String, fallback: Variant = null) -> Variant:
		return werte.get(key, fallback)


## UiTheme-Double: nur das reduced_motion-Feld (ThemeService duck-typed).
class FakeUiTheme:
	extends Node
	var reduced_motion := true


## VisitService-Double: Rollen/Codes + Emote-Recorder.
class FakeVisitService:
	extends Node
	var role := "guest"
	var host_code := "GOOBY-HOST"
	var guest_code := "GOOBY-GAST"
	var peer_name := "Lena"
	var peer_gooby_name := "Flauschi"
	var emotes: Array[String] = []

	func send_emote(emote_id: String) -> void:
		emotes.append(emote_id)


## Besuchs-Szene-Double: my_gooby/remote-Felder + visit_service() wie
## VisitScene (duck-typed vom SnapAGooby-Overlay benutzt).
class FakeVisitSzene:
	extends Node
	var my_gooby: Node3D = null
	var remote: Node3D = null
	var dienst: Node = null

	func visit_service() -> Node:
		return dienst


## Gast-Gooby-Double: apply_state-Recorder (RemoteGooby-API).
class FakeRemote:
	extends Node3D
	var ziele: Array = []

	func apply_state(pos: Vector3, anim: String) -> void:
		ziele.append({"pos": pos, "anim": anim})


## „Mein Gooby“-Double: trägt nur das rig-Feld (GoobyHome-Duck).
class FakeGoobyTraeger:
	extends Node3D
	var rig: Node3D = null


## Parallax-Senke wie AcWallpaper (set_parallax_offset-Recorder).
class FakeParallaxZiel:
	extends Control
	var offsets: Array = []

	func set_parallax_offset(offset_px: Vector2) -> void:
		offsets.append(offset_px)


# ---------------------------------------------------------------- Rahmen


func test_rahmen_katalog_und_rotation() -> void:
	var ids := FotoRahmen.ids()
	assert_eq(ids.size(), 7, "6 Rahmen + 'kein'")
	assert_eq(ids[0], "kein", "'kein' startet die Rotation")
	for id in ["polaroid", "herzen", "sterne", "postkarte", "filmstreifen", "stempel"]:
		assert_true(ids.has(id), "Rahmen vorhanden: %s" % id)
		assert_true(FotoRahmen.ist_gueltig(id), "gültig: %s" % id)
	assert_false(FotoRahmen.ist_gueltig("quark"), "unbekannter Rahmen ungültig")
	# Volle Rotation läuft einmal durch alle und wickelt zurück auf Start.
	var aktuell := "kein"
	var gesehen: Array[String] = []
	for _i in ids.size():
		gesehen.append(aktuell)
		aktuell = FotoRahmen.naechster(aktuell)
	assert_eq(aktuell, "kein", "Rotation wickelt zurück")
	assert_eq(gesehen.size(), 7, "alle Rahmen besucht")
	for id in ids:
		assert_true(gesehen.has(id), "Rotation erreicht %s" % id)
	assert_eq(FotoRahmen.naechster("unbekannt"), "kein", "unbekannt → erster")


func test_rahmen_geometrie_pur() -> void:
	var size := Vector2(1000.0, 800.0)
	var masse := FotoRahmen.polaroid_masse(size)
	assert_almost(float(masse["rand"]), 45.0, 0.001, "Polaroid-Rand = 4,5 % Breite")
	assert_almost(float(masse["fuss"]), 112.0, 0.001, "Polaroid-Fuß = 14 % Höhe")
	assert_eq(FotoRahmen.stern_punkte(10.0).size(), 10, "Stern: 10 Punkte")
	assert_eq(FotoRahmen.herz_punkte(10.0).size(), 24, "Herz: 24 Stützpunkte")
	var band := size.x * FotoRahmen.STREU_BAND_ANTEIL
	var a := FotoRahmen.streu(size, band, 40, 42)
	var b := FotoRahmen.streu(size, band, 40, 42)
	assert_eq(a.size(), 40, "Streu liefert die gewünschte Anzahl")
	for i in a.size():
		assert_eq(a[i]["pos"], b[i]["pos"], "Streu deterministisch (Seed 42)")
	var c := FotoRahmen.streu(size, band, 40, 7)
	assert_ne(a[0]["pos"], c[0]["pos"], "anderer Seed → anderes Konfetti")
	# Jeder Eintrag klebt am Rand (eine der 4 Kanten, im Band).
	for eintrag in a:
		var pos: Vector2 = eintrag["pos"]
		var am_rand := (
			pos.y <= band or pos.y >= size.y - band or pos.x <= band or pos.x >= size.x - band
		)
		assert_true(am_rand, "Streu bleibt im Randband: %s" % pos)


# ---------------------------------------------------------------- Werkzeuge


func test_werkzeuge_kataloge_und_rotation() -> void:
	assert_eq(FotoWerkzeuge.pose_ids().size(), 6, "frei + 5 Posen")
	assert_eq(FotoWerkzeuge.emotion_ids().size(), 13, "keine + 12 W12-Emotionen")
	for id in FeelEmotions.EMOTIONEN:
		assert_true(FotoWerkzeuge.emotion_ids().has(id), "W12-Emotion wählbar: %s" % id)
	var w := FotoWerkzeuge.new()
	assert_eq(w.als_meta(), {}, "Defaults erzeugen KEINE Metadaten")
	w.waehle_pose("quark")
	assert_eq(w.pose_id, "frei", "unbekannte Pose ignoriert")
	w.waehle_emotion("freude")
	w.waehle_pose("winken")
	w.waehle_rahmen("polaroid")
	var meta := w.als_meta()
	assert_eq(meta.get("pose"), "winken", "Pose wandert in die Metadaten")
	assert_eq(meta.get("emotion"), "freude", "Emotion wandert in die Metadaten")
	assert_eq(meta.get("rahmen"), "polaroid", "Rahmen wandert in die Metadaten")
	# Rotation: einmal durchtippen wickelt zurück auf den Start.
	w.zuruecksetzen()
	for _i in FotoWerkzeuge.pose_ids().size():
		w.naechste_pose()
	assert_eq(w.pose_id, "frei", "Pose-Rotation wickelt zurück")
	for _i in FotoWerkzeuge.emotion_ids().size():
		w.naechste_emotion()
	assert_eq(w.emotion_id, "keine", "Emotion-Rotation wickelt zurück")
	for _i in FotoRahmen.ids().size():
		w.naechster_rahmen()
	assert_eq(w.rahmen_id, "kein", "Rahmen-Rotation wickelt zurück")


func test_pose_und_selfie_clip_fallback() -> void:
	assert_eq(FotoWerkzeuge.pose_clip("frei", ["wave"]), "", "frei = kein Eingriff")
	assert_eq(FotoWerkzeuge.pose_clip("winken", ["wave", "sit"]), "wave", "Clip vorhanden")
	assert_eq(FotoWerkzeuge.pose_clip("sitzen", ["sit"]), "sit", "sit vorhanden")
	assert_eq(
		FotoWerkzeuge.pose_clip("jubeln", ["wave", "sit"]),
		"wave",
		"fehlender Clip → wave-Fallback (Battleship-Tomaten-Muster)"
	)
	assert_eq(FotoWerkzeuge.selfie_clip(["phone_up", "wave"]), "phone_up", "phone_up bevorzugt")
	assert_eq(FotoWerkzeuge.selfie_clip(["wave", "idle"]), "wave", "Selfie-Fallback wave")


func test_merke_foto_mit_werkzeug_metadaten() -> void:
	var gs := FakeGameState.new({"city": {"fotos": []}})
	var w := FotoWerkzeuge.new()
	w.waehle_pose("sitzen")
	w.waehle_rahmen("sterne")
	var extra := w.als_meta()
	extra["selfie"] = true
	var liste := FotoModus.merke_foto(gs, "user://fotos/x.png", JETZT_S * 1000, "funkelpark", extra)
	assert_eq(liste.size(), 1, "ein Album-Eintrag")
	var eintrag: Dictionary = liste[0]
	assert_eq(eintrag.get("pfad"), "user://fotos/x.png", "Pfad gespeichert")
	assert_eq(eintrag.get("ort"), "funkelpark", "Ort gespeichert")
	assert_eq(eintrag.get("pose"), "sitzen", "Werkzeug-Zustand mitgeknipst: Pose")
	assert_eq(eintrag.get("rahmen"), "sterne", "Werkzeug-Zustand mitgeknipst: Rahmen")
	assert_false(eintrag.has("emotion"), "Default-Emotion bleibt schlank")
	assert_eq(eintrag.get("selfie"), true, "Selfie-Flag mitgeknipst")
	assert_true(gs.slices_notified.has("city"), "city-Slice benachrichtigt")


func test_fotomodus_wendet_pose_emotion_und_rahmen_an() -> void:
	var gs := FakeGameState.new({"city": {"fotos": []}})
	var rig := FakeRig.new()
	tree.root.add_child(rig)
	var modus := FotoModus.new()
	modus.gs = gs
	modus.rig_override = rig
	modus.uhr_unix_s = func() -> int: return JETZT_S
	tree.root.add_child(modus)
	await wait_frames(1)
	# Mit Gooby im Bild gibt es alle drei Werkzeug-Reihen + Selfie-Knopf.
	for art in ["pose", "emotion", "rahmen"]:
		assert_true(modus._werkzeug_chips.has(art), "Werkzeug-Reihe existiert: %s" % art)
	assert_true(modus._selfie_button != null, "Selfie-Knopf existiert")
	# Pose: winken → wave-Clip über die öffentliche Rig-API.
	modus._on_chip("pose", "winken")
	assert_true(rig.gespielt.has("wave"), "Pose spielt den Rig-Clip")
	# Emotion: freude wird über die Override-API GEHALTEN (kein Timer).
	modus._on_chip("emotion", "freude")
	assert_eq(rig.override_gesichter.size(), 1, "Emotion setzt den Override")
	var def := FeelEmotions.def_of("freude")
	assert_eq(rig.override_gesichter[0], def["gesicht"], "Override = W12-Gesicht")
	# Rahmen: Auswahl wirkt live aufs Sucher-Overlay (wird mitgeknipst,
	# weil das Overlay beim Auslösen sichtbar bleibt).
	modus._on_chip("rahmen", "polaroid")
	assert_eq(modus._rahmen_overlay.rahmen_id, "polaroid", "Rahmen live im Sucher")
	assert_false(
		str(modus._rahmen_overlay.kontext.get("datum", "")).is_empty(),
		"Polaroid-Kontext trägt das (injizierte) Datum"
	)
	# Schließen räumt den Gooby auf: Override weg, zurück zu idle.
	modus.schliessen()
	assert_eq(rig.override_geloescht, 1, "Override beim Schließen gelöscht")
	assert_eq(rig.gespielt.back(), "idle", "Pose beim Schließen zurückgesetzt")
	await wait_frames(1)
	rig.queue_free()
	await wait_frames(1)


# ---------------------------------------------------------------- Parallax


func test_parallax_mathe_pur() -> void:
	# Totzone: ±2° ohne Sprung (Web deadzoneDegrees).
	assert_almost(GyroParallax.totzone(1.5), 0.0, 1e-9, "in der Totzone → 0")
	assert_almost(GyroParallax.totzone(3.0), 1.0, 1e-9, "Totzone abgezogen")
	assert_almost(GyroParallax.totzone(-5.0), -3.0, 1e-9, "Vorzeichen bleibt")
	# Neutral = keine Auslenkung.
	assert_eq(GyroParallax.offset_m(0.0, 0.0), Vector2.ZERO, "neutral → 0")
	# Klemmen: riesige Winkel → ±MAX (0,12 m / 0,08 m, Web-Parität).
	# Vector2-Komponenten sind float32 → eps 1e-6 statt bit-genau.
	var extrem := GyroParallax.offset_m(90.0, 90.0)
	assert_almost(extrem.x, GyroParallax.MAX_X_M, 1e-6, "x klemmt bei 0,12 m")
	assert_almost(extrem.y, -GyroParallax.MAX_Y_M, 1e-6, "beta+ kippt die Kamera runter")
	# 5° gamma → (5−2)·0,008 = 0,024 m.
	assert_almost(GyroParallax.offset_m(0.0, 5.0).x, 0.024, 1e-6, "Empfindlichkeit 0,008 m/°")
	# Neutral-Pose verschiebt den Nullpunkt.
	assert_eq(GyroParallax.offset_m(10.0, 5.0, Vector2(10.0, 5.0)), Vector2.ZERO, "Neutral-Abzug")
	# Zeiger-Fallback: Bildschirmrand → exakt ±0,06 m (Web POINTER_EDGE).
	assert_almost(GyroParallax.zeiger_offset_m(1.0, 0.0).x, 0.06, 1e-6, "Rand rechts → +0,06")
	assert_almost(GyroParallax.zeiger_offset_m(-1.0, 0.0).x, -0.06, 1e-6, "Rand links → −0,06")
	assert_almost(GyroParallax.zeiger_offset_m(0.0, 1.0).y, 0.06, 1e-6, "oben → +0,06")
	assert_almost(GyroParallax.zeiger_offset_m(9.0, 0.0).x, 0.06, 1e-6, "Eingang geklemmt")
	# Glättung: dt=0 → 0; großes dt → praktisch 1; monoton.
	assert_almost(GyroParallax.glaettungs_alpha(0.0, 0.15), 0.0, 1e-9, "dt 0 → alpha 0")
	assert_true(GyroParallax.glaettungs_alpha(10.0, 0.15) > 0.999, "großes dt → alpha ≈ 1")
	var a1 := GyroParallax.glaettungs_alpha(0.016, 0.15)
	var a2 := GyroParallax.glaettungs_alpha(0.1, 0.15)
	assert_true(a1 > 0.0 and a2 > a1, "alpha wächst mit dt")
	# Neigung aus dem Gravitationsvektor: Portrait-Ruhelage = (0, 0).
	assert_eq(GyroParallax.neigung_grad(Vector3(0.0, -1.0, 0.0)), Vector2.ZERO, "Ruhelage")
	assert_true(GyroParallax.neigung_grad(Vector3(0.5, -1.0, 0.0)).y > 0.0, "Roll rechts → gamma+")


func test_parallax_setting_und_reduced_motion() -> void:
	# Settings-Auflösung pur: explizites Flag gewinnt, sonst migriertes gyro.
	assert_false(GyroParallax.setting_aktiv(null, null), "ohne Quellen: aus")
	var gs_an := FakeGameState.new({"settings": {"gyro": true}})
	assert_true(GyroParallax.setting_aktiv(null, gs_an), "migriertes settings.gyro als Fallback")
	var app := FakeApp.new()
	app.werte["game.parallax"] = false
	assert_false(GyroParallax.setting_aktiv(app, gs_an), "explizites Flag schlägt Fallback")
	app.werte["game.parallax"] = true
	assert_true(GyroParallax.setting_aktiv(app, null), "explizit an")
	# Runtime: Reduced Motion zwingt den Ziel-Offset auf 0 — auch wenn das
	# Setting an ist (FakeUiTheme/FakeApp als /root-Duck-Doubles).
	app.name = "AppSettings"
	tree.root.add_child(app)
	var ui := FakeUiTheme.new()
	ui.name = "UiTheme"
	tree.root.add_child(ui)
	var runtime := GyroParallax.new()
	tree.root.add_child(runtime)
	assert_eq(runtime._ziel_offset_m(0.016), Vector2.ZERO, "Reduced Motion → 0")
	ui.reduced_motion = false
	app.werte["game.parallax"] = false
	assert_eq(runtime._ziel_offset_m(0.016), Vector2.ZERO, "Setting aus → 0")
	# Verteilung: registrierte Ziele bekommen den skalierten px-Offset.
	var ziel := FakeParallaxZiel.new()
	tree.root.add_child(ziel)
	runtime.melde_an(ziel, 0.5)
	assert_eq(runtime.ziel_anzahl(), 1, "Ziel registriert")
	runtime.melde_an(ziel, 0.5)
	assert_eq(runtime.ziel_anzahl(), 1, "Doppel-Anmeldung dedupliziert")
	runtime._verteile(Vector2(10.0, 4.0))
	assert_eq(ziel.offsets.back(), Vector2(5.0, 2.0), "Offset × Stärke gepusht")
	runtime.melde_ab(ziel)
	assert_eq(runtime.ziel_anzahl(), 0, "abgemeldet")
	for node: Node in [app, ui, runtime, ziel]:
		node.queue_free()
	await wait_frames(1)


# ---------------------------------------------------------------- Selfie


func test_selfie_countdown_statemaschine_zeitinjiziert() -> void:
	# Grenzen bewusst mit Überhang getaktet (Float-Summen treffen die
	# exakte Kante nicht bit-genau).
	var ablauf := SnapAGooby.Ablauf.new()
	assert_eq(ablauf.phase, "pose", "startet im Pose-Beat")
	assert_eq(ablauf.takt(0.79), [], "Pose-Beat läuft noch")
	assert_eq(ablauf.takt(0.02), ["zeige_3"], "0,8 s → Countdown 3")
	assert_eq(ablauf.takt(0.9), [], "Sekunde noch nicht um")
	assert_eq(ablauf.takt(0.11), ["zeige_2"], "→ 2")
	assert_eq(ablauf.takt(1.0), ["zeige_1"], "→ 1")
	assert_eq(ablauf.takt(1.0), ["ausloesen"], "1 → Klick")
	assert_eq(ablauf.phase, "fertig", "Statemaschine fertig")
	assert_eq(ablauf.takt(99.0), [], "fertig bleibt fertig")
	# Ein riesiger Takt liefert alle Ereignisse in Reihenfolge (kein Frame-Verlust).
	var eilig := SnapAGooby.Ablauf.new()
	assert_eq(
		eilig.takt(60.0),
		["zeige_3", "zeige_2", "zeige_1", "ausloesen"],
		"großes dt spult sauber durch"
	)


func test_besuchs_selfie_posiert_knipst_und_sendet_mail_foto() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	# NetMail mit Temp-Outbox als Meta parken — SnapAGoobys attach()-Aufruf
	# findet dann DIESE Instanz (kein user://outbox.json-Schmutz).
	var mail := NetMail.new()
	var outbox_pfad := "user://test_w13c_outbox_%d.json" % Time.get_ticks_usec()
	mail.setup(rig.client, NetOutbox.new(outbox_pfad))
	rig.client.set_meta(NetMail.META_KEY, mail)
	var posts: Array = []
	mail.poster = func(url: String, _headers: PackedStringArray, body: String) -> Variant:
		posts.append({"url": url, "body": body})
		return {"ok": true, "id": "mail-selfie", "sentToday": 1, "dailyLimit": 20}

	# Fixtures: Mini-PNG als „Aufnahme“, Besuchs-Szene-Double (Gast-Rolle).
	var foto_pfad := "user://test_selfie_%d.png" % Time.get_ticks_usec()
	var bild := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	bild.fill(Color(1.0, 0.5, 0.2))
	assert_eq(bild.save_png(foto_pfad), OK, "Fixture-PNG geschrieben")
	var szene := FakeVisitSzene.new()
	szene.dienst = FakeVisitService.new()
	szene.add_child(szene.dienst)
	tree.root.add_child(szene)

	var gs := FakeGameState.new({"city": {"fotos": []}})
	var snap := SnapAGooby.starte(szene, gs)
	snap.uhr_unix_s = func() -> int: return JETZT_S
	snap.foto_quelle = func() -> String: return foto_pfad
	snap.net_override = rig.client
	await wait_frames(1)
	# Posieren beim Start: Relay-Emote ging raus (Peer sieht die Pose).
	assert_true(
		(szene.dienst as FakeVisitService).emotes.has(SnapAGooby.RELAY_EMOTE),
		"Peer bekommt das Relay-Emote"
	)
	# Klick: knipst (injizierte Quelle), Album-Eintrag + Mail-Foto.
	var fertig_pfad: Array = []
	snap.fertig.connect(func(pfad: String) -> void: fertig_pfad.append(pfad))
	await snap._knipse_und_sende()
	assert_eq(fertig_pfad, [foto_pfad], "fertig-Signal mit dem Aufnahme-Pfad")
	var fotos: Array = gs.get_value("city.fotos", [])
	assert_eq(fotos.size(), 1, "Selfie landet im eigenen Album")
	assert_eq((fotos[0] as Dictionary).get("selfie"), true, "Album-Eintrag als Selfie markiert")
	assert_eq((fotos[0] as Dictionary).get("emote"), "snap_a_gooby", "Emote vermerkt")
	assert_eq(posts.size(), 1, "genau EIN Mail-Foto-POST")
	assert_true(str(posts[0]["url"]).ends_with("/api/mail"), "W13B-Mail-Endpoint")
	var body: Dictionary = JSON.parse_string(str(posts[0]["body"]))
	assert_eq(body.get("to"), "GOOBY-HOST", "als Gast geht die Kopie an den Host")
	assert_false(str(body.get("photoB64", "")).is_empty(), "Foto als photoB64 im Vertrag")
	szene.queue_free()
	await rig.shutdown(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(foto_pfad))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outbox_pfad))
	await wait_frames(1)


func test_besuchs_selfie_posiert_beide_goobys() -> void:
	# Eigenes Rig hält das Handy (phone_up fehlt → wave-Fallback), der
	# Gast-Gooby hoppelt neben den eigenen Gooby ins Bild.
	var szene := FakeVisitSzene.new()
	tree.root.add_child(szene)
	var traeger := FakeGoobyTraeger.new()
	var rig := FakeRig.new()
	rig.clips = ["idle", "wave"]
	traeger.rig = rig
	traeger.add_child(rig)
	szene.add_child(traeger)
	traeger.position = Vector3(2.0, 0.0, 1.0)
	var remote := FakeRemote.new()
	szene.add_child(remote)
	szene.my_gooby = traeger
	szene.remote = remote
	var snap := SnapAGooby.new()
	snap.gs = FakeGameState.new({"city": {"fotos": []}})
	snap._szene = szene
	szene.add_child(snap)
	await wait_frames(1)
	assert_eq(rig.gespielt, ["wave"] as Array[String], "phone_up fehlt → wave-Fallback")
	assert_eq(remote.ziele.size(), 1, "Gast-Gooby bekommt ein Hop-Ziel")
	var ziel: Dictionary = remote.ziele[0]
	assert_eq(ziel.get("anim"), "hop", "Gast hoppelt ins Bild")
	assert_eq(
		ziel.get("pos"),
		traeger.global_position + SnapAGooby.GAST_VERSATZ,
		"Ziel liegt neben dem eigenen Gooby"
	)
	szene.queue_free()
	await wait_frames(1)
