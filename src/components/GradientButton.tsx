import type { AnchorHTMLAttributes, ReactNode } from 'react'

type GradientButtonProps = {
  children: ReactNode
  variant?: 'solid' | 'outline'
  className?: string
} & AnchorHTMLAttributes<HTMLAnchorElement>

export default function GradientButton({
  children,
  variant = 'solid',
  className = '',
  ...rest
}: GradientButtonProps) {
  const base =
    'inline-block font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[13px] px-5 pb-2 transition duration-100 hover:brightness-110 hover:-translate-y-0.5 cursor-pointer select-none'

  const solid =
    'text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]'

  const outline =
    'text-bap-pink bg-transparent border-2 border-bap-pink hover:bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] hover:text-white hover:border-transparent'

  return (
    <a
      className={`${base} ${variant === 'outline' ? outline : solid} ${className}`}
      {...rest}
    >
      {children}
    </a>
  )
}
