extends TestCase
## W15/UPDREPO — Updates über das PRIVATE Haupt-Repo (GitHub-Release-API).
## Pure Bausteine: URL-Klassifikation (API vs. direkt), Header-Bau mit/ohne
## Token, Token-Ketten-Vorrang (Override > user://-Settings > config-Pack),
## Asset-Auswahl aus einer Fixture-API-Antwort, Fehlertext ohne Token.
## Ende-zu-Ende: der komplette Check-Flow gegen einen LOKALEN Mini-HTTP-Stub
## (ephemerer Port), der die GitHub-Release-API nachstellt — inklusive
## Authorization-/Accept-Header-Beweis und browser-URL→Asset-URL-Umschreibung.
## Der bestehende Direkt-URL-Pfad bleibt unangetastet (test_updates_flow).

const BASE_API := "user://w15_updrepo_api"
const BASE_NOTOKEN := "user://w15_updrepo_notoken"
const BASE_KETTE := "user://w15_updrepo_kette"
const REPO_DL := "https://github.com/MedusaV9/CustomServerPrivate/releases/download/updates"
const REPO_API := "https://api.github.com/repos/MedusaV9/CustomServerPrivate/releases/tags/updates"

## Realistisch gekürzte GitHub-Release-API-Antwort (GET …/releases/tags/updates).
## `url` ist die Asset-API-URL (Download via Accept: octet-stream); die
## browser_download_url-Felder der echten Antwort sind hier weggelassen.
const FIXTURE_RELEASE_JSON := """
{
	"id": 231001,
	"tag_name": "updates",
	"name": "GOOBY Updates (rollend)",
	"assets": [
		{
			"id": 9001,
			"name": "manifest.json",
			"size": 512,
			"content_type": "application/json",
			"url": "https://api.github.com/repos/MedusaV9/CustomServerPrivate/releases/assets/9001"
		},
		{
			"id": 9002,
			"name": "cosmetics-v1.4.0.pck",
			"size": 1848320,
			"content_type": "application/octet-stream",
			"url": "https://api.github.com/repos/MedusaV9/CustomServerPrivate/releases/assets/9002"
		}
	]
}
"""


func test_url_klassifikation() -> void:
	assert_true(UpdateService.is_github_api_url(REPO_API), "api.github.com wird als API erkannt")
	assert_false(
		UpdateService.is_github_api_url(REPO_DL + "/manifest.json"),
		"browser-download-URL ist KEINE API-URL"
	)
	assert_false(UpdateService.is_github_api_url("file:///tmp/m.json"), "file:// nie API")
	assert_true(
		UpdateService.is_github_api_url(
			"http://127.0.0.1:8123/repos/o/r/releases/tags/updates",
			PackedStringArray(["127.0.0.1:8123"])
		),
		"Test-Stub-Host über extra_hosts"
	)
	# Klassifikation: API-URL zieht IMMER; browser-URL nur MIT Token; fremde
	# Hosts und lokale Schemata bleiben direkt (Abwärtskompatibilität).
	assert_eq(UpdateService.classify_manifest_source(REPO_API, ""), "api", "API-URL ohne Token")
	assert_eq(UpdateService.classify_manifest_source(REPO_API, "tok"), "api", "API-URL mit Token")
	assert_eq(
		UpdateService.classify_manifest_source(REPO_DL + "/manifest.json", ""),
		"direct",
		"browser-URL ohne Token = alter Direkt-Pfad (öffentliches Repo)"
	)
	assert_eq(
		UpdateService.classify_manifest_source(REPO_DL + "/manifest.json", "tok"),
		"api",
		"browser-URL MIT Token = API-Pfad (privates Repo)"
	)
	assert_eq(
		UpdateService.classify_manifest_source("https://example.org/manifest.json", "tok"),
		"direct",
		"fremder Server bleibt direkt (Token geht NIE an fremde Hosts)"
	)
	assert_eq(
		UpdateService.classify_manifest_source("file:///tmp/m.json", "tok"),
		"direct",
		"lokales Schema bleibt direkt (DEV/Tests)"
	)
	# browser-URL-Zerlegung + API-Äquivalent.
	var parts := UpdateService.parse_release_download_url(REPO_DL + "/cosmetics-v1.4.0.pck")
	assert_eq(str(parts.get("owner")), "MedusaV9", "owner")
	assert_eq(str(parts.get("repo")), "CustomServerPrivate", "repo")
	assert_eq(str(parts.get("tag")), "updates", "tag")
	assert_eq(str(parts.get("file")), "cosmetics-v1.4.0.pck", "datei")
	assert_eq(
		UpdateService.api_release_url_for(REPO_DL + "/manifest.json"),
		REPO_API,
		"browser-URL → Release-API-URL"
	)
	assert_true(
		(
			UpdateService
			. parse_release_download_url("https://github.com/o/r/archive/main.zip")
			. is_empty()
		),
		"Nicht-Release-URL → {}"
	)


