class_name RanchAudio
extends Node
## RW-8 — Der Klang der Ranch: EINE Anlaufstelle für Hufschlag je Untergrund,
## Pferde-Reaktionen (Begrüßung/Bindung/Erschöpfung), Pflege-Foley,
## Ambience-Loops je Zone/Wetter/Tageszeit (weiche Übergänge, Lautstärke nach
## Entfernung) und Turnier-Fanfare + Publikum. One-Shots laufen über den
## AudioDirector (SfxMap-Ids `ranch_*`), Loops über eigene Player auf dem
## bestehenden Sfx-Bus — KEINE neuen Busse, Lautstärkeregler greifen weiter.
##
## Verdrahtung ist DEFENSIV (RW-1/RW-2 laufen parallel): der Knoten hängt
## sich an SceneRouter.travel_finished, verbindet auf Ranch-Zielen die
## Szenen-Signale `zone_gewechselt` (Region), `wetter_changed` (Kind
## "Wetter") und die Reiter-Signale (`erschoepft`/`gescheut`/
## `zweiter_wind_genutzt`), wenn es sie gibt — fehlt etwas, bleibt alles
## still statt zu crashen. Musik: Ranch-Ziele setzen die MusicRegistry-
## Kontexte ranch/ranch_reiten/ranch_turnier/ranch_nacht über den
## bestehenden MusicDirector (Crossfade inklusive — kein zweites System).
##
## Die Mix-Mathematik (ambience_ziel, huf_id_fuer, musik_kontext_fuer, …)
## ist PURE und im Runner testbar. Headless-sicher: ohne Baum springen
## Fades sofort ans Ziel, der Dummy-Treiber spielt still.

const NODE_NAME := "RanchAudio"
## Weiche Ambience-Übergänge (Wetter-/Zonenwechsel).
const AMBIENCE_FADE_S := 2.5
const STILLE_DB := -60.0
## Ambience-Ebenen — Ids: "ranch_ambience_<ebene>" (+ Publikum "menge").
const AMBIENCE_EBENEN: Array[String] = ["wind", "regen", "gewitter", "voegel", "grillen", "bach"]
## Hörweite des Bachs bzw. des Publikums in Metern (linearer Falloff).
const HOERWEITE_BACH := 60.0
const HOERWEITE_MENGE := 40.0
## Nachtfenster für Grillen/Vögel und die Nacht-Musik.
const NACHT_AB := 20.0
const NACHT_BIS := 6.0

## Untergrund-Id (RW-2 ride_feel.UNTERGRUND) → Hufschlag-Sound-Id.
const HUF_IDS := {
	"gras": "ranch_huf_gras",
	"wiese": "ranch_huf_gras",
	"matsch": "ranch_huf_gras",
	"sand": "ranch_huf_sand",
	"holz": "ranch_huf_holz",
	"stein": "ranch_huf_stein",
}

## Reaktions-Art → Pferdelaut (Wiehern = laut/sozial, Schnauben = leise/Körper).
const REAKTION_IDS := {
	"begruessung": "ranch_wiehern_a",
	"freude": "ranch_wiehern_b",
	"scheu": "ranch_wiehern_b",
	"bindung": "ranch_schnauben_a",
	"zweiter_wind": "ranch_schnauben_a",
	"erschoepfung": "ranch_schnauben_b",
}

## Pflege-Aktion → Foley.
const PFLEGE_IDS := {
	"buersten": "ranch_buerste",
	"striegeln": "ranch_buerste",
	"heu": "ranch_heu",
	"futter": "ranch_heu",
	"sattel": "ranch_sattel",
	"aufsteigen": "ranch_sattel",
}

static var _fallback: RanchAudio

## Tests/Screenshots: feste Tageszeit (-1 = Systemzeit).
var stunde_override := -1.0

var _zone := "hof"
var _wetter: Dictionary = {}
var _ebenen_player: Dictionary = {}
var _ebenen_ziel: Dictionary = {}
var _ebenen_tween: Dictionary = {}


