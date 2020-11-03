import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'game.dart';

void main() {
  runApp(MyApp());
  SystemChrome.setEnabledSystemUIOverlays([]);
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Egyptian Mouse Pounce',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

enum AnimationMode {
  none,
  play_card_back,
  play_card_front,
  ai_slap,
  waiting_to_move_pile,
  pile_to_winner,
  illegal_slap,
}

final illegalSlapAnimationDuration = Duration(milliseconds: 600);

enum AIMode {human_vs_human, human_vs_ai, ai_vs_ai}

enum DialogMode {none, main_menu, preferences, game_paused, game_over, statistics}

enum AIMood {none, happy, very_happy, angry}

final aiMoodImages = {
  AIMood.happy: 'bubble_happy.png',
  AIMood.very_happy: 'bubble_grin.png',
  AIMood.angry: 'bubble_mad.png',
};

enum AISlapSpeed {slow, medium, fast}

String prefsKeyForVariation(RuleVariation v) {
  return 'rule.${v.toString()}';
}

final String aiSlapSpeedPrefsKey = 'ai_slap_speed';
final String badSlapPenaltyPrefsKey = 'bad_slap_penalty';

// https://docs.google.com/document/d/1yohSuYrvyya5V1hB6j9pJskavCdVq9sVeTqSoEPsWH0/edit#
final ButtonStyle raisedButtonStyle = ElevatedButton.styleFrom(
  onPrimary: Colors.black87,
  primary: Colors.grey[300],
  minimumSize: Size(88, 36),
  padding: EdgeInsets.symmetric(horizontal: 16),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
  ),
);

class _MyHomePageState extends State<MyHomePage> {
  Random rng = Random();
  Game game = Game();
  AnimationMode animationMode = AnimationMode.none;
  AIMode aiMode = AIMode.ai_vs_ai;
  DialogMode dialogMode = DialogMode.main_menu;
  int pileMovingToPlayer;
  PileCard penaltyCard;
  bool penaltyCardPlayed = false;
  int aiSlapPlayerIndex;
  int aiSlapCounter = 0;
  List<int> catImageNumbers;
  List<AIMood> aiMoods = [AIMood.none, AIMood.none];
  int aiMoodCounter = 0;
  AISlapSpeed aiSlapSpeed = AISlapSpeed.medium;
  final numCatImages = 4;

  @override void initState() {
    super.initState();
    game = Game(rng: rng);
    catImageNumbers = _randomCatImageNumbers();
    penaltyCard = null;
    _readPreferencesAndStartGame();
  }

  @override void didChangeDependencies() async {
    super.didChangeDependencies();
    _preloadCardImages();
  }

  void _readPreferencesAndStartGame() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    for (var v in RuleVariation.values) {
      bool enabled = prefs.getBool(prefsKeyForVariation(v)) ?? false;
      game.rules.setVariationEnabled(v, enabled);
    }

    final speedStr = prefs.getString(aiSlapSpeedPrefsKey) ?? '';
    aiSlapSpeed = AISlapSpeed.values.firstWhere(
        (s) => s.toString() == speedStr, orElse: () => AISlapSpeed.medium);

    final penaltyStr = prefs.getString(badSlapPenaltyPrefsKey) ?? '';
    game.rules.badSlapPenalty = BadSlapPenaltyType.values.firstWhere(
        (s) => s.toString() == penaltyStr, orElse: () => BadSlapPenaltyType.none);

