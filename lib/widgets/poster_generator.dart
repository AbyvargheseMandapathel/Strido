import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class PosterGenerator {
  static Future<File?> createPoster({
    required int steps,
    required String date,
    required int rank,
    String username = 'You',
  }) async {
    // Load the background image
    final bgBytes = await rootBundle.load('assets/images/strido_story_bg.png');
    final bgImage = img.decodeImage(bgBytes.buffer.asUint8List());
    if (bgImage == null) return null;

    // Create a new image with the background
    final image = img.Image(width: 1080, height: 1920);
    img.compositeImage(image, bgImage);

    // Load the font
    final fontData = await rootBundle.load('assets/fonts/arial.ttf');
    final font = img.BitmapFont.fromZip(fontData.buffer.asUint8List());

    // Draw the content with corrected font sizes
    _drawText(image, font, 'STRIDO', 360, 200, size: 40);
    _drawText(image, font, date, 400, 350, size: 25);
    _drawText(image, font, steps.toString(), 300, 700, size: 80);
    _drawText(image, font, 'STEPS', 420, 900, size: 30);
    if (rank <= 10) {
      _drawText(image, font, 'RANK #$rank', 380, 1100, size: 35);
    }
    _drawText(image, font, 'Shared by $username', 350, 1600, size: 25);

    // Add the logo
    final logoBytes = await rootBundle.load('assets/icon/logo.png');
    final logoImage = img.decodeImage(logoBytes.buffer.asUint8List());
    if (logoImage != null) {
      img.compositeImage(image, logoImage, dstX: 440, dstY: 1700);
    }

    // Save the image
    try {
      if (await Permission.storage.request().isGranted) {
        final directory = await getTemporaryDirectory();
        final path = '${directory.path}/poster.png';
        final file = File(path);
        await file.writeAsBytes(img.encodePng(image));
        return file;
      }
    } catch (e) {
      print(e);
    }
    return null;
  }

  static void _drawText(img.Image image, img.BitmapFont font, String text, int x, int y, {int size = 2}) {
    img.drawString(image, text, font: font, x: x, y: y, wrap: false, color: img.ColorRgb8(255, 255, 255));
  }
}
