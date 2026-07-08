# Asset drop-in folder

The site renders fine with this folder empty — all visuals are CSS gradients,
inline SVG, or remote images. Real art can be dropped in later using these
filenames (no code changes needed):

| File | Used for |
| --- | --- |
| `logo.svg` | Navbar logo (replaces the text wordmark) |
| `hero-art.png` | Hero section character art |
| `og-image.png` | Social preview image (Open Graph / Twitter card) |
| `icon-512.png` | PWA icon, 512×512 (`any` + `maskable` in the manifest) |
| `icon-192.png` | PWA icon, 192×192 |
| `apple-touch-icon.png` | iOS home-screen icon, 180×180 |
| `mods/<mod-id>.png` | Per-mod card image overrides (e.g. `mods/sonic.bapbap.hp-numbers.png`) |

## og-image.png

A default `og-image.png` (1200×630) is committed here. It is generated from
`scripts/og-template.html` via headless Chrome:

```sh
google-chrome --headless=new --screenshot=public/assets/og-image.png \
  --window-size=1200,630 --hide-scrollbars --virtual-time-budget=5000 \
  "file://$PWD/scripts/og-template.html"
```

Feel free to overwrite it with real art — nothing in the code references the
template at runtime.

## PWA icons (icon-512.png, icon-192.png, apple-touch-icon.png)

Generated from `scripts/icon-template.html` (bap-night background, centered
Emblem at ~62% for maskable-safe padding) via headless Chrome — same
convention as the og-image. On machines where the default Chrome profile is
locked by a running instance, pass `--user-data-dir`:

```sh
google-chrome --headless=old --no-sandbox --user-data-dir=/tmp/chrome-icons \
  --hide-scrollbars --window-size=512,512 \
  --screenshot=public/assets/icon-512.png "file://$PWD/scripts/icon-template.html"
google-chrome --headless=old --no-sandbox --user-data-dir=/tmp/chrome-icons \
  --hide-scrollbars --window-size=192,192 \
  --screenshot=public/assets/icon-192.png "file://$PWD/scripts/icon-template.html"
google-chrome --headless=old --no-sandbox --user-data-dir=/tmp/chrome-icons \
  --hide-scrollbars --window-size=180,180 \
  --screenshot=public/assets/apple-touch-icon.png "file://$PWD/scripts/icon-template.html"
```

The manifest (`public/manifest.webmanifest`) references the two `icon-*.png`
files; `index.html` links the apple-touch icon. Nothing references the
template at runtime.
