import React from 'react';
import {AbsoluteFill, Audio, Sequence, staticFile} from 'remotion';
import {ClipScene} from './components/ClipScene';
import {Flash} from './components/Flash';
import {MontageBadge} from './components/MontageBadge';
import {Outro} from './components/Outro';
import {TitleCard} from './components/TitleCard';
import {TrioScene} from './components/TrioScene';
import {loadBaloo} from './load-font';
import {BEAT, COLORS} from './theme';

loadBaloo();

/**
 * Fahrplan (60 fps, Beat = 36 Frames bei 100 BPM — alle Schnitte liegen auf
 * Beat-Vielfachen):
 *
 *   0.0– 3.0 s  Titelkarte „GOOBY 5.0 — Das Godot-Engine-Update“
 *   3.0– 7.2 s  Neuer 3D-Gooby (Showcase) — „Alles neu. Alles in 3D.“
 *   7.2– 9.6 s  Zuhause (Wohnzimmer, lebender Gooby)
 *   9.6–13.2 s  Baumodus (Bett aus dem Lager + Hammer-Gag)
 *  13.2–15.0 s  GOUHBUS-Möbelausstellung („IKEA“)
 *  15.0–16.8 s  Garderobe (Outfits am lebenden Gooby)
 *  16.8–18.6 s  Stadt-Panorama (goldene Stunde)
 *  18.6–20.4 s  Autofahrt am Tag (Ausparken/Verkehr)
 *  20.4–21.6 s  Stadt bei Nacht (Scheinwerfer)
 *  21.6–28.8 s  Minispiel-Montage im Beat (6 Slots à 1,2 s)
 *  28.8–31.2 s  Multiplayer-Besuch (zwei Goobys)
 *  31.2–33.6 s  Ranch-Teaser (Gooby-Pferde im Galopp)
 *  33.6–37.2 s  Outro (Feature-Chips + Logo + Credit)
 */

type Abschnitt = {
  at: number; // Startframe
  dur: number;
  el: React.ReactNode;
  flash?: boolean;
};

const MONTAGE_START = 36 * BEAT; // 21,6 s
const SLOT = 2 * BEAT; // 1,2 s pro Montage-Slot

export const TRAILER_DURATION = 62 * BEAT; // 37,2 s = 2232 Frames

export const Trailer: React.FC = () => {
  const abschnitte: Abschnitt[] = [
    {at: 0, dur: 5 * BEAT, el: <TitleCard />},
    {
      at: 5 * BEAT,
      dur: 7 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/showcase.mp4"
          startFrom={30}
          durationInFrames={7 * BEAT}
          label="Alles neu. Alles in 3D."
          accent={COLORS.pink}
          zoomFrom={1.0}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 12 * BEAT,
      dur: 4 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/home_room.mp4"
          startFrom={60}
          durationInFrames={4 * BEAT}
          label="Dein Zuhause …"
          accent={COLORS.teal}
          zoomTo={1.06}
        />
      ),
    },
    {
      at: 16 * BEAT,
      dur: 6 * BEAT,
      el: (
        <ClipScene
          src="clips/home_build.mp4"
          startFrom={90}
          durationInFrames={6 * BEAT}
          label="… mit echtem Baumodus"
          accent={COLORS.teal}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 22 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/ikea.mp4"
          startFrom={100}
          durationInFrames={3 * BEAT}
          label="Möbel shoppen im GOUHBUS"
          accent={COLORS.yellow}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 25 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/wardrobe.mp4"
          startFrom={70}
          durationInFrames={3 * BEAT}
          label="Outfits für deinen Gooby"
          accent={COLORS.pink}
          zoomTo={1.04}
        />
      ),
    },
    {
      at: 28 * BEAT,
      dur: 3 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/city_overview.mp4"
          startFrom={60}
          durationInFrames={3 * BEAT}
          label="Eine lebendige Stadt"
          accent={COLORS.teal}
          zoomTo={1.0}
        />
      ),
    },
    {
      at: 31 * BEAT,
      dur: 3 * BEAT,
      el: (
        <ClipScene
          src="clips/city_day.mp4"
          startFrom={300}
          durationInFrames={3 * BEAT}
          label="Steig ein und fahr los"
          accent={COLORS.gold}
          zoomTo={1.03}
        />
      ),
    },
    {
      at: 34 * BEAT,
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
    // ---- Minispiel-Montage (Beat-Schnitte) ----
    {
      at: MONTAGE_START,
      dur: SLOT,
      flash: true,
      el: (
        <ClipScene
          src="clips/mg_toy_racer.mp4"
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
          startFrom={300}
          durationInFrames={SLOT}
          zoomTo={1.05}
        >
          <MontageBadge text="GOB NOM" accent={COLORS.pinkDark} />
        </ClipScene>
      ),
    },
    {
      at: 48 * BEAT,
      dur: 4 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/visit.mp4"
          startFrom={200}
          durationInFrames={4 * BEAT}
          label="Besucht euch gegenseitig!"
          accent={COLORS.pink}
          zoomTo={1.05}
        />
      ),
    },
    {
      at: 52 * BEAT,
      dur: 4 * BEAT,
      flash: true,
      el: (
        <ClipScene
          src="clips/ranch.mp4"
          startFrom={330}
          durationInFrames={4 * BEAT}
          label="NEU: Die Gooby Ranch"
          accent={COLORS.gold}
          zoomTo={1.05}
        />
      ),
    },
    {at: 56 * BEAT, dur: 6 * BEAT, flash: true, el: <Outro />},
  ];

  return (
    <AbsoluteFill style={{backgroundColor: COLORS.cream}}>
      <Audio src={staticFile('audio/glitter_blast_cut.m4a')} />
      {abschnitte.map((ab, i) => (
        <Sequence key={i} from={ab.at} durationInFrames={ab.dur}>
          {ab.el}
          {ab.flash ? <Flash /> : null}
        </Sequence>
      ))}
      {/* Montage-Dachzeile über allen Slots */}
      <Sequence from={MONTAGE_START} durationInFrames={6 * SLOT}>
        <MontageHeadline />
      </Sequence>
    </AbsoluteFill>
  );
};

const MontageHeadline: React.FC = () => {
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
      Über 30 Minispiele!
    </div>
  );
};
