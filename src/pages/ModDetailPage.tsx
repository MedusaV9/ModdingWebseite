import { useParams } from 'react-router-dom'
import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageTitle from '../hooks/usePageTitle'

export default function ModDetailPage() {
  const { id } = useParams<'id'>()
  usePageTitle('Mod Details')

  return (
    <section className="mx-auto max-w-7xl px-4 py-20 md:px-6">
      <SectionHeading
        eyebrow="COMING SOON"
        title="MOD DETAILS"
        subtitle={`A detail page for “${id ?? 'unknown'}” is under construction.`}
      />
      <div className="mt-8">
        <GradientButton to="/">BACK TO HOME</GradientButton>
      </div>
    </section>
  )
}
