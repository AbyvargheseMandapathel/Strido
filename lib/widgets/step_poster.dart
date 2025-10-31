// lib/widgets/step_poster.dart
import 'package:flutter/material.dart';

class StepPoster extends StatelessWidget {
  final String date;
  final int steps;
  final int rank;
  final String username;

  const StepPoster({
    super.key,
    required this.date,
    required this.steps,
    required this.rank,
    this.username = 'You',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1920,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF121212), Color(0xFF1B5E20)],
        ),
      ),
      padding: const EdgeInsets.all(80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'STRIDO',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Helvetica',
            ),
          ),
          const SizedBox(height: 40),
          Text(date, style: const TextStyle(fontSize: 48, color: Colors.grey)),
          const SizedBox(height: 60),
          Text(
            '$steps',
            style: const TextStyle(
              fontSize: 120,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Text(
            'STEPS',
            style: TextStyle(fontSize: 40, color: Colors.grey),
          ),
          const SizedBox(height: 50),
          if (rank <= 10)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withAlpha((255 * 0.2).round()),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.greenAccent, width: 2),
              ),
              child: Text(
                '🏆 Rank #$rank',
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          const Spacer(),
          Text(
            'Shared by $username',
            style: const TextStyle(fontSize: 32, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
