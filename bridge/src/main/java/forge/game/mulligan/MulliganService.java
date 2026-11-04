package forge.game.mulligan;

import forge.MulliganDefs;
import forge.StaticData;
import forge.game.Game;
import forge.game.GameType;
import forge.game.player.Player;
import java.util.*;
import java.util.concurrent.*;

/** Bridge-local compatibility override. Only decision collection is concurrent;
 * every keep, bottom, shuffle and redraw still executes on Forge's game thread. */
public class MulliganService {
    public interface Decisions {
        boolean supports(Player player);
        CompletableFuture<Boolean> request(Player player, Player first, int returnCount);
        void kept(Player player);
    }
    // A BridgeMain JVM owns exactly one match. Local games leave this unset.
    public static volatile Decisions onlineDecisions;
    private final Player firstPlayer;
    private final Game game;
    private final List<AbstractMulligan> mulligans = new ArrayList<>();

    public MulliganService(Player player) { firstPlayer = player; game = player.getGame(); }

    public void perform() {
        List<Player> order = new ArrayList<>(game.getPlayers());
        Collections.rotate(order, -order.indexOf(firstPlayer));
        boolean free = game.getPlayers().size() > 2 || game.getRules().hasAppliedVariant(GameType.Brawl);
        for (Player player : order) {
            AbstractMulligan mulligan = switch (StaticData.instance().getMulliganRule()) {
                case Original -> new OriginalMulligan(player, free);
                case Paris -> new ParisMulligan(player, free);
                case London -> new LondonMulligan(player, free);
                case Houston -> new HoustonMulligan(player, free);
                default -> new VancouverMulligan(player, free);
            };
            mulligans.add(mulligan);
            mulligan.beforeFirstMulligan();
        }
        if (onlineDecisions == null) runSequential();
        else runOnline(onlineDecisions);
        if (!game.isGameOver()) for (AbstractMulligan mulligan : mulligans) mulligan.afterMulligan();
    }

    private void runSequential() {
        boolean allKept;
        do {
            allKept = true;
            for (AbstractMulligan mulligan : mulligans) {
                if (mulligan.hasKept()) continue;
                boolean keep = !mulligan.canMulligan() || mulligan.getPlayer().getController()
                        .mulliganKeepHand(firstPlayer, mulligan.tuckCardsDuringMulligan());
                if (game.isGameOver()) return;
                if (keep) mulligan.keep();
                else { allKept = false; mulligan.mulligan(); }
            }
        } while (!allKept);
    }

    private record Choice(AbstractMulligan mulligan, boolean keep, Throwable error) { }

    private void runOnline(Decisions decisions) {
        while (!game.isGameOver()) {
            var results = new LinkedBlockingQueue<Choice>();
            var pending = new ArrayList<AbstractMulligan>();
            // Install every human's real Forge input before waiting for anybody.
            for (AbstractMulligan mulligan : mulligans) {
                if (mulligan.hasKept()) continue;
                pending.add(mulligan);
                Player player = mulligan.getPlayer();
                if (!mulligan.canMulligan()) results.add(new Choice(mulligan, true, null));
                else if (decisions.supports(player)) decisions.request(player, firstPlayer, mulligan.tuckCardsDuringMulligan())
                        .whenComplete((keep, error) -> results.add(new Choice(mulligan, Boolean.TRUE.equals(keep), error)));
                else results.add(new Choice(mulligan, player.getController().mulliganKeepHand(firstPlayer, mulligan.tuckCardsDuringMulligan()), null));
            }
            if (pending.isEmpty()) return;
            Set<AbstractMulligan> redraw = new HashSet<>();
            for (int remaining = pending.size(); remaining > 0; remaining--) {
                Choice choice;
                try { choice = results.take(); }
                catch (InterruptedException e) { Thread.currentThread().interrupt(); throw new IllegalStateException(e); }
                if (game.isGameOver()) return;
                if (choice.error() != null) throw new IllegalStateException("Opening hand decision failed", choice.error());
                AbstractMulligan mulligan = choice.mulligan();
                if (!mulligan.getPlayer().isInGame()) { mulligan.keep(); continue; }
                if (choice.keep()) {
                    mulligan.keep(); // Includes the real London bottom selection, when required.
                    decisions.kept(mulligan.getPlayer());
                } else redraw.add(mulligan);
            }
            // Redraw in turn order, after everybody has chosen for this round.
            for (AbstractMulligan mulligan : pending) if (redraw.contains(mulligan)) mulligan.mulligan();
        }
    }
}
