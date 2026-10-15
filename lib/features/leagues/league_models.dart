/// "Beach Tennis Arena": the group from before leagues (D-023). Matches saved
/// on the phone before the update belong to it.
const arenaLeagueId = '00000000-0000-0000-0000-000000000001';

enum LeagueVisibility {
  public('PUBLIC', 'Pública'),
  private('PRIVATE', 'Privada');

  const LeagueVisibility(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static LeagueVisibility fromApi(String value) => values.firstWhere((v) => v.apiValue == value);
}

enum LeagueRole {
  admin('ADMIN'),
  member('MEMBER');

  const LeagueRole(this.apiValue);

  final String apiValue;

  static LeagueRole? fromApi(String? value) => value == null ? null : values.firstWhere((r) => r.apiValue == value);
}

/// A league as the signed-in user sees it (D-017). Who may administer it comes
/// from [canAdminister]; the app never deduces it otherwise.
class League {
  const League({
    required this.id,
    required this.name,
    this.description,
    required this.visibility,
    required this.memberCount,
    required this.memberLimit,
    this.archived = false,
    this.myRole,
    this.canAdminister = false,
    this.joinRequestPending = false,
  });

  factory League.fromJson(Map<String, dynamic> json) => League(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        visibility: LeagueVisibility.fromApi(json['visibility'] as String),
        memberCount: json['memberCount'] as int,
        memberLimit: json['memberLimit'] as int,
        archived: json['archived'] as bool,
        myRole: LeagueRole.fromApi(json['myRole'] as String?),
        canAdminister: json['canAdminister'] as bool,
        joinRequestPending: json['joinRequestPending'] as bool,
      );

  final String id;
  final String name;
  final String? description;
  final LeagueVisibility visibility;
  final int memberCount;
  final int memberLimit;

  /// Read-only: no matches, seasons or administration (still listed in "Minhas ligas").
  final bool archived;

  /// Null when the user is not a member.
  final LeagueRole? myRole;
  final bool canAdminister;
  final bool joinRequestPending;

  bool get isMember => myRole != null;

  bool get full => memberCount >= memberLimit;

  /// Shown everywhere as "13/50".
  String get membersLabel => '$memberCount/$memberLimit';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'visibility': visibility.apiValue,
        'memberCount': memberCount,
        'memberLimit': memberLimit,
        'archived': archived,
        'myRole': myRole?.apiValue,
        'canAdminister': canAdminister,
        'joinRequestPending': joinRequestPending,
      };
}

extension LeagueCopy on League {
  League copyWith({bool? joinRequestPending}) => League(
        id: id,
        name: name,
        description: description,
        visibility: visibility,
        memberCount: memberCount,
        memberLimit: memberLimit,
        archived: archived,
        myRole: myRole,
        canAdminister: canAdminister,
        joinRequestPending: joinRequestPending ?? this.joinRequestPending,
      );
}

class LeaguePage {
  const LeaguePage({required this.items, required this.hasNext});

  final List<League> items;
  final bool hasNext;
}

class LeagueMember {
  const LeagueMember({required this.playerId, required this.displayName, required this.role, required this.joinedAt});

  factory LeagueMember.fromJson(Map<String, dynamic> json) => LeagueMember(
        playerId: json['playerId'] as String,
        displayName: json['displayName'] as String,
        role: LeagueRole.fromApi(json['role'] as String)!,
        joinedAt: DateTime.parse(json['joinedAt'] as String).toLocal(),
      );

  final String playerId;
  final String displayName;
  final LeagueRole role;
  final DateTime joinedAt;
}

/// An invitation the user received to a league (D-019).
class LeagueInvitation {
  const LeagueInvitation({required this.id, required this.league, required this.invitedByName, required this.createdAt});

  factory LeagueInvitation.fromJson(Map<String, dynamic> json) => LeagueInvitation(
        id: json['id'] as String,
        league: League.fromJson(json['league'] as Map<String, dynamic>),
        invitedByName: json['invitedByName'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );

  final String id;
  final League league;
  final String invitedByName;
  final DateTime createdAt;
}
