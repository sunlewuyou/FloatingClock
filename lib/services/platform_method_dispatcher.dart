import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared dispatcher for native callbacks on the floating_clock MethodChannel.
/// Pages register listeners instead of replacing the channel's single handler.
typedef PlatformCallHandler = Future<void> Function(MethodCall call);

class PlatformMethodDispatcher {
  PlatformMethodDispatcher._();


  static const MethodChannel channel = MethodChannel('floating_clock');
  static final Map<Object, PlatformCallHandler> _listeners = {};
  static bool _installed = false;


  static VoidCallback register(Object owner, PlatformCallHandler handler) {
    _listeners[owner] = handler;
    if (!_installed) {
      channel.setMethodCallHandler(_dispatch);
      _installed = true;
    }
    return () {
      _listeners.remove(owner);
      // Keep the single dispatcher installed. Removing the platform handler here
      // would break other mounted routes and allow native events to be lost.
    };
  }


  static Future<void> _dispatch(MethodCall call) async {
    // Snapshot protects iteration if a route unregisters during dispatch.
    for (final handler in List<PlatformCallHandler>.of(_listeners.values)) {
      try {
        await handler(call);
      } catch (error, stackTrace) {
        debugPrint('Native callback ${call.method} failed: $error\n$stackTrace');
      }
    }
  }
}
