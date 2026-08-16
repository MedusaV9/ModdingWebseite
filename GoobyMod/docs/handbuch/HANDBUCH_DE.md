# Gooby-Handbuch DE · v5.1.0 „Interaktions-Politur"

Für **Minecraft 1.21.1**, NeoForge **21.1.248** und GeckoLib 4.9.x.

## Neu in v5.1.0

- Jeder Klick bekommt eine Antwort: Absagen (Anschmiegen, Garderobe, Färben,
  Schere, Mäntel, Tasche) klingen jetzt hörbar, Bürsten- und
  Schnüffel-Cooldowns zeigen ihre Restzeit in der Actionbar.
- Streichel-Klickspam löst keine Kunststück-Absagen mehr aus — der
  Doppelklick wird nur zum Trick-Wunsch, wenn dein erwachsener Gooby den
  Trick auch beherrscht.
- Pflege aus der Zweithand funktioniert: Leere Haupthand plus Nutella,
  Bürste oder Happen in der anderen Hand benutzt jetzt das Item.
- Scheue wilde Goobys betteln nicht mehr um Streicheln, während sie fliehen.
  Nach dem Aufwecken steht Gooby sofort auf statt einzufrieren.
- Beim Reiten ohne Nutella-Glas erscheint ein Lenk-Hinweis. Drehung,
  High-Five und die Trick-Auswahl haben eigene Sounds.
- Das Baby-Modell ist lückenlos texturiert; `baby_hop` und die
  Begrüßungs-Animation loopen ruckelfrei.

## Neu in v5.0.2

- Langzeitserver behalten pro Gooby nur begrenzte Session-, Emote- und
  Partnerhistorien. Logout räumt Spielersitzungen sofort auf; persistente
  Freundschaft bleibt erhalten.
- Sozialverhalten bleibt niedrig priorisiert, kann im normalen KI-Pfad jetzt
  aber sowohl Begrüßung als auch das begrenzte Fangspiel auswählen. Kommandos,
  Gefahr, Schlaf und Familie gewinnen weiterhin.
- Alle zwölf normalen Crafting-Rezepte werden beim passenden Material im
  Rezeptbuch sichtbar. Nutzungshinweise an Nutella, Bürste, Trainingshappen,
  Funkel-Fussel und Schatzkarte führen direkt zum nächsten Spielschritt.
- Blasen-, Outfit- und Stallnamen sind für die Entity-/BlockEntity-Synchronisation
  paketfest begrenzt. Der Soundlimiter wird pro Serversitzung sauber neu gestartet.

## Neu in v5.0.0

- Handbuch 2.0 öffnet einen illustrierten Bildschirm mit acht Kapiteln,
  animiertem Titel-Gooby, direkten Reitern, lokalisierter Navigation und dem
  vollständigen Weg von Pflege bis Schatz. Für Werkzeuge bleibt zusätzlich
  ein 16-seitiger Buchinhalt erhalten.
- Lokale Client-Optionen `accessibility.reducedMotion` und
  `accessibility.highContrastBubbles` stoppen Kosmetikbewegung bzw. stärken
  den Blasenkontrast, ohne Server-Gameplay zu ändern. Pfeifenmodi zeigen
  eindeutige Actionbar-Symbole; jeder Sound bleibt untertitelt.
- Mikroanimationen und Pfotenakzente pausieren jenseits 24 Blöcken oder ohne
  Rendering. Periodische Stimmen werden pro Chunk zusammengefasst.
  Freundschaft speichert höchstens 32 zuletzt benutzte Nicht-Besitzer plus
  immer den Besitzer; sehr alte Besucherwerte können am Limit vergessen werden.
- Addons erhalten stabil für 5.x: `GoobyAccessor`, Zähm-/Stufen-/Geschenk-
  Events, den öffentlichen Hut-Tag und einen validierten Sprachpool-Hook.
  Siehe [`docs/ADDON_API.md`](../ADDON_API.md).
- Jeder eingebaute Sprachpool besitzt mindestens vier eigenständig formulierte
  Lines. Zwölf Handbuchbilder und der reproduzierbare
  [`docs/demo_world`](../demo_world/README.md)-Showcase schließen den Pass ab.

## Barrierefreiheit und Leistung

Client-Barrierefreiheit liegt in `config/goobymod-client.toml`. Reduzierte
Bewegung deaktiviert nur Mikroanimation und Pop-/Schwanzbewegung der Blasen;
Aktionen, Zustand und Timing bleiben gleich. Hoher Kontrast nutzt eine
blickdichte Cremefläche mit dunklem Text. Beide Optionen sind standardmäßig aus.

Das 24-Block-Kosmetik-LOD pausiert weder Bewegung, KI, Bedürfnisse, Speichern
noch Kommandos. Der Sound-Limiter bündelt nur periodische Gruppenstimmen pro
Dimension/Chunk/Sound; Interaktionsfeedback bleibt sofort.

## Neu in v4.3.0

