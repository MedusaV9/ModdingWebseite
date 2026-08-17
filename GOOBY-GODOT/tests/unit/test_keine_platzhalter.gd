extends TestCase
## FERTIG-1: Vertrags-Tests „keine erreichbaren Bald-Platzhalter“.
## Der User hat sich über „Kommt bald“-Texte beschwert. Die vier verbliebenen
## Platzhalter-Strings sind reine DEFENSIV-Guards; diese Tests beweisen, dass
## ihre Einstiege unerreichbar sind — und schlagen an, sobald jemand einen
## neuen toten Eintrag anlegt (Stub-Ort, coming_soon-Spiel, HUD-Aktion ohne
## Handler, fehlende Social-Szene, fehlender UpdateManager).

const CITY_MAP_JSON := "res://scripts/city/data/city_map.json"
const SOCIAL_SCENE := "res://scripts/ui/social/social_screen.tscn"

## Vertrag: jede HUD-Aktion aus Hud.ACTIONS hat einen Handler in
## home_entry.gd (`bau`/`reise` inline, Rest via _dispatch_to_screens).
## Neue Aktion? → Handler bauen UND hier eintragen, sonst faellt der Test —
## genau das verhindert, dass `home.aktion_bald` je wieder erreichbar wird.
const BEHANDELTE_AKTIONEN: Array[StringName] = [
	&"igohbie",
	&"bau",
	&"reise",
	&"arcade",
	&"album",
	&"profil",
	&"wardrobe",
	&"ikea",
	&"gestalten",
	&"quests",
]


## Guard `city.ort.bald_offen` (city_scene.gd): unerreichbar, solange KEIN
## Ort ein Stub ist und jede Ort-Szene wirklich existiert.
func test_stadt_orte_haben_echte_szenen() -> void:
	var raw := FileAccess.get_file_as_string(CITY_MAP_JSON)
	var json := JSON.new()
	assert_eq(json.parse(raw), OK, "city_map.json muss parsen")
	var orte: Array = (json.data as Dictionary).get("orte", [])
	assert_true(orte.size() >= 10, "Stadtkarte hat alle Orte")
	for ort: Dictionary in orte:
		var id := str(ort.get("id", "?"))
		assert_ne(str(ort.get("typ", "")), "stub", "Ort '%s' darf kein Stub sein" % id)
		var szene := str(ort.get("szene", ""))
		assert_false(szene.is_empty(), "Ort '%s' braucht eine Szene" % id)
		assert_true(ResourceLoader.exists(szene), "Szene von '%s' fehlt: %s" % [id, szene])


## Guard `mg.arcade.coming_soon` (arcade_screen.gd): unerreichbar, solange
## kein registriertes Minispiel als coming_soon markiert ist.
func test_kein_minispiel_ist_coming_soon() -> void:
	var alle := MinigameRegistry.all_games()
	assert_true(alle.size() >= 36, "Arcade hat alle 36 Spiele (hat %d)" % alle.size())
	for game: Dictionary in alle:
		assert_false(
			bool(game.get("coming_soon", false)),
			"Spiel '%s' ist coming_soon — fertig bauen oder austragen" % str(game.get("id", "?"))
		)


## Guard `phone.freunde.fehlt` (social_apps.gd): unerreichbar, solange die
## Social-Szene existiert.
func test_social_screen_existiert() -> void:
	assert_true(ResourceLoader.exists(SOCIAL_SCENE), "social_screen.tscn fehlt")


## Guard `home.aktion_bald` (home_entry.gd): unerreichbar, solange jede
## Aktion aus Hud.ACTIONS im Behandelt-Vertrag steht (und umgekehrt).
func test_hud_aktionen_alle_behandelt() -> void:
	var ids: Array[StringName] = []
	for action: Dictionary in Hud.ACTIONS:
		ids.append(action["id"])
	for id in ids:
		assert_true(
			BEHANDELTE_AKTIONEN.has(id),
			"HUD-Aktion '%s' hat keinen Handler-Vertrag — home_entry.gd erweitern" % id
		)
	for id in BEHANDELTE_AKTIONEN:
		assert_true(ids.has(id), "Vertrags-Aktion '%s' existiert nicht mehr im HUD" % id)


## Die Screen-Handler existieren wirklich und ignorieren fremde Aktionen
## (sonst waere der Behandelt-Vertrag oben nur Papier).
func test_screen_handler_ignorieren_fremde_aktionen() -> void:
	assert_false(ArcadeScreen.handle_hud_action(&"__nie__"), "ArcadeScreen")
	assert_false(AlbumScreen.handle_hud_action(&"__nie__"), "AlbumScreen")
	assert_false(WardrobeScreen.handle_hud_action(&"__nie__"), "WardrobeScreen")
	assert_false(IkeaScreen.handle_hud_action(&"__nie__"), "IkeaScreen")
	assert_false(CustomizeScreen.handle_hud_action(&"__nie__"), "CustomizeScreen")
	assert_false(DailyQuestService.handle_hud_action(&"__nie__"), "DailyQuestService")
	assert_false(ProfilScreen.handle_hud_action(&"__nie__"), "ProfilScreen")
	assert_false(PhoneShell.handle_hud_action(&"__nie__", null, null), "PhoneShell")


## Guard `settings.update_bald` (settings_screen.gd): unerreichbar, solange
## der UpdateManager-Autoload registriert ist und Updates pruefen kann.
func test_update_manager_ist_registriert() -> void:
	assert_true(
		ProjectSettings.has_setting("autoload/UpdateManager"),
		"UpdateManager-Autoload fehlt in project.godot"
	)
	var script := load("res://scripts/updates/update_service.gd")
	var hat := false
	for m: Dictionary in (script as GDScript).get_script_method_list():
		if str(m.get("name", "")) == "check_for_updates":
			hat = true
	assert_true(hat, "UpdateManager.check_for_updates fehlt")
