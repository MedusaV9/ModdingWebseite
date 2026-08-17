# E6 — Deutsch-Qualität & Ton (GOOBY-GODOT)

Repo `/workspace`, Branch `cursor/gooby-godot-rewrite-d1d8`. **Keine Datei geändert** (read-only Audit).

## Prüfumfang (vollständig gelesen)

| Quelle | Umfang |
|---|---|
| `GOOBY-GODOT/strings/de.json` | 102 Z., alle Domains (`ui/hud/dialog/onboarding/settings/news`) |
| `GOOBY-GODOT/strings/de/*.json` | 11 Dateien: `album, bad, city, events, gvz, home, mg, net, social, system, updates` |
| `GOOBY-GODOT/strings/en*` | Gegenprobe für Parität (387 vs. 387 Keys) |
| `content/events/data/events.json` + `stories.json` | 6 Events, 2 Geschichten |
| `content/stickers/data/stickers.json` + `sticker_pages.json` | 105 Sticker, 18 Seiten |
| `content/codes|cosmetics|config|balance|core` | alle `*_de`-Felder |
| `scripts/city/data/dialoge/*.json` | GOOUHBUS (Arzt), GOOBYTHEKE, REHWEI |
| `scripts/city/data/*_sortiment.json`, `scripts/home/data/furniture_catalog.json` | 3 + 19 + 65 `name_de` |
| `scripts/**/*.gd` | Grep auf Umlaut-/DE-Literale, `I18nService.t()`-Keys, Fallback-Strings |
| Layout-Gegenprobe | `dialog_bubble.tscn` (600×132, Font 20), `album_screen.gd` (Card 190 px, `clip_text`), `dialog_view.gd` (Options-Stack 340 px), `ac_theme.tres` (Button 22 px) |

**Gesamturteil: gut bis sehr gut.** Die Gooby-Stimme (kindlich, Kurzsätze, Großbuchstaben-Ausbrüche, trockene Nachsätze) ist klar von der UI-Stimme (sachlich, duzend, ohne Albernheit) unterscheidbar — genau wie gewollt. Der Arzt-Dialog und GOOBERANDO sind die Textperlen. Die Mängel sind punktuell, nicht systemisch.

**Findings: P0 = 0 · P1 = 8 · P2 = 16 · P3 = 12.**

---

## P1 — Echte Fehler

### P1-1 · Grammatikfehler im Standard-Fail-Text (6× + Fallback + Test)
`content/events/data/events.json` → `items[*].fail_text_de` (Zeilen 12, 24, 37, 50, 63, 75)
`scripts/events/random_events.gd:227` (Hardcode-Fallback), `:12` (Doc-Kommentar)

> „Gooby hat es schon alleine **hingekommen** -_-“

`hinkommen` ist intransitiv — „es hinkommen“ existiert nicht. Korrekt ist `hinbekommen`/`hinkriegen`.
**Vorschlag:** „Gooby hat es schon alleine hingekriegt -_-“
*Achtung:* Der Fehler steht auch in der Spec (`docs/godot-rewrite/F-gooby.md` §4.2) und wird in `tests/unit/test_events_engine.gd:187` festgenagelt — Fix muss alle drei Orte treffen.

### P1-2 · Gemischte Anführungszeichen
`content/stickers/data/stickers.json` → `saysSuperstar.hint_de`

> `Hol 100 Punkte bei „Gooby sagt".`

Öffnend `„` (U+201E), schließend gerades `"`. Das `name_de` desselben Stickers macht es richtig (`„Gooby sagt“-Superstar`).
**Vorschlag:** `… bei „Gooby sagt“.`

### P1-3 · Ungrammatischer Satz (Anglizismus-Kalke)
`content/stickers/data/stickers.json` → `nightSkyPostcard.flavor_de`

> „**Schön wärst du hier.**“

Wörtliche Übertragung von „Wish you were here“; deutsche Wortstellung ergibt „Du wärst schön, wenn du hier wärst“.
**Vorschlag:** „Wärst du doch hier. Die Sterne finden das auch.“

### P1-4 · Sinnloser Satz (zweite Kalke)
`content/stickers/data/stickers.json` → `freshDrip.flavor_de`

> „**Neues Fell, wer ist da?**“

Übertragung von „New fur, who dis?“ — im Deutschen bedeutungslos.
**Vorschlag:** „Neues Fell. Gooby erkennt sich selbst kaum wieder.“

