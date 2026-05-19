import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

// 1. إضافة واجهة EnhancedIndexService
abstract class EnhancedIndexService {
  Future<List<String>> getEnhancedSuggestions(String query);
}

class SupplierTransaction {
  final String
      type; // 'purchase_debt', 'box_received', 'box_paid', 'receipt_payment', 'receipt_load'
  final double amount;
  final DateTime timestamp;
  final String? reference; // رقم اليومية أو المرجع

  SupplierTransaction({
    required this.type,
    required this.amount,
    required this.timestamp,
    this.reference,
  });
}

class SupplierData {
  String name;
  double balance;
  String mobile;
  bool isBalanceLocked;
  List<SupplierTransaction> transactions; // <-- إضافة قائمة المعاملات

  SupplierData({
    required this.name,
    this.balance = 0.0,
    this.mobile = '',
    this.isBalanceLocked = false,
    this.transactions = const [], // <-- إضافة افتراضية
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'balance': balance,
        'mobile': mobile,
        'isBalanceLocked': isBalanceLocked,
        'transactions': transactions
            .map((t) => {
                  'type': t.type,
                  'amount': t.amount,
                  'timestamp': t.timestamp.toIso8601String(),
                  'reference': t.reference,
                })
            .toList(),
      };

  factory SupplierData.fromJson(dynamic json) {
    if (json is String) {
      return SupplierData(name: json);
    }

    List<SupplierTransaction> transactions = [];
    if (json['transactions'] != null) {
      final List<dynamic> transList = json['transactions'];
      transactions = transList
          .map((t) => SupplierTransaction(
                type: t['type'],
                amount: (t['amount'] ?? 0.0).toDouble(),
                timestamp: DateTime.parse(t['timestamp']),
                reference: t['reference'],
              ))
          .toList();
    }

    return SupplierData(
      name: json['name'] ?? '',
      balance: (json['balance'] ?? 0.0).toDouble(),
      mobile: json['mobile'] ?? '',
      isBalanceLocked: json['isBalanceLocked'] ?? false,
      transactions: transactions,
    );
  }
}

// 2. جعل SupplierIndexService تطبق واجهة EnhancedIndexService
class SupplierIndexService implements EnhancedIndexService {
  static final SupplierIndexService _instance =
      SupplierIndexService._internal();
  factory SupplierIndexService() => _instance;
  SupplierIndexService._internal();

