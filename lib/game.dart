import 'dart:math';

enum Suit {clubs, diamonds, hearts, spades}

extension SuitExtension on Suit {
  String get asciiChar {
    switch (this) {
      case Suit.clubs: return 'C';
      case Suit.diamonds: return 'D';
      case Suit.hearts: return 'H';
      case Suit.spades: return 'S';
    }
  }
}

enum Rank {two, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace}

extension RankExtension on Rank {
  // Returns number for non-face card, or jack=11, queen=12, king=13, ace=14.
  int get numericValue {
    return this.index + 2;
  }

  String get asciiChar {
    switch (this) {
      case Rank.ace: return 'A';
      case Rank.king: return 'K';
      case Rank.queen: return 'Q';
      case Rank.jack: return 'J';
      case Rank.ten: return 'T';
      default:
        return this.numericValue.toString();
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
  slap_on_add_to_10,
}

// Penalty options for incorrect slaps.
enum BadSlapPenaltyType {
  none,
  // A card is put on the bottom of the pile.
  penalty_card,
  // The offending player can't slap for the next N cards.
  slap_timeout,
}

class GameRules {
  Set<RuleVariation> _enabledVariations = Set();
  BadSlapPenaltyType badSlapPenalty = BadSlapPenaltyType.none;

  bool isVariationEnabled(RuleVariation v) {
    return _enabledVariations.contains(v);
  }

  void setVariationEnabled(RuleVariation v, bool enabled) {
    enabled ? _enabledVariations.add(v) : _enabledVariations.remove(v);
  }
}

class Game {
  late GameRules rules;
  late Random rng;
  List<List<PlayingCard>> playerCards = [];
  List<PileCard> pileCards = [];
  // Penalty cards go at the bottom of the pile, and don't count for slaps.
  int numPenaltyCardsInPile = 0;
  int currentPlayerIndex = 0;
  int? numChallengeChances;
  int? challengeChanceOwner;
  int? challengeChanceWinner;
  List<int> slapTimeoutCardsRemaining = [];

  Game({Random? rng, GameRules? rules}) {
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
    numPenaltyCardsInPile = 0;
    slapTimeoutCardsRemaining = [0, 0];
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

  bool canPlayCard(final int playerIndex) {
    return this.currentPlayerIndex == playerIndex && this.challengeChanceWinner == null;
  }

  void playCard() {
    if (!canPlayCard(this.currentPlayerIndex)) {
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
      numChallengeChances = numChallengeChances! - 1;
      if (numChallengeChances! <= 0) {
        challengeChanceWinner = challengeChanceOwner;
      }
      if (hand.isEmpty) {
        _moveToNextPlayer();
      }
    }
    for (var i = 0; i < slapTimeoutCardsRemaining.length; i++) {
      int n = slapTimeoutCardsRemaining[i];
      slapTimeoutCardsRemaining[i] = max(0, n - 1);
    }
  }

  PileCard? addPenaltyCard(final int playerIndex) {
    var hand = playerCards[playerIndex];
    if (hand.isNotEmpty) {
      var card = hand.removeAt(0);
      var pc = PileCard(card, playerIndex, rng);
      pileCards.insert(0, pc);
      numPenaltyCardsInPile += 1;
      return pc;
    }
    return null;
  }

  void movePileToPlayer(final int playerIndex) {
    playerCards[playerIndex].addAll(pileCards.map((pc) => pc.card));
    pileCards = [];
    numPenaltyCardsInPile = 0;
    currentPlayerIndex = playerIndex;
    numChallengeChances = null;
    challengeChanceOwner = null;
    challengeChanceWinner = null;
  }

  bool canSlapPile() {
    // Penalty cards don't count.
    final activeCards = pileCards.sublist(numPenaltyCardsInPile);
    final ps = activeCards.length;
    if (ps >= 2 && activeCards[ps - 1].card.rank == activeCards[ps - 2].card.rank) {
      return true;
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_sandwich) && ps >= 3 &&
        activeCards[ps - 1].card.rank == activeCards[ps - 3].card.rank) {
      return true;
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_same_suit_of_4) && ps >= 4) {
      Suit topSuit = pileCards[ps - 1].card.suit;
      if (activeCards[ps - 2].card.suit == topSuit &&
          activeCards[ps - 3].card.suit == topSuit &&
          activeCards[ps - 4].card.suit == topSuit) {
        return true;
      }
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_run_of_3) && ps >= 3) {
      final numRanks = Rank.values.length;
      final r1 = activeCards[ps - 1].card.rank.index;
      final r2 = activeCards[ps - 2].card.rank.index;
      final r3 = activeCards[ps - 3].card.rank.index;
      if ((r2 == (r1 + 1) % numRanks) && r3 == (r1 + 2) % numRanks) {
        return true;
      }
      if ((r2 == (r3 + 1) % numRanks) && r1 == (r3 + 2) % numRanks) {
        return true;
      }
    }
    if (rules.isVariationEnabled(RuleVariation.slap_on_add_to_10) && ps >= 2) {
      final r1 = pileCards[ps - 1].card.rank.numericValue;
      final r2 = pileCards[ps - 2].card.rank.numericValue;
      if (r1 + r2 == 10) {
        return true;
      }
    }
    return false;
  }

  bool isPlayerAllowedToSlap(final int playerIndex) {
    return !(rules.badSlapPenalty == BadSlapPenaltyType.slap_timeout &&
        slapTimeoutCardsRemaining[playerIndex] > 0);
  }

  int slapTimeoutCardsForPlayer(final int playerIndex) {
    return slapTimeoutCardsRemaining[playerIndex];
  }

  void setSlapTimeoutCardsForPlayer(final int cards, final int playerIndex) {
    slapTimeoutCardsRemaining[playerIndex] = cards;
  }

  int? gameWinner() {
    if (pileCards.isNotEmpty) {
      return null;
    }
    int? potentialWinner;
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
