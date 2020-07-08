import 'dart:math';
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

class _MyHomePageState extends State<MyHomePage> {
  Game game = Game();
  AnimationMode animationMode = AnimationMode.none;
  AIMode aiMode = AIMode.human_vs_ai;
  int pileMovingToPlayer;
  int aiSlapPlayerIndex;
  int aiSlapCounter = 0;

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
    return aiMode == AIMode.ai_vs_ai ||
        (aiMode == AIMode.human_vs_ai && game.currentPlayerIndex == 1);
  }

  void _scheduleAiPlayIfNeeded() {
    if (_shouldAiPlayCard()) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _playCard();
      });
    }
  }

  void _playCardFinished() {
    animationMode = AnimationMode.none;
    if (game.canSlapPile()) {
      final delayMillis = 1000;
      aiSlapCounter++;
      final counterSnapshot = aiSlapCounter;
      Future.delayed(Duration(milliseconds: delayMillis), () {
        if (counterSnapshot == aiSlapCounter) {
          setState(() {
            animationMode = AnimationMode.ai_slap;
            pileMovingToPlayer = 1;
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
      final pileWinner = game.saveChanceWinner;
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
      Future.delayed(const Duration(milliseconds: 2000), () {
        setState(() {
          game.startGame();
        });
      });
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
    final pnum = (globalOffset.dy > globalHeight / 2) ? 0 : 1;
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
    return GestureDetector(
        onTap: () {_playCardIfPlayerTurn(playerIndex);},
        child: Padding(
          padding: EdgeInsets.all(0.025 * displaySize.height),

          child: Text (
              'Cards: ${game.playerCards[playerIndex].length}',
              style: TextStyle(
                fontSize: Theme.of(context).textTheme.headline4.fontSize,
                color: game.currentPlayerIndex == playerIndex ? Colors.green : Colors.grey,
              )
          ),
        )
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
                heightFactor: 0.75,
                widthFactor: 0.75,
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
          Image(
              image: AssetImage('assets/cats/paw1.png'),
              alignment: Alignment.center,
          ),
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

  @override
  Widget build(BuildContext context) {
    print(animationMode);
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // _playerStatusWidget(game, 1, displaySize),
            Container(
              color: Colors.white70,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Transform.translate(offset: Offset(0, 10), child: Image(
                  image: AssetImage('assets/cats/cat1.png'),
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                )),
            ])),
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
                children: [_playerStatusWidget(game, 0, displaySize)],
            )),
          ],
        ),
      ),
    );
  }
}
