import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

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
}

enum AIMode {human_vs_human, human_vs_ai, ai_vs_ai}

enum DialogMode {none, main_menu, preferences, game_paused, game_over, statistics}

class _MyHomePageState extends State<MyHomePage> {
  Random rng = Random();
  Game game = Game();
  AnimationMode animationMode = AnimationMode.none;
  AIMode aiMode = AIMode.ai_vs_ai;
  DialogMode dialogMode = DialogMode.main_menu;
  int pileMovingToPlayer;
  int aiSlapPlayerIndex;
  int aiSlapCounter = 0;
  List<int> catImageNumbers;
  final numCatImages = 4;

  _MyHomePageState() {
    game = Game(rng: rng);
    catImageNumbers = _randomCatImageNumbers();
    _scheduleAiPlayIfNeeded();
  }

  List<int> _randomCatImageNumbers() {
    int c1 = rng.nextInt(numCatImages);
    int c2 = (c1 + 1 + rng.nextInt(numCatImages - 1)) % numCatImages;
    return [c1 + 1, c2 + 1];
  }

  void _playCard() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      game.playCard();
      animationMode = AnimationMode.play_card_back;
      aiSlapCounter++;
    });
  }

  bool _shouldAiPlayCard() {
    if (game.gameWinner() != null) {
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
    return 300 + (500 * rng.nextDouble()).toInt();
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
              setState(() {
                animationMode = AnimationMode.pile_to_winner;
              });
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
          setState(() {
            animationMode = AnimationMode.pile_to_winner;
          });
        });
      }
      else {
        _scheduleAiPlayIfNeeded();
      }
    }
  }

  void _movePileToWinner() {
    game.movePileToPlayer(pileMovingToPlayer);
    int winner = game.gameWinner();
    if (winner != null) {
      print("Player ${winner} wins!");
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
      setState(() {
        _playCard();
      });
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
    print('Tap: ${globalOffset.dy} ${globalHeight} ${pnum}');
    if (game.canSlapPile()) {
      setState(() {
        aiSlapCounter++;
        pileMovingToPlayer = pnum;
        animationMode = AnimationMode.pile_to_winner;
      });
    }
  }

  Widget _playerStatusWidget(final Game game, final int playerIndex, final Size displaySize) {
    final enabled = game.currentPlayerIndex == playerIndex;
    return Transform.rotate(
      angle: (playerIndex == 1) ? pi : 0,
        child: Padding(
          padding: EdgeInsets.all(0.025 * displaySize.height),
          child: RaisedButton(
            onPressed: enabled ? (() {_playCardIfPlayerTurn(playerIndex);}) : null,
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
    return Transform.rotate(
      angle: playerIndex == 1 ? 0 : pi,
      child: Transform.translate(
        offset: Offset(0, 10),
        child: Image(
          image: AssetImage('assets/cats/cat${catImageNumbers[playerIndex]}.png'),
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
        ),
      ),
    );
  }

  Widget _cardImage(final PlayingCard card) {
    return Image(
      image: AssetImage('assets/cards/' + card.asciiString() + '.png'),
      fit: BoxFit.contain,
      alignment: Alignment.center,
    );
  }

  Widget _pileCardWidget(final PileCard pc, final Size displaySize) {
    final minDim = min(displaySize.width, displaySize.height);
    final maxOffset = minDim * 0.1;
    return Container(
        height: double.infinity,
        width: double.infinity,
        child: Transform.translate(
            offset: Offset(pc.xOffset * maxOffset, pc.yOffset * maxOffset),
            child:
            Transform.rotate(
              angle: pc.rotation * pi / 12,
              child: FractionallySizedBox(
                alignment: Alignment.center,
                heightFactor: 0.7,
                widthFactor: 0.7,
                child: GestureDetector(
                    onTapDown: (TapDownDetails tap) {
                      _doSlap(tap.globalPosition, displaySize.height);
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
                onEnd: () {
                  setState(_playCardFinished);
                },
                child: _pileCardWidget(lastPileCard, displaySize),
                builder: (BuildContext context, double animValue, Widget child) {
                  double startYOff = displaySize.height / 2 * (lastPileCard.playedBy == 0 ? 1 : -1);
                  return Transform.translate(
                    offset: Offset(0, startYOff * (1 - animValue)),
                    child: child,
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
          onEnd: () {
            setState(_movePileToWinner);
          },
          child: Stack(children: _pileCardWidgets(game.pileCards, displaySize)),
          builder: (BuildContext context, double animValue, Widget child) {
            return Transform.translate(
              offset: Offset(0, endYOff * animValue),
              child: child,
            );
          },
        );

      default:
        return Container();
    }
  }

  Widget _paddingAll(final double paddingPx, final Widget child) {
    return Padding(padding: EdgeInsets.all(paddingPx), child: child);
  }

  Widget _mainMenuDialog(final Size displaySize) {
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
                      fontSize: displaySize.width / 20,
                    )
                )),
                _paddingAll(10, Row(
                  children: [Expanded(
                    child: RaisedButton(
                      onPressed: _startOnePlayerGame,
                      child: Text('Play against computer'),
                    ),
                  )],
                )),
                _paddingAll(10, Row(
                  children: [Expanded(
                    child: RaisedButton(
                      onPressed: _startTwoPlayerGame,
                      child: Text('Play against human'),
                    ),
                  )],
                )),
                _paddingAll(10, Row(
                  children: [Expanded(
                    child: RaisedButton(
                      onPressed: _showPreferences,
                      child: Text('Preferences'),
                    ),
                  )],
                )),
                _paddingAll(10, Row(
                  children: [Expanded(
                    child: RaisedButton(
                      onPressed: _watchAiGame,
                      child: Text('Watch the cats'),
                    ),
                  )],
                )),
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
                  child: RaisedButton(
                    onPressed: _continueGame,
                    child: Text('Continue'),
                  ),
                )],
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: RaisedButton(
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
                    fontSize: displaySize.width / 20,
                  )
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: RaisedButton(
                    onPressed: _startNewGame,
                    child: Text('Rematch'),
                  ),
                )],
              )),
              _paddingAll(10, Row(
                children: [Expanded(
                  child: RaisedButton(
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

  Widget _preferencesDialog(final Size displaySize) {
    final makeCheckboxRow = (String title, Function(bool) setter, bool Function() getter) {
      return TableRow(children: [
        Text(title),
        Checkbox(
          onChanged: (bool checked) {setState(() {setter(checked);});},
          value: getter(),
        )
      ]);
    };

    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Dialog(
          backgroundColor: Color.fromARGB(0xc0, 0xc0, 0xc0, 0xc0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paddingAll(10, Text(
                'Preferences',
                style: TextStyle(
                  fontSize: displaySize.width / 20,
                )
              )),
              Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                defaultColumnWidth: const IntrinsicColumnWidth(),
                children: [
                  makeCheckboxRow('Tens are stoppers',
                          (bool checked) {game.rules.tenIsStopper = checked;},
                          () {return game.rules.tenIsStopper;}
                  ),
                  makeCheckboxRow('Slap on sandwiches',
                          (bool checked) {game.rules.slapOnSandwich = checked;},
                          () {return game.rules.slapOnSandwich;}
                  ),
                  makeCheckboxRow('Slap on run of 3',
                          (bool checked) {game.rules.slapOnRunOf3 = checked;},
                          () {return game.rules.slapOnRunOf3;}
                  ),
                  makeCheckboxRow('Slap on 4 of same suit',
                          (bool checked) {game.rules.slapOnSameSuitOf4 = checked;},
                          () {return game.rules.slapOnSameSuitOf4;}
                  ),
                ],
              ),
              _paddingAll(10, Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [RaisedButton(
                    onPressed: _closePreferences,
                    child: Text('OK'),
                  ),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // print(animationMode);
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    final displaySize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 0, 128, 0),
      body: Center(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // _playerStatusWidget(game, 1, displaySize),
                Container(
                  color: Colors.white70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      aiMode == AIMode.human_vs_human ?
                      _playerStatusWidget(game, 1, displaySize) :
                      _aiPlayerWidget(game, 1, displaySize),
                    ],
                  ),
                ),
                Expanded(
                  child:
                    Container(
                      child: _pileContent(game, displaySize),
                    ),
                ),
                Container(
                  color: Colors.white70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      aiMode == AIMode.ai_vs_ai ?
                        _aiPlayerWidget(game, 0, displaySize) :
                        _playerStatusWidget(game, 0, displaySize),
                    ],
                )),
              ],
            ),
            if (dialogMode == DialogMode.main_menu) _mainMenuDialog(displaySize),
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
