import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'api_client.dart';

class CouponImageSaver {
  const CouponImageSaver();

  static const _channel = MethodChannel('checky/coupon_image_save');

  Future<void> save(CouponImageData image) async {
    var bytes = image.bytes;
    var mimeType = image.mimeType;
    // Photos does not consistently import WebP across supported iOS releases.
    if (mimeType == 'image/webp') {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (png == null) {
            throw const FormatException('Unable to encode image');
          }
          bytes = png.buffer.asUint8List();
          mimeType = 'image/png';
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    await _channel.invokeMethod<void>('save', <String, Object>{
      'bytes': bytes,
      'mimeType': mimeType,
    });
  }
}
