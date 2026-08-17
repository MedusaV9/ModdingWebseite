# Gooby Mod

**GOOBY** — ein dicker, großer, niedlicher Hase (ca. 1,4 Blöcke hoch, kugelrund), der IMMER
lächelt, freundlich ist und die ganze Zeit gestreichelt werden will. Seit 4.3
„Schatzsucher" ist Gooby ein vollwertiger Abenteuerbegleiter; auf 5.1.0
„Interaktions-Politur" folgt 5.2.0 „Begleiter-Deluxe" mit Apportieren,
Explorer-Outfit, Begleiter-HUD, sechs Kunststücken und Premium-Fellen.

- **Mod-Id:** `goobymod` · **Version:** 5.2.0 · **Autor:** made by Sonic0810
- **Minecraft:** 1.21.1 · **Loader:** NeoForge 21.1.x · **Benötigt:** GeckoLib 4.9+
- **Optional:** Create 6.0.10+ (typisierte Sitz-, Konstruktions- und Kinetik-Integration;
  ohne Create bleiben alle Pfade vollständig inaktiv)
- **Optional:** Curios 9.5.1+ (die Gooby-Pfeife passt datengetrieben in den Charm-Slot)

## Wie bekomme ich einen Gooby?

### Weg 1: Wildhase + Nutella

1. **Nutella craften:** 3× Kakaobohnen + 1× Milcheimer + 1× Zucker (formlos, Eimer kommt zurück).
2. Einem **Wildhasen** das Nutella-Glas geben (Rechtsklick).
3. Magischer Moment: Wirbel-Partikel, *Plop!* — GOOBY ist da, **gezähmt und dir treu**!

### Weg 2: Für hasenlose Gegenden

1. Nutella-Glas auf einen **Grasblock** stellen.
2. Nachts hoppelt ein **wilder** Gooby heran und schleckt das Glas leer.
   (Jedes Glas ruft genau EINEN Gooby — es wird beim Losschicken reserviert.)
3. Wilde Goobys zähmst du, indem du ihnen ein Nutella-Glas fütterst.

## Begleiter-Deluxe (5.2)

- **Apportieren:** Der Gooby-Ball (Schleimball + Faden + Fussel) lässt sich
  werfen; dein erwachsener Gooby bringt GENAU deinen Ball zurück — verlustfrei
  über Chunk- und Server-Reloads. Unerreichbare Bälle werden kurz gemieden
  statt endlos angelaufen.
- **Sechs Kunststücke & nativer Trick-Bildschirm:** Rolle und Tanz ergänzen
  Drehung, Pfötchen, Flauf und Sprich. Der Schleich-Luftpfiff öffnet einen
  echten Auswahlbildschirm (Maus/Tastatur/Narrator) mit serverseitig
  autorisierter Auswahl bis 64 Blöcke; Clients ohne Payload-Kanal behalten
  das Chat-Menü.
- **Begleiter-HUD, Screen-FX & Config-Bildschirm:** kompakte Begleiter-Karte
  (Name, Stimmung, Kommando, Balken), Kuschel-Vignette, Alarm-Puls und
  sanfter Kamera-Shake — alles einzeln abschaltbar und Reduced-Motion-treu.
  Der neue Config-Bildschirm bietet Live-Vorschau und atomares Speichern.
- **Explorer-Outfit & eigene Partikel:** Blumenkranz, färbbares
  Abenteuer-Halstuch und Picknick-Rucksack über den serverautoritativen
  Garderobenpfad; Konfetti-, Flausch- und Notenpartikel aus eigenen,
  deterministisch generierten Sheets.
- **Deko & Snacks:** Nutella-Toast (Schnelligkeitsschub), Knopfauge,
  knuddelbares Gooby-Plüschtier (dämpft Landungen) und nachts funkelnde
  Gooby-Statue.
- **Welt:** Gooby-Baue expandieren als echtes Jigsaw (Tunnel, Kammern,
  Vorratskammer), dazu die neue oberirdische Picknick-Begegnung in Ebenen,
  Wiesen, Blumenwäldern und Kirschhainen.
