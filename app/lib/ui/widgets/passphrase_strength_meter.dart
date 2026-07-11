import 'package:flutter/material.dart';
import 'package:zxcvbnm/languages/en.dart';
import 'package:zxcvbnm/zxcvbnm.dart';

/// One shared estimator; constructing it wires up the (sizeable) English
/// dictionaries once. Everything runs locally and synchronously — nothing
/// about the passphrase leaves the process.
final Zxcvbnm _zxcvbnm = Zxcvbnm(dictionaries: dictionaries);

/// A zxcvbn strength estimate reduced to what the meter shows.
class PassphraseStrength {
  const PassphraseStrength(this.score, this.warning);

  /// zxcvbn score, 0 (weakest) to 4 (strongest).
  final int score;

  /// Targeted feedback for a weak passphrase, when zxcvbn has any.
  final String? warning;

  String get label => switch (score) {
        0 => 'Very weak',
        1 => 'Weak',
        2 => 'Fair',
        3 => 'Good',
        _ => 'Strong',
      };
}

/// Estimates [passphrase] with zxcvbn (guess-based, catches common passwords,
/// words, dates, keyboard walks — not just character classes).
PassphraseStrength estimatePassphrase(String passphrase) {
  final result = _zxcvbnm(passphrase);
  return PassphraseStrength(result.score, result.feedback.warning);
}

/// The strength bar + label under a passphrase field. Purely advisory: it
/// never blocks submission — vault creation is the trust moment, and a meter
/// that nags less is read more. Renders nothing while the field is empty.
class PassphraseStrengthMeter extends StatelessWidget {
  const PassphraseStrengthMeter({super.key, required this.passphrase});

  final String passphrase;

  static const List<Color> _colors = [
    Color(0xFFD32F2F), // 0 very weak
    Color(0xFFE64A19), // 1 weak
    Color(0xFFF9A825), // 2 fair
    Color(0xFF7CB342), // 3 good
    Color(0xFF388E3C), // 4 strong
  ];

  @override
  Widget build(BuildContext context) {
    if (passphrase.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final strength = estimatePassphrase(passphrase);
    final color = _colors[strength.score];
    final warning = strength.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (strength.score + 1) / 5,
                    minHeight: 4,
                    color: color,
                    backgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                strength.label,
                key: const Key('strength-label'),
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ],
          ),
          if (warning != null && warning.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              warning,
              key: const Key('strength-warning'),
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ],
      ),
    );
  }
}
