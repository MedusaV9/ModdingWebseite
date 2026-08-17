class_name MinigameResults
extends Control
## Results-Screen des Minigame-Hosts: Score, Coins (inkl. Tagesbonus-×2-Chip,
## Tageslimit-Hinweis), Bestwert/Neuer-Rekord, XP/Level-Ups. Buttons feuern
## nur Signale — Navigation gehört dem Host (again → Neustart, back → Arcade).
##
## POLISH-A: der Screen ist der Belohnungsmoment ALLER Spiele — Punkte zählen
## hörbar hoch, Sterne ploppen nacheinander ein (1 = geschafft, +1 Ziel
## geschlagen, +1 neuer Rekord), „Neuer Rekord!“ feiert mit Konfetti +
## Rekord-Fanfare, Münzen regnen. Alles über JuiceKit/FeelSfx und damit
## Reduced-Motion-sauber (Töne bleiben, Bewegung stoppt).
##
## W21/P4 (c) „ACNH-Zeremonie“: die Karte ist KEIN 9-Zeilen-Textstapel mehr —
## Zeilen fliegen gestaffelt ein (MotionKit.stagger_ein), die Sterne landen
## als STEMPEL, und Rekord/Geist/Bonus/Modifier sind klar getrennte Chips
## mit IKONEN (Frost-Mini-Kapseln — die Farbe trägt das Icon, der Text
## bleibt Ink) statt sechs Textfarben. Konfetti gibt es NUR beim neuen
## Rekord (Sparsamkeitsregel UI-DESIGN-ACNH §6.3). Quer-Formate löst das
## LAYOUT nach Skala („Deko weicht zuerst“, W20-Regel) statt des alten
## 0,72-Font-Shrinks.

signal again_pressed
signal back_pressed
## G7-P56: dritter Rahmen-Knopf — direkt nach Hause statt Umweg über Arcade.
signal home_pressed

## Wunschbreite der Karte (Design-px — FB3: skaliert mit UiScale).
const PANEL_BASE_WIDTH := 420.0
## W21/P4 (c) „Karten-Layout nach Skala“: im QUER-Canvas wird die Karte
## BREIT statt die Schriften klein — der Feier-Fluss bleibt selbst im
## Feier-Worst-Case (Rekord + Tagesbonus + Spotlight + Ziel) einzeilig und
## die Karte unter der Safe-Area-Höhe (Befund Font-Zerdrückung 0,72).
const PANEL_QUER_WIDTH := 600.0
## G7-P56: DERSELBE Mini-Gooby wie auf der Lade-Karte (LoadingVeil) — die
## eine Figur begleitet den Spieler durch Wipe → Pregame → Results.
const GOOBY_MOTIV_PFAD := "res://assets/acui/gooby_loading_motif.png"
## Sticker-Durchmesser in Design-px (Web-Motiv-Maß, skaliert mit UiScale).
const GOOBY_STICKER_PX := 72.0
## Chip-Ikonen: dieselben Glyphen wie das HUD (EIN Icon-Set, W21-Regel).
const ICON_DIR := "res://assets/ui/icons/"

var _panel: PanelContainer
var _center: CenterContainer
var _rows: VBoxContainer
var _juice: JuiceKit
var _again: Button
var _back: Button
var _home: Button
var _gooby: LoadingVeilSticker
## W21/P4 (c): Feier-Chip-Fluss + Sterne-Reihe der laufenden Anzeige (die
## Zeremonie stempelt die Sterne an ihrem Beat, s. _starte_zeremonie).
var _feier_flow: HFlowContainer
var _stars: FeelStarRow
var _stars_earned := 0


func _ready() -> void:
	# E14-P0: and_offsets — nur Anker setzen behält das aktuelle Rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	# G7-P56: gleiche Abdunkelung wie das Pause-Modal — EIN Rahmen-Look.
	dim.color = MinigamePauseModal.DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"AcCardLg"
	_panel.custom_minimum_size = Vector2(PANEL_BASE_WIDTH, 0)
	_center.add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_panel.add_child(_rows)
	get_viewport().size_changed.connect(_apply_metrics)


