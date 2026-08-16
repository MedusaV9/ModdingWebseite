/**
 * Music + SFX layer of the hype trailers, timed to the hype_track beat grid.
 * Balanced so SFX sit under the music: music ~0.84, impacts 0.8, riser 0.62,
 * whooshes ≤0.42, ticks ≤0.3 — no layer runs at 1.0 to avoid clipping when
 * hits stack on the drops.
 */
import React from 'react';
import {Sequence, interpolate} from 'remotion';
import {MusicTrack, Sfx} from '../shared/SmartMedia';
import {B, BREAK, DROP1, DROP2, OUTRO, RISER_FRAMES} from './timeline';

type Cue = {name: string; frame: number; volume: number};

const CUES: Cue[] = [
  // Iconic can-open at the very first frame.
  {name: 'fizz_open', frame: 0, volume: 0.7},

  // Countdown ticks 3 → 2 → 1 with whoosh transitions during the tease.
  {name: 'ui_tick', frame: B(4), volume: 0.3},
  {name: 'whoosh_1', frame: B(4), volume: 0.4},
  {name: 'ui_tick', frame: B(8), volume: 0.3},
  {name: 'whoosh_2', frame: B(8), volume: 0.4},
  {name: 'ui_tick', frame: B(12), volume: 0.3},
  {name: 'whoosh_1', frame: B(12), volume: 0.4},

  // Riser into drop 1, impact on the hit.
  {name: 'riser_short', frame: DROP1 - RISER_FRAMES, volume: 0.62},
  {name: 'impact_1', frame: DROP1, volume: 0.8},

  // Drop-1 montage transitions (every 4-beat chapter, ticks on the 2-beat run).
  {name: 'whoosh_2', frame: B(20), volume: 0.38},
  {name: 'whoosh_1', frame: B(24), volume: 0.38},
  {name: 'whoosh_2', frame: B(28), volume: 0.38},
  {name: 'whoosh_3', frame: B(32), volume: 0.42},
  {name: 'whoosh_1', frame: B(36), volume: 0.38},
  {name: 'whoosh_2', frame: B(40), volume: 0.38},
  {name: 'ui_tick', frame: B(42), volume: 0.28},
  {name: 'ui_tick', frame: B(44), volume: 0.28},
  {name: 'ui_tick', frame: B(46), volume: 0.28},

  // Into the break: one long whoosh, one soft mid-break transition.
  {name: 'whoosh_3', frame: BREAK, volume: 0.48},
  {name: 'whoosh_2', frame: B(56), volume: 0.32},

  // Riser into drop 2, harder impact on the hit.
  {name: 'riser_short', frame: DROP2 - RISER_FRAMES, volume: 0.62},
  {name: 'impact_2', frame: DROP2, volume: 0.8},

  // Drop-2 montage: whooshes on the 2-beat cuts, tick strobe on 1-beat cuts.
  {name: 'whoosh_1', frame: B(68), volume: 0.36},
  {name: 'whoosh_2', frame: B(72), volume: 0.36},
  {name: 'whoosh_1', frame: B(76), volume: 0.36},
  ...new Array(8).fill(0).map((_, i) => ({
    name: 'ui_tick',
    frame: B(80 + i),
    volume: 0.26,
  })),
  // EARLY letter-slam finale.
  {name: 'impact_2', frame: B(88), volume: 0.5},

  // Outro: whoosh into the endcard, sparkle on the logo reveal.
  {name: 'whoosh_3', frame: OUTRO, volume: 0.48},
  {name: 'sparkle_pop', frame: OUTRO + 24, volume: 0.7},
];

export const HypeAudio: React.FC = () => (
  <>
    <MusicTrack
      trailerStyle="hype"
      volume={(f) =>
        interpolate(f, [0, 10, OUTRO, OUTRO + 30], [0.7, 0.84, 0.84, 0.72], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        })
      }
    />
    {CUES.map((cue, i) => (
      <Sequence key={`${cue.name}-${i}`} from={cue.frame} name={`sfx:${cue.name}`}>
        <Sfx name={cue.name} volume={cue.volume} />
      </Sequence>
    ))}
  </>
);
