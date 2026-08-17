class_name UpdatesSektion
extends VBoxContainer
## W15/UPDREPO — Zusatzzeilen der Settings-Sektion "Updates" (unter dem
## "Nach Updates suchen"-Knopf). Eigene Datei nach dem NETSET-Muster: die
## Sektions-HUELLE baut settings_screen._build_updates_section, dort haengt
## NUR die minimale Andock-Zeile `rows.add_child(UpdatesSektion.new())`.
##
## Inhalt: das maskierte Feld "GitHub-Token (fuer App-Updates)". Das Update-
## Repo ist das PRIVATE Haupt-Repo — Downloads laufen ueber die GitHub-
## Release-API und brauchen dafuer einen Zugangsschluessel (fine-grained PAT,
## nur contents:read; verteilt der Server-Betreiber, docs/UPDATES.md).
## Persistenz: user://updates_user_override.json ueber die statischen
## UpdateService-Helfer; resolve_github_token liest die Datei MIT VORRANG vor
## dem config-Pack-Feld `github_token` bei JEDER Update-Suche frisch — kein
## Neustart noetig.

var _token_edit: LineEdit
var _status: Label
var _zuletzt_gespeichert := ""


func _ready() -> void:
	name = "UpdatesZeilen"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var f := UiScale.for_viewport(get_viewport())
	var tf := UiScale.font_scale(get_viewport())
	add_theme_constant_override("separation", int(10.0 * f))
	var row := HBoxContainer.new()
	row.name = "RowGithubToken"
	row.add_theme_constant_override("separation", int(12.0 * f))
	var label := Label.new()
	label.name = "RowLabel"
	label.text = I18nService.t("updates.token_label")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * tf))
	row.add_child(label)
	_token_edit = LineEdit.new()
	_token_edit.name = "Value"
	_token_edit.secret = true
	_token_edit.placeholder_text = I18nService.t("updates.token_platzhalter")
	_token_edit.custom_minimum_size = Vector2(240.0 * f, AcTokens.TOUCH_FLOOR * f)
	_token_edit.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * tf))
	_token_edit.text_submitted.connect(func(_text: String) -> void: _speichern())
	_token_edit.focus_exited.connect(_speichern)
	row.add_child(_token_edit)
	add_child(row)
	var hinweis := Label.new()
	hinweis.name = "TokenHinweis"
	hinweis.theme_type_variation = "SoftLabel"
	hinweis.text = I18nService.t("updates.token_hinweis")
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinweis.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * tf))
	add_child(hinweis)
	_status = Label.new()
	_status.name = "TokenStatus"
	_status.theme_type_variation = "SoftLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * tf))
	_status.visible = false
	add_child(_status)
	_token_edit.text = str(UpdateService.load_user_override().get("github_token", ""))
	_zuletzt_gespeichert = _token_edit.text


## Speichert das Token in die User-Settings-Datei (leer = Datei weg, es gilt
## wieder das config-Pack-Feld). Wirkt ab der naechsten Update-Suche.
func _speichern() -> void:
	var token := _token_edit.text.strip_edges()
	if token == _zuletzt_gespeichert:
		return
	_zuletzt_gespeichert = token
	if token.is_empty():
		UpdateService.clear_user_override()
	else:
		UpdateService.save_user_override({"github_token": token})
	_status.text = I18nService.t("updates.token_gespeichert")
	_status.visible = true