- Rüste die Winzige Tasche aus und benutze eine weitere Tasche an deinem
  erwachsenen Gooby, um vier Lagerplätze zu öffnen. Nur der Besitzer darf
  hinein; Inhalt übersteht Reload und fällt beim Ablegen/erzwungenen Tod sicher.
- Ab Freund-Stufe zeigst du schleichend Karotte, Kartoffel, Rote-Bete-Samen
  oder einen Block, während die andere Hand einen Trainingshappen hält. Gooby
  durchsucht einmalig einen begrenzten unterirdischen 24-Block-Bereich, legt
  eine Pfotenspur und markiert den Fund.
- Der Fünf-Minuten-Cooldown gilt auch ohne Fund. Die Trost-Bubble ist
  absichtliches Feedback. Erze brauchen `seek.allowOres=true`; gemütliche Ziele
  funktionieren standardmäßig.
- Ferne Buddelgeschenke landen atomar in der Tasche. Welt-Drops gehören zehn
  Sekunden dem vorgesehenen Freund.
- Beste Freunde buddeln mit seltenen 5 % einen Kartenfetzen aus. Vier Fetzen
  ergeben eine Gooby-Schatzkarte zum generierten Schatzversteck.

## Auf Schatzsuche

1. Erreiche Freund-Stufe und rüste am Gooby eine Winzige Tasche aus.
2. Halte das Such-Item in der Interaktionshand und einen Trainingshappen in der
   anderen. Schleich-benutze Gooby. Schnüffeln und Pfoten bestätigen eine Spur.
3. Folge Gooby bis zum Buddelmarker. Ohne Ziel bekommst du eine Trost-Line und
   wartest den eingestellten Cooldown.
4. Pflege einen besten Freund und sammle vier seltene Fetzen. Crafte sie im
   2×2-Feld und benutze die Karte, damit ein rotes X erscheint.

Das seltene Jigsaw-Versteck enthält Accessoires, Funkel-Fussel, Gooby-Fussel
und Nutella. „Flausch am X“ belohnt die fertige Karte; „Liebevoll gepackt“ alle
vier belegten Taschenplätze.

## Neu in v4.2.0

- Nahe Goobys begrüßen sich synchron, spielen begrenzt Fangen, tauschen
  kosmetische Geschenke und kuscheln beim Schlafen. Jede Sozialbewegung hat
  niedrigere Priorität als Bleiben, Folgen, Schlaf, Schutz, Familie und Gefahr.
- Ein Fangspiel endet nach 30 Sekunden; dasselbe Paar wartet danach fünf
  Minuten. `social.playChase=false` schaltet es ab.
- Absichtliche Spieler-Emotes bekommen Antworten: Drücke beim Ansehen zweimal
  in einer Sekunde Schleichen für eine Verbeugung; springe dreimal bei einem
  glücklichen Gooby für gemeinsames Hüpfen. `social.emoteReactions` schaltet um.
- Drei Schläfer in drei Blöcken bilden einen Flauschhaufen und verleihen das
  Advancement. Einzelne Zzz verschmelzen zu einem großen Haufenmarker.
- Sprechblasen staffeln sich nach Entity, skalieren weich ein/aus, zeigen zum
  angesprochenen Spieler und unterstützen Herz-, Nutella-, Schlaf-/Alarmglyphen.

## Goobys unter sich

Soziales Spiel ändert nie ein Kommando. Ein Bleiben-Gooby bleibt exakt am Ort;
ein Folgen-Gooby priorisiert weiterhin seinen Besitzer. Begrüßungspartner
spiegeln denselben zweistufigen Hopser. Fangspiele besitzen immer ein
600-Tick-Limit und Paar-Cooldown. Benannte Goobys erscheinen in Sozialblasen.

Sieh für das Verbeugungs-Emote deinen Gooby an und drücke Schleichen zweimal
getrennt innerhalb von 20 Ticks. Normales Geduckthalten wiederholt nichts.
Die Sprungantwort braucht glückliche Stimmung und drei Sprünge in 40 Ticks.

## Neu in v4.1.0

- Seltene wilde Goobys spawnen einzeln in Blumenwäldern, Kirschhainen und
  Wiesen. `worldgen.wildSpawns` schaltet natürliche Spawns ab, ohne Baue oder
  von Spielern erzeugte Begleiter zu beeinflussen.
- Wilde Goobys fliehen vor unbekannten Spielern bis zum ersten Nutella. Sie
  spähen scheu, hinterlassen kurzlebige Pfotenpartikel auf Sand und Schnee und
  rufen über 32 Blöcke, damit aufmerksame Entdecker sie finden.
- Grasbedeckte Gooby-Baue enthalten einen persistenten Bewohner und einen
  Startervorrat aus einem Nutella-Glas, Karotten und Fussel. Entdeckung gibt
  „Wer wohnt denn hier?“.
- Buddeln hinterlässt eine kollisionslose Erdspur, die nach zwei Minuten
  zerfällt. Hasen folgen wilden Goobys, Katzen starren und wilde Wölfe lösen
  Alarm aus.
