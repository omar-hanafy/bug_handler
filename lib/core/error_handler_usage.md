# ErrorHandler Usage Guide

## Overview
The ErrorHandler system provides a robust error handling framework with built-in reporting capabilities. It follows a tuple-based return pattern for consistent error management across your application.
All errors are from abstract type -> BaseException 
this package has built in some like: api_exception, auth_exception, base_exception, data_exception, exceptions, flutter_error_exception, initialization_exception,navigation_exception, permission_exception, platform_exception, platform_payment_exception,
storage_exception, unexpected_exception, and validation_exception.

You can add your custom in your project, by extending BaseException.

Usage:
in your app we have controllers and may other logic, service stuff,
parsers, helpers, etc. the role is to make sure all these stuff throw the right exception, not to silent them.
finally in the controller, e.g. bloc, notifier,
etc. you run in one of the following method to handle them and it guarantee returning BaseException type if there is any.
in your controller's state you make its error?
as BaseException instead of string,
or string but u use BaseException.userMessage or BaseException.devMessage if you are in test env, however you like.
the final goal is all error messages are consistent in a clean way.
even if you forget to handle the error,
but u used our helper wrapper and methods,
u can get pretty good info about it, and benefit from the reporter built in.

Package Import: `bug_handler`

- To use me --> import 'package:bug_handler/core/error_handler.dart';

## Core Concepts

### Return Value Pattern
All error handling methods return a tuple containing:
- `Report?` - The bug report if one was created (null if reporting failed or was disabled)
- `bool` - Whether an error occurred (`didThrow`)

### Error Flow Control
Check `didThrow` to determine if an error occurred:
```dart
final (report, didThrow) = await handleError(...);
if (didThrow) {
  // Error path
  if (report != null) {
    analytics.logError(report.id);
  }
  return; // Exit current operation
}
// Success path
```

## Error Handling Methods

### 1. handleError
For direct error handling with maximum control.

```dart
try {
  await riskyOperation();
} catch (error, stack) {
  final (report, didThrow) = await handleError(
    error,
    stack,
    source: 'PaymentScreen',
    userMessage: 'Payment failed, please try again',
    devMessage: 'Payment gateway timeout',
    severity: ErrorSeverity.critical,
    onError: (exception) async {
      await showErrorDialog(exception.userMessage);
      await analytics.logPaymentError(exception);
    },
  );
}
```

### 2. wrapper
For clean, declarative error handling of async operations.

```dart
// Simple Usage
final (report, didThrow) result = await wrapper(
  () => api.fetchData(),
  source: 'DataService',
);

// Advanced Usage with State Management
Future<void> processPayment(String orderId) async {
  final (report, didThrow) = await wrapper(
    () => paymentGateway.process(orderId),
    source: 'PaymentProcessor',
    onSuccess: (receipt) async {
      state = PaymentState.success(receipt);
      await analytics.logPaymentSuccess(receipt);
    },
    onError: (exception) async {
      state = PaymentState.failed(exception.message);
      if (exception is PaymentDeclinedException) {
        await showDeclinedDialog();
      }
    },
  );

  if (didThrow) {
    // do extra stuff if needed.
    // ...

     /// u usually gonna need the didThrow just to return, in case u wanna stop the operation, and since any handling done through the wrapper might be enough for u, however it depends on ur case.    
    return;
  }
  
  // Continue with post-payment operations
}
```

### 3. parser
For safe data parsing with automatic error transformation.

```dart
class ProductModel {
  final String id;
  final double price;
  final List<String> categories;

  ProductModel.fromJson(Map<String, dynamic> json) {
    return parser(() {
      id = json['id'] as String;
      price = (json['price'] as num).toDouble();
      categories = (json['categories'] as List).cast<String>();
    },
     data: json,
     );
  }
}
```

## Best Practices

### 1. Error Severity Guidelines
```dart
// Choose appropriate severity levels:
ErrorSeverity.debug    // Use for development-only issues
ErrorSeverity.info     // Minor issues that don't affect functionality
ErrorSeverity.warning  // Issues that might cause problems
ErrorSeverity.error    // Standard errors that affect functionality
ErrorSeverity.critical // Severe issues requiring immediate attention
```

### 2. Source Naming Convention
```dart
// Good - Clear and specific
source: 'PaymentScreen.processPayment'
source: 'UserRepository.fetchProfile'

// Avoid - Too vague
source: 'process'
source: 'api'
```

### 3. Error Message Guidelines
```dart
await handleError(
  error,
  stack,
  // User-friendly message
  userMessage: 'Unable to update your profile. Please try again.',
  // Technical details for debugging
  devMessage: 'Profile update failed: Invalid JSON response',
);
```

### 4. Batch Operations
```dart
Future<void> syncData() async {
  for (final item in items) {
    final (report, didThrow) = await wrapper(
      () => api.sync(item),
      source: 'DataSync',
      onError: (e) async {
        failedItems.add(item);
        // Continue with next item instead of stopping
      },
    );
  }
}
```

## Error Reporting Integration

The ErrorHandler automatically creates error reports when possible. To make the most of this:

```dart
// 1. Configure report metadata
await BugReporter.instance.configure(
  appVersion: '1.2.3',
  deviceInfo: await DeviceInfo.gather(),
);

// 2. Access report details
final (report, didThrow) = await handleError(...);
if (report != null) {
  print('Error Report ID: ${report.id}');
  print('Report Status: ${report.status}');
}
```

## Common Patterns

### Progressive Enhancement
```dart
Future<void> loadData() async {
  final (report, didThrow) = await wrapper(
    () => api.fetchData(),
    source: 'DataLoader',
    onSuccess: (data) async {
      // Try to enhance data with optional features
      await wrapper(
        () => enrichData(data),
        source: 'DataEnricher',
        // Fail silently on enhancement errors
        onError: (_) {},
      );
      
      state = DataState.loaded(data);
    },
  );
}
```
