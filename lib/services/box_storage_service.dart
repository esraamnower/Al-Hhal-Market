import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../models/box_model.dart';
import 'package:flutter/foundation.dart';

class BoxStorageService {
  // ✅ المسار الجذري الموحد: Documenti/alhalmarket
  Future<String> _getBasePath() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else if (Platform.isWindows) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final rootPath = '${directory!.path}/alhalmarket';
    final rootFolder = Directory(rootPath);
    if (!await rootFolder.exists()) {
      await rootFolder.create(recursive: true);
    }

    return rootPath;
  }

  // اسم الملف يعتمد على التاريخ فقط
  String _createFileName(String date) {
    final dateParts = date.split('/');
    final formattedDate = dateParts.join('-');
    return 'box-$formattedDate.json';
  }

  Future<bool> saveBoxDocument(BoxDocument document) async {
    try {
      final basePath = await _getBasePath();
      // ✅ المسار الصحيح: alhalmarket/BoxJournals
      final folderPath = '$basePath/BoxJournals';
      final folder = Directory(folderPath);
      if (!await folder.exists()) await folder.create(recursive: true);

      final fileName = _createFileName(document.date);
      final filePath = '$folderPath/$fileName';
      final file = File(filePath);
      final jsonString = jsonEncode(document.toJson());
      await file.writeAsString(jsonString);

      if (kDebugMode) {
        debugPrint('✅ تم حفظ يومية الصندوق: $filePath');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في حفظ يومية الصندوق: $e');
      }
      return false;
    }
  }

  Future<BoxDocument?> loadBoxDocumentForDate(String date) async {
    try {
      final basePath = await _getBasePath();
      // ✅ المسار الصحيح: alhalmarket/BoxJournals
      final folderPath = '$basePath/BoxJournals';
      final fileName = _createFileName(date);
      final filePath = '$folderPath/$fileName';

      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final jsonString = await file.readAsString();
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return BoxDocument.fromJson(jsonMap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في قراءة يومية الصندوق: $e');
      }
      return null;
    }
  }

  Future<BoxDocument?> loadBoxDocument(String date, String recordNumber) async {
    // تتجاهل recordNumber لأن هناك ملف واحد فقط لكل يوم
    return await loadBoxDocumentForDate(date);
  }

  Future<List<String>> getAvailableRecords(String date) async {
    try {
      final document = await loadBoxDocumentForDate(date);
      if (document != null) {
        return [document.recordNumber];
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في قراءة سجلات الصندوق: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, String>>> getAvailableDatesWithNumbers() async {
    try {
      final basePath = await _getBasePath();
      // ✅ المسار الصحيح: alhalmarket/BoxJournals
      final folderPath = '$basePath/BoxJournals';

      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        return [];
      }

      final files = await folder.list().toList();
      final datesWithNumbers = <Map<String, String>>[];

      for (var file in files) {
        if (file is File &&
            file.path.endsWith('.json') &&
            file.path.split(Platform.pathSeparator).last.startsWith('box-')) {
          try {
            final jsonString = await file.readAsString();
            final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
            final date = jsonMap['date']?.toString() ?? '';
            final journalNumber = jsonMap['recordNumber']?.toString() ?? '1';
            if (date.isNotEmpty) {
              datesWithNumbers.add({
                'date': date,
                'journalNumber': journalNumber,
              });
            }
          } catch (e) {/* تجاهل الملفات التالفة */}
        }
      }

      datesWithNumbers.sort((a, b) {
        final numA = int.tryParse(a['journalNumber'] ?? '0') ?? 0;
        final numB = int.tryParse(b['journalNumber'] ?? '0') ?? 0;
        return numA.compareTo(numB);
      });

      return datesWithNumbers;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في قراءة تواريخ الصندوق: $e');
      }
      return [];
    }
  }

  Future<String?> getFilePath(String date) async {
    try {
      final basePath = await _getBasePath();
      final folderPath = '$basePath/BoxJournals';
      final fileName = _createFileName(date);
      final filePath = '$folderPath/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        return filePath;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في الحصول على مسار ملف الصندوق: $e');
      }
      return null;
    }
  }

  Future<String> getJournalNumberForDate(String date) async {
    try {
      final document = await loadBoxDocumentForDate(date);
      return document?.recordNumber ?? '1';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في الحصول على رقم يومية الصندوق: $e');
      }
      return '1';
    }
  }

  Future<String> getNextJournalNumber() async {
    try {
      final basePath = await _getBasePath();
      final folderPath = '$basePath/BoxJournals';

      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        return '1';
      }

      final files = await folder.list().toList();
      int maxJournalNumber = 0;

      for (var file in files) {
        if (file is File &&
            file.path.endsWith('.json') &&
            file.path.split(Platform.pathSeparator).last.startsWith('box-')) {
          try {
            final jsonString = await file.readAsString();
            final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
            final journalNumber =
                int.tryParse(jsonMap['recordNumber'] ?? '0') ?? 0;
            if (journalNumber > maxJournalNumber) {
              maxJournalNumber = journalNumber;
            }
          } catch (e) {/* تجاهل الملفات التالفة */}
        }
      }
      return (maxJournalNumber + 1).toString();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في الحصول على الرقم التسلسلي التالي للصندوق: $e');
      }
      return '1';
    }
  }
}
