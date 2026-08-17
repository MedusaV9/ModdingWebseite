import React from 'react';
import type {ReactNode} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

type InfiniteZoomProps = {
  /** Scenes zoomed through, in order. */
  layers: ReactNode[];
  /** Frames spent per zoom level. */
  framesPerLayer: number;
  /**
   * Relative size of the embedded next scene (0.3 = next scene occupies 30%
   * of the width, i.e. zoom factor ≈ 3.33 per level).
   */
  windowScale?: number;
  /** Frame color drawn around embedded scenes. */
  frameColor?: string;
};

/**
 * Scene-in-scene infinite zoom: each layer contains the next one shrunk in a
 * framed window at its center; the camera zooms continuously so the window
 * grows to fill the screen, then the cycle repeats with the next pair.
 */
export const InfiniteZoom: React.FC<InfiniteZoomProps> = ({
  layers,
  framesPerLayer,
  windowScale = 0.34,
  frameColor = '#ffffff',
}) => {
  const frame = useCurrentFrame();
  const S = 1 / windowScale;

  const t = frame / Math.max(1, framesPerLayer);
  const current = Math.min(layers.length - 1, Math.floor(t));
  const localEased = Easing.inOut(Easing.quad)(Math.min(1, t - current));
  const zoom = interpolate(localEased, [0, 1], [1, S]);

  const renderLayer = (index: number, scale: number, withFrame: boolean) => {
    if (index >= layers.length) return null;
    return (
      <AbsoluteFill
        key={index}
        style={{
          transform: `scale(${scale})`,
          border: withFrame ? `${6 / Math.max(0.4, scale)}px solid ${frameColor}` : undefined,
          boxShadow: withFrame ? '0 0 120px rgba(0,0,0,0.55)' : undefined,
          overflow: 'hidden',
          backgroundColor: '#000',
        }}
      >
        {layers[index]}
      </AbsoluteFill>
    );
  };

  return (
    <AbsoluteFill style={{backgroundColor: '#000', overflow: 'hidden'}}>
      {/* Outgoing layer blows up past the viewport. */}
      {renderLayer(current, zoom, false)}
      {/* Incoming layer sits in the framed window and grows to fullscreen. */}
      {renderLayer(current + 1, zoom * windowScale, true)}
      {/* Peek of the layer after that, deep inside. */}
      {renderLayer(current + 2, zoom * windowScale * windowScale, true)}
    </AbsoluteFill>
  );
};
