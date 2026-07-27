import React from 'react';
import {Composition} from 'remotion';
import {EclipseTrailer} from './EclipseTrailer';

export const Root: React.FC = () => {
  return (
    <Composition
      id="EclipseTrailer"
      component={EclipseTrailer}
      durationInFrames={1800}
      fps={60}
      width={3840}
      height={2160}
    />
  );
};
