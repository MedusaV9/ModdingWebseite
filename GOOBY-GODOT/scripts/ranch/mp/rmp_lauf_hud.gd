class_name RmpLaufHud
extends PanelContainer
## Live-HUD während Rennen/Fangen/Parcours (RW-6): eigener Fortschritt
## (Tor n/max), Fortschritt der Gegner (aus MG_STATE), Fänger-Anzeige +
## Restzeit beim Fangen, Strafzeiten im Parcours, Peer-Down/Up-Hinweise.
## Rein anzeigend — Spiellogik läuft im Controller/Service.

var service: RanchMultiplayerService = null

var _zeile1: Label
var _zeile2: Label
var _hinweis: Label
var _hinweis_bis_ms := 0
var _progress: Dictionary = {}
var _strafen_ms := 0
var _mein_next := 0


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_zeile1 = Label.new()
	_zeile1.theme_type_variation = &"TitleLabel"
	box.add_child(_zeile1)
	_zeile2 = Label.new()
	_zeile2.theme_type_variation = &"CaptionLabel"
	box.add_child(_zeile2)
	_hinweis = Label.new()
	_hinweis.theme_type_variation = &"CaptionLabel"
	_hinweis.visible = false
	box.add_child(_hinweis)
	_refresh()


func setup(mp_service: RanchMultiplayerService) -> void:
	service = mp_service
	service.state_updated.connect(_on_state)
	service.peer_down.connect(_on_peer_down)
	service.peer_up.connect(_on_peer_up)
	service.match_started.connect(func(_d: Dictionary) -> void: _reset())


## Eigener Checkpoint-Fortschritt (Controller meldet nach OK vom Server).
func set_mein_fortschritt(next_idx: int) -> void:
	_mein_next = next_idx
	_refresh()


func _process(_delta: float) -> void:
	if _hinweis.visible and Time.get_ticks_msec() > _hinweis_bis_ms:
		_hinweis.visible = false
	if service != null and service.mode == "fangen" and service.ends_at_ms > 0:
		_refresh()


func _on_state(data: Dictionary) -> void:
	if data.get("progress") is Dictionary:
		for code: Variant in data["progress"] as Dictionary:
			_progress[str(code)] = int((data["progress"] as Dictionary)[code])
	if data.get("strafe") is Dictionary:
		var strafe: Dictionary = data["strafe"]
		if str(strafe.get("friendCode", "")) == _mein_code():
			_strafen_ms = int(strafe.get("strafenMs", 0))
			_zeige_hinweis(
				I18nService.t("ranch_mp.lauf.strafe", {"s": "%.0f" % (float(_strafen_ms) / 1000.0)})
			)
	if data.get("finished") is Dictionary:
		var fin: Dictionary = data["finished"]
		if str(fin.get("friendCode", "")) == _mein_code():
			_zeige_hinweis(I18nService.t("ranch_mp.lauf.ziel"))
	if data.get("dnf") is Dictionary:
		var wer := _name_fuer(str((data["dnf"] as Dictionary).get("friendCode", "")))
		_zeige_hinweis("%s — %s" % [wer, I18nService.t("ranch_mp.ergebnis.dnf")])
	_refresh()


func _on_peer_down(data: Dictionary) -> void:
	_zeige_hinweis(
		I18nService.t(
			"ranch_mp.lauf.peer_weg", {"name": _name_fuer(str(data.get("friendCode", "")))}
		)
	)


func _on_peer_up(data: Dictionary) -> void:
	_zeige_hinweis(
		I18nService.t(
			"ranch_mp.lauf.peer_da", {"name": _name_fuer(str(data.get("friendCode", "")))}
		)
	)


func _refresh() -> void:
	if _zeile1 == null:
		return
	if service == null:
		_zeile1.text = ""
		_zeile2.text = ""
		return
	if service.mode == "fangen":
		var it := service.it_code
		if it == _mein_code():
			_zeile1.text = I18nService.t("ranch_mp.lauf.du_bist_faenger")
		else:
			_zeile1.text = I18nService.t("ranch_mp.lauf.faenger", {"name": _name_fuer(it)})
		var rest := maxi(0, service.ends_at_ms - service.server_now_ms())
		_zeile2.text = I18nService.t("ranch_mp.lauf.restzeit", {"s": rest / 1000})
		return
	var max_tore := RmpKurse.checkpoint_anzahl(service.kurs)
	_zeile1.text = I18nService.t("ranch_mp.lauf.checkpoint", {"n": _mein_next, "max": max_tore})
	_zeile1.text += "  ·  %s" % I18nService.t("ranch_mp.lauf.platz", {"n": _mein_platz()})
	var teile: Array[String] = []
	for spieler: Variant in service.players:
		if not (spieler is Dictionary):
			continue
		var code := str((spieler as Dictionary).get("friendCode", ""))
		if code == _mein_code():
			continue
		(
			teile
			. append(
				(
					"%s %d/%d"
					% [
						str((spieler as Dictionary).get("name", code)),
						int(_progress.get(code, 0)),
						max_tore,
					]
				)
			)
		)
	_zeile2.text = " · ".join(teile)


## Live-Platz aus dem Checkpoint-Fortschritt (bei Gleichstand optimistisch).
func _mein_platz() -> int:
	var platz := 1
	for code: Variant in _progress:
		if str(code) != _mein_code() and int(_progress[code]) > _mein_next:
			platz += 1
	return platz


func _reset() -> void:
	_progress = {}
	_strafen_ms = 0
	_mein_next = 0
	_refresh()


func _zeige_hinweis(text: String) -> void:
	_hinweis.text = text
	_hinweis.visible = true
	_hinweis_bis_ms = Time.get_ticks_msec() + 3000


func _mein_code() -> String:
	return service.my_code() if service != null else ""


func _name_fuer(code: String) -> String:
	if service != null:
		for spieler: Variant in service.players:
			if spieler is Dictionary and str((spieler as Dictionary).get("friendCode", "")) == code:
				return str((spieler as Dictionary).get("name", code))
	return code
