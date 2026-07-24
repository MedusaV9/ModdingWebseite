extends RefCounted
## OS-Bridge STUB (W1d/STATE) — iOS-NSUserDefaults-Leser fuer den
## Legacy-Web-Save. BACKLOG-MARKER: die native Seite ist NICHT Teil von W1
## (Doc H §5.3 "iOS-Import-Realitaet"); dieses Interface ist eingefroren,
## damit der Boot-Flow (W1a main.gd) heute schon dagegen programmieren kann.
##
## WIE DAS NATIVE PLUGIN ES IMPLEMENTIERT (Doc H §5.3, recherchiert):
## - Die Alt-App (Capacitor-WebView, Bundle-Id com.permissionmaxed.gooby)
##   spiegelt JEDEN persist() nach @capacitor/preferences == NSUserDefaults,
##   physisch `Library/Preferences/com.permissionmaxed.gooby.plist`.
##   Erwarteter Key: `CapacitorStorage.gooby.save` (Prefix "CapacitorStorage."
##   ist die Capacitor-Default-Gruppe — AUF ECHTEM GERAET VERIFIZIEREN;
##   Plan B: alle UserDefaults-Keys dumpen und `*gooby.save` suchen).
## - iOS-Update-Semantik: eine .ipa mit DERSELBEN Bundle-Id ersetzt nur das
##   App-Bundle, der Container (Library/) BLEIBT — auch bei TestFlight/
##   Sideloading. Loeschen + Neuinstallation wipet dagegen alles →
##   Onboarding-Warnung "Alte App NICHT loeschen, drueber installieren!".
## - Godot-Seite: ~40-Zeilen-ObjC-Plugin `legacy_save_reader` mit
##   `[[NSUserDefaults standardUserDefaults] stringForKey:@"CapacitorStorage.gooby.save"]`,
##   angebunden als iOS-Export-Plugin (.gdip). Fallback OHNE Plugin:
##   bplist00-Parser in GDScript (~200 LOC, Format dokumentiert) direkt auf
##   dem Plist-Pfad (NSHomeDirectory()/Library/Preferences/… ist im eigenen
##   Sandbox-Container lesbar via OS.get_environment("HOME")).
## - Der zurueckgegebene String ist der ROHE v4-Save-JSON → direkt in
##   MigrationV4.migrate_any() geben (gleicher Pfad wie der Umzugskoffer).
##   Import-Reihenfolge beim ersten Start: 1. user://save_v5.json → normal.
##   2. read_legacy_capacitor_save() != null → Vorschau + "Uebernehmen".
##   3. nichts → Onboarding mit "Ich habe einen alten Spielstand"-Option.

## NSUserDefaults-Key des Capacitor-Preferences-Mirrors (Doc H §5.3).
const LEGACY_SAVE_KEY := "CapacitorStorage.gooby.save"
## Name des kuenftigen iOS-Plugin-Singletons (Engine.get_singleton).
const IOS_PLUGIN_NAME := "LegacySaveReader"


## Liest den Legacy-Capacitor-Save (roher v4-JSON-String) oder null.
## STUB: liefert heute nur auf iOS MIT installiertem Plugin Daten; ueberall
## sonst (Editor, Desktop, Android, iOS ohne Plugin) → null.
static func read_legacy_capacitor_save() -> Variant:
	if OS.get_name() != "iOS":
		return null
	if not Engine.has_singleton(IOS_PLUGIN_NAME):
		# BACKLOG: bplist-Fallback-Parser (Doc H §5.3) landet hier.
		return null
	var plugin: Object = Engine.get_singleton(IOS_PLUGIN_NAME)
	if not plugin.has_method("string_for_key"):
		return null
	var value: Variant = plugin.call("string_for_key", LEGACY_SAVE_KEY)
	if value is String and not value.is_empty():
		return value
	return null


## True wenn auf dieser Plattform ueberhaupt ein Legacy-Fund moeglich ist
## (steuert, ob der Boot-Flow die Import-Vorschau anbieten soll).
static func legacy_save_possible() -> bool:
	return OS.get_name() == "iOS"
