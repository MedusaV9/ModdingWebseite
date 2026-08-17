#!/usr/bin/env ruby
# frozen_string_literal: true

# GOOBY-WIDGETS: injiziert die WidgetKit-Extension + die goobykit-Swift-
# Laufzeit in das von Godot exportierte Xcode-Projekt (ios-ipa-Job, NACH
# `godot --export-release`, VOR xcodebuild). Idempotent: ein zweiter Lauf
# auf demselben Projekt aendert nichts mehr.
#
# Was passiert (gegen den ECHTEN Godot-4.4.1-Export verifiziert — der
# Template-Aufbau: App-Target "GOOBY", CODE_SIGN_ENTITLEMENTS
# GOOBY/GOOBY.entitlements (leer), INFOPLIST GOOBY/GOOBY-Info.plist mit
# $(MARKETING_VERSION)-Platzhaltern, dummy.cpp ruft goobykit_init()):
#  1. App-Target: GoobyKitRuntime.swift + GoobyKitShared.swift als Sources
#     (SWIFT_VERSION setzen — das Template kompiliert sonst kein Swift),
#     App-Group in die BESTEHENDE Entitlements-Datei mergen,
#     NSSupportsLiveActivities=true in die App-Info.plist.
#  2. Neues Target "GoobyWidgets" (app_extension, min iOS 16.2) mit den
#     SwiftUI-Quellen aus GOOBY-GODOT/ios/widgets/, eigener Info.plist +
#     Entitlements; eingebettet via PlugIns-Copy-Phase + Target-Dependency
#     (das bestehende GOOBY-Scheme baut die Extension dadurch mit).
#  3. Beide Entitlements-Dateien landen zusaetzlich als Bundle-Ressourcen
#     in .app/.appex — die IPA ist unsigniert, AltStore/SideStore lesen die
#     App-Group daraus beim Re-Signieren.
#
# WidgetKit/ActivityKit werden NICHT explizit gelinkt: Swift-Autolink +
# ld64-Availability-Weak-Linking (Xcode 15+) erledigen das; ActivityKit
# (iOS 16.1+) wird bei Deployment-Target 15.0 automatisch weak.
#
# Aufruf:
#   ruby tools/ci/inject_widgets.rb <GOOBY.xcodeproj> <widgets-src-dir> \
#     <plugin-src-dir> <app-group-id> <widget-bundle-id>

require "fileutils"

begin
  require "xcodeproj"
rescue LoadError
  abort "FEHLER: ruby-Gem 'xcodeproj' fehlt — `gem install xcodeproj --no-document`."
end

if ARGV.length != 5
  abort "Aufruf: inject_widgets.rb <xcodeproj> <widgets-src> <plugin-src> <app-group> <widget-bundle-id>"
end

PROJECT_PATH, WIDGETS_SRC, PLUGIN_SRC, APP_GROUP, WIDGET_BUNDLE_ID = ARGV
EXT_NAME = "GoobyWidgets"
EXT_MIN_IOS = "16.2"
SWIFT_VERSION = "5.0"
GROUPS_KEY = "com.apple.security.application-groups"

abort "FEHLER: #{PROJECT_PATH} fehlt (Godot-Export gelaufen?)" unless File.directory?(PROJECT_PATH)
abort "FEHLER: Widget-Quellen fehlen: #{WIDGETS_SRC}" unless File.directory?(WIDGETS_SRC)
abort "FEHLER: Plugin-Quellen fehlen: #{PLUGIN_SRC}" unless File.directory?(PLUGIN_SRC)

project_dir = File.dirname(File.expand_path(PROJECT_PATH))
project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.product_type == "com.apple.product-type.application" }
abort "FEHLER: kein App-Target im Projekt gefunden." if app_target.nil?
puts "App-Target: #{app_target.name}"

def resolved(target, key)
  values = target.resolved_build_setting(key).values.compact
  values.empty? ? nil : values.first
end

# ---------------------------------------------------------------------------
# Quellen in das (wegwerfbare) Export-Projektverzeichnis kopieren, damit das
# Xcode-Projekt in sich geschlossen bleibt (relative Referenzen).
# ---------------------------------------------------------------------------
ext_dir = File.join(project_dir, "goobywidgets")
runtime_dir = File.join(project_dir, "goobykit_runtime")
FileUtils.mkdir_p([ext_dir, runtime_dir])
Dir.glob(File.join(WIDGETS_SRC, "*.{swift,plist,entitlements}")).each do |file|
  FileUtils.cp(file, ext_dir)
end
FileUtils.cp(File.join(PLUGIN_SRC, "GoobyKitRuntime.swift"), runtime_dir)
FileUtils.cp(File.join(WIDGETS_SRC, "GoobyKitShared.swift"), runtime_dir)

# ---------------------------------------------------------------------------
# App-Entitlements: App-Group in die vom Godot-Export angelegte Datei mergen.
# ---------------------------------------------------------------------------
app_entitlements_rel = resolved(app_target, "CODE_SIGN_ENTITLEMENTS") || "#{app_target.name}.entitlements"
app_entitlements_path = File.join(project_dir, app_entitlements_rel)
app_entitlements =
  File.exist?(app_entitlements_path) ? Xcodeproj::Plist.read_from_path(app_entitlements_path) : {}
app_entitlements = {} if app_entitlements.nil?
groups = app_entitlements[GROUPS_KEY] || []
unless groups.include?(APP_GROUP)
  app_entitlements[GROUPS_KEY] = groups + [APP_GROUP]
  Xcodeproj::Plist.write_to_path(app_entitlements, app_entitlements_path)
