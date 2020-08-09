import 'package:flutter_test/flutter_test.dart';
import 'package:mouse_pounce/game.dart';

void main() {
  test('Game should be initialized', () {
    final game = Game();

    expect(game.numPlayers, 2);
    expect(game.playerCards[0].length, 26);
    expect(game.playerCards[1].length, 26);
  });
}
