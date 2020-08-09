import 'dart:math';

enum Suit {clubs, diamonds, hearts, spades}

extension SuitExtension on Suit {
  get asciiChar {
    switch (this) {
      case Suit.clubs: return 'C';
      case Suit.diamonds: return 'D';
      case Suit.hearts: return 'H';
      case Suit.spades: return 'S';
    }
    throw AssertionError("Unrecognized suit");
  }
}

enum Rank {two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace}

extension RankExtension on Rank {
  get asciiChar {
    switch (this) {
      case Rank.ace: return 'A';
      case Rank.king: return 'K';
      case Rank.queen: return 'Q';
      case Rank.jack: return 'J';
      case Rank.ten: return 'T';
      default:
        return (this.index + 2).toString();
    }
  }
}

// "Card" is a Flutter UI class, PlayingCard avoids having to disambiguate.
class PlayingCard {
  PlayingCard(this.rank, this.suit);

  final Rank rank;
  final Suit suit;

  String asciiString() {
    return this.rank.asciiChar + this.suit.asciiChar;
  }
}

final standardDeckCards = [
  for (var r in Rank.values) PlayingCard(r, Suit.clubs),
  for (var r in Rank.values) PlayingCard(r, Suit.diamonds),
  for (var r in Rank.values) PlayingCard(r, Suit.hearts),
  for (var r in Rank.values) PlayingCard(r, Suit.spades),
];

class PileCard {
  final PlayingCard card;
  final int playedBy;
  final double xOffset;
  final double yOffset;
  final double rotation;

  PileCard(this.card, this.playedBy, Random rng) :
      xOffset = 2 * rng.nextDouble() - 1,
      yOffset = 2 * rng.nextDouble() - 1,
      rotation = 2 * rng.nextDouble() - 1;
}

enum RuleVariation {
  ten_is_stopper,
  slap_on_sandwich,
  slap_on_run_of_3,
  slap_on_same_suit_of_4,
}

class GameRules {
  Set<RuleVariation> _enabledVariations = Set();

  bool isVariationEnabled(RuleVariation v) {
    return _enabledVariations.contains(v);
  }

  void setVariationEnabled(RuleVariation v, bool enabled) {
    enabled ? _enabledVariations.add(v) : _enabledVariations.remove(v);
  }
}

class Game {
  GameRules rules;
  Random rng;
  List<List<PlayingCard>> playerCards;
  List<PileCard> pileCards;
  int currentPlayerIndex;
  int numChallengeChances;
  int challengeChanceOwner;
  int challengeChanceWinner;

  Game({Random rng, GameRules rules}) {
    this.rng = rng ?? Random();
    this.rules = rules ?? GameRules();
    startGame();
  }

  void startGame() {
    var allCards = [...standardDeckCards];
    allCards.shuffle(this.rng);
    var midpoint = allCards.length ~/ 2;
    playerCards = [allCards.sublist(0, midpoint), allCards.sublist(midpoint)];
    pileCards = [];
    currentPlayerIndex = 0;
    numChallengeChances = null;
    challengeChanceOwner = null;
    challengeChanceWinner = null;
  }

  int get numPlayers {
    return playerCards.length;
  }

  int _challengeChancesForCard(final PlayingCard card) {
    switch (card.rank) {
      case Rank.ace: return 4;
      case Rank.king : return 3;
      case Rank.queen: return 2;
      case Rank.jack: return 1;
      default: return 0;
    }
  }

  bool _isStopper(final PlayingCard card) {
    if (rules.isVariationEnabled(RuleVariation.ten_is_stopper) && card.rank == Rank.ten) {
      return true;
    }
    return card.rank.index >= Rank.jack.index;
  }

  void _moveToNextPlayer() {
    final origPlayer = currentPlayerIndex;
    var newPlayer = (currentPlayerIndex + 1) % numPlayers;
    while (newPlayer != origPlayer && playerCards[newPlayer].isEmpty) {
      newPlayer = (newPlayer + 1) % numPlayers;
    }
    currentPlayerIndex = newPlayer;
  }

  void playCard() {
    if (challengeChanceWinner != null) {
      return;
    }
    var hand = playerCards[currentPlayerIndex];
    var card = hand.removeAt(0);
    pileCards.add(PileCard(card, currentPlayerIndex, rng));
    final chances = _challengeChancesForCard(card);
    if (chances > 0) {
      // Face card.
      numChallengeChances = chances;
      challengeChanceOwner = currentPlayerIndex;
      _moveToNextPlayer();
    }
    else if (numChallengeChances == null) {
      // No face cards.
      _moveToNextPlayer();
    }
    else if (_isStopper(card)) {
      numChallengeChances = null;
      _moveToNextPlayer();
    }
    else {
      --numChallengeChances;
      if (numChallengeChances <= 0) {
        challengeChanceWinner = challengeChanceOwner;
      }
      if (hand.isEmpty) {
        _moveToNextPlayer();
      }
    }
  }

  void movePileToPlayer(final int playerIndex) {
    playerCards[playerIndex].addAll(pileCards.map((pc) => pc.card));
    pileCards = [];
    currentPlayerIndex = playerIndex;
    numChallengeChances = null;
    challengeChanceOwner = null;
    challengeChanceWinner = null;
  }

  bool canSlapPile() {
    final ps = pileCards.length;
    if (ps >= 2 && pileCards[ps - 1].card.rank == pileCards[ps - 2].card.rank) {
      return true;
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_sandwich) && ps >= 3 &&
        pileCards[ps - 1].card.rank == pileCards[ps - 3].card.rank) {
      return true;
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_same_suit_of_4) && ps >= 4) {
      Suit topSuit = pileCards[ps - 1].card.suit;
      if (pileCards[ps - 2].card.suit == topSuit &&
          pileCards[ps - 3].card.suit == topSuit &&
          pileCards[ps - 4].card.suit == topSuit) {
        return true;
      }
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_run_of_3) && ps >= 3) {
      final numRanks = Rank.values.length;
      final r1 = pileCards[ps - 1].card.rank.index;
      final r2 = pileCards[ps - 2].card.rank.index;
      final r3 = pileCards[ps - 3].card.rank.index;
      if ((r2 == (r1 + 1) % numRanks) && r3 == (r1 + 2) % numRanks) {
        return true;
      }
      if ((r2 == (r3 + 1) % numRanks) && r1 == (r3 + 2) % numRanks) {
        return true;
      }
    }
    return false;
  }

  int gameWinner() {
    if (pileCards.isNotEmpty) {
      return null;
    }
    int potentialWinner = null;
    for (int i = 0; i < playerCards.length; i++) {
      if (playerCards[i].isNotEmpty) {
        if (potentialWinner != null) {
          return null;
        }
        potentialWinner = i;
      }
    }
    return potentialWinner;
  }
}
