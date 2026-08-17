extends RefCounted
## Legacy-Capacitor-Save-Leser (FIX-6; Doc H §5.3 — der Weg OHNE Plugin).
##
## Die Alt-App ist ein Capacitor-Web-Spiel mit DERSELBEN Bundle-Id
## (com.permissionmaxed.gooby). Wird die neue .ipa DRUEBER installiert
## (gleiche Bundle-Id, TestFlight/Sideload), bleibt der App-Container
## erhalten — und damit die Altdaten. Fundorte im Container:
##
## 1. `Library/Preferences/com.permissionmaxed.gooby.plist` (NSUserDefaults):
##    Die Alt-App spiegelt seit v1 (G13, web core/save.js) JEDEN persist()
##    nach @capacitor/preferences → Key `CapacitorStorage.gooby.save`, Wert =
##    roher v0–v4-Save-JSON. DAS liest dieser Reader — als Binaer-Plist ueber
##    bplist.gd, ganz ohne natives Plugin (eigener Sandbox-Container ist per
##    FileAccess lesbar; HOME zeigt auf den Container-Root).
## 2. `Library/WebKit/WebsiteData/**/LocalStorage/*.sqlite3` (WKWebView-
##    localStorage): waere die zweite Quelle, ist aber SQLite-Binaerformat —
##    dafuer braeuchte es einen SQLite-Reader oder ein natives Plugin.
##    BEWUSST NICHT implementiert: die Preferences-Spiegelung (1) traegt
##    denselben Stand und ist die von der Alt-App vorgesehene, robuste Quelle.
##    Nur URALT-Installationen, die nie ein Update mit der Spiegelung gesehen
##    haben, haetten ausschliesslich localStorage → fuer die bleibt der
##    manuelle Weg (Export-Knopf in der Alt-App → Transfer-Screen).
##
## Ein spaeteres natives Plugin (`LegacySaveReader`, ~40 Zeilen ObjC mit
## `stringForKey:`) wird ZUERST probiert, falls es je gebaut wird — dieser
## Reader ist der heute funktionierende Fallback dahinter.

const BPlist := preload("res://scripts/state/import/bplist.gd")

const BUNDLE_ID := "com.permissionmaxed.gooby"
const SAVE_KEY := "CapacitorStorage.gooby.save"
const IOS_PLUGIN_NAME := "LegacySaveReader"


## Legacy-Save-JSON finden. {"ok", "json", "source", "error"} — ok=false mit
## error=="" heisst schlicht "nichts gefunden" (kein Fehlerfall).
static func read_save_json(plist_override := "") -> Dictionary:
	var via_plugin: Variant = _read_via_plugin()
	if via_plugin != null:
		return {"ok": true, "json": via_plugin, "source": "ios-plugin", "error": ""}
	var path := plist_override if not plist_override.is_empty() else default_plist_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "json": "", "source": "", "error": ""}
	return read_from_plist(path)


## Standard-Fundort der NSUserDefaults-Datei im eigenen Container.
static func default_plist_path() -> String:
	var home := OS.get_environment("HOME")
	if home.is_empty():
		return ""
	return home.path_join("Library/Preferences/%s.plist" % BUNDLE_ID)


## Plist parsen + Save-Key suchen. {"ok", "json", "source", "error"}.
static func read_from_plist(path: String) -> Dictionary:
	var parsed := BPlist.parse_file(path)
	if not parsed["ok"]:
		return {"ok": false, "json": "", "source": "", "error": str(parsed["error"])}
	if not (parsed["value"] is Dictionary):
		return {"ok": false, "json": "", "source": "", "error": "plist root is not a dict"}
	var root: Dictionary = parsed["value"]
	var json := _find_save_value(root)
	if json.is_empty():
		return {"ok": false, "json": "", "source": "", "error": ""}
	return {"ok": true, "json": json, "source": "ios-preferences", "error": ""}


## Exakter Key zuerst; Plan B (Doc H §5.3): jeder Key `*gooby.save`
## (Capacitor-Gruppen-Prefix koennte auf echten Geraeten abweichen).
static func _find_save_value(root: Dictionary) -> String:
	var exact: Variant = root.get(SAVE_KEY)
	if exact is String and not (exact as String).is_empty():
		return exact
	for key: Variant in root.keys():
		if key is String and (key as String).ends_with("gooby.save"):
			var value: Variant = root[key]
			if value is String and not (value as String).is_empty():
				return value
	return ""


static func _read_via_plugin() -> Variant:
	if not Engine.has_singleton(IOS_PLUGIN_NAME):
		return null
	var plugin: Object = Engine.get_singleton(IOS_PLUGIN_NAME)
	if not plugin.has_method("string_for_key"):
		return null
	var value: Variant = plugin.call("string_for_key", SAVE_KEY)
	if value is String and not (value as String).is_empty():
		return value
	return null