func test_header_bau_mit_und_ohne_token() -> void:
	var mit := UpdateService.github_headers("abc123", UpdateService.ACCEPT_OCTET_STREAM)
	assert_true(mit.has("Authorization: Bearer abc123"), "Bearer-Header mit Token")
	assert_true(mit.has("Accept: application/octet-stream"), "Accept-Header (Asset-Download)")
	assert_true(mit.has("X-GitHub-Api-Version: 2022-11-28"), "API-Version-Header")
	var ohne := UpdateService.github_headers("", UpdateService.ACCEPT_GITHUB_JSON)
	assert_true(ohne.has("Accept: application/vnd.github+json"), "Accept-Header (Release-JSON)")
	for header in ohne:
		assert_false(header.begins_with("Authorization:"), "ohne Token KEIN Authorization-Header")


func test_token_ketten_vorrang() -> void:
	_wipe(BASE_KETTE)
	DirAccess.make_dir_recursive_absolute(BASE_KETTE)
	var service := UpdateService.new()
	service.packs_dir = BASE_KETTE + "/packs"
	service.user_override_path = BASE_KETTE + "/user_override.json"
	# Basis: eingebauter config-Pack hat KEIN github_token → leer.
	assert_eq(service.resolve_github_token(), "", "ohne alles: kein Token")
	# Stufe 3: config-Pack-Feld (Remote-Config user://packs/config.json).
	_write_text(
		BASE_KETTE + "/packs/config.json",
		JSON.stringify({"schema": 1, "github_token": "aus-config-pack"})
	)
	assert_eq(service.resolve_github_token(), "aus-config-pack", "config-Pack-Feld greift")
	# Stufe 2: user://-Settings (Updates-Sektion) schlagen den config-Pack.
	UpdateService.save_user_override({"github_token": "aus-settings"}, service.user_override_path)
	assert_eq(service.resolve_github_token(), "aus-settings", "User-Settings > config-Pack")
	assert_eq(
		str(UpdateService.load_user_override(service.user_override_path).get("github_token")),
		"aus-settings",
		"Settings-Datei-Roundtrip"
	)
	# Stufe 1: DEV/Test-Override schlägt alles.
	service.github_token_override = "aus-override"
	assert_eq(service.resolve_github_token(), "aus-override", "Override > alles")
	# Rückbau: clear löscht die Datei, config-Pack gilt wieder.
	service.github_token_override = ""
	UpdateService.clear_user_override(service.user_override_path)
	assert_false(FileAccess.file_exists(service.user_override_path), "clear entfernt die Datei")
	assert_eq(service.resolve_github_token(), "aus-config-pack", "zurück auf config-Pack")
	# Leeres Token speichern = Datei weg (Allowlist, kein Leichnam).
	UpdateService.save_user_override({"github_token": ""}, service.user_override_path)
	assert_false(
		FileAccess.file_exists(service.user_override_path), "leeres Token legt keine Datei an"
	)
	service.free()
	_wipe(BASE_KETTE)


func test_asset_auswahl_aus_fixture() -> void:
	var json := JSON.new()
	assert_eq(json.parse(FIXTURE_RELEASE_JSON), OK, "Fixture parst")
	var release: Dictionary = json.data
	var manifest_asset := UpdateService.select_release_asset(release, "manifest.json")
	assert_eq(int(manifest_asset.get("id", 0)), 9001, "manifest.json-Asset gefunden")
	assert_eq(
		str(manifest_asset.get("url")),
		"https://api.github.com/repos/MedusaV9/CustomServerPrivate/releases/assets/9001",
		"Asset-API-URL (Download mit Accept: octet-stream)"
	)
	var pck := UpdateService.select_release_asset(release, "cosmetics-v1.4.0.pck")
	assert_eq(int(pck.get("id", 0)), 9002, "Pack-Asset per Dateiname")
	assert_true(
		UpdateService.select_release_asset(release, "gibt-es-nicht.pck").is_empty(),
		"fehlendes Asset → {}"
	)