- **Bewegung & Optik:** deterministische Walk/Run-Gangarten mit Hysterese für
  Adult und Baby; alle fünf Entity-Felle als Premium-Texturen direkt aus den
  Runtime-Geometrien gemalt.
- **Stimme:** 91 deterministische Audio-Clips mit Drei-Varianten-Pools und
  fail-closed Audio-Gate (Manifest, Container, Lautheit).
- **Sichere Garderobe:** volle ItemStack-Persistenz inkl. DataComponents;
  Fremd-Mod-Accessoires überleben das Fehlen ihres Mods unangetastet.

## Hochglanz-LTS (5.0)

- 5.0.2 härtet alle transienten Spieler-/Partner-Caches zusätzlich mit festen
  Obergrenzen und Logout-Cleanup, begrenzt synchronisierte Strings und leert
  den statischen Soundlimiter beim Serverstopp.
- Die Sozial-KI wählt Fangspiele nun im normalen Goal-Pfad und bleibt während
  der Aktion aktiv; Hasen drosseln ihre Wild-Gooby-Suche auf einmal pro Sekunde.
- Alle zwölf normalen Rezepte erscheinen über Material-Unlocks im Rezeptbuch.
  Neue DE+EN-Tooltips erklären die wichtigsten Progressionsitems.
- Handbuch 2.0: acht illustrierte Kapitel, animiertes Titel-Gooby, direkte
  Reiter und vollständige DE+EN-Texte; der Buch-Fallback umfasst 16 Seiten.
- Barrierefreiheit: lokale Reduced-Motion- und High-Contrast-Bubble-Optionen,
  vollständige Untertitel und eindeutige Actionbar-Symbole für alle Pfeifmodi.
- Leistung: Mikroanimationen/Pfoten pausieren außerhalb 24 Blöcken bzw. ohne
  Render, periodische Gruppenstimmen werden pro Chunk gebündelt und höchstens
  32 Nicht-Besitzer-Freundschaften plus Besitzer bleiben im LRU-Speicher.
- Addon-API: stabil für die gesamte 5.x-Reihe mit `GoobyAccessor`, Zähm-,
  Freundschaftsstufen- und Geschenk-Events, öffentlichem Hut-Tag und
  registrierbaren lokalisierten Sprachpools. [API-Dokumentation](docs/ADDON_API.md)
- Finale Sprach-/Assetrunde: jeder eingebaute Sprechpool hat mindestens vier
  eigenständige Lines; zwölf Handbuchillustrationen und ein reproduzierbarer
  [Showcase-Weltbauplan](docs/demo_world/README.md) sind enthalten.

## Schatzsucher (4.3)

- Die Winzige Tasche besitzt vier besitzergebundene Slots. Benutze eine
  ausgerüstete Tasche erneut am eigenen Gooby; Inhalt bleibt in NBT erhalten
  und fällt bei erzwungenem Tod oder Ablegen sicher heraus.
- Für „Schnüffel & Such“ zeigst du deinem Freund-Gooby schleichend eine
  Karotte oder einen gemütlichen Block und hältst in der anderen Hand einen
  Trainingshappen. Gooby sucht einmalig 24 Blöcke weit, markiert den Fund und
  wartet danach fünf Minuten. `seek.allowOres` ist standardmäßig aus.
- Ferne Buddelgeschenke landen atomar in der Tasche; Welt-Drops gehören zehn
  Sekunden dem vorgesehenen Empfänger. Beste Freunde finden selten
  Kartenfetzen. Vier ergeben eine Karte zum nächsten Gooby-Schatzversteck.
- Neue Tasche-GUI, drei Schatz-Animationen, Pfotenspur, zwei Sounds,
  Schatz-Loot sowie „Flausch am X“ und „Liebevoll gepackt“.

## Soziale Goobys (4.2)

- Niedrig priorisierte Begrüßung, 30-Sekunden-Fangspiel mit 5-Minuten-
  Paarcooldown, kosmetischer Geschenkaustausch und Schlafkuscheln. Kommandos,
  Gefahr, Folgen, Schutz und Schlaf gewinnen immer.
- Zweimaliges Schleich-Drücken in einer Sekunde beim Ansehen wird mit einer
  Verbeugung beantwortet; drei Sprünge beim glücklichen Gooby lösen Mit-Hüpfen aus.