## FB3: Karte skaliert mit der ZENTRALEN UiScale-Regel, bleibt in der
## Safe-Area zentriert (Notch/Home-Indicator) und die Knöpfe halten den
## Touch-Floor — vorher feste 420 px + Canvas-Zentrum.
func _apply_metrics() -> void:
	if _panel == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	_center.offset_left = float(insets["left"])
	_center.offset_right = -float(insets["right"])
	_center.offset_top = float(insets["top"])
	_center.offset_bottom = -float(insets["bottom"])
	# W21/P4 (c) „Karten-Layout nach Skala“: quer wird die Karte BREIT
	# (der Feier-Fluss bleibt flach) statt dass die Schriften schrumpfen.
	var canvas: Vector2 = m["canvas"]
	var wunsch := PANEL_QUER_WIDTH if canvas.x > canvas.y else PANEL_BASE_WIDTH
	var karten_breite := ScreenShell.card_width(m, wunsch)
	_panel.custom_minimum_size = Vector2(karten_breite, 0)
	if _feier_flow != null and is_instance_valid(_feier_flow):
		# FlowContainer wickelt an seiner AKTUELLEN Breite — vor dem ersten
		# Sort ist die 0 und die Min-Höhe stapelt ALLE Chips (W18-B1-Muster).
		# Eine realistische Startbreite hält die Messung bei echten Zeilen;
		# der Sort setzt die exakte Breite gleich danach ohnehin neu.
		if _feier_flow.size.x <= 1.0:
			_feier_flow.size = Vector2(
				karten_breite - 2.0 * AcTokens.px(float(AcTokens.SPACE_M), f), 0.0
			)
	for btn in [_again, _back, _home]:
		if btn != null:
			ScreenShell.touch_target(btn, m)
	var sticker_d := GOOBY_STICKER_PX * f
	if _gooby != null and is_instance_valid(_gooby):
		# Voll zurücksetzen (Größe + Sichtbarkeit), damit der Deko-Fit unten
		# bei jedem Resize deterministisch von der Design-Basis aus misst.
		_gooby.custom_minimum_size = Vector2(sticker_d, sticker_d)
		_gooby.visible = true
	ScreenShell.scale_fonts(_panel, f)
	# Chip-Ikonen skalieren mit derselben f-Regel wie die Schriften.
	for icon in _panel.find_children("Icon", "", true, false):
		if icon is Control:
			(icon as Control).custom_minimum_size = (
				Vector2.ONE * AcTokens.px(float(AcTokens.ICON_S), f)
			)
	# W21/P4 (c) — Quer-Fit über das LAYOUT nach Skala statt Font-Shrink
	# (Befund „Font-Zerdrückung 0,72“): die Karte darf nie höher werden als
	# die Safe-Area, und dafür weicht die DEKO ZUERST (W20-Regel):
	#   1) die Zeilen-Luft geht von SPACE_S auf SPACE_XS zurück,
	#   2) der Gooby-Sticker gibt Höhe ab bis zum Ausblenden,
	#   3) die restliche Zeilen-Luft fällt (Kapseln/Zeilen haben eigenes
	#      Innen-Polster — enge Karte schlägt kleine Schrift).
	# Schriften bleiben auf der f-Skala; nur ein Not-Netz für extrem kleine
	# Fenster darf darunter — im Leit-/Befund-Format greift es nie (Wächter
	# test_w21_p4_rahmen: Results-Schrift bleibt bei f in quer_2556x1179).
	var safe_h := (canvas.y - float(insets["top"]) - float(insets["bottom"])) * 0.96
	_rows.add_theme_constant_override("separation", AcTokens.px(float(AcTokens.SPACE_S), f))
	if _panel.get_combined_minimum_size().y > safe_h:
		_rows.add_theme_constant_override("separation", AcTokens.px(float(AcTokens.SPACE_XS), f))
	if _gooby != null and is_instance_valid(_gooby):
		var over := _panel.get_combined_minimum_size().y - safe_h
		if over > 0.0:
			var d_neu := maxf(sticker_d - over, 0.0)
			_gooby.custom_minimum_size = Vector2(d_neu, d_neu)
			_gooby.visible = d_neu >= 40.0
	if _panel.get_combined_minimum_size().y > safe_h:
		_rows.add_theme_constant_override("separation", 0)
	# Not-Netz (NACH der Deko, vorher war es der erste Griff): Schrift-Fit
	# nur, wenn selbst die kompakte Karte nicht passt — nie unter die
	# Design-Basis, die Knöpfe behalten ihren Touch-Floor.
	var f_fit := f
	for _pass in 4:
		var need := _panel.get_combined_minimum_size().y
		if f_fit <= 1.0 or need <= safe_h:
			break
		f_fit = maxf(f_fit * safe_h / need, 1.0)
		ScreenShell.scale_fonts(_panel, f_fit)


