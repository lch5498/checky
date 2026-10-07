import 'package:flutter/services.dart';

class IncomingSharePayload {
  const IncomingSharePayload({required this.id, required this.text});

  final String id;
  final String text;

  static IncomingSharePayload? fromPlatform(Object? value) {
    if (value is! Map) {
      return null;
    }

    final id = value['id'];
    final text = value['text'];

    if (id is! String || text is! String) {
      return null;
    }

    final normalizedId = id.trim();
    final normalizedText = text.trim();

    if (normalizedId.isEmpty || normalizedText.isEmpty) {
      return null;
    }

    return IncomingSharePayload(id: normalizedId, text: normalizedText);
  }
}

class IncomingShareService {
  IncomingShareService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('checky/incoming_share');

  final MethodChannel _channel;

  void listen(Future<void> Function(IncomingSharePayload payload) onShare) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onShare') {
        return;
      }

      final payload = IncomingSharePayload.fromPlatform(call.arguments);
      if (payload != null) {
        await onShare(payload);
      }
    });
  }

  void stopListening() {
    _channel.setMethodCallHandler(null);
  }

  Future<IncomingSharePayload?> consumePending() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getPendingShare');
      return IncomingSharePayload.fromPlatform(value);
    } on MissingPluginException {
      return null;
    }
  }
}
