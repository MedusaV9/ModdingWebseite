import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { Link } from 'react-router-dom'

type GradientButtonProps = {
  children: ReactNode
  variant?: 'solid' | 'outline'
  size?: 'md' | 'lg'
  /** Rendered after the label, e.g. <Icon name="download" className="h-5 w-5" />. */
  icon?: ReactNode
  className?: string
  /** Internal route path — renders a react-router <Link> instead of an <a>. */
  to?: string
} & AnchorHTMLAttributes<HTMLAnchorElement>

const sizes = {
  md: 'text-[1.2rem] pt-[13px] px-5 pb-2',
  lg: 'text-[1.4rem] pt-[15px] px-7 pb-2.5',
}

export default function GradientButton({
  children,
  variant = 'solid',
  size = 'md',
  icon,
  className = '',
  to,
  ...rest
}: GradientButtonProps) {
  const base =
    'inline-block font-teko font-bold uppercase leading-none tracking-wide hover:-translate-y-0.5 cursor-pointer select-none'

  // Solid gets a hover gradient sweep: the gradient is twice the button width
  // and the background-position pans across it on hover.
  const solid =
    'text-white bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] bg-[length:200%_auto] bg-[position:0%_0%] hover:bg-[position:100%_0%] transition-[background-position,translate,filter] duration-150 hover:brightness-110'

  const outline =
    'text-bap-pink bg-transparent border-2 border-bap-pink hover:bg-[linear-gradient(to_left,#eb204f,#ff2a6d)] hover:text-white hover:border-transparent transition duration-100 hover:brightness-110'

  const classes = `${base} ${sizes[size]} ${
    variant === 'outline' ? outline : solid
  } ${className}`

  const content = (
    <>
      {children}
      {icon ? (
        <span className="ml-2 inline-block align-[-3px]">{icon}</span>
      ) : null}
    </>
  )

  if (to) {
    return (
      <Link to={to} className={classes} {...rest}>
        {content}
      </Link>
    )
  }

  return (
    <a className={classes} {...rest}>
      {content}
    </a>
  )
}
