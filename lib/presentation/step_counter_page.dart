import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/step_tracker_service.dart';
import '../presentation/history_page.dart';
import '../services/device_sync_service.dart';
import '../utils/permissions_helper.dart';
import 'connected_devices_page.dart';

class StepCounterPage extends StatefulWidget {
  const StepCounterPage({super.key});

  @override
  State<StepCounterPage> createState() => _StepCounterPageState();
}

class _StepCounterPageState extends State<StepCounterPage> with WidgetsBindingObserver {
  late final StepTrackerService _service;
  StreamSubscription<int>? _stepsSub;
  StreamSubscription<String>? _statusSub;

  int _steps = 0;
  String? _lastUpdated;

  // Persistent daily goal
  int _stepGoal = 10000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DeviceSyncService.instance.loadPaired();
    _service = StepTrackerService();
    _initService();
    
    // Initialize step goal from preferences or use default
    _loadStepGoal();
  }

  Future<void> _loadStepGoal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _stepGoal = prefs.getInt('step_goal') ?? 20000;
    });
  }


  Future<void> _saveGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_step_goal', goal);
    if (mounted) setState(() => _stepGoal = goal);
  }

  Future<void> _editGoalDialog() async {
    final controller = TextEditingController(text: _stepGoal.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set daily step goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter step goal'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? _stepGoal;
              Navigator.pop(ctx, val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (res != null) await _saveGoal(res);
  }

Future<void> _initService() async {
  final permsOk = await PermissionsHelper.ensureBlePermissions(context);
  if (!permsOk) {
    return;
  }

  await _service.initialize(); // ✅ NO context

  _stepsSub = _service.stepStream.listen((steps) {
    if (!mounted) return;
    if (!DeviceSyncService.instance.isConnected) {
      setState(() => _steps = steps);
      _updateLastUpdated();
    }
  });

  _statusSub = _service.statusStream.listen((s) {
    if (!mounted) return;
    if (s == 'PERMISSION_DENIED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Step tracking requires activity recognition permission.')),
      );
    }
  });

  DeviceSyncService.instance.externalStepStream.listen((extSteps) {
    if (!mounted) return;
    setState(() => _steps = extSteps);
    _updateLastUpdated();
  });

  DeviceSyncService.instance.connectionStateStream.listen((connected) {
    if (!mounted) return;
    if (!connected) {
      _service.refresh().then((_) => _updateLastUpdated());
    } else {
      _service.getSession(DateTime.now().toIso8601String().substring(0, 10)).then((s) {
        if (!mounted) return;
        if (s != null) {
          setState(() {
            _steps = s['user_steps'] as int? ?? 0;
            _lastUpdated = s['last_updated'] as String?;
          });
        }
      });
    }
  });

  _updateLastUpdated();
}

  Future<void> _updateLastUpdated() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final session = await _service.getSession(today);
    if (!mounted) return;
    setState(() {
      _lastUpdated = session == null ? null : session['last_updated'] as String?;
    });
  }

  String _relativeMinutes(String? iso) {
    if (iso == null) return 'never';
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes == 1) return '1 minute ago';
      return '${diff.inMinutes} minutes ago';
    } catch (_) {
      return 'never';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepsSub?.cancel();
    _statusSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_stepGoal > 0) ? (_steps / _stepGoal).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Step Tracker'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history, color: Colors.greenAccent),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'Goal',
            icon: const Icon(Icons.flag, color: Colors.greenAccent),
            onPressed: _editGoalDialog,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'connected') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectedDevicesPage()),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'connected', child: Text('Connected devices')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _updateLastUpdated();
          final today = DateTime.now().toIso8601String().substring(0, 10);
          final session = await _service.database.getSessionForDay(today);
          if (session != null) {
            final steps = session['user_steps'] as int;
            if (mounted) setState(() => _steps = steps);
          } else {
            if (mounted) setState(() => _steps = 0);
          }
        },
        color: Colors.greenAccent,
        backgroundColor: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated circular goal completion
                SizedBox(
                  width: 220,
                  height: 220,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: percent),
                        duration: const Duration(milliseconds: 700),
                        builder: (context, animatedPercent, _) => SizedBox(
                          width: 220,
                          height: 220,
                          child: CircularProgressIndicator(
                            value: animatedPercent,
                            strokeWidth: 14,
                            color: Colors.greenAccent,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _steps.toString(),
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'STEPS TODAY',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                      // Source badge removed — no Google Fit
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('${(percent * 100).toStringAsFixed(0)}% of goal', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Goal: $_stepGoal', style: const TextStyle(color: Colors.white70)),
                    const SizedBox(width: 16),
                    Text('${(percent * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.greenAccent)),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.update, color: Colors.greenAccent),
                    const SizedBox(width: 10),
                    Text(
                      'Last updated: ${_relativeMinutes(_lastUpdated)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}