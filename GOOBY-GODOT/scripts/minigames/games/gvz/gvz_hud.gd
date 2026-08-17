class_name GvzHud
extends RefCounted
## HUD-Zeichnung der GvZ-Spielszene (G5/P26-Split, Muster build_ui_dock.gd):
## gvz_game.gd stand exakt am 1000-Zeilen-Limit — Karten, Zähler, Balken,
## Banner und Drag-Ghost wohnen jetzt hier. Reine PRÄSENTATION: dieser
## Helfer liest den Sim-State nur und zeichnet auf die Szene (view);
## Layout-Mathe (Zellen/Karten-Rects) bleibt in gvz_game.gd, weil auch die
## Eingabe sie braucht. Für das Netz-PvP (P26) kennt der HUD zusätzlich
## Matsch als Ressource, Zombie-Karten und den Überlebens-Timer.
##
## W21/P5 (Befund GVZ-1..3, die „Fix-Pixel-Schuld"): ALLE Maße skalieren
## jetzt mit dem MgHudKit-Faktor (Kurzkante/390), Schriften laufen über
## MgHudKit.font_px (Typo-Minimum 14 px), das Wellen-Banner trägt den
## Kit-Banner-Standard (Milchglas-Plate statt nackter Schrift auf Feld),
## Boss-Bar = Kit-Progress, HP-Striche bekommen Track + Skala.
##
## Eval C Befund 2 (Draw-Call-Budget): die Vektor-Icons der Kartenleiste
## kosteten pro Karte ~15 Zeichenbefehle im Rect/Polygon/Text-Wechsel — das
## zerhackt das 2D-Batching in dutzende Draw-Calls PRO FRAME. Ein Einweg-
## SubViewport rendert deshalb alle Icons EINMAL in einen Atlas; die Leiste
## zeichnet in PÄSSEN (alle Plates → alle Icons aus DEMSELBEN Atlas → alle
## Texte → alle Schleier), sodass gleichartige Befehle zusammen batchen.

const BANNER_SEC := 2.2
## Spaltenzahl des Icon-Atlas (Kacheln zeilenweise, Türme→Zombies→Extras).
const ATLAS_COLS := 6

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
## Kit-Plates (W21/P5): Banner-Milchglas + Progress-Track, wiederverwendet.
var _banner_plate := StyleBoxFlat.new()
var _progress_plate := MgHudKit.progress_plate()
## Icon-Atlas (Eval C Befund 2): Einweg-SubViewport als Textur-Quelle.
var _atlas_vp: SubViewport
## Typ → Zell-Rect im Atlas; "shovel"/"nutella" sind Sonderzellen.
var _atlas_cells: Dictionary = {}
## Fuß-Anker innerhalb einer Zelle (Figuren stehen auf diesem Punkt).
var _atlas_foot := Vector2.ZERO
## Aktiver Größen-Schlüssel bzw. gerade angeforderter (Bau via deferred).
var _atlas_key := ""
var _atlas_want := ""


func _init(game_view: CanvasItem) -> void:
	view = game_view
	_font = ThemeService.font(600)
	_font_bold = ThemeService.font(800)


## DER Skalierungs-Faktor des Gefechts-HUD (MgHudKit-Kanon, W21/P5).
func ui() -> float:
	return MgHudKit.ui_scale(view._view_size())


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


