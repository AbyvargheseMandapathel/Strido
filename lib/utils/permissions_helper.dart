import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionsHelper {
  /// Ensure BLE + location permissions required for scanning/connecting are granted.
  /// Shows a short rationale dialog if not previously granted.
  static Future<bool> ensureBlePermissions(BuildContext context) async {
    if (Platform.isIOS) {
      // iOS: ensure Info.plist keys present; runtime prompt happens automatically.
      return true;
    }

    // Android path
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdk = androidInfo.version.sdkInt ?? 0;

    // Show rationale dialog before requesting if not granted
    Future<bool> _showRationale() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Permission required'),
          content: const Text(
            'We need Bluetooth & location permissions to discover and connect to wearable devices. '
            'This allows the app to sync step counts from your watch.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Continue')),
          ],
        ),
      );
      return ok ?? false;
    }

    // Request appropriate permissions
    if (sdk >= 31) {
      // Android 12+ : new bluetooth runtime perms
      final granted = await Permission.bluetoothScan.isGranted &&
          await Permission.bluetoothConnect.isGranted;
      if (granted) return true;

      final proceed = await _showRationale();
      if (!proceed) return false;

      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        // keep location as fallback for some devices
        Permission.locationWhenInUse,
      ].request();

      final ok = (results[Permission.bluetoothScan]?.isGranted ?? false) &&
          (results[Permission.bluetoothConnect]?.isGranted ?? false);
      if (ok) return true;

      // handle permanently denied
      if (results.values.any((p) => p.isPermanentlyDenied)) {
        await _showOpenSettings(context);
      }
      return false;
    } else {
      // Older Android: location permission is needed for BLE scanning
      if (await Permission.locationWhenInUse.isGranted) return true;
      final proceed = await _showRationale();
      if (!proceed) return false;

      final status = await Permission.locationWhenInUse.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) await _showOpenSettings(context);
      return false;
    }
  }

  static Future<void> _showOpenSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Permission required'),
        content: const Text('Permissions are permanently denied. Open app settings to enable them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(dialogCtx);
              },
              child: const Text('Open settings')),
        ],
      ),
    );
  }
}