## breakdown = MinigameAward.award()-Ergebnis; meta = Registry-Zeile.
## juice (optional, vom Host): schaltet Count-Up/Konfetti/Münz-Regen frei —
## ohne Kit (Alt-Aufrufer/Tests) steht der Screen sofort statisch da.
func show_results(breakdown: Dictionary, meta: Dictionary, juice: JuiceKit = null) -> void:
	_juice = juice
	# EF-3 F3 („jeweils passend“): 0 Punkte bekommen keinen Sieg-Klang —
	# der weiche game_lose passt zum Trost-Moment des Hosts.
	FeelSfx.play(self, "game_win" if int(breakdown.get("score", 0)) > 0 else "game_lose")
	# W18 B1 (Playtest Welle H): Alt-Zeilen SYNCHRON aus dem Baum nehmen —
	# mit queue_free() allein koexistierten alte + neue Rows einen Frame, der
	# Min-Größen-Spike blähte den FULL_RECT-verankerten _center über das
	# Anker-Rect hinaus auf, und Godot schrumpft ein Control nach dem
	# Min-Rückgang NIE von selbst zurück (Parent ist kein Container) — die
	# Karte zentrierte ab Runde 2 dauerhaft off-screen (Soft-Lock, alle
	# Knöpfe unterhalb des Bildschirms). remove_child wirkt sofort aufs
	# Layout, queue_free bleibt als sichere, deferred Freigabe.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	# G7-P56: die immer gleiche Gooby-Präsenz des Rahmens — derselbe runde
	# Motiv-Sticker wie auf der Lade-Karte. Sieg → er hüpft (jubelt),
	# 0 Punkte oder Reduced Motion → eingefrorene Ruhepose (schnauft).
	_gooby = LoadingVeilSticker.new()
	_gooby.name = "GoobySticker"
	_gooby.custom_minimum_size = Vector2(GOOBY_STICKER_PX, GOOBY_STICKER_PX)
	_gooby.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if ResourceLoader.exists(GOOBY_MOTIV_PFAD):
		_gooby.set_motiv(load(GOOBY_MOTIV_PFAD))
	_gooby.set_animated(int(breakdown.get("score", 0)) > 0 and not _reduced_motion())
	_rows.add_child(_gooby)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mg.results.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(title)
	var game_name := Label.new()
	game_name.theme_type_variation = &"CaptionLabel"
	game_name.text = I18nService.t(str(meta.get("title_key", "mg.results.title")))
	game_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(game_name)
	var final_score := int(breakdown.get("score", 0))
	var score := Label.new()
	score.theme_type_variation = &"HeadlineLabel"
	score.text = I18nService.t("mg.results.score", {"score": final_score})
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(score)
	_add_stars(breakdown, final_score)
	# W21/P4 (c): Feier-Chips (Rekord/Geist/Bonus/Modifier) fließen als
	# Ikonen-Kapseln zentriert in EINEM Fluss — quer wird er breit statt
	# hoch (Karten-Layout nach Skala statt Font-Shrink).
	var f := _f()
	_feier_flow = HFlowContainer.new()
	_feier_flow.name = "FeierChips"
	_feier_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_feier_flow.add_theme_constant_override(
		"h_separation", AcTokens.px(float(AcTokens.SPACE_XS), f)
	)
	_feier_flow.add_theme_constant_override(
		"v_separation", AcTokens.px(float(AcTokens.SPACE_XS), f)
	)
	_rows.add_child(_feier_flow)
	var new_best := bool(breakdown.get("newBest", false))
	if new_best:
		var best_chip := _chip(I18nService.t("mg.results.new_best"), "sparkle", AcTokens.GOLD)
		best_chip.name = "RekordChip"
		_feier_flow.add_child(best_chip)
		_celebrate_record(best_chip)
		# W15/VOICE2 (W13-Request): neuer Rekord → Gooby feiert mit (None-sicher).
		SeeleRunner.kommentar_global("minispiel.rekord")
	else:
		var best_chip := _chip(
			I18nService.t("mg.results.best", {"best": int(breakdown.get("best", 0))}),
			"sparkle",
			AcTokens.INK_FAINT
		)
		best_chip.name = "BestChip"
		_feier_flow.add_child(best_chip)
	# W19/GEIST: der Bestlauf-Geist wurde am Rundenende endgültig überholt —
	# eigener kleiner Feier-Beat (Pop + heller Ton), EINMAL pro Runde und
	# bewusst OHNE zweites Konfetti (das große Fest gehört der Rekord-Feier).
	if breakdown.get("geistGeschlagen", false):
		_zeige_geist_zeile()
	if breakdown.get("firstToday", false):
		var bonus_chip := _chip(
			I18nService.t("mg.results.daily_bonus"), "gift", AcTokens.YELLOW_DARK
		)
		bonus_chip.name = "TagesbonusChip"
		_feier_flow.add_child(bonus_chip)
	# W19/SPOTLIGHT: der Spiel-des-Tages-Bonus steht sichtbar im Ergebnis.
	var spotlight_coins := int(breakdown.get("spotlightBonusCoins", 0))
	if spotlight_coins > 0:
		var spot_chip := _chip(
			I18nService.t("mg.spotlight.results.bonus", {"coins": spotlight_coins}),
			"sparkle",
			AcTokens.TEAL_DARK
		)
		spot_chip.name = "SpotlightChip"
		_feier_flow.add_child(spot_chip)
	if breakdown.get("beatTarget", false):
		var ziel_chip := _chip(I18nService.t("mg.results.beat_target"), "check", AcTokens.LEAF_DARK)
		ziel_chip.name = "ZielChip"
		_feier_flow.add_child(ziel_chip)
	if int(breakdown.get("levelsGained", 0)) > 0:
		var lvl_chip := _chip(
			I18nService.t(
				"mg.results.level_up", {"coins": int(breakdown.get("coinsFromLevels", 0))}
			),
			"sparkle",
			AcTokens.PINK_DARK
		)
		lvl_chip.name = "LevelUpChip"
		_feier_flow.add_child(lvl_chip)
		# EF-1/EVAL-1 D8: Level-Up wird GEFEIERT (Vollbild-Moment nach dem
		# Count-Up) — vorher war es nur eine unscheinbare Textzeile.
		_feier_level_up(breakdown)
	# FERTIG-1 (EVAL Rang 12): Modifier-Wirkung sichtbar im Ergebnis.
	_add_modifier_lines(breakdown)
	# Stat-Zeile: Münzen + XP als ZWEI Ikonen-Chips auf EINER Zeile (QW #20:
	# Erfolgs-Grün/Coin-Gold sind Token-Tints der ICONS, der Text bleibt Ink).
	var stat_zeile := HBoxContainer.new()
	stat_zeile.name = "StatZeile"
	stat_zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	stat_zeile.add_theme_constant_override("separation", AcTokens.px(float(AcTokens.SPACE_S), f))
	_rows.add_child(stat_zeile)
	var coins := int(breakdown.get("coins", 0))
	var coins_line := _chip(
		I18nService.t("mg.results.coins", {"coins": coins}), "coin", AcTokens.YELLOW_DARK
	)
	coins_line.name = "MuenzChip"
	stat_zeile.add_child(coins_line)
	var xp_chip := _chip(
		I18nService.t("mg.results.xp", {"xp": int(breakdown.get("xp", 0))}),
		"leaf",
		AcTokens.LEAF_DARK
	)
	xp_chip.name = "XpChip"
	stat_zeile.add_child(xp_chip)
	if breakdown.get("dayCapReached", false):
		_add_line(I18nService.t("mg.results.day_cap"), AcTokens.INK_FAINT)
	# G7-P56: DIE eine Knopf-Reihenfolge des Rahmens — Nochmal/Arcade/Home,
	# in jedem der 38 Spiele identisch (QW #3: SquishButtons).
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_rows.add_child(buttons)
	_again = SquishButton.new()
	_again.name = "Nochmal"
	_again.theme_type_variation = &"PrimaryButton"
	_again.text = I18nService.t("mg.results.again")
	_again.focus_mode = Control.FOCUS_ALL
	_again.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_confirm")
			again_pressed.emit()
	)
	buttons.add_child(_again)
	_back = SquishButton.new()
	_back.name = "Arcade"
	_back.theme_type_variation = &"GhostButton"
	_back.text = I18nService.t("mg.results.back")
	_back.focus_mode = Control.FOCUS_ALL
	_back.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			back_pressed.emit()
	)
	buttons.add_child(_back)
	_home = SquishButton.new()
	_home.name = "Zuhause"
	_home.theme_type_variation = &"GhostButton"
	_home.text = I18nService.t("mg.results.home")
	_home.focus_mode = Control.FOCUS_ALL
	_home.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			home_pressed.emit()
	)
	buttons.add_child(_home)
	var actions: Array[Control] = [_again, _back, _home]
	FocusNavigation.wire_controls(actions, true)
	_apply_metrics()
	show()
	# Das Results-Panel kann im selben Frame wieder geschlossen werden
	# (Tests, schneller Szenenwechsel). Der zentrale Helfer bindet die
	# kurzlebige Wurzel deshalb schwach und fokussiert nur im lebenden Baum.
	FocusNavigation.grab_first_deferred(self)
	# W18 B1 (Netz zum Wurzelfix in _add_line): sollte ein transienter
	# Min-Spike den _center doch je über das Anker-Rect hinaus geklemmt
	# haben, zentriert der nächste Frame deterministisch zurück — Godot
	# selbst re-layoutet nur bei Anker-/Offset-/Parent-Änderungen und lässt
	# eine einmal aufgeblähte size sonst für immer stehen.
	# W21/P4: der Nachfit misst zusätzlich mit der ECHTEN Flow-Breite nach
	# dem ersten Sort (FlowContainer wickelt an der aktuellen Breite).
	_nachfit.call_deferred()
	# W21/P4 (c): Zeilen-Choreo NACH dem ersten Container-Sort (deferred) —
	# gestaffelter Einflug + Sterne-Stempel, Reduced-Motion-gated im Kit.
	_starte_zeremonie.call_deferred()
	if _juice != null:
		# Punkte zählen hörbar hoch (Ticks steigen in der Tonhöhe), das Panel
		# federt ein, Münzen regnen sobald es welche gab. Präfix/Suffix werden
		# locale-sicher aus dem Template geschnitten ({score} kann wandern).
		var template := I18nService.t("mg.results.score", {"score": "|"})
		var parts := template.split("|")
		var suffix := parts[1] if parts.size() > 1 else ""
		_juice.count_to(score, 0, final_score, 0.9, parts[0], suffix)
		_juice.scale_pop(_panel, 1.06, 260)
		if coins > 0:
			_pulse_later(0.5, coins_line)


