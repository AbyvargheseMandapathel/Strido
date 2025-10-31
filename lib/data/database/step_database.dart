import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class StepDatabase {
  static final StepDatabase instance = StepDatabase._init();

  static Database? _database;

  StepDatabase._init();

  /// Ensure restored from a backup file (if present) before opening DB.
  /// This tries to copy a backup DB from the platform Downloads directory
  /// into the app database path if the database file doesn't exist yet.
  Future<void> ensureRestored() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'steps.db');
      final dbFile = File(path);
      if (await dbFile.exists()) {
        // DB already present — nothing to do.
        return;
      }

      // Request permission to read external storage if needed.
      if (!Platform.isIOS) {
        final status = await Permission.storage.request();
        if (!status.isGranted) return;
      }

      // Look for a file in Downloads named 'steps_backup.db' (created by exportBackup).
      Directory? downloads;
      if (Platform.isAndroid) {
        downloads = await getExternalStorageDirectory();
        // On many devices getExternalStorageDirectory() returns Android/data/...;
        // try a common Downloads fallback.
        if (downloads != null) {
          final candidate = Directory('${downloads.path}/Download');
          if (await candidate.exists()) downloads = candidate;
        }
      } else if (Platform.isIOS) {
        downloads = await getApplicationDocumentsDirectory();
      } else {
        downloads = await getApplicationDocumentsDirectory();
      }

      if (downloads == null) return;
      final backupFile = File(p.join(downloads.path, 'steps_backup.db'));
      if (await backupFile.exists()) {
        await backupFile.copy(path);
      }
    } catch (e) {
      // Non-fatal—restore is best-effort.
      debugPrint('DB restore error: $e');
    }
  }

  /// Export a copy of the DB to the platform Downloads (or app docs on iOS).
  /// Returns the destination File if successful.
  Future<File?> exportBackup() async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'steps.db');
      final dbFile = File(path);
      if (!await dbFile.exists()) return null;

      // Request permission to write external storage on Android.
      if (!Platform.isIOS) {
        final status = await Permission.storage.request();
        if (!status.isGranted) return null;
      }

      Directory? targetDir;
      if (Platform.isAndroid) {
        targetDir = await getExternalStorageDirectory();
        if (targetDir != null) {
          final candidate = Directory('${targetDir.path}/Download');
          if (await candidate.exists()) targetDir = candidate;
        }
      } else {
        targetDir = await getApplicationDocumentsDirectory();
      }
      if (targetDir == null) return null;

      final now = DateTime.now().toIso8601String().replaceAll(':', '-');
      final dest = File(p.join(targetDir.path, 'steps_backup_$now.db'));
      return await dbFile.copy(dest.path);
    } catch (e) {
      debugPrint('DB export error: $e');
      return null;
    }
  }

  /// Export step data to a JSON file
  Future<File?> exportJsonData() async {
    try {
      debugPrint('Starting JSON export...');
      
      // Get all sessions data
      final sessions = await getAllSessions();
      debugPrint('Retrieved ${sessions.length} sessions');
      final profile = await getUserProfile();
      debugPrint('Retrieved user profile');

      // Create JSON structure
      final Map<String, dynamic> exportData = {
        'app': 'Step Tracker',
        'version': '1.0',
        'export_date': DateTime.now().toIso8601String(),
        'sessions': sessions.map((session) => {
          'date': session['date'],
          'system_base_steps': session['system_base_steps'],
          'user_steps': session['user_steps'],
          'calories': session['calories'],
          'distance_m': session['distance_m'],
          'last_updated': session['last_updated'],
          'walking_start_time': session['walking_start_time'],
          'walking_end_time': session['walking_end_time'],
        }).toList(),
        'user_profile': {
          'height_cm': profile['heightCm'],
          'weight_kg': profile['weightKg'],
        },
        'settings': {
          'step_goal': null, // This would be loaded from SharedPreferences if needed
        },
      };

      debugPrint('Created JSON structure');

      // Request permission for file storage (Android only)
      if (!Platform.isIOS && !Platform.isWindows) {
        final status = await Permission.storage.request();
        debugPrint('Storage permission status: $status');
        if (!status.isGranted) {
          debugPrint('Storage permission denied');
          return null;
        }
      }

      // Get target directory with better error handling
      Directory? targetDir;
      try {
        if (Platform.isAndroid) {
          // Try external storage first
          final externalDir = await getExternalStorageDirectory();
          debugPrint('External storage dir: ${externalDir?.path}');
          
          if (externalDir != null) {
            // Try Download folder
            final downloadPath = '${externalDir.path}/Download';
            final downloadDir = Directory(downloadPath);
            
            if (await downloadDir.exists()) {
              targetDir = downloadDir;
              debugPrint('Using Download directory: ${targetDir.path}');
            } else {
              // Create Download directory if it doesn't exist
              try {
                await downloadDir.create(recursive: true);
                targetDir = downloadDir;
                debugPrint('Created and using Download directory: ${targetDir.path}');
              } catch (e) {
                debugPrint('Failed to create Download directory: $e');
                // Fall back to external directory itself
                targetDir = externalDir;
                debugPrint('Using external directory as fallback: ${targetDir.path}');
              }
            }
          }
        } else if (Platform.isIOS) {
          // iOS uses Documents directory
          targetDir = await getApplicationDocumentsDirectory();
          debugPrint('Using iOS documents directory: ${targetDir.path}');
        } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          // Desktop platforms
          targetDir = await getApplicationDocumentsDirectory();
          debugPrint('Using desktop documents directory: ${targetDir.path}');
        }
      } catch (e) {
        debugPrint('Error getting target directory: $e');
        return null;
      }

      if (targetDir == null) {
        debugPrint('No valid target directory found');
        return null;
      }

      // Verify directory is writable
      if (!await targetDir.exists()) {
        debugPrint('Target directory does not exist: ${targetDir.path}');
        return null;
      }

      // Create filename with timestamp (sanitized)
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'strido_backup_$timestamp.json';
      final filePath = p.join(targetDir.path, fileName);

      debugPrint('Attempting to write file to: $filePath');

      // Write JSON file
      final file = File(filePath);
      final jsonString = JsonEncoder.withIndent('  ').convert(exportData);
      
      await file.writeAsString(jsonString);
      debugPrint('Successfully wrote file: ${file.path}');
      
      // Verify file was created
      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('File created successfully, size: $fileSize bytes');
        return file;
      } else {
        debugPrint('File was not created successfully');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('JSON export error: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Import step data from a JSON file
  Future<bool> importJsonData(File file) async {
    try {
      // Read and parse JSON file
      final content = await file.readAsString();
      final data = json.decode(content);

      // Validate JSON structure
      if (!data.containsKey('sessions') || data['sessions'] is! List) {
        throw Exception('Invalid file format: missing sessions data');
      }

      // Import sessions data
      final sessions = data['sessions'] as List;
      for (final session in sessions) {
        if (session.containsKey('date') && 
            session.containsKey('user_steps')) {
          await saveSession(
            session['date'] as String,
            session['system_base_steps'] as int? ?? 0,
            session['user_steps'] as int,
            calories: (session['calories'] as num?)?.toDouble() ?? 0.0,
            distanceMeters: (session['distance_m'] as num?)?.toDouble() ?? 0.0,
            walkingStartTime: session['walking_start_time'] as String?,
            walkingEndTime: session['walking_end_time'] as String?,
          );
        }
      }

      // Import user profile if available
      if (data.containsKey('user_profile') && data['user_profile'] is Map) {
        final profile = data['user_profile'] as Map<String, dynamic>;
        await saveUserProfile(
          heightCm: (profile['height_cm'] as num?)?.toDouble(),
          weightKg: (profile['weight_kg'] as num?)?.toDouble(),
        );
      }

      return true;
    } catch (e) {
      debugPrint('JSON import error: $e');
      return false;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('steps.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    // bump DB version to 2 to add last_updated column if upgrading
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        date TEXT PRIMARY KEY,
        system_base_steps INTEGER NOT NULL,
        user_steps INTEGER NOT NULL,
        calories REAL NOT NULL,
        distance_m REAL NOT NULL,
        last_updated TEXT,
        walking_start_time TEXT,
        walking_end_time TEXT,
        height_cm REAL,
        weight_kg REAL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // add last_updated column in migration
      try {
        await db.execute('ALTER TABLE sessions ADD COLUMN last_updated TEXT;');
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN walking_start_time TEXT;',
        );
        await db.execute(
          'ALTER TABLE sessions ADD COLUMN walking_end_time TEXT;',
        );
        await db.execute('ALTER TABLE sessions ADD COLUMN height_cm REAL;');
        await db.execute('ALTER TABLE sessions ADD COLUMN weight_kg REAL;');
      } catch (e) {
        // ignore if already exists or unsupported
      }
    }
  }

  Future<Map<String, Object?>?> getSessionForDay(String date) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> saveSession(
    String date,
    int systemBase,
    int userSteps, {
    double calories = 0.0,
    double distanceMeters = 0.0,
    String? walkingStartTime,
    String? walkingEndTime,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('sessions', {
      'date': date,
      'system_base_steps': systemBase,
      'user_steps': user_steps,
      'calories': calories,
      'distance_m': distanceMeters,
      'last_updated': now,
      'walking_start_time': walkingStartTime,
      'walking_end_time': walkingEndTime,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateUserSteps(
    String date,
    int userSteps,
    double calories,
    double distanceMeters,
  ) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sessions',
      {
        'user_steps': userSteps,
        'calories': calories,
        'distance_m': distanceMeters,
        'last_updated': now,
      },
      where: 'date = ?',
      whereArgs: [date],
    );
  }

  Future<List<Map<String, Object?>>> getAllSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'date DESC');
  }

  Future<int> getStepsForDate(String date) async {
    final row = await getSessionForDay(date);
    if (row == null) return 0;
    return row['user_steps'] as int? ?? 0;
  }

  Future<String?> getLastUpdatedForDate(String date) async {
    final row = await getSessionForDay(date);
    if (row == null) return null;
    return row['last_updated'] as String?;
  }

  /// Get the step baseline for a specific day (steps at midnight)
  Future<int?> getStepBaselineForDay(String date) async {
    final session = await getSessionForDay(date);
    return session?['system_base_steps'] as int?;
  }

  /// Set the step baseline for a specific day (steps at midnight)
  Future<void> setStepBaselineForDay(String date, int baseline) async {
    final db = await database;
    await db.update(
      'sessions',
      {'system_base_steps': baseline},
      where: 'date = ?',
      whereArgs: [date],
    );
  }

  /// Save user profile (height and weight)
  Future<void> saveUserProfile({double? heightCm, double? weightKg}) async {
    final prefs = await SharedPreferences.getInstance();
    if (heightCm != null) await prefs.setDouble('user_height_cm', heightCm);
    if (weightKg != null) await prefs.setDouble('user_weight_kg', weightKg);
  }

  /// Get user profile
  Future<Map<String, double?>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'heightCm': prefs.getDouble('user_height_cm'),
      'weightKg': prefs.getDouble('user_weight_kg'),
    };
  }

  Future close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