- Nur natürlich gespawnte, unbenannte wilde Goobys despawnen normal.
  Gezähmte, verwandelte, Spawn-Ei- und Bau-Goobys bleiben persistent.

## Wilde Goobys & Baue

Achte in Wiesen, Kirschhainen und Blumenwäldern auf den fernen Zweiton-Ruf.
Nähere dich langsam: Ein neu gefundener Gooby hält zehn Blöcke Abstand, bis du
Nutella anbietest. Ein Bau ist ein niedriger Grashügel mit südlichem Tunnel.
Sein Bewohner behandelt die Kammer als Zuhause und despawnt nie; die Truhe
liefert das erste Glas zum Vertrauensaufbau.

Natürliche Spawns bleiben bewusst extrem selten (Gewicht 1, Einzeltier).
Server können `worldgen.wildSpawns=false` setzen; bestehende Goobys und
generierte Baue bleiben unberührt.

## Neu in v4.0.0

- Create 6.0.10 ist compile-sichtbar, bleibt aber optional. Ohne Create sind
  alle Kompat-Funktionen inaktiv und Gooby Mod lädt normal. Mit Create ersetzen
  typisierte Sitz-, Konstruktions- und Kinetik-APIs die Klassen-Namensprüfung;
  ein verifizierter Reflexions-Fallback schützt den Sitzpfad bei API-Drift.
- Ein vor der Montage auf einem Sitz platzierter Gooby wechselt beim Aufbau
  eines Lagers, Gantrys oder Zugs auf die bewegte Konstruktion und bleibt
  Passagier. Entspanntes Schaukeln und Zug-Neigen folgen der Bewegung. Bei der
  Ankunft erscheint eine von sechs Sprechblasen.
- Ein Luftpfiff reißt Gooby nie von einer fahrenden Konstruktion. Gooby
  antwortet freundlich, dass er gerade Zug fährt, und bleibt sitzen.
- Ein Gooby im Modus Bleiben erhält im Fünf-Block-Radius einer laufenden, nicht
  überlasteten Kinetikmaschine alle 30 Sekunden einen Zufriedenheitspunkt und
  nutzt sechs Maschinen-Lines.
- Leere Gooby-Gläser entstehen aus drei Glasscheiben. Create ergänzt zwei
  bedingte Produktionswege; das ursprüngliche Handrezept bleibt unverändert.
- Create-Fehler sind getrennt: API-/Linkage-Mismatch deaktiviert nur die
  Integration dauerhaft; transiente Laufzeitfehler erhalten drei nicht
  blockierende Retries mit 1/2/4-Tick-Backoff.

## Create-Express

Beide Verarbeitungsrezepte existieren nur mit geladenem Create:

```text
Mechanischer Mixer
250 mB Milch + 3× Kakaobohnen + Zucker
                              │
                              ▼
                         Nutella-Glas

Ausgießer
250 mB Create-Schokolade
             │
             ▼
    Leeres Gooby-Glas ──► Nutella-Glas
```

Der Mixer ist der Mengenweg und ersetzt nicht das formlose
Milcheimer-Handrezept. Der Ausgießer verbraucht ein leeres Gooby-Glas und
250 mB Schokolade. Drei Glasscheiben in V-Form ergeben zwei leere Gläser.

Schleich-benutze deinen eigenen erwachsenen Gooby neben einem freien
Create-Sitz, bevor die Konstruktion montiert wird. Create übernimmt den
Passagier beim Aufbau und setzt Gooby bei der Demontage zurück. Beim Start
erscheint genau eine knappe Diagnose mit Create-Version und Integrationsstufe.

## Neu in v3.9.0

- Gooby besitzt persistente, synchronisierte Slots für Kopf, Hals und Rücken.
  Getaggte Hüte, ein färbbarer Gooby-Schal oder eine Fliege und die winzige
  Tasche bleiben für alle sichtbar und überstehen Reloads.
- Alle kleinen Blumen und 16 Wollteppiche sind über
  `#goobymod:gooby_hats` Hüte. Datapacks können den Tag erweitern.
- Drei Wolle plus Gooby-Fussel ergeben einen Schal. Das Vanilla-Färberezept
  unterstützt 16 Farben; Farbstoff am getragenen Schal erzeugt zusätzlich
  einen farblich passenden Partikelpuff.
- Bei Beste Freunde hat Bürsten 5 % Chance auf Funkel-Fussel. Vier davon am
  eigenen erwachsenen Gooby schalten das nächste Creme-, Kakao- oder
  Fleckenfell dauerhaft frei. Schleich-Bürsten wechselt die Varianten.
- Eine Schere gibt alle Accessoires gemeinsam zurück. Ein vollständiges
  Drei-Slot-Outfit verleiht „Herausgeputzt".
- Mit Curios 9.5.1+ passt die Gooby-Pfeife in einen Charm-Slot. Curios bleibt
  optional; ohne Mod werden keine Kompat-Klassen geladen und keine Logs erzeugt.