## Autoload-frei nutzbar (Muster AudioDirector): /root/RanchAudio bevorzugt,
## sonst lazy-Instanz unter /root.
static func get_or_create(from: Node) -> RanchAudio:
	var existing := from.get_node_or_null("/root/%s" % NODE_NAME)
	if existing is RanchAudio:
		return existing
	if _fallback != null and is_instance_valid(_fallback):
		return _fallback
	var node := RanchAudio.new()
	node.name = NODE_NAME
	_fallback = node
	from.get_tree().root.add_child.call_deferred(node)
	return node


# ── PURE: Zuordnungen + Mix-Mathematik (Runner-testbar) ──────────────────────


## Untergrund → Hufschlag-Id; unbekannter Boden fällt weich auf Gras zurück.
static func huf_id_fuer(untergrund: String) -> String:
	return str(HUF_IDS.get(untergrund, "ranch_huf_gras"))


## Gangart → Huf-Loop ("" = kein Loop, Einzelschritte nehmen huf_id_fuer).
static func huf_loop_id_fuer(gangart: String) -> String:
	match gangart:
		"trab":
			return "ranch_huf_trab"
		"galopp":
			return "ranch_huf_galopp"
		_:
			return ""


## Reaktions-Art → Pferdelaut ("" = unbekannt, kein Ton).
static func reaktion_id(art: String) -> String:
	return str(REAKTION_IDS.get(art, ""))


## Pflege-Aktion → Foley-Id ("" = unbekannt).
static func pflege_id(aktion: String) -> String:
	return str(PFLEGE_IDS.get(aktion, ""))


## Linearer Lautstärke-Falloff nach Entfernung (1 = dran, 0 = außer Hörweite).
static func entfernung_gain(entfernung: float, hoerweite: float) -> float:
	if hoerweite <= 0.0:
		return 0.0
	return clampf(1.0 - maxf(entfernung, 0.0) / hoerweite, 0.0, 1.0)


static func ist_nacht(stunde: float) -> bool:
	return stunde >= NACHT_AB or stunde < NACHT_BIS


## DER Ambience-Mix: Ziel-Gains (0..1) je Ebene für Zone/Wetter/Tageszeit.
## wetter = RanchWetter.zustand()-Dictionary ({typ, intensitaet, wind, …});
## wasser_entfernung >= 0 steuert den Bach nach Metern, sonst nach Zone.
static func ambience_ziel(
	zone: String, wetter: Dictionary, stunde: float, wasser_entfernung := -1.0
) -> Dictionary:
	var typ := str(wetter.get("typ", "sonne"))
	var intensitaet := clampf(float(wetter.get("intensitaet", 0.5)), 0.0, 1.0)
	var wind_staerke := clampf(float(wetter.get("wind", 0.3)), 0.0, 1.0)
	var nacht := ist_nacht(stunde)
	var regen := 0.0
	match typ:
		"niesel":
			regen = 0.35 + 0.3 * intensitaet
		"regen":
			regen = 0.6 + 0.3 * intensitaet
		"gewitter":
			regen = 0.8 + 0.2 * intensitaet
	var wind := 0.2 + 0.5 * wind_staerke
	if zone == "huegelkamm":
		wind += 0.2
	var voegel := 0.0
	if not nacht and regen <= 0.0 and typ != "nebel":
		voegel = 0.75 if zone == "waeldchen" or zone == "weidetal" else 0.55
	elif not nacht and typ == "nebel":
		voegel = 0.2
	var grillen := 0.0
	if nacht and regen <= 0.0:
		grillen = 0.65
	var bach := 0.0
	if wasser_entfernung >= 0.0:
		bach = 0.85 * entfernung_gain(wasser_entfernung, HOERWEITE_BACH)
	elif zone == "bachlauf":
		bach = 0.85
	elif zone == "see":
		bach = 0.7
	return {
		"wind": clampf(wind, 0.0, 1.0),
		"regen": clampf(regen, 0.0, 1.0),
		"gewitter": 0.9 if typ == "gewitter" else 0.0,
		"voegel": clampf(voegel, 0.0, 1.0),
		"grillen": clampf(grillen, 0.0, 1.0),
		"bach": clampf(bach, 0.0, 1.0),
	}


