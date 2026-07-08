// The 28 `visual.preset` tokens the launcher supports for BAPHub cards.
// Order matters: the gallery renders swatches in exactly this sequence.
// Effect styling lives in src/index.css as `.fx-<id>` classes; localized
// one-liners live in t.modders.gallery.descriptions keyed by PresetId.
export type PresetId =
  | 'default'
  | 'featured'
  | 'shiny'
  | 'holo'
  | 'neon'
  | 'frost'
  | 'ember'
  | 'prism'
  | 'glitch'
  | 'aurora'
  | 'frozen'
  | 'plasma'
  | 'toxic'
  | 'cosmic'
  | 'vapor'
  | 'storm'
  | 'inferno'
  | 'velvet'
  | 'matrix'
  | 'ghost'
  | 'crystal'
  | 'chrome'
  | 'noir'
  | 'sunset'
  | 'void'
  | 'candy'
  | 'dev'
  | 'event'

export const PRESETS: { id: PresetId }[] = [
  { id: 'default' },
  { id: 'featured' },
  { id: 'shiny' },
  { id: 'holo' },
  { id: 'neon' },
  { id: 'frost' },
  { id: 'ember' },
  { id: 'prism' },
  { id: 'glitch' },
  { id: 'aurora' },
  { id: 'frozen' },
  { id: 'plasma' },
  { id: 'toxic' },
  { id: 'cosmic' },
  { id: 'vapor' },
  { id: 'storm' },
  { id: 'inferno' },
  { id: 'velvet' },
  { id: 'matrix' },
  { id: 'ghost' },
  { id: 'crystal' },
  { id: 'chrome' },
  { id: 'noir' },
  { id: 'sunset' },
  { id: 'void' },
  { id: 'candy' },
  { id: 'dev' },
  { id: 'event' },
]
