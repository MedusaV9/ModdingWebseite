extends TestCase
## M2/ORTE — POW! (Doc E §2.3, USER §E61): die drei TAGESANGEBOTE sind
## deterministisch aus dem Kalendertag gezogen (gleicher Tag ⇒ gleiche Ware,
## auf jedem Gerät, ohne Server), und die KAMERA ist das Gate für Fotomodus
## und IGohbie-Kamera-App.

## 2026-07-25 12:00:00 UTC — Samstag (der Wochenmarkt-Tag).
const SAMSTAG_MITTAG := 1784980800


class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {}, "economy": {"coins": 500}, "inventory": {"items": {}, "food": {}}
	}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func test_sortiment_datei_ist_vollstaendig() -> void:
	assert_true(PowAngebote.pool().size() >= PowAngebote.SLOTS, "Pool größer als die Slots")
	var kamera := PowAngebote.kamera_ware()
	assert_false(kamera.is_empty(), "Kamera-Ware fehlt im Sortiment")
	assert_eq(str(kamera.get("inventar", "")), PowAngebote.KAMERA_ITEM, "Kamera-Inventar-Key")
	assert_true(int(kamera.get("preis", 0)) > 0, "Kamera hat einen Preis")
	for ware: Dictionary in PowAngebote.pool():
		assert_ne(str(ware.get("id", "")), "", "Pool-Ware ohne id")
		assert_true(int(ware.get("preis", 0)) > 0, "Pool-Ware ohne Preis: %s" % ware.get("id"))


func test_angebote_sind_deterministisch() -> void:
	var seed_wert := PowAngebote.tag_seed(SAMSTAG_MITTAG)
	var a := PowAngebote.angebote(seed_wert)
	var b := PowAngebote.angebote(seed_wert)
	assert_eq(a.size(), PowAngebote.SLOTS, "drei Slots")
	assert_eq(a, b, "gleicher Tag ⇒ gleiche Angebote")


func test_angebote_wechseln_mit_dem_tag() -> void:
	var heute := PowAngebote.angebote(PowAngebote.tag_seed(SAMSTAG_MITTAG))
	var morgen := PowAngebote.angebote(PowAngebote.tag_seed(SAMSTAG_MITTAG + 86400))
	assert_ne(heute, morgen, "am nächsten Tag stehen andere Sachen im Regal")


func test_tag_seed_haengt_nur_am_kalendertag() -> void:
	var morgens := PowAngebote.tag_seed(SAMSTAG_MITTAG - 6 * 3600)
	var abends := PowAngebote.tag_seed(SAMSTAG_MITTAG + 6 * 3600)
	assert_eq(morgens, abends, "6 Uhr und 18 Uhr sind derselbe Tag")
	assert_ne(morgens, PowAngebote.tag_seed(SAMSTAG_MITTAG + 86400), "morgen ist ein anderer Tag")


func test_angebote_sind_paarweise_verschieden_und_rabattiert() -> void:
	# Über viele Tage: nie zweimal dieselbe Ware am selben Tag.
	for tag in 40:
		var angebote := PowAngebote.angebote(PowAngebote.tag_seed(SAMSTAG_MITTAG + tag * 86400))
		var gesehen: Dictionary = {}
		for angebot: Dictionary in angebote:
			var id := str(angebot["id"])
			assert_false(gesehen.has(id), "Ware doppelt am Tag %d: %s" % [tag, id])
			gesehen[id] = true
			assert_true(int(angebot["rabatt"]) > 0, "Angebot ohne Rabatt: %s" % id)
			assert_true(
				int(angebot["preis_neu"]) < int(angebot["preis"]), "Angebot nicht billiger: %s" % id
			)
			assert_true(int(angebot["preis_neu"]) >= 1, "Preis mindestens 1 Münze")


func test_rabatt_rechnung() -> void:
	assert_eq(PowAngebote.preis_mit_rabatt(100, 20), 80)
	assert_eq(PowAngebote.preis_mit_rabatt(100, 50), 50)
	assert_eq(PowAngebote.preis_mit_rabatt(1, 90), 1, "nie unter 1 Münze")
	assert_eq(PowAngebote.preis_mit_rabatt(0, 0), 1, "auch Gratis-Kram kostet den Mindestpreis")


func test_rest_bis_wechsel() -> void:
	var d := Time.get_datetime_dict_from_unix_time(SAMSTAG_MITTAG)
	var erwartet := 86400 - (int(d["hour"]) * 3600 + int(d["minute"]) * 60 + int(d["second"]))
	assert_eq(PowAngebote.rest_s_bis_wechsel(SAMSTAG_MITTAG), erwartet)
	assert_true(PowAngebote.rest_s_bis_wechsel(SAMSTAG_MITTAG) <= 86400)


func test_kamera_gate() -> void:
	var gs := FakeGameState.new()
	assert_false(PowAngebote.hat_kamera(gs), "ohne Kauf keine Kamera")
	assert_false(PowAngebote.hat_kamera(null), "ohne GameState auch nicht")
	gs.state["inventory"]["items"][PowAngebote.KAMERA_ITEM] = 1
	assert_true(PowAngebote.hat_kamera(gs), "nach dem Kauf ist die Kamera da")