### P1-5 · Sticker-Hinweis nennt ein Minispiel, das es nicht gibt
`content/stickers/data/stickers.json` → `carrotChampion.hint_de`: „Hol 60 Punkte beim **Karottenfang**.“
Das Spiel heißt im UI aber `mg.carrotCatch.title` = **„Möhrenfang“** (`strings/de/mg.json`).
Der Hinweis schickt Kinder auf die Suche nach einem Namen, der nirgends auf dem Bildschirm steht.
**Vorschlag:** „Hol 60 Punkte beim Möhrenfang.“ (Name auch in `carrotChampion.name_de` „Karotten-Champion“ → „Möhren-Champion“, s. P2-6.)

### P1-6 · Genus-Widerspruch „Arcade“
`strings/de.json` → `news.items[4].text`: „**Das** Arcade ist zurück …“
`strings/de/mg.json` → `mg.results.back`: „**Zur** Arcade“ (= *die* Arcade); ebenso `scripts/minigames/minigame_host.gd:63`.
Zwei Genera für denselben Ort im selben Build.
**Vorschlag:** „**Die** Arcade ist zurück — mit Goobys vs Zombies und weiteren Minispielen.“

### P1-7 · Vier identische Regler, drei abweichende deutsche Namen
Dieselben Morph-Ids (`eyes_apart`, `eye_scale`, `ear_len`, `chubby`) werden an zwei Stellen beschriftet:
`scripts/ui/onboarding/onboarding_flow.gd:108` → `onboarding.slider_*` und `scripts/home/interactables/spiegel.gd:10-13` → `bad.spiegel.*`.

| Morph | Onboarding (`strings/de.json`) | Spiegel (`strings/de/bad.json`) | EN (beide) |
|---|---|---|---|
| `eyes_apart` | Augen**weite** | Augen**abstand** | Eye spacing |
| `ear_len` | **Ohren**länge | **Ohr**länge | Ear length |
| `chubby` | Pausb**äckchen** | Pausb**acken** | Chubby cheeks |

EN ist konsistent, DE nicht — also ein reiner DE-Defekt.
**Vorschlag:** überall `Augenabstand / Augengröße / Ohrenlänge / Pausbäckchen`.

### P1-8 · UI verspricht ein Feature, das es nicht gibt
`strings/de/home.json` → `build.lager_voll`: „Lager voll! **Bau dir einen Schuppen im Garten!**“
`scripts/home/home_state.gd:154` liefert `home.storageCapacity` fest = **100**; im `furniture_catalog.json` (65 Items, Kategorie `garten`: Bank, Blumen, Busch, Bäume, Topf, Grasbüschel) existiert **kein Schuppen**. Der Shed ist nur geplant (`docs/godot-rewrite/D-house.md` §2.3 / §Roadmap „Shed Level 1/2/3 — M1“).
Der Spieler bekommt eine Sackgassen-Anweisung genau in dem Moment, in dem er blockiert ist.
**Vorschlag bis der Shed da ist:** „Lager voll! Stell erst was auf oder verkauf ein Möbel.“ (EN analog: `build.lager_voll`).

---

## P2 — Ton, Länge, Konsistenz

### Längen / Clipping (mit Layout-Gegenprobe statt Bauchgefühl)

**P2-1 · Album-Sticker-Namen werden hart abgeschnitten** — `scripts/ui/album/album_screen.gd:272` setzt `label.clip_text = true`, Card ist `Vector2(190, 200)`, Band-Margin 6 px, Font 20 px → **ca. 17–18 Zeichen**. Betroffen in `content/stickers/data/stickers.json`:

| Zeichen | `id` | `name_de` |
|---|---|---|
| 23 | `nightSkyPostcard` | Sternenhimmel-Postkarte |
| 22 | `saysSuperstar` | „Gooby sagt“-Superstar |
| 20 | `surfStar` | Einkaufswagen-Surfer |
| 19 | `questScout` | Aufgaben-Pfadfinder |
| 19 | `storyTeller` | Geschichtenerzähler |
| 19 | `garten_gewaechshaus` | Gewächshaus-Gärtner |
| 19 | `garten_pause` | Wohlverdiente Pause |
| 17 (Grenzfall) | `maxFloof`, `modifierMischief`, `carrotChampion`, `bakeryPostcard`, `interiorDesigner` | — |

