/**
 * KILL CONTRACTS ("Blutvertrag", IDEA-20): daily hunter→target contracts with a 30-minute
 * real-time window, the one deliberate anonymity breach (the target's REAL face is shown to
 * the hunter, X-marked, name never), armor blackout while the window runs, wrong-kill
 * justice (Blutschuld/Vergeltung), a PRANK variant where everyone is told "you are hunted"
 * and nobody is, and a per-day advantage/disadvantage ledger that expires at rollover.
 *
 * <ul>
 *   <li>{@link dev.projecteclipse.eclipse.contracts.ContractService} — the crash-safe state
 *       machine (IDLE → SCHEDULED → ANNOUNCED → ACTIVE → resolved back to IDLE).</li>
 *   <li>{@link dev.projecteclipse.eclipse.contracts.ContractState} — SavedData
 *       ({@code data/eclipse_contracts.dat}).</li>
 *   <li>{@link dev.projecteclipse.eclipse.contracts.ContractConfig} —
 *       {@code config/eclipse/contracts.json}, hot-reloaded by {@code /dev reload}.</li>
 *   <li>{@link dev.projecteclipse.eclipse.contracts.ContractModifierService} — per-day,
 *       per-player timed modifiers (outgoing damage, grudge, temp hearts, secret skills
 *       multiplier, award-void); hard invariant: NEVER touches permanent LIVES.</li>
 * </ul>
 *
 * <p>Client counterpart: {@code client/contracts/}; wire transport:
 * {@code network/contracts/ContractPayloads}. Ops surface:
 * {@code devtools/dev/DevContractCommands} ({@code /dev contract ...}).</p>
 */
package dev.projecteclipse.eclipse.contracts;
