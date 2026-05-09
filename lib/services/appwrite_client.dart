import 'package:appwrite/appwrite.dart';

/// Central Appwrite client — call [initialize] once in [main].
/// Access the singleton via [AppwriteClient.instance].
class AppwriteClient {
  AppwriteClient._();

  static final AppwriteClient instance = AppwriteClient._();

  // ─── Project constants ─────────────────────────────────────────────────────
  static const String endpoint = 'https://appwrite.techgetafrica.com/v1';
  static const String projectId = '69ff316500020a7faedd';
  static const String databaseId = '69ff331f003581a0a14d';
  static const String storageId = '69ff334c002518a2ca78';

  // ─── Collection IDs ────────────────────────────────────────────────────────
  // Create these collections in your Appwrite Console under database [databaseId].
  //
  // Collection: tasks
  //   title          string (required)
  //   note           string
  //   dueLabel       string
  //   dueAt          string (ISO-8601, nullable)
  //   listId         string (required)
  //   bucket         string (today | inbox | upcoming)
  //   priority       string (high | medium | low)
  //   checklistDone  integer
  //   checklistTotal integer
  //   isFlagged      boolean
  //   isDone         boolean
  //   recurrence     string (none | daily | weekly)
  //   tags           string[] (array)
  //   userId         string (required) — index this field for fast queries
  //
  // Collection: streaks
  //   userId          string (required, unique)
  //   currentStreak   integer
  //   longestStreak   integer
  //   totalCompleted  integer
  //   lastDate        string (YYYY-MM-DD)
  static const String tasksCollectionId = 'tasks';
  static const String streaksCollectionId = 'streaks';

  // ─── SDK instances ─────────────────────────────────────────────────────────
  late final Client client;
  late final Account account;
  late final Databases databases;
  late final Realtime realtime;
  late final Storage storage;

  void initialize() {
    client = Client()
        .setEndpoint(endpoint)
        .setProject(projectId)
        .setSelfSigned(
          status: true,
        ); // self-hosted — remove if you add a valid SSL cert

    account = Account(client);
    databases = Databases(client);
    realtime = Realtime(client);
    storage = Storage(client);
  }
}
