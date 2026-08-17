extends TestCase
## FIX-6 — Spielstand-Uebertragung Ende-zu-Ende (Doc H §5.3 sichtbar gemacht):
## 1. bplist.gd liest synthetische NSUserDefaults-Binaer-Plists (der Weg,
##    ueber den die Alt-Capacitor-App ihren Save im iOS-Container spiegelt).
## 2. legacy_capacitor.gd findet den `CapacitorStorage.gooby.save`-Key darin.
## 3. transfer_service.gd liefert Vorschau (echtes v4-Fixture!) und apply()
##    sichert den alten Stand VOR dem Ersetzen.
## 4. transfer_screen.gd faehrt den ganzen UI-Ablauf: Einfuegen → Pruefen →
##    Vorschau → Uebernehmen → Fertig (und Fehlerpfad bei Muell-Eingabe).

const BPlist := preload("res://scripts/state/import/bplist.gd")
const LegacyCapacitor := preload("res://scripts/state/import/legacy_capacitor.gd")
const TransferService := preload("res://scripts/state/import/transfer_service.gd")
const TransferScreenScene := preload("res://scripts/state/import/transfer_screen.tscn")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")
const Vacation := preload("res://scripts/logic/vacation.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")

## Alle echten v4-Fixtures (gegen die Web-Kette validiert — siehe
## docs/godot-rewrite/SAVE-TRANSFER.md, Abschnitt Feldliste).
const ALL_V4_FIXTURES: Array[String] = [
	"v4_fresh.json", "v4_midgame.json", "v4_maxed.json", "v4_extras.json", "v4_urlaub.json"
]

## Gepinnte Uhr der Fixture-Generierung (2026-01-15T12:00:00Z).
const NOW_MS := 1768478400000
## v4_midgame-Erwartungen: 4210 Coins + 250 Umzugsbonus + 180 Urlaubs-Erstattung.
const MIDGAME_COINS := 4640
const MIDGAME_LEVEL := 12

var _seq := 0


class FakeGameState:
	extends RefCounted
	var imported: Dictionary = {}
	var import_calls := 0
	var current: Dictionary = {"v": 5, "fake": true}

	func import_state(new_state: Dictionary) -> void:
		imported = new_state
		import_calls += 1

	func state() -> Dictionary:
		return current

	func get_value(_path: String, default: Variant = null) -> Variant:
		return default


func _fixture_text(file_name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/" + file_name)


func _temp_dir() -> String:
	_seq += 1
	var dir := "user://fix6_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


# ── bplist-Builder (Test-Seite): baut echte bplist00-Bytes wie iOS ───────────


## Minimaler bplist00-Writer fuer die Tests: EIN Dict aus String-Keys und
## String/Int/Bool/Float-Werten (genau die NSUserDefaults-Formen).
func _build_bplist(entries: Dictionary) -> PackedByteArray:
	var objects: Array[PackedByteArray] = []
	var dict_bytes := PackedByteArray()
	var count := entries.size()
	dict_bytes.append(0xD0 | count)  # Dict, count < 15 reicht den Tests
	# Objekt 0 = Dict; Keys = 1..count, Values = count+1..2*count.
	for i in count:
		dict_bytes.append(1 + i)
	for i in count:
		dict_bytes.append(1 + count + i)
	objects.append(dict_bytes)
	for key: String in entries.keys():
		objects.append(_encode_string(key))
	for key: String in entries.keys():
		objects.append(_encode_value(entries[key]))

	var out := "bplist00".to_ascii_buffer()
	var offsets: Array[int] = []
	for obj in objects:
		offsets.append(out.size())
		out.append_array(obj)
	var table_offset := out.size()
	for off in offsets:
		out.append((off >> 8) & 0xFF)  # offset_int_size = 2 (BE)
		out.append(off & 0xFF)
	# Trailer: 6 Fuellbytes, offset_int_size, ref_size, dann 3× 8-Byte-BE.
	out.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 2, 1]))
	out.append_array(_be64(objects.size()))
	out.append_array(_be64(0))  # top object = das Dict
	out.append_array(_be64(table_offset))
	return out


