import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class CustomerData {
  String name;
  double balance;
  String mobile;
  bool isBalanceLocked; // قفل الرصيد بعد أول عملية أو إدخال أولي

  CustomerData({
    required this.name,
    this.balance = 0.0,
    this.mobile = '',
    this.isBalanceLocked = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'balance': balance,
        'mobile': mobile,
        'isBalanceLocked': isBalanceLocked,
      };

  factory CustomerData.fromJson(dynamic json) {
    if (json is String) {
      return CustomerData(name: json);
    }
    return CustomerData(
      name: json['name'] ?? '',
      balance: (json['balance'] ?? 0.0).toDouble(),
      mobile: json['mobile'] ?? '',
      isBalanceLocked: json['isBalanceLocked'] ?? false,
    );
  }
}

class CustomerIndexService {
  static final CustomerIndexService _instance =
      CustomerIndexService._internal();
  factory CustomerIndexService() => _instance;
  CustomerIndexService._internal();

  static const String _fileName = 'customer_index.json';
  Map<int, CustomerData> _customerMap = {};
  bool _isInitialized = false;
  int _nextId = 1;

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await _loadCustomers();
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

    final folderPath = '${directory!.path}/alhalmarket/CustomerIndex';
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return '$folderPath/$_fileName';
  }

  Future<void> _loadCustomers() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final Map<String, dynamic> jsonData = jsonDecode(jsonString);

        if (jsonData.containsKey('customers') &&
            jsonData.containsKey('nextId')) {
          final Map<String, dynamic> customersJson = jsonData['customers'];

          _customerMap.clear();
          customersJson.forEach((key, value) {
            _customerMap[int.parse(key)] = CustomerData.fromJson(value);
          });

          _nextId = jsonData['nextId'] ?? 1;
        } else {
          _customerMap.clear();
          if (jsonData is List) {
            for (int i = 0; i < jsonData.length; i++) {
              _customerMap[i + 1] = CustomerData(name: jsonData[i].toString());
            }
            _nextId = jsonData.length + 1;
          } else if (jsonData.containsKey('customers')) {
            final List<dynamic> jsonList = jsonData['customers'];
            for (int i = 0; i < jsonList.length; i++) {
              _customerMap[i + 1] = CustomerData(name: jsonList[i].toString());
            }
            _nextId = jsonList.length + 1;
          }
          await _saveToFile();
        }
      } else {
        _customerMap.clear();
        _nextId = 1;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ خطأ في تحميل فهرس الزبائن: $e');
      }
      _customerMap.clear();
      _nextId = 1;
    }
  }

  Future<void> saveCustomer(String customer) async {
    await _ensureInitialized();
    if (customer.trim().isEmpty) return;
    final normalizedCustomer = _normalizeCustomer(customer);

    if (!_customerMap.values
        .any((c) => c.name.toLowerCase() == normalizedCustomer.toLowerCase())) {
      _customerMap[_nextId] = CustomerData(name: normalizedCustomer);
      _nextId++;
      await _saveToFile();
    }
  }

  String _normalizeCustomer(String customer) {
    String normalized = customer.trim();
    if (normalized.isNotEmpty) {
      normalized = normalized[0].toUpperCase() + normalized.substring(1);
    }
    return normalized;
  }

  Future<List<String>> getSuggestions(String query) async {
    await _ensureInitialized();
    if (query.isEmpty) return [];
    final normalizedQuery = query.toLowerCase().trim();
    return _customerMap.entries
        .where(
            (entry) => entry.value.name.toLowerCase().contains(normalizedQuery))
        .map((entry) => entry.value.name)
        .toList();
  }

  Future<List<String>> getEnhancedSuggestions(String query) async {
    await _ensureInitialized();
    if (query.isEmpty) return [];
    final normalizedQuery = query.trim();
    if (RegExp(r'^\d+$').hasMatch(normalizedQuery)) {
      final int? queryNumber = int.tryParse(normalizedQuery);
      if (queryNumber != null && _customerMap.containsKey(queryNumber)) {
        return [_customerMap[queryNumber]!.name];
      }
    }
    return await getSuggestions(normalizedQuery);
  }

  Future<List<String>> getAllCustomers() async {
    await _ensureInitialized();
    final customers = _customerMap.values.map((c) => c.name).toList();
    customers.sort((a, b) => a.compareTo(b));
    return customers;
  }

  Future<int?> getCustomerPosition(String customer) async {
    await _ensureInitialized();
    final normalizedCustomer = _normalizeCustomer(customer);
    for (var entry in _customerMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedCustomer.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> updateCustomerBalance(String customerName, double amount) async {
    await _ensureInitialized();
    final normalizedCustomer = _normalizeCustomer(customerName);
    for (var entry in _customerMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedCustomer.toLowerCase()) {
        entry.value.balance += amount;
        entry.value.isBalanceLocked = true; // قفل الرصيد بعد أول عملية حسابية
        await _saveToFile();
        return;
      }
    }
  }

  Future<void> setInitialBalance(String customerName, double balance) async {
    await _ensureInitialized();
    final normalizedCustomer = _normalizeCustomer(customerName);
    for (var entry in _customerMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedCustomer.toLowerCase()) {
        if (!entry.value.isBalanceLocked) {
          entry.value.balance = balance;
          await _saveToFile();
        }
        return;
      }
    }
  }

  Future<void> updateCustomerMobile(String customerName, String mobile) async {
    await _ensureInitialized();
    final normalizedCustomer = _normalizeCustomer(customerName);
    for (var entry in _customerMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedCustomer.toLowerCase()) {
        entry.value.mobile = mobile;
        await _saveToFile();
        return;
      }
    }
  }

  Future<void> updateCustomerName(int id, String newName) async {
    await _ensureInitialized();
    if (_customerMap.containsKey(id)) {
      _customerMap[id]!.name = _normalizeCustomer(newName);
      await _saveToFile();
    }
  }

  Future<void> removeCustomer(String customer) async {
    await _ensureInitialized();
    final normalizedCustomer = _normalizeCustomer(customer);
    int? keyToRemove;
    for (var entry in _customerMap.entries) {
      if (entry.value.name.toLowerCase() == normalizedCustomer.toLowerCase()) {
        keyToRemove = entry.key;
        break;
      }
    }
    if (keyToRemove != null) {
      _customerMap.remove(keyToRemove);
      await _saveToFile();
    }
  }

  Future<void> _saveToFile() async {
    try {
      final filePath = await _getFilePath();
      final file = File(filePath);
      final Map<String, dynamic> customersJson = {};
      _customerMap.forEach((key, value) {
        customersJson[key.toString()] = value.toJson();
      });
      final Map<String, dynamic> jsonData = {
        'customers': customersJson,
        'nextId': _nextId,
      };
      await file.writeAsString(jsonEncode(jsonData));
    } catch (e) {
      if (kDebugMode) debugPrint('❌ خطأ في حفظ فهرس الزبائن: $e');
    }
  }

  Future<Map<int, CustomerData>> getAllCustomersWithData() async {
    await _ensureInitialized();
    return Map.from(_customerMap);
  }

  // توافق مع الكود القديم
  Future<Map<int, String>> getAllCustomersWithNumbers() async {
    await _ensureInitialized();
    return _customerMap.map((key, value) => MapEntry(key, value.name));
  }
}