## Kartenleiste + Zähler in PÄSSEN (Eval C Befund 2): erst alle Plates
## (Rects), dann alle Icons (Atlas-Textur), dann alle Texte, dann alle
## Cooldown-Schleier — gleichartige Zeichenbefehle batchen zusammen, statt
## pro Karte Rect/Polygon/Text im Wechsel das Batching zu zerhacken.
func draw_hud() -> void:
	var state: Dictionary = view.state
	var f := ui()
	# Ressourcen-Zähler (Nutella bzw. PvP-Matsch) — poppt bei jeder Änderung.
	var amount := int(view.hud_resource())
	if amount != _resource_seen:
		if _resource_seen >= 0:
			_resource_pop = Time.get_ticks_msec() / 1000.0
		_resource_seen = amount
	var pop := maxf(0.0, 1.0 - (Time.get_ticks_msec() / 1000.0 - _resource_pop) / 0.3)
	# Zähler-Chip links NEBEN der Kartenleiste an der Unterkante (G4);
	# W21/P5: Maße/Schrift auf Skala×f (vorher 78/34/17 px fix).
	var dims: Vector2 = view._card_dims()
	var vp: Vector2 = view._view_size()
	var atlas := _atlas_ready(f, dims)
	var counter := Rect2(6.0 * f, vp.y - view.TOP_PAD - dims.y, 78.0 * f, dims.y)
	var cards: Array = view._card_list()
	var queue: Array = state["conveyor"].get("queue", []) if bool(view._conveyor_active()) else []
	var conveyor_only: bool = (
		view._conveyor_active() and not bool(state["mods"].get("conveyor_hybrid", false))
	)
	# Pass 1: alle Plates.
	_rounded(
		counter, AcTokens.PAPER if pop <= 0.0 else AcTokens.PAPER.lerp(GvzArt.STAR_GOLD, pop * 0.35)
	)
	for i in cards.size():
		_card_plate(str(cards[i]), view._card_rect(i), conveyor_only or queue.has(str(cards[i])))
	# Pass 2: alle Icons.
	var drop_s := 34.0 * f * (1.0 + 0.25 * pop)
	var drop_at: Vector2 = counter.position + Vector2(22.0 * f, dims.y * 0.71)
	if atlas:
		var bob := sin(float(int(state["tick"])) * 0.2) * drop_s * 0.04
		_atlas_icon("nutella", drop_at + Vector2(0.0, bob), drop_s / (34.0 * f))
	else:
		GvzArt.draw_nutella_drop(view, drop_at, drop_s, int(state["tick"]))
	for i in cards.size():
		_card_icon(str(cards[i]), view._card_rect(i), f, dims, atlas)
	# Pass 3: alle Texte.
	view.draw_string(
		_font_bold,
		counter.position + Vector2(38.0 * f, dims.y * 0.61),
		str(amount),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		int(MgHudKit.font_px(17.0, f) * (1.0 + 0.2 * pop)),
		AcTokens.INK
	)
	for i in cards.size():
		_card_label(str(cards[i]), view._card_rect(i), conveyor_only or queue.has(str(cards[i])), f)
	# Pass 4: Cooldown-Schleier + Sonderleisten.
	for i in cards.size():
		_card_cooldown(str(cards[i]), view._card_rect(i), conveyor_only or queue.has(str(cards[i])))
	if bool(view._conveyor_active()) and not conveyor_only:
		_draw_conveyor_strip(queue, f, dims, atlas)
	_draw_boss_bar(f)
	_draw_netz_status(f)


## Drag-Feedback: das Karten-Icon folgt dem Finger (UI-Schicht); die grüne/
## rote Zell-Markierung rendert die 3D-Bühne (_sync_stage → ghost).
func draw_ghost() -> void:
	if not bool(view.dragging) or view.selected_card == "" or view.selected_card == "shovel":
		return
	var f := ui()
	var at: Vector2 = view.drag_pos + Vector2(0.0, 20.0 * f)
	var type := str(view.selected_card)
	var zombie := bool((view._card_info(type) as Dictionary).get("zombie", false))
	if _atlas_live() and _atlas_cells.has(type):
		var dims: Vector2 = view._card_dims()
		var baked := dims.y * (0.5 if zombie else 0.6)
		_atlas_icon(type, at, (34.0 if zombie else 44.0) * f / baked)
	elif zombie:
		GvzArt.draw_zombie(view, type, at, 34.0 * f, 0)
	else:
		GvzArt.draw_tower(view, type, at, 44.0 * f, 0)


