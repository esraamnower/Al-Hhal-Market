import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// توحيد النصوص العربية لتفادي فروقات المسافات، والهمزات، والتاء المربوطة، إلخ.
String _normalizeArabic(String text) {
  var n = text.trim().toLowerCase();
  n = n.replaceAll(RegExp(r'[\u064B-\u065F]'), ''); // إزالة الحركات
  n = n.replaceAll(RegExp(r'[أإآ]'), 'ا'); // توحيد الألف والهمزات
  n = n.replaceAll('ة', 'ه'); // توحيد التاء المربوطة والهاء
  n = n.replaceAll('ى', 'ي'); // توحيد الألف المقصورة والياء
  n = n.replaceAll(' ', ''); // إزالة المسافات تماماً لضمان المطابقة اللينة مثل (ابو احمد) و (ابواحمد)
  return n;
}

class SupplierBill {
  final String billNumber;
  final String supplierName;
  final String sValue;
  final String date;

  final double totalSalesValue;
  final double maloomPercent;
  final double maloomValue;
  final double loadValue;
  final double paymentValue;
  final double portageValue; // مرة واحدة فقط
  final double totalExpenses;
  final double netInvoice;
  final String createdAt;

  SupplierBill({
    required this.billNumber,
    required this.supplierName,
    required this.sValue,
    required this.date,
    required this.totalSalesValue,
    required this.maloomPercent,
    required this.maloomValue,
    required this.loadValue,
    required this.paymentValue,
    required this.portageValue,
    required this.totalExpenses,
    required this.netInvoice,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'billNumber': billNumber,
        'supplierName': supplierName,
        'sValue': sValue,
        'date': date,
        'totalSalesValue': totalSalesValue,
        'maloomPercent': maloomPercent,
        'maloomValue': maloomValue,
        'loadValue': loadValue,
        'paymentValue': paymentValue,
        'portageValue': portageValue,
        'totalExpenses': totalExpenses,
        'netInvoice': netInvoice,
        'createdAt': createdAt,
      };

  factory SupplierBill.fromJson(Map<String, dynamic> json) {
    return SupplierBill(
      billNumber: json['billNumber'] ?? '',
      supplierName: json['supplierName'] ?? '',
      sValue: json['sValue'] ?? '',
      date: json['date'] ?? '',
      totalSalesValue: (json['totalSalesValue'] ?? 0).toDouble(),
      maloomPercent: (json['maloomPercent'] ?? 0).toDouble(),
      maloomValue: (json['maloomValue'] ?? 0).toDouble(),
      loadValue: (json['loadValue'] ?? 0).toDouble(),
      paymentValue: (json['paymentValue'] ?? 0).toDouble(),
      portageValue: (json['portageValue'] ?? 0).toDouble(),
      totalExpenses: (json['totalExpenses'] ?? 0).toDouble(),
      netInvoice: (json['netInvoice'] ?? 0).toDouble(),
      createdAt: json['createdAt'] ?? '',
    );
  }
}

class SupplierBillStorageService {
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
    if (!await rootFolder.exists()) await rootFolder.create(recursive: true);
    return rootPath;
  }

  Future<String> _getFolderPath() async {
    final basePath = await _getBasePath();
    final folderPath = '$basePath/SupplierBills';
    final folder = Directory(folderPath);
    if (!await folder.exists()) await folder.create(recursive: true);
    return folderPath;
  }

  String _createFileName(String date, String supplierName, String sValue) {
    final dateParts = date.split('/');
    final formattedDate = dateParts.join('-');
    final normalizedSupplier = _normalizeArabic(supplierName);
    final safeSupplier = normalizedSupplier.replaceAll(RegExp(r'[\\/]'), '_');
    
    // توحيد قيمة س برمجياً لتجنب اختلاف الأسماء بالأصفار البادئة (01 مقابل 1)
    final parsedS = int.tryParse(sValue.trim());
    final normalizedS = parsedS != null ? parsedS.toString() : sValue.trim();
    final safeS = normalizedS.replaceAll(RegExp(r'[\\/]'), '_');
    
    return 'bill-$formattedDate-${safeSupplier}-s$safeS.json';
  }

  Future<File> _getBillFile(
      String date, String supplierName, String sValue) async {
    final folderPath = await _getFolderPath();
    final fileName = _createFileName(date, supplierName, sValue);
    return File('$folderPath/$fileName');
  }

  Future<bool> billExists(
      String date, String supplierName, String sValue) async {
    try {
      final file = await _getBillFile(date, supplierName, sValue);
      return await file.exists();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في فحص وجود الفاتورة: $e');
      return false;
    }
  }

  Future<SupplierBill?> loadBill(
      String date, String supplierName, String sValue) async {
    try {
      final file = await _getBillFile(date, supplierName, sValue);
      if (!await file.exists()) return null;
      final jsonString = await file.readAsString();
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return SupplierBill.fromJson(jsonMap);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في تحميل الفاتورة: $e');
      return null;
    }
  }

  Future<String?> saveBill({
    required String date,
    required String supplierName,
    required String sValue,
    required double totalSalesValue,
    required double maloomPercent,
    required double maloomValue,
    required double loadValue,
    required double paymentValue,
    required double portageValue, // معامل واحد فقط
    required double totalExpenses,
    required double netInvoice,
  }) async {
    try {
      final file = await _getBillFile(date, supplierName, sValue);
      if (await file.exists()) {
        if (kDebugMode) debugPrint('⚠️ الفاتورة موجودة مسبقاً');
        return null;
      }

      final billNumber = await getNextBillNumber();
      final bill = SupplierBill(
        billNumber: billNumber,
        supplierName: supplierName.trim(),
        sValue: sValue.trim(),
        date: date,
        totalSalesValue: totalSalesValue,
        maloomPercent: maloomPercent,
        maloomValue: maloomValue,
        loadValue: loadValue,
        paymentValue: paymentValue,
        portageValue: portageValue,
        totalExpenses: totalExpenses,
        netInvoice: netInvoice,
        createdAt: DateTime.now().toIso8601String(),
      );

      await file.writeAsString(jsonEncode(bill.toJson()));
      if (kDebugMode) debugPrint('✅ تم حفظ فاتورة المورد رقم $billNumber');
      return billNumber;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في حفظ فاتورة المورد: $e');
      return null;
    }
  }

  Future<bool> deleteBill(
      String date, String supplierName, String sValue) async {
    try {
      final file = await _getBillFile(date, supplierName, sValue);
      if (await file.exists()) {
        await file.delete();
        if (kDebugMode) debugPrint('✅ تم حذف فاتورة المورد');
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في حذف الفاتورة: $e');
      return false;
    }
  }

  Future<String> getNextBillNumber() async {
    try {
      final folderPath = await _getFolderPath();
      final folder = Directory(folderPath);
      if (!await folder.exists()) return '1';

      final files = await folder.list().toList();
      int maxNumber = 0;
      for (var f in files) {
        if (f is File &&
            f.path.endsWith('.json') &&
            f.path.split(Platform.pathSeparator).last.startsWith('bill-')) {
          try {
            final jsonMap =
                jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            final num =
                int.tryParse(jsonMap['billNumber']?.toString() ?? '0') ?? 0;
            if (num > maxNumber) maxNumber = num;
          } catch (_) {}
        }
      }
      return (maxNumber + 1).toString();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في حساب رقم الفاتورة التالي: $e');
      return '1';
    }
  }

  Future<bool> isLocked(String date, String supplierName, String sValue) async {
    return await billExists(date, supplierName, sValue);
  }
}
