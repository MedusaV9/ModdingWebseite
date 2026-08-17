class_name BuildLagerUi
extends Node
## W21 P2 „Welt zuerst“ — VERHALTEN des Lager-Blatts im Bau-Dock (das
## Layout der Chips baut BuildUiDock: item_chip/set_kategorien):
## - Bild-Chips mit Zähler-Badge: Thumbnails aus der geteilten
##   CraftVorschau-Bäckerei (SubViewport-Renderer der Cosmetics, Muster
##   craft_panel.gd) — bis die Bäckerei fertig ist, trägt der Chip sein
##   Kategorie-Icon; fertige Texturen rüsten per fertig()-Signal nach.
## - Kategorie-Chips im Griff filtern das Blatt (erneuter Tap = „alle“);
##   wer eine Kategorie wählt, will stöbern → das Blatt klappt auf.
## - Chip-Stagger beim Aufklappen (MotionKit, Reduced-Motion-gated).
## BuildMode delegiert über refresh()/stagger_chips()/scroll_zu() und hört
## auf item_gewaehlt (Drawer-Tap → Ghost/Spann-Flow; programmatische
## Starts wie der Bett-Quest-Autostart bleiben bewusst stumm).

signal item_gewaehlt(def: Dictionary)

var _dock_ui: BuildUiDock
var _gs: Object
## Geteilte Thumbnail-Bäckerei der Bild-Chips.
var _vorschau: CraftVorschau
## Aktiver Kategorie-Filter des Item-Blatts ("" = alle Kategorien).
var _kat_filter := ""
## Signatur des letzten Aufbaus (Inhalt + Kapazität + Filter) —
## unverändertes Lager wird nicht neu gebaut (FIX-3: Öffnen-Ruckler).
var _sig := ""


func setup(dock_ui: BuildUiDock, gs: Object) -> void:
	_dock_ui = dock_ui
	_gs = gs
	_vorschau = CraftVorschau.new()
	_vorschau.name = "ChipVorschau"
	add_child(_vorschau)
	_vorschau.fertig.connect(_on_vorschau_fertig)
	# Manueller Griff-Tap (Blatt auf/zu) klingt als Toggle — die
	# programmatische Klapp-Choreographie bleibt bewusst stumm.
	dock_ui.kontext.griff.pressed.connect(func() -> void: AudioDirector.try_play(self, "ui_toggle"))


## Lager-Blatt neu bestücken: Kapazitäts-Titel, Kategorie-Chips und
## Bild-Chips (Thumbnail sofort aus dem Bäckerei-Cache oder später per
## fertig()) — W21 P2: Bild-Chip statt 295-px-Text-Pille.
func refresh() -> void:
	var storage: Array = HomeState.storage(_gs) if _gs != null else []
	var cap := HomeState.storage_capacity(_gs) if _gs != null else 100
	var sig := "%s|%d|%s" % [str(storage), cap, _kat_filter]
	if sig == _sig:
		return
	_sig = sig
	var items := _dock_ui.drawer_items
	for child in items.get_children():
		# remove_child VOR queue_free: die Chip-Namen (Chip_<id>) werden
		# sofort frei — der Neuaufbau erbt sie ohne @-Umbenennung.
		items.remove_child(child)
		child.queue_free()
	var used := StorageLogic.points_used(storage, FurnitureCatalog.defs())
	# W21: Kurzform-Fallback (build_ui_dock) — Ellipse fraß hochkant die Zahl.
	_dock_ui.set_capacity_text(used, cap)
	_kategorien_bestuecken(storage)
	if storage.is_empty():
		var empty := Label.new()
		empty.text = I18nService.t("build.leer")
		items.add_child(empty)
		return
	var chips: Array = []
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		if def.is_empty():
			continue
		if _kat_filter != "" and str(def.get("kategorie", "")) != _kat_filter:
			continue
		var btn := _dock_ui.item_chip(def, int(entry.get("count", 1)))
		btn.pressed.connect(_on_chip.bind(def))
		if _vorschau != null:
			_dock_ui.chip_textur(btn, _vorschau.hole_item(str(def["id"])))
		items.add_child(btn)
		chips.append(btn)
	# Voller Metrik-Pass NACH dem Neuaufbau: die Dock-Breite hugt den
	# Zeilen-Inhalt — ohne Nachführung bräche die Griff-Zeile nach dem
	# Kategorie-Chip-Aufbau um (doppelte Zeilenhöhe fraß das Welt-Budget).
	_dock_ui.apply_metrics()
	# Chip-Stagger nur wenn das Blatt gerade zu sehen ist — unsichtbare
	# Tweens wären reine Arbeit ohne Auftritt.
	if _dock_ui.ui.visible and not _dock_ui.lager_eingeklappt():
		MotionKit.stagger_ein(chips)


## Chip-Stagger beim Aufklappen (Werkzeug endet → Stöber-Einladung).
func stagger_chips() -> void:
	MotionKit.stagger_ein(_dock_ui.drawer_items.get_children().filter(_ist_control))


## Auto-Scroll zum Chip eines Items (W21-Befund 3: der frisch eingelagerte
## Chip lag unsichtbar rechts außerhalb des Scroll-Fensters) — deferred,
## der neue Chip braucht erst seinen Layout-Pass.
func scroll_zu(item_id: String) -> void:
	_dock_ui.blatt_scroll_zu.call_deferred(item_id)


## Kategorie-Chips der Griff-Zeile: nur Kategorien, die im Lager wirklich
## vorkommen (Reihenfolge des ersten Auftauchens); ein verwaister Filter
## (letztes Item der Kategorie herausgenommen) fällt auf „alle“ zurück.
func _kategorien_bestuecken(storage: Array) -> void:
	var kategorien: Array[String] = []
	for entry: Variant in storage:
		if not (entry is Dictionary):
			continue
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		var kat := str(def.get("kategorie", ""))
		if kat != "" and not kategorien.has(kat):
			kategorien.append(kat)
	if _kat_filter != "" and not kategorien.has(_kat_filter):
		_kat_filter = ""
	for chip in _dock_ui.set_kategorien(kategorien):
		chip.pressed.connect(_on_kat_chip.bind(str(chip.get_meta("bau_kategorie", ""))))
	_dock_ui.set_aktive_kategorie(_kat_filter)


## Kategorie-Chip im Griff: Filter togglen (erneuter Tap = „alle“) und das
## Blatt aufklappen — wer eine Kategorie wählt, will stöbern.
func _on_kat_chip(kategorie: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	_kat_filter = "" if _kat_filter == kategorie else kategorie
	refresh()
	_dock_ui.klappe_lager(false)


## Drawer-Chip: Auswahl-Klang, dann item_gewaehlt (BuildMode startet den
## Ghost/Spann-Flow — programmatische Starts bleiben stumm).
func _on_chip(def: Dictionary) -> void:
	AudioDirector.try_play(self, "ui_chip")
	item_gewaehlt.emit(def)


## Bäckerei fertig: Thumbnail des passenden Bild-Chips nachrüsten.
func _on_vorschau_fertig(key: String, textur: Texture2D) -> void:
	if not key.begins_with(CraftVorschau.PREFIX) or _dock_ui == null:
		return
	var item_id := key.trim_prefix(CraftVorschau.PREFIX)
	_dock_ui.chip_textur(_dock_ui.lager_chip(item_id), textur)


static func _ist_control(node: Node) -> bool:
	return node is Control
