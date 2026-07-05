import GradientButton from '../components/GradientButton'
import SectionHeading from '../components/SectionHeading'
import usePageTitle from '../hooks/usePageTitle'

export default function ModdersPage() {
  usePageTitle('For Modders')

  return (
    <section className="mx-auto max-w-7xl px-4 py-20 md:px-6">
      <SectionHeading
        eyebrow="COMING SOON"
        title="FOR MODDERS"
        subtitle="Resources for building and publishing your own BAPBAP mods are under construction."
      />
      <div className="mt-8">
        <GradientButton to="/">BACK TO HOME</GradientButton>
      </div>
    </section>
  )
}
