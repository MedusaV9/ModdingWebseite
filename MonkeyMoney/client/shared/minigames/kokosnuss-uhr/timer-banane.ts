// Die Timer-Banane ist zum gemeinsamen Baustein aufgestiegen (client/shared/ui.ts,
// dort heißt sie timerBalken und ersetzt überall den nackten Balken).
// Dieser Re-Export hält die bestehenden Minigame-Importe stabil.
export { timerBalken as timerBanane } from "../../ui";
