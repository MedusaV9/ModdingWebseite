class_name Stammkunden
## J3 „Läden lebendig 2“ — benannte Stammkunden: wiederkehrende Charaktere
## mit Namen, Mini-Persönlichkeit und fester Tagesroutine (Vorbild: Onkel
## Alwin im Goo-und-Bye-Laden, der jeden Markttag als Kunde 0 seine eine
## Möhre kauft). Jeder Eintrag gehört zu GENAU einem Ort und einem
## Stunden-Fenster [von, bis) — OrtLeben spawnt die Figur nur, wenn die
## (injizierbare!) Uhr im Fenster liegt. Der Tages-Seed des Orts steuert
## Startphase/Rotation, die Route selbst ist FEST (Wiedererkennung!).
##
## Sprüche: 2 Zeilen je Figur unter `city_leben.sprueche.stammkunde_<id>`,
## Namen unter `city_leben.stammkunden.<id>` (DE führend, EN paritätisch).
## Alles PURE Statics — headless testbar ohne Szenenbaum.

## Katalog aller Stammkunden. Felder je Eintrag:
##   id           Kurz-Id (Spruch-Domain + Node-Name)
##   ort          ort_id der OrtLeben-Konfig (rehwei, baumarkt, funkelpark …)
##   von/bis      Stunden-Fenster [von, bis) der Anwesenheit
##   tint         Fellfarbe (Wiedererkennung, bewusst ≠ Besucher-Palette)
##   hut          Hutfarbe (jeder Stammkunde trägt seinen Hut)
##   tempo        Schlender-Tempo in m/s (Rollo skatet, Opa Hatschi schlurft)
##   greift       true = greift/schnuppert an den Regalen (Pausen-Geste)
##   koffer       true = Rollkoffer-Gepäck (Frau Fernweh am Flughafen)
##   punkte       FESTE Wegpunkt-Schleife im Ort (kein Jitter)
##   blick        Blickziel in den Schau-Pausen
const KATALOG: Array[Dictionary] = [
	{
		"id": "rosine",
		"ort": "rehwei",
		"von": 8,
		"bis": 12,
		"tint": Color("#C48BB4"),
		"hut": Color("#8E4C86"),
		"tempo": 0.5,
		"greift": true,
		"koffer": false,
		"punkte": [Vector3(-3.3, 0.0, -0.5), Vector3(-2.4, 0.0, -0.3), Vector3(-4.0, 0.0, 0.4)],
		"blick": Vector3(-3.2, 0.0, -1.5),
	},
	{
		"id": "hatschi",
		"ort": "goobytheke",
		"von": 9,
		"bis": 11,
		"tint": Color("#A8C0B0"),
		"hut": Color("#5B7C8C"),
		"tempo": 0.4,
		"greift": false,
		"koffer": false,
		"punkte": [Vector3(-1.4, 0.0, -0.4), Vector3(0.9, 0.0, 0.6), Vector3(-2.9, 0.0, -1.9)],
		"blick": Vector3(0.0, 0.0, -2.2),
	},
	{
		"id": "fernweh",
		"ort": "flughafen",
		"von": 11,
		"bis": 16,
		"tint": Color("#E8A34C"),
		"hut": Color("#4E79D6"),
		"tempo": 0.55,
		"greift": false,
		"koffer": true,
		"punkte": [Vector3(-2.4, 0.0, 1.4), Vector3(1.6, 0.0, 0.6), Vector3(-0.6, 0.0, 2.0)],
		"blick": Vector3(2.6, 0.0, -3.4),
	},
	{
		"id": "duebel",
		"ort": "baumarkt",
		"von": 15,
		"bis": 18,
		"tint": Color("#8FA8C8"),
		"hut": Color("#F2A03D"),
		"tempo": 0.62,
		"greift": true,
		"koffer": false,
		"punkte": [Vector3(-2.6, 0.0, -2.0), Vector3(2.6, 0.0, -2.2), Vector3(3.8, 0.0, 0.9)],
		"blick": Vector3(0.0, 0.0, -4.0),
	},
	{
		"id": "rollo",
		"ort": "funkelpark",
		"von": 14,
		"bis": 18,
		"tint": Color("#8FD06C"),
		"hut": Color("#3E8E5A"),
		"tempo": 1.25,
		"greift": false,
		"koffer": false,
		"punkte": [Vector3(8.0, 0.0, 13.0), Vector3(10.5, 0.0, 9.0), Vector3(5.5, 0.0, 8.5)],
		"blick": Vector3(0.0, 0.0, 0.0),
	},
]


## Alle Stammkunden, die JETZT (Stunde) an diesem Ort sind (PURE).
static func fuer_ort(ort_id: String, stunde: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eintrag in KATALOG:
		if str(eintrag["ort"]) != ort_id:
			continue
		if stunde >= float(eintrag["von"]) and stunde < float(eintrag["bis"]):
			out.append(eintrag)
	return out


## Anzeigename (Namensschild) aus den Strings.
static func anzeigename(eintrag: Dictionary) -> String:
	return I18nService.t("city_leben.stammkunden.%s" % str(eintrag["id"]))


## Spruch-Domain der Figur (Rotation über OrtLeben.naechster_spruch).
static func spruch_domain(eintrag: Dictionary) -> String:
	return "stammkunde_%s" % str(eintrag["id"])
