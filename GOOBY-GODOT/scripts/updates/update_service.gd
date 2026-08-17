class_name UpdateService
extends Node
## „Suche nach Updates“-Service (Doc B §2.1; W2b UPDATES). Autoload-Kandidat
## „UpdateManager“ — der Name ist W1c-Kontrakt: settings_screen.gd ruft per
## Duck-Typing `/root/UpdateManager.check_for_updates()`.
##
## Flow: Manifest von konfigurierbarer URL holen (Default aus dem config-Pack;
## DEV/Tests: file://-Pfad) → Vergleich gegen max(eingebaut, installiert) →
## Download nach user://packs/<id>-v<version>.pck → sha256-Verify (HashingContext)
## → installed.json-Buchführung. min_native-Gate: Pack braucht neuere App →
## nicht laden, „braucht neue IPA“ melden. Offline-first: Fehler blockieren nie.
##
## W15/UPDREPO — GitHub-Release-API-Quelle: Das Update-Repo ist das PRIVATE
## Haupt-Repo; tokenlose browser-download-URLs (releases/download/…) liefern
## dort 404. Zeigt die manifest_url auf api.github.com ODER ist ein Token
## gesetzt (Kette: Override > user://-Settings > config-Pack `github_token`),
## läuft der Check über die Release-API: Release am Tag holen (Assets-Liste),
## manifest.json-Asset mit Accept: application/octet-stream laden, Pack-
## browser-URLs auf ihre Asset-API-URLs umschreiben. Authorization geht NUR
## an API-Hosts, nie an fremde Server. Der Direkt-URL-Pfad (öffentliche
## Repos/eigene Server, file://-Tests) bleibt unverändert funktionsfähig.

signal check_started
signal check_completed(result: int, details: Dictionary)
signal pack_downloaded(pack_id: String, version: String)

enum Result { UP_TO_DATE, UPDATED, NEEDS_NATIVE, ERROR }

const HTTP_TIMEOUT_SEC := 10.0
const GITHUB_API_HOST := "api.github.com"
## User-Settings der Updates-Sektion (Allowlist: github_token) — Doc W15.
const USER_OVERRIDE_PATH := "user://updates_user_override.json"
const ACCEPT_GITHUB_JSON := "application/vnd.github+json"
const ACCEPT_OCTET_STREAM := "application/octet-stream"
const _HASH_CHUNK_BYTES := 65536
## Panel-Fehlertext, wenn das private Repo ohne Token angefragt wurde.
const _TOKEN_REQUIRED_ERROR := (
	"Updates brauchen einen Zugangsschlüssel — Einstellungen → Updates "
	+ "(GitHub-Token, bekommst du vom Server-Betreiber)."
)

var packs_dir := "user://packs"
var content_root := "res://content"
## Leer → ProjectSettings application/config/version (Request: 5.0.0), Fallback "5.0.0".
var app_version := ""
## DEV/Tests: feste Manifest-Quelle (file:///abs/pfad, user://…, res://… oder http…).
var manifest_url_override := ""
## DEV/Tests: Token-Override — höchster Vorrang in der Token-Kette.
var github_token_override := ""
## Tests: zusätzliche Hosts (host[:port]), die wie api.github.com behandelt
## werden (lokaler API-Stub auf ephemerem Port).
var api_hosts_extra := PackedStringArray()
## Tests: Umleitung der User-Settings-Datei (user:// ist geteilt).
var user_override_path := USER_OVERRIDE_PATH

var _checking := false
var _seq_counter := 0
## API-Modus des laufenden Checks: Asset-Name → Asset-Dictionary + Token.
var _release_assets := {}
var _api_token := ""


