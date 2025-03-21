import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:mouse_pounce/soundeffects.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'game.dart';

const appTitle = "Egyptian Mouse Pounce";
const appVersion = "1.4.0";
const appLegalese = "© 2020-2025 Brian Nenninger";

void main() {
  runApp(MyApp());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
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
  MyHomePage({Key? key}) : super(key: key);

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

const cardAspectRatio = 521.0 / 726;

const illegalSlapAnimationDuration = Duration(milliseconds: 600);
const moodDuration = Duration(milliseconds: 5000);
const moodFadeMillis = 500;

enum AIMode {human_vs_human, human_vs_ai, ai_vs_ai}

enum DialogMode {
  none,
  main_menu,
  preferences,
  game_paused,
  game_over,
  statistics,
  animation_speed_warning,
}

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

final soundEnabledPrefsKey = 'sound_enabled';
final aiSlapSpeedPrefsKey = 'ai_slap_speed';
final badSlapPenaltyPrefsKey = 'bad_slap_penalty';

final dialogBackgroundColor = Color.fromARGB(0xd0, 0xd8, 0xd8, 0xd8);
const dialogTableBackgroundColor = Color.fromARGB(0x80, 0xc0, 0xc0, 0xc0);

class _MyHomePageState extends State<MyHomePage> {
  Random rng = Random();
  late final SharedPreferences preferences;
  Game game = Game();
  AnimationMode animationMode = AnimationMode.none;
  AIMode aiMode = AIMode.ai_vs_ai;
  DialogMode dialogMode = DialogMode.main_menu;
  int? pileMovingToPlayer;
  int? badSlapPileWinner;
  PileCard? penaltyCard;
  bool penaltyCardPlayed = false;
  int? aiSlapPlayerIndex;
  int aiSlapCounter = 0;  // Used to check if a previously scheduled AI slap is still valid.
  late List<int> catImageNumbers;
  List<AIMood> aiMoods = [AIMood.none, AIMood.none];
  AISlapSpeed aiSlapSpeed = AISlapSpeed.medium;
  final numCatImages = 4;
  SoundEffectPlayer soundPlayer = SoundEffectPlayer();

  @override void initState() {
    super.initState();
    game = Game(rng: rng);
    catImageNumbers = _randomCatImageNumbers();
    penaltyCard = null;
    soundPlayer.init();
    _readPreferencesAndStartGame();
  }

  @override void didChangeDependencies() {
    super.didChangeDependencies();
    _preloadCardImages();
  }

  void _readPreferencesAndStartGame() async {
    this.preferences = await SharedPreferences.getInstance();
    soundPlayer.enabled = preferences.getBool(soundEnabledPrefsKey) ?? true;

    for (var v in RuleVariation.values) {
      bool enabled = this.preferences.getBool(prefsKeyForVariation(v)) ?? false;
      game.rules.setVariationEnabled(v, enabled);
    }

    final speedStr = this.preferences.getString(aiSlapSpeedPrefsKey) ?? '';
    aiSlapSpeed = AISlapSpeed.values.firstWhere(
        (s) => s.toString() == speedStr, orElse: () => AISlapSpeed.medium);

    final penaltyStr = this.preferences.getString(badSlapPenaltyPrefsKey) ?? '';
    game.rules.badSlapPenalty = BadSlapPenaltyType.values.firstWhere(
        (s) => s.toString() == penaltyStr, orElse: () => BadSlapPenaltyType.none);

    _scheduleAiPlayIfNeeded();

    runAnimationTimingTestIfNeeded();
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
    for (Rank r in Rank.values) {
      for (Suit s in Suit.values) {
        precacheImage(AssetImage(_imagePathForCard(PlayingCard(r, s))), context);
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
        if (thisGame == game && _shouldAiPlayCard() && badSlapPileWinner == null) {
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
        Future.delayed(const Duration(milliseconds: 1000), () {
          setState(() {
            if (this.animationMode == AnimationMode.waiting_to_move_pile) {
              this.pileMovingToPlayer = pileWinner;
              this.animationMode = AnimationMode.pile_to_winner;
            }
          });
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

  // Whether the AI should show a mood after winning or losing a pile, as determined by the number
  // and importance of cards in the pile.
  bool _aiHasMoodForPile(final List<PileCard> pileCards) {
    int total = 0;
    for (PileCard pc in pileCards) {
      int cval = moodWeights.containsKey(pc.card.rank) ? moodWeights[pc.card.rank]! : 1;
      total += cval;
    }
    return total > 16;
  }

  void _setAiMoods(final List<AIMood> moods) {
    setState(() => aiMoods = moods);
  }

  void _updateAiMoodsForPile(final List<PileCard> pileCards, final int pileWinner) {
    if (_aiHasMoodForPile(pileCards)) {
      var moods = pileWinner == 0 ? [AIMood.happy, AIMood.angry] : [AIMood.angry, AIMood.happy];
      _setAiMoods(moods);

      _playSoundForMoods(moods);
    }
  }

  void _updateAiMoodsForGameWinner(int winner) {
    var moods = winner == 0 ? [AIMood.very_happy, AIMood.angry] : [AIMood.angry, AIMood.very_happy];
    _setAiMoods(moods);
    _playSoundForMoods(moods);
  }

  void _playSoundForMoods(final List<AIMood> moods) {
    if (aiMode != AIMode.human_vs_ai) {
      return;
    }
    switch (moods[1]) {
      case AIMood.angry:
        soundPlayer.playMadSound();
        break;
      case AIMood.happy:
      case AIMood.very_happy:
        soundPlayer.playHappySound();
        break;
      default:
        break;
    }
  }

  void _movePileToWinner() {
    final cardsWon = [...game.pileCards];
    game.movePileToPlayer(pileMovingToPlayer!);
    int? winner = game.gameWinner();
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
    else {
      _updateAiMoodsForPile(cardsWon, pileMovingToPlayer!);
    }

    animationMode = AnimationMode.none;
    pileMovingToPlayer = null;
    _scheduleAiPlayIfNeeded();
  }

  void _playCardIfPlayerTurn(int pnum) {
    if (animationMode != AnimationMode.none) {
      return;
    }
    if (game.canPlayCard(pnum)) {
      setState(_playCard);
    }
  }

  void _doSlap(Offset globalOffset, double globalHeight) {
    if (animationMode != AnimationMode.none && animationMode != AnimationMode.waiting_to_move_pile) {
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
    final penalty = this.game.rules.badSlapPenalty;
    setState(() {
      this.animationMode = AnimationMode.illegal_slap;
      switch (penalty) {
        case BadSlapPenaltyType.penalty_card:
          // Only one penalty card per real card?
          if (!penaltyCardPlayed) {
            this.penaltyCard = game.addPenaltyCard(playerIndex);
            this.penaltyCardPlayed = (penaltyCard != null);
          }
          break;
        case BadSlapPenaltyType.slap_timeout:
          this.game.setSlapTimeoutCardsForPlayer(5, playerIndex);
          break;
        case BadSlapPenaltyType.opponent_wins_pile:
          this.badSlapPileWinner = 1 - playerIndex;
          break;
        default:
          break;
      }
    });
    // When the slap animation finishes, move the pile to the winner if there is one.
    Future.delayed(illegalSlapAnimationDuration, () {
      setState(() {
        this.penaltyCard = null;
        if (this.badSlapPileWinner != null) {
          this.pileMovingToPlayer = badSlapPileWinner;
          this.badSlapPileWinner = null;
          this.animationMode = AnimationMode.pile_to_winner;
        }
        else {
          final cw = this.game.challengeChanceWinner;
          if (cw != null) {
            this.pileMovingToPlayer = cw;
            this.animationMode = AnimationMode.pile_to_winner;
          }
          else {
            this.animationMode = AnimationMode.none;
          }
        }
      });
      this._scheduleAiPlayIfNeeded();
    });
  }

  Widget _playerStatusWidget(final Game game, final int playerIndex, final Size displaySize) {
    final enabled = game.canPlayCard(playerIndex);
    return Transform.rotate(
      angle: (playerIndex == 1) ? pi : 0,
        child: Padding(
          padding: EdgeInsets.all(0.025 * displaySize.height),
          child: ElevatedButton(
            onPressed: enabled ? (() => _playCardIfPlayerTurn(playerIndex)) : null,
            child: Padding(padding: EdgeInsets.all(10), child: Text (
              'Play card: ${game.playerCards[playerIndex].length} left',
              style: TextStyle(
                fontSize: Theme.of(context).textTheme.headlineMedium!.fontSize,
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

          // Fade mood bubbles in and out.
          if (moodImage != null) Positioned.fill(top: 5, bottom: 40, child:
            Transform.translate(
                offset: Offset(110, 0),
                child: TweenAnimationBuilder(
                  tween: Tween(begin: 0.0, end: moodDuration.inMilliseconds.toDouble()),
                  duration: moodDuration,
                  onEnd: () => setState(() => aiMoods = [AIMood.none, AIMood.none]),
                  child: Image(
                    image: AssetImage('assets/cats/$moodImage'),
                      fit: BoxFit.fitHeight,
                      alignment: Alignment.center,
                  ),
                  builder: (BuildContext context, double animMillis, Widget? child) {
                    double op = 1.0;
                    if (animMillis < moodFadeMillis) {
                      op = animMillis / moodFadeMillis;
                    }
                    else if (animMillis > moodDuration.inMilliseconds - moodFadeMillis) {
                      op = (moodDuration.inMilliseconds - animMillis) / moodFadeMillis;
                    }
                    return Opacity(
                      opacity: op,
                      child: child,
                    );
                  },
                )
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardImage(final PlayingCard card) {
    return LayoutBuilder(builder: (context, constraints) {
      double width = constraints.maxWidth;
      double height = constraints.maxHeight;
      double viewAspectRatio = width / height;

      final cardRect = (() {
        if (viewAspectRatio > cardAspectRatio) {
          // Full height, centered width.
          double cardWidth = height * cardAspectRatio;
          return Rect.fromLTWH(width / 2 - cardWidth / 2, 0, cardWidth, height);
          // return Rect.fromLTWH(0, 0, width, height);
        }
        else {
          // Full width, centered height.
          double cardHeight = width / cardAspectRatio;
          return Rect.fromLTWH(0, height / 2 - cardHeight / 2, width, cardHeight);
        }
      })();

      // For some reason Stack doesn't work as a child of Positioned.
      return Stack(children: [
        Positioned.fromRect(
          rect: cardRect,
          child: Image(
            image: AssetImage(_imagePathForCard(card)),
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
        Positioned.fromRect(
          rect: cardRect,
          child: Container(decoration: BoxDecoration(
            border: Border.all(
              color: const Color.fromRGBO(64, 64, 64, 1),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(cardRect.width * 0.04),
          )),
        ),
      ]);
    });
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
              image: AssetImage('assets/cats/paw${catImageNumbers[aiSlapPlayerIndex!]}.png'),
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
                builder: (BuildContext context, double animValue, Widget? child) {
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
          builder: (BuildContext context, double animValue, Widget? child) {
            return Transform.translate(
              offset: Offset(0, endYOff * animValue),
              child: child,
            );
          },
        );

      case AnimationMode.illegal_slap:
        final pc = this.penaltyCard;
        return Stack(children: [
          if (pc != null) TweenAnimationBuilder(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: illegalSlapAnimationDuration,
            builder: (BuildContext context, double animValue, Widget? child) {
              double startYOff = displaySize.height / 2 * (pc.playedBy == 0 ? 1 : -1);
              return Transform.translate(
                offset: Offset(0, startYOff * (1 - animValue)),
                child: _pileCardWidget(pc, displaySize, rotationFrac: animValue),
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
            builder: (BuildContext context, double animValue, Widget? child) {
              return Opacity(
                opacity: min(animValue, 1),
                child: child,
              );
            },
          ),
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
                        // primary: Colors.blue,
                        backgroundColor: Colors.white,
                      ),
                    onPressed: () {},
                    child: Text(numTimeoutCards.toString(),
                    style: TextStyle(fontSize: size * 0.24, height: 0))),
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

  TableRow _makeButtonRow(String title, void Function() onPressed) {
    return TableRow(children: [
      Padding(
        padding: EdgeInsets.all(8),
        child: ElevatedButton(
          onPressed: onPressed,
          child: Text(title),
        ),
      ),
    ]);
  }

  Widget _mainMenuDialog(final BuildContext context, final Size displaySize) {
    final minDim = min(displaySize.width, displaySize.height);

    return Container(
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: Dialog(
            backgroundColor: dialogBackgroundColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _paddingAll(10, Text(
                    'Egyptian Mouse Pounce',
                    style: TextStyle(
                      fontSize: min(minDim / 18, 40),
                    )
                )),
                Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    _makeButtonRow('Play against computer', _startOnePlayerGame),
                    _makeButtonRow('Play against human', _startTwoPlayerGame),
                    _makeButtonRow('Watch the cats', _watchAiGame),
                    _makeButtonRow('Preferences...', _showPreferences),
                    _makeButtonRow('About...', () => _showAboutDialog(context)),
                  ],
                ),
                Container(height: 10, width: 0),
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
          backgroundColor: dialogBackgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  _makeButtonRow("Continue", _continueGame),
                  _makeButtonRow("End Game", _endGame),
                ],
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
          backgroundColor: dialogBackgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Text(
                  title,
                  style: TextStyle(
                    fontSize: min(displaySize.width / 15, 40),
                  )
              )),
              _paddingAll(10, Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  _makeButtonRow("Rematch", _startNewGame),
                  _makeButtonRow("Main menu", _endGame),
                ],
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
      aiSlapCounter++;
      game.startGame();
    });
  }

  void _startTwoPlayerGame() {
    setState(() {
      aiMode = AIMode.human_vs_human;
      dialogMode = DialogMode.none;
      animationMode = AnimationMode.none;
      aiSlapCounter++;
      game.startGame();
    });
  }

  void _startNewGame() {
    setState(() {
      dialogMode = DialogMode.none;
      animationMode = AnimationMode.none;
      aiSlapCounter++;
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
      aiSlapCounter++;
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
        applicationName: appTitle,
        applicationVersion: appVersion,
        applicationLegalese: appLegalese,
        children: [
          Container(height: 15),
          MarkdownBody(
            data: aboutText,
            onTapLink: (text, href, title) => launch(href!),
            // https://github.com/flutter/flutter_markdown/issues/311
            listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
          ),
        ],
    );
  }

  void setSoundEnabled(bool enabled) {
    setState(() {
      soundPlayer.enabled = enabled;
    });
    preferences.setBool(soundEnabledPrefsKey, enabled);
    if (Random().nextBool()) {
      soundPlayer.playMadSound();
    }
    else {
      soundPlayer.playHappySound();
    }
  }

  Widget _preferencesDialog(final Size displaySize) {
    final minDim = displaySize.shortestSide;
    final maxDim = displaySize.longestSide;
    final baseFontSize = min(maxDim / 36.0, minDim / 20.0);
    final titleFontSize = baseFontSize * 1.3;

    final makeRuleCheckboxRow = (String title, RuleVariation v, [double fontScale = 1.0]) {
      return CheckboxListTile(
          dense: true,
          title: Text(title, style: TextStyle(fontSize: baseFontSize * fontScale)),
          isThreeLine: false,
          onChanged: (bool? checked) {
            setState(() => game.rules.setVariationEnabled(v, checked == true));
            this.preferences.setBool(prefsKeyForVariation(v), checked == true);
          },
          value: game.rules.isVariationEnabled(v),
        );
    };

    final makeAiSpeedRow = () {
      final menuItemStyle = TextStyle(fontSize: baseFontSize * 0.9, color: Colors.blue, fontWeight: FontWeight.bold);
      return _paddingAll(0, ListTile(
        title: Text('Cat slap speed:', style: TextStyle(fontSize: baseFontSize)),
        trailing: DropdownButton(
          value: aiSlapSpeed,
          onChanged: (AISlapSpeed? value) {
            setState(() => aiSlapSpeed = value!);
            this.preferences.setString(aiSlapSpeedPrefsKey, value.toString());
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

    final makeSlapPenaltyRow = () {
      final menuItemStyle = TextStyle(fontSize: baseFontSize * 0.9, color: Colors.blue, fontWeight: FontWeight.bold);
      return DropdownButton(
            value: game.rules.badSlapPenalty,
            onChanged: (BadSlapPenaltyType? p) {
              setState(() => game.rules.badSlapPenalty = p!);
              this.preferences.setString(badSlapPenaltyPrefsKey, p.toString());
            },
            items: [
              DropdownMenuItem(value: BadSlapPenaltyType.none, child: Text('None', style: menuItemStyle)),
              DropdownMenuItem(
                  value: BadSlapPenaltyType.penalty_card, child: Text('Penalty card', style: menuItemStyle)),
              DropdownMenuItem(value: BadSlapPenaltyType.slap_timeout, child: Text("Can't slap for next 5 cards", style: menuItemStyle)),
              DropdownMenuItem(value: BadSlapPenaltyType.opponent_wins_pile, child: Text('Opponent wins pile', style: menuItemStyle)),
            ],
          );
    };

    final dialogWidth = 0.8 * minDim;
    final dialogPadding = (displaySize.width - dialogWidth) / 2;
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Dialog(
        insetPadding: EdgeInsets.only(left: dialogPadding, right: dialogPadding),
        backgroundColor: dialogBackgroundColor,
        child: Padding(
          padding: EdgeInsets.all(minDim * 0.03),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Preferences', style: TextStyle(fontSize: titleFontSize)),

              Flexible(child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                primary: true,
                child: Container(
                  color: dialogTableBackgroundColor,
                  child: Column(children: [
                    CheckboxListTile(
                      dense: true,
                      title: Text("Enable sound", style: TextStyle(fontSize: baseFontSize)),
                      value: soundPlayer.enabled,
                      onChanged: (bool? checked) {
                        setSoundEnabled(checked == true);
                      },
                    ),

                    makeAiSpeedRow(),
                    makeRuleCheckboxRow('Tens are stoppers', RuleVariation.ten_is_stopper),
                    SizedBox(height: baseFontSize * 0.25),

                    Row(children: [Text('Slap on:', style: TextStyle(fontSize: baseFontSize))]),
                    makeRuleCheckboxRow('Sandwiches', RuleVariation.slap_on_sandwich, 0.85),
                    makeRuleCheckboxRow('Run of 3', RuleVariation.slap_on_run_of_3, 0.85),
                    makeRuleCheckboxRow(
                        '4 of same suit', RuleVariation.slap_on_same_suit_of_4, 0.85),
                    makeRuleCheckboxRow(
                        'Adds to 10', RuleVariation.slap_on_add_to_10, 0.85),
                    makeRuleCheckboxRow('Marriages', RuleVariation.slap_on_marriage, 0.85),
                    makeRuleCheckboxRow('Divorces', RuleVariation.slap_on_divorce, 0.85),

                    Container(height: baseFontSize * 0.25),

                    Row(children: [Text('Penalty for wrong slap:', style: TextStyle(fontSize: baseFontSize))]),
                    Row(children: [makeSlapPenaltyRow()]),
              ]))))),

              SizedBox(height: 15, width: 0),
              ElevatedButton(
                onPressed: _closePreferences,
                child: Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A Fluttter bug causes most animations to take nearly zero time if the
  // ""Transition animation scale" option is set to off. This makes the game
  // unplayable, so we try to detect it by running a test animation on startup.
  // If the animation finishes much faster than it's supposed to, we're probably
  // in that condition and we notify the user.
  // See https://github.com/flutter/flutter/issues/164287
  bool runningTimingTestAnimation = false;
  int timingTestAnimationStartTimestamp = 0;

  void runAnimationTimingTestIfNeeded() {
    if (Platform.isAndroid) {
      Future.delayed(Duration(milliseconds: 1000), () {
        setState(() {
          timingTestAnimationStartTimestamp = DateTime.now().millisecondsSinceEpoch;
          runningTimingTestAnimation = true;
          // print("*** Started test animation");
        });
      });
    }
  }

  Widget timingTestAnimation() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(seconds: 3),
      onEnd: timingTestAnimationFinished,
      child: const Positioned(left: 0, top: 0, height: 0, width: 0, child: SizedBox()),
      builder: (BuildContext context, double animMillis, Widget? child) {
        return child!;
      },
    );
  }

  void timingTestAnimationFinished() {
    int elapsed = DateTime.now().millisecondsSinceEpoch - timingTestAnimationStartTimestamp;
    // print("*** test animation done, elapsed: $elapsed");
    if (elapsed < 1000) {
      setState(() {dialogMode = DialogMode.animation_speed_warning;});
    }
  }

  Widget animationSpeedWarningDialog(final Size displaySize) {
    String animationMessage = 'If animations are too fast, check the "Transition animation scale" option in the Settings app and make sure it\'s not set to "off".';
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Dialog(
          backgroundColor: dialogBackgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: EdgeInsets.all(24), child: Text(
                  animationMessage,
                  style: TextStyle(
                    fontSize: 20,
                  )
              )),
              Padding(padding: EdgeInsets.only(bottom: 24), child: ElevatedButton(
                onPressed: () {setState(() {dialogMode = DialogMode.main_menu;});},
                child: Text('OK'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // displayPadding accounts for display cutouts which we don't want to draw over.
    final fullDisplaySize = MediaQuery.sizeOf(context);
    final displayPadding = MediaQuery.paddingOf(context);
    final displaySize = Size(
        fullDisplaySize.width - displayPadding.left - displayPadding.right,
        fullDisplaySize.height - displayPadding.top - displayPadding.bottom);

    final playerHeight = 120.0; // displaySize.height / 9;

    const cardAreaBackgroundColor = Color.fromARGB(255, 0, 128, 0);
    const backgroundColor = Color.fromARGB(255, 187, 216, 182);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Padding(padding: displayPadding, child: Center(
        child: Stack(
          children: [
            // Use a stack with the card pile last so that the cards will draw
            // over the player areas when they're animating in.
            Stack(
              children: [
                if (runningTimingTestAnimation) timingTestAnimation(),

                Positioned(
                  left: 0,
                  width: displaySize.width,
                  top: 0,
                  height: playerHeight,
                  child: Container(
                    height: playerHeight,
                    width: double.infinity,
                    child: aiMode == AIMode.human_vs_human ?
                      _playerStatusWidget(game, 1, displaySize) :
                      _aiPlayerWidget(game, 1, displaySize)
                  ),
                ),
                Positioned(
                  left: 0,
                  width: displaySize.width,
                  top: displaySize.height - playerHeight,
                  height: playerHeight,
                  child: Container(
                      height: playerHeight,
                      width: double.infinity,
                      child: aiMode == AIMode.ai_vs_ai ?
                      _aiPlayerWidget(game, 0, displaySize) :
                      _playerStatusWidget(game, 0, displaySize)
                  ),
                ),
                Positioned(
                  left: 0,
                  width: displaySize.width,
                  top: playerHeight,
                  height: displaySize.height - 2 * playerHeight,
                  child: Container(
                    color: cardAreaBackgroundColor,
                    child:
                      Stack(children: [
                        Container(
                          child: _pileContent(game, displaySize),
                        ),
                        _noSlapWidget(0, displaySize),
                        _noSlapWidget(1, displaySize),
                      ]),
                  ),
                ),
              ],
            ),
            if (dialogMode == DialogMode.main_menu) _mainMenuDialog(context, displaySize),
            if (dialogMode == DialogMode.game_paused) _pausedMenuDialog(displaySize),
            if (dialogMode == DialogMode.game_over) _gameOverDialog(displaySize),
            if (dialogMode == DialogMode.preferences) _preferencesDialog(displaySize),
            if (dialogMode == DialogMode.animation_speed_warning) animationSpeedWarningDialog(displaySize),
            if (dialogMode == DialogMode.none) _menuIcon(),
            // Text(this.animationMode.toString()),
          ],
        ),
      ),
    ));
  }
}
