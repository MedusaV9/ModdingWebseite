import React from 'react';
import {Composition} from 'remotion';
import {Trailer, TRAILER_DURATION} from './Trailer';

export const Root: React.FC = () => {
  return (
    <Composition
      id="Trailer"
      component={Trailer}
      durationInFrames={TRAILER_DURATION}
      fps={60}
      width={1920}
      height={1080}
    />
  );
};