**Vorschläge:** Sternenhimmel-Postkarte → **„Sternenkarte“**; „Gooby sagt“-Superstar → **„Superstar“**; Einkaufswagen-Surfer → **„Wagen-Surfer“**; Aufgaben-Pfadfinder → **„Pfadfinder“**; Geschichtenerzähler → **„Erzähler“**; Gewächshaus-Gärtner → **„Gewächshaus“**; Wohlverdiente Pause → **„Verdiente Pause“**.

**P2-2 · Dialog-Option sprengt den Options-Stapel** — `scripts/city/dialog_view.gd:33-38` fixiert die VBox auf **340 px**; Button-Font 22 px → ca. 26 Zeichen. In `scripts/city/data/dialoge/gouhbus.json`:
- „Er hat ein ganzes Glas Nutella gegessen.“ = **40 Zeichen** → Button wächst auf ~470 px und bricht die Bündigkeit des Stapels (kein `clip_text`, kein `autowrap` an Buttons).
- „Sind Sie wirklich 4× Doktor?“ = 28 Zeichen (Grenzfall).
**Vorschlag:** „Er hat ein ganzes Glas Nutella gegessen.“ → **„Ein ganzes Glas Nutella.“** (24).

**P2-3 · Button-Strings > 18 Zeichen** (Kandidatenliste wie angefordert; alle in Sheets/Vollbreite-Reihen, daher Risiko mittel bis niedrig):

| Zeichen | Key | Text |
|---|---|---|
| 26 | `travel.gooberando.trinkgeld_geben` | 5 Münzen Trinkgeld geben 💛 |
| 23 | `travel.taxi.storno` | Stornieren (2 ᴳ Gebühr) |
| 22 | `events.nutella.weitermachen` | Ach, lass ihm den Spaß |
| 19 | `settings.update_suchen` | Nach Updates suchen |
| 18 | `settings.news_button` | Neu in 5.0 ansehen |

**Vorschläge:** `trinkgeld_geben` → **„Trinkgeld (5 ᴳ) 💛“**; `travel.taxi.storno` → **„Stornieren (2 ᴳ)“**; `events.nutella.weitermachen` → **„Lass ihn machen“** (auch näher an der Spec).

**P2-4 · Bubble-Strings > 38 Zeichen/Zeile** (angeforderte Liste — Risiko real **niedrig**: `dialog_bubble.tscn` ist 600 px breit mit `autowrap_mode = 2`, Font 20 → ~55 Zeichen/Zeile, ~3 Zeilen sichtbar):
`events.kuehlschrank.bubble` (56) · `events.nutella.aufraeumen` (55) · `events.kuehlschrank.danke` (50) · `events.scherben.danke` (46) · `events.sockensuche.bubble` (44) · `events.teller.bubble` (43) · `events.nutella.strahlen` (43) · `events.story.kichern` (42) · `events.glas.bubble` (41) · `build.bett_quest` (40).
Die längsten Bubble-Texte sind aber die **Arzt-Dialoge**: `gouhbus.json → hallo[0]` = 111 Zeichen, `titel[0]` = 109, `diagnose[0]` = 92. Auch die passen (2–3 Zeilen), sitzen aber am Anschlag — bei jeder Verkleinerung der Bubble oder größerem Font kippen sie zuerst.

### Glossar / Terminologie

**P2-5 · Währung: „Münzen“ vs. „ᴳ“ ohne Regel.** Wort: `city.laden.coins`, `travel.confirm.preis`, `travel.abholen.overdue`, `travel.gooberando.trinkgeld_geben`, `social.pal.*`, `mg.results.coins`. Symbol: `city.laden.kaufen` `{preis} ᴳ`, `net.friends.coins`, `travel.taxi.storno`, `travel.gooberando.gebuehr`. **Vorschlag:** Regel festschreiben — Symbol nur in Preis-Chips/Buttons, Fließtext immer „Münzen“ — und `trinkgeld_geben`/`storno` (Buttons) auf `ᴳ` umstellen (löst auch P2-3).

**P2-6 · „Karotte“ vs. „Möhre“.** Möhre: `rehwei_sortiment.json` `carrot`, `mg.carrotCatch.title` „Möhrenfang“, `gvz_moehrenschuetze`, `stories.json` `moehre`, `gvz_zombiegooby` „Nur Möhren“. Karotte: `firstNom.flavor_de` „Die allererste **Karotte**“, `carrotChampion.name_de/hint_de`, `storyTeller.flavor_de` „…wurde die **Karotte** gerettet“, `kissenkoenigreich` „Krone aus **Karotten**“. **Vorschlag:** „Möhre“ als Leitbegriff (steht im Shop), „Karotte“ nur wenn der Rhythmus es braucht — die 4 Stellen oben angleichen.