- Drei nahe Schläfer verleihen „Flauschhaufen" und teilen einen großen Zzz-
  Marker. Benannte Flauschfreunde erscheinen in acht Sozialblasen.
- Bubble v2: Entity-Staffelung gegen Überlappung, weiches Ein-/Ausblenden,
  gerichteter Schwanz und scharfer Icon-Font für Herz/Nutella/Schlaf/Alarm.
- Server-Schalter: `social.playChase` und `social.emoteReactions`.

## Wilde Welt (4.1)

- Sehr seltene Einzelspawns in Blumenwald, Kirschhain und Wiese über
  `#goobymod:has_wild_goobys`; per `worldgen.wildSpawns` abschaltbar.
- Scheue wilde Goobys fliehen bis zum ersten Nutella, spähen mit eigener
  Animation und rufen über 32 Blöcke. Auf Sand und Schnee bleiben kurzlebige
  Pfotenabdrücke.
- Grasbedeckte Gooby-Baue enthalten einen persistenten Bewohner mit Heimat und
  eine Startertruhe aus Nutella, Karotten und Fussel. Fund: „Wer wohnt denn hier?“.
- Buddelspuren zerfallen nach zwei Minuten. Hasen folgen wilden Goobys, Katzen
  starren und wilde Wölfe lösen Goobys Alarm aus.
- Nur natürlich gespawnte, unbenannte Wild-Goobys despawnen; alle
  spielergebundenen, verwandelten, Spawn-Ei- und Bau-Goobys bleiben erhalten.

## Create Express (4.0)

- Compile-sichtbare, optionale Create-6.0.10-API hinter einem einzigen
  `CreateBridge`. Ohne Create lädt Gooby Mod eigenständig; ein Start-Log nennt
  Version und aktive Integrationsstufe.
- Sitzende Goobys werden beim Aufbau eines mechanischen Lagers, Gantrys oder
  Zugs als Passagier übernommen, spielen Schaukeln/Zug-Neigen und begrüßen die
  Ankunft mit einer von sechs Bubbles.
- Ein Luftpfiff reißt Gooby nie von einer fahrenden Konstruktion. Ein
  Bleiben-Gooby nahe laufender Kinetik erhält alle 30 Sekunden einen kleinen
  Zufriedenheitsbonus und sechs eigene Maschinen-Lines.
- Create-bedingte Rezepte: Mixer aus 250 mB Milch, 3× Kakao und Zucker;
  Ausgießer aus leerem Gooby-Glas plus 250 mB Schokolade. Zwei leere Gläser
  lassen sich aus drei Glasscheiben herstellen.
- Transiente Create-Fehler erhalten drei tickbasierte Retries (1/2/4);
  nur echte API-Mismatches deaktivieren die Integration dauerhaft.

## Release Rails (3.0)

- **Schutzengel:** Mob-Angriffe verursachen bei gezähmten Goobys keinen
  Lebenspunktverlust. Unter hohem Druck fliehen sie zum Besitzer oder Stall.
- **Chunk-sichere Glas-Lease:** UUID + 15-Minuten-Frist verhindern
  Doppel-Spawns über Chunk-Unloads hinweg.
- **Sicheres Inventar:** Ein Hut droppt selbst bei `/kill`, Leere oder
  deaktiviertem Schutz.
- **Polish:** trauriges Wimmern statt fröhlichem Todessound, Hüte am animierten
  Kopfanker, wirklich betretbarer Hasenstall, kein doppeltes Reit-Audio.
- Vollständige Handbücher: [Deutsch](docs/handbuch/HANDBUCH_DE.md) ·
  [English](docs/handbuch/MANUAL_EN.md)

## Alive & Blinking (3.1)

- Eigener Micro-Controller: Blinzeln, Ohrenzucken, Näschenwackeln,
  Aufwach-Gähnen und glückliches Schwanzwedeln.
- Deterministische Clips für Hinsetzen/Aufstehen und Schlafen/Aufwachen.
- Landungs-Squash mit Wolkenpartikeln nach Fällen über zwei Blöcke.
- Geglättetes Kopf-Tracking, geschlossene Lid-Flächen und Sprechblasen mit
  Sichtlinien-/Unsichtbarkeitsprüfung.
