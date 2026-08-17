class_name AcScreenHeader
extends HBoxContainer
## W20/P4 — DER wiederverwendbare Screen-Header-Baustein (Befund E4:
## „Kopfzeilen-Grammatik uneinheitlich — Einstellungen linksbündig neben
## Zurück, andere Screens zentriert mit rechter Info-Pille“). EINE
## Kopfzeilen-Grammatik für alle Menü-Screens: Zurück-Pill LINKS, Titel
## ZENTRIERT, optionale Info-Chips RECHTS. Die Seiten-Slots halten sich
## symmetrisch breit, damit der Titel auch MIT Chips wirklich mittig steht.
##
## API (für P3-/Screen-Agents):
##   var header := AcScreenHeader.build("Album", _on_back)  # Callable optional
##   rows.add_child(header)                    # ganz oben in die Inhaltsspalte
##   header.add_chip(meine_pille)              # optional, rechter Slot
##   header.apply_metrics(m)                   # m = ScreenShell.metrics(...)
##       — bei Viewport.size_changed erneut rufen (Touch-Floor + Schriften)
##   header.back_pressed                       # Signal (Alternative zum Callable)
##   header.title_label / header.back_button   # für Feintuning
##
## Der Baustein bringt bewusst KEINE eigene Safe-Area-Logik mit — er lebt
## IN der Inhaltsspalte des Screens (ScreenShell.frame/content_frame setzt
## die Insets); Touch-Floor + Schrift-Skalierung kommen über apply_metrics.

signal back_pressed

## Abstand zwischen den drei Header-Slots (Design-px, Theme-Separation).
const SLOT_GAP := 10

var back_button: Button
var title_label: Label

var _links: HBoxContainer
var _rechts: HBoxContainer


## Fabrik: Header mit Titel + Zurück-Knopf; `on_back` optional (sonst das
## `back_pressed`-Signal verbinden).
static func build(titel: String, on_back := Callable()) -> AcScreenHeader:
	var header := AcScreenHeader.new()
	header.name = "ScreenHeader"
	header._bauen(titel)
	if on_back.is_valid():
		header.back_pressed.connect(on_back)
	return header


## Info-Chip (Pille/Zähler) in den rechten Slot hängen.
func add_chip(chip: Control) -> void:
	_rechts.add_child(chip)
	_seiten_symmetrisch()


## ScreenShell.metrics-Dictionary anwenden: Zurück-Knopf auf den
## Touch-Floor heben, Schriften mit f skalieren, Slots symmetrisch halten.
func apply_metrics(m: Dictionary) -> void:
	ScreenShell.touch_target(back_button, m)
	ScreenShell.scale_fonts(self, m["f"])
	_seiten_symmetrisch()


func _bauen(titel: String) -> void:
	add_theme_constant_override("separation", SLOT_GAP)
	_links = HBoxContainer.new()
	_links.name = "HeaderLinks"
	_links.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_links)
	back_button = SquishButton.new()
	back_button.name = "HeaderZurueck"
	back_button.theme_type_variation = &"GhostButton"
	back_button.text = "‹  %s" % I18nService.t("ui.zurueck")
	back_button.pressed.connect(_on_back_pressed)
	_links.add_child(back_button)
	title_label = Label.new()
	title_label.name = "HeaderTitel"
	title_label.theme_type_variation = &"TitleLabel"
	title_label.text = titel
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(title_label)
	_rechts = HBoxContainer.new()
	_rechts.name = "HeaderRechts"
	_rechts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_rechts)
	_seiten_symmetrisch()


func _on_back_pressed() -> void:
	back_pressed.emit()


## Beide Seiten-Slots auf die Breite des breiteren klemmen — nur so bleibt
## der EXPAND_FILL-Titel optisch in der Screen-Mitte (auch mit Chips).
func _seiten_symmetrisch() -> void:
	if _links == null or _rechts == null:
		return
	_links.custom_minimum_size.x = 0.0
	_rechts.custom_minimum_size.x = 0.0
	var breite := maxf(_links.get_combined_minimum_size().x, _rechts.get_combined_minimum_size().x)
	_links.custom_minimum_size.x = breite
	_rechts.custom_minimum_size.x = breite
