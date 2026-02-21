import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ScreenshotOcrResult {
  final List<XFile> images;
  final String extractedText;

  ScreenshotOcrResult({required this.images, required this.extractedText});
}

class ScreenshotOcrService {
  ScreenshotOcrService._();

  static final ImagePicker _picker = ImagePicker();

  /// Pick up to [maxImages] screenshots from gallery and OCR them on-device.
  /// Returns extracted text + the selected images list (for thumbnails).
  static Future<ScreenshotOcrResult?> pickAndExtract({
    int maxImages = 3,
  }) async {
    // image_picker: multi-image (gallery)
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return null;

    final images = picked.take(maxImages).toList(growable: false);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final buffer = StringBuffer();

      for (final img in images) {
        final f = File(img.path);
        if (!await f.exists()) continue;

        final input = InputImage.fromFile(f);
        final recognized = await recognizer.processImage(input);

        final text = recognized.text.trim();
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln("\n---\n");
          buffer.writeln(text);
        }
      }

      return ScreenshotOcrResult(
        images: images,
        extractedText: buffer.toString().trim(),
      );
    } finally {
      await recognizer.close();
    }
  }

  /// Simple privacy redaction (optional): mask phone-like numbers + emails.
  static String redactBasic(String text) {
    var t = text;

    // emails
    t = t.replaceAll(RegExp(r'\b[\w\.\-]+@[\w\.\-]+\.\w+\b'), '[EMAIL]');

    // phone-ish sequences (very rough)
    t = t.replaceAll(RegExp(r'\b(\+?\d[\d\-\s]{7,}\d)\b'), '[PHONE]');

    return t;
  }
}
