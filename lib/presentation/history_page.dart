import 'dart:io';
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

  Future<void> _shareToStory(String date, int steps, int rank, String walkingInfo) async {
    try {
      final Size storySize = const Size(1080, 1920);

      // Create a proper widget for the story
      final Widget captureWidget = RepaintBoundary(
        child: Material(
          child: Container(
            width: storySize.width,
            height: storySize.height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF121212), Color(0xFF1B5E20)],
              ),
            ),
            child: Padding(
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
                      fontFamily: 'Roboto',
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    date,
                    style: const TextStyle(
                      fontSize: 48,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 60),
                  Text(
                    '$steps',
                    style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF69F0AE),
                    ),
                  ),
                  const Text(
                    'STEPS',
                    style: TextStyle(
                      fontSize: 40,
                      color: Colors.grey,
                    ),
                  ),
                  if (walkingInfo.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.greenAccent, width: 2),
                      ),
                      child: Text(
                        walkingInfo,
                        style: const TextStyle(
                          fontSize: 36,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 50),
                  if (rank <= 10)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.2),
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
                  const Text(
                    'Shared by You',
                    style: TextStyle(
                      fontSize: 32,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Capture the widget
      final imageBytes = await _screenshotController.captureFromWidget(
        captureWidget,
        delay: const Duration(milliseconds: 1000),
        pixelRatio: 2.0,
      );

      if (imageBytes == null) throw Exception('Capture failed: returned null');

      // Save and share
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/strido_story.png';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'My daily steps on Strido 🏃‍♂️\n$date: $steps steps\n$walkingInfo\n\n#Strido #Fitness #StepTracking',
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
    final startTime = row['walking_start_time']?.toString();
    final endTime = row['walking_end_time']?.toString();

    final rank = await _getRankForDate(date);
    
    String walkingInfo = '';
    if (startTime != null || endTime != null) {
      String start = startTime != null ? _formatTime(startTime) : 'Unknown';
      String end = endTime != null ? _formatTime(endTime) : 'Now';
      walkingInfo = '$steps steps walked from $start to $end';
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(date),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (walkingInfo.isNotEmpty) ...[
                Text(walkingInfo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                const SizedBox(height: 8),
              ],
              Text(
                'Steps: $steps\n'
                'Distance: ${distance.toStringAsFixed(2)} m\n'
                'Calories: ${calories.toStringAsFixed(2)} kcal\n'
                'Rank: #$rank',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _shareToStory(date, steps, rank, walkingInfo);
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (e) {
      return isoTime;
    }
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
