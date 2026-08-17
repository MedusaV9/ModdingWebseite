class_name UiMotion
extends RefCounted
## UICOZY — DIE gemeinsame Mikro-Animations-Bibliothek (der „Polish“ aus der
## Web-Referenz, styles.css-Keyframes). Alle Helfer sind statisch, nutzen die
## Web-Motion-Tokens (`AcTokens.DUR_POP`/`DUR_SHEET`, --ease-spring =
## TRANS_BACK/EASE_OUT) und sind KOMPLETT reduced-motion-gated: bei
## `UiTheme.reduced_motion` springen sie sofort in den Endzustand und geben
## `null` zurück.
##
## Panels federn auf (`pop_in`/`slide_up_in`), Karten schweben beim Hover
## (`attach_hover`), Toasts hüpfen (`bounce`), Münzen/Sticker glitzern
## (`sparkle`), Zahlen zählen hoch (`count_to`), Balken gleiten (`bar_to`).

## Web @keyframes toast-in/panel-up: Einfahr-Offset in Design-px.
const SLIDE_OFFSET := 16.0
## Karten-Hover (Web .shop-card:hover-Familie): sanftes Anheben.
const HOVER_SCALE := 1.03
## Hüpfer-Überschwinger (Toast/Chip).
const BOUNCE_SCALE := 1.06
## Web .stat-fill: width-transition 300ms ease.
const BAR_SEC := 0.3
## Zähl-Animation (HUD-Coins, Ergebnis-Zähler).
const COUNT_SEC := 0.45
## Glitzer-Partikel pro `sparkle()`-Aufruf.
const SPARKLE_COUNT := 5
const SPARKLE_SEC := 0.55
const SPARKLE_TEXTURE := "res://assets/ui/icons/sparkle.svg"


## Reduced-Motion-Zustand (statisch-sicher, ohne Autoload false).
static func reduced(node: Node) -> bool:
	return ThemeService.is_reduced_motion(node)


## Pop-in mit Federung (Web --dur-pop + --ease-spring): Scale 0.9 → 1 + Fade.
static func pop_in(ctl: Control, dur := AcTokens.DUR_POP) -> Tween:
	if not ctl.is_inside_tree():
		return null
	if reduced(ctl):
		ctl.scale = Vector2.ONE
		ctl.modulate.a = 1.0
		return null
	ctl.pivot_offset = ctl.size / 2.0
	ctl.scale = Vector2.ONE * 0.9
	ctl.modulate.a = 0.0
	var tween := ctl.create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ctl, "scale", Vector2.ONE, dur)
	tween.tween_property(ctl, "modulate:a", 1.0, dur / 2.0).set_trans(Tween.TRANS_LINEAR)
	return tween


## Panel-Auffahren mit Federung (Web @keyframes panel-up: +16 px → −3 px → 0).
static func slide_up_in(ctl: Control, dur := AcTokens.DUR_SHEET) -> Tween:
	if not ctl.is_inside_tree():
		return null
	if reduced(ctl):
		ctl.modulate.a = 1.0
		return null
	var rest_y := ctl.position.y
	ctl.position.y = rest_y + SLIDE_OFFSET
	ctl.modulate.a = 0.0
	var tween := ctl.create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(ctl, "position:y", rest_y, dur)
	tween.tween_property(ctl, "modulate:a", 1.0, dur / 2.0).set_trans(Tween.TRANS_LINEAR)
	return tween


## Sanftes Ausblenden (Web .toast-out: 250 ms ease, leicht absinken).
static func fade_out(ctl: Control, dur := 0.25) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.modulate.a = 0.0
		return null
	var tween := ctl.create_tween()
	tween.tween_property(ctl, "modulate:a", 0.0, dur)
	return tween


## Vorherigen Impuls-Tween desselben Helfers auf ctl killen (Anti-Stapeln:
## Münz-Serien erzeugten sonst parallele Tweens auf scale/rotation → Zittern).
static func _fresh_tween(ctl: Control, key: StringName) -> Tween:
	# has_meta-Guard: get_meta(key, null) loggt bei fehlendem Key einen ERROR.
	if ctl.has_meta(key):
		var alt: Variant = ctl.get_meta(key)
		if alt is Tween and (alt as Tween).is_valid():
			(alt as Tween).kill()
	var tween := ctl.create_tween()
	ctl.set_meta(key, tween)
	return tween


