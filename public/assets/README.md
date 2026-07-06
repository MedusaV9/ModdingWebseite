# Asset drop-in folder

The site renders fine with this folder empty — all visuals are CSS gradients,
inline SVG, or remote images. Real art can be dropped in later using these
filenames (no code changes needed):

| File | Used for |
| --- | --- |
| `logo.svg` | Navbar logo (replaces the text wordmark) |
| `hero-art.png` | Hero section character art |
| `og-image.png` | Social preview image (Open Graph / Twitter card) |
| `mods/<mod-id>.png` | Per-mod card image overrides (e.g. `mods/nexus-hud.png`) |

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
