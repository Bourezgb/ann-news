import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// اختيار الملفات ونسخها إلى مجلد التطبيق حتى تبقى متاحة (للسجل والتصميم).
class MediaPicker {
  static final _imagePicker = ImagePicker();

  static Future<Directory> _dir(String name) async {
    final d = Directory(p.join((await getApplicationDocumentsDirectory()).path, name));
    await d.create(recursive: true);
    return d;
  }

  static Future<String> _keep(XFile f, String folder) async {
    final dir = await _dir(folder);
    final ext = p.extension(f.name).isEmpty ? p.extension(f.path) : p.extension(f.name);
    final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}$ext');
    await f.saveTo(dest);
    return dest;
  }

  static Future<List<String>> pickImages() async {
    final files = await _imagePicker.pickMultiImage();
    return [for (final f in files) await _keep(f, 'inputs')];
  }

  static Future<String?> takePhoto() async {
    final f = await _imagePicker.pickImage(source: ImageSource.camera);
    return f == null ? null : _keep(f, 'inputs');
  }

  static Future<String?> pickAudio() => _pickOne(FileType.audio);

  static Future<String?> pickVideo() => _pickOne(FileType.video);

  static Future<String?> _pickOne(FileType type) async {
    final picked = await FilePicker.pickFile(type: type);
    if (picked == null) return null;
    final path = picked.path;
    // الملفات الكبيرة (فيديو) لا تُنسخ إذا كان لها مسار حقيقي.
    if (path != null && File(path).existsSync()) return path;
    return _keep(picked.xFile, 'inputs');
  }

  /// صورة خلفية للتصميم.
  static Future<String?> pickBackground({bool camera = false}) async {
    final f = await _imagePicker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery);
    return f == null ? null : _keep(f, 'backgrounds');
  }

  /// ملف قالب PNG.
  static Future<File?> pickTemplateFile() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['png', 'webp', 'jpg', 'jpeg']);
    if (picked == null) return null;
    final path = picked.path;
    if (path != null && File(path).existsSync()) return File(path);
    return File(await _keep(picked.xFile, 'tmp'));
  }
}
