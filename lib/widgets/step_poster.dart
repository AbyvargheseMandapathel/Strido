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
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A237E), Color(0xFF880E4F)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: Image.asset(
                'assets/images/strido_story_bg.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(80),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHeader(),
                const Spacer(),
                _buildStepCount(),
                const SizedBox(height: 30),
                _buildRank(),
                const Spacer(),
                _buildFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'STRIDO',
          style: TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontFamily: 'Helvetica',
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          date,
          style: const TextStyle(
            fontSize: 36,
            color: Colors.white70,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildStepCount() {
    return Column(
      children: [
        Text(
          '$steps',
          style: const TextStyle(
            fontSize: 120,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            shadows: [
              Shadow(
                blurRadius: 20.0,
                color: Colors.black45,
                offset: Offset(5.0, 5.0),
              ),
            ],
          ),
        ),
        const Text(
          'STEPS',
          style: TextStyle(
            fontSize: 36,
            color: Colors.white70,
            fontWeight: FontWeight.w300,
            letterSpacing: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildRank() {
    if (rank > 10) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.pinkAccent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.pinkAccent, width: 3),
      ),
      child: Text(
        '🏆 RANK #$rank',
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: Colors.pinkAccent,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Shared by $username',
          style: const TextStyle(fontSize: 28, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Image.asset(
          'assets/icon/logo.png',
          height: 60,
        ),
      ],
    );
  }
}
