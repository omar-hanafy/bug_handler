import 'package:bug_reporting_system/context/provider.dart';

/// Lightweight user/session context. Keep PII to a minimum by default.
/// If you need to include sensitive traits, a sanitizer in your privacy
/// pipeline should mask/strip them before sending.
class UserContextProvider extends ContextProvider {
  /// Creates a user context provider that exposes lightweight identifiers and
  /// traits, optionally limiting collection to manual reports.
  UserContextProvider({
    this.id,
    this.email,
    this.role,
    this.tenantId,
    Map<String, dynamic> traits = const {},
    bool manualOnly = false,
  })  : _traits = Map<String, dynamic>.from(traits),
        _manualOnly = manualOnly;

  /// Stable identifier for the current user, if available.
  final String? id;

  /// Primary email address associated with the user, when safe to expose.
  final String? email;

  /// Access level or role label used for authorization decisions.
  final String? role;

  /// Multi-tenant scope identifier for the user/session.
  final String? tenantId;
  final Map<String, dynamic> _traits;
  final bool _manualOnly;

  @override
  String get name => 'user';

  /// When `true`, user context is included only in user-initiated reports.
  @override
  bool get manualReportOnly => _manualOnly;

  @override
  Map<String, dynamic> getData() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
      if (tenantId != null) 'tenantId': tenantId,
      if (_traits.isNotEmpty) 'traits': _traits,
    };
  }
}
