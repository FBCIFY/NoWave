/// Profil renvoyé par le backend. [UserProfile.fromJson] lit les clés en
/// snake_case ; [copyWith] ne modifie que les trois préférences.
class UserProfile {
  final String id;
  final String username;
  final DateTime? dateOfBirth;
  final String? nationality;
  final String role;
  final String status;
  final bool showUserName;
  final bool showBoatInfo;
  final bool notificationsEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.dateOfBirth,
    required this.nationality,
    required this.role,
    required this.status,
    required this.showUserName,
    required this.showBoatInfo,
    required this.notificationsEnabled,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final dateOfBirth = json['date_of_birth'] as String?;

    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      dateOfBirth: dateOfBirth == null ? null : DateTime.parse(dateOfBirth),
      nationality: json['nationality'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
      showUserName: json['show_user_name'] as bool,
      showBoatInfo: json['show_boat_info'] as bool,
      notificationsEnabled: json['notifications_enabled'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  UserProfile copyWith({
    bool? showUserName,
    bool? showBoatInfo,
    bool? notificationsEnabled,
  }) {
    return UserProfile(
      id: id,
      username: username,
      dateOfBirth: dateOfBirth,
      nationality: nationality,
      role: role,
      status: status,
      showUserName: showUserName ?? this.showUserName,
      showBoatInfo: showBoatInfo ?? this.showBoatInfo,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
