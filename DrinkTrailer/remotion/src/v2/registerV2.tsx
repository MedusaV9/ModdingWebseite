/**
 * Registers one Remotion composition per available v2 style:
 *   EarlyV2-{NN}-{slug-with-dashes}   (1080x1920 @ 60fps)
 *
 * (Remotion IDs only allow [a-zA-Z0-9-], so slug underscores become dashes;
 * rendered files keep underscores — see scripts/render-v2.mjs.)
 *
 * Hooked into src/Root.tsx via {registerV2()}.
 */
import React from 'react';
import {Composition} from 'remotion';
import {compositionId2, durationInFrames2, FPS2, HEIGHT2, WIDTH2} from './config/types';
import {TrailerFactory} from './factory/TrailerFactory';
import {V2_STYLES} from './styles';

export const registerV2 = (): React.ReactNode => (
  <>
    {V2_STYLES.map((config) => (
      <Composition
        key={config.slug}
        id={compositionId2(config)}
        component={TrailerFactory}
        durationInFrames={durationInFrames2(config)}
        fps={FPS2}
        width={WIDTH2}
        height={HEIGHT2}
        defaultProps={{config}}
      />
    ))}
  </>
);