## FERTIG-1 (EVAL Rang 12): war ein Modifier-Event aktiv, zeigt der Screen
## Name + jede konkrete Wirkung (Bonus-Coins, Punkte-/XP-Faktor, gratis
## Energie, Glücksrolle) und den Tages-Ledger-Hinweis, wenn gedeckelt.
## W21/P4 (c): Präsentation als Ikonen-Chips im Feier-Fluss — die
## Bedingungs-LOGIK (welche Wirkung wann erscheint) ist unverändert.
func _add_modifier_lines(breakdown: Dictionary) -> void:
	var mod: Variant = breakdown.get("modifier")
	if not (mod is Dictionary) or (mod as Dictionary).is_empty():
		return
	var type_id := str((mod as Dictionary).get("type", ""))
	var def: Variant = ModifierEngine.TYPES.get(type_id)
	if not (def is Dictionary):
		return
	var color: Color = (def as Dictionary).get("color", AcTokens.YELLOW_DARK)
	var mod_name := I18nService.t(str((def as Dictionary).get("name_key", type_id)))
	var line := _chip(I18nService.t("modifier.results.aktiv", {"name": mod_name}), "sparkle", color)
	line.name = "ModifierChip"
	_feier_flow.add_child(line)
	if _juice != null:
		_juice.scale_pop(line, 1.12, 220)
	var bonus := int(breakdown.get("modifierBonusCoins", 0))
	if bonus > 0:
		_feier_flow.add_child(
			_chip(I18nService.t("modifier.results.bonus_coins", {"n": bonus}), "coin", color)
		)
	if float((mod as Dictionary).get("score_mult", 1.0)) > 1.0:
		_feier_flow.add_child(_chip(I18nService.t("modifier.results.score_mult"), "sparkle", color))
	if float((mod as Dictionary).get("xp_mult", 1.0)) > 1.0:
		_feier_flow.add_child(_chip(I18nService.t("modifier.results.xp_mult"), "leaf", color))
	if (mod as Dictionary).get("energy_free", false):
		_feier_flow.add_child(_chip(I18nService.t("modifier.results.energie"), "energy", color))
	var glueck := int(breakdown.get("gluecksrolleCoins", 0))
	if glueck > 0:
		_feier_flow.add_child(
			_chip(I18nService.t("modifier.results.gluecksrolle", {"n": glueck}), "coin", color)
		)
	if breakdown.get("modifierCapped", false):
		_add_line(I18nService.t("modifier.results.capped"), AcTokens.INK_FAINT)