**P2-7 · „Tierarzt“ vs. „Doktor“.** `drGooby.name_de` „Beim **Tierarzt**“ / `hint_de` „…zum **Tierarzt**“ vs. `stadt_doktor.hint_de` „Gehe zum **Doktor**“ — beide zählen denselben Counter `vetTrips`, und der Ort heißt im UI `city.ort.gouhbus` „Dr.Dr.Professor.Dr.Dr.GOOUHBUS“. „Tierarzt“ ist zudem inhaltlich schief: GOOUHBUS behandelt Gooby als Patient, nicht als Tier. **Vorschlag:** überall „Doktor“.

**P2-8 · Doppelter Sticker-Name.** „Großeinkäufer“ für `bigSpender` (Seite `bestFriends`) *und* `stadt_einkauf` (Seite `stadt`) — im Album stehen zwei verschiedene Sticker mit identischem Namen. **Vorschlag:** `bigSpender` → „Goldesel“ oder „3000 ausgegeben!“.

**P2-9 · „Sammler“ ist ein Name, den niemand kennt.** `gvz.end.lose_hint` = „Tipp: Sammler früh pflanzen!“ — der Pflanzenname taucht in keinem sichtbaren String auf (GvZ-UI zeigt nur Kosten-Labels `◦%d`); im Doc heißt sie „Nutella-Sammler-Gooby“. **Vorschlag:** „Tipp: Pflanz zuerst die Nutella-Sammler!“

### Anrede & Register

**P2-10 · Imperativ-Form uneinheitlich.** Infinitiv-Anweisungen: `dialog.weiter_hinweis` „Tippen für mehr“, `home.tuer.mash_hint` „Tippen! Tippen! Tippen!“, `bad.lampe.umlegen` „Schalter umlegen“, `bad.zahnputz.rubbel` „Rubbel die Bürste…“ (du). Du-Imperative: `events.story.hinweis` „Tippe ein Wort…“, `build.bett_quest` „Platzier dein Bett!“. Bei einer duzenden Marke sollte das Du gewinnen. **Vorschlag:** `dialog.weiter_hinweis` → **„Tipp für mehr“**, `home.tuer.mash_hint` → **„Tipp! Tipp! Tipp!“**.
Dasselbe bei Sticker-Hints: `Hol 60 Punkte…` (`carrotChampion`, `memoryMaster`, `discoGooby`) vs. `Erziele 60 Punkte…` (`teaTime`, `lanternKeeper`, `snailCourier`, `pipeDreamer`) für exakt dieselbe Mechanik (`gameBest`). Ein Verb wählen — „Hol“ ist knuffiger.

**P2-11 · „GOOBY: „Bleeeh~““ steht in der Bubble des Arztes.** `scripts/city/data/dialoge/gouhbus.json` → `diagnose.text[1]`. `dialog_view.gd:58` rendert *alle* Zeilen eines Knotens in dieselbe Bubble und zeigt keinen Sprecher-Namen an — der Spieler sieht also den Doktor sagen: `GOOBY: „Bleeeh~“`. Das bricht die Bubble-Fiktion (und ist der einzige Ort im ganzen Text mit Drehbuch-Notation). **Vorschlag:** Zeile streichen und in `hallo`/`diagnose` als Regie-Klammer wie beim Brillen-Gag lösen: „(Gooby macht „Bleeeh~“.)“

### Lokalisierungs-Lücken (deutscher Text, wo er nicht sein dürfte)

