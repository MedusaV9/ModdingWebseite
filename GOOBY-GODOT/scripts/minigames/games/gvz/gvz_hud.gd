class_name GvzHud
extends RefCounted
## HUD-Zeichnung der GvZ-Spielszene (G5/P26-Split, Muster build_ui_dock.gd):
## gvz_game.gd stand exakt am 1000-Zeilen-Limit — Karten, Zähler, Balken,
## Banner und Drag-Ghost wohnen jetzt hier. Reine PRÄSENTATION: dieser
## Helfer liest den Sim-State nur und zeichnet auf die Szene (view);
## Layout-Mathe (Zellen/Karten-Rects) bleibt in gvz_game.gd, weil auch die
## Eingabe sie braucht. Für das Netz-PvP (P26) kennt der HUD zusätzlich
## Matsch als Ressource, Zombie-Karten und den Überlebens-Timer.

const BANNER_SEC := 2.2

## Die Spielszene (gvz_game.gd) — bewusst untypisiert (kein class_name dort;
## ein Preload wäre zirkulär). Liefert Layout-Helfer, state und balance.
var view

## Banner-Zustand ("info" | "wave" | "huge" | "boss" | "intro").
var banner_text := ""
var banner_kind := "info"
var banner_start := 0.0
var banner_until := 0.0

var _font: Font
var _font_bold: Font
## Nutella-/Matsch-Zähler: letzter Stand + Pop-Startzeit (Zähler feiert).
var _resource_seen := -1
var _resource_pop := -10.0


func _init(game_view: CanvasItem) -> void:
	view = game_view
	_font = ThemeService.font(600)
	_font_bold = ThemeService.font(800)


func show_banner(text: String, kind := "info") -> void:
	banner_text = text
	banner_kind = kind
	banner_start = Time.get_ticks_msec() / 1000.0
	banner_until = banner_start + BANNER_SEC


## HP-Balken als 2D-Overlay über den 3D-Figuren (gleiche Anker wie vor dem
## Umbau; Zombies hinter der Nebelwand bleiben — wie ihre Figuren — verdeckt).
func draw_bars() -> void:
	var state: Dictionary = view.state
	var cell: Vector2 = view._cell_size()
	var field: Rect2 = view._field_rect()
	for key: Variant in state["towers"]:
		var tower: Dictionary = state["towers"][key]
		var feet: Vector2 = (
			view._cell_center(int(tower["lane"]), int(tower["col"])) + Vector2(0, cell.y * 0.4)
		)
		var hp := float(tower["hp"]) / float(tower["max_hp"])
		if hp < 0.99:
			_draw_bar(
				feet + Vector2(-cell.x * 0.3, -cell.y * 0.95), cell.x * 0.6, hp, GvzArt.MELON_GREEN
			)
	var fog_mm: int = (
		view._fog_start_mm() if int(view._fog_cols()) > 0 else GvzLogic.COLS * GvzLogic.CELL_MM * 2
	)
	for zombie: Dictionary in state["zombies"]:
		if bool(zombie["dead"]) or int(zombie["x"]) >= fog_mm:
			continue
		var feet := Vector2(
			view._x_to_px(int(zombie["x"])),
			field.position.y + (int(zombie["lane"]) + 1) * cell.y - 3.0
		)
		var total := int(zombie["hp"]) + int(zombie["armor_hp"])
		var max_total := int(zombie["max_hp"]) + int(zombie.get("armor_hp", 0))
		if total < int(zombie["max_hp"]):
			_draw_bar(
				feet + Vector2(-cell.x * 0.25, -cell.y * 1.02),
				cell.x * 0.5,
				float(total) / float(maxi(1, max_total)),
				GvzArt.BERRY_RED
			)


func draw_hud() -> void:
	var state: Dictionary = view.state
	# Ressourcen-Zähler (Nutella bzw. PvP-Matsch) — poppt bei jeder Änderung.
	var amount := int(view.hud_resource())
	if amount != _resource_seen:
		if _resource_seen >= 0:
			_resource_pop = Time.get_ticks_msec() / 1000.0
		_resource_seen = amount
	var pop := maxf(0.0, 1.0 - (Time.get_ticks_msec() / 1000.0 - _resource_pop) / 0.3)
	# Zähler-Chip links NEBEN der Kartenleiste an der Unterkante (G4).
	var dims: Vector2 = view._card_dims()
	var vp: Vector2 = view._view_size()
	var counter := Rect2(6, vp.y - view.TOP_PAD - dims.y, 78, dims.y)
	_rounded(
		counter, AcTokens.PAPER if pop <= 0.0 else AcTokens.PAPER.lerp(GvzArt.STAR_GOLD, pop * 0.35)
	)
	GvzArt.draw_nutella_drop(
		view,
		counter.position + Vector2(22, dims.y * 0.71),
		34 * (1.0 + 0.25 * pop),
		int(state["tick"])
	)
	view.draw_string(
		_font_bold,
		counter.position + Vector2(38, dims.y * 0.61),
		str(amount),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int(17 * (1.0 + 0.2 * pop)),
		AcTokens.INK
	)
	var cards: Array = view._card_list()
	var queue: Array = state["conveyor"].get("queue", []) if bool(view._conveyor_active()) else []
	var conveyor_only: bool = (
		view._conveyor_active() and not bool(state["mods"].get("conveyor_hybrid", false))
	)
	for i in cards.size():
		_draw_card(str(cards[i]), view._card_rect(i), conveyor_only or queue.has(str(cards[i])))
	if bool(view._conveyor_active()) and not conveyor_only:
		_draw_conveyor_strip(queue)
	_draw_boss_bar()
	_draw_netz_status()