    _scheduleAiPlayIfNeeded();
  }

  List<int> _randomCatImageNumbers() {
    int c1 = rng.nextInt(numCatImages);
    int c2 = (c1 + 1 + rng.nextInt(numCatImages - 1)) % numCatImages;
    return [c1 + 1, c2 + 1];
  }

  String _imagePathForCard(final PlayingCard card) {
    return 'assets/cards/${card.asciiString()}.webp';
  }

  void _preloadCardImages() {
    var numCardsLoaded = 0;
    for (Rank r in Rank.values) {
      for (Suit s in Suit.values) {
        precacheImage(AssetImage(_imagePathForCard(PlayingCard(r, s))), context).then((_) {
          numCardsLoaded += 1;
        });
      }
    }
  }

  void _playCard() {
    setState(() {
      game.playCard();
      animationMode = AnimationMode.play_card_back;
      aiSlapCounter++;
      penaltyCard = null;
      penaltyCardPlayed = false;
    });
  }
  
  bool _shouldAiPlayCard() {
    if (game.gameWinner() != null) {
      return false;
    }
    // Don't play if we're in the middle of another animation (e.g. penalty card).
    // _scheduleAiPlayIfNeeded should be called when the animation finishes.
    if (animationMode != AnimationMode.none) {
      return false;
    }
    return aiMode == AIMode.ai_vs_ai ||
        (aiMode == AIMode.human_vs_ai && game.currentPlayerIndex == 1);
  }

  void _scheduleAiPlayIfNeeded() {
    final thisGame = game;
    if (_shouldAiPlayCard()) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (thisGame == game && _shouldAiPlayCard()) {
          _playCard();
        }
      });
    }
  }

  int _aiSlapDelayMillis() {
    int baseDelay = 300 + (500 * rng.nextDouble()).toInt();
    switch (aiSlapSpeed) {
      case AISlapSpeed.medium:
        return baseDelay;
      case AISlapSpeed.fast:
        return (baseDelay * 0.6).toInt();
      case AISlapSpeed.slow:
        return baseDelay * 2;
      default:
        throw AssertionError('Unknown AISlapSpeed');
    }
  }

  void _playCardFinished() {
    animationMode = AnimationMode.none;
    if (game.canSlapPile() && aiMode != AIMode.human_vs_human) {
      final delayMillis = _aiSlapDelayMillis();
      aiSlapCounter++;
      final counterSnapshot = aiSlapCounter;
      final aiIndex = aiMode == AIMode.human_vs_ai ? 1 : rng.nextInt(2);
      Future.delayed(Duration(milliseconds: delayMillis), () {
        if (counterSnapshot == aiSlapCounter) {
          setState(() {
            animationMode = AnimationMode.ai_slap;
            pileMovingToPlayer = aiIndex;
            aiSlapPlayerIndex = aiIndex;
            Future.delayed(Duration(milliseconds: 1000), () {
              setState(() => animationMode = AnimationMode.pile_to_winner);
            });
          });
        }
      });
    }
    else {
      final pileWinner = game.challengeChanceWinner;
      if (pileWinner != null) {
        animationMode = AnimationMode.waiting_to_move_pile;
        pileMovingToPlayer = pileWinner;
        Future.delayed(const Duration(milliseconds: 1000), () {
          setState(() => animationMode = AnimationMode.pile_to_winner);
        });
      }
      else {
        _scheduleAiPlayIfNeeded();
      }
    }
  }

  final moodWeights = {
    Rank.ace: 2,
    Rank.king: 4,
    Rank.queen: 6,
    Rank.jack: 12,
  };

  void _setAiMoods(final List<AIMood> moods) {
    aiMoodCounter += 1;
    int previousMoodCounter = aiMoodCounter;
    setState(() => aiMoods = moods);
    Future.delayed(const Duration(milliseconds: 5000), () {
      if (previousMoodCounter == aiMoodCounter) {
        setState(() => aiMoods = [AIMood.none, AIMood.none]);
      }
    });
  }

  // Whether the AI should show a mood after winning or losing a pile, as determined by the number
  // and importance of cards in the pile.
  bool _aiHasMoodForPile(final List<PileCard> pileCards) {
    int total = 0;
    for (PileCard pc in pileCards) {
      int cval = moodWeights.containsKey(pc.card.rank) ? moodWeights[pc.card.rank] : 1;
      total += cval;
    }
    return total > 16;
  }

  void _updateAiMoodsForPile(final List<PileCard> pileCards, final int pileWinner) {
    if (_aiHasMoodForPile(pileCards)) {
      var moods = pileWinner == 0 ? [AIMood.happy, AIMood.angry] : [AIMood.angry, AIMood.happy];
      _setAiMoods(moods);
    }
  }

  void _updateAiMoodsForGameWinner(int winner) {
    var moods = winner == 0 ? [AIMood.very_happy, AIMood.angry] : [AIMood.angry, AIMood.very_happy];
    _setAiMoods(moods);
  }

  void _movePileToWinner() {
    _updateAiMoodsForPile(game.pileCards, pileMovingToPlayer);
    game.movePileToPlayer(pileMovingToPlayer);
    int winner = game.gameWinner();
    if (winner != null) {
      _updateAiMoodsForGameWinner(winner);
      if (aiMode == AIMode.ai_vs_ai) {
        Future.delayed(const Duration(milliseconds: 2000), () {
          setState(() {
            game.startGame();
            _scheduleAiPlayIfNeeded();
          });
        });
      }
      else {
        dialogMode = DialogMode.game_over;
      }
    }
    animationMode = AnimationMode.none;
    pileMovingToPlayer = null;
    _scheduleAiPlayIfNeeded();
  }

  void _playCardIfPlayerTurn(int pnum) {
    if (animationMode != AnimationMode.none) {
      return;
    }
    if (game.currentPlayerIndex == pnum) {
      setState(_playCard);
    }
  }

  void _doSlap(Offset globalOffset, double globalHeight) {
    if (animationMode != AnimationMode.none) {
      return;
    }
    int pnum = 0;
    if (aiMode == AIMode.human_vs_human) {
      pnum = (globalOffset.dy > globalHeight / 2) ? 0 : 1;
    }
    if (!game.isPlayerAllowedToSlap(pnum)) {
      return;
    }
    if (game.canSlapPile()) {
      setState(() {
        aiSlapCounter++;
        pileMovingToPlayer = pnum;
        animationMode = AnimationMode.pile_to_winner;
      });
    }
    else {
      _handleIllegalSlap(pnum);
    }
  }

  void _handleIllegalSlap(final int playerIndex) {
    setState(() {
      animationMode = AnimationMode.illegal_slap;
      switch (game.rules.badSlapPenalty) {
        case BadSlapPenaltyType.penalty_card:
          // Only one penalty card per real card?
          if (!penaltyCardPlayed) {
            penaltyCard = game.addPenaltyCard(playerIndex);
            penaltyCardPlayed = (penaltyCard != null);
          }
          break;
        case BadSlapPenaltyType.slap_timeout:
          game.setSlapTimeoutCardsForPlayer(5, playerIndex);
          break;
      }
    });
    Future.delayed(illegalSlapAnimationDuration, () {
      setState(() {
        animationMode = AnimationMode.none;
        penaltyCard = null;
      });
      _scheduleAiPlayIfNeeded();
    });
  }

  Widget _playerStatusWidget(final Game game, final int playerIndex, final Size displaySize) {
    final enabled = game.currentPlayerIndex == playerIndex;
    return Transform.rotate(
      angle: (playerIndex == 1) ? pi : 0,
        child: Padding(
          padding: EdgeInsets.all(0.025 * displaySize.height),
          child: ElevatedButton(
            style: raisedButtonStyle,
            onPressed: enabled ? (() => _playCardIfPlayerTurn(playerIndex)) : null,
            child: Padding(padding: EdgeInsets.all(10), child: Text (
              'Play card: ${game.playerCards[playerIndex].length} left',
              style: TextStyle(
                fontSize: Theme.of(context).textTheme.headline4.fontSize,
                color: enabled ? Colors.green : Colors.grey,
              )
          )),
        )));
  }

  Widget _aiPlayerWidget(final Game game, final int playerIndex, final Size displaySize) {
    final moodImage = aiMoodImages[aiMoods[playerIndex]];
    return Transform.rotate(
      angle: playerIndex == 1 ? 0 : pi,
      child: Stack(
        children: [
          Positioned.fill(child:
            Transform.translate(
              offset: Offset(0, 10),
              child: Image(
                image: AssetImage('assets/cats/cat${catImageNumbers[playerIndex]}.png'),
                fit: BoxFit.fitHeight,
                alignment: Alignment.center,
              )
            )
          ),

          if (moodImage != null) Positioned.fill(top: 5, bottom: 40, child:
            Transform.translate(
                offset: Offset(110, 0),
                child: Image(
                  image: AssetImage('assets/cats/${moodImage}'),
                  fit: BoxFit.fitHeight,
                  alignment: Alignment.center,
                )
            )
          ),
        ],
      )
    );
  }

  Widget _cardImage(final PlayingCard card) {
    return Image(
      image: AssetImage(_imagePathForCard(card)),
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );
  }

  Widget _pileCardWidget(
      final PileCard pc, final Size displaySize, {final rotationFrac = 1.0}) {
    final minDim = min(displaySize.width, displaySize.height);
    final maxOffset = minDim * 0.1;
    return Container(
        height: double.infinity,
        width: double.infinity,
        child: Transform.translate(
            offset: Offset(pc.xOffset * maxOffset, pc.yOffset * maxOffset),
            child:
            Transform.rotate(
              angle: pc.rotation * rotationFrac * pi / 12,
              child: FractionallySizedBox(
                alignment: Alignment.center,
                heightFactor: 0.7,
                widthFactor: 0.7,
                child: GestureDetector(
                    onTapDown: (TapDownDetails tap) {
                      if (dialogMode == DialogMode.none) {
                        _doSlap(tap.globalPosition, displaySize.height);
                      }
                    },
                    child: _cardImage(pc.card),
                ),
              ),
            )
        )
    );
  }

  List<Widget> _pileCardWidgets(Iterable<PileCard> pileCards, final Size displaySize) {
    return pileCards.map((pc) => _pileCardWidget(pc, displaySize)).toList();
  }

  Widget _pileContent(final Game game, final Size displaySize) {
    final pileCardsWithoutLast = game.pileCards.sublist(0, max(0, game.pileCards.length - 1));
    final lastPileCard = game.pileCards.isNotEmpty ? game.pileCards.last : null;

    /* // Fixed cards to take screenshots for icon.
    final demoCards = [
      PileCard(PlayingCard(Rank.queen, Suit.diamonds), 0, rng),
      PileCard(PlayingCard(Rank.four, Suit.spades), 0, rng),
      PileCard(PlayingCard(Rank.four, Suit.hearts), 0, rng),
    ];
    demoCards[0].xOffset = -0.7;
    demoCards[0].yOffset = 0.2;
    demoCards[0].rotation = -0.25;
    demoCards[1].xOffset = -0.3;
    demoCards[1].yOffset = -0.2;
    demoCards[1].rotation = 0.15;
    demoCards[2].xOffset = 0.6;
    demoCards[2].yOffset = 0.0;
    demoCards[2].rotation = 0.0;
    */

    switch (animationMode) {
      case AnimationMode.none:
      case AnimationMode.waiting_to_move_pile:
        return Stack(children: _pileCardWidgets(game.pileCards, displaySize));

      case AnimationMode.ai_slap:
        return Stack(children: [
          ..._pileCardWidgets(game.pileCards, displaySize),
          Center(child: Image(
              image: AssetImage('assets/cats/paw${catImageNumbers[aiSlapPlayerIndex]}.png'),
              alignment: Alignment.center,
          )),
        ]);

      case AnimationMode.play_card_back:
        return Stack(
              children: [
                ..._pileCardWidgets(pileCardsWithoutLast, displaySize).toList(),
              if (lastPileCard != null) TweenAnimationBuilder(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200),
                onEnd: () => setState(_playCardFinished),
                builder: (BuildContext context, double animValue, Widget child) {
                  double startYOff = displaySize.height / 2 * (lastPileCard.playedBy == 0 ? 1 : -1);
                  return Transform.translate(
                    offset: Offset(0, startYOff * (1 - animValue)),
                    child: _pileCardWidget(lastPileCard, displaySize, rotationFrac: animValue),
                  );
                },
              ),
            ]
        );

      case AnimationMode.pile_to_winner:
        double endYOff = displaySize.height * 0.75 * (pileMovingToPlayer == 0 ? 1 : -1);
        return TweenAnimationBuilder(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300),
          onEnd: () => setState(_movePileToWinner),
          child: Stack(children: _pileCardWidgets(game.pileCards, displaySize)),
          builder: (BuildContext context, double animValue, Widget child) {
            return Transform.translate(
              offset: Offset(0, endYOff * animValue),
              child: child,
            );
          },
        );

      case AnimationMode.illegal_slap:
        return Stack(children: [
          if (penaltyCard != null) TweenAnimationBuilder(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: illegalSlapAnimationDuration,
            builder: (BuildContext context, double animValue, Widget child) {
              double startYOff = displaySize.height / 2 * (penaltyCard.playedBy == 0 ? 1 : -1);
              return Transform.translate(
                offset: Offset(0, startYOff * (1 - animValue)),
                child: _pileCardWidget(penaltyCard, displaySize, rotationFrac: animValue),
              );
            },
          ),
          Opacity(opacity: penaltyCard != null ? 0.25 : 1.0, child: Stack(
              children: _pileCardWidgets(
                  penaltyCard != null ? game.pileCards.sublist(1) : game.pileCards,
                  displaySize),
          )),
          TweenAnimationBuilder(
            tween: Tween(begin: 2.0, end: 0.0),
            duration: illegalSlapAnimationDuration,
            child: Center(child: Image(
              image: AssetImage('assets/misc/no.png'),
              alignment: Alignment.center,
            )),
            builder: (BuildContext context, double animValue, Widget child) {
              return Opacity(
                opacity: min(animValue, 1),
                child: child,
              );
            },
          )
        ]);

      default:
        return SizedBox.shrink();
    }
  }

  Widget _noSlapWidget(final int playerIndex, final Size displaySize) {
    int numTimeoutCards = game.slapTimeoutCardsForPlayer(playerIndex);
    if (numTimeoutCards <= 0) {
      return SizedBox.shrink();
    }
    final minDim = min(displaySize.width, displaySize.height);
    final size = min(minDim * 0.2, 100.0);
    final padding = 10.0;
    return Positioned(
      left: playerIndex == 0 ? padding : null,
      bottom: playerIndex == 0 ? padding : null,
      right: playerIndex == 0 ? null : padding,
      top: playerIndex == 0 ? null : padding,
      child: Transform.rotate(
        angle: playerIndex == 1 ? pi : 0,
        child: Stack(
          children: [
            SizedBox(
                width: size,
                height: size,
                child: Image(image: AssetImage('assets/cats/paw${catImageNumbers[playerIndex]}.png'))),
            SizedBox(
                width: size,
                height: size,
                child: Image(image: AssetImage('assets/misc/no.png'))),
            Padding(
              padding: EdgeInsets.only(left: size * 0.55, top: size * 0.55),
              child: SizedBox(
                  width: size * 0.45,
                  height: size * 0.45,
                  child: TextButton(
                      style: TextButton.styleFrom(
                        shape: CircleBorder(),
                        primary: Colors.blue,
                        backgroundColor: Colors.white,
                      ),
                    onPressed: () {},
                    child: Text(numTimeoutCards.toString(),
                    style: TextStyle(fontSize: size * 0.24))),
              ),
            ),
          ],
        )
      )
    );
  }

  Widget _paddingAll(final double paddingPx, final Widget child) {
    return Padding(padding: EdgeInsets.all(paddingPx), child: child);
  }

  Widget _mainMenuDialog(final BuildContext context, final Size displaySize) {
    final minDim = min(displaySize.width, displaySize.height);

    final makeButtonRow = (String title, Function onPressed) {
      return TableRow(children: [
        Padding(
          padding: EdgeInsets.all(8),
          child: ElevatedButton(
            style: raisedButtonStyle,
            onPressed: onPressed,
            child: Text(title),
          ),
        ),
      ]);
    };

    return Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Dialog(
            backgroundColor: Color.fromARGB(0xa0, 0xc0, 0xc0, 0xc0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paddingAll(10, Text(
                    'Egyptian Mouse Pounce',
                    style: TextStyle(
                      fontSize: minDim / 18,
                    )
                )),
                Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    makeButtonRow('Play against computer', _startOnePlayerGame),
                    makeButtonRow('Play against human', _startTwoPlayerGame),
                    makeButtonRow('Watch the cats', _watchAiGame),
                    makeButtonRow('Preferences...', _showPreferences),
                    makeButtonRow('About...', () => _showAboutDialog(context)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _pausedMenuDialog(final Size displaySize) {
    return Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Dialog(
          backgroundColor: Color.fromARGB(0xa0, 0xc0, 0xc0, 0xc0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Row(
                children: [Expanded(
                  child: ElevatedButton(
                    style: raisedButtonStyle,
                    onPressed: _continueGame,
                    child: Text('Continue'),
                  ),
                )],
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: ElevatedButton(
                    style: raisedButtonStyle,
                    onPressed: _endGame,
                    child: Text('End Game'),
                  ),
                )],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameOverDialog(final Size displaySize) {
    final winner = game.gameWinner();
    if (winner == null) {
      return Container();
    }
    String title = (aiMode == AIMode.human_vs_ai) ?
        (winner == 0 ? 'You won!' : 'You lost!') :
        'Player ${winner + 1} won!';
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Dialog(
          backgroundColor: Color.fromARGB(0xa0, 0xc0, 0xc0, 0xc0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Text(
                  title,
                  style: TextStyle(
                    fontSize: displaySize.width / 18,
                  )
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: ElevatedButton(
                    style: raisedButtonStyle,
                    onPressed: _startNewGame,
                    child: Text('Rematch'),
                  ),
                )],
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: ElevatedButton(
                    style: raisedButtonStyle,
                    onPressed: _endGame,
                    child: Text('Main menu'),
                  ),
                )],
              )),
            ],
          )
        )
      )
    );
  }

  void _startOnePlayerGame() {
    setState(() {
      aiMode = AIMode.human_vs_ai;
      dialogMode = DialogMode.none;
      animationMode = AnimationMode.none;
      catImageNumbers = _randomCatImageNumbers();
      game.startGame();
    });
  }

  void _startTwoPlayerGame() {
    setState(() {
      aiMode = AIMode.human_vs_human;
      dialogMode = DialogMode.none;
      animationMode = AnimationMode.none;
      game.startGame();
    });
  }

  void _startNewGame() {
    setState(() {
      dialogMode = DialogMode.none;
      animationMode = AnimationMode.none;
      game.startGame();
    });
  }

  void _continueGame() {
    setState(() {
      dialogMode = DialogMode.none;
    });
  }

  void _endGame() {
    setState(() {
      dialogMode = DialogMode.main_menu;
      aiMode = AIMode.ai_vs_ai;
      animationMode = AnimationMode.none;
      game.startGame();
      _scheduleAiPlayIfNeeded();
    });
  }

  void _showPreferences() {
    setState(() {
      dialogMode = DialogMode.preferences;
    });
  }

  void _closePreferences() {
    setState(() {
      dialogMode = (aiMode == AIMode.ai_vs_ai ? DialogMode.main_menu : DialogMode.none);
    });
  }

  void _watchAiGame() {
    setState(() {
      dialogMode = DialogMode.none;
      if (aiMode != AIMode.ai_vs_ai) {
        aiMode = AIMode.ai_vs_ai;
        game.startGame();
        _scheduleAiPlayIfNeeded();
      }
    });
  }

  Widget _menuIcon() {
    return Padding(
      padding: EdgeInsets.all(10),
      child: FloatingActionButton(
        onPressed: _showMenu,
        child: Icon(aiMode == AIMode.ai_vs_ai ? Icons.menu : Icons.pause),
      ),
    );
  }

  void _showMenu() {
    setState(() {
      switch (aiMode) {
        case AIMode.ai_vs_ai:
          dialogMode = DialogMode.main_menu;
          break;
        default:
          dialogMode = DialogMode.game_paused;
          break;
      }
    });
  }

  void _showAboutDialog(BuildContext context) async {
    final aboutText = await DefaultAssetBundle.of(context).loadString('assets/doc/about.md');
    showAboutDialog(
        context: context,
        applicationName: 'Egyptian Mouse Pounce',
        applicationVersion: '1.1.0',
        applicationLegalese: '© 2020 Brian Nenninger',
        children: [
          Container(height: 15),
          MarkdownBody(
            data: aboutText,
            onTapLink: (text, href, title) => launch(href),
          ),
        ],
    );
  }

  Widget _preferencesDialog(final Size displaySize) {
    final minDim = min(displaySize.width, displaySize.height);
    final titleFontSize = min(36.0, minDim / 15.0);
    final baseFontSize = min(24.0, minDim / 18.0);

    final makeRuleCheckboxRow = (String title, RuleVariation v) {
      return TableRow(children: [
        CheckboxListTile(
          dense: true,
          title: Text(title, style: TextStyle(fontSize: baseFontSize)),
          isThreeLine: false,
          onChanged: (bool checked) async {
            setState(() => game.rules.setVariationEnabled(v, checked));
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setBool(prefsKeyForVariation(v), checked);
          },
          value: game.rules.isVariationEnabled(v),
        )
      ]);
    };

    final makeAiSpeedRow = () {
      final menuItemStyle = TextStyle(fontSize: baseFontSize * 0.9, fontWeight: FontWeight.normal);
      return _paddingAll(0, ListTile(
        title: Text('AI slap speed:', style: TextStyle(fontSize: baseFontSize)),
        trailing: DropdownButton(
          value: aiSlapSpeed,
          onChanged: (AISlapSpeed value) async {
            setState(() => aiSlapSpeed = value);
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString(aiSlapSpeedPrefsKey, value.toString());
          },
          items: [
            DropdownMenuItem(value: AISlapSpeed.slow, child: Text('Slow', style: menuItemStyle)),
            DropdownMenuItem(
                value: AISlapSpeed.medium, child: Text('Medium', style: menuItemStyle)),
            DropdownMenuItem(value: AISlapSpeed.fast, child: Text('Fast', style: menuItemStyle)),
          ],
        )),
      );
    };

    final makePenaltyRadioOptionRow = (String label, BadSlapPenaltyType penalty) {
      return TableRow(children: [
        RadioListTile(
          dense: true,
          title: Text(label, style: TextStyle(fontSize: baseFontSize)),
          groupValue: game.rules.badSlapPenalty,
          value: penalty,
          onChanged: (BadSlapPenaltyType p) async {
            setState(() {game.rules.badSlapPenalty = p;});
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setString(badSlapPenaltyPrefsKey, p.toString());
          },
        ),
      ]);
    };

    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Dialog(
          backgroundColor: Color.fromARGB(0xd0, 0xc0, 0xc0, 0xc0),
          insetPadding: EdgeInsets.all(0),
          child: Padding(padding: EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Text('Preferences', style: TextStyle(fontSize: titleFontSize))),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Table(
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    defaultColumnWidth: const IntrinsicColumnWidth(),
                    children: [
                      TableRow(children: [makeAiSpeedRow()]),
                      makeRuleCheckboxRow('Tens are stoppers', RuleVariation.ten_is_stopper),

                      TableRow(children: [Container(height: 10)]),

                      TableRow(children: [Text('Slap on:', style: TextStyle(fontSize: baseFontSize))]),
                      makeRuleCheckboxRow('Sandwiches', RuleVariation.slap_on_sandwich),
                      makeRuleCheckboxRow('Run of 3', RuleVariation.slap_on_run_of_3),
                      makeRuleCheckboxRow(
                          '4 of same suit', RuleVariation.slap_on_same_suit_of_4),

                      TableRow(children: [Container(height: 10)]),

                      TableRow(children: [Text('Penalty for wrong slap:', style: TextStyle(fontSize: baseFontSize))]),
                      makePenaltyRadioOptionRow('None', BadSlapPenaltyType.none),
                      makePenaltyRadioOptionRow('Penalty card', BadSlapPenaltyType.penalty_card),
                      makePenaltyRadioOptionRow("Can't slap for next 5 cards", BadSlapPenaltyType.slap_timeout),
                    ],
                  ),

                ],
              ),

              _paddingAll(10, Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [ElevatedButton(
                  style: raisedButtonStyle,
                  onPressed: _closePreferences,
                  child: Text('OK'),
                )],
              )),
            ],
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final displaySize = MediaQuery.of(context).size;
    final playerHeight = 120.0; // displaySize.height / 9;
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 0, 128, 0),
      body: Center(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: playerHeight,
                  width: double.infinity,
                  color: Colors.white70,
                  child: aiMode == AIMode.human_vs_human ?
                    _playerStatusWidget(game, 1, displaySize) :
                    _aiPlayerWidget(game, 1, displaySize)
                ),
                Expanded(
                  child:
                    Stack(children: [
                      Container(
                        child: _pileContent(game, displaySize),
                      ),
                      _noSlapWidget(0, displaySize),
                      _noSlapWidget(1, displaySize),
                    ]),
                ),
                Container(
                  height: playerHeight,
                  width: double.infinity,
                  color: Colors.white70,
                  child: aiMode == AIMode.ai_vs_ai ?
                        _aiPlayerWidget(game, 0, displaySize) :
                        _playerStatusWidget(game, 0, displaySize)
                ),
              ],
            ),
            if (dialogMode == DialogMode.main_menu) _mainMenuDialog(context, displaySize),
            if (dialogMode == DialogMode.game_paused)
              _pausedMenuDialog(displaySize),
            if (dialogMode == DialogMode.game_over) _gameOverDialog(displaySize),
            if (dialogMode == DialogMode.preferences) _preferencesDialog(displaySize),
            if (dialogMode == DialogMode.none) _menuIcon(),
          ],
        ),
      ),
    );
  }
}
