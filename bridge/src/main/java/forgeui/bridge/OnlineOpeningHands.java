package forgeui.bridge;

import forge.game.mulligan.MulliganService;
import forge.game.player.Player;
import forge.gamemodes.match.input.InputConfirmMulligan;
import forge.player.PlayerControllerHuman;
import java.util.concurrent.*;

/** Waiters only collect UI answers. They never mutate cards or run game actions. */
final class OnlineOpeningHands implements MulliganService.Decisions {
    private final ExecutorService waiters = Executors.newFixedThreadPool(4, task -> {
        var thread = new Thread(task, "online-opening-choice");
        thread.setDaemon(true);
        return thread;
    });

    @Override public boolean supports(Player player) {
        return player.getController() instanceof PlayerControllerHuman human && human.getGui() instanceof BridgeGuiGame;
    }

    @Override public CompletableFuture<Boolean> request(Player player, Player first, int returnCount) {
        var human = (PlayerControllerHuman) player.getController();
        var gui = (BridgeGuiGame) human.getGui();
        gui.openingHandComplete = false;
        var input = new InputConfirmMulligan(human, player, first);
        human.getInputQueue().setInput(input);
        return CompletableFuture.supplyAsync(() -> {
            input.awaitLatchRelease();
            return input.isKeepHand();
        }, waiters);
    }

    @Override public void kept(Player player) {
        if (player.getController() instanceof PlayerControllerHuman human && human.getGui() instanceof BridgeGuiGame gui) {
            gui.openingHandComplete = true;
            gui.openingChanged();
        }
    }
}