- Animationszeiten und Bone-Verträge: [Animation Guide](docs/ANIMATION_GUIDE.md)

## Voice of Gooby (3.2)

- 29 neue Audiodateien: Varianten für alle Kernereignisse sowie
  Happy-/Neutral-/Sleepy-Ambient-Pools.
- Fade-Schnurr-Loop nur für den streichelnden Client; Umstehende hören das
  normale räumliche One-shot-Feedback.
- Akustisch unterscheidbare Wander-/Follow-/Stay-Pfeiftöne und Bürstengeräusch.
- Vollständiger DE+EN-Untertitel-Audit und globale ±10-%-Jitterung.

## Moods & Needs (3.3)

- Sechs synchronisierte Mood-Zustände mit 30-s-Mindestdauer.
- Fütterungs-/Besitzerzeit, lesbare Partikel/Posen/Sounds und kontextuelle
  Sprechblasen.
- Hungry-Feed- und Lonely-Pet-Boni; Schlaf pausiert Zufriedenheitsverlust.
- Shift-Blick-Inspektion zeigt Mood, Zufriedenheit und Geschenk-Ladungen.

## Tricks & Training (3.6)

- Vier persistente Drei-Sterne-Kunststücke: Drehung, Pfötchen, Flauf und Sprich.
- Trainingshappen wählen/trainieren; Leerhand-Doppelklick führt das aktive
  gelernte Kunststück über die priorisierte Actions-Schicht vor.
- Pfeife in die Luft ruft den nächsten eigenen Gooby und teleportiert ihn ab
  32 Blöcken sicher; Shift-Luftpfiff öffnet das klickbare Kunststückmenü.
- Lokales Vanilla-Buch-Handbuch mit zwölf DE+EN-Seiten, Give-once beim ersten
  Zähmen und zusätzlichem Crafting-Rezept.

## Hutch, Sweet Hutch (3.7)

- BlockEntity-Stall mit offenem Eingang, Innen-Curl, Eingang-Zzz und
  persistentem Bewohner-/Belegungszustand.
- Drei sichtbare Woll-Bettzeugstufen geben morgens 15/20/25 Zufriedenheit;
  Komfort 3 kann ein tägliches Geschenk erzeugen.
- Benanntes Namensschild bindet den nächsten eigenen Gooby explizit an den
  Stall und wird an dessen Front gerendert.
- Gebundene Homes gewinnen jede Nachtsuche. Morgenroutine: Exit-Hop, Strecken,
  Gähnen, Trillern und Lauf zum online anwesenden Besitzer.
- Sicherer Break-Eject und zustandsabhängiges Woll-Loot.

## Little Goobys (3.8)

- Nutella-Glas auf platziertem Kuchen bereitet den Ritualkuchen vor. Zwei
  erwachsene, gezähmte Goobys brauchen bei ihren jeweiligen Besitzern
  mindestens Freund-Stufe.
- Pro Elternpaar und Minecraft-Tag entsteht atomar höchstens ein Baby; beide
  Partner speichern den Cooldown und das Baby beide Eltern-UUIDs.
- Eigenes Baby-Modell mit großem Kopf, kurzen Ohren und 55-%-Scale, Baby-
  Textur, drei Piepsvarianten und vier Familienanimationen.
- Babys folgen ihren Eltern statt Pfeifen, spielen kurze Fangrunden und
  schlafen gemeinsam am Familiennest. Reiten, Hüte und Kunststücke warten bis
  zum Erwachsenwerden.
- Wachstum dauert standardmäßig 36.000 Ticks; Trainingshappen beschleunigen es.

## Fashion Fluff (3.9)

- Drei synchronisierte und persistente Slots: Hut, Schal/Fliege und winzige
  Rückentasche. Eine Schere legt das vollständige Outfit ab.
- `#goobymod:gooby_hats` ersetzt die alte Hardcode-Liste: alle kleinen Blumen,
  16 Wollteppiche und Datapack-Erweiterungen funktionieren als Hüte.
- Gooby-Schals lassen sich über das Vanilla-Färberezept in 16 Farben färben;
  Farbstoff am getragenen Schal erzeugt zusätzlich einen passenden Partikelpuff.
