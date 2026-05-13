# 🔥 Flameup

> **Keep your habit flames burning.** Track streaks and build consistency every day.

Flameup is a cross-platform habit and task tracker built with Flutter and Appwrite. Its core belief is simple: **consistency beats intensity**. Every completed task extends your flame — your daily streak — and every broken day resets it. That single mechanic turns mundane to-do lists into a momentum-building game.

---

## Table of Contents

- [Vision](#vision)
- [Current Features](#current-features)
- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Environment Setup](#environment-setup)
- [Running the App](#running-the-app)
- [Next Steps & Roadmap](#next-steps--roadmap)
- [Contributing](#contributing)

---

## Vision

Most productivity apps optimise for *capture* — getting tasks in — but forget about *completion*. Flameup is designed around the psychology of habit formation:

1. **The Streak** — A visible, ever-present streak counter rewards users for showing up every day. Missing a day hurts, which keeps the motivation alive.
2. **Focus over multitasking** — A built-in 25-minute focus timer (Pomodoro-style) pairs each work session with a single task, reducing context switching.
3. **Social accountability** *(coming soon)* — Buddy challenges and shared streaks make habits a team sport, not a solo grind.
4. **Progressive achievement** *(coming soon)* — Milestones and unlockable badges celebrate long-term discipline, not just daily wins.

The long-term goal is for Flameup to be the productivity app you *want* to open every morning — not because you have to, but because the flame is waiting.

---

## Current Features

### Authentication
- Email/password sign-up and login via Appwrite
- Google OAuth sign-in
- Password reset via email
- Session persistence across app restarts

### Task Management
- Create, edit, and delete tasks with a title, notes, priority, due date, tags, and checklist progress
- **Quick Add** bottom sheet for rapid task capture
- **Full Task Editor** screen for detailed editing (priority, recurrence, flagging, list assignment)
- Priority levels: **High** 🔴, **Medium** 🟡, **Low** 🟢
- Recurrence: **None**, **Daily**, **Weekly**
- Flag important tasks for quick filtering

### Smart & Custom Lists
| List | Type | Description |
|------|------|-------------|
| Today | Smart | Tasks due today or overdue |
| Inbox | Smart | Tasks without a due date |
| Upcoming | Smart | Tasks due tomorrow or later |
| Work | Custom | User-scoped work tasks |
| Personal | Custom | Personal errands and goals |
| Team | Custom | Personal team-related tasks |

### Streak Tracking
- Current streak, longest streak, and total completions tracked locally
- Streak increments once per day on the first task completion
- If a day is skipped, the streak resets the next time a completion is recorded

### Focus Timer
- Built-in 25-minute Pomodoro-style focus timer
- Link any task to a focus session
- Local notification fires when the session ends

### Notifications
- Daily reminder at 9 AM: *"Keep the streak alive"*
- Per-task reminders scheduled at the task's due time
- Notifications auto-cancelled when a task is marked done

### Real-Time Sync
- Appwrite Realtime subscription keeps task state in sync across multiple devices/tabs without polling

### UI / UX
- Light, Dark, and System theme modes (persisted across sessions)
- Poppins font throughout
- Onboarding flow (3 animated pages) shown once on first launch
- Segment filter (All / Open / Done) on every list
- Sort options within lists
- Inline search / browse across tasks
- Calendar date-picker for upcoming tasks

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI framework | [Flutter](https://flutter.dev) (Dart) |
| Backend / Auth / DB | [Appwrite](https://appwrite.io) |
| Google Sign-In | Appwrite OAuth2 (`Account.createOAuth2Session`) |
| State management | [Riverpod](https://riverpod.dev) |
| Navigation | [GoRouter](https://pub.dev/packages/go_router) |
| Local storage | `shared_preferences` |
| Notifications | `flutter_local_notifications` + `timezone` |
| Fonts | `google_fonts` (Poppins) |
| URL handling | `url_launcher` |

---

## Architecture

```
lib/
├── main.dart               # App entry, GoRouter, theme providers
├── firebase_options.dart   # Generated config for Appwrite Google OAuth
├── models/
│   └── task_models.dart    # FlameTask, TaskListItem, enums, date utilities
├── screens/
│   ├── splash_screen.dart          # Auth-gate redirect on launch
│   ├── onboarding_screen.dart      # 3-page first-run introduction
│   ├── login_screen.dart           # Email + Google sign-in
│   ├── signup_screen.dart          # Account creation
│   ├── forgot_password_screen.dart # Password recovery
│   ├── home_screen.dart            # Main task view, focus timer, navigation
│   ├── task_editor_screen.dart     # Full-screen task detail/edit
│   └── settings_screen.dart        # Theme, account, profile
└── services/
    ├── appwrite_client.dart     # Appwrite SDK singleton (endpoint, IDs)
    ├── auth_service.dart        # Authentication business logic
    ├── task_store.dart          # Task CRUD + Realtime + optimistic updates
    ├── streak_service.dart      # Local streak tracking (SharedPreferences)
    └── notification_service.dart # Local notification scheduling
```

### Key Patterns

- **Singleton services** — `AuthService`, `AppwriteClient`, `NotificationService`, and `StreakService` all use the factory-singleton pattern so a single instance is shared app-wide.
- **Optimistic updates** — `TaskStore` applies state changes locally before sending them to Appwrite, then rolls back on failure. This makes the UI feel instant even on slow connections.
- **ChangeNotifier + Riverpod** — `TaskStore` extends `ChangeNotifier` and is consumed directly in the `HomeScreen` via `addListener`, while global state (theme mode, auth) is managed through Riverpod providers.
- **GoRouter** — All navigation is declarative. The splash screen checks session state and routes users to `/login` or `/home` based on whether an active session exists.

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (stable channel, Dart SDK ≥ 3.11.4)
- An [Appwrite](https://appwrite.io) project (self-hosted or cloud) with Google OAuth provider enabled

### Environment Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/Reagandennis/Flameup.git
   cd Flameup
   ```

2. **Configure Appwrite**

   Open `lib/services/appwrite_client.dart` and fill in your project details:
   ```dart
   static const String endpoint = 'https://your-appwrite-endpoint/v1';
   static const String projectId = 'your-project-id';
   static const String databaseId = 'your-database-id';
   static const String tasksCollectionId = 'your-tasks-collection-id';
   ```

   Create a **tasks** collection in Appwrite with the following attributes and types:
   - `title`: string
   - `note`: string
   - `dueLabel`: string
   - `dueAt`: string
   - `listId`: string
   - `bucket`: string
   - `priority`: string
   - `checklistDone`: integer
   - `checklistTotal`: integer
   - `isFlagged`: boolean
   - `tags`: string array
   - `isDone`: boolean
   - `recurrence`: string
   - `userId`: string

3. **Enable Google OAuth in Appwrite**

   In your Appwrite Console go to **Auth → OAuth2 providers**, enable **Google**, and supply your Android/iOS OAuth client IDs. No Firebase setup is required; sign-in uses `Account.createOAuth2Session(provider: google)` directly through the Appwrite SDK.

4. **Install dependencies**
   ```bash
   flutter pub get
   ```

### Running the App

```bash
# Mobile (connected device or emulator)
flutter run

# Web
flutter run -d chrome

# Specific platform
flutter run -d macos
flutter run -d windows
```

---

## Next Steps & Roadmap

### Short Term
- [ ] **Cloud streak sync** — Move streak data from `SharedPreferences` to Appwrite so it persists across devices and app reinstalls.
- [ ] **Recurrence engine** — When a recurring task is marked done, auto-generate the next occurrence for the following day/week.
- [ ] **Custom list management** — Allow users to create, rename, reorder, and delete their own task lists from within the app.
- [ ] **Task search** — Full-text search across all task titles and notes using the existing browse UI.

### Medium Term
- [ ] **Buddy challenges** — Invite a friend via a share link; both users can see each other's streak and cheer or react to completions.
- [ ] **Achievements & badges** — Unlock milestones (7-day streak, 50 tasks done, first flagged task, etc.) stored in Appwrite and displayed on a profile card.
- [ ] **Habit templates** — Pre-built task sets (morning routine, reading habit, workout plan) that users can install with one tap.
- [ ] **Progress analytics** — Weekly and monthly charts showing completion rate, top tags, and streak history.
- [ ] **Home-screen widgets** — iOS and Android widgets that show today's task count and current streak without opening the app.

### Long Term
- [ ] **Offline-first architecture** — Local SQLite cache with conflict resolution so the app works fully without internet and syncs when connectivity returns.
- [ ] **Team / workspace mode** — Shared lists where multiple users can assign, complete, and comment on tasks in real time.
- [ ] **Wearable companion** — Apple Watch / Wear OS glance showing today's streak and a one-tap "mark done" for the next task.
- [ ] **AI task suggestions** — Analyse past completion patterns to suggest the best time of day to schedule specific task types.
- [ ] **Public profiles** — Optional shareable streak pages so users can share their consistency publicly.

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow the existing code style (Dart `analysis_options.yaml` enforces flutter_lints).
3. Write or update tests in the `test/` directory for any new logic.
4. Open a pull request with a clear description of the change and why it belongs in Flameup.

For bug reports and feature requests, please open a GitHub issue.

---

*Built with 🔥 by the Flameup team.*