## Goobys Garderobe

| Slot | Auswahl |
|---|---|
| Kopf | jedes Item in `#goobymod:gooby_hats` |
| Hals | färbbarer Gooby-Schal oder Gooby-Fliege |
| Rücken | winzige Tasche (vier besitzergebundene Lagerplätze) |

Die Shift-Blick-Zeile zeigt kleine Garderoben-Glyphen und das aktive Fell.
Schal und Tasche verwenden 3D-Anhänge an animierten Körperankern und folgen
dadurch Hoppeln und Schlafen, statt im Weltraum zu schweben.

## Neu in v3.8.0

- Benutze ein Nutella-Glas auf einem platzierten Vanilla-Kuchen, um einen
  **Nutella-Kuchen** vorzubereiten. Er wartet in der Welt auf eine passende
  Familie.
- Das Ritual braucht zwei erwachsene, gezähmte Goobys. Jeder benötigt bei
  seinem eigenen Besitzer mindestens **Freund (50)**; die Besitzer dürfen
  verschieden sein.
- Ein erfolgreiches Ritual erzeugt exakt ein gezähmtes Baby. Dasselbe Paar
  kann auch nach Reload oder Ersatzkuchen höchstens ein Baby pro Minecraft-Tag
  begrüßen.
- Babys besitzen ein eigenes großköpfiges, kurzohriges Modell mit 55 % Scale,
  folgen einem ihrer gespeicherten Eltern, spielen kurze Fangrunden und
  schlafen gemeinsam am Familiennest.
- Babys können nicht reiten, Create-Sitze nutzen, Hüte tragen, Kunststücke
  ausführen oder Pfeifen folgen. Nach 36.000 Ticks (1,5 Tagen) wachsen sie
  heran; Trainingshappen verkürzen die Restzeit.

## Nachwuchs

1. Bringe zwei erwachsene, gezähmte Goobys bei ihren jeweiligen Besitzern auf
   die Stufe Freund.
2. Platziere einen Kuchen auf festem Boden; beide Goobys müssen höchstens sechs
   Blöcke entfernt sein.
3. Benutze ein Nutella-Glas am Kuchen. Herzen, Nuzzeln und ein Baby bestätigen
   das Ritual. Fehlt eine Voraussetzung, wartet der vorbereitete Kuchen.
4. Lass das Baby seinen Eltern folgen. Alter, beide Eltern-UUIDs, Familiennest
   und Paar-Cooldown bleiben in Saves erhalten.

Baby-Piepser sind drei separat erzeugte Sounds und nicht nur hochgepitchte
Erwachsenenstimmen. Ein seltener Purzelbaum besitzt einen harten
Ein-Minuten-Cooldown. Trainingshappen des Besitzers beschleunigen das Wachstum,
statt das Kunststücktraining zu öffnen.

## Neu in v3.7.0

- Der Hasenstall besitzt einen offenen Eingang, sichtbaren Innenraum und drei
  Bettzeugstufen. Rechtsklicke ihn pro Stufe mit einem Wollblock.
- Benenne ein Namensschild am Amboss und benutze es am Stall, während dein
  eigener Gooby in höchstens 16 Blöcken Nähe steht. Das Schild übernimmt den
  Namen und bindet genau diesen Gooby an das Zuhause.
- Gebundene Goobys reisen abends aus bis zu 96 Blöcken heim, schlafen im engen
  Stall-Curl und senden Zzz durch den Eingang. Weiter entfernte Goobys schlafen
  ausnahmsweise draußen, ohne ihren Stall zu vergessen.
- Komfort 1–3 gibt morgens 15/20/25 Zufriedenheit. Komfort 3 hat zusätzlich
  eine Chance auf ein tägliches Geschenk.
- Beim Aufwachen hoppelt Gooby heraus, streckt sich, gähnt und trillert, bevor
  er seinen online anwesenden Besitzer aufsucht. Beim Stallabbau wird ein
  Bewohner sicher ausgeworfen; alle Bettzeug-Wollblöcke fallen zurück.

## Ein Zuhause für Gooby

1. Crafte den Stall aus acht Brettern um einen Heuballen und stelle den Eingang
   frei zugänglich auf.
2. Baue mit ein bis drei Woll-Rechtsklicks das Bettzeug aus. Die Farbe wird
   aktuell als warmes Komfort-Overlay dargestellt; beim Abbau fällt weiße Wolle.
3. Benenne ein Namensschild exakt so, wie Gooby heißen soll. Rechtsklicke den
   Stall damit: Der nächste Gooby in deinem Besitz wird benannt und gebunden.
4. Lass den Weg abends frei. Ein gebundener Stall schlägt jeden näheren freien
   Stall; `home.duskTravelRadius` regelt die maximale Heimreise.

Ein belegter Stall zeigt Zzz am Eingang. Das Namensschild bleibt über
Save/Reload erhalten. Wird der Stall im Schlaf abgebaut, wacht Gooby außerhalb
der Kollisionsfläche auf, verliert nur dieses Zuhause und bleibt unverletzt.