## Stern-LOGIK unverändert (1 = geschafft, +1 Ziel, +1 Rekord) — die
## Enthüllung gehört seit W21/P4 der Zeremonie (_starte_zeremonie stempelt).
func _add_stars(breakdown: Dictionary, final_score: int) -> void:
	var earned := 0
	if final_score > 0:
		earned += 1
	if breakdown.get("beatTarget", false):
		earned += 1
	if breakdown.get("newBest", false):
		earned += 1
	_stars = FeelStarRow.new()
	_stars.name = "SterneZeile"
	_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(_stars)
	_stars_earned = earned


## W21/P4 (c) Zeilen-Choreo: alle Kartenzeilen fliegen in Kartenreihenfolge
## gestaffelt ein (MotionKit.stagger_ein — 40 ms Versatz); die Sterne sind
## vom Stagger ausgenommen und LANDEN an ihrem Beat als STEMPEL
## (MotionKit.stempel), danach füllen sie wie gehabt nacheinander
## (FeelStarRow.reveal). Reduced Motion: alles steht sofort, die Sterne
## enthüllen ohne Bewegung — das Gating liegt im Kit bzw. reveal(true).
func _starte_zeremonie() -> void:
	if _rows == null or not visible:
		return
	var reihen: Array = []
	var stern_beat := 0.0
	for child in _rows.get_children():
		if not (child is Control):
			continue
		if child == _stars:
			stern_beat = float(reihen.size()) * MotionKit.STAGGER_S
			continue
		reihen.append(child)
	MotionKit.stagger_ein(reihen)
	if _stars == null or not is_instance_valid(_stars):
		return
	if _reduced_motion():
		_stars.reveal(_stars_earned, true)
		return
	var tree := get_tree()
	if tree == null:
		_stars.reveal(_stars_earned, false)
		return
	_stars.modulate.a = 0.0
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(stern_beat + MotionKit.POP_S * 0.5).timeout.connect(_stempel_sterne)


