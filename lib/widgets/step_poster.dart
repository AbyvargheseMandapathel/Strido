import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.8,
          colors: [
            Color(0xFF0D1B3E),
            Color(0xFF0A122A),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildHeader(),
            const Spacer(),
            _buildStepCount(),
            const SizedBox(height: 40),
            _buildStats(),
            const Spacer(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      'DAILY SUMMARY',
      style: GoogleFonts.poppins(
        fontSize: 36,
        fontWeight: FontWeight.w300,
        color: Colors.white70,
        letterSpacing: 6,
      ),
    );
  }

  Widget _buildStepCount() {
    return Column(
      children: [
        Text(
          '$steps',
          style: GoogleFonts.poppins(
            fontSize: 120,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [
              const Shadow(
                blurRadius: 30.0,
                color: Colors.black54,
                offset: Offset(0, 10.0),
              ),
            ],
          ),
        ),
        Text(
          'STEPS',
          style: GoogleFonts.poppins(
            fontSize: 32,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
            letterSpacing: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildStats() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildStatItem('DATE', date),
        if (rank <= 10) _buildStatItem('RANK', '#$rank', isRank: true),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, {bool isRank = false}) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: isRank ? const Color(0xFF00FFFF) : Colors.white,
            shadows: isRank
                ? [
                    const Shadow(
                      blurRadius: 20.0,
                      color: Color(0xFF00FFFF),
                      offset: Offset(0, 0),
                    ),
                  ]
                : [],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Shared by $username',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 20),
        Image.asset(
          'assets/icon/logo.png',
          height: 50,
        ),
        const SizedBox(height: 10),
        Text(
          'STRIDO',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}