func _encode_string(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	var is_ascii := true
	for i in text.length():
		if text.unicode_at(i) > 127:
			is_ascii = false
			break
	if is_ascii:
		var bytes := text.to_ascii_buffer()
		out.append_array(_marker_with_len(0x5, bytes.size()))
		out.append_array(bytes)
		return out
	# UTF-16BE (Godot liefert LE → Paare drehen); BOM abschneiden.
	var utf16 := text.to_utf16_buffer()
	out.append_array(_marker_with_len(0x6, utf16.size() / 2))
	for i in range(0, utf16.size(), 2):
		out.append(utf16[i + 1])
		out.append(utf16[i])
	return out


func _encode_value(value: Variant) -> PackedByteArray:
	if value is String:
		return _encode_string(value)
	if value is bool:
		return PackedByteArray([0x09 if value else 0x08])
	if value is int:
		# 4-Byte-BE reicht den Testwerten.
		var v := int(value)
		return PackedByteArray(
			[0x12, (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
		)
	if value is float:
		var le := PackedByteArray()
		le.resize(8)
		le.encode_double(0, value)
		le.reverse()
		var out := PackedByteArray([0x23])
		out.append_array(le)
		return out
	fail_test("unbekannter Testwert-Typ: %s" % typeof(value))
	return PackedByteArray()


func _marker_with_len(kind: int, count: int) -> PackedByteArray:
	if count < 15:
		return PackedByteArray([(kind << 4) | count])
	if count < 256:
		return PackedByteArray([(kind << 4) | 0xF, 0x10, count])
	return PackedByteArray([(kind << 4) | 0xF, 0x11, (count >> 8) & 0xFF, count & 0xFF])


func _be64(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	for i in 8:
		out.append((value >> ((7 - i) * 8)) & 0xFF)
	return out


func _write_plist(dir: String, entries: Dictionary) -> String:
	var path := dir + "/com.permissionmaxed.gooby.plist"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_build_bplist(entries))
	file.flush()
	return path


# ── 1. bplist-Parser ─────────────────────────────────────────────────────────


func test_bplist_roundtrip_basistypen() -> void:
	var save_json := _fixture_text("v4_midgame.json")
	var bytes := _build_bplist(
		{
			"CapacitorStorage.gooby.save": save_json,
			"einInt": 42,
			"einBool": true,
			"einFloat": 2.5,
			"umlautKey": "Müsli für Gooby",
		}
	)
	var res := BPlist.parse(bytes)
	assert_true(res["ok"], "synthetische Plist parst: " + str(res["error"]))
	var root: Dictionary = res["value"]
	assert_eq(root["CapacitorStorage.gooby.save"], save_json, "langer ASCII-String verbatim")
	assert_eq(root["einInt"], 42)
	assert_eq(root["einBool"], true)
	assert_almost(float(root["einFloat"]), 2.5, 1e-12)
	assert_eq(root["umlautKey"], "Müsli für Gooby", "UTF-16BE-String verbatim")


func test_bplist_lehnt_muell_ab_ohne_crash() -> void:
	var junk: Array = [
		PackedByteArray(),
		"kein plist".to_utf8_buffer(),
		"bplist00".to_ascii_buffer(),
		_fixture_text("v4_fresh.json").to_utf8_buffer(),
	]
	for bytes: PackedByteArray in junk:
		var res := BPlist.parse(bytes)
		assert_false(res["ok"], "Muell (%d Bytes) sauber abgelehnt" % bytes.size())
		assert_false(str(res["error"]).is_empty(), "Fehler benannt")
	# Abgeschnittene ECHTE Plist (Trailer zerstoert) → Fehler, kein Crash.
	var real := _build_bplist({"CapacitorStorage.gooby.save": "{}"})
	var cut := real.slice(0, real.size() - 9)
	assert_false(BPlist.parse(cut)["ok"], "abgeschnittene Plist abgelehnt")


# ── 2. Legacy-Reader (NSUserDefaults-Spiegelung) ─────────────────────────────


func test_legacy_capacitor_findet_save_key() -> void:
	var dir := _temp_dir()
	var save_json := _fixture_text("v4_midgame.json")
	var path := _write_plist(dir, {"CapacitorStorage.gooby.save": save_json, "anderes": 1})
	var res := LegacyCapacitor.read_from_plist(path)
	assert_true(res["ok"], "Save gefunden: " + str(res["error"]))
	assert_eq(res["json"], save_json, "roher v4-JSON verbatim")
	assert_eq(res["source"], "ios-preferences")
	# read_save_json mit Override (Nicht-iOS-Testpfad).
	var via_api := LegacyCapacitor.read_save_json(path)
	assert_true(via_api["ok"], "read_save_json via Override")
	assert_eq(via_api["json"], save_json)


func test_legacy_capacitor_plan_b_prefix_und_leere_quelle() -> void:
	var dir := _temp_dir()
	# Plan B: abweichender Capacitor-Gruppen-Prefix, Suffix `gooby.save` zaehlt.
	var path := _write_plist(dir, {"CapacitorStorageGroup.gooby.save": '{"v":4}'})
	var res := LegacyCapacitor.read_from_plist(path)
	assert_true(res["ok"], "Suffix-Suche greift")
	assert_eq(res["json"], '{"v":4}')
	# Plist ohne Save-Key → ok=false mit error=="" (kein Fehlerfall).
	var empty_path := _write_plist(_temp_dir(), {"NSLanguages": "de"})
	var missing := LegacyCapacitor.read_from_plist(empty_path)
	assert_false(missing["ok"], "kein Save → nicht gefunden")
	assert_eq(missing["error"], "", "fehlender Save ist KEIN Fehler")
	# Fehlende Datei → nicht gefunden, kein Crash.
	assert_false(LegacyCapacitor.read_save_json(dir + "/gibtsnicht.plist")["ok"])


# ── 3. Transfer-Service (Vorschau + Uebernahme) ──────────────────────────────


func test_probe_legacy_liefert_vorschau_aus_echtem_fixture() -> void:
	var dir := _temp_dir()
	var path := _write_plist(dir, {"CapacitorStorage.gooby.save": _fixture_text("v4_midgame.json")})
	var probe := TransferService.probe_legacy(NOW_MS, path)
	assert_true(probe["found"], "Alt-Save gefunden: " + str(probe["error"]))
	assert_eq(probe["source"], "ios-preferences")
	var preview: Dictionary = probe["preview"]
	assert_true(preview["ok"], "Vorschau migriert")
	var info := TransferService.report_summary(preview["report"])
	assert_eq(int(info["level"]), MIDGAME_LEVEL, "Level in der Vorschau")
	assert_eq(int(info["coins"]), MIDGAME_COINS, "Muenzen inkl. Bonus+Erstattung")
	assert_eq(int(info["stickers"]), 20, "Sticker-Anzahl")
	assert_eq(int(info["furniture"]), 9, "Moebel im Umzugskarton")
	# Kein Alt-Save auf dem Geraet → found=false, still (kein Fehlertext).
	var silent := TransferService.probe_legacy(NOW_MS, dir + "/leer.plist")
	assert_false(silent["found"])
	assert_eq(silent["error"], "")


func test_preview_text_und_datei_gleiche_pipeline() -> void:
	var text := _fixture_text("v4_maxed.json")
	var via_text := TransferService.preview_text(text, NOW_MS)
	assert_true(via_text["ok"], via_text["error"])
	assert_eq(int(via_text["report"]["level"]), 40)
	var dir := _temp_dir()
	var path := dir + "/export.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.flush()
	var via_file := TransferService.preview_file(path, NOW_MS)
	assert_true(via_file["ok"], via_file["error"])
	assert_eq(via_file["state"], via_text["state"], "Datei == Text (deterministisch)")
	assert_false(TransferService.preview_file(dir + "/fehlt.json", NOW_MS)["ok"])
	assert_false(TransferService.preview_text("kein save {{{", NOW_MS)["ok"])


func test_apply_sichert_alten_stand_vor_dem_ersetzen() -> void:
	var dir := _temp_dir()
	var save_path := dir + "/save_v5.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string('{"v":5,"alterStand":true}')
	file.flush()
	file = null
	var preview := TransferService.preview_text(_fixture_text("v4_fresh.json"), NOW_MS)
	assert_true(preview["ok"], preview["error"])
	var fake := FakeGameState.new()
	assert_true(TransferService.apply(preview["state"], fake, save_path), "apply klappt")
	assert_eq(fake.import_calls, 1, "GameState.import_state genau 1×")
	assert_eq(fake.imported, preview["state"], "neuer Stand uebergeben")
	var backup_path := save_path.get_basename() + ".pre_import.json"
	assert_true(FileAccess.file_exists(backup_path), "Vorsicherung existiert")
	assert_eq(
		FileAccess.get_file_as_string(backup_path),
		'{"v":5,"alterStand":true}',
		"Vorsicherung traegt den ALTEN Stand"
	)
	# Ohne import_state-Faehigkeit: sauberes false statt Crash.
	assert_false(TransferService.apply(preview["state"], RefCounted.new(), save_path))
	assert_false(TransferService.apply(preview["state"], null, save_path))


# ── 4. Transfer-Screen (UI-Ablauf) ───────────────────────────────────────────


func _make_screen(fake: FakeGameState) -> TransferScreen:
	var screen: TransferScreen = TransferScreenScene.instantiate()
	screen.gs_override = fake
	screen.now_override = NOW_MS
	screen.auto_probe = false
	tree.root.add_child(screen)
	return screen


func test_screen_einfuegen_vorschau_uebernehmen() -> void:
	var fake := FakeGameState.new()
	var screen := _make_screen(fake)
	await wait_frames(1)
	assert_eq(screen.phase, "input", "startet leer")
	screen.set_input_text(_fixture_text("v4_midgame.json"))
	var preview := screen.check_now()
	assert_true(preview["ok"], "Vorschau ok: " + str(preview.get("error", "")))
	assert_eq(screen.phase, "preview", "Vorschau-Phase")
	screen.apply_now()
	assert_eq(screen.phase, "done", "Fertig-Phase")
	assert_eq(fake.import_calls, 1, "Import lief")
	assert_eq(int(fake.imported["progression"]["level"]), MIDGAME_LEVEL)
	assert_eq(int(fake.imported["economy"]["coins"]), MIDGAME_COINS)
	screen.queue_free()
	await wait_frames(1)


func test_screen_fehlerpfad_und_abbrechen() -> void:
	var fake := FakeGameState.new()
	var screen := _make_screen(fake)
	await wait_frames(1)
	screen.set_input_text("das ist kein spielstand")
	var res := screen.check_now()
	assert_false(res["ok"], "Muell abgelehnt")
	assert_eq(screen.phase, "input", "bleibt bei der Eingabe")
	assert_eq(fake.import_calls, 0, "nichts importiert")
	# apply_now ohne gueltige Vorschau ist ein No-Op.
	screen.apply_now()
	assert_eq(fake.import_calls, 0, "apply ohne Vorschau ignoriert")
	screen.queue_free()
	await wait_frames(1)


func test_screen_auto_import_karte_aus_plist() -> void:
	var dir := _temp_dir()
	var path := _write_plist(dir, {"CapacitorStorage.gooby.save": _fixture_text("v4_fresh.json")})
	var fake := FakeGameState.new()
	var screen: TransferScreen = TransferScreenScene.instantiate()
	screen.gs_override = fake
	screen.now_override = NOW_MS
	screen.plist_override = path
	tree.root.add_child(screen)
	await wait_frames(1)
	var probe: Variant = screen.get_meta("auto_probe", {})
	assert_true(probe is Dictionary and (probe as Dictionary)["found"], "Auto-Fund gemerkt")
	screen._on_auto_preview_pressed()
	assert_eq(screen.phase, "preview", "Auto-Fund → Vorschau")
	screen.apply_now()
	assert_eq(screen.phase, "done")
	assert_eq(int(fake.imported["economy"]["coins"]), 350, "fresh: 100 + 250 Bonus")
	screen.queue_free()
	await wait_frames(1)


# ── 5. Feldliste: nichts geht verloren (alle 5 Fixtures) ─────────────────────


func _parse_fixture(file_name: String) -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(_fixture_text(file_name)), OK, file_name + " muss parsen")
	return json.data


## Der bindende "Feldlisten"-Vertrag der Save-Uebertragung: fuer JEDES echte
## v4-Fixture muessen Muenzen (inkl. Bonus/Erstattung), Level, Sticker-Set,
## Outfits, Fell, Moebel (Anzahl im Umzugskarton), Stats, Counters, Daily,
## Sammlungen, Profil, Sammelpass (visited), Reisen und Postkarten-Archiv
## 1:1 im v5-Stand ankommen. Doku: docs/godot-rewrite/SAVE-TRANSFER.md.
func test_feldliste_kernfelder_ueber_alle_fixtures() -> void:
	for file_name in ALL_V4_FIXTURES:
		var v4 := _parse_fixture(file_name)
		var res := MigrationV4.migrate_any(v4, NOW_MS)
		assert_true(res["ok"], file_name + " migriert: " + str(res["error"]))
		var s: Dictionary = res["state"]
		var tag := file_name + ": "
		# Muenzen: verbatim + 250 Umzugsbonus + Erstattung einer laufenden Reise.
		var vac := Vacation.slice_of(v4)
		var refund := 0
		if vac["phase"] != Vacation.PHASE_NONE:
			var dest: Variant = Vacation.CATALOG.get(vac["destId"])
			refund = int(dest["price"]) if dest != null else 0
		assert_eq(
			int(s["economy"]["coins"]),
			int(v4.get("coins", 0)) + 250 + refund,
			tag + "Muenzen inkl. Bonus/Erstattung"
		)
		assert_eq(int(s["progression"]["level"]), int(v4.get("level", 1)), tag + "Level 1:1")
		# Sticker-/Outfit-/Fell-Sets identisch.
		var got_stickers: Array = s["stickers"]["unlocked"].keys()
		var want_stickers: Array = v4.get("stickers", {}).get("unlocked", {}).keys()
		got_stickers.sort()
		want_stickers.sort()
		assert_eq(got_stickers, want_stickers, tag + "Sticker-Set")
		assert_deep_eq(
			s["cosmetics"]["outfits"]["owned"], v4["outfits"]["owned"], tag + "Outfits owned"
		)
		assert_deep_eq(s["cosmetics"]["fur"]["owned"], v4["skins"]["owned"], tag + "Fell owned")
		assert_eq(
			str(s["cosmetics"]["fur"]["equipped"]), str(v4["skins"]["equipped"]), tag + "Fell an"
		)
		# Moebel: jede owned-ID landet im Umzugskarton (Anzahl-Summe gleich).
		var boxed := 0
		for row: Dictionary in s["home"]["storage"]:
			boxed += int(row["count"])
		assert_eq(boxed, (v4["furniture"]["owned"] as Array).size(), tag + "Moebel im Karton")
		assert_true(bool(s["home"]["movingDay"]), tag + "Umzugstag-Marker")
		# Stats/Counters/Daily/Sammlungen/Profil verbatim.
		assert_deep_eq(s["gooby"]["stats"], v4["stats"], tag + "Stats")
		for k: String in v4["achievements"]["counters"].keys():
			assert_eq(
				int(s["achievements"]["counters"][k]),
				int(v4["achievements"]["counters"][k]),
				tag + "counter " + k
			)
		assert_deep_eq(s["daily"], v4["daily"], tag + "daily")
		assert_deep_eq(s["collections"], v4["collections"], tag + "Sammlungen")
		assert_eq(
			int(s["profile"]["playtimeMin"]), int(v4["profile"]["playtimeMin"]), tag + "Spielzeit"
		)
		assert_eq(int(s["profile"]["distanceM"]), int(v4["profile"]["distanceM"]), tag + "Distanz")
		assert_eq(
			int(s["quests"]["completedTotal"]),
			int(v4["quests"]["completedTotal"]),
			tag + "Quest-Zaehler"
		)
		# Sammelpass (besuchte Orte), Reise-Zaehler, Postkarten-Archiv verbatim.
		assert_deep_eq(s["vacation"]["visited"], vac["visited"], tag + "besuchte Orte")
		assert_eq(int(s["vacation"]["trips"]), int(vac["trips"]), tag + "Reise-Zaehler")
		assert_eq(
			(s["vacation"]["archive"] as Array).size(),
			(vac["archive"] as Array).size(),
			tag + "Postkarten-Archiv"
		)
		assert_eq(
			int(s["gallery"]["legacyCount"]),
			int(v4.get("gallery", {}).get("count", 0)),
			tag + "Foto-Zaehler"
		)
		# Ehrliche Verlustliste ist IMMER dokumentiert (xp/quests/modifiers/...).
		var lost_text := "\n".join(PackedStringArray(s["migration"]["lost"]))
		for needle: String in ["xp", "quests.active", "modifiers", "photos"]:
			assert_true(lost_text.contains(needle), tag + "Verlustliste nennt " + needle)


## Urlaub-Fixture: Gooby steht bei der Uebertragung am Flughafen
## (returnReady). Die Reise wird abgebrochen + erstattet, Sammelpass,
## Reise-Historie und Postkarten-Archiv bleiben vollstaendig.
func test_urlaub_fixture_reise_erstattet_sammelpass_bleibt() -> void:
	var res := MigrationV4.migrate_any(_parse_fixture("v4_urlaub.json"), NOW_MS)
	assert_true(res["ok"], "v4_urlaub migriert: " + str(res["error"]))
	var s: Dictionary = res["state"]
	# 1180 + 250 Umzugsbonus + 350 Space-Erstattung.
	assert_eq(int(s["economy"]["coins"]), 1780, "Space-Reisepreis erstattet")
	assert_eq(s["vacation"]["phase"], "none", "Reise beendet (Gooby zieht ja um)")
	assert_eq(s["vacation"]["destId"], "")
	var interrupted: Dictionary = s["migration"]["interruptedVacation"]
	assert_eq(interrupted["destId"], "space")
	assert_eq(interrupted["phase"], "returnReady")
	assert_eq(int(interrupted["refund"]), 350)
	assert_eq(int(interrupted["remainingMs"]), 43200000, "12 h bis pickupBy")
	assert_eq(int(interrupted["postcards"]), 3)
	# Lebenszeit-Andenken bleiben: 3 Reisen, 5 Postkarten, 3 besuchte Orte.
	assert_eq(int(s["vacation"]["trips"]), 3)
	assert_eq((s["vacation"]["archive"] as Array).size(), 5)
	assert_deep_eq(
		s["vacation"]["visited"],
		{"beach": true, "harbor": true, "bigCity": true},
		"Sammelpass verbatim"
	)
	# Additive Slices: Klo-Cooldown uebernommen, Cutscene-Latch ehrlich verloren.
	assert_eq(int(s["bad"]["kloLastMs"]), 1768471200000, "care.toiletAt → bad.kloLastMs")
	var lost_text := "\n".join(PackedStringArray(s["migration"]["lost"]))
	assert_true(lost_text.contains("cutscenes.seen"), "Cutscene-Latch in Verlustliste")
	assert_true(bool(s["camera"]["owned"]), "6 Fotos → Kamera-Grandfathering")
	# Vorschau-Report zeigt dieselben Zahlen wie der Screen.
	var info := TransferService.report_summary(res["report"])
	assert_eq(int(info["level"]), 22)
	assert_eq(int(info["coins"]), 1780)
	assert_eq(int(info["stickers"]), 10)
	assert_eq(int(info["furniture"]), 11)


## Numerisch tolerantes Deep-Equal (JSON floats vs GDScript ints).
func assert_deep_eq(got: Variant, want: Variant, message := "") -> void:
	var diff := Util.first_diff(got, want)
	assert_true(diff.is_empty(), "%s — erster Diff: %s" % [message, diff])
