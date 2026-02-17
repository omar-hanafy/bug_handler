/// Represents the severity level of an error or exception
enum ErrorSeverity {
  /// Critical errors that need immediate attention
  /// Usually system-wide failures or data corruption issues
  critical,

  /// Standard errors that impact core functionality
  /// Most exceptions should use this level
  error,

  /// Issues that don't break core functionality
  /// But might impact user experience
  warning,

  /// Informational issues that don't impact functionality
  /// Useful for tracking edge cases or deprecation notices
  info
  ;

  /// Whether this severity level should trigger an automatic report
  bool get shouldAutoReport => index <= ErrorSeverity.error.index;

  /// Whether this severity level should be reported to Sentry
  bool get shouldReportToSentry => index <= ErrorSeverity.warning.index;
}
