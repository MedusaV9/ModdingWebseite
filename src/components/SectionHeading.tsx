type SectionHeadingProps = {
  eyebrow: string
  title: string
  subtitle?: string
  className?: string
}

export default function SectionHeading({
  eyebrow,
  title,
  subtitle,
  className = '',
}: SectionHeadingProps) {
  return (
    <div className={`flex flex-col gap-2 ${className}`}>
      <span className="font-teko uppercase text-bap-pink tracking-widest text-lg leading-none">
        {eyebrow}
      </span>
      <h2 className="font-display uppercase text-4xl md:text-5xl text-white">
        {title}
      </h2>
      {subtitle && <p className="text-white/60 max-w-2xl">{subtitle}</p>}
    </div>
  )
}
