import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache for Game Party posts.
///
/// Firestore remains the source of truth. This database stores a local copy
/// of the feed so the app can reuse the latest downloaded post data.
class LocalDatabaseService {
  LocalDatabaseService._();

  static final LocalDatabaseService instance = LocalDatabaseService._();

  static const int _databaseVersion = 1;
  static const String _databaseName = 'game_party_local.db';
  static const String _postsTable = 'cached_posts';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;

    final databasePath = await getDatabasesPath();
    final db = await openDatabase(
      path.join(databasePath, _databaseName),
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_postsTable (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL DEFAULT '',
            userName TEXT NOT NULL DEFAULT '',
            game TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            detail TEXT NOT NULL DEFAULT '',
            imageUrl TEXT NOT NULL DEFAULT '',
            createdAtMillis INTEGER,
            likes INTEGER NOT NULL DEFAULT 0,
            dataJson TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_cached_posts_created ON $_postsTable(createdAtMillis DESC)',
        );
      },
    );
    _database = db;
    return db;
  }

  /// Returns the full path to the SQLite database file on this platform.
  /// The path can be printed during debugging to help locate the database.
  Future<String> getDatabaseFilePath() async {
    final databasePath = await getDatabasesPath();
    return path.join(databasePath, _databaseName);
  }

  /// Saves/replaces a batch of Firestore posts in a single transaction.
  Future<void> cachePosts(List<Map<String, dynamic>> posts) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final post in posts) {
        final id = (post['id'] ?? '').toString();
        if (id.isEmpty) continue;

        final data = Map<String, dynamic>.from(
          (post['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final createdAt = _timestampMillis(data['createdAt']);
        final serializableData = _makeJsonSafe(data);

        batch.insert(
          _postsTable,
          {
            'id': id,
            'uid': (data['uid'] ?? '').toString(),
            'userName': (data['userName'] ?? data['name'] ?? '').toString(),
            'game': (data['game'] ?? '').toString(),
            'title': (data['title'] ?? '').toString(),
            'detail': (data['detail'] ?? '').toString(),
            'imageUrl': (data['imageUrl'] ?? '').toString(),
            'createdAtMillis': createdAt,
            'likes': _toInt(data['likes']),
            'dataJson': jsonEncode(serializableData),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Returns cached posts, newest first. `data` is decoded from JSON.
  Future<List<Map<String, dynamic>>> getCachedPosts() async {
    final db = await database;
    final rows = await db.query(
      _postsTable,
      orderBy: 'createdAtMillis DESC',
    );

    return rows.map((row) {
      final decoded = jsonDecode(row['dataJson'] as String);
      return {
        'id': row['id'],
        'data': Map<String, dynamic>.from(decoded as Map),
        'cachedAtMillis': row['createdAtMillis'],
      };
    }).toList();
  }

  /// Returns how many posts are currently stored in SQLite.
  Future<int> getCachedPostCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $_postsTable',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns a small diagnostic summary useful when checking the local DB.
  Future<Map<String, dynamic>> getDatabaseSummary() async {
    final db = await database;
    final count = await getCachedPostCount();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    return {
      'databaseName': _databaseName,
      'databasePath': await getDatabaseFilePath(),
      'cachedPostCount': count,
      'tables': tables.map((row) => row['name']).toList(),
    };
  }

  Future<void> clearCachedPosts() async {
    final db = await database;
    await db.delete(_postsTable);
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }

  int? _timestampMillis(dynamic value) {
    if (value == null) return null;
    // Avoid a direct dependency on Cloud Firestore types in this service.
    try {
      final milliseconds = (value as dynamic).millisecondsSinceEpoch;
      if (milliseconds is int) return milliseconds;
    } catch (_) {}
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    return null;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  dynamic _makeJsonSafe(dynamic value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is List) return value.map(_makeJsonSafe).toList();
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _makeJsonSafe(item)),
      );
    }

    // Firestore Timestamp and other timestamp-like objects.
    final millis = _timestampMillis(value);
    if (millis != null) return millis;
    return value.toString();
  }
}
