# Gameplay interaction fixes

The complete right sidebar uses terminal styling: a dark teal CRT frame, monospace turn/phase headings and instructions, and teal command buttons with purple primary actions and decision highlights. Navigation, Undo, combat and recipient-choice controls share the same styling, hover/focus states and readable disabled states.

The right-hand stack is presented as a CRT activity feed. Numbered entries show CAST, TRIGGER or ACTIVATE, the source and caster, wrapped effect text and target names. The next entry has an amber NEXT marker and blinking cursor; empty state shows SYSTEM IDLE. Entries keep their native stack IDs and remain stable through snapshots. Active decisions use the shared scrolling sidebar slot, and longer queues use the rail's available height.

Created tokens now carry artwork URLs resolved from Forge's token key, edition and collector number, including token URL-map overrides. `RuntimeArtwork` requests each distinct public token face once, tries alternative URLs, caches successful bytes in `user://runtime-art/` (also reads the legacy token cache), and registers decoded textures with the shared renderer. Existing card faces repaint on arrival without needing another game snapshot. Hidden and face-down token descriptors never trigger downloads; tokens cannot incorrectly fall back to an ordinary card with the same name. Verify actual downloading with `node client-godot/tools/live-check.mjs --render --scenario=tokens --token-online-images` (four Soldier tokens from Raise the Alarm plus Doubling Season).

Popup inspection artwork preserves its proportions even if a container allocates extra space. The selection gallery's right preview has fixed card proportions and reserves width when computing its page columns, including on resize; distribution-row previews also avoid vertical stretching. Rendered regression captures cover multi-row galleries at 1600×1000 and 1280×800, alongside async token repaint/deduplication/privacy checks.

The intended interaction policy is now: show decisions and effects that concern the local player; advance unrelated routine stack items automatically when that player has no legal response. Forge still creates, orders, responds to and resolves the real stack. This changes presentation and priority passing, not casting rules or resolution order.

| Interaction | Behavior |
| --- | --- |
| Opponent casts an ordinary creature/artifact and you have no response | Pass automatically; the routine item is omitted from the actionable rail while resolving. |
| You hold an affordable counterspell, free alternate-cost response, or usable activated ability | Keep the response window; **Let resolve** declines it. |
| You only have mana abilities, wrong-color mana, or an instant without legal targets | Those alone do not hold routine opponent actions. |
| Opponent draws, gains life, scries, surveils, creates tokens for themselves, or searches for a land | Proceed automatically with no local response. Actual engine choices still appear when required. |
| A known single-target effect concerns other players' cards/players/spells | No forced local popup; proceed automatically when there is no local response. Manual review remains available. |
| A spell targets you, your controlled/owned cards, or your spell | Retain attention and the response window. |
| Board wipes, broad effects such as opponent proliferate, unknown APIs or recipient definitions | Retain attention conservatively. |
| Targeting, mana payment, optional choices, sacrifice/discard, or pending draws | Always keep the actual decision; an automatic priority pass cannot answer it. |

`StackInteractionPolicy` classifies effects and every sub-ability. The bridge enables Forge's available-action scan on its game thread using per-controller overrides, with no persistent preference changes. The scanner accounts for timing, targets, alternate costs, available mana and non-mana activated abilities, and conservatively reports available actions if its budget expires. Snapshot construction only reads that result. Forge's generic yield suggestions and unconditional no-actions yielding are disabled for this bridge controller so they cannot bypass the local-impact policy. Existing automation for your own routine actions remains.

Native scenario checks cover normal creatures, invalid targets, wrong-color mana, Counterspell actually countering a creature, activated responses, free responses, Manifold Insights, token/life/damage trigger chains, and protection against a board wipe. These are local bridge matches against AI; a multiplayer human lobby has not been exercised here.

Right-rail decisions such as Proliferate replace the underlying stack list and duplicate native prompt/OK/Mine controls while active. The stack attention outline follows the decision's outer panel rather than drawing the covered stack item's rectangle over its instructions and preview. The pulse uses an outline without a content tint. Source-card previews reserve an eight-pixel margin for their rendered edges. The shared behavior also applies to attacker/blocker decisions; decisions outside the rail retain the ordinary stack cue. Rendered regression checks cover the Atraxa source, wrapped instructions, preview/action spacing and pulse routing; a real Contentious Plan scenario verifies native Proliferate selections and resulting counters.

The follow-up interaction pass fixes revealed-card browsing to render card faces, including explicitly authorized reveals from private zones. Decision dialogs carry the resolving source card and readable printed rules; native card galleries also show that context. A real opponent-cast Manifold Insights fixture checks the reveal, source context, card choice and resulting caster hand count.

Ability rows now fill the popup width. Tap-only mana abilities omit the redundant tap cost and submit the selected mana with one click; mixed abilities retain their additional costs and ordinary confirmation. Optional native card selections expose **Choose none**, including Forge's cancel-based optional one-card inputs. Empty legal board selections use the same clear label.

Combat snapshots include Forge's persistent `blocked` state and trample keyword. When a declared blocker leaves combat, a blocked nontrampling attacker no longer gains a misleading arrow to the defending player. Targeted-effect popups use larger, equally sized source/target cards with a short adjacent arrow. Tests cover absent blockers, trample, reveal faces, full-width abilities, exact mana indices, duplicate-submit prevention and optional declines.

The October 25 cleanup addresses these reported behaviors:

- After attackers are declared, the primary action reads **Continue to blockers** when attacks exist, **Continue to main 2** when no attackers were declared, or **Resolve combat effects** when something is on the stack. The heading and instructions also reflect an empty combat. Forge still provides the legal instant/ability response window; selecting attackers remains a separate input.
- Individual tri-land mana choices describe only the color that option produces, while preserving costs and any additional effects.
- Counter badges translate Forge's `P1P1` notation to `+1/+1`, including other signed power/toughness variants.
- Proliferate uses highlighted battlefield cards and eligible player portraits. Native Forge inputs submit clicks immediately; bulk callback decisions collect selections until final confirmation. The own-permanents shortcut remains available.
- Provisional blocker assignments reach snapshots before the declaration is committed. Click an attacker and a blocker, repeat for other attackers, and confirm once. Clicking an assigned blocker again removes that assignment.
- Main menu, end-game, and quit confirmations use the themed game overlay. Returning to the menu retains the running match and the resume-disk behavior.
- Carousel selection synchronizes the monitor's deck dropdown/name.
- Equipment and Auras stack behind their actual host with individually exposed edges. Attachment metadata distinguishes card hosts from player hosts; detachment restores independent placement.
- Decision galleries and affected-card notices use explicit pages instead of scrollbars. Long rules/messages have text pages that preserve the full content and explicit line breaks.

Validation includes 175 Java bridge checks, the Godot UI regression suite, rendered popup checks, and real Forge/Godot scenarios for tri-land mana, proliferate with counter replacement effects, multiple blockers, Aura combat, and multiple Equipment followed by Unsummon. The application integration covers carousel selection, styled leave confirmation, retained match/resume, fresh restart, and process cleanup.

Reproduce the focused scenarios with `node client-godot/tools/live-check.mjs --scenario=blocking --render`, replacing `blocking` with `triland`, `proliferate`, `combat`, or `equipment`. Run UI checks with `./client-godot/tools/run.ps1 -Check` and rendered checks with `-Capture`. These tests exercise the reported paths; they do not exhaust every Magic card combination.
