import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cumulative statistics for games with at least one human player.
/// Games against the computer and games between two humans are tracked
/// separately. Instances are immutable; the update methods return new copies.
class Stats {
  final int vsAiWins;
  final int vsAiLosses;
  final int vsAiTotalCardsPlayed;
  final int vsAiSlapsByHuman;
  final int vsAiSlapsByAi;

  final int vsHumanPlayer1Wins;
  final int vsHumanPlayer2Wins;
  final int vsHumanTotalCardsPlayed;
  final int vsHumanPlayer1Slaps;
  final int vsHumanPlayer2Slaps;

  const Stats({
    required this.vsAiWins,
    required this.vsAiLosses,
    required this.vsAiTotalCardsPlayed,
    required this.vsAiSlapsByHuman,
    required this.vsAiSlapsByAi,
    required this.vsHumanPlayer1Wins,
    required this.vsHumanPlayer2Wins,
    required this.vsHumanTotalCardsPlayed,
    required this.vsHumanPlayer1Slaps,
    required this.vsHumanPlayer2Slaps,
  });

  static const Stats empty = Stats(
    vsAiWins: 0,
    vsAiLosses: 0,
    vsAiTotalCardsPlayed: 0,
    vsAiSlapsByHuman: 0,
    vsAiSlapsByAi: 0,
    vsHumanPlayer1Wins: 0,
    vsHumanPlayer2Wins: 0,
    vsHumanTotalCardsPlayed: 0,
    vsHumanPlayer1Slaps: 0,
    vsHumanPlayer2Slaps: 0,
  );

  int get vsAiGamesPlayed => vsAiWins + vsAiLosses;
  int get vsHumanGamesPlayed => vsHumanPlayer1Wins + vsHumanPlayer2Wins;

  Stats copyWith({
    int? vsAiWins,
    int? vsAiLosses,
    int? vsAiTotalCardsPlayed,
    int? vsAiSlapsByHuman,
    int? vsAiSlapsByAi,
    int? vsHumanPlayer1Wins,
    int? vsHumanPlayer2Wins,
    int? vsHumanTotalCardsPlayed,
    int? vsHumanPlayer1Slaps,
    int? vsHumanPlayer2Slaps,
  }) {
    return Stats(
      vsAiWins: vsAiWins ?? this.vsAiWins,
      vsAiLosses: vsAiLosses ?? this.vsAiLosses,
      vsAiTotalCardsPlayed: vsAiTotalCardsPlayed ?? this.vsAiTotalCardsPlayed,
      vsAiSlapsByHuman: vsAiSlapsByHuman ?? this.vsAiSlapsByHuman,
      vsAiSlapsByAi: vsAiSlapsByAi ?? this.vsAiSlapsByAi,
      vsHumanPlayer1Wins: vsHumanPlayer1Wins ?? this.vsHumanPlayer1Wins,
      vsHumanPlayer2Wins: vsHumanPlayer2Wins ?? this.vsHumanPlayer2Wins,
      vsHumanTotalCardsPlayed: vsHumanTotalCardsPlayed ?? this.vsHumanTotalCardsPlayed,
      vsHumanPlayer1Slaps: vsHumanPlayer1Slaps ?? this.vsHumanPlayer1Slaps,
      vsHumanPlayer2Slaps: vsHumanPlayer2Slaps ?? this.vsHumanPlayer2Slaps,
    );
  }

  // In all of the update methods, player 0 is the human in games against the
  // computer, and player 1 is the computer.

  Stats withVsAiCardPlayed() {
    return copyWith(vsAiTotalCardsPlayed: vsAiTotalCardsPlayed + 1);
  }

  Stats withVsAiSlap(int playerIndex) {
    return playerIndex == 0 ?
        copyWith(vsAiSlapsByHuman: vsAiSlapsByHuman + 1) :
        copyWith(vsAiSlapsByAi: vsAiSlapsByAi + 1);
  }