- Bürsten bei Beste Freunde kann zu 5 % Funkel-Fussel ergeben. Vier Stück
  schalten nacheinander Creme-, Kakao- und Fleckenfell dauerhaft frei;
  Schleich-Bürsten wechselt zwischen freigeschalteten Varianten.
- 3D-Schal, Fliege und Tasche folgen Körperanimationen. Das „Herausgeputzt"-
  Advancement belohnt ein vollständiges Drei-Slot-Outfit.

## Best Friends (2.0)

| Feature | So geht's |
|---|---|
| **Zähmung** | Nutella füttern → Gooby gehört dir (echter Besitz, persistent) |
| **Freundschaft** | 0–100 **pro Spieler**, persistent: Streicheln (+2, alle 5 s), Füttern (+8) |
| **Gooby-Pfeife** | 2× Goldnugget + Faden + Gooby-Fussel; Rechtsklick auf DEINEN Gooby: Wander → Follow → Stay |
| **Follow** | Gooby folgt dir (teleportiert bei zu großem Abstand hinterher) |
| **Stay** | Gooby sitzt und bewacht exakt diese Stelle |
| **Geschenke** | Füttern lädt Geschenk-Ladungen (max. 3); beim Buddeln übergibt Gooby sie an Freunde (Freundschaft ≥ 50) — mit Cooldown (Standard 5 min). Goldene Karotte nur für beste Freunde (≥ 90) |
| **Garderobe** | Getaggter Hut + Schal/Fliege + Tasche sind synchron und persistent; Schere nimmt alles ab |
| **Reiten** | Nur gezähmte Goobys: Besitzer immer, andere ab Stufe Freund (≥ 50) |
| **Advancements** | Eigener Baum: Goobyologie → Mein Gooby! → Beste Freunde, Gut erzogen, Gooby-Express, Buddel-Bote, Hutmode, Herausgeputzt, Kuschelzeit, Kunststücke und Familienglück |
| **Zuhause** | Benanntes Namensschild bindet Gooby an den Stall; 1–3 Wollschichten erhöhen Komfort und Morgenbonus |
| **Nachwuchs** | Nutella auf platziertem Kuchen + zwei erwachsene Tame-Goobys auf Freund-Stufe → ein Baby pro Paar/Tag |

## Was kann Gooby sonst?

