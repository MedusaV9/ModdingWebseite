class_name GoobymanKatalog
extends RefCounted
## GOOBYMAN-Sortiment + Kauf-Effekte (W13C GOOBYMAN, Doc H §6.4): der
## Drogerie-Laden der Stadt (Wortspiel auf Rossmann). Warenliste kommt wie
## bei REHWEI aus einem Daten-JSON (goobyman_sortiment.json) — zusätzlich
## remote-config-fähig übers bestehende Pack-System: liefert ein Pack die
## Domain "goobyman" (content/<pack>/data/goobyman.json mit items[]),
## gewinnt sie über die eingebaute Datei (Muster StoryBooks/books).
##
## Kategorien: zahnbuerste (inventory.items, Haltbarkeit s. ZahnbuersteState),
## pflaster (Sofort-Wirkung: −heilt Gesundheits-Druckpunkte junkScore,
## Cap 1/Tag — Tag wird IMMER hereingereicht), einmalig (Schlafmaske: kauft
## man genau einmal, +10 % schnelleres Einschlafen in der Geschichten-Stunde).
## Eigener Save-Slice "goobyman": {pflasterTag}.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const PFAD := "res://scripts/city/data/goobyman_sortiment.json"
const DOMAIN := "goobyman"
const SLICE_ID := "goobyman"

const KATEGORIE_ZAHNBUERSTE := "zahnbuerste"
const KATEGORIE_PFLASTER := "pflaster"
const KATEGORIE_EINMALIG := "einmalig"

## Ab so vielen Artikeln in EINEM Einkauf wirft der Verkäufer den
## GOOBYMAN-Umhang-Gag ein (Doc H §6.4).
const UMHANG_GAG_AB := 5

## Schlafmaske: 10 % weniger Vorlese-Wörter bis zum Einschlafen.
const SCHLAFMASKE_ITEM := "schlafmaske"
const SCHLAFMASKE_FAKTOR := 0.9

static var _registered := false


## Idempotent — Muster BadState/StoryBooks.
static func register_slice() -> void:
	if _registered:
		return
	_registered = true
	SaveSchema.register_slice(SLICE_ID, default_slice, normalize_slice)


static func default_slice() -> Dictionary:
	return {"pflasterTag": ""}


static func normalize_slice(raw: Variant) -> Dictionary:
	var slice: Dictionary = raw if raw is Dictionary else default_slice()
	slice["pflasterTag"] = str(slice.get("pflasterTag", ""))
	return slice


## Nur für Tests.
static func reset_for_tests() -> void:
	_registered = false


# ── Sortiment ────────────────────────────────────────────────────────────────


## Warenliste: Pack-Domain "goobyman" gewinnt (Remote-Update ohne .ipa),
## sonst die eingebaute JSON (Muster rehwei_sortiment.json/CitySortiment).
static func waren() -> Array:
	var aus_pack := _waren_aus_registry()
	if not aus_pack.is_empty():
		return aus_pack
	return CitySortiment.laden(PFAD)


static func ware(liste: Array, id: String) -> Dictionary:
	return CitySortiment.ware(liste, id)


static func nach_kategorie(liste: Array, kategorie: String) -> Array:
	var out: Array = []
	for eintrag: Variant in liste:
		if eintrag is Dictionary and str(eintrag.get("kategorie", "")) == kategorie:
			out.append(eintrag)
	return out


# ── Umhang-Gag (pure) ────────────────────────────────────────────────────────


## 5+ Artikel in einem Besuch → Superhelden-Einlage (Latch macht das Sheet).
static func umhang_gag_faellig(im_besuch_gekauft: int) -> bool:
	return im_besuch_gekauft >= UMHANG_GAG_AB


# ── Pflaster (Sofort-Heilung, Cap 1/Tag — Tag injiziert) ─────────────────────


## Darf heute noch ein Pflaster wirken? `tag` = Clock.local_day().
static func pflaster_frei(state: Dictionary, tag: String) -> bool:
	return tag.is_empty() or str(normalize_slice(state.get(SLICE_ID)).get("pflasterTag")) != tag


## Pflaster anwenden: nimmt `heilt` Gesundheits-Druckpunkte (junkScore im
## gooby.health-Slice, Boden 0) und latcht den Tag. false = heute schon
## verarztet (Cap 1/Tag). Münzen zieht der Aufrufer (GoobymanSheet) ab.
static func pflaster_anwenden(gs: Object, eintrag: Dictionary, tag: String) -> bool:
	var ok := {"ok": false}
	gs.update(
		func(state: Dictionary) -> void:
			if not pflaster_frei(state, tag):
				return
			var slice := _ensure(state)
			slice["pflasterTag"] = tag
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and gooby.get("health") is Dictionary:
				var health: Dictionary = gooby["health"]
				var heilt := maxf(0.0, float(eintrag.get("heilt", 5)))
				health["junkScore"] = maxf(0.0, _num(health.get("junkScore")) - heilt)
			ok["ok"] = true
	)
	if ok["ok"]:
		gs.notify_slice_changed(SLICE_ID)
		gs.notify_slice_changed("gooby")
	return ok["ok"]


# ── Schlafmaske (einmalig, dockt an StoryBooks.needed_words an) ──────────────


static func schlafmaske_gekauft(state: Dictionary) -> bool:
	var inventory: Variant = state.get("inventory")
	if inventory is Dictionary and inventory.get("items") is Dictionary:
		return int(inventory["items"].get(SCHLAFMASKE_ITEM, 0)) > 0
	return false


## +10 % schnelleres Einschlafen: 10 % weniger benötigte Vorlese-Wörter
## (Boden StoryBooks.WORDS_MIN). Ohne Maske unverändert — die Verdrahtung
## in story_time.gd läuft per Request (W13-requests.md, Tag GOOBYMAN).
static func schlafmaske_woerter(basis: int, maske_gekauft: bool) -> int:
	if not maske_gekauft:
		return basis
	return maxi(StoryBooks.WORDS_MIN, int(floorf(float(basis) * SCHLAFMASKE_FAKTOR)))


static func _waren_aus_registry() -> Array:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return []
	var registry := (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	if registry == null or not registry.has_method("get_items"):
		return []
	return registry.get_items(DOMAIN)


static func _ensure(state: Dictionary) -> Dictionary:
	state[SLICE_ID] = normalize_slice(state.get(SLICE_ID))
	return state[SLICE_ID]


static func _num(value: Variant) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return 0.0