## Kompletter Update-Check (Coroutine). Rückgabe { "result": Result, "details": {…} };
## Details: updated[{id,version}], gated[ids], native_update, errors[], notes_de.
## Feuert check_started / pack_downloaded / check_completed.
func check_for_updates() -> Dictionary:
	if _checking:
		return {"result": Result.ERROR, "details": {"busy": true}}
	_checking = true
	check_started.emit()
	var details := {
		"updated": [],
		"gated": [],
		"native_update": false,
		"latest_native": "",
		"errors": [],
		"notes_de": "",
		"token_required": false,
	}
	var outcome := await _run_check(details)
	_checking = false
	check_completed.emit(outcome, details)
	return {"result": outcome, "details": details}


func resolve_app_version() -> String:
	if not app_version.is_empty():
		return app_version
	var from_project := str(ProjectSettings.get_setting("application/config/version", ""))
	return from_project if UpdatesManifest.is_semver(from_project) else "5.0.0"


## Manifest-URL: Override (DEV/Tests) → Remote-Config (user://packs/config.json)
## → eingebauter config-Pack. Die eine feste URL ist Doc-B-Design (§2.1).
func resolve_manifest_url() -> String:
	if not manifest_url_override.is_empty():
		return manifest_url_override
	var user_url := _config_value_from_file(packs_dir + "/config.json", "manifest_url")
	if not user_url.is_empty():
		return user_url
	return _config_value_from_file(content_root + "/config/data/config.json", "manifest_url")


## GitHub-Token-Kette (W15/UPDREPO): Override (DEV/Tests) → user://-Settings
## (Updates-Sektion der Einstellungen) → Remote-Config (user://packs/config.json)
## → eingebauter config-Pack (`github_token`, optional). Leer = kein Token.
func resolve_github_token() -> String:
	if not github_token_override.is_empty():
		return github_token_override
	var user_token := str(load_user_override(user_override_path).get("github_token", ""))
	if not user_token.is_empty():
		return user_token
	var remote_token := _config_value_from_file(packs_dir + "/config.json", "github_token")
	if not remote_token.is_empty():
		return remote_token
	return _config_value_from_file(content_root + "/config/data/config.json", "github_token")


