class User {
  final String id;
  final String name;
  final String email;
  final String? lastLogin;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.lastLogin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'],
      email: json['email'],
      lastLogin: json['lastLogin'],
    );
  }
}
