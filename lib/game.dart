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

class Game {
  Random rng;
  List<List<PlayingCard>> playerCards;
  List<PileCard> pileCards;
  int currentPlayerIndex;
  int numSaveChances;
  int saveChanceOwner;
  int saveChanceWinner;

  Game() {
    this.rng = Random();
    startGame();
  }

  Game.withSeed(int seed) {
    this.rng = Random(seed);
    startGame();
  }

  void startGame() {
    var allCards = [...standardDeckCards];
    allCards.shuffle(this.rng);
    var midpoint = allCards.length ~/ 2;
    playerCards = [allCards.sublist(0, midpoint), allCards.sublist(midpoint)];
    pileCards = [];
    currentPlayerIndex = 0;
    numSaveChances = null;
    saveChanceOwner = null;
    saveChanceWinner = null;
  }

  int get numPlayers {
    return playerCards.length;
  }

  int _saveChancesForCard(final PlayingCard card) {
    switch (card.rank) {
      case Rank.ace: return 4;
      case Rank.king : return 3;
      case Rank.queen: return 2;
      case Rank.jack: return 1;
      default: return 0;
    }
  }

  bool _isStopper(final PlayingCard card) {
    return card.rank.index >= Rank.ten.index;
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
    if (saveChanceWinner != null) {
      return;
    }
    var hand = playerCards[currentPlayerIndex];
    var card = hand.removeAt(0);
    pileCards.add(PileCard(card, currentPlayerIndex, rng));
    final chances = _saveChancesForCard(card);
    if (chances > 0) {
      // Face card.
      numSaveChances = chances;
      saveChanceOwner = currentPlayerIndex;
      _moveToNextPlayer();
    }
    else if (numSaveChances == null) {
      // No face cards.
      _moveToNextPlayer();
    }
    else if (_isStopper(card)) {
      numSaveChances = null;
      _moveToNextPlayer();
    }
    else {
      --numSaveChances;
      if (numSaveChances <= 0) {
        saveChanceWinner = saveChanceOwner;
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
    numSaveChances = null;
    saveChanceOwner = null;
    saveChanceWinner = null;
  }

  bool canSlapPile() {
    int ps = pileCards.length;
    return ps >= 2 && pileCards[ps - 1].card.rank == pileCards[ps - 2].card.rank;
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

void main() {
  var sum = 0.0;
  for (var i = 0; i < 10000; i++) {
    for (var j = 0; j < 10000; j++) {
      sum += cos(i * j / 1e8);
    }
  }
  print(sum);
}