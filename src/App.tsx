import Navbar from './components/Navbar'
import Footer from './components/Footer'
import Marquee from './components/Marquee'
import Hero from './sections/Hero'
import Mods from './sections/Mods'
import GameModes from './sections/GameModes'
import Launcher from './sections/Launcher'
import HowItWorks from './sections/HowItWorks'
import Community from './sections/Community'

export default function App() {
  return (
    <>
      <Navbar />
      <Marquee text="READY TO MOD?" />
      <main>
        <Hero />
        <Mods />
        <GameModes />
        <Launcher />
        <HowItWorks />
        <Community />
      </main>
      <Footer />
    </>
  )
}
