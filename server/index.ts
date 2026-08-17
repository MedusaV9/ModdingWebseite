// Entry-Point: `node server/dist/index.js` (Release) bzw. `tsx server/index.ts` (Dev).
import { main } from "./core/index";

main().catch((err) => {
  console.error("Server-Start fehlgeschlagen:", err);
  process.exit(1);
});