## Kurzer Hüpfer (Toast erscheint, Chip reagiert): 1 → 1.06 → 1, federnd.
static func bounce(ctl: Control, peak := BOUNCE_SCALE) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.scale = Vector2.ONE
		return null
	ctl.pivot_offset = ctl.size / 2.0
	ctl.scale = Vector2.ONE
	var tween := _fresh_tween(ctl, &"_uim_bounce")
	tween.tween_property(ctl, "scale", Vector2.ONE * peak, AcTokens.DUR_POP / 2.0)
	(
		tween
		. tween_property(ctl, "scale", Vector2.ONE, AcTokens.DUR_POP)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Münz-Wackler: kleiner Dreh-Impuls ±maxdeg mit federndem Ausklang.
static func wiggle(ctl: Control, max_deg := 6.0) -> Tween:
	if not ctl.is_inside_tree() or reduced(ctl):
		ctl.rotation = 0.0
		return null
	ctl.pivot_offset = ctl.size / 2.0
	ctl.rotation = 0.0
	var tween := _fresh_tween(ctl, &"_uim_wiggle")
	tween.tween_property(ctl, "rotation", deg_to_rad(-max_deg), AcTokens.DUR_POP / 3.0)
	tween.tween_property(ctl, "rotation", deg_to_rad(max_deg * 0.6), AcTokens.DUR_POP / 3.0)
	(
		tween
		. tween_property(ctl, "rotation", 0.0, AcTokens.DUR_POP)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Zahlen zählen hoch statt zu springen (HUD-Coins, Ergebnis-Screens).
## `formatter` bekommt den gerundeten int und liefert den Label-Text.
static func count_to(label: Label, from: int, to: int, formatter := Callable()) -> Tween:
	var fmt := formatter if formatter.is_valid() else func(v: int) -> String: return str(v)
	if not label.is_inside_tree() or reduced(label) or from == to:
		label.text = fmt.call(to)
		return null
	var tween := label.create_tween()
	(
		tween
		. tween_method(
			func(v: float) -> void: label.text = fmt.call(int(roundf(v))),
			float(from),
			float(to),
			COUNT_SEC
		)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	return tween


## Weicher Füllbalken (Web .stat-fill: 300 ms ease) statt Wertesprung.
static func bar_to(bar: Range, value: float) -> Tween:
	if not bar.is_inside_tree() or reduced(bar):
		bar.value = value
		return null
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", value, BAR_SEC).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	return tween


## FB3: Gestaffeltes Einblenden für Listen/Grids (Web-Stagger): jedes
## Element federt nacheinander auf (pop_in), EIN Sequenz-Tween statt
## n Timern. Reduced Motion: alles sofort sichtbar, keine Bewegung.
static func stagger_in(ctls: Array, step := 0.05) -> void:
	if ctls.is_empty():
		return
	var first := ctls[0] as Control
	if first == null or not first.is_inside_tree() or reduced(first):
		for ctl: Control in ctls:
			ctl.modulate.a = 1.0
		return
	for ctl: Control in ctls:
		ctl.modulate.a = 0.0
	var tween := first.create_tween()
	for ctl: Control in ctls:
		tween.tween_callback(_stagger_pop.bind(ctl))
		tween.tween_interval(step)


static func _stagger_pop(ctl: Control) -> void:
	if is_instance_valid(ctl) and ctl.is_inside_tree():
		ctl.modulate.a = 1.0
		pop_in(ctl)


## Schwebe-Hover für Karten/Kacheln: verbindet mouse_entered/exited EINMAL
## (Meta-Flag verhindert Doppel-Anschluss) und hebt das Control sanft an.
static func attach_hover(ctl: Control) -> void:
	if ctl.has_meta("uicozy_hover"):
		return
	ctl.set_meta("uicozy_hover", true)
	ctl.mouse_entered.connect(_hover.bind(ctl, true))
	ctl.mouse_exited.connect(_hover.bind(ctl, false))


## Glitzer beim Erhalten (Sticker/Münzen): kleine Sparkle-Sterne poppen um
## die Control-Mitte auf und verblassen. Reduced Motion: gar nichts.
static func sparkle(host: Control, tint := AcTokens.GOLD, count := SPARKLE_COUNT) -> void:
	if not host.is_inside_tree() or reduced(host):
		return
	var texture: Texture2D = load(SPARKLE_TEXTURE)
	if texture == null:
		return
	var center := host.size / 2.0
	var radius := maxf(center.length(), 24.0)
	for i in count:
		var star := TextureRect.new()
		star.texture = texture
		star.self_modulate = tint
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.custom_minimum_size = Vector2.ONE * 14.0
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.z_index = 10
		host.add_child(star)
		var angle := TAU * (float(i) + randf() * 0.6) / float(count)
		var target := center + Vector2.from_angle(angle) * radius
		star.position = center
		star.pivot_offset = Vector2.ONE * 7.0
		star.scale = Vector2.ZERO
		var tween := star.create_tween().set_parallel()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(star, "position", target - Vector2.ONE * 7.0, SPARKLE_SEC)
		tween.tween_property(star, "scale", Vector2.ONE, SPARKLE_SEC * 0.4).set_trans(
			Tween.TRANS_BACK
		)
		tween.chain().tween_property(star, "modulate:a", 0.0, SPARKLE_SEC * 0.5)
		tween.chain().tween_callback(star.queue_free)


static func _hover(ctl: Control, entered: bool) -> void:
	if reduced(ctl):
		ctl.scale = Vector2.ONE
		return
	ctl.pivot_offset = ctl.size / 2.0
	var tween := ctl.create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var target := Vector2.ONE * HOVER_SCALE if entered else Vector2.ONE
	tween.tween_property(ctl, "scale", target, AcTokens.DUR_POP)