## Reiseziel + Tageszeit → Musik-Kontext der MusicRegistry ("" = kein Ranch-
## Ziel, Musik bleibt wie sie ist). Turnier schlägt Nacht schlägt Reiten.
static func musik_kontext_fuer(ziel: String, stunde: float) -> String:
	if not ziel.begins_with("ranch/"):
		return ""
	if ziel.contains("turnier"):
		return "ranch_turnier"
	if ist_nacht(stunde):
		return "ranch_nacht"
	if ziel == "ranch/welt" or ziel == "ranch/fahrt":
		return "ranch_reiten"
	return "ranch"


# ── One-Shots (über AudioDirector/SfxMap, Sfx-Bus) ───────────────────────────


## Einzelner Hufschlag passend zum Untergrund (Gras/Sand/Holz/Stein).
func huf(untergrund: String, pitch := 1.0) -> void:
	AudioDirector.try_play(self, huf_id_fuer(untergrund), pitch)


## Pferde-Reaktion (begruessung/freude/bindung/erschoepfung/scheu/…).
func reaktion(art: String) -> void:
	var id := reaktion_id(art)
	if not id.is_empty():
		AudioDirector.try_play(self, id)


## Pflege-Geräusch (buersten/heu/sattel/…).
func pflege(aktion: String) -> void:
	var id := pflege_id(aktion)
	if not id.is_empty():
		AudioDirector.try_play(self, id)


## Turnier-Fanfare; sieg=true nimmt die große Sieg-Fanfare + Jubel.
func fanfare(sieg := false) -> void:
	AudioDirector.try_play(self, "ranch_fanfare_sieg" if sieg else "ranch_fanfare")
	if sieg:
		AudioDirector.try_play(self, "ranch_menge_jubel")


# ── Ambience-Loops (eigene Player auf dem Sfx-Bus, weiche Fades) ─────────────


## Ambience auf Zone/Wetter/Tageszeit einstellen (weiche 2,5-s-Übergänge).
func ambience_anwenden(zone: String, wetter: Dictionary, stunde: float, wasser := -1.0) -> void:
	_zone = zone
	_wetter = wetter
	var ziele := ambience_ziel(zone, wetter, stunde, wasser)
	for ebene: String in AMBIENCE_EBENEN:
		_fahre_ebene(ebene, "ranch_ambience_%s" % ebene, float(ziele.get(ebene, 0.0)))


## Alle Ambience-Ebenen (inkl. Publikum) ausblenden.
func ambience_stop() -> void:
	for ebene: String in _ebenen_player.keys():
		_fahre_ebene(ebene, "", 0.0)


## Publikums-Gemurmel am Turnierplatz an/aus, Lautstärke nach Entfernung.
func publikum_loop(an: bool, entfernung := 0.0) -> void:
	var gain := entfernung_gain(entfernung, HOERWEITE_MENGE) if an else 0.0
	_fahre_ebene("menge", "ranch_menge_gemurmel", gain)


# ── Defensive Verdrahtung (SceneRouter + Szenen-Signale) ─────────────────────


func _ready() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_signal("travel_finished"):
		router.travel_finished.connect(_on_travel_finished)


func _on_travel_finished(target: StringName) -> void:
	var ziel := String(target)
	if not ziel.begins_with("ranch/"):
		ambience_stop()
		return
	var stunde := _aktuelle_stunde()
	var kontext := musik_kontext_fuer(ziel, stunde)
	if not kontext.is_empty():
		MusicDirector.get_or_create(self).set_context(kontext)
	_zone = "hof"
	_verbinde_szene()
	ambience_anwenden(_zone, _wetter, stunde)


