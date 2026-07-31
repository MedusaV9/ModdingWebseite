class_name PhoneApps
extends RefCounted
## IGohbie-App-Registry (Doc E §5.1 „App-Shell-Contract: Apps registrieren
## sich per Manifest“) — PURE. EINE Liste, aus der die Shell das App-Grid
## baut und die Tests die Reihenfolge/Gates prüfen. Neue Apps kommen HIER
## dazu, nicht im UI-Code.
##
## Manifest je App: {id, name_key, text_key, icon, gate}.
##   gate: ""       — immer offen
##         "kamera" — erst nach dem Kamera-Kauf bei POW! (USER §E61)
##         "online" — braucht den Netz-Client (degradiert offline im App-UI)

const ICON_DIR := "res://assets/city/icons"

const MANIFEST: Array[Dictionary] = [
	{
		"id": "taxi",
		"name_key": "phone.app.taxi",
		"text_key": "phone.app.taxi_text",
		"icon": "app_taxi",
		"gate": "",
	},
	{
		"id": "guber",
		"name_key": "phone.app.guber",
		"text_key": "phone.app.guber_text",
		"icon": "app_guber",
		"gate": "",
	},
	{
		"id": "gooberando",
		"name_key": "phone.app.gooberando",
		"text_key": "phone.app.gooberando_text",
		"icon": "app_gooberando",
		"gate": "",
	},
	{
		"id": "kamera",
		"name_key": "phone.app.kamera",
		"text_key": "phone.app.kamera_text",
		"icon": "app_kamera",
		"gate": "kamera",
	},
	{
		"id": "freunde",
		"name_key": "phone.app.freunde",
		"text_key": "phone.app.freunde_text",
		"icon": "app_freunde",
		"gate": "online",
	},
	{
		"id": "goobypal",
		"name_key": "phone.app.goobypal",
		"text_key": "phone.app.goobypal_text",
		"icon": "app_goobypal",
		"gate": "online",
	},
	{
		"id": "instant",
		"name_key": "phone.app.instant",
		"text_key": "phone.app.instant_text",
		"icon": "app_instant",
		"gate": "online",
	},
]


## Alle App-Manifeste in Grid-Reihenfolge.
static func alle() -> Array[Dictionary]:
	return MANIFEST.duplicate(true)


static func ids() -> Array[String]:
	var out: Array[String] = []
	for app: Dictionary in MANIFEST:
		out.append(str(app["id"]))
	return out


static func app(id: String) -> Dictionary:
	for eintrag: Dictionary in MANIFEST:
		if str(eintrag["id"]) == id:
			return eintrag.duplicate(true)
	return {}


static func icon_pfad(id: String) -> String:
	var eintrag := app(id)
	if eintrag.is_empty():
		return ""
	return "%s/%s.svg" % [ICON_DIR, str(eintrag["icon"])]


## Ist die App benutzbar? Nur das KAMERA-Gate sperrt hart — Online-Apps
## bleiben antippbar und degradieren in ihrem eigenen UI (Doc C §3.7).
static func ist_offen(id: String, gs: Object) -> bool:
	var eintrag := app(id)
	if eintrag.is_empty():
		return false
	if str(eintrag["gate"]) == "kamera":
		return PowAngebote.hat_kamera(gs)
	return true


## Hinweis-Text-Key, warum eine App zu ist ("" = sie ist offen).
static func gesperrt_key(id: String, gs: Object) -> String:
	if ist_offen(id, gs):
		return ""
	return "phone.app.kamera_gesperrt"


## Sichtbare Apps mit Zustand: [{..manifest.., offen: bool}].
static func grid(gs: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eintrag: Dictionary in alle():
		var kopie := eintrag.duplicate(true)
		kopie["offen"] = ist_offen(str(eintrag["id"]), gs)
		out.append(kopie)
	return out
