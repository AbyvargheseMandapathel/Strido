import 'package:flutter/material.dart';
import '../data/database/step_database.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({Key? key}) : super(key: key);

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final StepDatabase _db = StepDatabase.instance;
  List<Map<String, Object?>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTop();
  }

  Future<void> _loadTop() async {
    setState(() => _loading = true);
    final db = await _db.database;
    final rows = await db.query('sessions', orderBy: 'user_steps DESC', limit: 10);
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _loadTop,
        child: _loading
            ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
            : _rows.isEmpty
                ? ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No data')))])
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final row = _rows[i];
                      final date = row['date'] as String? ?? 'unknown';
                      final steps = row['user_steps']?.toString() ?? '0';
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(date),
                        trailing: Text('$steps'),
                      );
                    },
                  ),
      ),
    );
  }
}