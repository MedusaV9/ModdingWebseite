import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { Link } from 'react-router-dom'

type GradientButtonProps = {
  children: ReactNode
  variant?: 'solid' | 'outline'
  className?: string
  /** Internal route path — renders a react-router <Link> instead of an <a>. */
  to?: string
} & AnchorHTMLAttributes<HTMLAnchorElement>

export default function GradientButton({
  children,
  variant = 'solid',
  className = '',
  to,
  ...rest
}: GradientButtonProps) {
  const base =
    'inline-block font-teko font-bold text-[1.2rem] uppercase leading-none tracking-wide pt-[13px] px-5 pb-2 transition duration-100 hover:brightness-110 hover:-translate-y-0.5 cursor-pointer select-none'

  const solid =
    'text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)]'

  const outline =
    'text-bap-pink bg-transparent border-2 border-bap-pink hover:bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] hover:text-white hover:border-transparent'

  const classes = `${base} ${variant === 'outline' ? outline : solid} ${className}`

  if (to) {
    return (
      <Link to={to} className={classes} {...rest}>
        {children}
      </Link>
    )
  }

  return (
    <a className={classes} {...rest}>
      {children}
    </a>
  )
}
