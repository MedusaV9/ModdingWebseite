class_name RekordPuls
extends RefCounted
## A2 „Rekord-Puls“ (G8-IDEEN A2): der Bestwert lebt IN der Runde — der
## Minigame-Host kennt live Score UND Bestwert (best_for_mode) und macht
## daraus Dramaturgie für ALLE 38 Spiele, ohne ein Spiel anzufassen.
## HIER wohnt die pure Stufen-Logik (bewusst ohne Node/Baum — Tests spielen
## sie direkt durch): 0 neutral · 1 golden (ab 80 % des Bestwerts bzw.
## Ziel-Anker erreicht) · 2 Rekord (Bestwert überholt — bleibt für den Rest
## der Runde). Alle Ereignisse zünden höchstens EINMAL pro Runde
## (Reizfrequenz-Bremse aus dem Ideen-Doc). Den sichtbaren Anteil
## (Pill-Gold, Ziel-Anker, „NEUER REKORD!“-Banner) übernimmt die
## Anzeige-Klasse unten; Sounds + rekord_moment_fired bleiben im Host.

## Ab diesem Anteil des Bestwerts beginnt die Pill zu schimmern.
const ANNAEHERUNG_ANTEIL := 0.8
## Gold-Töne: der Annäherungs-Schimmer pendelt PULS_GOLD ↔ PULS_GOLD_HELL,
## nach dem Überholen bleibt die Pill REKORD_GOLD; die warme Outline hält
## den Text auf jedem Spielhintergrund lesbar.
const PULS_GOLD := Color(1.0, 0.78, 0.25)
const PULS_GOLD_HELL := Color(1.0, 0.92, 0.58)
const REKORD_GOLD := Color(1.0, 0.72, 0.14)
const PULS_OUTLINE := Color(0.45, 0.28, 0.08, 0.85)
## So lange steht das „NEUER REKORD!“-Banner, bevor es weich ausblendet.
const BANNER_SEC := 1.15

var best := 0
var ziel := 0
var stufe := 0
var annaeherung_gefeuert := false
var ziel_gefeuert := false
var rekord_gefeuert := false


## Schwelle, ab der die Annäherung beginnt (mindestens 1 Punkt).
static func annaeherung_schwelle(best_wert: int) -> int:
	return maxi(1, int(ceil(float(best_wert) * ANNAEHERUNG_ANTEIL)))


## Frische Runde: Bestwert des Modus + Ziel (0 = kein Anker) setzen.
func reset(best_wert: int, ziel_wert: int) -> void:
	best = maxi(0, best_wert)
	ziel = maxi(0, ziel_wert)
	stufe = 0
	annaeherung_gefeuert = false
	ziel_gefeuert = false
	rekord_gefeuert = false


## Erstrunde ohne Bestwert? Dann zeigt der Host den Ziel-Anker.
func zeigt_ziel() -> bool:
	return best <= 0 and ziel > 0


## Ein Score-Tick: hebt die Stufe (nie senken) und meldet, welche
## Einmal-Ereignisse JETZT zünden: {stufe, annaeherung, ziel, rekord}.
func bewerte(score_wert: int) -> Dictionary:
	var ereignis := {"stufe": stufe, "annaeherung": false, "ziel": false, "rekord": false}
	if best > 0:
		if score_wert > best and not rekord_gefeuert:
			rekord_gefeuert = true
			# Sprung DIREKT über den Rekord verbraucht auch die Annäherung
			# — max. 1 Puls pro Runde (Doc-Leitplanke).
			annaeherung_gefeuert = true
			stufe = 2
			ereignis["rekord"] = true
		elif (
			score_wert >= annaeherung_schwelle(best)
			and score_wert <= best
			and not annaeherung_gefeuert
		):
			annaeherung_gefeuert = true
			stufe = maxi(stufe, 1)
			ereignis["annaeherung"] = true
	elif zeigt_ziel() and score_wert >= ziel and not ziel_gefeuert:
		ziel_gefeuert = true
		stufe = maxi(stufe, 1)
		ereignis["ziel"] = true
	ereignis["stufe"] = stufe
	return ereignis