## Neu in v3.6.0

- `Gooby-Fussel + Zucker + Kakaobohne` ergeben drei Trainingshappen. Mit einem
  Happen in der Hand wählt Shift-Rechtsklick das Kunststück; normaler
  Rechtsklick trainiert es. Drei erfolgreiche Sitzungen ergeben drei Sterne.
- Trainierte Kunststücke führst du mit einem schnellen Leerhand-Doppelklick
  aus: **Drehung**, **Pfötchen**, **Flauf** oder **Sprich**.
- Benutze die Pfeife in die Luft, um den nächsten eigenen Gooby zu rufen.
  Jenseits von 32 Blöcken ploppt er mit den bekannten Sicherheitsprüfungen zu
  dir. Shift-Luftpfiff zeigt ein klickbares Auswahlmenü im Chat.
- Das Ingame-Gooby-Handbuch wird beim ersten Zähmen einmal vergeben (Config)
  und lässt sich zusätzlich aus Buch + Gooby-Fussel craften.

## Kunststücke trainieren

1. Schleiche und rechtsklicke mit einem Trainingshappen, bis das gewünschte
   Kunststück angezeigt wird. Alternativ wählst du es im Pfeifenmenü.
2. Rechtsklicke normal mit dem Happen. Nach jeder erfolgreichen Runde braucht
   Gooby zwei Sekunden Pause; nur erfolgreiche Runden verbrauchen einen Happen.
3. Bereits ein Stern schaltet die Vorführung frei. Drei Sterne meistern das
   Kunststück. Die Shift-Blick-Statuszeile zeigt Auswahl und Sterne.
4. Doppelklicke Gooby mit leerer Hand. **Sprich** erzeugt garantiert eine
   Sprechblase samt Stimme; **Flauf** endet mit einer weichen Plüschlandung.

Die Pfeife merkt ihren letzten Wander-/Follow-/Stay-Modus im Tooltip.
Fremde oder wilde Goobys antworten mit einem klar tieferen Ablehnungssignal.

## Neu in v3.5.0

- Der bestehende Freundschaftswert ergibt ohne Save-Migration vier Stufen.
  Stufenaufstiege feiern mit Bounce, Jingle, Herzen, Bubble und Actionbar.
- Erste Fütterung, erstes Streicheln und Stufenaufstiege werden als
  UUID-gebundene Erinnerungen gespeichert. Nach sieben Ingame-Tagen erinnert
  Gooby sich mit einer besonderen Bubble.
- Ein benannter Gooby stellt die Ohren auf und schaut zum Besitzer, wenn dieser
  seinen Namen im Chat sagt (`bonding.nameRecognition`).
- Beste Freunde können einmal pro Ingame-Tag mit Shift-Rechtsklick kuscheln:
  langes Schnurren, goldene Herzen und Regeneration I für zehn Sekunden.

## Freundschaftsstufen

| Stufe | Wert | Freischaltungen |
|---|---:|---|
| Fremd | 0–19 | kennenlernen, füttern und streicheln |
| Kumpel | 20–49 | persönliche Begrüßung und Winken |
| Freund | 50–89 | Geschenke, Reiten und kurzer Tag-along beim Vorbeisprinten |
| Beste Freunde | 90–100 | goldene Geschenke und tägliche Kuschelzeit |

Die alte Reitschwelle 30 wurde vereinheitlicht: Nicht-Besitzer benötigen jetzt
**Freund (50)**. Der Besitzer darf den eigenen gezähmten Gooby weiterhin
unabhängig von seiner persönlichen Zahl reiten. Fortschritt erscheint nur bei
Stufenwechseln und überschrittenen Fünfergrenzen, nicht nach jedem Klick.

## Neu in v3.4.0

- Hostile innerhalb von 12 Blöcken lösen SCARED, aufgerichtete Ohren und einen
  Alarm aus. Ein naher Besitzer wird aus einer Position zwischen ihm und der
  Gefahr gewarnt; Gooby greift niemals an.
- Creeper erkennt Gooby vier Blöcke früher und meldet sie lauter. Eine kurze
  Hysterese verhindert Alarmflattern am Rand.
- Wilde Goobys fliehen nach Schaden. Feuer, Kakteen und Pulverschnee besitzen
  hohe bzw. unpassierbare Wegkosten.
- Bei Regen sucht Gooby Dach oder Stall. Bei Gewitter versteckt er sich hinter
  seinem Besitzer; beim Trocknen schüttelt er Wassertropfen aus dem Fell.
- Mittags streunt und buddelt Gooby aktiver, abends sitzt er häufiger gemütlich.

## Gooby passt auf dich auf

Der scharfe Doppel-Alarm bedeutet, dass Gooby einen feindlichen Mob gesehen
hat. Die Blickrichtung und die aufrechten Ohren zeigen die Gefahr. Ein
tieferer, lauterer Alarm kennzeichnet Creeper. Der Alarm ist eine Warnung:
Gooby ist kein Kämpfer. Bringe ihn und dich in Sicherheit. Follow-Teleports
lehnen Lava, Feuer, Kakteen, Pulverschnee, Weltgrenzen und unsichere Bauhöhen
ab.

