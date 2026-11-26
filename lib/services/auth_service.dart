import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final bool _isInitializing = false; // Sessão em cache imediata; nunca bloqueia a UI
  String? _errorMessage;

  GoogleSignInAccount? get googleUser => _googleUser;
  User? get firebaseUser => _firebaseUser;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  bool get isSignedIn => _firebaseUser != null;
  String? get errorMessage => _errorMessage;

  String get userDisplayName =>
      _googleUser?.displayName ?? _firebaseUser?.displayName ?? 'Usuário';
  String get userEmail =>
      _googleUser?.email ?? _firebaseUser?.email ?? '';
  String? get userPhotoUrl =>
      _googleUser?.photoUrl ?? _firebaseUser?.photoURL;
  String get userId => _firebaseUser?.uid ?? '';

  AuthService() {
    _firebaseUser = _firebaseAuth.currentUser;
    _firebaseAuth.authStateChanges().listen((user) {
      _firebaseUser = user;
      notifyListeners();
    });
    // Atualiza GoogleSignInAccount em background sem bloquear a abertura do app
    _trySilentSignIn();
  }

  Future<void> _trySilentSignIn() async {
    try {
      final googleUser = await _googleSignIn
          .signInSilently()
          .timeout(const Duration(seconds: 4));
      if (googleUser != null) {
        _googleUser = googleUser;
        if (_firebaseUser == null) {
          await _signInToFirebase(googleUser)
              .timeout(const Duration(seconds: 6));
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Silent sign-in em background (offline/VPN): $e');
    }
  }

  Future<void> signIn() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Sem timeout na UI interativa do seletor de conta / senha / 2FA
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // Usuário cancelou
      _googleUser = googleUser;
      await _signInToFirebase(googleUser)
          .timeout(const Duration(seconds: 15));
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      final msg = e.message ?? '';
      if (code == 'sign_in_canceled' || code == 'sign_in_cancelled') {
        _errorMessage = null;
      } else if (code == 'network_error') {
        _errorMessage =
            'Erro de rede ao conectar com Google. Verifique sua internet ou VPN.';
      } else if (msg.contains('10:') ||
          msg.contains('ApiException: 10') ||
          msg.contains('DEVELOPER_ERROR')) {
        _errorMessage =
            'Erro de configuração/assinatura no Firebase (ApiException: 10 / SHA-1 não registrado).';
      } else {
        _errorMessage =
            'Falha no login Google [${e.code}]${msg.isNotEmpty ? ': $msg' : ''}';
      }
      debugPrint('Sign-in PlatformException [${e.code}]: $msg');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        _errorMessage =
            'Erro de rede no Firebase Auth. Verifique sua internet ou VPN.';
      } else {
        _errorMessage =
            'Erro de autenticação Firebase [${e.code}]${e.message != null ? ': ${e.message}' : ''}';
      }
      debugPrint('Sign-in FirebaseAuthException [${e.code}]: ${e.message}');
    } on TimeoutException {
      _errorMessage =
          'Tempo esgotado ao autenticar no Firebase. Verifique sua internet ou VPN.';
      debugPrint('Sign-in timeout');
    } catch (e) {
      _errorMessage = 'Erro ao entrar com Google: $e';
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
    _errorMessage = null;
    notifyListeners();
  }

  /// Retorna um client HTTP autenticado para Google Calendar API
  Future<gcal.CalendarApi?> getCalendarApi() async {
    if (_googleUser == null) {
      try {
        _googleUser = await _googleSignIn
            .signInSilently()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('getCalendarApi silent sign-in falhou: $e');
      }
    }
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    return gcal.CalendarApi(httpClient);
  }
}