## Wellen-Banner im Kit-Standard (W21/P5, Befund GVZ-3): Milchglas-Plate +
## Tinte statt nackter weißer Schrift auf dem Feld — Größe/Optik identisch
## zu tea/memory/carrot. Der GvZ-Charakter bleibt als Flanken-Deko: Mini-
## Zombies neben Wellen-/Boss-Bannern, das Intro-Duell Möhre vs. Schlurfi.
func draw_banner() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if banner_text == "" or now > banner_until:
		return
	var state: Dictionary = view.state
	var vp: Vector2 = view._view_size()
	var f := ui()
	var rect := MgHudKit.draw_banner(
		view, _banner_plate, vp, f, banner_text, banner_until - now, banner_kind == "intro"
	)
	if rect.size.x <= 0.0:
		return
	var h := rect.size.y
	if banner_kind == "intro":
		# Ziel-Icon-Duell: links der Möhren-Wächter, rechts sein Zombie.
		var icon := h * 0.5
		GvzArt.draw_tower(
			view, "moehre", rect.position + Vector2(-icon - 8.0 * f, h * 0.85), icon * 1.3, 0
		)
		GvzArt.draw_zombie(
			view,
			"schlurfi",
			rect.position + Vector2(rect.size.x + icon + 8.0 * f, h * 0.8),
			icon,
			0
		)
	elif banner_kind != "info":
		var icon_s := h * 0.42
		var horde := 3 if banner_kind == "huge" else 1
		for i in horde:
			var offset := icon_s * (0.4 + 1.1 * float(i))
			GvzArt.draw_zombie(
				view,
				"schlurfi",
				rect.position + Vector2(-offset - 6.0 * f, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 3
			)
			GvzArt.draw_zombie(
				view,
				"schlurfi",
				rect.position + Vector2(rect.size.x + offset + 6.0 * f, h * 0.72),
				icon_s,
				int(state["tick"]) + i * 5 + 2
			)


## ── Interne Zeichen-Helfer ───────────────────────────────────────────────


## Pass 1: Karten-Plate + Auswahl-Rahmen (nur Rects).
func _card_plate(type: String, rect: Rect2, from_belt: bool) -> void:
	var info: Dictionary = view._card_info(type)
	var affordable := (
		type == "shovel" or from_belt or int(view.hud_resource()) >= int(info.get("cost", 0))
	)
	var fill := (
		AcTokens.PAPER
		if affordable and int(info.get("cooldown_left", 0)) == 0
		else AcTokens.PAPER_SHADE
	)
	_rounded(rect, fill)
	if str(view.selected_card) == type:
		view.draw_rect(rect, AcTokens.PINK, false, 3.0)


## Pass 2: Karten-Icon — aus dem Atlas (EIN Textur-Rect) oder als
## Vektor-Fallback, solange der Atlas noch baut.
func _card_icon(type: String, rect: Rect2, f: float, dims: Vector2, atlas: bool) -> void:
	if type == "shovel":
		if atlas:
			_atlas_icon("shovel", rect.get_center(), 1.0)
		else:
			_draw_shovel_icon(view, rect.get_center(), f)
		return
	var icon_at: Vector2 = rect.get_center() + Vector2(0, rect.size.y * 0.28)
	if atlas and _atlas_cells.has(type):
		_atlas_icon(type, icon_at, rect.size.y / dims.y)
	elif bool((view._card_info(type) as Dictionary).get("zombie", false)):
		GvzArt.draw_zombie(view, type, icon_at, rect.size.y * 0.5, 0)
	else:
		GvzArt.draw_tower(view, type, icon_at, rect.size.y * 0.6, 0)


## Pass 3: Kosten-Label. W21/P5 (GVZ-1): Kosten auf Skala×f mit
## Typo-Minimum + hellem Saum statt 11 px nackt über den Hasenohren.
func _card_label(type: String, rect: Rect2, from_belt: bool, f: float) -> void:
	if type == "shovel":
		return
	var cost := int((view._card_info(type) as Dictionary).get("cost", 0))
	var affordable := from_belt or int(view.hud_resource()) >= cost
	var label := "◦%d" % cost if not from_belt else I18nService.t("gvz.hud.free")
	var label_px := MgHudKit.font_px(12.0, f)
	var label_at: Vector2 = rect.position + Vector2(4.0 * f, 2.0 * f + float(label_px))
	view.draw_string_outline(
		_font,
		label_at,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		int(rect.size.x - 8.0 * f),
		label_px,
		maxi(2, AcTokens.px(3.0, f)),
		Color(1.0, 0.99, 0.94, 0.9)
	)
	view.draw_string(
		_font,
		label_at,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		int(rect.size.x - 8.0 * f),
		label_px,
		AcTokens.INK if affordable else GvzArt.BERRY_RED
	)


## Pass 4: Cooldown-Schleier über der ganzen Karte.
func _card_cooldown(type: String, rect: Rect2, from_belt: bool) -> void:
	var info: Dictionary = view._card_info(type)
	var cooldown := int(info.get("cooldown_left", 0))
	if cooldown <= 0 or from_belt:
		return
	var left := float(cooldown) / float(maxi(1, int(info.get("cooldown_total", 1))))
	view.draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, rect.size.y * left)),
		Color(0.29, 0.23, 0.21, 0.35)
	)


