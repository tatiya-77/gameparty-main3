/// อัปโหลดรูปภาพและวิดีโอไปยัง Cloudinary แล้วคืน secure URL ให้หน้าจอนำไปบันทึกใน Firestore.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// ใช้ unsigned upload preset ส่ง bytes ไปยัง endpoint แยก image/video แล้วอ่าน secure_url จาก response.
class CloudinaryService {
  // Cloudinary configuration
  static const String cloudName = 'ikevsyy7';
  static const String uploadPreset = 'game-party-202';

  /// อัปโหลดรูปภาพ
  static Future<String?> uploadImage(XFile image) async {
    return uploadMedia(image, isVideo: false);
  }

  /// อัปโหลดรูปภาพหรือวิดีโอ
  /// สร้าง multipart request พร้อม timeout, ตรวจรหัส HTTP และแปลงข้อผิดพลาดของ Cloudinary ให้อ่านได้.
  static Future<String?> uploadMedia(
    XFile file, {
    required bool isVideo,
  }) async {
    try {
      if (cloudName.trim().isEmpty ||
          uploadPreset.trim().isEmpty ||
          cloudName == 'YOUR_CLOUD_NAME' ||
          uploadPreset == 'YOUR_UNSIGNED_UPLOAD_PRESET') {
        throw Exception(
          'กรุณาตั้งค่า Cloudinary Cloud Name '
          'และ Unsigned Upload Preset',
        );
      }

      final resourceType = isVideo ? 'video' : 'image';

      final uri = Uri.https(
        'api.cloudinary.com',
        '/v1_1/$cloudName/$resourceType/upload',
      );

      // อ่านข้อมูลไฟล์
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('ไฟล์ที่เลือกไม่มีข้อมูล');
      }

      debugPrint('[Cloudinary] File: ${file.name}');
      debugPrint('[Cloudinary] Size: ${bytes.length} bytes');
      debugPrint('[Cloudinary] Type: $resourceType');

      // เตรียมคำขออัปโหลด
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name.isNotEmpty
                ? file.name
                : (isVideo ? 'upload_video.mp4' : 'upload_image.jpg'),
          ),
        );

      // ส่งไฟล์ไป Cloudinary
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        '[Cloudinary] HTTP: ${response.statusCode}',
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        var message = 'Cloudinary อัปโหลดไม่สำเร็จ';

        try {
          final body = jsonDecode(response.body);

          if (body is Map) {
            final error = body['error'];

            if (error is Map) {
              message = error['message']?.toString() ?? message;
            }
          }
        } catch (_) {
          // ใช้ข้อความเริ่มต้น หากอ่านรายละเอียดไม่ได้
        }

        throw Exception(
          '$message (HTTP ${response.statusCode})',
        );
      }

      // อ่านผลลัพธ์จาก Cloudinary
      final dynamic decoded = jsonDecode(response.body);

      if (decoded is! Map) {
        throw Exception(
          'รูปแบบข้อมูลที่ Cloudinary ส่งกลับมาไม่ถูกต้อง',
        );
      }

      final url = decoded['secure_url']?.toString();

      if (url == null || url.isEmpty) {
        throw Exception(
          'Cloudinary ไม่ได้ส่ง URL ของไฟล์กลับมา',
        );
      }

      debugPrint('[Cloudinary] Upload successful: $url');

      return url;
    } catch (e, stackTrace) {
      debugPrint('[Cloudinary] Upload error: $e');
      debugPrintStack(stackTrace: stackTrace);

      rethrow;
    }
  }
}
