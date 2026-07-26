class_name RmpBesuchPanel
extends PanelContainer
## Besuchs-Overlay (RW-6): zeigt dem GAST die Ranch-Metadaten des Hosts
## (Ausbau, Pferde mit Name/Rasse/Level, Trophäen) und die Gast-Aktionen
## Streicheln/Füttern (kleine Geste, KEINE Wirtschaftswirkung) + Herz.
## Beide Seiten sehen Reaktions-Toasts über reaction_received. Für den
## HOST zeigt das Panel nur den Gast-Hinweis + Herz. Andocken über
## setup(service) — die Ranch-Welt selbst rendert die Szene (POS-Relay
## läuft über MG_POSE, s. rmp_ausritt_controller.gd).

signal ende_pressed

var service: RanchMultiplayerService = null

var _titel: Label
var _status: NetStatusIndicator
var _info_box: VBoxContainer
var _toast: Label
var _toast_bis_ms := 0
var _pferde_namen: Array[String] = []


func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 12)
	box.add_child(kopf)
	_titel = Label.new()
	_titel.theme_type_variation = &"HeadlineLabel"
	_titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(_titel)
	_status = NetStatusIndicator.new()
	kopf.add_child(_status)
	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 4)
	box.add_child(_info_box)
	_toast = Label.new()
	_toast.theme_type_variation = &"CaptionLabel"
	_toast.visible = false
	box.add_child(_toast)
	var aktionen := HBoxContainer.new()
	aktionen.add_theme_constant_override("separation", 8)
	box.add_child(aktionen)
	_baue_knopf(aktionen, "ranch_mp.besuch.herz", func() -> void: _sende_herz())
	_baue_knopf(aktionen, "ranch_mp.besuch.streicheln", func() -> void: _sende_geste("streicheln"))
	_baue_knopf(aktionen, "ranch_mp.besuch.fuettern", func() -> void: _sende_geste("fuettern"))
	var ende := Button.new()
	ende.theme_type_variation = &"GhostButton"
	ende.text = I18nService.t("ranch_mp.besuch.beenden")
	ende.pressed.connect(func() -> void: ende_pressed.emit())
	aktionen.add_child(ende)


func setup(mp_service: RanchMultiplayerService) -> void:
	service = mp_service
	if _status != null and service.net() != null:
		_status.setup(service.net())
	service.reaction_received.connect(_on_reaction)


func _process(_delta: float) -> void:
	if _toast.visible and Time.get_ticks_msec() > _toast_bis_ms:
		_toast.visible = false


## Host-Ranch-Metadaten anzeigen (Gast-Sicht; meta = RmpRanchMeta.normalize).
func zeige_ranch(meta: Dictionary) -> void:
	_titel.text = I18nService.t("ranch_mp.besuch.titel", {"name": str(meta.get("name", "?"))})
	for kind in _info_box.get_children():
		kind.queue_free()
	_pferde_namen = []
	var ausbau: Dictionary = meta.get("ausbau", {}) if meta.get("ausbau") is Dictionary else {}
	var extras := ""
	if bool(ausbau.get("reitplatz", false)):
		extras += I18nService.t("ranch_mp.besuch.reitplatz")
	if bool(ausbau.get("weidezaun", false)):
		extras += I18nService.t("ranch_mp.besuch.weidezaun")
	_zeile(
		I18nService.t(
			"ranch_mp.besuch.ausbau", {"boxen": int(ausbau.get("boxen", 1)), "extras": extras}
		)
	)
	_zeile(
		(
			I18nService
			. t(
				"ranch_mp.besuch.trophaeen",
				{
					"n": (meta.get("trophaeen", []) as Array).size(),
					"n2": int(_num(meta.get("schleifen"), 0.0)),
				}
			)
		)
	)
	var kopf := Label.new()
	kopf.theme_type_variation = &"CaptionLabel"
	kopf.text = I18nService.t("ranch_mp.besuch.pferde")
	_info_box.add_child(kopf)
	for pferd: Variant in meta.get("pferde", []):
		if not (pferd is Dictionary):
			continue
		_pferde_namen.append(str((pferd as Dictionary).get("name", "?")))
		_zeile(
			(
				I18nService
				. t(
					"ranch_mp.besuch.pferd_zeile",
					{
						"name": str((pferd as Dictionary).get("name", "?")),
						"rasse": str((pferd as Dictionary).get("rasse", "?")),
						"level": int(_num((pferd as Dictionary).get("level"), 1.0)),
					}
				)
			)
		)


## Host-Sicht: „X ist zu Besuch!" statt Ranch-Infos.
func zeige_gast(gast_name: String) -> void:
	_titel.text = I18nService.t("ranch_mp.besuch.gast", {"name": gast_name})


## ---------------------------------------------------------------- intern


func _sende_herz() -> void:
	if service != null and service.send_reaction("HERZ"):
		_zeige_toast("♥")


func _sende_geste(geste: String) -> void:
	if service == null:
		return
	var pferd := _pferde_namen[0] if not _pferde_namen.is_empty() else ""
	if service.send_reaction("GESTE", {"id": geste, "pferd": pferd}):
		_zeige_toast(
			I18nService.t(
				"ranch_mp.besuch.geste_%s" % geste,
				{"name": I18nService.t("ranch_mp.besten.du"), "pferd": pferd}
			)
		)


func _on_reaction(kind: String, from_code: String, body: Dictionary) -> void:
	var wer := _name_fuer(from_code)
	match kind:
		"HERZ":
			_zeige_toast(I18nService.t("ranch_mp.besuch.herz_von", {"name": wer}))
		"GESTE":
			var geste := str(body.get("id", ""))
			if geste == "streicheln" or geste == "fuettern":
				_zeige_toast(
					I18nService.t(
						"ranch_mp.besuch.geste_%s" % geste,
						{"name": wer, "pferd": str(body.get("pferd", ""))}
					)
				)


func _zeige_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_bis_ms = Time.get_ticks_msec() + 3000


func _zeile(text: String) -> void:
	var label := Label.new()
	label.theme_type_variation = &"SoftLabel"
	label.text = text
	_info_box.add_child(label)


func _name_fuer(code: String) -> String:
	if service != null:
		for spieler: Variant in service.players:
			if spieler is Dictionary and str((spieler as Dictionary).get("friendCode", "")) == code:
				return str((spieler as Dictionary).get("name", code))
	return code


func _baue_knopf(parent: Node, key: String, handler: Callable) -> void:
	var btn := Button.new()
	btn.theme_type_variation = &"PrimaryButton"
	btn.text = I18nService.t(key)
	btn.pressed.connect(handler)
	parent.add_child(btn)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