func test_fehlertext_ohne_token_keys() -> void:
	var keys := SettingsUpdateGlue.result_text_keys(
		UpdateService.Result.ERROR, {"token_required": true}
	)
	assert_eq(keys, ["updates.token_fehlt"], "token_required → klarer Panel-Hinweis")
	assert_eq(
		SettingsUpdateGlue.result_text_keys(UpdateService.Result.ERROR, {}),
		["updates.fehler"],
		"normaler Fehler bleibt beim generischen Toast"
	)
	var text := I18nService.t("updates.token_fehlt")
	assert_true(text.contains("Zugangsschlüssel"), "DE-Text nennt den Zugangsschlüssel")
	assert_true(text.contains("Einstellungen"), "DE-Text verweist auf die Einstellungen")


func test_api_flow_gegen_stub_mit_token() -> void:
	_wipe(BASE_API)
	DirAccess.make_dir_recursive_absolute(BASE_API + "/dist")
	var stub := GithubApiStub.new()
	tree.root.add_child(stub)
	var port := stub.start()
	assert_true(port > 0, "Stub lauscht auf ephemerem Port %d" % port)
	# Test-Pack + Remote-config bauen (PCKPacker — wie test_updates_flow).
	var pck_path := BASE_API + "/dist/cosmetics-v9.1.0.pck"
	_build_test_pack(pck_path, "9.1.0")
	var pck_sha := UpdateService.sha256_of_file(pck_path)
	var config_path := BASE_API + "/dist/config.json"
	_write_text(
		config_path, JSON.stringify({"schema": 1, "net": {"host": "15.15.15.15", "port": 1515}})
	)
	# Manifest trägt BROWSER-URLs (so baut es build_manifest.mjs) — der Client
	# muss sie im API-Modus über die Assets-Liste auf die Asset-URLs umschreiben.
	var manifest_text := (
		JSON
		. stringify(
			{
				"schema": 1,
				"latest_native": "5.0.0",
				"notes_de": "W15-Stub-Test",
				"packs":
				[
					{
						"id": "cosmetics",
						"version": "9.1.0",
						"type": "pck",
						"url": REPO_DL + "/cosmetics-v9.1.0.pck",
						"sha256": pck_sha,
						"min_native": "5.0.0",
						"priority": 400,
					},
					{
						"id": "config",
						"version": "9.0.1",
						"type": "json",
						"url": REPO_DL + "/config.json",
						"sha256": UpdateService.sha256_of_file(config_path),
						"min_native": "5.0.0",
						"priority": 700,
					},
				],
			},
			"\t"
		)
	)
	var base := "http://127.0.0.1:%d" % port
	stub.routes["/repos/MedusaV9/CustomServerPrivate/releases/tags/updates"] = {
		"content_type": "application/json",
		"body":
		(
			JSON
			. stringify(
				{
					"id": 1,
					"tag_name": "updates",
					"assets":
					[
						{"id": 1, "name": "manifest.json", "url": base + "/assets/1"},
						{"id": 2, "name": "cosmetics-v9.1.0.pck", "url": base + "/assets/2"},
						{"id": 3, "name": "config.json", "url": base + "/assets/3"},
					],
				}
			)
			. to_utf8_buffer()
		),
	}
	stub.routes["/assets/1"] = {
		"content_type": "application/octet-stream", "body": manifest_text.to_utf8_buffer()
	}
	stub.routes["/assets/2"] = {
		"content_type": "application/octet-stream", "body": FileAccess.get_file_as_bytes(pck_path)
	}
	stub.routes["/assets/3"] = {
		"content_type": "application/octet-stream",
		"body": FileAccess.get_file_as_bytes(config_path),
	}
	var service := _make_api_service(BASE_API, base, port)
	service.github_token_override = "test-token-w15"
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.UPDATED, "API-Flow → UPDATED")
	assert_false(bool(outcome["details"]["token_required"]), "mit Token kein Token-Hinweis")
	assert_true(
		FileAccess.file_exists(BASE_API + "/packs/cosmetics-v9.1.0.pck"),
		"Pack über Asset-API geladen + verifiziert"
	)
	assert_eq(
		UpdateService.sha256_of_file(BASE_API + "/packs/cosmetics-v9.1.0.pck"),
		pck_sha,
		"Download byte-identisch (sha256)"
	)
	assert_true(FileAccess.file_exists(BASE_API + "/packs/config.json"), "config-Asset geladen")
	# Header-Beweise: Authorization überall, Accept je nach Request-Art.
	assert_eq(stub.requests.size(), 4, "Release-JSON + 3 Asset-Downloads")
	for request: Dictionary in stub.requests:
		assert_eq(
			str(request["headers"].get("authorization", "")),
			"Bearer test-token-w15",
			"Authorization auf %s" % str(request["path"])
		)
	assert_true(
		str(stub.requests[0]["headers"].get("accept", "")).contains("vnd.github+json"),
		"Release-Request mit Accept: application/vnd.github+json"
	)
	for i in [1, 2, 3]:
		assert_eq(
			str(stub.requests[i]["headers"].get("accept", "")),
			"application/octet-stream",
			"Asset-Request %d mit Accept: application/octet-stream" % i
		)
	print("[W15] API-Flow über Stub: %s" % str(outcome["details"]["updated"]))
	service.queue_free()
	stub.queue_free()
	await wait_frames(1)


