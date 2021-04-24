import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pounce/game.dart';

// Convert a string like "8D" to the corresponding card.
PlayingCard card(String rankAndSuit) {
  String rankChar = rankAndSuit.substring(0, 1);
  String suitChar = rankAndSuit.substring(1, 2);
  Rank rank = Rank.values.firstWhere((r) => r.asciiChar == rankChar);
  Suit suit = Suit.values.firstWhere((s) => s.asciiChar == suitChar);
  return PlayingCard(rank, suit);
}

List<PlayingCard> cards(String cardStr) {
  final cardStrs = cardStr.split(' ');
  return cardStrs.map((cs) => card(cs)).toList();
}

void main() {
  test('Game should be initialized', () {
    final game = Game();

    expect(game.numPlayers, 2);
    expect(game.playerCards[0].length, 26);
    expect(game.playerCards[1].length, 26);
    expect(game.pileCards.length, 0);
    expect(game.currentPlayerIndex, 0);
    expect(game.canPlayCard(0), true);
    expect(game.canPlayCard(1), false);
  });

  test('handles face cards', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.ten_is_stopper, false);
    // Ugly way of setting the cards that players have. There should be a better API.
    game.playerCards = [
      cards('4S KH TD 2S AS'),
      cards('7D 7C 2D QC AH'),
    ];

    // Play should go 4S-7D-KH-7C-2D-QC-TD-2S
    for (var i = 0; i < 7; i++) {
      game.playCard();
      expect(game.challengeChanceWinner, null);
      expect(game.canPlayCard(game.currentPlayerIndex), true);
      expect(game.canPlayCard(1 - game.currentPlayerIndex), false);
    }

    expect(game.currentPlayerIndex, 0);
    game.playCard();
    expect(game.pileCards.map((pc) => pc.card.asciiString()).join(' '), '4S 7D KH 7C 2D QC TD 2S');
    expect(game.challengeChanceWinner, 1);
    expect(game.canPlayCard(0), false);
    expect(game.canPlayCard(1), false);

    game.movePileToPlayer(1);
    expect(game.playerCards[0].map((c) => c.asciiString()).join(' '), 'AS');
    expect(game.playerCards[1].map((c) => c.asciiString()).join(' '), 'AH 4S 7D KH 7C 2D QC TD 2S');
    expect(game.currentPlayerIndex, 1);
  });

  test('handles face cards with ten as stopper', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.ten_is_stopper, true);
    // Ugly way of setting the cards that players have. There should be a better API.
    game.playerCards = [
      cards('4S KH TD 2S AS'),
      cards('7D 7C 2D QC AH'),
    ];

    // Play should go 4S-7D-KH-7C-2D-QC-TD
    for (var i = 0; i < 7; i++) {
      game.playCard();
      expect(game.challengeChanceWinner, null);
    }
    expect(game.currentPlayerIndex, 1);
  });

  test('handles pair slaps', () {
    final game = Game();
    game.playerCards = [
      cards('4S 7H QD 6C 6S'),
      cards('7D 8C QH 4H 4S'),
    ];

    // Play should go 4S-7D-7H(*)-8C-QD-QH(*)-6C-6H(*).
    final slapIndices = {2, 5, 7};
    for (var i = 0; i < 8; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('handles sandwich slaps', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_sandwich, true);
    game.playerCards = [
      cards('4S 4H KD 6C 5S 6D'),
      cards('7D 8C 8H KH 4S AH'),
    ];

    // Play should go 4S-7D-4H(*)-8C-KD-8H(*)-KH(*)-6C-5S-6D(*).
    final slapIndices = {2, 5, 6, 9};
    for (var i = 0; i < 10; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('ignores sandwiches if disabled', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_sandwich, false);
    game.playerCards = [
      cards('4S 4H KD 6C 5S 6D'),
      cards('7D 8C 8H KH 4S AH'),
    ];
    for (var i = 0; i < 10; i++) {
      game.playCard();
      expect(game.canSlapPile(), false);
    }
  });

  test('handles slaps on runs of 3', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_run_of_3, true);
    game.playerCards = [
      cards('4S 5H 3D KS 2S 3D TH'),
      cards('6D 4C QH AH 9S 9D 7H'),
    ];

    // Play should go 4S-6D-5H-4C(*)-3D(*)-QH-KS-AH(*)-2S(*)-3D(*)-TH.
    final slapIndices = {3, 4, 7, 8, 9};
    for (var i = 0; i < 11; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('ignores runs of 3 if disabled', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_run_of_3, false);
    game.playerCards = [
      cards('4S 5H 3D KS 2S 3D TH'),
      cards('6D 4C QH AH 9S 9D 7H'),
    ];
    for (var i = 0; i < 11; i++) {
      game.playCard();
      expect(game.canSlapPile(), false);
    }
  });

  test('handles slaps on 4 of same suit', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_same_suit_of_4, true);
    game.playerCards = [
      cards('4S 5D AD 9S 2S 7H'),
      cards('4D TD 5D 6C 7S KS'),
    ];

    // Play should go 4S-4D(*)-5D-TD-AD(*)-5D(*)-6C-7S-KS-9S-2S(*)-7H.
    final slapIndices = {1, 4, 5, 10};
    for (var i = 0; i < 12; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('ignores 4 of same suit if disabled', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_same_suit_of_4, false);
    game.playerCards = [
      cards('4S 5D AD 9S 2S 7H'),
      cards('4D TD 5D 6C 7S KS'),
    ];
    final slapIndices = {1};
    for (var i = 0; i < 12; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('handles sum to 10', () {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_add_to_10, true);
    game.playerCards = [
      cards('TS 6S AH 5S 3S 2H'),
      cards('6D TD 9C 2C 8S KS'),
    ];

    // Play should go TS-6D-4S(*)-TD-AH-9C-2C-8S(*)-KS-5S-3S-2H.
    final slapIndices = {2, 7};
    for (var i = 0; i < 12; i++) {
      game.playCard();
      expect(game.canSlapPile(), slapIndices.contains(i), reason: 'Wrong at index $i');
    }
  });

  test('ignores sum to 10 if disabled', ()
  {
    final game = Game();
    game.rules.setVariationEnabled(RuleVariation.slap_on_add_to_10, false);
    game.playerCards = [
      cards('TS 4S AH 5S 3S 2H'),
      cards('6D TD 9C 2C 8S KS'),
    ];

    for (var i = 0; i < 12; i++) {
      game.playCard();
      expect(game.canSlapPile(), false, reason: 'Wrong at index $i');
    }
  });
}
