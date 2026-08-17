import {
  Box, Swords, Target, Trees, Mountain, Pickaxe, Ship, Rocket, Castle, Skull, Car, Plane,
  Gamepad2, Globe, Tent, Anchor, Bug, Zap, Shield, Crosshair, Footprints, Radiation,
  Network, Download, Wrench, FlaskConical, Server, Cpu, Joystick,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

const ICONS: Record<string, LucideIcon> = {
  'box': Box, 'swords': Swords, 'target': Target, 'trees': Trees, 'mountain': Mountain,
  'pickaxe': Pickaxe, 'ship': Ship, 'rocket': Rocket, 'castle': Castle, 'skull': Skull,
  'car': Car, 'plane': Plane, 'gamepad-2': Gamepad2, 'globe': Globe, 'tent': Tent,
  'anchor': Anchor, 'bug': Bug, 'zap': Zap, 'shield': Shield, 'crosshair': Crosshair,
  'footprints': Footprints, 'radiation': Radiation, 'network': Network, 'download': Download,
  'wrench': Wrench, 'flask': FlaskConical, 'server': Server, 'cpu': Cpu, 'joystick': Joystick,
}

export function GameIcon({ icon, color, size = 18, boxed = false }: { icon?: string; color?: string; size?: number; boxed?: boolean }) {
  const Icon = ICONS[icon ?? 'server'] ?? Server
  if (!boxed) return <Icon size={size} style={color ? { color } : undefined} />
  return (
    // Soft glass tile: blueprint-color tint (color-mix off currentColor) with a
    // gentle vertical falloff + the shared specular top edge (.sheen).
    <span
      className="sheen inline-flex shrink-0 items-center justify-center rounded-xl border"
      style={{
        width: size + 14,
        height: size + 14,
        color: color ?? 'var(--t-accent)',
        borderColor: 'color-mix(in oklab, currentColor 32%, transparent)',
        background:
          'linear-gradient(180deg, color-mix(in oklab, currentColor 16%, transparent), color-mix(in oklab, currentColor 9%, transparent))',
      }}
    >
      <Icon size={size} />
    </span>
  )
}