func test_api_ohne_token_meldet_zugangsschluessel() -> void:
	_wipe(BASE_NOTOKEN)
	DirAccess.make_dir_recursive_absolute(BASE_NOTOKEN)
	var stub := GithubApiStub.new()
	tree.root.add_child(stub)
	var port := stub.start()
	assert_true(port > 0, "Stub lauscht")
	# Wie GitHub bei privaten Repos: ohne Authorization → 404 (kein Leak).
	var base := "http://127.0.0.1:%d" % port
	stub.routes["/repos/MedusaV9/CustomServerPrivate/releases/tags/updates"] = {
		"content_type": "application/json",
		"body": JSON.stringify({"id": 1, "tag_name": "updates", "assets": []}).to_utf8_buffer(),
	}
	var service := _make_api_service(BASE_NOTOKEN, base, port)
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.ERROR, "ohne Token → ERROR")
	assert_true(bool(outcome["details"]["token_required"]), "details.token_required gesetzt")
	var errors: Array = outcome["details"]["errors"]
	assert_eq(errors.size(), 1, "genau ein Fehlertext")
	assert_true(
		str(errors[0]).contains("Zugangsschlüssel"), "Fehlertext nennt den Zugangsschlüssel"
	)
	assert_true(
		str(errors[0]).contains("Einstellungen → Updates"),
		"Fehlertext verweist auf Einstellungen → Updates"
	)
	service.queue_free()
	stub.queue_free()
	await wait_frames(1)
	_wipe(BASE_NOTOKEN)


## ------------------------------------------------------------------ Helfer


## UpdateService gegen den Stub: user://-Pfade isoliert, Stub-Host als API-Host.
func _make_api_service(base_dir: String, base_url: String, port: int) -> UpdateService:
	var service := UpdateService.new()
	service.packs_dir = base_dir + "/packs"
	service.app_version = "5.0.0"
	service.manifest_url_override = (
		base_url + "/repos/MedusaV9/CustomServerPrivate/releases/tags/updates"
	)
	service.api_hosts_extra = PackedStringArray(["127.0.0.1:%d" % port])
	service.user_override_path = base_dir + "/user_override.json"
	tree.root.add_child(service)
	return service


## Minimales Cosmetics-Test-Pack (kompletter Katalog + 1 neues Item) — Muster
## aus test_updates_flow; version ist Parameter, damit die Läufe unabhängig sind.
func _build_test_pack(pck_path: String, version: String) -> void:
	var src_dir := pck_path.get_base_dir() + "/src"
	var meta := {
		"schema": 1,
		"id": "cosmetics",
		"version": version,
		"priority": 400,
		"min_native": "5.0.0",
		"domains": ["cosmetics"],
	}
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string("res://content/cosmetics/data/cosmetics.json"))
	var catalog: Dictionary = json.data
	(
		catalog["items"]
		. append(
			{
				"id": "hut_w15_api",
				"type": "hat",
				"name_de": "API-Hut",
				"price": 150,
				"rarity": "rare",
				"asset": "",
			}
		)
	)
	_write_text(src_dir + "/pack.json", JSON.stringify(meta, "\t"))
	_write_text(src_dir + "/cosmetics.json", JSON.stringify(catalog, "\t"))
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(pck_path), OK, "PCKPacker.pck_start")
	packer.add_file("res://content/cosmetics/pack.json", src_dir + "/pack.json")
	packer.add_file("res://content/cosmetics/data/cosmetics.json", src_dir + "/cosmetics.json")
	assert_eq(packer.flush(), OK, "PCKPacker.flush")


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


