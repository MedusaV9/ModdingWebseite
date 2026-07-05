import type { ReactNode } from 'react'

type BadgeProps = {
  children: ReactNode
  tone?: 'pink' | 'amber' | 'neutral'
  className?: string
}

const toneClasses: Record<NonNullable<BadgeProps['tone']>, string> = {
  pink: 'text-bap-pink border-bap-pink/50 bg-bap-pink/10',
  amber: 'text-bap-amber border-bap-amber/50 bg-bap-amber/10',
  neutral: 'text-white/70 border-bap-line bg-white/5',
}

export default function Badge({ children, tone = 'neutral', className = '' }: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center gap-1 border font-teko uppercase tracking-wider text-sm leading-none pt-[5px] px-2 pb-[2px] ${toneClasses[tone]} ${className}`}
    >
      {children}
    </span>
  )
}
