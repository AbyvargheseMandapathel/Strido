import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:logger/logger.dart';

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
      print('DB restore error: $e');
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
      print('DB export error: $e');
      return null;
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
    return await openDatabase(path, version: 2, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        date TEXT PRIMARY KEY,
        system_base_steps INTEGER NOT NULL,
        user_steps INTEGER NOT NULL,
        calories REAL NOT NULL,
        distance_m REAL NOT NULL,
        last_updated TEXT
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // add last_updated column in migration
      try {
        await db.execute('ALTER TABLE sessions ADD COLUMN last_updated TEXT;');
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

  Future<void> saveSession(String date, int systemBase, int userSteps,
      {double calories = 0.0, double distanceMeters = 0.0}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'sessions',
      {
        'date': date,
        'system_base_steps': systemBase,
        'user_steps': userSteps,
        'calories': calories,
        'distance_m': distanceMeters,
        'last_updated': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUserSteps(
      String date, int userSteps, double calories, double distanceMeters) async {
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

  Future close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}