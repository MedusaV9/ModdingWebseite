import React from 'react';
import {AbsoluteFill, Audio, Sequence, staticFile} from 'remotion';
import {ClipScene} from './components/ClipScene';
import {Flash} from './components/Flash';
import {MontageBadge} from './components/MontageBadge';
import {Outro} from './components/Outro';
import {RanchCard} from './components/RanchCard';
import {TitleCard} from './components/TitleCard';
import {TrioScene} from './components/TrioScene';
import {loadBaloo} from './load-font';
import {BEAT, COLORS} from './theme';

loadBaloo();

/**
 * Fahrplan v3 (60 fps, Beat = 36 Frames bei 100 BPM — alle Schnitte liegen
 * auf Beat-Vielfachen; 96 Beats = 57,6 s):
 *
 *   0.0– 2.4 s  Titelkarte „GOOBY 5.0“
 *   2.4– 4.8 s  Der wiederhergestellte Gooby (Showcase, Fell-Look mit Flaum)
 *   4.8– 7.2 s  NEU: Emotions-Nahaufnahme — Schreck (!) + Verliebtheit (♥)
 *               mit Symbol überm Kopf, echtem Regie-Zoom und Zeitlupe
 *   7.2– 9.0 s  Zuhause mit echten Möbeln (Wohnzimmer)
 *   9.0–11.4 s  Baumodus (Bett aus dem Lager, Vorstadt-Kulisse, Hammer-Gag)
 *  11.4–13.2 s  Gestalten-Modus (Fassaden-/Dach-/Türfarben live)
 *  13.2–15.0 s  NEU: Das eigene Haus steht im Garten (HAUS-SICHT)
 *  15.0–16.2 s  GOUHBUS-Möbelausstellung in 3D
 *  16.2–18.0 s  Garderobe (93 Kosmetik-Teile am lebenden Gooby)
 *  18.0–19.2 s  Stadt-Panorama
 *  19.2–21.0 s  Autofahrt am Tag (lesbare Billboard-Ortsschilder)
 *  21.0–22.2 s  Stadt bei Nacht
 *  22.2–25.2 s  NEU: Funkelpark — Tor-Totale, dann Achterbahn-POV
 *  25.2–32.4 s  Minispiel-Montage „38 Minispiele“ (6 Slots à 1,2 s,
 *               inkl. Hochkant-Triptychon)
 *  32.4–33.6 s  Multiplayer-Besuch (zwei Goobys im Wohnzimmer)
 *  33.6–35.4 s  ★ Kapitel-Karte GOOBY RANCH (Key-Artwork + Logo)
 *  35.4–37.2 s  Überlandfahrt zur Ranch (Landstraße, Felder, Kühe)
 *  37.2–39.0 s  Ranch-Hof (Gooby-Pferde im Galopp, Huf-Bodenkontakt)
 *  39.0–40.8 s  Freies Reiten in der offenen Region
 *  40.8–42.0 s  Bergmassiv: Hängebrücke über die Schlucht
 *  42.0–43.2 s  Bergsee (Wasser mit Wellen, Tiefe und Schaumsaum)
 *  43.2–46.8 s  Neue-Zonen-Montage (Lavendel, Moor, Ruine, Bucht,
 *               Apfelgarten, Kornfeld mit Wind — 6 × 0,6 s)
 *  46.8–48.6 s  7 Wetterlagen (mehrschichtiger Regen mit Aufschlagringen)
 *  48.6–50.4 s  Dorf Hufingen (Quests & NPCs)
 *  50.4–52.2 s  Turnier-Springen (Wettbewerbe + Liga)
 *  52.2–54.0 s  Multiplayer-Ausritt (zwei Reiter im Weidetal)
 *  54.0–57.6 s  Outro (Feature-Chips + Logo + Musik-Credit)
 */

type Abschnitt = {
  at: number; // Startframe
  dur: number;
  el: React.ReactNode;
  flash?: boolean;
};