  static const String _fileName = 'supplier_index.json';
  Map<int, SupplierData> _supplierMap = {};
  bool _isInitialized = false;
  int _nextId = 1;

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _loadSuppliers();
      _isInitialized = true;
    }
  }

  Future<String> _getFilePath() async {
    Directory? directory;

    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final folderPath = '${directory!.path}/alhalmarket/SupplierIndex';
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return '$folderPath/$_fileName';
  }

  Future<void> _loadSuppliers() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final Map<String, dynamic> jsonData = jsonDecode(jsonString);

        if (jsonData.containsKey('suppliers') &&
            jsonData.containsKey('nextId')) {
          final Map<String, dynamic> suppliersJson = jsonData['suppliers'];

          _supplierMap.clear();
          suppliersJson.forEach((key, value) {
            _supplierMap[int.parse(key)] = SupplierData.fromJson(value);
          });

          _nextId = jsonData['nextId'] ?? 1;
        } else {
          _supplierMap.clear();
          if (jsonData is List) {
            for (int i = 0; i < jsonData.length; i++) {
              _supplierMap[i + 1] = SupplierData(name: jsonData[i].toString());
            }
            _nextId = jsonData.length + 1;
          } else if (jsonData.containsKey('suppliers')) {
            final List<dynamic> jsonList = jsonData['suppliers'];
            for (int i = 0; i < jsonList.length; i++) {
              _supplierMap[i + 1] = SupplierData(name: jsonList[i].toString());
            }
            _nextId = jsonList.length + 1;
          }
          await _saveToFile();
        }
      } else {
        _supplierMap.clear();
        _nextId = 1;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في تحميل فهرس الموردين: $e');
      }
      _supplierMap.clear();
      _nextId = 1;
    }
  }

  Future<void> saveSupplier(String supplier) async {
    await _ensureInitialized();
    if (supplier.trim().isEmpty) return;
    final normalizedSupplier = _normalizeSupplier(supplier);

    if (!_supplierMap.values
        .any((s) => s.name.toLowerCase() == normalizedSupplier.toLowerCase())) {
      _supplierMap[_nextId] = SupplierData(name: normalizedSupplier);
      _nextId++;
      await _saveToFile();
    }
  }

  String _normalizeSupplier(String supplier) {
    String normalized = supplier.trim();
    if (normalized.isNotEmpty) {
      normalized = normalized[0].toUpperCase() + normalized.substring(1);
    }
    return normalized;
  }

  Future<List<String>> getSuggestions(String query) async {
    await _ensureInitialized();
    if (query.isEmpty) return [];
    final normalizedQuery = query.toLowerCase().trim();
    return _supplierMap.entries
        .where(
            (entry) => entry.value.name.toLowerCase().contains(normalizedQuery))
        .map((entry) => entry.value.name)
        .toList();
  }

  // 3. تنفيذ دالة getEnhancedSuggestions المطلوبة من الواجهة
  @override
  Future<List<String>> getEnhancedSuggestions(String query) async {
    await _ensureInitialized();
    if (query.isEmpty) return [];
    final normalizedQuery = query.trim();

    // البحث بالأرقام
    if (RegExp(r'^\d+$').hasMatch(normalizedQuery)) {
      final int? queryNumber = int.tryParse(normalizedQuery);
      if (queryNumber != null && _supplierMap.containsKey(queryNumber)) {
        return [_supplierMap[queryNumber]!.name];
      }
    }

    // البحث النصي
    return await getSuggestions(normalizedQuery);
  }

  Future<List<String>> getAllSuppliers() async {
    await _ensureInitialized();
    final suppliers = _supplierMap.values.map((s) => s.name).toList();
    suppliers.sort((a, b) => a.compareTo(b));
    return suppliers;
  }

  Future<int?> getSupplierPosition(String supplier) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplier);
    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> updateSupplierBalance(String supplierName, double amount,
      {String operationType = ''}) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);

    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        // تطبيق القواعد الخاصة بالموردين
        switch (operationType) {
          case 'purchase_debt': // دين من المشتريات
          case 'box_received': // مقبوض من الصندوق
            entry.value.balance += amount;
            break;
          case 'box_paid': // مدفوع من الصندوق
          case 'receipt_load': // حمولة من الاستلام
          case 'receipt_payment': // دفعة من الاستلام
            entry.value.balance -= amount;
            break;
          default:
            entry.value.balance += amount;
        }

        entry.value.isBalanceLocked = true;
        await _saveToFile();
        return;
      }
    }
  }

