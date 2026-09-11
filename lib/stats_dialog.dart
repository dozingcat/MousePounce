import 'package:intl/intl.dart';
import 'dart:math';

import 'package:flutter/material.dart';

import 'stats.dart';

/// Shows cumulative statistics, with separate sections for games against the
/// computer and games between two humans.
class StatsDialog extends StatefulWidget {
  final Stats stats;
  final Size displaySize;
  final Color backgroundColor;
  final Color tableBackgroundColor;
  final void Function() onClose;
  final void Function() onReset;

  const StatsDialog({
    super.key,
    required this.stats,
    required this.displaySize,
    required this.backgroundColor,
    required this.tableBackgroundColor,
    required this.onClose,
    required this.onReset,
  });

  @override
  State<StatsDialog> createState() => _StatsDialogState();
}

class _StatsDialogState extends State<StatsDialog> {
  bool confirmingReset = false;

  Stats get stats => widget.stats;

  @override
  Widget build(BuildContext context) {
    final displaySize = widget.displaySize;
    final minDim = displaySize.shortestSide;
    final maxDim = displaySize.longestSide;
    final baseFontSize = min(maxDim / 36.0, minDim / 20.0);
    final titleFontSize = baseFontSize * 1.3;
    final sectionFontSize = baseFontSize * 1.1;

    final dialogWidth = 0.8 * minDim;
    final dialogPadding = (displaySize.width - dialogWidth) / 2;

    final hasVsHumanValues = (stats.vsHumanTotalCardsPlayed > 0);

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: Dialog(
        insetPadding: EdgeInsets.only(left: dialogPadding, right: dialogPadding),
        backgroundColor: widget.backgroundColor,
        child: Padding(
          padding: EdgeInsets.all(minDim * 0.03),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Statistics', style: TextStyle(fontSize: titleFontSize)),
              SizedBox(height: baseFontSize * 0.5),

              Flexible(child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  primary: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasVsHumanValues) _sectionTitle('Versus cats', sectionFontSize),
                      _statsTable(_vsAiRows(), baseFontSize),
                      if (hasVsHumanValues) ...[
                        _sectionTitle('Versus humans', sectionFontSize),
                        _statsTable(_vsHumanRows(), baseFontSize),
                      ],
                    ],
                  ),
                ),
              )),

              SizedBox(height: baseFontSize * 0.75),
              confirmingReset ? _resetConfirmation(baseFontSize) : _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buttons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => setState(() => confirmingReset = true),
          child: const Text('Reset...'),
        ),
        const SizedBox(width: 20),
        ElevatedButton(
          onPressed: widget.onClose,
          child: const Text('OK'),
        ),
      ],
    );
  }

  Widget _resetConfirmation(double fontSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Reset all statistics?', style: TextStyle(fontSize: fontSize)),
        SizedBox(height: fontSize * 0.5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => confirmingReset = false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                setState(() => confirmingReset = false);
                widget.onReset();
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ],
    );
  }

  List<_StatsRow> _vsAiRows() {
    return [
      _StatsRow('Games won', stats.vsAiWins),
      _StatsRow('Games lost', stats.vsAiLosses),
      _StatsRow('Cards played', stats.vsAiTotalCardsPlayed),
      _StatsRow('Your slaps', stats.vsAiSlapsByHuman),
      _StatsRow('Cat slaps', stats.vsAiSlapsByAi),
    ];
  }

  List<_StatsRow> _vsHumanRows() {
    return [
      _StatsRow('Player 1 wins', stats.vsHumanPlayer1Wins),
      _StatsRow('Player 2 wins', stats.vsHumanPlayer2Wins),
      _StatsRow('Cards played', stats.vsHumanTotalCardsPlayed),
      _StatsRow('Player 1 slaps', stats.vsHumanPlayer1Slaps),
      _StatsRow('Player 2 slaps', stats.vsHumanPlayer2Slaps),
    ];
  }

  Widget _sectionTitle(String title, double fontSize) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: fontSize * 0.3),
      child: Text(title, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statsTable(List<_StatsRow> rows, double fontSize) {
    final textStyle = TextStyle(fontSize: fontSize * 0.9);
    final cellPadding = EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: fontSize * 0.3);
    final numberFormat = NumberFormat.decimalPattern();
    return Container(
      color: widget.tableBackgroundColor,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(),
          1: IntrinsicColumnWidth(),
        },
        children: [
          for (final row in rows) TableRow(children: [
            Padding(padding: cellPadding, child: Text(row.name, style: textStyle)),
            Padding(padding: cellPadding, child:
                Text(numberFormat.format(row.value), textAlign: TextAlign.right, style: textStyle)),
          ]),
        ],
      ),
    );
  }
}

class _StatsRow {
  final String name;
  final int value;

  const _StatsRow(this.name, this.value);
}