const MONTAGE_START = 42 * BEAT; // 25,2 s
const SLOT = 2 * BEAT; // 1,2 s pro Montage-Slot
const ZONEN_START = 72 * BEAT; // 43,2 s
const ZONEN_SLOT = BEAT; // 0,6 s pro Zonen-Shot

/**
 * Spiel-Canvas der Querformat-Minigame-Aufnahmen: der MinigameHost rendert
 * das Spiel in dieses Teilrechteck des 1920×1080-Fensters (außenrum
 * Host-Chrome mit Sterne-Zähler/Pause) — im Trailer füllt das SPIEL das
 * Bild (Rect per Einzelbild-Vermessung, 2 px nach innen gezogen).
 */
const MG_RECT = {x: 2, y: 190, w: 1626, h: 750};

export const TRAILER_DURATION = 96 * BEAT; // 57,6 s = 3456 Frames

/** Neue-Zonen-Montage: [startFrom im Quellclip, Badge, Akzent]. */
const ZONEN: [number, string, string][] = [
  [100, 'Lavendelwiese', COLORS.pink],
  [280, 'Nebelmoor', COLORS.tealDark],
  [460, 'Turmruine', COLORS.gold],
  [640, 'Muschelbucht', COLORS.teal],
  [820, 'Apfelgarten', COLORS.pinkDark],
  [1000, 'Kornfeld', COLORS.yellow],
];