## Liest die User-Settings-Datei (Allowlist: github_token). Fehlend/kaputt → {}.
static func load_user_override(path: String = USER_OVERRIDE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	var out := {}
	if not str(data.get("github_token", "")).is_empty():
		out["github_token"] = str(data["github_token"])
	return out


## Schreibt die User-Settings-Datei (Allowlist); leeres Dictionary → Datei weg.
static func save_user_override(data: Dictionary, path: String = USER_OVERRIDE_PATH) -> void:
	var out := {}
	if not str(data.get("github_token", "")).is_empty():
		out["github_token"] = str(data["github_token"])
	if out.is_empty():
		clear_user_override(path)
		return
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("UpdateService: User-Settings nicht schreibbar: %s" % path)
		return
	file.store_string(JSON.stringify(out, "\t"))
	file.close()


static func clear_user_override(path: String = USER_OVERRIDE_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## ---------------------- GitHub-Release-API (W15/UPDREPO) — pure Bausteine


## Host (inkl. Port) einer URL — "" bei lokalen Schemata/Pfaden.
static func url_host(url: String) -> String:
	var rest := url
	var scheme := rest.find("://")
	if scheme < 0:
		return ""
	rest = rest.substr(scheme + 3)
	var slash := rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	return rest


## true, wenn die URL auf die GitHub-API zeigt (Tests: extra_hosts = Stub).
static func is_github_api_url(url: String, extra_hosts := PackedStringArray()) -> bool:
	var host := url_host(url)
	if host.is_empty():
		return false
	return host == GITHUB_API_HOST or extra_hosts.has(host)


## Zerlegt eine browser-download-URL
## (https://github.com/<owner>/<repo>/releases/download/<tag>/<datei>) in
## {owner, repo, tag, file} — {} wenn die URL kein GitHub-Release-Download ist.
static func parse_release_download_url(url: String) -> Dictionary:
	if url_host(url) != "github.com":
		return {}
	var path := url.substr(url.find("github.com/") + "github.com/".length())
	var parts := path.split("/")
	if parts.size() < 6 or parts[2] != "releases" or parts[3] != "download":
		return {}
	if parts[0].is_empty() or parts[1].is_empty() or parts[4].is_empty() or parts[5].is_empty():
		return {}
	return {"owner": parts[0], "repo": parts[1], "tag": parts[4], "file": parts[5]}


## browser-download-URL → Release-API-URL (…/releases/tags/<tag>); "" wenn keine.
static func api_release_url_for(url: String) -> String:
	var parts := parse_release_download_url(url)
	if parts.is_empty():
		return ""
	return (
		"https://%s/repos/%s/%s/releases/tags/%s"
		% [GITHUB_API_HOST, parts["owner"], parts["repo"], parts["tag"]]
	)


## Quelle der Manifest-URL: "api" (Release-API mit Assets-Liste) oder "direct"
## (unveränderter Alt-Pfad). API gilt für api.github.com-URLs immer, für
## browser-download-URLs nur MIT Token (öffentliche Repos bleiben tokenlos
## direkt — Abwärtskompatibilität). Fremde Hosts + lokale Schemata: direkt.
static func classify_manifest_source(
	url: String, token: String, extra_hosts := PackedStringArray()
) -> String:
	if is_github_api_url(url, extra_hosts):
		return "api"
	if not token.is_empty() and not parse_release_download_url(url).is_empty():
		return "api"
	return "direct"


## Header für GitHub-API-Requests; Authorization NUR wenn Token vorhanden.
static func github_headers(token: String, accept: String) -> PackedStringArray:
	var headers := PackedStringArray(
		[
			"Accept: " + accept,
			"X-GitHub-Api-Version: 2022-11-28",
			"User-Agent: GOOBY-Updater",
		]
	)
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	return headers


## Asset per Name aus einer Release-API-Antwort wählen ({} = nicht vorhanden).
static func select_release_asset(release: Dictionary, file_name: String) -> Dictionary:
	for asset: Variant in release.get("assets", []):
		if asset is Dictionary and str((asset as Dictionary).get("name", "")) == file_name:
			return asset
	return {}


## Streaming-sha256 einer Datei via HashingContext (hex, lowercase; "" bei Fehler).
static func sha256_of_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while not file.eof_reached():
		var chunk := file.get_buffer(_HASH_CHUNK_BYTES)
		if chunk.size() > 0:
			ctx.update(chunk)
	file.close()
	return ctx.finish().hex_encode()


func _run_check(details: Dictionary) -> int:
	var url := resolve_manifest_url()
	if url.is_empty():
		details["errors"].append("Keine Manifest-URL konfiguriert (config-Pack prüfen).")
		return Result.ERROR
	_api_token = resolve_github_token()
	_release_assets = {}
	var fetched := {}
	if classify_manifest_source(url, _api_token, api_hosts_extra) == "api":
		fetched = await _fetch_manifest_via_api(url, details)
	else:
		fetched = await _fetch_text(url)
	if not fetched["ok"]:
		details["errors"].append(fetched["error"])
		return Result.ERROR
	var parsed := UpdatesManifest.parse(fetched["text"])
	if not parsed["ok"]:
		details["errors"].append(parsed["error"])
		return Result.ERROR
	var manifest: Dictionary = parsed["manifest"]
	details["notes_de"] = str(manifest.get("notes_de", manifest.get("notes", "")))
	details["latest_native"] = str(manifest.get("latest_native", ""))
	var version := resolve_app_version()
	var installed := UpdatesManifest.read_installed(_installed_path())
	var plan := UpdatesManifest.plan_updates(manifest, installed, _builtin_versions(), version)
	details["native_update"] = plan["native_update"]
	for gated_entry: Dictionary in plan["gated"]:
		details["gated"].append(str(gated_entry["id"]))
	for entry: Dictionary in plan["to_install"]:
		var installed_ok := await _install_pack(entry, installed, details)
		if installed_ok:
			details["updated"].append({"id": str(entry["id"]), "version": str(entry["version"])})
			pack_downloaded.emit(str(entry["id"]), str(entry["version"]))
	UpdatesManifest.write_installed(_installed_path(), installed)
	return _final_result(details)


## Ergebnis-Priorität: UPDATED > ERROR > NEEDS_NATIVE > UP_TO_DATE.
func _final_result(details: Dictionary) -> int:
	if not details["updated"].is_empty():
		_reload_registry_if_present()
		return Result.UPDATED
	if not details["errors"].is_empty():
		return Result.ERROR
	if details["native_update"] or not details["gated"].is_empty():
		return Result.NEEDS_NATIVE
	return Result.UP_TO_DATE


## Ein Pack herunterladen + verifizieren + verbuchen. true = installiert.
func _install_pack(entry: Dictionary, installed: Dictionary, details: Dictionary) -> bool:
	var pack_id := str(entry["id"])
	var version := str(entry["version"])
	var is_json := str(entry.get("type", "pck")) == "json" or pack_id == "config"
	var file_name := "config.json" if is_json else "%s-v%s.pck" % [pack_id, version]
	var tmp_path := "%s/tmp/%s.part" % [packs_dir, file_name]
	_ensure_dir(packs_dir + "/tmp")
	var source := _resolve_pack_source(str(entry["url"]))
	if not source["ok"]:
		details["errors"].append("%s: %s" % [pack_id, source["error"]])
		return false
	var downloaded := await _download_file(str(source["url"]), tmp_path, source["headers"])
	if not downloaded["ok"]:
		details["errors"].append("%s: %s" % [pack_id, downloaded["error"]])
		return false
	var got_sha := sha256_of_file(tmp_path)
	var want_sha := str(entry["sha256"]).to_lower()
	if got_sha != want_sha:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
		details["errors"].append(
			(
				"%s: sha256-Mismatch (erwartet %s…, bekommen %s…) — Download verworfen."
				% [pack_id, want_sha.substr(0, 12), got_sha.substr(0, 12)]
			)
		)
		return false
	var dest_path := "%s/%s" % [packs_dir, file_name]
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(dest_path)
	)
	if err != OK:
		details["errors"].append("%s: Konnte Download nicht ablegen (Fehler %d)." % [pack_id, err])
		return false
	_record_install(installed, entry, file_name, is_json)
	return true


## installed.json-Eintrag schreiben; alte Datei bleibt als `previous` liegen
## (Rollback-Reserve, wird beim nächsten Erfolgs-Boot gelöscht — Doc B §2.5).
func _record_install(
	installed: Dictionary, entry: Dictionary, file_name: String, is_json: bool
) -> void:
	var pack_id := str(entry["id"])
	var packs: Dictionary = installed["packs"]
	var old_entry: Dictionary = packs.get(pack_id, {})
	var record := {
		"version": str(entry["version"]),
		"file": file_name,
		"sha256": str(entry["sha256"]).to_lower(),
		"min_native": str(entry["min_native"]),
		"priority": UpdatesManifest.priority_of(entry),
		"type": "json" if is_json else "pck",
		"enabled": true,
		"installed_at": Time.get_datetime_string_from_system(true) + "Z",
		"installed_seq": _next_seq(installed),
		"survived_boot": is_json,
	}
	var old_file := str(old_entry.get("file", ""))
	if not is_json and not old_file.is_empty() and old_file != file_name:
		var stale_previous := str(old_entry.get("previous", ""))
		if not stale_previous.is_empty() and stale_previous != old_file:
			_remove_pack_file(stale_previous)
		record["previous"] = old_file
		record["previous_version"] = str(old_entry.get("version", "0.0.0"))
		record["previous_sha256"] = str(old_entry.get("sha256", ""))
	packs[pack_id] = record


func _next_seq(installed: Dictionary) -> int:
	var highest := _seq_counter
	for pack_id: String in installed["packs"]:
		highest = maxi(highest, int(installed["packs"][pack_id].get("installed_seq", 0)))
	_seq_counter = highest + 1
	return _seq_counter


## GitHub-Release-API-Weg (W15/UPDREPO): Release am Tag holen (JSON mit
## Assets-Liste), Assets für die Pack-Downloads merken, dann das
## manifest.json-Asset mit Accept: application/octet-stream laden.
## Scheitert der Release-Abruf am privaten Repo OHNE Token (GitHub antwortet
## 404, bei API-Limit 401/403), meldet details.token_required den klaren
## Panel-Hinweis statt des generischen Fehler-Toasts.
func _fetch_manifest_via_api(url: String, details: Dictionary) -> Dictionary:
	var release_url := url
	if not is_github_api_url(url, api_hosts_extra):
		release_url = api_release_url_for(url)
	var release_fetch := await _fetch_text(
		release_url, github_headers(_api_token, ACCEPT_GITHUB_JSON)
	)
	if not release_fetch["ok"]:
		var code := int(release_fetch.get("code", 0))
		if code in [401, 403, 404]:
			if _api_token.is_empty():
				details["token_required"] = true
				return {"ok": false, "error": _TOKEN_REQUIRED_ERROR, "text": "", "code": code}
			return {
				"ok": false,
				"error":
				(
					"Zugangsschlüssel abgelehnt (http=%d) — GitHub-Token in den " % code
					+ "Einstellungen prüfen."
				),
				"text": "",
				"code": code,
			}
		return release_fetch
	var json := JSON.new()
	if json.parse(str(release_fetch["text"])) != OK or not (json.data is Dictionary):
		return {"ok": false, "error": "Release-API-Antwort ist kein JSON-Objekt.", "text": ""}
	var release: Dictionary = json.data
	for asset: Variant in release.get("assets", []):
		if asset is Dictionary and not str((asset as Dictionary).get("name", "")).is_empty():
			_release_assets[str((asset as Dictionary)["name"])] = asset
	var manifest_asset := select_release_asset(release, "manifest.json")
	if manifest_asset.is_empty():
		return {
			"ok": false,
			"error": "Release hat kein manifest.json-Asset (Pack-Release prüfen).",
			"text": "",
		}
	return await _fetch_text(
		str(manifest_asset.get("url", "")), github_headers(_api_token, ACCEPT_OCTET_STREAM)
	)


## Pack-URL → tatsächliche Download-Quelle {ok, url, headers, error}.
## Direkt-Modus (keine Assets-Liste gemerkt): unverändert, OHNE Zusatz-Header.
## API-Modus: browser-download-URLs werden über die Assets-Liste auf ihre
## Asset-API-URL umgeschrieben (Accept: octet-stream + Authorization).
## Lokale Schemata bleiben immer direkt; das Token geht NIE an fremde Hosts.
func _resolve_pack_source(url: String) -> Dictionary:
	var direct := {"ok": true, "url": url, "headers": PackedStringArray(), "error": ""}
	if _release_assets.is_empty() or not _local_path_for(url).is_empty():
		return direct
	if is_github_api_url(url, api_hosts_extra):
		direct["headers"] = github_headers(_api_token, ACCEPT_OCTET_STREAM)
		return direct
	var parts := parse_release_download_url(url)
	if parts.is_empty():
		return direct
	var asset: Dictionary = _release_assets.get(str(parts["file"]), {})
	if asset.is_empty():
		return {
			"ok": false,
			"url": "",
			"headers": PackedStringArray(),
			"error":
			(
				"Asset '%s' fehlt im Release (Manifest und Release nicht synchron)."
				% str(parts["file"])
			),
		}
	return {
		"ok": true,
		"url": str(asset.get("url", "")),
		"headers": github_headers(_api_token, ACCEPT_OCTET_STREAM),
		"error": "",
	}


## Manifest-Text holen. Lokale Schemata (file://, user://, res://, /abs) lesen
## direkt vom Dateisystem — der DEV-/Test-Weg. Sonst HTTPRequest mit Timeout.
func _fetch_text(url: String, headers := PackedStringArray()) -> Dictionary:
	var local_path := _local_path_for(url)
	if not local_path.is_empty():
		if not FileAccess.file_exists(local_path):
			return {
				"ok": false,
				"error": "Manifest nicht gefunden: %s" % local_path,
				"text": "",
				"code": 0,
			}
		return {
			"ok": true, "error": "", "text": FileAccess.get_file_as_string(local_path), "code": 200
		}
	if not is_inside_tree():
		return {
			"ok": false,
			"error": "HTTP braucht einen SceneTree (Node nicht im Tree).",
			"text": "",
			"code": 0,
		}
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SEC
	add_child(http)
	var err := http.request(url, headers)
	if err != OK:
		http.queue_free()
		return {
			"ok": false,
			"error": "HTTP-Request fehlgeschlagen (Fehler %d)." % err,
			"text": "",
			"code": 0,
		}
	var response: Array = await http.request_completed
	http.queue_free()
	var http_result := int(response[0])
	var code := int(response[1])
	if http_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return {
			"ok": false,
			"error": "Manifest nicht erreichbar (result=%d, http=%d)." % [http_result, code],
			"text": "",
			"code": code,
		}
	var body: PackedByteArray = response[3]
	return {"ok": true, "error": "", "text": body.get_string_from_utf8(), "code": code}


## Datei nach dest_path laden (lokal = Kopie, http(s) = HTTPRequest.download_file).
func _download_file(url: String, dest_path: String, headers := PackedStringArray()) -> Dictionary:
	var local_path := _local_path_for(url)
	if not local_path.is_empty():
		return _copy_local(local_path, dest_path)
	if not is_inside_tree():
		return {"ok": false, "error": "HTTP braucht einen SceneTree (Node nicht im Tree)."}
	var http := HTTPRequest.new()
	http.timeout = HTTP_TIMEOUT_SEC
	http.download_file = dest_path
	add_child(http)
	var err := http.request(url, headers)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Download-Request fehlgeschlagen (Fehler %d)." % err}
	var response: Array = await http.request_completed
	http.queue_free()
	var http_result := int(response[0])
	var code := int(response[1])
	if http_result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var why := "Download fehlgeschlagen (result=%d, http=%d)." % [http_result, code]
		return {"ok": false, "error": why}
	return {"ok": true, "error": ""}


func _copy_local(source_path: String, dest_path: String) -> Dictionary:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "Quelle nicht lesbar: %s" % source_path}
	var dest := FileAccess.open(dest_path, FileAccess.WRITE)
	if dest == null:
		source.close()
		return {"ok": false, "error": "Ziel nicht schreibbar: %s" % dest_path}
	while not source.eof_reached():
		var chunk := source.get_buffer(_HASH_CHUNK_BYTES)
		if chunk.size() > 0:
			dest.store_buffer(chunk)
	source.close()
	dest.close()
	return {"ok": true, "error": ""}


## file:///abs, /abs, user://, res:// → lesbarer Pfad; "" = kein lokales Schema.
func _local_path_for(url: String) -> String:
	if url.begins_with("file://"):
		return url.trim_prefix("file://")
	if url.begins_with("user://") or url.begins_with("res://") or url.begins_with("/"):
		return url
	return ""


func _config_value_from_file(path: String, key: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return ""
	return str(json.data.get(key, ""))


func _builtin_versions() -> Dictionary:
	var loader := get_node_or_null("/root/PackLoader")
	if loader != null and "builtin_versions" in loader:
		var cached: Dictionary = loader.builtin_versions
		if not cached.is_empty():
			return cached
	return UpdatesManifest.read_builtin_versions(content_root)


func _reload_registry_if_present() -> void:
	var registry := get_node_or_null("/root/ContentRegistry")
	if registry != null and registry.has_method("reload"):
		registry.reload()


func _installed_path() -> String:
	return packs_dir + "/installed.json"


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)


func _remove_pack_file(file_name: String) -> void:
	var path := "%s/%s" % [packs_dir, file_name]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