func _draw_shovel_icon(ci: CanvasItem, at: Vector2, f: float) -> void:
	ci.draw_line(at + Vector2(-8, -14) * f, at + Vector2(8, 6) * f, GvzArt.WOOD, 5.0 * f)
	var points := PackedVector2Array(
		[at + Vector2(4, 2) * f, at + Vector2(16, 10) * f, at + Vector2(8, 18) * f]
	)
	ci.draw_colored_polygon(points, GvzArt.METAL)


func _draw_conveyor_strip(queue: Array, f: float, dims: Vector2, atlas: bool) -> void:
	var vp: Vector2 = view._view_size()
	var w := 34.0 * f
	var x: float = vp.x - 8.0 * f - w * maxf(1.0, float(queue.size()))
	# Band-Vorschau ÜBER der Kartenleiste (Karten hängen unten, G4).
	var strip := Rect2(x, view._card_top() - 34.0 * f, w * maxf(1.0, float(queue.size())), 30.0 * f)
	_rounded(strip, Color("#D8CBB4"))
	for i in queue.size():
		var center: Vector2 = strip.position + Vector2(w * (i + 0.5), 22.0 * f)
		if atlas and _atlas_cells.has(str(queue[i])):
			_atlas_icon(str(queue[i]), center, 24.0 * f / (dims.y * 0.6))
		else:
			GvzArt.draw_tower(view, str(queue[i]), center, 24.0 * f, 0)
		if i == 0:
			view.draw_rect(
				Rect2(strip.position + Vector2(w * i, 0), Vector2(w, 30.0 * f)),
				AcTokens.LEAF,
				false,
				2.0
			)


## Boss-Bar = Kit-Progress (EINE Balkenhöhe, Pill-Track — W21/P5).
func _draw_boss_bar(f: float) -> void:
	var boss: Dictionary = view.state["boss"]
	if boss.is_empty() or int(boss["hp"]) <= 0:
		return
	var vp: Vector2 = view._view_size()
	# Oben mittig — unten wohnt jetzt die Kartenleiste (G4).
	var rect := Rect2(vp.x * 0.3, 8.0 * f, vp.x * 0.4, MgHudKit.bar_h(f))
	var frac := float(boss["hp"]) / float(maxi(1, int(boss["max_hp"])))
	MgHudKit.draw_progress(view, _progress_plate, rect, frac, GvzArt.BERRY_RED)


## Netz-PvP-Schicht (P26): Überlebens-Timer oben mittig + „Warte auf
## Partner“-Hinweis, wenn der Lockstep auf den Partner-Fence wartet.
func _draw_netz_status(f: float) -> void:
	var info: Dictionary = view.netz_hud_info()
	if not bool(info.get("active", false)):
		return
	var vp: Vector2 = view._view_size()
	var seconds := maxi(0, int(info.get("seconds_left", 0)))
	@warning_ignore("integer_division")
	var timer_text := "%d:%02d" % [seconds / 60, seconds % 60]
	var chip := Rect2(vp.x * 0.5 - 44.0 * f, 24.0 * f, 88.0 * f, 26.0 * f)
	_rounded(chip, AcTokens.PAPER)
	view.draw_string(
		_font_bold,
		chip.position + Vector2(0.0, 19.0 * f),
		timer_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		int(chip.size.x),
		MgHudKit.font_px(16.0, f),
		AcTokens.INK
	)
	if bool(info.get("waiting", false)):
		view.draw_string(
			_font,
			Vector2(0.0, 68.0 * f),
			I18nService.t("gvz.netz.warte_partner"),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(vp.x),
			MgHudKit.font_px(14.0, f),
			Color(0.29, 0.23, 0.21, 0.8)
		)


## ── Icon-Atlas (Eval C Befund 2) ─────────────────────────────────────────


## true = Atlas nutzbar. Fehlt er (erster Frame, Resize), stößt das den Bau
## deferred an und dieser Frame zeichnet noch den Vektor-Fallback.
func _atlas_ready(f: float, dims: Vector2) -> bool:
	var key := "%d|%d" % [int(dims.y * 4.0), int(f * 100.0)]
	if key == _atlas_key and is_instance_valid(_atlas_vp):
		return true
	if key != _atlas_want:
		_atlas_want = key
		_build_icon_atlas.call_deferred(key, f, dims)
	return false


func _atlas_live() -> bool:
	return _atlas_key != "" and is_instance_valid(_atlas_vp)