**P2-12 · Hartkodierte deutsche Fallbacks — EN-Spieler sehen Deutsch.** Vier Keys fehlen in `strings/`:
- `scripts/core/loading_veil.gd:27-34` `FALLBACK_TIPS` — **6 komplette deutsche Ladetipps** („Tipp: Ein satter Gooby hüpft höher — Kühlschrank checken!“ …), Key `veil.tips` existiert nicht.
- `scripts/core/loading_veil.gd:60` „Lädt…“, Key `veil.laedt` fehlt.
- `scripts/ui/hud_status_sheet.gd:54` „Gooby-Status“, Key `hud.sheet_titel` fehlt; `:135` „{wert} Buff“, Key `hud.sheet_buff` fehlt.
- `scripts/events/random_events.gd:227` Fail-Text-Fallback (s. P1-1).
Der Paritäts-Test greift nicht, weil die Keys gar nicht erst existieren. Die Kommentare verweisen auf `handoffs/W4P2-strings-request.md` — die Datei ist im Repo nicht vorhanden. Verstößt außerdem gegen `strings/OWNERSHIP.md` Regel 2 („Keine UI-Texte hartkodiert in `.gd`“).

**P2-13 · Stadt-Dialoge existieren nur auf Deutsch.** `scripts/city/data/dialoge/{gouhbus,goobytheke,rehwei}.json` nutzen ein blankes `"text"`/`"optionen[].text"` — weder `_de`-Suffix (wie überall sonst im Content) noch EN-Pendant. Bei `locale=en` bleiben Arzt, Apotheke und Supermarkt komplett deutsch. Das ist die einzige Bruchstelle in einer sonst 100 % paritätischen Textbasis.

### Sprachlich schwach (aber nicht falsch)

**P2-14 ·** `strings/de/events.json` → `events.kuehlschrank.bubble`: „Hilfst du mir **aufsammeln**?“ — `helfen` + nacktes Verb ohne Objekt klingt abgeschnitten. **Vorschlag:** „Hilfst du mir beim Aufsammeln?“

**P2-15 ·** `strings/de/city.json` → `travel.weg.rest`: „Er kommt in ca. {tage} **Tag(en)** zurück.“ — Klammer-Plural ist Formularsprache im Kuscheltext (das EN-Original hat dasselbe Problem: „day(s)“). **Vorschlag:** „Noch ca. {tage}× schlafen, dann ist er zurück!“

**P2-16 ·** `strings/de/updates.json` → `updates.safe_mode`: „Sicherer Modus: Updates sind vorübergehend aus — eingebaute Inhalte aktiv.“ Für die Zielgruppe zu technisch (`pack_deaktiviert` und `braucht_ipa` sind ähnlich trocken, aber unvermeidbar). **Vorschlag:** „Wir spielen kurz mit den eingebauten Sachen weiter — Updates machen gerade Pause.“

---

## P3 — Witz-Qualität & Geschmack

**Gesamteindruck Humor: stark.** Die Gags leben von genau der richtigen Technik für diese Marke — Untertreibung nach einer Katastrophe („Der Teller wollte fliegen. Er konnte nicht.“), kindliche Logik („Niesen ist nur Applaus von innen.“) und Nachsätze, die die Behauptung sofort verraten („Nichts angeknabbert. Ehrenwort.“ / „Ich räum das weg. Spurlos. Niemand wird es je erfahren.“). Nichts ist zynisch, nichts geht auf Goobys Kosten — der Ton ist durchgehend liebevoll.

**Der Arzt-Dialog (`gouhbus.json`) ist der beste Text im Projekt.** Drei Brillen gleichzeitig, „Der zählt moralisch.“, „Zunge raus! … Das ist ein Ohr. Auch gut.“, „Ich habe als Student zwei geschafft.“, der Stempel auf der eigenen Hand und der Käsebrot-Callback von 1987, der in der GOOBYTHEKE eingelöst wird (`rezept_einloesen`: „‚Käsebrot‘. Der alte Gauner.“) — das ist ein sauber gebauter Zwei-Szenen-Gag. **Nicht anfassen** (außer P2-2 und P2-11).

**GOOBERANDO trägt ebenfalls.** „Erstmal Goobyn.“ (Lieferando-Parodie), „Die Küche goobyt schon.“, der Zettel „Hab geklingelt! – G.“, „Verbeugung inklusive.“ — konsistente Mini-Marke.

Wo es flach ist:

**P3-1 · `events.kuehlschrank.bubble` ist reine Aufgabenansage.** „Der Kühlschrank ist umgekippt! Hilfst du mir aufsammeln?“ — der einzige Event-Bubble ohne Pointe. Die Spec hatte sie schon: `docs/godot-rewrite/F-gooby.md` §4.2 → **„Der war schon immer wacklig!! Frag nicht.“** Wiederherstellen (Aufforderung kann als zweite Zeile bleiben).