// إضافة دالة لتحديث رصيد المورد بناءً على العملية
  Future<void> updateSupplierBalanceByOperation(
      String supplierName, double amount, String operation) async {
    String operationType = '';

    switch (operation) {
      case 'purchase':
        operationType = 'purchase_debt';
        break;
      case 'box_received':
        operationType = 'box_received';
        break;
      case 'box_paid':
        operationType = 'box_paid';
        break;
      case 'receipt':
        // للاستلام: الدفعة والحمولة تطرح من الرصيد
        operationType = 'receipt_payment_load';
        break;
    }

    await updateSupplierBalance(supplierName, amount,
        operationType: operationType);
  }

  Future<void> setInitialBalance(String supplierName, double balance) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);
    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        if (!entry.value.isBalanceLocked) {
          entry.value.balance = balance;
          await _saveToFile();
        }
        return;
      }
    }
  }

  Future<void> updateSupplierMobile(String supplierName, String mobile) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);
    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        entry.value.mobile = mobile;
        await _saveToFile();
        return;
      }
    }
  }

  Future<void> updateSupplierName(int id, String newName) async {
    await _ensureInitialized();
    if (_supplierMap.containsKey(id)) {
      _supplierMap[id]!.name = _normalizeSupplier(newName);
      await _saveToFile();
    }
  }

  Future<void> removeSupplier(String supplier) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplier);
    int? keyToRemove;
    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        keyToRemove = entry.key;
        break;
      }
    }
    if (keyToRemove != null) {
      _supplierMap.remove(keyToRemove);
      await _saveToFile();
    }
  }

  Future<void> _saveToFile() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      final Map<String, dynamic> suppliersJson = {};
      _supplierMap.forEach((key, value) {
        suppliersJson[key.toString()] = value.toJson();
      });
      final Map<String, dynamic> jsonData = {
        'suppliers': suppliersJson,
        'nextId': _nextId,
      };
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في حفظ فهرس الموردين: $e');
    }
  }

  Future<Map<int, SupplierData>> getAllSuppliersWithData() async {
    await _ensureInitialized();
    return Map.from(_supplierMap);
  }

  Future<Map<int, String>> getAllSuppliersWithNumbers() async {
    await _ensureInitialized();
    return _supplierMap.map((key, value) => MapEntry(key, value.name));
  }

  // 4. إضافة دالة للحصول على بيانات مورد معين
  Future<SupplierData?> getSupplierData(String supplierName) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);
    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  // في supplier_index_service.dart
  Future<void> updateSupplierBalanceWithTracking(
    String supplierName,
    double amount,
    String transactionType,
    String? reference,
  ) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);

    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        // تسجيل المعاملة أولاً
        final transaction = SupplierTransaction(
          type: transactionType,
          amount: amount,
          timestamp: DateTime.now(),
          reference: reference,
        );

        // إضافة المعاملة للقائمة
        entry.value.transactions.add(transaction);

        // تطبيق المعادلة: e = a + b - c - d
        switch (transactionType) {
          case 'purchase_debt': // a (+)
          case 'box_received': // b (+)
            entry.value.balance += amount;
            break;
          case 'box_paid': // c (-)
          case 'receipt_payment': // d (-)
          case 'receipt_load': // d (-)
            entry.value.balance -= amount;
            break;
          default:
            entry.value.balance += amount;
        }

        // تقييد الرصيد بعد أول عملية
        if (!entry.value.isBalanceLocked && amount != 0) {
          entry.value.isBalanceLocked = true;
        }

        // حصرية: لا يزيد الرصيد عن 5 معاملات (أو حسب الحاجة)
        if (entry.value.transactions.length > 5) {
          entry.value.transactions = entry.value.transactions
              .sublist(entry.value.transactions.length - 5);
        }

        await _saveToFile();
        return;
      }
    }
  }

// دالة لحساب الرصيد من البداية (للتدقيق)
  Future<double> calculateSupplierBalanceFromHistory(
      String supplierName) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);

    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        double balance = 0.0;

        for (var transaction in entry.value.transactions) {
          switch (transaction.type) {
            case 'purchase_debt':
            case 'box_received':
              balance += transaction.amount;
              break;
            case 'box_paid':
            case 'receipt_payment':
            case 'receipt_load':
              balance -= transaction.amount;
              break;
          }
        }

        return balance;
      }
    }

    return 0.0;
  }

// دالة لتصحيح الرصيد يدوياً
  Future<void> correctSupplierBalance(
      String supplierName, double correctBalance) async {
    await _ensureInitialized();
    final normalizedSupplier = _normalizeSupplier(supplierName);

    for (var entry in _supplierMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedSupplier.toLowerCase()) {
        final double oldBalance = entry.value.balance;
        entry.value.balance = correctBalance;
        entry.value.isBalanceLocked = true;

        // تسجيل تصحيح
        entry.value.transactions.add(SupplierTransaction(
          type: 'balance_correction',
          amount: correctBalance - oldBalance,
          timestamp: DateTime.now(),
          reference: 'تصحيح رصيد',
        ));

        await _saveToFile();

        print(
            '✅ تم تصحيح رصيد ${entry.value.name} من $oldBalance إلى $correctBalance');
        return;
      }
    }
  }
}