## Baut den SubViewport-Atlas (Türme→Zombies→Schaufel→Nutella, zeilenweise,
## Kataloge aus der Balance — deckt auch PvP-Zombie-Karten und Band-Typen).
## Der Viewport rendert EINMAL (UPDATE_ONCE) und bleibt danach als reine
## Textur-Quelle im Baum — kein weiterer Render, kein Draw-Call pro Frame.
func _build_icon_atlas(key: String, f: float, dims: Vector2) -> void:
	if key != _atlas_want or view == null or not is_instance_valid(view):
		return
	if is_instance_valid(_atlas_vp):
		_atlas_vp.queue_free()
	var towers: Array = (view.balance.get("towers", {}) as Dictionary).keys()
	towers.sort()
	var zombies: Array = (view.balance.get("zombies", {}) as Dictionary).keys()
	zombies.sort()
	var types: Array = towers.duplicate()
	types.append_array(zombies)
	types.append("shovel")
	types.append("nutella")
	# Zelle: breit/hoch genug für die größte Figur (fliegender Ballon-Zombie
	# ragt ~2,2×s über den Fuß; Fuß-Anker sitzt knapp über der Unterkante).
	var cell := Vector2(ceilf(dims.y * 1.1), ceilf(dims.y * 1.35))
	_atlas_foot = Vector2(cell.x * 0.5, cell.y - ceilf(dims.y * 0.12))
	_atlas_cells = {}
	for i in types.size():
		var col := i % ATLAS_COLS
		var row := int(float(i) / float(ATLAS_COLS))
		_atlas_cells[types[i]] = Rect2(Vector2(float(col) * cell.x, float(row) * cell.y), cell)
	var rows := ceili(float(types.size()) / float(ATLAS_COLS))
	var atlas_vp := SubViewport.new()
	atlas_vp.size = Vector2i(int(cell.x) * ATLAS_COLS, int(cell.y) * rows)
	atlas_vp.transparent_bg = true
	atlas_vp.disable_3d = true
	atlas_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Control.new()
	painter.draw.connect(_paint_icon_atlas.bind(painter, towers, zombies, f, dims))
	atlas_vp.add_child(painter)
	(view as Node).add_child(atlas_vp)
	_atlas_vp = atlas_vp
	_atlas_key = key


## Malt alle Icons in ihre Atlas-Zellen (läuft im SubViewport-Render).
func _paint_icon_atlas(
	painter: Control, towers: Array, zombies: Array, f: float, dims: Vector2
) -> void:
	for type: Variant in towers:
		GvzArt.draw_tower(painter, str(type), _cell_foot(str(type)), dims.y * 0.6, 0)
	for type: Variant in zombies:
		GvzArt.draw_zombie(painter, str(type), _cell_foot(str(type)), dims.y * 0.5, 0)
	var shovel: Rect2 = _atlas_cells["shovel"]
	_draw_shovel_icon(painter, shovel.position + shovel.size * 0.5, f)
	GvzArt.draw_nutella_drop(painter, _cell_foot("nutella"), 34.0 * f, 0)


func _cell_foot(type: String) -> Vector2:
	return (_atlas_cells[type] as Rect2).position + _atlas_foot


## EIN Textur-Rect statt ~15 Vektor-Befehlen: Zelle um den Anker skaliert.
func _atlas_icon(type: String, anchor: Vector2, scale: float) -> void:
	var cell: Rect2 = _atlas_cells[type]
	var origin := cell.size * 0.5 if type == "shovel" else _atlas_foot
	view.draw_texture_rect_region(
		_atlas_vp.get_texture(), Rect2(anchor - origin * scale, cell.size * scale), cell
	)


func _draw_bar(at: Vector2, width: float, frac: float, color: Color) -> void:
	# W21/P5 (GVZ-2): HP-Striche skalieren mit und bekommen einen Track-
	# Saum statt der nackten dünnen Linie.
	var h := maxf(3.0, 4.0 * ui())
	view.draw_rect(Rect2(at, Vector2(width, h)).grow(1.0), Color(0.29, 0.23, 0.21, 0.45))
	view.draw_rect(Rect2(at, Vector2(width, h)), Color(1.0, 0.99, 0.94, 0.55))
	view.draw_rect(Rect2(at, Vector2(width * clampf(frac, 0.0, 1.0), h)), color)


func _rounded(rect: Rect2, color: Color) -> void:
	view.draw_rect(rect, GvzArt.OUTLINE.lerp(color, 0.7))
	view.draw_rect(rect.grow(-1.5), color)
