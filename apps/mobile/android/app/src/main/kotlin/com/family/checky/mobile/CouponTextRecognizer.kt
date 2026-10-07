package com.family.checky.mobile

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

object CouponTextRecognizer {
    fun register(context: Context, messenger: BinaryMessenger) {
        val appContext = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "checky/coupon_text").setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.arguments as? ByteArray
            if (bytes == null || bytes.isEmpty() || bytes.size > 2 * 1024 * 1024) {
                result.error("invalid_image", "Invalid coupon image", null)
                return@setMethodCallHandler
            }
            Thread {
                var file: File? = null
                try {
                    // fromFilePath handles EXIF orientation. Keep the transient file app-private.
                    file = File.createTempFile("coupon-ocr-", ".image", appContext.cacheDir)
                    file.writeBytes(bytes)
                    val input = InputImage.fromFilePath(appContext, Uri.fromFile(file))
                    val recognizer = TextRecognition.getClient(KoreanTextRecognizerOptions.Builder().build())
                    val imageFile = file
                    recognizer.process(input)
                        .addOnSuccessListener { text ->
                            val rotated = input.rotationDegrees % 180 != 0
                            val width = (if (rotated) input.height else input.width).toDouble().coerceAtLeast(1.0)
                            val height = (if (rotated) input.width else input.height).toDouble().coerceAtLeast(1.0)
                            val lines = text.textBlocks.flatMap { it.lines }.map { line ->
                                mapOf("text" to line.text,
                                    "top" to ((line.boundingBox?.top ?: 0) / height),
                                    "left" to ((line.boundingBox?.left ?: 0) / width),
                                    "height" to ((line.boundingBox?.height() ?: 0) / height))
                            }
                            result.success(lines)
                        }
                        .addOnFailureListener { result.error("ocr_failed", "Could not read coupon text", null) }
                        .addOnCompleteListener { recognizer.close(); imageFile.delete() }
                } catch (_: Exception) {
                    file?.delete()
                    main.post { result.error("ocr_failed", "Could not read coupon text", null) }
                }
            }.start()
        }
    }
}