| Feature | So geht's |
|---|---|
| **Streicheln** | Rechtsklick mit leerer Hand → Herzchen, Quietschen, Streichel-Animation |
| **Zufriedenheit** | Viel streicheln → Glücks-Aura (Funkel-Partikel) + schnelleres Hoppeln |
| **Sprechblasen** | Gooby erzählt von seiner Nougatschleuse, seinem Handyspiel GOOBY u.v.m. (DE/EN) |
| **Streichel-Wunsch** | Alle 1–2 Minuten schaut er dich an: „Streicheln? 🥺" |
| **Nutella füttern** | Rechtsklick mit Nutella → Gesicht ins Glas! +Zufriedenheit +Freundschaft |
| **Folgen (Lockmittel)** | Gooby folgt Spielern mit Nutella in der Hand |
| **Apportieren** | Gooby-Ball werfen → dein erwachsener Gooby bringt genau deinen Ball zurück („Apport!") |
| **Buddeln** | Gooby buddelt zum Spaß — Geschenke gibt's nur über das Geschenk-System |
| **Bürsten** | Gooby-Bürste (Wolle + Stock) → Gooby-Fussel; bei Beste Freunde 5 % Funkel-Fussel für Fellvarianten |
| **Gooby-Wolle** | Deko-Block, SO weich, dass er Fallschaden KOMPLETT dämpft |
| **Hasenstall** | Bretter + Heuballen; offener Eingang, Gooby läuft zum Innenanker und schläft wirklich darin. Aufwecken unterbricht den Schlaf 30 s |
| **Unverwundbar** | Spieler-Schläge und Mob-Angriffe auf gezähmte Goobys prallen mit *Boing!* ab |
| **Selbstschutz** | Aus Lava & Co. teleportiert sich Gooby einfach weg („Huch! Da war's mir zu heiß!") |
| **Wachsamkeit** | Erkennt Hostile in 12 Blöcken; Creeper früher. Alarm, SCARED-Pose und Schutzposition warnen den Besitzer |
| **Wettersinn** | Sucht bei Regen Dach/Stall, versteckt sich bei Gewitter hinter dem Besitzer und schüttelt Wasser ab |
| **Freundschaftsstufen** | Fremd → Kumpel → Freund → Beste Freunde; Winken, Tag-along, Geschenke, Reiten und tägliches Kuscheln |
| **Erinnerungen** | Erstes Füttern/Streicheln und Tier-Ups bleiben gespeichert; benannte Goobys hören auf den Besitzer-Chat |
| **Create-Kompat** | Freier Sitz per Shift-Rechtsklick; Passagiertransfer bei Montage/Demontage, Zugpfiff-Schutz und Maschinenkomfort |

## Server-Config

Liegt pro Welt unter `serverconfig/goobymod-server.toml`, wird zu Clients synchronisiert:

- `specialLines.enableSpecialLines` (Standard `true`) — Killswitch für die namensgebundenen
  Special-Lines. Diese sind **rein kosmetisch** (lokale Sprechblase nur für den passenden
  Spieler selbst, kein Gameplay-Effekt, keine Logs/Telemetrie).
- `specialLines.specialLineChance` (Standard `0.65`)
- `bubbles.bubbleDistance` (Standard `40`) — Render-Distanz der Sprechblasen in Blöcken
- `bubbles.idleLineMinTicks` / `idleLineMaxTicks` (Standard `2400`/`4800`)
- `gifts.giftCooldownTicks` (Standard `6000`) · `gifts.maxGiftCharges` (Standard `3`)
- `protection.goobyMobProtection` (Standard `true`) — Mob-Schutz für gezähmte Goobys
- `protection.escapeToOwner` (Standard `true`) — Flucht zu Besitzer/Stall bei niedrigem Schutzdruck
- `audio.goobyVolumeScale` (Standard `1.0`, Bereich `0.0–2.0`) — Gooby-Masterlautstärke
- `needs.hungerHours` (`1.5`) · `needs.lonelyMinutes` (`10.0`)
- `awareness.creeperAlarm` (`true`) · `awareness.alertRadius` (`12.0`)
- `bonding.nameRecognition` (`true`) — benannter eigener Gooby hört seinen Namen im Chat
- `bonding.giveHandbookOnTame` (`true`) — einmaliges Ingame-Handbuch beim ersten Zähmen
- `home.duskTravelRadius` (`96`) — maximale Heimreise zum explizit gebundenen Stall
- `family.growthTicks` (`36000`) — Wachstumsdauer eines Babys
- `family.ritualCooldown` (`24000`) — Cooldown pro Elternpaar
- `worldgen.wildSpawns` (`true`) — seltene natürliche Wild-Goobys
- `social.playChase` / `social.emoteReactions` (`true`)
- `seek.allowOres` (`false`) · `seek.cooldown` (`6000`) — optionale Erzsuche
  und Fünf-Minuten-Abklingzeit

Lokale Client-Optionen liegen in `config/goobymod-client.toml` und sind auch
über den Ingame-Config-Bildschirm (Mod-Liste → Konfiguration) einstellbar:

- `accessibility.reducedMotion` (`false`)
- `accessibility.highContrastBubbles` (`false`)
- `companionHud.showCompanionHud` (`true`) — Begleiter-Karte des nächsten
  eigenen Goobys
- `companionHud.companionHudOffsetX` / `companionHudOffsetY` (`4`/`4`) —
  Kartenposition in GUI-Pixeln
- `screenFx.screenEffects` (`true`) — Kuschel-Vignette und Alarm-Puls
- `screenFx.cameraShake` (`true`) — sanfter Kamera-Shake bei echtem Alarm

## Rezepte

- **Nutella-Glas:** 3× Kakaobohnen + Milcheimer + Zucker (formlos)
- **Leere Gooby-Gläser (2×):** 3× Glasscheibe in V-Form
- **Create-Mixer:** 250 mB Milch + 3× Kakaobohnen + Zucker → Nutella-Glas
- **Create-Ausgießer:** leeres Gooby-Glas + 250 mB Schokolade → Nutella-Glas
- **Gooby-Pfeife:** 2× Goldnugget + Faden + Gooby-Fussel (formlos)
- **Trainingshappen (3×):** Gooby-Fussel + Zucker + Kakaobohne (formlos)
- **Gooby-Handbuch:** Buch + Gooby-Fussel (formlos)
- **Gooby-Schal:** 3× Wolle + Gooby-Fussel; danach mit Vanilla-Farbstoff färbbar
- **Gooby-Fliege:** 2× Wolle + Faden
- **Winzige Tasche:** 4× Leder + Faden + Gooby-Fussel
- **Gooby-Schatzkarte:** 2×2 zerrissene Kartenfetzen
- **Gooby-Bürste:** beliebige Wolle über Stock
- **Gooby-Wolle:** 2×2 Gooby-Fussel
- **Hasenstall:** 8× Bretter (unten Mitte frei = Eingang) + Heuballen in der Mitte
- **Nutella-Toast (2×):** Brot + Nutella-Glas (formlos)
- **Knopfauge (2×):** 4× Goldnugget um eine Honigwabe
- **Gooby-Plüschtier:** 2× Knopfauge oben, Fussel–Gooby-Wolle–Fussel, Gooby-Wolle unten
- **Gooby-Statue:** Knopfauge über 2×3 Steinziegeln
- **Gooby-Ball (2×):** Schleimball + Faden + Gooby-Fussel (formlos)
- **Blumenkranz:** 3× kleine Blume über Faden–Fussel–Faden
- **Abenteuer-Halstuch:** Wolle–Faden–Wolle über Gooby-Fussel; färbbar
- **Picknick-Rucksack:** Leder-Rahmen um Gooby-Wolle, unten mittig ein Knopfauge

## Entwicklung

```bash
./gradlew build --max-workers=2 # Jar bauen (build/libs/goobymod-5.2.0.jar)
./gradlew runGameTestServer --max-workers=2 # 203 Kernsuite-GameTests (in CI fatal)
./gradlew runGameTestServer -PwithCreate --max-workers=2 # 3 Create-GameTests
./gradlew runGameTestServer -PwithSoak --max-workers=2   # Langzeit-Soak-Suite
./gradlew runServer          # Dev-Server (Port 26565)
./gradlew runClientMp        # Testclient, verbindet direkt auf den Dev-Server
python3 scripts/release.py --check-only # Release-Metadaten fail-closed prüfen
python3 scripts/release.py   # prüfen, bauen, nummeriert unter versions/ archivieren
```

Assets werden mit Python generiert — sichere Reihenfolge:

```bash
python3 scripts/gen_textures.py         # Item-/Block-/GUI-Texturen (Pillow);
                                        # fasst textures/entity/ NIE an
python3 scripts/gen_entity_textures.py  # die fünf Premium-Entity-Sheets
                                        # (gooby, cream, cocoa, spotted, baby)
python3 scripts/gen_particle_textures.py # Partikel-Sheets; --check verifiziert
python3 scripts/gen_bbmodel.py          # Blockbench-Quellen aus den Runtime-Assets
python3 scripts/validate_assets.py      # fail-closed: Geos, Animationen, UVs,
                                        # Texturen, .bbmodel-Konsistenz
python3 scripts/validate_worldgen.py    # fail-closed: Structure→Set→Pool→NBT→Loot
python3 scripts/gen_sounds.py --verify  # Audio-Gate: Manifest, Container, Lautheit
```

Daneben: `scripts/gen_whistle_texture.py`, `scripts/gen_sounds.py`
(numpy + ffmpeg, siehe `docs/AUDIO.md`), `scripts/gen_structure.py`
(GameTest-Arenen und Worldgen-Templates); Modellquellen unter
`assets_src/blockbench/` (generiert) und `assets_src/blender/` (Referenz).

`PATCHNOTES.md` enthält die spielerfreundlichen DE+EN-Änderungen.
`versions/README.md` indexiert die reproduzierbaren Release-Jars.

Made with ❤ (und sehr viel Nutella) by Sonic0810.
