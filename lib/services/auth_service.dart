import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;

import 'appwrite_client.dart';

/// Singleton auth service backed by Appwrite Account.
class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final AppwriteClient _aw = AppwriteClient.instance;

  final StreamController<models.User?> _userCtrl =
      StreamController<models.User?>.broadcast();

  models.User? _currentUser;

  Stream<models.User?> get userStream => _userCtrl.stream;
  models.User? get currentUser => _currentUser;
  String? get uid => _currentUser?.$id;

  String get displayName =>
      (_currentUser?.name.isNotEmpty == true) ? _currentUser!.name : 'Flameup member';

  String get email => _currentUser?.email ?? '';

  Future<void> initialize() async {
    try {
      _currentUser = await _aw.account.get();
    } on AppwriteException {
      _currentUser = null;
    }
    _userCtrl.add(_currentUser);
  }

  Future<models.User?> signUpWithEmail(
      String email, String password, String name) async {
    await _aw.account.create(
      userId: ID.unique(),
      email: email.trim(),
      password: password,
      name: name.trim(),
    );
    return signInWithEmail(email, password);
  }

  Future<models.User?> signInWithEmail(String email, String password) async {
    await _aw.account.createEmailPasswordSession(
      email: email.trim(),
      password: password,
    );
    _currentUser = await _aw.account.get();
    _userCtrl.add(_currentUser);
    return _currentUser;
  }

  Future<void> signInWithGoogle() async {
    await _aw.account.createOAuth2Session(
      provider: enums.OAuthProvider.google,
    );
    _currentUser = await _aw.account.get();
    _userCtrl.add(_currentUser);
  }

  Future<void> signOut() async {
    try {
      await _aw.account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      // already expired - ignore
    }
    _currentUser = null;
    _userCtrl.add(null);
  }

  Future<void> sendPasswordReset(String email) async {
    await _aw.account.createRecovery(
      email: email.trim(),
      url: '${AppwriteClient.endpoint}/account/recovery',
    );
  }

  Future<void> updateDisplayName(String name) async {
    _currentUser = await _aw.account.updateName(name: name.trim());
    _userCtrl.add(_currentUser);
  }

  static String friendlyError(Object e) {
    if (e is AppwriteException) {
      final String msg = (e.message ?? '').toLowerCase();
      if (msg.contains('invalid credentials') ||
          msg.contains('user_invalid_credentials')) {
        return 'Incorrect email or password.';
      }
      if (msg.contains('user_already_exists') || msg.contains('already exists')) {
        return 'An account with this email already exists.';
      }
      if (msg.contains('user_not_found')) {
        return 'No account found with that email.';
      }
      if (msg.contains('password')) {
        return 'Password must be at least 8 characters.';
      }
      return e.message ?? 'Authentication error. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