## Drag-Feedback: das Karten-Icon folgt dem Finger (UI-Schicht); die grüne/
## rote Zell-Markierung rendert die 3D-Bühne (_sync_stage → ghost).
func draw_ghost() -> void:
	if not bool(view.dragging) or view.selected_card == "" or view.selected_card == "shovel":
		return
	var at: Vector2 = view.drag_pos + Vector2(0, 20)
	if bool((view._card_info(str(view.selected_card)) as Dictionary).get("zombie", false)):
		GvzArt.draw_zombie(view, str(view.selected_card), at, 34.0, 0)
	else:
		GvzArt.draw_tower(view, str(view.selected_card), at, 44.0, 0)


## Wellen-Banner mit WUCHT: schlägt groß ein (Punch-Skalierung), Farbe nach
## Gefahr (Welle sand, Riesenwelle/Boss berry-rot), Mini-Zombies flankieren
## den Text, am Ende blendet es weich aus.
func draw_banner() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if banner_text == "" or now > banner_until:
		return
	var state: Dictionary = view.state
	var vp: Vector2 = view._view_size()
	var t := now - banner_start
	var punch := maxf(0.0, 1.0 - t / 0.3)
	var s := 1.0 + 0.5 * punch * punch
	var fade := clampf((banner_until - now) / 0.35, 0.0, 1.0)
	var danger := banner_kind == "huge" or banner_kind == "boss"
	var w := (440.0 if banner_kind == "intro" else (340.0 if danger else 300.0)) * s
	var h := (54.0 if danger or banner_kind == "intro" else 44.0) * s
	var rect := Rect2(vp.x * 0.5 - w * 0.5, vp.y * 0.32 - (h - 44.0) * 0.5, w, h)
	var fill := Color(0.29, 0.23, 0.21, 0.8)
	if banner_kind == "huge":
		fill = Color(0.62, 0.2, 0.16, 0.88)
	elif banner_kind == "boss":
		fill = Color(0.42, 0.14, 0.3, 0.9)
	elif banner_kind == "intro":
		fill = Color(0.24, 0.42, 0.2, 0.88)
	fill.a *= fade
	_rounded(rect, fill)
	if danger:
		view.draw_rect(rect.grow(-1.5), Color(1.0, 0.83, 0.3, 0.85 * fade), false, 2.5)
	if banner_kind == "intro":
		# Ziel-Icon-Duell: links der Möhren-Wächter, rechts sein Zombie.
		var icon := h * 0.5
		var links := rect.position + Vector2(-icon - 8.0, h * 0.85)
		var rechts := rect.position + Vector2(w + icon + 8.0, h * 0.8)
		GvzArt.draw_tower(view, "moehre", links, icon * 1.3, 0)
		GvzArt.draw_zombie(view, "schlurfi", rechts, icon, 0)
	elif banner_kind != "info":
		var icon_s := h * 0.42
		var horde := 3 if banner_kind == "huge" else 1
		for i in horde:
			var offset := icon_s * (0.4 + 1.1 * float(i))
			GvzArt.draw_zombie(
				view,
				"schlurfi",
				rect.position + Vector2(-offset - 6.0, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 3
			)
			GvzArt.draw_zombie(
				view,
				"schlurfi",
				rect.position + Vector2(w + offset + 6.0, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 5 + 2
			)
	view.draw_string(
		_font_bold,
		rect.position + Vector2(0, h * 0.5 + 8.0 * s),
		banner_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(rect.size.x),
		int((26 if danger else 22) * s),
		Color(1.0, 1.0, 1.0, fade)
	)


## ── Interne Zeichen-Helfer ───────────────────────────────────────────────


func _draw_card(type: String, rect: Rect2, from_belt: bool) -> void:
	var info: Dictionary = view._card_info(type)
	var cost := int(info.get("cost", 0))
	var cooldown := int(info.get("cooldown_left", 0))
	var affordable := type == "shovel" or from_belt or int(view.hud_resource()) >= cost
	var fill := AcTokens.PAPER if affordable and cooldown == 0 else AcTokens.PAPER_SHADE
	_rounded(rect, fill)
	if str(view.selected_card) == type:
		view.draw_rect(rect, AcTokens.PINK, false, 3.0)
	if type == "shovel":
		_draw_shovel_icon(rect.get_center())
	else:
		var icon_at: Vector2 = rect.get_center() + Vector2(0, rect.size.y * 0.28)
		if bool(info.get("zombie", false)):
			GvzArt.draw_zombie(view, type, icon_at, rect.size.y * 0.5, 0)
		else:
			GvzArt.draw_tower(view, type, icon_at, rect.size.y * 0.6, 0)
		var label := "◦%d" % cost if not from_belt else I18nService.t("gvz.hud.free")
		view.draw_string(
			_font,
			rect.position + Vector2(4, 14),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(rect.size.x) - 8,
			11,
			AcTokens.INK if affordable else GvzArt.BERRY_RED
		)
	if cooldown > 0 and not from_belt:
		var total := int(info.get("cooldown_total", 1))
		var left := float(cooldown) / float(maxi(1, total))
		view.draw_rect(
			Rect2(rect.position, Vector2(rect.size.x, rect.size.y * left)),
			Color(0.29, 0.23, 0.21, 0.35)
		)


func _draw_shovel_icon(at: Vector2) -> void:
	view.draw_line(at + Vector2(-8, -14), at + Vector2(8, 6), GvzArt.WOOD, 5.0)
	var points := PackedVector2Array(
		[at + Vector2(4, 2), at + Vector2(16, 10), at + Vector2(8, 18)]
	)
	view.draw_colored_polygon(points, GvzArt.METAL)


func _draw_conveyor_strip(queue: Array) -> void:
	var vp: Vector2 = view._view_size()
	var w := 34.0
	var x: float = vp.x - 8.0 - w * maxf(1.0, float(queue.size()))
	# Band-Vorschau ÜBER der Kartenleiste (Karten hängen unten, G4).
	var strip := Rect2(x, view._card_top() - 34.0, w * maxf(1.0, float(queue.size())), 30.0)
	_rounded(strip, Color("#D8CBB4"))
	for i in queue.size():
		var center: Vector2 = strip.position + Vector2(w * (i + 0.5), 22.0)
		GvzArt.draw_tower(view, str(queue[i]), center, 24.0, 0)
		if i == 0:
			view.draw_rect(
				Rect2(strip.position + Vector2(w * i, 0), Vector2(w, 30.0)),
				AcTokens.LEAF,
				false,
				2.0
			)


func _draw_boss_bar() -> void:
	var boss: Dictionary = view.state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return
	var vp: Vector2 = view._view_size()
	# Oben mittig — unten wohnt jetzt die Kartenleiste (G4).
	var rect := Rect2(vp.x * 0.3, 8.0, vp.x * 0.4, 10.0)
	_rounded(rect, AcTokens.PAPER)
	var frac := float(boss["hp"]) / float(maxi(1, int(boss["max_hp"])))
	view.draw_rect(
		Rect2(
			rect.position + Vector2(1, 1), Vector2((rect.size.x - 2.0) * frac, rect.size.y - 2.0)
		),
		GvzArt.BERRY_RED
	)


## Netz-PvP-Schicht (P26): Überlebens-Timer oben mittig + „Warte auf
## Partner“-Hinweis, wenn der Lockstep auf den Partner-Fence wartet.
func _draw_netz_status() -> void:
	var info: Dictionary = view.netz_hud_info()
	if not bool(info.get("active", false)):
		return
	var vp: Vector2 = view._view_size()
	var seconds := maxi(0, int(info.get("seconds_left", 0)))
	@warning_ignore("integer_division")
	var timer_text := "%d:%02d" % [seconds / 60, seconds % 60]
	var chip := Rect2(vp.x * 0.5 - 44.0, 24.0, 88.0, 26.0)
	_rounded(chip, AcTokens.PAPER)
	view.draw_string(
		_font_bold,
		chip.position + Vector2(0, 19),
		timer_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(chip.size.x),
		16,
		AcTokens.INK
	)
	if bool(info.get("waiting", false)):
		view.draw_string(
			_font,
			Vector2(0, 68),
			I18nService.t("gvz.netz.warte_partner"),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(vp.x),
			14,
			Color(0.29, 0.23, 0.21, 0.8)
		)


func _draw_bar(at: Vector2, width: float, frac: float, color: Color) -> void:
	view.draw_rect(Rect2(at, Vector2(width, 4.0)), Color(0.29, 0.23, 0.21, 0.4))
	view.draw_rect(Rect2(at, Vector2(width * clampf(frac, 0.0, 1.0), 4.0)), color)


func _rounded(rect: Rect2, color: Color) -> void:
	view.draw_rect(rect, GvzArt.OUTLINE.lerp(color, 0.7))
	view.draw_rect(rect.grow(-1.5), color)
