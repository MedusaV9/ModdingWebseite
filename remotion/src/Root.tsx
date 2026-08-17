import React from "react";
import { Composition } from "remotion";
import "./fonts";
import { HOWTO_FPS, HOWTO_FRAMES, HowToCard, stinkbananeProps, vierLianenProps } from "./HowToCard";
import { TRAILER_FPS, TRAILER_FRAMES, Trailer } from "./trailer/Trailer";
import { TUTORIALS } from "./tutorials";

export const Root: React.FC = () => (
  <>
    <Composition
      id="Trailer"
      component={Trailer}
      durationInFrames={TRAILER_FRAMES}
      fps={TRAILER_FPS}
      width={1920}
      height={1080}
    />
    <Composition
      id="TutorialVierLianen"
      component={HowToCard}
      durationInFrames={HOWTO_FRAMES}
      fps={HOWTO_FPS}
      width={1920}
      height={1080}
      defaultProps={vierLianenProps}
    />
    <Composition
      id="TutorialStinkbanane"
      component={HowToCard}
      durationInFrames={HOWTO_FRAMES}
      fps={HOWTO_FPS}
      width={1920}
      height={1080}
      defaultProps={stinkbananeProps}
    />
    {/* Tutorial-Rollout: alle weiteren Formate aus tutorials.ts (Props je
        Format aus der jeweiligen explainCard abgeleitet). */}
    {TUTORIALS.map((t) => (
      <Composition
        key={t.id}
        id={t.kompId}
        component={HowToCard}
        durationInFrames={HOWTO_FRAMES}
        fps={HOWTO_FPS}
        width={1920}
        height={1080}
        defaultProps={t.props}
      />
    ))}
  </>
);