## Szenen-Signale defensiv anschließen (fehlt eines, passiert nichts).
func _verbinde_szene() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("get_current_scene"):
		return
	var szene: Node = router.get_current_scene()
	if szene == null:
		return
	_verbinde(szene, "zone_gewechselt", _on_zone_gewechselt)
	var wetter := szene.get_node_or_null("Wetter")
	if wetter != null:
		_verbinde(wetter, "wetter_changed", _on_wetter_changed)
	var reiter := _finde_mit_signal(szene, "erschoepft")
	if reiter != null:
		_verbinde(reiter, "erschoepft", reaktion.bind("erschoepfung"))
		_verbinde(reiter, "gescheut", reaktion.bind("scheu"))
		_verbinde(reiter, "zweiter_wind_genutzt", _on_zweiter_wind)


func _verbinde(quelle: Node, signal_name: String, ziel: Callable) -> void:
	if not quelle.has_signal(signal_name):
		return
	if quelle.is_connected(signal_name, ziel):
		return
	quelle.connect(signal_name, ziel)


## Breitensuche mit Deckel — Szenen können tausende Knoten haben.
func _finde_mit_signal(wurzel: Node, signal_name: String) -> Node:
	var offen: Array[Node] = [wurzel]
	var besucht := 0
	while not offen.is_empty() and besucht < 400:
		var knoten: Node = offen.pop_front()
		besucht += 1
		if knoten.has_signal(signal_name):
			return knoten
		for kind in knoten.get_children():
			offen.append(kind)
	return null


func _on_zone_gewechselt(zone_id: String) -> void:
	ambience_anwenden(zone_id, _wetter, _aktuelle_stunde())


func _on_wetter_changed(zustand: Dictionary) -> void:
	ambience_anwenden(_zone, zustand, _aktuelle_stunde())


func _on_zweiter_wind(_bonus: float) -> void:
	reaktion("zweiter_wind")


func _aktuelle_stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	return LoadingScreenRules.aktuelle_stunde()


## Eine Loop-Ebene mit weichem Fade auf ihren Ziel-Gain fahren.
func _fahre_ebene(ebene: String, sfx_id: String, gain: float) -> void:
	_ebenen_ziel[ebene] = gain
	var player: AudioStreamPlayer = _ebenen_player.get(ebene)
	if gain <= 0.0:
		if player != null and player.playing:
			_fade_player(ebene, player, STILLE_DB, true)
		return
	if player == null:
		player = _erzeuge_player(sfx_id)
		if player == null:
			return
		_ebenen_player[ebene] = player
	if not player.playing:
		player.volume_db = STILLE_DB
		player.play()
	var basis := float(SfxMap.entry(sfx_id).get("volume_db", 0.0))
	_fade_player(ebene, player, basis + linear_to_db(maxf(gain, 0.001)), false)


func _erzeuge_player(sfx_id: String) -> AudioStreamPlayer:
	var pfad := SfxMap.path(sfx_id)
	if pfad.is_empty() or not ResourceLoader.exists(pfad):
		push_warning("[ranch-audio] Ambience-Datei fehlt: %s (%s)" % [sfx_id, pfad])
		return null
	var stream: AudioStream = load(pfad)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.bus = &"Sfx"
	player.stream = stream
	add_child(player)
	return player


func _fade_player(ebene: String, player: AudioStreamPlayer, ziel_db: float, stopp: bool) -> void:
	var alt: Variant = _ebenen_tween.get(ebene)
	if alt is Tween and (alt as Tween).is_valid():
		(alt as Tween).kill()
	if not is_inside_tree():
		player.volume_db = ziel_db
		if stopp:
			player.stop()
		return
	var tween := create_tween()
	_ebenen_tween[ebene] = tween
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(player, "volume_db", ziel_db, AMBIENCE_FADE_S)
	if stopp:
		tween.tween_callback(player.stop)
