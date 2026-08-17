import { Link } from 'react-router-dom'
import { Compass } from 'lucide-react'
import { useT } from '../i18n/index.tsx'
import { Button, Card } from '../components/ui.tsx'

export function NotFound() {
  const t = useT()
  return (
    <div className="flex items-center justify-center py-16 sm:py-24">
      <Card className="scale-in flex w-full max-w-md flex-col items-center px-8 py-12 text-center">
        <span className="glass-subtle mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl text-muted/60">
          <Compass size={26} />
        </span>
        <h1 className="text-gradient font-display text-7xl font-bold tracking-tight">404</h1>
        <p className="mt-3 text-sm leading-relaxed text-muted">{t('notfound.title')}</p>
        <Link to="/" className="mt-8">
          <Button variant="primary" size="md">{t('notfound.back')}</Button>
        </Link>
      </Card>
    </div>
  )
}