export const Trailer: React.FC = () => {
  const abschnitte: Abschnitt[] = [
    {at: 0, dur: 4 * BEAT, el: <TitleCard />},
    {
      at: 4 * BEAT,
      dur: 4 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/showcase.mp4"
          startFrom={60}
          durationInFrames={4 * BEAT}
          label="Alles neu — und ganz der Alte!"
          accent={COLORS.pink}
          zoomFrom={1.08}
          zoomTo={1.18}
        />
      ),
    },
    // ---- NEU: Emotions-Nahaufnahme (Schreck, dann Verliebtheit) ----
    {
      at: 8 * BEAT,
      dur: 2 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/emotion.mp4"
          startFrom={56}
          durationInFrames={2 * BEAT}
          label="Neu: 12 große Gefühle"
          accent={COLORS.teal}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 10 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/emotion.mp4"
          startFrom={330}
          durationInFrames={2 * BEAT}
          zoomTo={1.06}
        >
          <MontageBadge text="… mit Herz!" accent={COLORS.pink} />
        </ClipScene>
      ),
    },
    {
      at: 12 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/home_room.mp4"
          startFrom={60}
          durationInFrames={3 * BEAT}
          label="Dein Zuhause — mit echten Möbeln"
          accent={COLORS.teal}
          zoomTo={1.06}
        />
      ),
    },
    {
      at: 15 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/home_build.mp4"
          startFrom={150}
          durationInFrames={2 * BEAT}
          label="Bau um, was du willst …"
          accent={COLORS.teal}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 17 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/home_build.mp4"
          startFrom={500}
          durationInFrames={2 * BEAT}
          label="… mitten in deiner Nachbarschaft"
          accent={COLORS.gold}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 19 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/home_style.mp4"
          startFrom={84}
          durationInFrames={3 * BEAT}
          label="… und gestalte dein ganzes Haus"
          accent={COLORS.pink}
          zoomTo={1.03}
        />
      ),
    },
    // ---- NEU: Das eigene Haus steht im Garten ----
    {
      at: 22 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/haus_garten.mp4"
          startFrom={324}
          durationInFrames={3 * BEAT}
          label="Neu: Dein Haus steht im Garten"
          accent={COLORS.gold}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 25 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/ikea.mp4"
          startFrom={100}
          durationInFrames={2 * BEAT}
          label="Möbel shoppen im GOUHBUS"
          accent={COLORS.yellow}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 27 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/wardrobe.mp4"
          startFrom={70}
          durationInFrames={3 * BEAT}
          label="93 Kosmetik-Teile für deinen Gooby"
          accent={COLORS.pink}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 30 * BEAT,
      dur: 2 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/city_overview.mp4"
          startFrom={60}
          durationInFrames={2 * BEAT}
          label="Eine lebendige Stadt"
          accent={COLORS.teal}
          zoomTo={1.0}
        />
      ),
    },
    {
      at: 32 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/city_day.mp4"
          startFrom={340}
          durationInFrames={3 * BEAT}
          label="Steig ein und fahr los"
          accent={COLORS.gold}
          zoomTo={1.03}
        />
      ),
    },
    {
      at: 35 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/city_night.mp4"
          startFrom={240}
          durationInFrames={2 * BEAT}
          label="… auch nachts"
          accent={COLORS.pinkDark}
          zoomTo={1.04}
        />
      ),
    },
    // ---- NEU: Funkelpark (Totale, dann Achterbahn-POV) ----
    {
      at: 37 * BEAT,
      dur: 2 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/funkelpark.mp4"
          startFrom={36}
          durationInFrames={2 * BEAT}
          label="Neu: der Funkelpark!"
          accent={COLORS.pink}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 39 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/funkelpark.mp4"
          startFrom={500}
          durationInFrames={3 * BEAT}
          zoomTo={1.05}
        >
          <MontageBadge text="Achterbahn-POV" accent={COLORS.teal} />
        </ClipScene>
      ),
    },
    // ---- Minispiel-Montage (Beat-Schnitte) ----
    {
      at: MONTAGE_START,
      dur: SLOT,
      flash: true,
      el: (
        <ClipScene
          src="clips/mg_toy_racer.mp4"
          sourceRect={MG_RECT}
          startFrom={240}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="Toy Racer" accent={COLORS.pink} />
        </ClipScene>
      ),
    },
    {
      at: MONTAGE_START + SLOT,
      dur: SLOT,
      el: (
        <ClipScene
          src="clips/mg_runner.mp4"
          sourceRect={MG_RECT}
          startFrom={300}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="Renner" accent={COLORS.teal} />
        </ClipScene>
      ),
    },
    {
      at: MONTAGE_START + 2 * SLOT,
      dur: SLOT,
      el: (
        <ClipScene
          src="clips/mg_goalie.mp4"
          sourceRect={MG_RECT}
          startFrom={280}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="Torwart-Gooby" accent={COLORS.gold} />
        </ClipScene>
      ),
    },
    {
      at: MONTAGE_START + 3 * SLOT,
      dur: SLOT,
      el: (
        <TrioScene
          clips={[
            {src: 'clips/mg_mini_golf.mp4', startFrom: 300},
            {src: 'clips/mg_fishing.mp4', startFrom: 320},
            {src: 'clips/mg_ghost_hunt.mp4', startFrom: 260},
          ]}
        />
      ),
    },
    {
      at: MONTAGE_START + 4 * SLOT,
      dur: SLOT,
      el: (
        <ClipScene
          src="clips/mg_gvz.mp4"
          sourceRect={MG_RECT}
          startFrom={420}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="GvZ" accent={COLORS.tealDark} />
        </ClipScene>
      ),
    },
    {
      at: MONTAGE_START + 5 * SLOT,
      dur: SLOT,
      el: (
        <ClipScene
          src="clips/mg_gobnom.mp4"
          sourceRect={MG_RECT}
          startFrom={300}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="GOB NOM" accent={COLORS.pinkDark} />
        </ClipScene>
      ),
    },
    {
      at: 54 * BEAT,
      dur: 2 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/visit.mp4"
          startFrom={200}
          durationInFrames={2 * BEAT}
          label="Multiplayer: Besucht euch!"
          accent={COLORS.pink}
          zoomTo={1.05}
        />
      ),
    },
    // ---- Kapitel GOOBY RANCH ----
    {at: 56 * BEAT, dur: 3 * BEAT, flash: true, el: <RanchCard />},
    {
      at: 59 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/ranch_fahrt.mp4"
          startFrom={500}
          durationInFrames={3 * BEAT}
          label="Fahr raus aufs Land …"
          accent={COLORS.gold}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 62 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch.mp4"
          startFrom={540}
          durationInFrames={3 * BEAT}
          label="… auf deine eigene Ranch!"
          accent={COLORS.gold}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 65 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch_ride.mp4"
          startFrom={240}
          durationInFrames={3 * BEAT}
          label="Reite hinaus in die offene Welt"
          accent={COLORS.teal}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 68 * BEAT,
      dur: 2 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/ranch_berge.mp4"
          startFrom={240}
          durationInFrames={2 * BEAT}
          label="Neu: das Bergmassiv"
          accent={COLORS.tealDark}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 70 * BEAT,
      dur: 2 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch_berge.mp4"
          startFrom={660}
          durationInFrames={2 * BEAT}
          label="… und oben wartet der Bergsee"
          accent={COLORS.teal}
          zoomTo={1.04}
        />
      ),
    },
    // ---- Neue-Zonen-Montage (6 × 1 Beat) ----
    ...ZONEN.map(([startFrom, badge, accent], i) => ({
      at: ZONEN_START + i * ZONEN_SLOT,
      dur: ZONEN_SLOT,
      flash: i === 0,
      el: (
        <ClipScene
          src="clips/ranch_zonen.mp4"
          startFrom={startFrom}
          durationInFrames={ZONEN_SLOT}
          zoomTo={1.03}
        >
          <MontageBadge text={badge} accent={accent} />
        </ClipScene>
      ),
    })),
    {
      at: 78 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch_wetter.mp4"
          startFrom={264}
          durationInFrames={3 * BEAT}
          label="7 Wetterlagen & Tageszeiten"
          accent={COLORS.gold}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 81 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch_dorf.mp4"
          startFrom={15}
          durationInFrames={3 * BEAT}
          label="Dorf Hufingen: Quests & NPCs"
          accent={COLORS.tealDark}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 84 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/ranch_comp.mp4"
          startFrom={525}
          durationInFrames={3 * BEAT}
          label="Gewinne Turniere — steig in der Liga auf!"
          accent={COLORS.pink}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 87 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/ranch_mp.mp4"
          startFrom={400}
          durationInFrames={3 * BEAT}
          label="Gemeinsame Ausritte & Rennen"
          accent={COLORS.teal}
          zoomTo={1.05}
        />
      ),
    },
    {at: 90 * BEAT, dur: 6 * BEAT, flash: true, el: <Outro />},
  ];

  return (
    <AbsoluteFill style={{backgroundColor: COLORS.cream}}>
      <Audio src={staticFile('audio/glitter_blast_cut576.m4a')} />
      {abschnitte.map((ab, i) => (
        <Sequence key={i} from={ab.at} durationInFrames={ab.dur}>
          {ab.el}
          {ab.flash ? <Flash /> : null}
        </Sequence>
      ))}
      {/* Montage-Dachzeile über allen Slots */}
      <Sequence from={MONTAGE_START} durationInFrames={6 * SLOT}>
        <MontageHeadline text="38 Minispiele — alle frisch poliert!" />
      </Sequence>
      {/* Dachzeile der Neue-Zonen-Montage */}
      <Sequence from={ZONEN_START} durationInFrames={6 * ZONEN_SLOT}>
        <MontageHeadline text="Sieben neue Zonen!" />
      </Sequence>
    </AbsoluteFill>
  );
};

const MontageHeadline: React.FC<{text: string}> = ({text}) => {
  return (
    <div
      style={{
        position: 'absolute',
        left: 64,
        bottom: 56,
        fontFamily: "'Baloo 2', sans-serif",
        fontWeight: 800,
        fontSize: 48,
        color: COLORS.brown,
        backgroundColor: COLORS.frost,
        borderRadius: 26,
        padding: '14px 36px 18px',
        boxShadow: '0 10px 36px rgba(74, 59, 54, 0.28)',
      }}
    >
      {text}
    </div>
  );
};