## Der SICHTBARE Anteil des Rekord-Pulses — als Host-Kind eingehängt
## (minigame_host._build_ui verdrahtet score_label/ziel_label/overlay/
## juice). Nicht spielunterbrechend: alles läuft über Overlays mit
## MOUSE_FILTER_IGNORE. Reduced Motion: statisches Gold statt Schimmer,
## Banner erscheint/verschwindet ohne Bewegung — Sounds bleiben (Host).
class Anzeige:
	extends Node

	var score_label: Label
	var ziel_label: Label
	var overlay: Control
	var juice: JuiceKit
	var banner: Label
	var tween: Tween
	var stufe := 0

	## Frische Runde: Pill neutral, Banner weg, Ziel-Anker nur für
	## Erstrunden ohne Bestwert (Text „Ziel: {n}“ liefert der Host).
	func reset(ziel_sichtbar: bool, ziel_text: String) -> void:
		setze_stufe(0, true)
		if banner != null and is_instance_valid(banner):
			banner.hide()
		if ziel_label == null:
			return
		ziel_label.visible = ziel_sichtbar
		if ziel_sichtbar:
			ziel_label.text = ziel_text
			ziel_label.remove_theme_color_override("font_color")

	## Score-Pill-Stufen: 0 neutral, 1 golden schimmernd (Reduced Motion:
	## statisch golden), 2 Rekord-Gold für den Rest der Runde. force
	## erzwingt den Neuaufbau beim Runden-Reset (frische Optik).
	func setze_stufe(neu: int, force := false) -> void:
		if score_label == null or (neu == stufe and not force):
			return
		stufe = neu
		if tween != null and tween.is_valid():
			tween.kill()
		tween = null
		if neu <= 0:
			score_label.remove_theme_color_override("font_color")
			score_label.remove_theme_color_override("font_outline_color")
			score_label.remove_theme_constant_override("outline_size")
			return
		score_label.add_theme_color_override("font_outline_color", PULS_OUTLINE)
		score_label.add_theme_constant_override("outline_size", 4)
		if neu >= 2:
			score_label.add_theme_color_override("font_color", REKORD_GOLD)
			return
		score_label.add_theme_color_override("font_color", PULS_GOLD)
		if _reduced_motion():
			return
		tween = create_tween().set_loops()
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(score_label, "theme_override_colors/font_color", PULS_GOLD_HELL, 0.55)
		tween.tween_property(score_label, "theme_override_colors/font_color", PULS_GOLD, 0.55)

	## Erstrunden-Pfad: Ziel erreicht — Anker wird gold und pulst einmal.
	func feiere_ziel() -> void:
		if ziel_label == null or not ziel_label.visible:
			return
		ziel_label.add_theme_color_override("font_color", REKORD_GOLD)
		if juice != null:
			juice.scale_pop(ziel_label, 1.3, 300)
			juice.hit_flash(Color(1.0, 0.9, 0.5, 0.1), 160)

	## Der sofortige Rekord-Moment: Goldblitz + Rand-Glühen + Pill-Pop +
	## Banner. Bewusst OHNE Konfetti (gehört dem Results-Screen); die
	## Grace-Marke (win_moment_msec) unterdrückt den zusätzlichen Auto-
	## End-Moment, wenn die Runde direkt danach endet — dieselbe Logik
	## wie END_MOMENT_GRACE_MS im Host.
	func feiere_rekord() -> void:
		if juice != null:
			juice.hit_flash(Color(1.0, 0.85, 0.35, 0.2), 300)
			juice.edge_glow(0.55, PULS_GOLD)
			juice.scale_pop(score_label, 1.35, 340)
			juice.win_moment_msec = Time.get_ticks_msec()
		_zeige_banner()

	## Kurzes Banner im oberen Spielfeld-Drittel: federt ein, steht
	## BANNER_SEC und blendet weich aus. Eingaben laufen ungestört durch.
	func _zeige_banner() -> void:
		if overlay == null:
			return
		if banner == null or not is_instance_valid(banner):
			banner = Label.new()
			banner.name = "RekordBanner"
			banner.theme_type_variation = &"TitleLabel"
			banner.text = I18nService.t("mg.host.rekord")
			banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			banner.add_theme_color_override("font_color", REKORD_GOLD)
			banner.add_theme_color_override("font_outline_color", Color(1.0, 0.98, 0.92, 0.95))
			banner.add_theme_constant_override("outline_size", 10)
			banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			# Oberes Drittel statt Bildmitte: das Spielgeschehen bleibt frei.
			banner.anchor_top = 0.3
			banner.anchor_bottom = 0.3
			banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
			banner.grow_vertical = Control.GROW_DIRECTION_BOTH
			banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.add_child(banner)
		banner.add_theme_font_size_override(
			"font_size", int(roundf(44.0 * UiScale.for_viewport(overlay.get_viewport())))
		)
		banner.modulate = Color.WHITE
		banner.show()
		if juice != null:
			juice.scale_pop(banner, 1.5, 380)
		if get_tree() == null:
			return
		# Echtzeit-Timer + gebundene Methode (REST5, B2): stirbt die Anzeige
		# vorher, trennt Godot die Verbindung automatisch.
		get_tree().create_timer(BANNER_SEC, true, false, true).timeout.connect(_blende_banner_aus)

	func _blende_banner_aus() -> void:
		if banner == null or not is_instance_valid(banner) or not banner.visible:
			return
		if _reduced_motion():
			banner.hide()
			return
		var raus := create_tween()
		raus.tween_property(banner, "modulate:a", 0.0, 0.28)
		raus.tween_callback(banner.hide)

	func _reduced_motion() -> bool:
		var settings := get_node_or_null("/root/AppSettings")
		if settings != null and settings.has_method("is_reduced_motion"):
			return settings.is_reduced_motion()
		return false