func _stempel_sterne() -> void:
	if _stars == null or not is_instance_valid(_stars) or not visible:
		return
	_stars.modulate.a = 1.0
	MotionKit.stempel(_stars)
	_stars.reveal(_stars_earned, false)


## W21/P4 (c): EIN Feier-/Info-Chip — Frost-Mini-Kapsel mit Icon + Text.
## Die FARBE trägt das Icon (Token-Tint), der Text bleibt Ink („Chips mit
## Ikonen statt 6 Textfarben“). Icon-Kante = ICON_S (skaliert in
## _apply_metrics über den "Icon"-Namens-Vertrag mit).
func _chip(text: String, icon_name: String, tint: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsuleMini"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var zeile := HBoxContainer.new()
	zeile.name = "Zeile"
	zeile.add_theme_constant_override("separation", AcTokens.px(float(AcTokens.SPACE_XS), _f()))
	zeile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(zeile)
	var pfad := "%s%s.svg" % [ICON_DIR, icon_name]
	if ResourceLoader.exists(pfad):
		var bild := TextureRect.new()
		bild.name = "Icon"
		bild.texture = load(pfad)
		bild.custom_minimum_size = Vector2.ONE * AcTokens.px(float(AcTokens.ICON_S), _f())
		bild.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bild.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bild.self_modulate = tint
		bild.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bild.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zeile.add_child(bild)
	var label := Label.new()
	label.name = "Text"
	label.theme_type_variation = &"CaptionLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zeile.add_child(label)
	return chip


## Aktueller UiScale-Faktor (Chip-/Icon-Aufbau in Design-px × f).
func _f() -> float:
	return UiScale.for_viewport(get_viewport())


## Level-Up-Feier (EF-1, EVAL-1 D8): der Vollbild-Moment kommt nach dem
## Score-Count-Up (Ranch-Muster levelup_feier.gd, eigenständige Klasse).
func _feier_level_up(breakdown: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2): wird der Results-Screen vor
	# dem Timeout freigegeben, löst Godot die Verbindung automatisch — ein
	# Lambda-Capture würde "Lambda capture ... was freed" loggen.
	tree.create_timer(1.1).timeout.connect(_zeige_level_up.bind(breakdown))


func _zeige_level_up(breakdown: Dictionary) -> void:
	if not visible:
		return
	LevelUpFeier.zeige_in(
		self, int(breakdown.get("level", 2)), int(breakdown.get("coinsFromLevels", 0))
	)


## W19/GEIST: „Geist geschlagen!“-Chip (Gespenst-Icon + Text) samt kleinem
## Beat NACH dem Score-Count-Up — als eigener Moment neben der Rekord-Feier.
## W21/P4 (c): Präsentation als Ikonen-Chip im Feier-Fluss; Beat-LOGIK
## (1-s-Timer, game_perfect, EIN Pop) unverändert. Node-Name „GeistZeile“
## ist Test-Vertrag (test_w19_geist_rekord).
func _zeige_geist_zeile() -> void:
	var zeile := _chip(I18nService.t("mg.geist.geschlagen"), "", Color.WHITE)
	zeile.name = "GeistZeile"
	var icon := GeistChip.GeistIcon.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2.ONE * AcTokens.px(float(AcTokens.ICON_S), _f())
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var innen := zeile.get_node("Zeile") as HBoxContainer
	innen.add_child(icon)
	innen.move_child(icon, 0)
	_feier_flow.add_child(zeile)
	if _juice == null:
		FeelSfx.play(self, "game_perfect")
		return
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(1.0).timeout.connect(_beat_geist.bind(zeile))


## `zeile` bewusst UNTYPISIERT: startet der Spieler vor dem Timeout die
## Folgerunde, hat show_results die Zeile bereits freigegeben — eine
## Control-typisierte Signatur scheitert dann schon an der Argument-
## Konvertierung („Cannot convert argument“), BEVOR is_instance_valid greift.
func _beat_geist(zeile: Variant) -> void:
	if not visible or _juice == null or not is_instance_valid(zeile):
		return
	FeelSfx.play(self, "game_perfect", 1.1)
	_juice.scale_pop(zeile, 1.25, 260)


## „Neuer Rekord!“ — Konfetti + Fanfare + Goldblitz, Chip poppt. DIE einzige
## Konfetti-Quelle der Karte (W21/P4-Sparsamkeitsregel: Konfetti NUR bei
## Rekord — der Wächter test_w21_p4_rahmen scannt die Quelle darauf).
func _celebrate_record(line: Control) -> void:
	if _juice == null:
		FeelSfx.play(self, "game_record")
		return
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(0.55).timeout.connect(_zeige_rekord_feier.bind(line))


func _zeige_rekord_feier(line: Control) -> void:
	if not visible or _juice == null:
		return
	FeelSfx.play(self, "game_record")
	_juice.confetti(110)
	_juice.hit_flash(Color(1.0, 0.85, 0.35, 0.2), 320)
	_juice.scale_pop(line, 1.35, 300)


func _pulse_later(delay: float, line: Control) -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Gebundene Methode statt Lambda (REST5, B2) — s. _feier_level_up.
	tree.create_timer(delay).timeout.connect(_pulse_now.bind(line))


func _pulse_now(line: Control) -> void:
	if not visible or _juice == null:
		return
	_juice.coin_rain(24)
	_juice.scale_pop(line, 1.18, 220)


func _add_line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Breiten-Sicherheit (G3): lange Übersetzungen (Modifier-/Bonus-Zeilen)
	# brechen um, statt die Karte über card_width hinaus zu verbreitern —
	# der PanelContainer wächst sonst mit dem längsten Kind.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_FILL
	# W18 B1 (WURZEL des Off-Screen-Soft-Locks): Autowrap-Labels melden ihre
	# Wickel-Minhöhe für die AKTUELLE Breite — und die ist vor dem ersten
	# Container-Sort 0 (der Screen ist beim Umbau versteckt, Container
	# sortieren erst nach show()). Quasi ein Wort pro Zeile ergab hunderte
	# Phantom-px pro Zeile; show() klemmte den FULL_RECT-_center synchron
	# auf diese Minhöhe (612→1914 px im Playtest) und die Karte zentrierte
	# ab Runde 2 dauerhaft unterhalb des Screens. Eine realistische
	# Startbreite hält die Minhöhe bei 1–2 Zeilen; der Sort setzt die
	# echte Breite gleich danach ohnehin neu.
	label.size = Vector2(PANEL_BASE_WIDTH, 0.0)
	label.add_theme_color_override("font_color", color)
	_rows.add_child(label)
	return label


## W21/P4: zweiter Fit-Lauf NACH dem ersten Container-Sort (deferred aus
## show_results) — erst dann kennt der Feier-Fluss seine echte Breite und
## der Deko-Fit misst die reale Kartenhöhe. Danach W18-B1-Recentering.
func _nachfit() -> void:
	if not visible:
		return
	_apply_metrics()
	_recenter()


## W18 B1: _center hart auf sein Anker-Rect (FULL_RECT minus Insets-Offsets)
## zurücksetzen, falls ein Min-Größen-Spike ihn aufgebläht hat. set_size
## hält die Anker konsistent (Godot rechnet die Offsets passend um), künftige
## Viewport-Resizes laufen also weiter über _apply_metrics.
func _recenter() -> void:
	if _center == null or not visible:
		return
	var soll := Vector2(
		size.x + _center.offset_right - _center.offset_left,
		size.y + _center.offset_bottom - _center.offset_top
	)
	if _center.size.is_equal_approx(soll):
		return
	_center.position = Vector2(_center.offset_left, _center.offset_top)
	_center.size = soll


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