end
puts "App-Entitlements: #{app_entitlements_rel} (+ Gruppe #{APP_GROUP})"

# ---------------------------------------------------------------------------
# App-Info.plist: NSSupportsLiveActivities; Versionen vom App-Target lesen.
# ---------------------------------------------------------------------------
info_plist_rel = resolved(app_target, "INFOPLIST_FILE")
abort "FEHLER: INFOPLIST_FILE des App-Targets nicht gefunden." if info_plist_rel.nil?
info_plist_path = File.join(project_dir, info_plist_rel)
info = Xcodeproj::Plist.read_from_path(info_plist_path)
unless info["NSSupportsLiveActivities"] == true
  info["NSSupportsLiveActivities"] = true
  Xcodeproj::Plist.write_to_path(info, info_plist_path)
end
marketing_version = resolved(app_target, "MARKETING_VERSION") || "1.0.0"
project_version = resolved(app_target, "CURRENT_PROJECT_VERSION") || "1"
puts "App-Info.plist: NSSupportsLiveActivities=true (v#{marketing_version})"

# ---------------------------------------------------------------------------
# Datei-Referenzen (idempotent ueber project.files-Lookup).
# ---------------------------------------------------------------------------
def file_ref(project, group, path)
  project.files.find { |f| f.path == path } || group.new_reference(path)
end

def add_source(target, ref)
  return if target.source_build_phase.files_references.include?(ref)
  target.source_build_phase.add_file_reference(ref, true)
end

def add_resource(target, ref)
  return if target.resources_build_phase.files_references.include?(ref)
  target.resources_build_phase.add_file_reference(ref, true)
end

kit_group = project.main_group.find_subpath("GoobyKit", true)
kit_group.set_source_tree("<group>")
runtime_ref = file_ref(project, kit_group, "goobykit_runtime/GoobyKitRuntime.swift")
shared_app_ref = file_ref(project, kit_group, "goobykit_runtime/GoobyKitShared.swift")
app_entitlements_ref = file_ref(project, kit_group, app_entitlements_rel)

ext_group = project.main_group.find_subpath(EXT_NAME, true)
ext_group.set_source_tree("<group>")
ext_swift_refs = Dir.glob(File.join(ext_dir, "*.swift")).sort.map do |file|
  file_ref(project, ext_group, "goobywidgets/#{File.basename(file)}")
end
ext_entitlements_ref = file_ref(project, ext_group, "goobywidgets/GoobyWidgets.entitlements")

# ---------------------------------------------------------------------------
# App-Target: Swift-Laufzeit + Settings.
# ---------------------------------------------------------------------------
add_source(app_target, runtime_ref)
add_source(app_target, shared_app_ref)
# Entitlements als Bundle-Ressource: sichtbar fuer Sideload-Signierer.
add_resource(app_target, app_entitlements_ref)

app_target.build_configurations.each do |config|
  config.build_settings["SWIFT_VERSION"] = SWIFT_VERSION
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = app_entitlements_rel
end

# ---------------------------------------------------------------------------
# Extension-Target.
# ---------------------------------------------------------------------------
ext_target = project.targets.find { |t| t.name == EXT_NAME }
if ext_target.nil?
  ext_target = project.new_target(:app_extension, EXT_NAME, :ios, EXT_MIN_IOS)
  puts "Target #{EXT_NAME} angelegt (app_extension, min iOS #{EXT_MIN_IOS})"
else
  puts "Target #{EXT_NAME} existiert bereits — Settings werden angeglichen."
end

ext_swift_refs.each { |ref| add_source(ext_target, ref) }
add_resource(ext_target, ext_entitlements_ref)

ext_target.build_configurations.each do |config|
  settings = config.build_settings
  settings["PRODUCT_NAME"] = EXT_NAME
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = WIDGET_BUNDLE_ID
  settings["INFOPLIST_FILE"] = "goobywidgets/Info.plist"
  settings["GENERATE_INFOPLIST_FILE"] = "NO"
  settings["CODE_SIGN_ENTITLEMENTS"] = "goobywidgets/GoobyWidgets.entitlements"
  settings["SWIFT_VERSION"] = SWIFT_VERSION
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = EXT_MIN_IOS
  settings["TARGETED_DEVICE_FAMILY"] = "1,2"
  settings["SKIP_INSTALL"] = "YES"
  settings["ARCHS"] = "arm64"
  settings["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"
  ]
  # Versionen 1:1 vom App-Target (beide Info.plists nutzen die Platzhalter).
  settings["MARKETING_VERSION"] = marketing_version
  settings["CURRENT_PROJECT_VERSION"] = project_version
end

# ---------------------------------------------------------------------------
# Einbetten: Dependency + PlugIns-Copy-Phase.
# ---------------------------------------------------------------------------
unless app_target.dependencies.any? { |d| d.target == ext_target }
  app_target.add_dependency(ext_target)
end

embed_phase = app_target.copy_files_build_phases.find { |p| p.name == "Embed App Extensions" }
if embed_phase.nil?
  embed_phase = app_target.new_copy_files_build_phase("Embed App Extensions")
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
unless embed_phase.files_references.include?(ext_target.product_reference)
  build_file = embed_phase.add_file_reference(ext_target.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

project.save
puts "OK: #{EXT_NAME} injiziert — App-Group #{APP_GROUP}, Bundle-Id #{WIDGET_BUNDLE_ID}."
