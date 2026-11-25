import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

/// Serviço de autenticação via Google Sign-In + Firebase Auth
class AuthService extends ChangeNotifier {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
      gcal.CalendarApi.calendarScope,
    ],
  );

  GoogleSignInAccount? _googleUser;
  User? _firebaseUser;
  bool _isLoading = false;
  bool _isInitializing = true; // Track silent sign in

  GoogleSignInAccount? get googleUser => _googleUser;
  User? get firebaseUser => _firebaseUser;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isSignedIn => _firebaseUser != null && _googleUser != null;

  String get userDisplayName =>
      _googleUser?.displayName ?? _firebaseUser?.displayName ?? 'Usuário';
  String get userEmail =>
      _googleUser?.email ?? _firebaseUser?.email ?? '';
  String? get userPhotoUrl =>
      _googleUser?.photoUrl ?? _firebaseUser?.photoURL;
  String get userId => _firebaseUser?.uid ?? '';

  AuthService() {
    _firebaseAuth.authStateChanges().listen((user) {
      _firebaseUser = user;
      notifyListeners();
    });
    // Tenta login silencioso ao iniciar
    _trySilentSignIn();
  }

  Future<void> _trySilentSignIn() async {
    try {
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser != null) {
        _googleUser = googleUser;
        await _signInToFirebase(googleUser);
      }
    } catch (e) {
      debugPrint('Silent sign-in failed: $e');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> signIn() async {
    _isLoading = true;
    notifyListeners();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // Usuário cancelou
      _googleUser = googleUser;
      await _signInToFirebase(googleUser);
    } catch (e) {
      debugPrint('Sign-in error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _signInToFirebase(GoogleSignInAccount googleUser) async {
    final auth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    await _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
    _googleUser = null;
    notifyListeners();
  }

  /// Retorna um client HTTP autenticado para Google Calendar API
  Future<gcal.CalendarApi?> getCalendarApi() async {
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    return gcal.CalendarApi(httpClient);
  }
}