## Neu in v3.3.0

- Gooby zeigt synchronisiert **Glücklich, Zufrieden, Hungrig, Schläfrig,
  Einsam** oder **Ängstlich**. Ein Zustand bleibt mindestens 30 Sekunden stabil.
- Hunger folgt der letzten Fütterung; Einsamkeit entsteht nach längerer
  Entfernung vom Besitzer. Schlaf stoppt Zufriedenheitsverlust.
- Hungriges Füttern gibt +2 Bonusfreundschaft. Streicheln bei Einsamkeit gibt
  doppelte Zufriedenheit.
- Shift halten und den eigenen Gooby eine Sekunde ansehen zeigt
  `❤ Zufriedenheit · Mood · 🎁 Ladungen` in der Actionbar.
- Nutella-Gedankenpartikel, Bettelpose, hängende Ohren, Happy-Bounce sowie
  hungriges Wimmern/einsames Seufzen machen Bedürfnisse ohne UI lesbar.

## Bedürfnisse lesen

Hungrige Goobys betteln bei sichtbarem Nutella und sprechen über Snacks.
Einsame Goobys lassen die Ohren hängen und freuen sich besonders über
Streicheln. Schläfrige Goobys fordern nachts keine Streicheleinheiten und
verlieren im Schlaf keine Zufriedenheit. Die kompakte Shift-Anzeige ist eine
Kontrolle, nicht der einzige Weg, den Zustand zu erkennen.

## Neu in v3.2.0

- Jeder zentrale Gooby-Sound besitzt jetzt zwei oder drei Varianten mit
  leichter Lautstärke- und Tonhöhenstreuung. Quietschen, Schnurren, Boing,
  Plop, Schmatzen und Schnarchen klingen nicht mehr maschinell identisch.
- Goobys Stimme folgt der Situation: glückliches Trillern bei hoher
  Zufriedenheit, neutrales Mümmeln tagsüber und schläfriges Murmeln nachts
  oder bei sehr niedriger Zufriedenheit.
- Nur der streichelnde Spieler hört einen weichen, ein- und ausblendenden
  Schnurr-Loop; Umstehende behalten das kurze räumliche Feedback.
- Wander, Follow und Stay haben klar verschiedene Pfeifentöne. Die Bürste
  besitzt ein eigenes leises Stoffgeräusch.
- `audio.goobyVolumeScale` regelt alle Gooby-Kreaturensounds von 0,0–2,0.

## Goobys Klänge verstehen

| Klang | Aussage |
|---|---|
| aufsteigendes Trillern | Gooby ist sehr zufrieden |
| ruhiges Mümmeln | neutraler, entspannter Tag |
| tiefes schläfriges Murmeln | Nacht oder sehr niedrige Zufriedenheit |
| tiefer Pfeifton | Wander |
| aufsteigender mittlerer Pfeifton | Follow |
| hoher gleichbleibender Pfeifton | Stay |
| langer leiser Schnurrer | du streichelst Gooby gerade |
| weiches Bürsten | Fellpflege wurde angenommen |

Alle Ereignisse besitzen eigene DE+EN-Untertitel. Schlafende Goobys spielen
keinen normalen Ambient-Sound; das 90-Tick-Schnarchen bleibt räumlich gedämpft.

## Neu in v3.1.0

- Gooby blinzelt alle 3–7 Sekunden, schnuppert mit dem Näschen alle 4–10
  Sekunden und zeigt zufälliges Ohrenzucken. Glückliche Goobys wedeln
  zusätzlich mit dem Puschelschwanz.
- Nach dem Aufwachen streckt sich Gooby und gähnt hörbar. Die Sounds laufen
  lokal über Animations-Keyframes und erzeugen keinen Server-Netzwerkverkehr.
- Hinsetzen, Aufstehen, Einschlafen und Aufwachen besitzen eigene
  Übergangsclips. Ein Zustandsautomat lässt jeden Übergang ausspielen.
- Nach einem Fall über mehr als zwei Blöcke landet Gooby mit Squash & Stretch
  und einer kleinen Wolke. Fallschaden nimmt er weiterhin nicht.
- Geschlossene Lid-Flächen machen Blinzeln und Schlaf klar lesbar.
- Die Blickbewegung des Kopfes ist geglättet. Sprechblasen werden nicht mehr
  durch Wände oder an unsichtbaren Goobys gerendert.

## Goobys Körpersprache

| Bewegung | Bedeutung |
|---|---|
| kurzes Blinzeln | ruhiger, aufmerksamer Gooby |
| wechselndes Ohrenzucken | ein Geräusch oder eine Bewegung wurde bemerkt |
| schnupperndes Näschen | Gooby erkundet entspannt seine Umgebung |
| schnelles Schwanzwedeln | hohe Zufriedenheit |
| Strecken und Gähnen | gerade aufgewacht |
| weiche Landekompression | sicherer Fall aus mehr als zwei Blöcken |
| gesenkte Ohren | trauriger oder erschrockener Zustand |

