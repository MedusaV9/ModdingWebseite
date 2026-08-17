import {continueRender, delayRender, staticFile} from 'remotion';

let geladen = false;

/** Lädt Baloo 2 (Variable Font, OFL — liegt im Spiel unter assets/fonts). */
export const loadBaloo = (): void => {
  if (geladen || typeof document === 'undefined') {
    return;
  }
  geladen = true;
  const handle = delayRender('Baloo-2-Font laden');
  const font = new FontFace(
    'Baloo 2',
    `url(${staticFile('fonts/baloo2-latin-var.woff2')}) format('woff2')`,
    {weight: '400 800'},
  );
  font
    .load()
    .then(() => {
      document.fonts.add(font);
      continueRender(handle);
    })
    .catch(() => continueRender(handle));
};
