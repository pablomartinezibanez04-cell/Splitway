enum UserRole {
  user,
  admin,
  superadmin;

  bool get isAdmin => this == admin || this == superadmin;

  static UserRole fromString(String? value) => switch (value) {
        'admin' => admin,
        'superadmin' => superadmin,
        _ => user,
      };
}
