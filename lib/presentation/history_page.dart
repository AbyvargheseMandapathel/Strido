import 'package:flutter/material.dart';
import '../data/database/step_database.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final StepDatabase _db = StepDatabase.instance;
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getAllSessions();
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _showDetails(Map<String, Object?> row) {
    final date = row['date'] as String? ?? 'unknown';
    final steps = row['user_steps']?.toString() ?? '0';
    final calories = row['calories']?.toString() ?? '0.0';
    final distance = row['distance_m']?.toString() ?? '0.0';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(date),
        content: Text('Steps: $steps\nDistance (m): $distance\nCalories: $calories'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _rows.isEmpty
                ? ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No history')))])
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final row = _rows[i];
                      final date = row['date'] as String? ?? 'unknown';
                      final steps = row['user_steps']?.toString() ?? '0';
                      final calories = row['calories']?.toString() ?? '0.0';
                      final distance = row['distance_m']?.toString() ?? '0.0';
                      return ListTile(
                        title: Text(date),
                        subtitle: Text('$steps steps • $distance m • $calories kcal'),
                        onTap: () => _showDetails(row),
                      );
                    },
                  ),
      ),
    );
  }
}