Mikrobewegungen sind eine eigene Animationsschicht. Daher bleibt das Hoppeln
aktiv, auch wenn ein Blinzeln fällig war. Streicheln, Fressen, Winken und
Landen haben Priorität und werden nie mitten im Clip abgeschnitten.

## Neu in v3.0.0

- **Schutzengel:** Gezähmte Goobys verlieren durch Angriffe von Mobs keine
  Lebenspunkte. Mehrere schwere Treffer versetzen sie in Panik; bei höchstens
  30 % verbleibender Schutz-Ausdauer fliehen sie zum Besitzer. Ist dieser nicht
  in derselben Dimension, ist der gemerkte Hasenstall das sichere Ersatzziel.
- Der Besitzer erhält eine Chat-Nachricht, wenn Gooby fliehen musste.
- Server können Mob-Schutz und Flucht einzeln in der Config abschalten.
- Der Hasenstall hat jetzt einen echten, offenen Innenanker. Gooby läuft hinein
  und schläft nicht mehr nur neben der Wand.
- Hüte sitzen auf einem eigenen Anker am animierten Kopf und folgen Schlaf-,
  Ess- und Streichelposen.
- Ein eigenes trauriges Wimmern ersetzt das fröhliche Todesquietschen.
- Nutella-Gläser speichern den UUID-Anspruch des gerufenen Goobys 15 Minuten
  lang. Chunk-Unloads können deshalb keinen zweiten Gooby erzeugen.

## Einen Gooby bekommen

### Wildhase verwandeln

1. Stelle ein Nutella-Glas aus drei Kakaobohnen, einem Milcheimer und Zucker
   formlos her. Der leere Eimer bleibt übrig.
2. Rechtsklicke einen Wildhasen mit dem Glas.
3. Der verwandelte Gooby ist sofort gezähmt, gehört dir und startet mit
   40 Freundschaft.

### Nutella-Glas aufstellen

Stelle das Glas auf einen Grasblock. Nachts kann ein wilder Gooby aus 5–8
Blöcken Entfernung angelockt werden. Das Glas reserviert exakt diesen Gooby,
auch wenn dessen Chunk entladen ist. Der wilde Gooby wird erst durch weiteres
Nutella gezähmt.

## Zähmung, Freundschaft und Zufriedenheit

- **Nutella füttern:** zähmt wilde Goobys, gibt +8 Freundschaft, +30
  Zufriedenheit und eine Geschenk-Ladung.
- **Streicheln:** leere Haupthand, Rechtsklick; +15 Zufriedenheit und +2
  Freundschaft. Der Freundschaftsgewinn zählt pro Spieler alle fünf Sekunden.
- Freundschaft wird pro Spieler von 0–100 gespeichert.
- Ab 60 Zufriedenheit funkelt Gooby und hoppelt schneller.
- Spieler-Schläge sind harmlos. Auch der Zufriedenheitsverlust ist nun auf
  einmal pro fünf Sekunden und Spieler begrenzt.

## Pfeife und Kommandos

Die Gooby-Pfeife entsteht formlos aus zwei Goldnuggets, Faden und Gooby-Fussel.
Nur der Besitzer kann damit den Modus wechseln:

1. **Wander:** Gooby erkundet frei.
2. **Follow:** Gooby folgt seinem Besitzer und teleportiert bei großer Distanz.
3. **Stay:** Gooby sitzt und bleibt am befohlenen Ort.

## Geschenke

Jedes gefütterte Nutella-Glas lädt eine Geschenk-Ladung (Standardmaximum 3).
Beim Buddeln kann Gooby genau eine Ladung für einen Spieler mit mindestens
50 Freundschaft ausgeben. Danach gilt standardmäßig fünf Minuten Cooldown.
Ab 90 Freundschaft kann eine goldene Karotte dabei sein.

## Sichere Garderobe

Der Besitzer rüstet einen getaggten Hut, ein Hals- und ein Rückenaccessoire
aus. Alle drei Slots sind synchronisiert und bleiben nach Neustarts erhalten.
Eine Schere gibt das vollständige Outfit gemeinsam zurück. Sollte ein Gooby
durch `/kill`, die Leere oder abgeschalteten Schutz doch sterben, fallen alle
Accessoires sicher als Items.

## Reiten und Create

Shift-Rechtsklick mit leerer Hand setzt den Besitzer auf einen gezähmten Gooby.
Andere Spieler benötigen die Stufe Freund (50). Halte Nutella zum Lenken. Die
Freuden-Hopser werden nur serverseitig ausgelöst, daher gibt es kein doppeltes
Quietschen mehr. Wenn Create 6.x vorhanden und kompatibel ist, kann der
Besitzer Gooby auf einen freien Create-Sitz setzen; ohne Create bleibt normales
Reiten verfügbar.

