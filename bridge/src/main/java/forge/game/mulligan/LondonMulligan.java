package forge.game.mulligan;

import forge.game.card.Card;
import forge.game.card.CardCollection;
import forge.game.player.Player;
import forge.game.zone.ZoneType;

/**
 * Local compatibility override for the pinned Forge London implementation.
 * Replacement hands stay complete until the player commits to keeping one.
 * Loaded ahead of forge-game by the bridge's target/classes-first classpath.
 */
public class LondonMulligan extends AbstractMulligan {
    public LondonMulligan(Player player, boolean firstMullFree) {
        super(player, firstMullFree);
    }

    @Override
    public boolean canMulligan() {
        return !kept && tuckCardsDuringMulligan() < player.getMaxHandSize();
    }

    @Override
    public int handSizeAfterNextMulligan() {
        return player.getMaxHandSize();
    }

    @Override
    public void mulliganDraw() {
        player.drawCards(handSizeAfterNextMulligan());
    }

    @Override
    public void keep() {
        if (hasKept()) return;
        super.keep();
        int toReturn = tuckCardsDuringMulligan();
        if (toReturn == 0) return;
        CardCollection hand = new CardCollection(player.getCardsIn(ZoneType.Hand));
        for (Card card : player.getController().tuckCardsViaMulligan(hand, toReturn)) {
            player.getGame().getAction().moveToLibrary(card, -1, null);
        }
    }

    @Override
    public int tuckCardsDuringMulligan() {
        return returnCount(timesMulliganed, firstMulliganFree);
    }

    public static int returnCount(int mulligans, boolean firstFree) {
        return Math.max(0, mulligans - (firstFree ? 1 : 0));
    }
}
