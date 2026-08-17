export interface Theme {
  id: string
  name: string
  dark: boolean
  vars: Record<string, string>
}

const base = {
  '--t-success': '#22c55e',
  '--t-warn': '#f59e0b',
  '--t-danger': '#ef4444',
  '--t-on-accent': '#ffffff',
}

export const THEMES: Theme[] = [
  {
    id: 'between-dark',
    name: 'Between Dark',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#0b0d14',
      '--t-surface': '#12151f',
      '--t-elevated': '#191d2b',
      '--t-line': '#262b3d',
      '--t-text': '#e8eaf2',
      '--t-muted': '#8b91a7',
      '--t-accent': '#6366f1',
      '--t-accent2': '#a855f7',
    },
  },
  {
    id: 'midnight',
    name: 'Midnight Ocean',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#060b16',
      '--t-surface': '#0b1322',
      '--t-elevated': '#101b30',
      '--t-line': '#1d2b45',
      '--t-text': '#e3edf9',
      '--t-muted': '#7e93b3',
      '--t-accent': '#0ea5e9',
      '--t-accent2': '#22d3ee',
    },
  },
  {
    id: 'aurora',
    name: 'Aurora',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#071210',
      '--t-surface': '#0c1a17',
      '--t-elevated': '#112420',
      '--t-line': '#1e352f',
      '--t-text': '#e6f5ef',
      '--t-muted': '#84a89b',
      '--t-accent': '#10b981',
      '--t-accent2': '#34d399',
    },
  },
  {
    id: 'crimson',
    name: 'Crimson Ops',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#120a0c',
      '--t-surface': '#1a1013',
      '--t-elevated': '#241419',
      '--t-line': '#3a2129',
      '--t-text': '#f5e8ec',
      '--t-muted': '#a98b95',
      '--t-accent': '#ef4444',
      '--t-accent2': '#f97316',
    },
  },
  {
    id: 'synthwave',
    name: 'Synthwave',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#0e0618',
      '--t-surface': '#160b24',
      '--t-elevated': '#1f1032',
      '--t-line': '#33204f',
      '--t-text': '#f3e9ff',
      '--t-muted': '#a78fc7',
      '--t-accent': '#e879f9',
      '--t-accent2': '#8b5cf6',
    },
  },
  {
    id: 'slate-light',
    name: 'Daylight',
    dark: false,
    vars: {
      ...base,
      '--t-bg': '#f4f6fb',
      '--t-surface': '#ffffff',
      '--t-elevated': '#eef1f8',
      '--t-line': '#d8deeb',
      '--t-text': '#141a2a',
      '--t-muted': '#5d6880',
      '--t-accent': '#4f46e5',
      '--t-accent2': '#7c3aed',
      // The vivid base status tokens measure ~2:1 as text on these light
      // surfaces (WCAG fail). These darker variants stay ≥4.5:1 against
      // --t-surface, --t-bg AND --t-elevated; as low-alpha tints
      // (bg-success/15 etc.) they read the same as the vivid ones.
      '--t-success': '#147a3a',
      '--t-warn': '#ac4f08',
      '--t-danger': '#b91c1c',
    },
  },
  {
    id: 'carbon',
    name: 'Carbon Contrast',
    dark: true,
    vars: {
      ...base,
      '--t-bg': '#000000',
      '--t-surface': '#0c0c0c',
      '--t-elevated': '#161616',
      '--t-line': '#2e2e2e',
      '--t-text': '#f5f5f5',
      '--t-muted': '#9e9e9e',
      '--t-accent': '#eab308',
      '--t-accent2': '#f59e0b',
      '--t-on-accent': '#111111',
      // Pure-black bg: lift the glass tint so panels stay legible over it.
      '--glass-tint': '#161616',
      '--glass-opacity': '70%',
    },
  },
]

export const ACCENTS: { id: string; accent: string; accent2: string }[] = [
  { id: 'indigo', accent: '#6366f1', accent2: '#a855f7' },
  { id: 'sky', accent: '#0ea5e9', accent2: '#22d3ee' },
  { id: 'emerald', accent: '#10b981', accent2: '#34d399' },
  { id: 'rose', accent: '#f43f5e', accent2: '#fb7185' },
  { id: 'amber', accent: '#f59e0b', accent2: '#fbbf24' },
  { id: 'fuchsia', accent: '#d946ef', accent2: '#a855f7' },
]

// Union of every var key any theme sets, so switching themes can clear
// per-theme extras (e.g. carbon's glass knobs) instead of leaking them.
const ALL_THEME_VARS = Array.from(new Set(THEMES.flatMap((t) => Object.keys(t.vars))))

export function applyTheme(themeId: string, accentId?: string | null) {
  const theme = THEMES.find((t) => t.id === themeId) ?? THEMES[0]
  const root = document.documentElement
  for (const key of ALL_THEME_VARS) {
    if (!(key in theme.vars)) root.style.removeProperty(key)
  }
  for (const [key, value] of Object.entries(theme.vars)) root.style.setProperty(key, value)
  if (accentId) {
    const accent = ACCENTS.find((a) => a.id === accentId)
    if (accent) {
      root.style.setProperty('--t-accent', accent.accent)
      root.style.setProperty('--t-accent2', accent.accent2)
    }
  }
  root.style.colorScheme = theme.dark ? 'dark' : 'light'
  // index.css keys the Liquid Glass knobs (highlight/opacity/shadows) off this.
  root.dataset.themeDark = String(theme.dark)
}
