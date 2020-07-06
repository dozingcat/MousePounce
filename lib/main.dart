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

enum AnimationMode {none, play_card_back, play_card_front, pile_to_winner}

class _MyHomePageState extends State<MyHomePage> {
  Game game = Game();
  AnimationMode animationMode = AnimationMode.none;
  int pileMovingToPlayer;

  void _playCard() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      game.playCard();
      animationMode = AnimationMode.play_card_back;

      if (game.saveChanceWinner != null) {
        print("Winner: " + game.saveChanceWinner.toString());
        Future.delayed(const Duration(milliseconds: 500), () {
          setState(() {
            pileMovingToPlayer = game.saveChanceWinner;
            animationMode = AnimationMode.pile_to_winner;
          });
        });
      }
    });
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
        // width: double.infinity,
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

  Widget _pileContent(final Game game, final Size displaySize) {
    final pileCardsWithoutLast = game.pileCards.sublist(0, max(0, game.pileCards.length - 1));
    final lastPileCard = game.pileCards.isNotEmpty ? game.pileCards.last : null;
    switch (animationMode) {

      case AnimationMode.none:
        return Stack(
            children: game.pileCards.map((pc) => _pileCardWidget(pc, displaySize)).toList());

      case AnimationMode.play_card_back:
        return Stack(
              children: [
                ...pileCardsWithoutLast.map((pc) => _pileCardWidget(pc, displaySize)).toList(),
              if (lastPileCard != null) TweenAnimationBuilder(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 200),
                onEnd: () {
                  setState(() {
                    animationMode = AnimationMode.none;
                  });
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
          child: Stack(children:
              game.pileCards.map((pc) => _pileCardWidget(pc, displaySize)).toList()),
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _playerStatusWidget(game, 1, displaySize),
          Expanded(
            child: _pileContent(game, displaySize)
          ),
            _playerStatusWidget(game, 0, displaySize),
          ],
        ),
      ),
    );
  }
}
