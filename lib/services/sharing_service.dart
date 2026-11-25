import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/auth_service.dart';

/// Perfil público de um usuário (publicado no Firestore)
class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String shareCode; // primeiros 8 chars do uid em maiúsculo

  UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.shareCode,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserProfile(
      uid: doc.id,
      displayName: d['displayName'] ?? d['email']?.toString().split('@').first ?? 'Usuário',
      email: d['email'] ?? '',
      shareCode: d['shareCode'] ?? doc.id.substring(0, 8).toUpperCase(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'email': email,
    'shareCode': shareCode,
    'updatedAt': Timestamp.now(),
  };
}

/// Compromisso publicado publicamente por um usuário para seus seguidores
class SharedCommitment {
  final String id;
  final String ownerUid;
  final String ownerName;
  final DateTime date;
  final String title;
  final String hour;
  final String notes;
  final int colorValue;

  SharedCommitment({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.date,
    required this.title,
    required this.hour,
    required this.notes,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  factory SharedCommitment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SharedCommitment(
      id: doc.id,
      ownerUid: d['ownerUid'] ?? '',
      ownerName: d['ownerName'] ?? 'Usuário',
      date: (d['date'] as Timestamp).toDate(),
      title: d['title'] ?? '',
      hour: d['hour'] ?? '',
      notes: d['notes'] ?? '',
      colorValue: d['colorValue'] ?? const Color(0xFF10A37F).value,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'ownerUid': ownerUid,
    'ownerName': ownerName,
    'date': Timestamp.fromDate(date),
    'title': title,
    'hour': hour,
    'notes': notes,
    'colorValue': colorValue,
    'updatedAt': Timestamp.now(),
  };
}

/// Serviço de compartilhamento baseado em "seguir usuário por código"
/// Estrutura Firestore:
///   /user_profiles/{uid}/   → { displayName, email, shareCode }
///   /user_schedules/{uid}/commitments/{id} → SharedCommitment
class SharingService extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _authService;

  UserProfile? _myProfile;
  // Lista de UIDs que eu sigo
  List<String> _followedUids = [];
  // Perfis dos usuários que sigo
  List<UserProfile> _followedProfiles = [];
  bool _isLoading = false;
  String? _error;

  SharingService(this._authService) {
    _authService.addListener(_onAuthChanged);
    if (_authService.isSignedIn) _init();
  }

  UserProfile? get myProfile => _myProfile;
  String get myShareCode => _myProfile?.shareCode ?? '';
  List<UserProfile> get followedProfiles => _followedProfiles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _onAuthChanged() {
    if (_authService.isSignedIn) {
      _init();
    } else {
      _myProfile = null;
      _followedUids = [];
      _followedProfiles = [];
      notifyListeners();
    }
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _publishMyProfile();
      await _loadFollowedList();
    } catch (e) {
      _error = e.toString();
      debugPrint('SharingService init error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Publica ou atualiza o perfil do usuário logado no Firestore
  Future<void> _publishMyProfile() async {
    final uid = _authService.userId;
    if (uid.isEmpty) return;
    final email = _authService.userEmail;
    final displayName = _authService.userDisplayName.isNotEmpty
        ? _authService.userDisplayName
        : email.split('@').first;
    final shareCode = uid.substring(0, 8).toUpperCase();

    _myProfile = UserProfile(
      uid: uid,
      displayName: displayName,
      email: email,
      shareCode: shareCode,
    );

    await _db.collection('user_profiles').doc(uid).set(
      _myProfile!.toFirestore(),
      SetOptions(merge: true),
    );
  }

  /// Carrega a lista de UIDs seguidos do Hive
  Future<void> _loadFollowedList() async {
    final box = Hive.box('settings');
    final key = 'followed_${_authService.userId}';
    _followedUids = List<String>.from(box.get(key, defaultValue: []));
    await _loadFollowedProfiles();
  }

  Future<void> _saveFollowedList() async {
    final box = Hive.box('settings');
    final key = 'followed_${_authService.userId}';
    await box.put(key, _followedUids);
  }

  Future<void> _loadFollowedProfiles() async {
    if (_followedUids.isEmpty) {
      _followedProfiles = [];
      return;
    }
    final futures = _followedUids.map((uid) =>
      _db.collection('user_profiles').doc(uid).get()
    );
    final results = await Future.wait(futures);
    _followedProfiles = results
      .where((d) => d.exists)
      .map((d) => UserProfile.fromFirestore(d))
      .toList();
  }

  /// Busca um usuário pelo código de 8 caracteres e começa a segui-lo
  Future<({bool success, String? errorMsg, UserProfile? profile})> followByCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return (success: false, errorMsg: 'Código vazio', profile: null);

    try {
      final snap = await _db
          .collection('user_profiles')
          .where('shareCode', isEqualTo: trimmed)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        return (success: false, errorMsg: 'Nenhum usuário encontrado com este código.', profile: null);
      }

      final profile = UserProfile.fromFirestore(snap.docs.first);

      if (profile.uid == _authService.userId) {
        return (success: false, errorMsg: 'Este é o seu próprio código!', profile: null);
      }

      if (_followedUids.contains(profile.uid)) {
        return (success: false, errorMsg: 'Você já segue ${profile.displayName}.', profile: null);
      }

      _followedUids.add(profile.uid);
      _followedProfiles.add(profile);

      await _saveFollowedList();

      notifyListeners();
      return (success: true, errorMsg: null, profile: profile);
    } catch (e) {
      return (success: false, errorMsg: 'Erro: $e', profile: null);
    }
  }

  /// Remove um usuário da lista de seguidos
  Future<void> unfollow(String uid) async {
    _followedUids.remove(uid);
    _followedProfiles.removeWhere((p) => p.uid == uid);
    await _saveFollowedList();
    notifyListeners();
  }

  /// Gera um ID determinístico para o compromisso (data + título + hora).
  /// Isso garante que re-publicar o mesmo evento não cria duplicatas.
  String _commitmentDocId(DateTime date, String title, String hour) {
    final base = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}_${title.trim()}_${hour.trim()}';
    return base.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  /// Publica um compromisso meu (visível para quem me segue).
  /// Usa ID determinístico: re-publicar o mesmo evento atualiza em vez de duplicar.
  Future<bool> publishCommitment({
    required DateTime date,
    required String title,
    required String hour,
    required String notes,
    required int colorValue,
  }) async {
    if (!_authService.isSignedIn || _myProfile == null) return false;
    try {
      final commitment = SharedCommitment(
        id: '',
        ownerUid: _myProfile!.uid,
        ownerName: _myProfile!.displayName,
        date: DateTime(date.year, date.month, date.day),
        title: title,
        hour: hour,
        notes: notes,
        colorValue: colorValue,
      );
      final docId = _commitmentDocId(date, title, hour);
      await _db
          .collection('user_profiles')
          .doc(_myProfile!.uid)
          .collection('commitments')
          .doc(docId)
          .set(commitment.toFirestore());
      return true;
    } catch (e) {
      debugPrint('Error publishing commitment: $e');
      return false;
    }
  }

  /// Sincroniza em lote todos os compromissos locais (Hive) para o Firestore.
  /// Chamado uma vez no login para garantir que o Usuário 2 veja eventos pré-existentes.
  /// Usa ID determinístico — seguro de chamar múltiplas vezes (idempotente).
  Future<void> syncAllCommitments(Map<String, List<dynamic>> allLocalCommitments) async {
    if (!_authService.isSignedIn || _myProfile == null) return;
    int published = 0;
    for (final entry in allLocalCommitments.entries) {
      final parts = entry.key.split('-');
      if (parts.length != 3) continue;
      DateTime date;
      try {
        date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      } catch (_) { continue; }

      for (final item in entry.value) {
        if (item is! Map) continue;
        final title = (item['title'] as String? ?? '').trim();
        if (title.isEmpty) continue;
        final hour = (item['hour'] as String? ?? '').trim();
        final notes = (item['notes'] as String? ?? '').trim();
        final colorValue = item['color'] as int? ?? const Color(0xFF10A37F).value;
        try {
          final commitment = SharedCommitment(
            id: '',
            ownerUid: _myProfile!.uid,
            ownerName: _myProfile!.displayName,
            date: date,
            title: title,
            hour: hour,
            notes: notes,
            colorValue: colorValue,
          );
          final docId = _commitmentDocId(date, title, hour);
          await _db
              .collection('user_profiles')
              .doc(_myProfile!.uid)
              .collection('commitments')
              .doc(docId)
              .set(commitment.toFirestore());
          published++;
        } catch (e) {
          debugPrint('syncAllCommitments: erro em $date/$title: $e');
        }
      }
    }
    debugPrint('syncAllCommitments: $published compromisso(s) sincronizados.');
  }

  /// Remove um compromisso publicado (somente o dono pode)
  Future<bool> deleteMyCommitment(String commitmentId) async {
    if (_myProfile == null) return false;
    try {
      await _db
          .collection('user_profiles')
          .doc(_myProfile!.uid)
          .collection('commitments')
          .doc(commitmentId)
          .delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting: $e');
      return false;
    }
  }

  /// Stream dos compromissos publicados de um usuário específico (num mês)
  Stream<List<SharedCommitment>> getCommitmentsStream(String uid, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return _db
        .collection('user_profiles')
        .doc(uid)
        .collection('commitments')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start),
                      isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map((d) => SharedCommitment.fromFirestore(d)).toList());
  }

  /// Stream dos meus próprios compromissos publicados (num mês)
  Stream<List<SharedCommitment>> getMyPublishedStream(DateTime month) {
    if (_myProfile == null) return const Stream.empty();
    return getCommitmentsStream(_myProfile!.uid, month);
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }
}
