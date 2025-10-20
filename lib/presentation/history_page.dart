import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:screenshot/screenshot.dart';
import '../data/database/step_database.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final StepDatabase _db = StepDatabase.instance;
  final ScreenshotController _screenshotController = ScreenshotController();

  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _loading = true);
      final rows = await _db.getAllSessions();
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: $e')),
      );
    }
  }

  Future<int> _getRankForDate(String date) async {
    try {
      final db = await _db.database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) + 1 AS rank
        FROM sessions
        WHERE user_steps > (SELECT user_steps FROM sessions WHERE date = ?)
      ''', [date]);
      return (result.first['rank'] as int?) ?? 1;
    } catch (_) {
      return 1;
    }
  }

  Future<void> _shareToStory(String date, int steps, int rank) async {
  try {
    final Size storySize = const Size(1080, 1920);

    // Create a widget with explicit size and repaint boundary
    final Widget captureWidget = RepaintBoundary(
      child: SizedBox.fromSize(
        size: storySize,
        child: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/strido_story_bg.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: Colors.black); // Fallback if image fails
                },
              ),
            ),

            // ONLY ADD: Rotated Step Count
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Transform.rotate(
                  angle: -0.26, // ~ -15 degrees
                  child: Text(
                    '$steps',
                    style: const TextStyle(
                      fontSize: 200,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3DFF00), // Bright green
                      shadows: [
                        Shadow(
                          offset: Offset(4, 4),
                          blurRadius: 20,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final imageBytes = await _screenshotController.captureFromWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: captureWidget,
      ),
      delay: const Duration(milliseconds: 500), // Give time for image to load
      pixelRatio: 3.0,
    );

    if (imageBytes == null) throw Exception('Capture failed: returned null');

    // Save and share
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/strido_story.png';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);

    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'My daily steps on Strido 🏃‍♂️ #Strido #Fitness #BESTRONG',
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to share story: $e')),
    );
  }
}

  
  void _showDetails(Map<String, Object?> row) async {
    final date = row['date']?.toString() ?? 'Unknown Date';
    final steps = (row['user_steps'] as int?) ?? 0;
    final calories = double.tryParse(row['calories']?.toString() ?? '0') ?? 0;
    final distance = double.tryParse(row['distance_m']?.toString() ?? '0') ?? 0;

    final rank = await _getRankForDate(date);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(date),
        content: Text(
          'Steps: $steps\n'
          'Distance: ${distance.toStringAsFixed(2)} m\n'
          'Calories: ${calories.toStringAsFixed(2)} kcal\n'
          'Rank: #$rank',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _shareToStory(date, steps, rank);
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? const Center(child: Text('No history available'))
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final row = _rows[i];
                      final date = row['date']?.toString() ?? 'Unknown Date';
                      final steps = (row['user_steps'] as int?) ?? 0;
                      final distance = double.tryParse(row['distance_m']?.toString() ?? '0') ?? 0;
                      final calories = double.tryParse(row['calories']?.toString() ?? '0') ?? 0;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: const Icon(Icons.directions_walk, color: Colors.green),
                          title: Text(
                            date,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '$steps steps • ${distance.toStringAsFixed(2)} m • ${calories.toStringAsFixed(2)} kcal',
                          ),
                          onTap: () => _showDetails(row),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