**P3-2 · `events.nutella.murmel` verschenkt die beste Pointe.** Aktuell: „mmmh… okay okay… ich geh ja schon…“. Spec: **„…war nicht mal meine Lieblingssorte“** — Trotz statt Gehorsam, viel goobyiger. Übernehmen.

**P3-3 · `travel.taxi.verpasst` — Pointe zündet nicht.** „Der Fahrer lässt grüßen. Wörtlich: ‚grüße‘.“ Der Meta-Witz über das Wort „grüße“ ist zu verkopft für die Zielgruppe und liest sich wie ein Tippfehler. **Vorschlag:** „Der Fahrer hat gewunken. Nicht freundlich.“

**P3-4 · `home.blocked.lava` ohne Feuer.** Spec `F-gooby.md` §6 schreibt den Button als **„🔥 BODEN IST LAVA“**; im Build ist es nacktes „BODEN IST LAVA“. Das Emoji ist hier keine Deko, es verkauft den Knopf. `home.blocked.spidergooby` („ICH BIN SPIDERGOOBY!!“) sitzt dagegen perfekt.

**P3-5 · `sockensuche` hat den Kern-Gag verloren.** Spec: die Socke hängt die ganze Zeit **an Goobys Ohr** („…oh. Da wo ich sie hingelegt hab. Logisch.“). Der Build macht daraus ein generisches Sammel-Event („Alle Socken vereint! Familientreffen!“ — nett, aber austauschbar). Wenn die Szene es hergibt: Spec-Pointe zurückholen.

**P3-6 · `maxFloof` Name und Hinweis widersprechen sich.** `name_de` „Maximal flauschig“ / `flavor_de` „Mehr Gooby zum Liebhaben.“ vs. `hint_de` „Füttere Gooby, bis er **extra rund** ist.“ Flausch ≠ Rundheit. **Vorschlag:** Hint → „Füttere Gooby, bis er maximal flauschig ist.“

**P3-7 · `news.items[3]` wechselt mitten im Satz die Person.** „**Besuch** deine Freunde, **spielt** zusammen Brettspiele — und **werft** liebevoll Tomaten.“ (du → ihr). Umgangssprachlich tolerierbar, aber holprig. **Vorschlag:** „Besuch deine Freunde, spiel mit ihnen Brettspiele — und wirf liebevoll Tomaten.“

**P3-8 · `firstSprout.flavor_de` „Du hast gegossen. Es hat's gemerkt.“** Das „Es“ hat kein Bezugswort (der Spross wurde nicht genannt). **Vorschlag:** „Du hast gegossen. Er hat's gemerkt.“

**P3-9 · Dusch-Peeks eskalieren nicht.** `bad.dusche.peek1-3`: „Ähm… ich bin noch hier drin?“ → „Das Wasser wird kalt, weißt du…“ → „Ich schrumpel schon!“ Der dritte ist der beste; der zweite bremst. **Vorschlag peek2:** „Das ist jetzt schon das dritte Mal.“ (Steigerung: verlegen → genervt → schrumpelig.)

**P3-10 · GOOBERANDO: „Nur winken“ bleibt unbeantwortet.** Für `trinkgeld_geben` gibt es `buff` („Extra-Grinsen 😁“), für `nur_winken` keine Reaktion. Ein Zweizeiler würde die Wahl erst zur Wahl machen. **Vorschlag:** „Der Liefer-Gooby winkt zurück. Etwas länger als nötig.“

**P3-11 · Siezen der NPCs — bitte beibehalten.** Der Spieler siezt Erwachsene („Sind Sie wirklich 4× Doktor?“, „Sammeln Sie Treuepunkte?“), die NPCs duzen zurück („Setz dich aufs Bänkchen“, „Nicht am Salat knabbern“, Hildes „Schatz“). Das ist kein Verstoß gegen die Duz-Regel, sondern glaubwürdige Kinderhöflichkeit — und Rehwalds Konter („Sammelst **du** Treuepunkte? Nein? Ich auch nicht, ich erfinde sie nur gern.“) macht daraus einen Gag. Unbedingt lassen.

**P3-12 · `travel.gooberando.uebergeben` könnte eine Beobachtung vertragen.** „Hier, noch warm! Verbeugung inklusive.“ ist gut; ein konkretes Bild wäre besser, weil die Verbeugung nur behauptet wird. **Vorschlag:** „Hier, noch warm! (Er verbeugt sich. Zweimal. Sicherheitshalber.)“