  Stats withVsAiGameWon(int winnerIndex) {
    return winnerIndex == 0 ?
        copyWith(vsAiWins: vsAiWins + 1) :
        copyWith(vsAiLosses: vsAiLosses + 1);
  }

  Stats withVsHumanCardPlayed() {
    return copyWith(vsHumanTotalCardsPlayed: vsHumanTotalCardsPlayed + 1);
  }

  Stats withVsHumanSlap(int playerIndex) {
    return playerIndex == 0 ?
        copyWith(vsHumanPlayer1Slaps: vsHumanPlayer1Slaps + 1) :
        copyWith(vsHumanPlayer2Slaps: vsHumanPlayer2Slaps + 1);
  }

  Stats withVsHumanGameWon(int winnerIndex) {
    return winnerIndex == 0 ?
        copyWith(vsHumanPlayer1Wins: vsHumanPlayer1Wins + 1) :
        copyWith(vsHumanPlayer2Wins: vsHumanPlayer2Wins + 1);
  }

  Map<String, dynamic> toJson() {
    return {
      "__version__": 1,
      "vsAiWins": vsAiWins,
      "vsAiLosses": vsAiLosses,
      "vsAiTotalCardsPlayed": vsAiTotalCardsPlayed,
      "vsAiSlapsByHuman": vsAiSlapsByHuman,
      "vsAiSlapsByAi": vsAiSlapsByAi,
      "vsHumanPlayer1Wins": vsHumanPlayer1Wins,
      "vsHumanPlayer2Wins": vsHumanPlayer2Wins,
      "vsHumanTotalCardsPlayed": vsHumanTotalCardsPlayed,
      "vsHumanPlayer1Slaps": vsHumanPlayer1Slaps,
      "vsHumanPlayer2Slaps": vsHumanPlayer2Slaps,
    };
  }

  // Missing fields default to 0 so that stats added in future versions can be
  // read from JSON written by older versions.
  static Stats fromJson(final Map<String, dynamic> json) {
    int field(String key) => (json[key] as num?)?.toInt() ?? 0;
    return Stats(
      vsAiWins: field("vsAiWins"),
      vsAiLosses: field("vsAiLosses"),
      vsAiTotalCardsPlayed: field("vsAiTotalCardsPlayed"),
      vsAiSlapsByHuman: field("vsAiSlapsByHuman"),
      vsAiSlapsByAi: field("vsAiSlapsByAi"),
      vsHumanPlayer1Wins: field("vsHumanPlayer1Wins"),
      vsHumanPlayer2Wins: field("vsHumanPlayer2Wins"),
      vsHumanTotalCardsPlayed: field("vsHumanTotalCardsPlayed"),
      vsHumanPlayer1Slaps: field("vsHumanPlayer1Slaps"),
      vsHumanPlayer2Slaps: field("vsHumanPlayer2Slaps"),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Stats &&
        vsAiWins == other.vsAiWins &&
        vsAiLosses == other.vsAiLosses &&
        vsAiTotalCardsPlayed == other.vsAiTotalCardsPlayed &&
        vsAiSlapsByHuman == other.vsAiSlapsByHuman &&
        vsAiSlapsByAi == other.vsAiSlapsByAi &&
        vsHumanPlayer1Wins == other.vsHumanPlayer1Wins &&
        vsHumanPlayer2Wins == other.vsHumanPlayer2Wins &&
        vsHumanTotalCardsPlayed == other.vsHumanTotalCardsPlayed &&
        vsHumanPlayer1Slaps == other.vsHumanPlayer1Slaps &&
        vsHumanPlayer2Slaps == other.vsHumanPlayer2Slaps;
  }

  @override
  int get hashCode => Object.hash(
      vsAiWins, vsAiLosses, vsAiTotalCardsPlayed, vsAiSlapsByHuman, vsAiSlapsByAi,
      vsHumanPlayer1Wins, vsHumanPlayer2Wins, vsHumanTotalCardsPlayed,
      vsHumanPlayer1Slaps, vsHumanPlayer2Slaps);

  @override
  String toString() => "Stats(${jsonEncode(toJson())})";
}