## Hasenstall und Schlaf

Der Hasenstall wird aus acht Brettern um einen Heuballen gebaut. Ohne
Namensschild nutzt Gooby weiterhin einen nahen freien Stall. Ein benanntes
Schild bindet Stall und Bewohner dagegen dauerhaft: Diese Bindung hat bei der
Nachtsuche Vorrang. Der Weg führt durch den offenen Eingang zum Innenanker.

Wolle erhöht Komfort auf 1–3. Morgens regeneriert Gooby abhängig davon
15/20/25 Zufriedenheit; auf Stufe 3 kann einmal pro Minecraft-Tag ein kleines
Geschenk fallen. Danach folgt die Exit-Hop-, Streck-, Gähn- und Trill-Sequenz.
Streicheln oder Füttern weckt Gooby und verhindert 30 Sekunden lang sofortiges
Wiedereinschlafen. Abbau gibt Bettzeug zurück und wirft Bewohner sicher aus.

## Bürste, Fussel und Gooby-Wolle

Eine Bürste aus Wolle und Stock liefert Gooby-Fussel; bei Beste Freunde
entsteht mit 5 % Chance stattdessen Funkel-Fussel. Vier normale Fussel ergeben
einen Gooby-Wollblock, der Fallschaden vollständig verhindert. Vier
Funkel-Fussel am eigenen erwachsenen Gooby schalten das nächste Fell dauerhaft
frei.

## Server-Config

Datei: `serverconfig/goobymod-server.toml`

| Schlüssel | Standard | Wirkung |
|---|---:|---|
| `protection.goobyMobProtection` | `true` | Mob-Schaden an gezähmten Goobys abfangen |
| `protection.escapeToOwner` | `true` | Flucht zu Besitzer oder Stall bei niedrigem Schutzdruck |
| `specialLines.enableSpecialLines` | `true` | kosmetische namensgebundene Lines |
| `specialLines.specialLineChance` | `0.65` | Chance auf passende Special-Line |
| `bubbles.bubbleDistance` | `40` | Renderdistanz der Sprechblasen |
| `bubbles.idleLineMinTicks` | `2400` | minimale Pause zwischen Idle-Lines |
| `bubbles.idleLineMaxTicks` | `4800` | maximale Pause zwischen Idle-Lines |
| `gifts.giftCooldownTicks` | `6000` | Geschenk-Cooldown |
| `gifts.maxGiftCharges` | `3` | gespeicherte Geschenk-Ladungen |
| `audio.goobyVolumeScale` | `1.0` | Master-Lautstärke aller Gooby-Sounds (0,0–2,0) |
| `needs.hungerHours` | `1.5` | Zeit bis Hunger (1,5 Minecraft-Tage) |
| `needs.lonelyMinutes` | `10.0` | Besitzer-Abwesenheit bis Einsamkeit (Minuten) |
| `awareness.creeperAlarm` | `true` | frühere und lautere Creeper-Warnung |
| `awareness.alertRadius` | `12.0` | normale Hostile-Erkennungsweite in Blöcken |
| `bonding.nameRecognition` | `true` | eigener benannter Gooby reagiert auf seinen Namen im Chat |
| `bonding.giveHandbookOnTame` | `true` | gibt jedem Spieler beim ersten Zähmen einmal das Ingame-Handbuch |
| `home.duskTravelRadius` | `96` | maximale abendliche Heimreise zum explizit gebundenen Stall |
| `family.growthTicks` | `36000` | Ticks, bis ein Gooby-Baby erwachsen wird |
| `family.ritualCooldown` | `24000` | Mindestzeit zwischen Babys desselben Paars |
| `worldgen.wildSpawns` | `true` | seltene natürliche Wild-Gooby-Spawns erlauben |
| `social.playChase` | `true` | begrenzte, niedrig priorisierte Fangspiele erlauben |
| `social.emoteReactions` | `true` | absichtliche Verbeugungs-/Freudensprung-Reaktionen |
| `seek.allowOres` | `false` | gezeigte Erzblöcke als Schnüffel-&-Such-Ziele erlauben |
| `seek.cooldown` | `6000` | Ticks zwischen erfolgreichen oder leeren Suchscans |

## Client-Config

Datei: `config/goobymod-client.toml`

| Schlüssel | Standard | Wirkung |
|---|---:|---|
| `accessibility.reducedMotion` | `false` | Kosmetik-Mikroanimation und Blasenbewegung stoppen |
| `accessibility.highContrastBubbles` | `false` | blickdichte Cremeblasen mit dunklerem Text |

## Hilfe bei Problemen

Prüfe zuerst Minecraft 1.21.1, NeoForge 21.1.248 und GeckoLib 4.9.x. Bei einem
Bugbericht helfen Logdatei, Gooby-Name, Kommandomodus und die betroffene
Config. Die Spielertexte sind vollständig auf Deutsch und Englisch vorhanden.

---

Made with ❤ (und sehr viel Nutella) by Sonic0810 · **made by Sonic0810**