---

## (e) DE/EN-Paritäts-Stichprobe — 20 zufällige Keys

Verfahren: beide Locales über `I18nService`-Merge-Logik geflacht (`strings/<loc>.json` + `strings/<loc>/*.json`), `random.seed(42)`, 20 Keys gezogen, zusätzlich globaler `{platzhalter}`-Abgleich.

| # | Key | DE | EN | Urteil |
|---|---|---|---|---|
| 1 | `travel.abholen.overdue` | Er hat selbst ein Taxi genommen — das kostet 60 Münzen. | He took a taxi himself — that costs 60 coins. | ok |
| 2 | `build.bett_quest` | Platzier dein Bett! Gooby will kuscheln! | Place your bed! Gooby wants to snuggle! | ok |
| 3 | `bad.klo.gang` | Muss mal… bin gleich zurück! | Gotta go… be right back! | ok |
| 4 | `travel.ziel.space` | Weltraum | Outer Space | ok |
| 5 | `home.tuer.mash_hint` | Tippen! Tippen! Tippen! | Tap! Tap! Tap! | ok (s. P2-10) |
| 6 | `gvz.hud.wave` | WELLE {n}! | WAVE {n}! | ok |
| 7 | `gvz.end.select` | Level-Wahl | Level select | ok |
| 8 | `city.fahren.bremse` | BREMSE | BRAKE | ok |
| 9 | `travel.ziel.meadowTrip` | Blumenwiese | Flower Meadow | ok |
| 10 | `board.tomato.limit` | Nur eine Tomate pro Runde! | Only one tomato per round! | ok |
| 11 | `travel.gooberando.buff` | Extra-Grinsen 😁 — Gooby wird 2 Stunden lang langsamer müde! | Extra grin 😁 — Gooby tires more slowly for 2 hours! | ok |
| 12 | `social.pal.amount` | Betrag | Amount | ok |
| 13 | `board.setup.ready` | Bereit! | Ready! | ok |
| 14 | `social.visit.at` | Zu Besuch bei {gooby} | Visiting {gooby} | ok |
| 15 | `net.friends.list_title` | Deine Freunde | Your friends | ok |
| 16 | `bad.lampe.umlegen` | Schalter umlegen | Flip the switch | ok |
| 17 | `bad.lampe.titel` | Lichtschalter | Light switch | ok |
| 18 | `board.sunk` | Versenkt! | Sunk! | ok |
| 19 | `gvz.end.next` | Weiter › | Next › | ok |
| 20 | `gvz.hud.huge_wave` | RIESIGE WELLE {n}! | HUGE WAVE {n}! | ok |

**Ergebnis: 20/20 inhaltlich deckungsgleich, Ton in beiden Sprachen gehalten.**
Zusätzlich global geprüft:
- **387 DE-Keys / 387 EN-Keys, 0 fehlend in beide Richtungen.**
- **0 Platzhalter-Abweichungen** über alle 387 Keys (`{name}`, `{coins}`, `{tage}` … stimmen paarweise).
- 39 Keys sind in DE und EN identisch — durchweg zu Recht (Eigennamen `REHWEI`, `GOOBYTHEKE`, `IGohbie`, `GoobyPal`, `Goobys vs. Zombies`; Symbole `★ {score}`, `ᴳ {coins}`, `Lv {level}`, ASCII-Art). Kein vergessener Übersetzungsfall.

Die einzigen echten Paritätslücken liegen **außerhalb** von `strings/`: P2-12 (hartkodierte DE-Fallbacks) und P2-13 (Stadt-Dialoge DE-only).

---

## Kurzfazit

Die deutsche Textbasis ist überdurchschnittlich: eine erkennbare, warme, duzende Markenstimme; eine sauber davon getrennte, sachliche UI-Stimme; ein Humor, der Kinder ernst nimmt statt sie zu bespaßen. Die 8 P1-Punkte sind allesamt punktuelle Korrekturen (ein Grammatikfehler in 8 Dateien, zwei Anglizismus-Kalken, ein falscher Spielname, ein Genus-Widerspruch, drei divergierende Regler-Labels, ein Feature-Versprechen ohne Feature). Der größte strukturelle Hebel ist P2-12/P2-13: solange Ladetipps und Stadt-Dialoge außerhalb von `strings/` leben, ist die sonst makellose 387/387-Parität nur auf dem Papier vollständig.
