import '../matches/match_draft.dart';

enum SyncStatus {
  /// Saved on the phone, waiting for a connection.
  pending,

  /// Being sent right now.
  sending,

  /// The server found a same-day match with the same teams; the user decides.
  needsConfirmation,

  /// The server rejected it (e.g. invalid data); the user can edit or discard.
  failed,
}

/// A match registered on this phone that the server does not have yet. It is
/// never dropped silently: it leaves the list only when the server confirms it
/// or when its author discards it.
class PendingMatch {
  const PendingMatch({
    required this.draft,
    required this.ownerUid,
    required this.status,
    this.message,
    this.duplicateConfirmed = false,
  });

  factory PendingMatch.fromStorage(Map<String, dynamic> json) => PendingMatch(
        draft: MatchDraft.fromStorage(json['draft'] as Map<String, dynamic>),
        ownerUid: json['ownerUid'] as String,
        // A send interrupted by closing the app is simply pending again.
        status: switch (SyncStatus.values.byName(json['status'] as String)) {
          SyncStatus.sending => SyncStatus.pending,
          final other => other,
        },
        message: json['message'] as String?,
        duplicateConfirmed: json['duplicateConfirmed'] as bool? ?? false,
      );

  final MatchDraft draft;

  /// Only the user who registered it may send, edit or discard it (D-016).
  final String ownerUid;
  final SyncStatus status;

  /// Last server or connection message, in Portuguese.
  final String? message;
  final bool duplicateConfirmed;

  String get id => draft.id;

  String get statusLabel => switch (status) {
        SyncStatus.pending => 'Pendente de sincronização',
        SyncStatus.sending => 'Enviando…',
        SyncStatus.needsConfirmation => 'Possível partida repetida: confirme',
        SyncStatus.failed => 'Erro de sincronização',
      };

  PendingMatch copyWith({
    MatchDraft? draft,
    SyncStatus? status,
    String? Function()? message,
    bool? duplicateConfirmed,
  }) =>
      PendingMatch(
        draft: draft ?? this.draft,
        ownerUid: ownerUid,
        status: status ?? this.status,
        message: message == null ? this.message : message(),
        duplicateConfirmed: duplicateConfirmed ?? this.duplicateConfirmed,
      );

  Map<String, dynamic> toStorage() => {
        'draft': draft.toStorage(),
        'ownerUid': ownerUid,
        'status': status.name,
        'message': message,
        'duplicateConfirmed': duplicateConfirmed,
      };
}