class GithubApiStub:
	extends Node
	## Mini-HTTP-Stub (ephemerer Port), der die GitHub-Release-API nachstellt:
	## GET-Routen aus `routes` (Pfad → content_type + body-Bytes), jede Antwort
	## Connection: close. Wie GitHub bei privaten Repos antwortet er OHNE
	## Authorization-Header mit 404 {"message":"Not Found"}. Alle Requests
	## landen mit Methode/Pfad/Headern (lowercase) in `requests` — die Tests
	## beweisen damit Authorization-/Accept-Header. Muster: test_net_integration
	## (lokaler Server, ephemerer Port), nur eben HTTP statt WebSocket.

	## Frames zwischen Antwort und Socket-Schließen (Daten sicher raus).
	const CLOSE_DELAY_FRAMES := 10

	var routes := {}
	var requests: Array[Dictionary] = []
	var require_auth := true

	var _server := TCPServer.new()
	var _pending: Array[Dictionary] = []
	var _closing: Array[Dictionary] = []

	## Lauschen auf ephemerem Port (0 = OS wählt). Rückgabe: Port oder 0.
	func start() -> int:
		if _server.listen(0, "127.0.0.1") == OK and _server.get_local_port() > 0:
			return _server.get_local_port()
		# Fallback: zufällige hohe Ports probieren (Muster test_net_integration).
		for _i in 20:
			var port := 20000 + randi() % 20000
			if _server.listen(port, "127.0.0.1") == OK:
				return port
		return 0

	func _exit_tree() -> void:
		_server.stop()

	func _process(_delta: float) -> void:
		while _server.is_connection_available():
			_pending.append({"peer": _server.take_connection(), "buf": PackedByteArray()})
		for entry in _pending.duplicate():
			if _pump(entry):
				_pending.erase(entry)
		for entry in _closing.duplicate():
			entry["frames"] = int(entry["frames"]) - 1
			if int(entry["frames"]) <= 0:
				(entry["peer"] as StreamPeerTCP).disconnect_from_host()
				_closing.erase(entry)

	## true = Verbindung fertig behandelt (antwortet, sobald der Header da ist).
	func _pump(entry: Dictionary) -> bool:
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return peer.get_status() == StreamPeerTCP.STATUS_ERROR
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_data(available)
			if int(chunk[0]) == OK:
				# PackedByteArray ist Value-Type: lokal anhängen, zurückschreiben.
				var buf: PackedByteArray = entry["buf"]
				buf.append_array(chunk[1])
				entry["buf"] = buf
		var text := (entry["buf"] as PackedByteArray).get_string_from_utf8()
		var head_end := text.find("\r\n\r\n")
		if head_end < 0:
			return false
		_respond(peer, text.substr(0, head_end))
		_closing.append({"peer": peer, "frames": CLOSE_DELAY_FRAMES})
		return true

	func _respond(peer: StreamPeerTCP, head: String) -> void:
		var lines := head.split("\r\n")
		var request_line := lines[0].split(" ")
		var path := request_line[1] if request_line.size() > 1 else ""
		var headers := {}
		for i in range(1, lines.size()):
			var colon := lines[i].find(":")
			if colon > 0:
				headers[lines[i].substr(0, colon).strip_edges().to_lower()] = (
					lines[i].substr(colon + 1).strip_edges()
				)
		requests.append({"method": request_line[0], "path": path, "headers": headers})
		if require_auth and not headers.has("authorization"):
			_send(peer, 404, "application/json", '{"message":"Not Found"}'.to_utf8_buffer())
			return
		if not routes.has(path):
			_send(peer, 404, "application/json", '{"message":"Not Found"}'.to_utf8_buffer())
			return
		var route: Dictionary = routes[path]
		_send(peer, 200, str(route["content_type"]), route["body"])

	func _send(peer: StreamPeerTCP, code: int, content_type: String, body: PackedByteArray) -> void:
		var status := "200 OK" if code == 200 else "404 Not Found"
		var head := (
			"HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
			% [status, content_type, body.size()]
		)
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(body)
