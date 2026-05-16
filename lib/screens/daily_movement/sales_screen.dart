import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/sales_model.dart';
import '../../services/sales_storage_service.dart';
// استيراد خدمات الفهرس
import '../../services/material_index_service.dart';
import '../../services/packaging_index_service.dart';
import '../../services/supplier_index_service.dart';
import '../../services/customer_index_service.dart';
import '../../widgets/table_builder.dart' as TableBuilder;
import '../../widgets/table_components.dart' as TableComponents;
import '../../widgets/common_dialogs.dart' as CommonDialogs;
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../widgets/suggestions_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../widgets/exit_button.dart';
import '../../widgets/pdf_action_menu.dart';

class SalesScreen extends StatefulWidget {
  final String sellerName;
  final String selectedDate;
  final String storeName;

  const SalesScreen({
    Key? key,
    required this.sellerName,
    required this.selectedDate,
    required this.storeName,
  }) : super(key: key);

  @override
  _SalesScreenState createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  // خدمة التخزين
  final SalesStorageService _storageService = SalesStorageService();

  // خدمات الفهرس
  final MaterialIndexService _materialIndexService = MaterialIndexService();
  final PackagingIndexService _packagingIndexService = PackagingIndexService();
  final SupplierIndexService _supplierIndexService = SupplierIndexService();
  final CustomerIndexService _customerIndexService = CustomerIndexService();
  // بيانات الحقول
  String dayName = '';

  // قائمة لتخزين صفوف الجدول
  List<List<TextEditingController>> rowControllers = [];
  List<List<FocusNode>> rowFocusNodes = [];
  List<String> cashOrDebtValues = [];
  List<String> emptiesValues = [];
  List<String> customerNames = [];
  List<String> sellerNames = []; // <-- تخزين اسم البائع لكل صف

  // متحكمات صف المجموع
  late TextEditingController totalCountController;
  late TextEditingController totalBaseController;
  late TextEditingController totalNetController;
  late TextEditingController totalGrandController;

  // قوائم الخيارات
  final List<String> cashOrDebtOptions = ['نقدي', 'دين'];
  final List<String> emptiesOptions = ['مع فوارغ', 'بدون فوارغ'];

  // متحكمات للتمرير
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final _scrollController = ScrollController(); // للتمرير
  // حالة الحفظ
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  // التواريخ المتاحة
  List<Map<String, String>> _availableRecords = [];
  bool _isLoadingRecords = false;

  String serialNumber = '';

  // متغيرات للاقتراحات
  List<String> _materialSuggestions = [];
  List<String> _packagingSuggestions = [];
  List<String> _supplierSuggestions = [];
  List<String> _customerSuggestions = [];

  List<SuggestionItem> _materialSuggestionItems = [];
  List<SuggestionItem> _packagingSuggestionItems = [];
  List<SuggestionItem> _supplierSuggestionItems = [];
  List<SuggestionItem> _customerSuggestionItems = [];

  // مؤشرات الصفوف النشطة للاقتراحات
  int? _activeMaterialRowIndex;
  int? _activePackagingRowIndex;
  int? _activeSupplierRowIndex;
  int? _activeCustomerRowIndex;
  // متغير لتتبع ما إذا كان يجب عرض الاقتراحات على كامل الشاشة
  bool _showFullScreenSuggestions = false;
  String _currentSuggestionType = '';

  late ScrollController _horizontalSuggestionsController;
  bool _isAdmin = false;

  double _grandTotal = 0.0;
  FocusNode? _addButtonFocusNode;
  int _currentFocusRow = -1;
  int _currentFocusCol = -1;

  @override
  void initState() {
    super.initState();

    dayName = _extractDayName(widget.selectedDate);

    totalCountController = TextEditingController();
    totalBaseController = TextEditingController();
    totalNetController = TextEditingController();
    totalGrandController = TextEditingController();

    _resetTotalValues();

    _horizontalSuggestionsController = ScrollController();

    _verticalScrollController.addListener(() {
      _hideAllSuggestionsImmediately();
    });

    _horizontalScrollController.addListener(() {
      _hideAllSuggestionsImmediately();
    });

    _addButtonFocusNode = FocusNode(); // <-- إضافة

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdminStatus();
      _loadOrCreateRecord();
      _loadAvailableDates();
      _loadJournalNumber();
    });
  }

  @override
  void dispose() {
    _saveCurrentRecord(silent: true);

    for (var row in rowControllers) {
      for (var controller in row) {
        controller.dispose();
      }
    }

    for (var row in rowFocusNodes) {
      for (var node in row) {
        node.dispose();
      }
    }

    totalCountController.dispose();
    totalBaseController.dispose();
    totalNetController.dispose();
    totalGrandController.dispose();

    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _scrollController.dispose();

    _horizontalSuggestionsController.dispose();
    _addButtonFocusNode?.dispose(); // <-- إضافة

    super.dispose();
  }

  String _extractDayName(String dateString) {
    final days = [
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
    ];
    final now = DateTime.now();
    return days[now.weekday % 7];
  }

  // تحميل السجل إذا كان موجوداً، أو إنشاء جديد
  Future<void> _loadOrCreateRecord() async {
    final document = await _storageService.loadSalesDocument(
      widget.selectedDate,
    );

    if (document != null && document.sales.isNotEmpty) {
      // تحميل اليومية الموجودة
      _loadDocument(document);
    } else {
      // إنشاء يومية جديدة
      _createNewRecord();
    }
  }

  void _createNewRecord() {
    setState(() {
      serialNumber = '1';

      rowControllers.clear();
      rowFocusNodes.clear();
      cashOrDebtValues.clear();
      emptiesValues.clear();
      customerNames.clear();
      sellerNames.clear();
      _resetTotalValues();
      _hasUnsavedChanges = false;
      _addNewRow();
    });

    // طلب التركيز على زر الإضافة بعد إنشاء اليومية الجديدة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addButtonFocusNode?.requestFocus(); // <-- إضافة
    });
  }

  void _resetTotalValues() {
    totalCountController.text = '0';
    totalBaseController.text = '0.00';
    totalNetController.text = '0.00';
    totalGrandController.text = '0.00';
  }

  void _addNewRow() {
    setState(() {
      final newSerialNumber = (rowControllers.length + 1).toString();

      List<TextEditingController> newControllers = List.generate(
        12,
        (index) => TextEditingController(),
      );

      List<FocusNode> newFocusNodes = List.generate(12, (index) => FocusNode());

      newControllers[0].text = newSerialNumber;

      // إضافة مستمعات للتغيير باستخدام دالة مساعدة
      _addChangeListenersToControllers(newControllers, rowControllers.length);

      // تخزين اسم البائع للصف الجديد
      sellerNames.add(widget.sellerName);

      rowControllers.add(newControllers);
      rowFocusNodes.add(newFocusNodes);
      cashOrDebtValues.add('');
      emptiesValues.add('');
      customerNames.add('');
    });

    // تركيز الماوس على حقل المادة في السجل الجديد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rowFocusNodes.isNotEmpty) {
        final newRowIndex = rowFocusNodes.length - 1;
        FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
      }
    });
  }

  // دالة مساعدة لإضافة المستمعات - مثل purchases_screen
  void _addChangeListenersToControllers(
    List<TextEditingController> controllers,
    int rowIndex,
  ) {
    // حقل المادة
    controllers[1].addListener(() {
      _hasUnsavedChanges = true;
      _updateMaterialSuggestions(rowIndex);
    });

    // حقل العائدية
    controllers[2].addListener(() {
      _hasUnsavedChanges = true;
      _updateSupplierSuggestions(rowIndex);
    });

    // حقل العبوة
    controllers[5].addListener(() {
      _hasUnsavedChanges = true;
      _updatePackagingSuggestions(rowIndex);
    });

    // حقل اسم الزبون
    controllers[10].addListener(() {
      _hasUnsavedChanges = true;
      _updateCustomerSuggestions(rowIndex);
    });

    // الحقول الرقمية مع التحديث التلقائي
    controllers[4].addListener(() {
      _hasUnsavedChanges = true;
      _calculateRowValues(rowIndex);
      _calculateAllTotals();
    });

    controllers[6].addListener(() {
      _hasUnsavedChanges = true;
      _validateStandingAndNet(rowIndex);
      _calculateRowValues(rowIndex);
      _calculateAllTotals();
    });

    controllers[7].addListener(() {
      _hasUnsavedChanges = true;
      _validateStandingAndNet(rowIndex);
      _calculateRowValues(rowIndex);
      _calculateAllTotals();
    });

    controllers[8].addListener(() {
      _hasUnsavedChanges = true;
      _calculateRowValues(rowIndex);
      _calculateAllTotals();
    });
  }

  // تحديث اقتراحات المادة
  void _updateMaterialSuggestions(int rowIndex) async {
    final query = rowControllers[rowIndex][1].text;
    if (query.length >= 1) {
      final allWithNumbers =
          await _materialIndexService.getAllMaterialsWithNumbers();
      final normalizedQuery = query.toLowerCase().trim();

      List<SuggestionItem> displaySuggestions = [];

      if (RegExp(r'^\d+$').hasMatch(query.trim())) {
        final int? queryNumber = int.tryParse(query.trim());
        if (queryNumber != null && allWithNumbers.containsKey(queryNumber)) {
          displaySuggestions = [
            SuggestionItem(
                number: queryNumber, name: allWithNumbers[queryNumber]!)
          ];
        }
      } else {
        displaySuggestions = allWithNumbers.entries
            .where((e) => e.value.toLowerCase().contains(normalizedQuery))
            .map((e) => SuggestionItem(number: e.key, name: e.value))
            .toList();
      }

      if (mounted) {
        setState(() {
          _materialSuggestionItems = displaySuggestions;
          _materialSuggestions =
              displaySuggestions.map((e) => e.displayName).toList();
          _activeMaterialRowIndex = rowIndex;
          _toggleFullScreenSuggestions(
              type: 'material', show: displaySuggestions.isNotEmpty);
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _materialSuggestions = [];
          _materialSuggestionItems = [];
          _activeMaterialRowIndex = null;
          _toggleFullScreenSuggestions(type: 'material', show: false);
        });
      }
    }
  }

  // تحديث اقتراحات العبوة
  void _updatePackagingSuggestions(int rowIndex) async {
    final query = rowControllers[rowIndex][5].text;
    if (query.length >= 1) {
      final allWithNumbers =
          await _packagingIndexService.getAllPackagingsWithNumbers();
      final normalizedQuery = query.toLowerCase().trim();

      List<SuggestionItem> displaySuggestions = [];

      if (RegExp(r'^\d+$').hasMatch(query.trim())) {
        final int? queryNumber = int.tryParse(query.trim());
        if (queryNumber != null && allWithNumbers.containsKey(queryNumber)) {
          displaySuggestions = [
            SuggestionItem(
                number: queryNumber, name: allWithNumbers[queryNumber]!)
          ];
        }
      } else {
        displaySuggestions = allWithNumbers.entries
            .where((e) => e.value.toLowerCase().contains(normalizedQuery))
            .map((e) => SuggestionItem(number: e.key, name: e.value))
            .toList();
      }

      if (mounted) {
        setState(() {
          _packagingSuggestionItems = displaySuggestions;
          _packagingSuggestions =
              displaySuggestions.map((e) => e.displayName).toList();
          _activePackagingRowIndex = rowIndex;
          _toggleFullScreenSuggestions(
              type: 'packaging', show: displaySuggestions.isNotEmpty);
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _packagingSuggestions = [];
          _packagingSuggestionItems = [];
          _activePackagingRowIndex = null;
          _toggleFullScreenSuggestions(type: 'packaging', show: false);
        });
      }
    }
  }

  // تحديث اقتراحات الموردين (العائدية)
  void _updateSupplierSuggestions(int rowIndex) async {
    final query = rowControllers[rowIndex][2].text;
    if (query.length >= 1) {
      final allWithNumbers =
          await _supplierIndexService.getAllSuppliersWithNumbers();
      final normalizedQuery = query.toLowerCase().trim();

      List<SuggestionItem> displaySuggestions = [];

      if (RegExp(r'^\d+$').hasMatch(query.trim())) {
        final int? queryNumber = int.tryParse(query.trim());
        if (queryNumber != null && allWithNumbers.containsKey(queryNumber)) {
          displaySuggestions = [
            SuggestionItem(
                number: queryNumber, name: allWithNumbers[queryNumber]!)
          ];
        }
      } else {
        displaySuggestions = allWithNumbers.entries
            .where((e) => e.value.toLowerCase().contains(normalizedQuery))
            .map((e) => SuggestionItem(number: e.key, name: e.value))
            .toList();
      }

      if (mounted) {
        setState(() {
          _supplierSuggestionItems = displaySuggestions;
          _supplierSuggestions =
              displaySuggestions.map((e) => e.displayName).toList();
          _activeSupplierRowIndex = rowIndex;
          _toggleFullScreenSuggestions(
              type: 'supplier', show: displaySuggestions.isNotEmpty);
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _supplierSuggestions = [];
          _supplierSuggestionItems = [];
          _activeSupplierRowIndex = null;
          _toggleFullScreenSuggestions(type: 'supplier', show: false);
        });
      }
    }
  }

  // تحديث اقتراحات الزبائن
  void _updateCustomerSuggestions(int rowIndex) async {
    if (rowControllers[rowIndex].length <= 10) return;
    final query = rowControllers[rowIndex][10].text;
    if (query.length >= 1 && cashOrDebtValues[rowIndex] == 'دين') {
      final allWithNumbers =
          await _customerIndexService.getAllCustomersWithNumbers();
      final normalizedQuery = query.toLowerCase().trim();

      List<SuggestionItem> displaySuggestions = [];

      if (RegExp(r'^\d+$').hasMatch(query.trim())) {
        final int? queryNumber = int.tryParse(query.trim());
        if (queryNumber != null && allWithNumbers.containsKey(queryNumber)) {
          displaySuggestions = [
            SuggestionItem(
                number: queryNumber, name: allWithNumbers[queryNumber]!)
          ];
        }
      } else {
        displaySuggestions = allWithNumbers.entries
            .where((e) => e.value.toLowerCase().contains(normalizedQuery))
            .map((e) => SuggestionItem(number: e.key, name: e.value))
            .toList();
      }

      if (mounted) {
        setState(() {
          _customerSuggestionItems = displaySuggestions;
          _customerSuggestions =
              displaySuggestions.map((e) => e.displayName).toList();
          _activeCustomerRowIndex = rowIndex;
          _toggleFullScreenSuggestions(
              type: 'customer', show: displaySuggestions.isNotEmpty);
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _customerSuggestions = [];
          _customerSuggestionItems = [];
          _activeCustomerRowIndex = null;
          _toggleFullScreenSuggestions(type: 'customer', show: false);
        });
      }
    }
  }

  // 1. اختيار اقتراح للمادة
  void _selectMaterialSuggestion(String suggestion, int rowIndex) {
    if (rowIndex >= rowControllers.length) return;
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][1].text = actualName;
    _hasUnsavedChanges = true;
    if (actualName.trim().length > 1) {
      _saveMaterialToIndex(actualName);
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && rowIndex < rowFocusNodes.length) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][2]);
      }
    });
  }

  // 2. اختيار اقتراح للعبوة
  void _selectPackagingSuggestion(String suggestion, int rowIndex) {
    if (rowIndex >= rowControllers.length) return;
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][5].text = actualName;
    _hasUnsavedChanges = true;
    if (actualName.trim().length > 1) {
      _savePackagingToIndex(actualName);
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && rowIndex < rowFocusNodes.length) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][6]);
      }
    });
  }

  // 3. اختيار اقتراح للمورد (العائدية)
  void _selectSupplierSuggestion(String suggestion, int rowIndex) {
    if (rowIndex >= rowControllers.length) return;
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][2].text = actualName;
    _hasUnsavedChanges = true;
    if (actualName.trim().length > 1) {
      _saveSupplierToIndex(actualName);
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && rowIndex < rowFocusNodes.length) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][3]);
      }
    });
  }

  // 4. اختيار اقتراح للزبون
  void _selectCustomerSuggestion(String suggestion, int rowIndex) {
    if (rowIndex >= rowControllers.length) return;
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][10].text = actualName;
    setState(() {
      customerNames[rowIndex] = actualName;
      _hasUnsavedChanges = true;
    });
    if (actualName.trim().length > 1) {
      _saveCustomerToIndex(actualName);
    }
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _showEmptiesDialog(rowIndex);
      }
    });
  }

  // حفظ المادة في الفهرس
  void _saveMaterialToIndex(String material) {
    final trimmedMaterial = material.trim();
    if (trimmedMaterial.length > 1) {
      _materialIndexService.saveMaterial(trimmedMaterial);
    }
  }

  // حفظ العبوة في الفهرس
  void _savePackagingToIndex(String packaging) {
    final trimmedPackaging = packaging.trim();
    if (trimmedPackaging.length > 1) {
      _packagingIndexService.savePackaging(trimmedPackaging);
    }
  }

  // حفظ المورد في الفهرس
  void _saveSupplierToIndex(String supplier) {
    final trimmedSupplier = supplier.trim();
    if (trimmedSupplier.length > 1) {
      _supplierIndexService.saveSupplier(trimmedSupplier);
    }
  }

  // تعديل _validateStandingAndNet
  void _validateStandingAndNet(int rowIndex) {
    if (rowIndex >= rowControllers.length) return;

    final controllers = rowControllers[rowIndex];

    try {
      double standing = double.tryParse(controllers[6].text) ?? 0;
      double net = double.tryParse(controllers[7].text) ?? 0;

      if (standing < net) {
        controllers[7].text = standing.toStringAsFixed(2);
        _showInlineWarning(rowIndex, 'الصافي لا يمكن أن يكون أكبر من القائم');

        _calculateRowValues(rowIndex);
        _calculateAllTotals();
      } else if (standing == 0 && net > 0) {
        controllers[7].text = '0.00';
        _showInlineWarning(
          rowIndex,
          'إذا كان القائم صفر، يجب أن يكون الصافي صفر',
        );

        _calculateRowValues(rowIndex);
        _calculateAllTotals();
      }
    } catch (e) {
      // تجاهل الأخطاء في التحليل
    }
  }

  // تحسين _calculateRowValues
  void _calculateRowValues(int rowIndex) {
    if (rowIndex >= rowControllers.length) return;

    final controllers = rowControllers[rowIndex];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          try {
            double count = (double.tryParse(controllers[4].text) ?? 0).abs();
            double net = (double.tryParse(controllers[7].text) ?? 0).abs();
            double price = (double.tryParse(controllers[8].text) ?? 0).abs();

            double baseValue = net > 0 ? net : count;
            double total = baseValue * price;
            controllers[9].text = total.toStringAsFixed(2);
          } catch (e) {
            controllers[9].text = '';
          }
        });
      }
    });
  }

  // تحسين _calculateAllTotals
  void _calculateAllTotals() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          double totalCount = 0;
          double totalBase = 0;
          double totalNet = 0;
          double totalGrand = 0;

          for (var controllers in rowControllers) {
            try {
              totalCount += double.tryParse(controllers[4].text) ?? 0;
              totalBase += double.tryParse(controllers[6].text) ?? 0;
              totalNet += double.tryParse(controllers[7].text) ?? 0;
              totalGrand += double.tryParse(controllers[9].text) ?? 0;
            } catch (e) {
              // تجاهل الأخطاء
            }
          }

          totalCountController.text = totalCount.toStringAsFixed(0);
          totalBaseController.text = totalBase.toStringAsFixed(2);
          totalNetController.text = totalNet.toStringAsFixed(2);
          totalGrandController.text = totalGrand.toStringAsFixed(2);
        });
      }
    });
  }

  void _loadDocument(SalesDocument document) {
    setState(() {
      for (var row in rowControllers) {
        for (var controller in row) {
          controller.dispose();
        }
      }
      for (var row in rowFocusNodes) {
        for (var node in row) {
          node.dispose();
        }
      }

      rowControllers.clear();
      rowFocusNodes.clear();
      cashOrDebtValues.clear();
      emptiesValues.clear();
      customerNames.clear();
      sellerNames.clear();

      serialNumber = document.recordNumber;

      for (int i = 0; i < document.sales.length; i++) {
        var sale = document.sales[i];

        List<TextEditingController> newControllers = [
          TextEditingController(text: sale.serialNumber),
          TextEditingController(text: sale.material),
          TextEditingController(text: sale.affiliation),
          TextEditingController(text: sale.sValue),
          TextEditingController(text: sale.count),
          TextEditingController(text: sale.packaging),
          TextEditingController(text: sale.standing),
          TextEditingController(text: sale.net),
          TextEditingController(text: sale.price),
          TextEditingController(text: sale.total),
          TextEditingController(text: sale.customerName ?? ''),
          TextEditingController(),
        ];

        List<FocusNode> newFocusNodes = List.generate(
          12,
          (index) => FocusNode(),
        );

        sellerNames.add(sale.sellerName);

        final bool isOwnedByCurrentSeller =
            sale.sellerName == widget.sellerName;

        if (isOwnedByCurrentSeller) {
          _addChangeListenersToControllers(newControllers, i);
        }

        rowControllers.add(newControllers);
        rowFocusNodes.add(newFocusNodes);
        cashOrDebtValues.add(sale.cashOrDebt);
        emptiesValues.add(sale.empties);
        customerNames.add(sale.customerName ?? '');
      }

      // ربط مستمعات التركيز لكل الصفوف المحملة
      for (int i = 0; i < rowFocusNodes.length; i++) {
        _attachFocusListeners(i); // <-- إضافة
      }

      if (document.totals.isNotEmpty) {
        totalCountController.text = document.totals['totalCount'] ?? '0';
        totalBaseController.text = document.totals['totalBase'] ?? '0.00';
        totalNetController.text = document.totals['totalNet'] ?? '0.00';
        totalGrandController.text = document.totals['totalGrand'] ?? '0.00';
      }

      _hasUnsavedChanges = false;
    });
  }

  void _scrollToField(int rowIndex, int colIndex) {
    const double headerHeight = 32.0;
    const double rowHeight = 25.0;
    final double verticalPosition = (rowIndex * rowHeight);
    final double verticalTarget = (verticalPosition + headerHeight)
        .clamp(0, _verticalScrollController.position.maxScrollExtent);

    const double columnWidth = 80.0;
    final double horizontalPosition = colIndex * columnWidth;
    final double horizontalTarget = horizontalPosition.clamp(
        0, _horizontalScrollController.position.maxScrollExtent);

    _verticalScrollController.animateTo(
      verticalTarget,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );

    _horizontalScrollController.animateTo(
      horizontalTarget,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildTableHeader() {
    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      columnWidths: {
        3: const FixedColumnWidth(30.0),
        10: const FlexColumnWidth(1.5),
      },
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            TableComponents.buildTableHeaderCell('مسلسل'),
            TableComponents.buildTableHeaderCell('المادة'),
            TableComponents.buildTableHeaderCell('العائدية'),
            TableComponents.buildTableHeaderCell('س'),
            TableComponents.buildTableHeaderCell('العدد'),
            TableComponents.buildTableHeaderCell('العبوة'),
            TableComponents.buildTableHeaderCell('القائم'),
            TableComponents.buildTableHeaderCell('الصافي'),
            TableComponents.buildTableHeaderCell('السعر'),
            TableComponents.buildTableHeaderCell('الإجمالي'),
            TableComponents.buildTableHeaderCell('نقدي او دين'),
            TableComponents.buildTableHeaderCell('الفوارغ'),
          ],
        ),
      ],
    );
  }

  Widget _buildTableContent() {
    List<TableRow> contentRows = [];

    for (int i = 0; i < rowControllers.length; i++) {
      // التحقق إذا كان السجل مملوكاً للبائع الحالي
      final bool isOwnedByCurrentSeller = sellerNames[i] == widget.sellerName;

      contentRows.add(
        TableRow(
          children: [
            _buildTableCell(
              rowControllers[i][0],
              rowFocusNodes[i][0],
              i,
              0,
              isOwnedByCurrentSeller,
            ),
            _buildMaterialCell(
              rowControllers[i][1],
              rowFocusNodes[i][1],
              i,
              1,
              isOwnedByCurrentSeller,
            ),
            _buildSupplierCell(
              rowControllers[i][2],
              rowFocusNodes[i][2],
              i,
              2,
              isOwnedByCurrentSeller,
            ),
            _buildTableCell(
              rowControllers[i][3],
              rowFocusNodes[i][3],
              i,
              3,
              isOwnedByCurrentSeller,
              isSField: true,
            ),
            _buildTableCell(
              rowControllers[i][4],
              rowFocusNodes[i][4],
              i,
              4,
              isOwnedByCurrentSeller,
            ),
            _buildPackagingCell(
              rowControllers[i][5],
              rowFocusNodes[i][5],
              i,
              5,
              isOwnedByCurrentSeller,
            ),
            _buildTableCell(
              rowControllers[i][6],
              rowFocusNodes[i][6],
              i,
              6,
              isOwnedByCurrentSeller,
            ),
            _buildTableCell(
              rowControllers[i][7],
              rowFocusNodes[i][7],
              i,
              7,
              isOwnedByCurrentSeller,
            ),
            _buildTableCell(
              rowControllers[i][8],
              rowFocusNodes[i][8],
              i,
              8,
              isOwnedByCurrentSeller,
            ),
            TableComponents.buildTotalValueCell(rowControllers[i][9]),
            _buildCashOrDebtCell(i, 10, isOwnedByCurrentSeller),
            _buildEmptiesCell(i, 11, isOwnedByCurrentSeller),
          ],
        ),
      );
    }

    if (rowControllers.length >= 2) {
      contentRows.add(
        TableRow(
          decoration: BoxDecoration(color: Colors.yellow[50]),
          children: [
            _buildEmptyCell(),
            _buildEmptyCell(),
            _buildEmptyCell(),
            _buildEmptyCell(),
            TableComponents.buildTotalCell(totalCountController),
            _buildEmptyCell(),
            TableComponents.buildTotalCell(totalBaseController),
            TableComponents.buildTotalCell(totalNetController),
            _buildEmptyCell(),
            TableComponents.buildTotalCell(totalGrandController),
            _buildEmptyCell(),
            _buildEmptyCell(),
          ],
        ),
      );
    }

    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      columnWidths: {
        3: const FixedColumnWidth(30.0),
        10: const FlexColumnWidth(1.5),
      },
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: contentRows,
    );
  }

  Widget _buildTableCell(
    TextEditingController controller,
    FocusNode focusNode,
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller, {
    bool isSField = false,
  }) {
    final bool enabled = _canEditRow(rowIndex);
    bool isSerialField = colIndex == 0;
    bool isNumericField =
        colIndex == 4 || colIndex == 6 || colIndex == 7 || colIndex == 8;

    Widget cell = TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled, // <--- تمرير القيمة هنا لتعطيل الـ TextField
      isSerialField: isSerialField,
      isNumericField: isNumericField,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
      isSField: isSField,
      inputFormatters: isSField
          ? [
              TableComponents.TwoDigitInputFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ]
          : (isNumericField
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  FilteringTextInputFormatter.deny(RegExp(r'\.\d{3,}')),
                ]
              : null),
      // ============> [تعديل] زيادة حجم الخط ليطابق الشاشات القديمة <============
      fontSize: isSField ? 11 : 16, // تم التغيير من 13 إلى 16
      // ============> [تعديل] جعل النص في المنتصف واتجاهه افتراضيًا <============
      textAlign: TextAlign
          .center, // تم التغيير من (isSField ? TextAlign.center : TextAlign.right)
      textDirection: TextDirection
          .ltr, // تم التغيير من (isSField ? TextDirection.ltr : TextDirection.rtl) لجعله دائمًا في المنتصف
    );

    // إذا لم يكن السجل مملوكاً للبائع الحالي، جعل الخلية للقراءة فقط
    if (!_canEditRow(rowIndex)) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0.7,
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[100]),
            child: cell,
          ),
        ),
      );
    }

    return cell;
  }

  Widget _buildMaterialCell(
    TextEditingController controller,
    FocusNode focusNode,
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller,
  ) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
      // ============> [تعديل] زيادة حجم الخط ليطابق الشاشات القديمة <============
      fontSize: 16, // تمت إضافة هذا السطر بقيمة 16
      // ============> [تعديل] جعل النص في المنتصف واتجاهه افتراضيًا <============
      textAlign: TextAlign.center, // تمت إضافة هذا السطر
      textDirection: TextDirection.ltr, // تمت إضافة هذا السطر
    );
  }

  Widget _buildPackagingCell(
    TextEditingController controller,
    FocusNode focusNode,
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller,
  ) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
      // ============> [تعديل] زيادة حجم الخط ليطابق الشاشات القديمة <============
      fontSize: 16, // تمت إضافة هذا السطر بقيمة 16
      // ============> [تعديل] جعل النص في المنتصف واتجاهه افتراضيًا <============
      textAlign: TextAlign.center, // تمت إضافة هذا السطر
      textDirection: TextDirection.ltr, // تمت إضافة هذا السطر
    );
  }

  Widget _buildSupplierCell(
    TextEditingController controller,
    FocusNode focusNode,
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller,
  ) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
      // ============> [تعديل] زيادة حجم الخط ليطابق الشاشات القديمة <============
      fontSize: 16, // تمت إضافة هذا السطر بقيمة 16
      // ============> [تعديل] جعل النص في المنتصف واتجاهه افتراضيًا <============
      textAlign: TextAlign.center, // تمت إضافة هذا السطر
      textDirection: TextDirection.ltr, // تمت إضافة هذا السطر
    );
  }

  void _handleFieldSubmitted(String value, int rowIndex, int colIndex) {
    if (!_canEditRow(rowIndex)) return;

    if (colIndex == 1) {
      if (_materialSuggestions.isNotEmpty) {
        _selectMaterialSuggestion(_materialSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _saveMaterialToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][2]);
    } else if (colIndex == 2) {
      if (_supplierSuggestions.isNotEmpty) {
        _selectSupplierSuggestion(_supplierSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _saveSupplierToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][3]);
    } else if (colIndex == 5) {
      if (_packagingSuggestions.isNotEmpty) {
        _selectPackagingSuggestion(_packagingSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _savePackagingToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][6]);
    } else if (colIndex == 10) {
      // تم الإبقاء على منطق الزبون كما هو لأنه يعمل بشكل صحيح لديك
      if (cashOrDebtValues[rowIndex] == 'دين' &&
          _customerSuggestions.isNotEmpty) {
        _selectCustomerSuggestion(_customerSuggestions[0], rowIndex);
        return;
      }
      if (cashOrDebtValues[rowIndex] == 'دين') {
        if (value.trim().length > 1) _saveCustomerToIndex(value.trim());
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) _showEmptiesDialog(rowIndex);
        });
        return;
      }
      if (cashOrDebtValues[rowIndex] == 'نقدي') {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted) _showEmptiesDialog(rowIndex);
        });
        return;
      }
    } else if (colIndex == 0) {
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][1]);
    } else if (colIndex == 8) {
      _showCashOrDebtDialog(rowIndex);
    } else if (colIndex == 11) {
      _addNewRow();
      if (rowControllers.isNotEmpty) {
        final newRowIndex = rowControllers.length - 1;
        FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
      }
    } else if (colIndex < 11) {
      FocusScope.of(
        context,
      ).requestFocus(rowFocusNodes[rowIndex][colIndex + 1]);
    }

    _hideAllSuggestionsImmediately();
  }

  void _handleFieldChanged(String value, int rowIndex, int colIndex) {
    // التحقق إذا كان السجل مملوكاً للبائع الحالي
    if (!_canEditRow(rowIndex)) {
      return;
    }

    setState(() {
      _hasUnsavedChanges = true;

      if (colIndex == 0) {
        for (int i = 0; i < rowControllers.length; i++) {
          rowControllers[i][0].text = (i + 1).toString();
        }
      }

      // إذا بدأ المستخدم بالكتابة في حقل آخر، إخفاء اقتراحات الحقول الأخرى
      if (colIndex == 1 && _activeMaterialRowIndex != rowIndex) {
        _clearAllSuggestions();
      } else if (colIndex == 2 && _activeSupplierRowIndex != rowIndex) {
        _clearAllSuggestions();
      } else if (colIndex == 5 && _activePackagingRowIndex != rowIndex) {
        _clearAllSuggestions();
      } else if (colIndex == 10 && _activeCustomerRowIndex != rowIndex) {
        _clearAllSuggestions();
      }
    });
  }

  Widget _buildEmptyCell() {
    return Container(
      padding: const EdgeInsets.all(1),
      constraints: const BoxConstraints(minHeight: 25),
      child: TextField(
        controller: TextEditingController()..text = '',
        focusNode: FocusNode(),
        enabled: false,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildCashOrDebtCell(
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller,
  ) {
    Widget cell = Stack(
      children: [
        TableBuilder.buildCashOrDebtCell(
          rowIndex: rowIndex,
          colIndex: colIndex,
          cashOrDebtValue: cashOrDebtValues[rowIndex],
          customerName: customerNames[rowIndex],
          customerController: rowControllers[rowIndex][10],
          focusNode: rowFocusNodes[rowIndex][colIndex],
          hasUnsavedChanges: _hasUnsavedChanges,
          setHasUnsavedChanges: (value) =>
              setState(() => _hasUnsavedChanges = value),
          onTap: () => _showCashOrDebtDialog(rowIndex),
          scrollToField: _scrollToField,
          onCustomerNameChanged: (value) {
            setState(() {
              customerNames[rowIndex] = value;
              _hasUnsavedChanges = true;
            });
            _updateCustomerSuggestions(rowIndex);
          },
          onCustomerSubmitted: (value, rIndex, cIndex) {
            _handleFieldSubmitted(value, rIndex, cIndex);
          },
          isSalesScreen: true,
        ),
      ],
    );
    if (!isOwnedByCurrentSeller) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0.7,
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[100]),
            child: cell,
          ),
        ),
      );
    }

    return cell;
  }
  // بناء قائمة اقتراحات الزبائن بشكل أفقي - مثل purchases_screen بالضبط

  Widget _buildEmptiesCell(
    int rowIndex,
    int colIndex,
    bool isOwnedByCurrentSeller,
  ) {
    Widget cell = TableComponents.buildEmptiesCell(
      value: emptiesValues[rowIndex],
      onTap: () => _showEmptiesDialog(rowIndex),
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
    );

    // إذا لم يكن السجل مملوكاً للبائع الحالي، جعل الخلية للقراءة فقط
    if (!isOwnedByCurrentSeller) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0.7,
          child: Container(
            decoration: BoxDecoration(color: Colors.grey[100]),
            child: cell,
          ),
        ),
      );
    }

    return cell;
  }

  void _showCashOrDebtDialog(int rowIndex) {
    // التحقق إذا كان السجل مملوكاً للبائع الحالي
    if (!_canEditRow(rowIndex)) return; // منع الظهور تماماً

    CommonDialogs.showCashOrDebtDialog(
      context: context,
      currentValue: cashOrDebtValues[rowIndex],
      options: cashOrDebtOptions,
      onSelected: (value) {
        setState(() {
          cashOrDebtValues[rowIndex] = value;
          _hasUnsavedChanges = true;

          if (value == 'نقدي') {
            customerNames[rowIndex] = '';
            // فتح نافذة الفوارغ بعد تأخير بسيط
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _showEmptiesDialog(rowIndex);
              }
            });
          } else if (value == 'دين') {
            // تفريغ اسم الزبون القديم إذا كان موجوداً
            customerNames[rowIndex] = '';
            rowControllers[rowIndex][10].text = '';
            // تركيز الماوس على حقل اسم الزبون بعد تأخير بسيط
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && rowIndex < rowFocusNodes.length) {
                FocusScope.of(
                  context,
                ).requestFocus(rowFocusNodes[rowIndex][10]);
                // تحديث الاقتراحات
                _updateCustomerSuggestions(rowIndex);
              }
            });
          }
        });
      },
      onCancel: () {
        // إذا تم الإلغاء، نرجع التركيز لحقل السعر
        if (mounted && rowIndex < rowFocusNodes.length) {
          FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][8]);
        }
      },
    );
  }

  void _showEmptiesDialog(int rowIndex) {
    // التحقق إذا كان السجل مملوكاً للبائع الحالي
    if (!_canEditRow(rowIndex)) return; // منع الظهور تماماً
    CommonDialogs.showEmptiesDialog(
      context: context,
      currentValue: emptiesValues[rowIndex],
      options: emptiesOptions,
      onSelected: (value) {
        setState(() {
          emptiesValues[rowIndex] = value;
          _hasUnsavedChanges = true;
        });
        // إضافة صف جديد بعد اختيار الفوارغ
        _addRowAfterEmptiesSelection(rowIndex);
      },
      onCancel: () {
        // إذا تم الإلغاء، نرجع التركيز لحقل اسم الزبون
        if (cashOrDebtValues[rowIndex] == 'دین') {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted && rowIndex < rowFocusNodes.length) {
              FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][10]);
            }
          });
        }
      },
    );
  }

  void _addRowAfterEmptiesSelection(int rowIndex) {
    _addNewRow();
    if (rowControllers.isNotEmpty) {
      final newRowIndex = rowControllers.length - 1;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // التركيز على حقل المادة في السجل الجديد
          FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
          _scrollToField(newRowIndex, 1);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ExitButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Focus(
                  focusNode: _addButtonFocusNode, // <-- تغيير
                  child: SizedBox(
                    width: 140,
                    height: 80,
                    child: ElevatedButton(
                      onPressed: () {
                        _addNewRow();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (rowFocusNodes.isNotEmpty) {
                            final newRowIndex = rowFocusNodes.length - 1;
                            FocusScope.of(context)
                                .requestFocus(rowFocusNodes[newRowIndex][1]);
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 14, 82, 184),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 3,
                      ),
                      child: const Text(
                        'إضافة',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_showFullScreenSuggestions &&
                _getSuggestionsByType().isNotEmpty)
              Expanded(
                child: SuggestionsBanner(
                  suggestions: _getSuggestionsByType(),
                  type: _currentSuggestionType,
                  currentRowIndex: _getCurrentRowIndexByType(),
                  scrollController: _horizontalSuggestionsController,
                  onSelect: (val, idx) {
                    if (_currentSuggestionType == 'material')
                      _selectMaterialSuggestion(val, idx);
                    if (_currentSuggestionType == 'packaging')
                      _selectPackagingSuggestion(val, idx);
                    if (_currentSuggestionType == 'supplier')
                      _selectSupplierSuggestion(val, idx);
                    if (_currentSuggestionType == 'customer')
                      _selectCustomerSuggestion(val, idx);
                  },
                  onClose: () =>
                      _toggleFullScreenSuggestions(type: '', show: false),
                ),
              )
            else
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'يومية مبيعات رقم /$serialNumber/ تاريخ ${widget.selectedDate} البائع ${widget.sellerName}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.5),
                    ),
                    // الرصيد الكلي
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('الإجمالي الكلي: ',
                              style: TextStyle(
                                  fontSize: 16, color: Colors.white70)),
                          Text(
                            _grandTotal.toStringAsFixed(2),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.lightGreenAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.orange[700],
        foregroundColor: Colors.white,
        actions: [
          PdfActionMenu(
            type: 'sales',
            supplierOrCustomerName: 'المبيعات',
            filterDesc: widget.selectedDate,
            balance: null,
            storeName: widget.storeName,
            selectedDate: widget.selectedDate,
            iconSize: 60,
            getItems: () async => rowControllers,
            generatePdfCallback: (items) => _generatePdfBytes(items),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.calendar_month, size: 60),
            tooltip: 'فتح يومية سابقة',
            onSelected: (selectedDate) async {
              if (selectedDate != widget.selectedDate) {
                if (_hasUnsavedChanges) {
                  final shouldSave = await _showUnsavedChangesDialog();
                  if (shouldSave) {
                    await _saveCurrentRecord(silent: true);
                  }
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SalesScreen(
                      sellerName: widget.sellerName,
                      selectedDate: selectedDate,
                      storeName: widget.storeName,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) {
              List<PopupMenuEntry<String>> items = [];

              if (_isLoadingRecords) {
                items.add(
                  const PopupMenuItem<String>(
                    value: '',
                    enabled: false,
                    child: Center(child: Text('جاري التحميل...')),
                  ),
                );
              } else if (_availableRecords.isEmpty) {
                items.add(
                  const PopupMenuItem<String>(
                    value: '',
                    enabled: false,
                    child: Center(child: Text('لا توجد يوميات سابقة')),
                  ),
                );
              } else {
                items.add(
                  const PopupMenuItem<String>(
                    value: '',
                    enabled: false,
                    child: Text(
                      'اليوميات المتاحة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
                items.add(const PopupMenuDivider());

                for (var record in _availableRecords) {
                  final date = record['date']!;
                  final journalNumber = record['journalNumber']!;

                  items.add(
                    PopupMenuItem<String>(
                      value: date,
                      child: Text(
                        'يومية رقم $journalNumber - تاريخ $date',
                        style: TextStyle(
                          fontWeight: date == widget.selectedDate
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: date == widget.selectedDate
                              ? Colors.orange
                              : Colors.black,
                        ),
                      ),
                    ),
                  );
                }
              }

              return items;
            },
          ),
        ],
      ),
      body: RawKeyboardListener(
        focusNode: FocusNode(),
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              final focusedNode = FocusScope.of(context).focusedChild;
              if (focusedNode == null || focusedNode == _addButtonFocusNode) {
                // <-- تغيير
                _addNewRow();
              }
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              // <-- إضافة
              _moveFocus(0, -1);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              // <-- إضافة
              _moveFocus(0, 1);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              // <-- إضافة
              _moveFocus(1, 0);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              // <-- إضافة
              _moveFocus(-1, 0);
            }
          }
        },
        child: _buildMainContent(),
      ),
      resizeToAvoidBottomInset: true,
    );
  }

  Widget _buildMainContent() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: _buildTableWithStickyHeader(),
            ),
            const SizedBox(height: 90),
          ],
        ),
        if (rowControllers.length >= 1)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.orange[700],
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange[700]!.withOpacity(0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // المجموع
                    Expanded(
                      child: Center(
                        child: const Text(
                          'المجموع',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // العدد
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'العدد',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalCountController,
                            builder: (context, value, child) {
                              return Text(
                                value.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // العبوة — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // القائم
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'القائم',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalBaseController,
                            builder: (context, value, child) {
                              return Text(
                                value.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // الصافي
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'الصافي',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalNetController,
                            builder: (context, value, child) {
                              return Text(
                                value.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.lightGreenAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // السعر — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // الإجمالي
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'الإجمالي',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalGrandController,
                            builder: (context, value, child) {
                              return Text(
                                value.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.lightGreenAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // نقدي/دين — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTableWithStickyHeader() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: CustomScrollView(
        controller: _verticalScrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            floating: false,
            delegate: _StickyTableHeaderDelegate(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  border: Border.all(color: Colors.grey),
                ),
                child: _buildTableHeader(),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _horizontalScrollController,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width,
                  ),
                  child: _buildTableContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentRecord({bool silent = false}) async {
    if (_isSaving) return;
    if (!mounted) return;
    setState(() => _isSaving = true);

    // 1. تجميع السجلات الحالية من الواجهة
    final List<Sale> allSalesFromUI = [];
    double tCount = 0, tStanding = 0, tNet = 0, tGrand = 0;

    for (int i = 0; i < rowControllers.length; i++) {
      final controllers = rowControllers[i];
      if (controllers[1].text.isNotEmpty || controllers[4].text.isNotEmpty) {
        if (_canEditRow(i)) {
          double s = double.tryParse(controllers[6].text) ?? 0;
          double n = double.tryParse(controllers[7].text) ?? 0;
          if (s < n) {
            controllers[7].text = s.toStringAsFixed(2);
            _calculateRowValues(i);
          }
        }

        final sale = Sale(
          serialNumber: (allSalesFromUI.length + 1).toString(),
          material: controllers[1].text,
          affiliation: controllers[2].text,
          sValue: controllers[3].text,
          count: controllers[4].text,
          packaging: controllers[5].text,
          standing: controllers[6].text,
          net: controllers[7].text,
          price: controllers[8].text,
          total: controllers[9].text,
          cashOrDebt: cashOrDebtValues[i],
          empties: emptiesValues[i],
          customerName:
              cashOrDebtValues[i] == 'دين' ? customerNames[i].trim() : null,
          sellerName: sellerNames[i],
        );

        allSalesFromUI.add(sale);
        tCount += double.tryParse(sale.count) ?? 0;
        tStanding += double.tryParse(sale.standing) ?? 0;
        tNet += double.tryParse(sale.net) ?? 0;
        tGrand += double.tryParse(sale.total) ?? 0;
      }
    }

    // 2. منطق تحديث الأرصدة الجديد (الإلغاء ثم التطبيق)
    Map<String, double> customerBalanceChanges = {};
    final existingDoc = await _storageService.loadSalesDocument(
      widget.selectedDate,
    );

    // الخطوة أ: إلغاء أثر جميع ديون البائع القديمة في هذا اليوم
    if (existingDoc != null) {
      for (var oldSale in existingDoc.sales) {
        if (oldSale.sellerName == widget.sellerName &&
            oldSale.cashOrDebt == 'دين' &&
            oldSale.customerName != null &&
            oldSale.customerName!.isNotEmpty) {
          double oldAmount = double.tryParse(oldSale.total) ?? 0;
          customerBalanceChanges[oldSale.customerName!] =
              (customerBalanceChanges[oldSale.customerName!] ?? 0) - oldAmount;
        }
      }
    }

    // الخطوة ب: تطبيق أثر جميع ديون البائع الجديدة من الواجهة
    for (var newSale in allSalesFromUI) {
      if (newSale.sellerName == widget.sellerName &&
          newSale.cashOrDebt == 'دين' &&
          newSale.customerName != null &&
          newSale.customerName!.isNotEmpty) {
        double newAmount = double.tryParse(newSale.total) ?? 0;
        customerBalanceChanges[newSale.customerName!] =
            (customerBalanceChanges[newSale.customerName!] ?? 0) + newAmount;
      }
    }

    // 3. بناء الوثيقة النهائية للحفظ
    final documentToSave = SalesDocument(
      recordNumber: serialNumber,
      date: widget.selectedDate,
      sellerName: "Multiple Sellers", // الاسم العام للملف
      storeName: widget.storeName,
      dayName: dayName,
      sales: allSalesFromUI, // نرسل القائمة الكاملة من الواجهة
      totals: {
        'totalCount': tCount.toStringAsFixed(0),
        'totalBase': tStanding.toStringAsFixed(2),
        'totalNet': tNet.toStringAsFixed(2),
        'totalGrand': tGrand.toStringAsFixed(2),
      },
    );

    // 4. الحفظ في الملف وتحديث الأرصدة
    final success = await _storageService.saveSalesDocument(documentToSave);

    if (success) {
      // تطبيق التغييرات الصافية على أرصدة الزبائن
      for (var entry in customerBalanceChanges.entries) {
        if (entry.value != 0) {
          await _customerIndexService.updateCustomerBalance(
            entry.key,
            entry.value,
          );
        }
      }
      setState(() => _hasUnsavedChanges = false);
      await _loadOrCreateRecord(); // إعادة تحميل لضمان التناسق
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'تم الحفظ بنجاح' : 'فشل الحفظ'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<bool> _showUnsavedChangesDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('تغييرات غير محفوظة'),
            content: const Text(
              'هناك تغييرات غير محفوظة. هل تريد حفظها قبل الانتقال؟',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('تجاهل'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showInlineWarning(int rowIndex, String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // دالة مساعدة لإخفاء جميع الاقتراحات فوراً - مثل purchases_screen
  void _hideAllSuggestionsImmediately() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _materialSuggestions = [];
          _packagingSuggestions = [];
          _supplierSuggestions = [];
          _customerSuggestions = [];
          _activeMaterialRowIndex = null;
          _activePackagingRowIndex = null;
          _activeSupplierRowIndex = null;
          _activeCustomerRowIndex = null;
          _showFullScreenSuggestions = false;
          _currentSuggestionType = '';
        });
      }
    });
  }

  // دالة مساعدة لإخفاء جميع الاقتراحات
  void _clearAllSuggestions() {
    if (_materialSuggestions.isNotEmpty ||
        _packagingSuggestions.isNotEmpty ||
        _supplierSuggestions.isNotEmpty ||
        _customerSuggestions.isNotEmpty) {
      if (mounted) {
        setState(() {
          _materialSuggestions = [];
          _packagingSuggestions = [];
          _supplierSuggestions = [];
          _customerSuggestions = [];
          _activeMaterialRowIndex = null;
          _activePackagingRowIndex = null;
          _activeSupplierRowIndex = null;
          _activeCustomerRowIndex = null;
        });
      }
    }
  }

  // دالة لتحميل التواريخ المتاحة (مشابهة للمشتريات)
  Future<void> _loadAvailableDates() async {
    if (_isLoadingRecords) return;

    setState(() {
      _isLoadingRecords = true;
    });

    try {
      final dates = await _storageService.getAvailableDatesWithNumbers();

      if (kDebugMode) {
        debugPrint('✅ تم تحميل ${dates.length} يومية مبيعات');
        for (var date in dates) {
          debugPrint(
            '   - تاريخ: ${date['date']}, رقم: ${date['journalNumber']}',
          );
        }
      }

      setState(() {
        _availableRecords = dates;
        _isLoadingRecords = false;
      });
      _loadGrandTotal(); // <-- إضافة
    } catch (e) {
      setState(() {
        _availableRecords = [];
        _isLoadingRecords = false;
      });

      if (kDebugMode) {
        debugPrint('❌ خطأ في تحميل اليوميات: $e');
      }
    }
  }

  // حفظ الزبون في الفهرس
  void _saveCustomerToIndex(String customer) {
    final trimmedCustomer = customer.trim();
    if (trimmedCustomer.length > 1) {
      _customerIndexService.saveCustomer(trimmedCustomer);
    }
  }

  void _toggleFullScreenSuggestions({
    required String type,
    required bool show,
  }) {
    if (mounted) {
      setState(() {
        _showFullScreenSuggestions = show;
        if (show) {
          _currentSuggestionType = type;
        } else {
          _currentSuggestionType = '';
        }
      });
    }
  }

  int _getCurrentRowIndexByType() {
    switch (_currentSuggestionType) {
      case 'material':
        return _activeMaterialRowIndex ?? -1;
      case 'packaging':
        return _activePackagingRowIndex ?? -1;
      case 'supplier':
        return _activeSupplierRowIndex ?? -1;
      case 'customer':
        return _activeCustomerRowIndex ?? -1;
      default:
        return -1;
    }
  }

  List<SuggestionItem> _getSuggestionsByType() {
    switch (_currentSuggestionType) {
      case 'material':
        return _materialSuggestionItems;
      case 'packaging':
        return _packagingSuggestionItems;
      case 'supplier':
        return _supplierSuggestionItems;
      case 'customer':
        return _customerSuggestionItems;
      default:
        return [];
    }
  }

  Future<void> _loadJournalNumber() async {
    try {
      final journalNumber = await _storageService.getJournalNumberForDate(
        widget.selectedDate,
      );
      if (mounted) {
        setState(() {
          serialNumber = journalNumber;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          serialNumber = '1'; // الرقم الافتراضي في حالة الخطأ
        });
      }
    }
  }

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final adminSeller = prefs.getString('admin_seller');
    if (mounted) {
      setState(() {
        _isAdmin = (widget.sellerName == adminSeller);
      });
    }
  }

  // 2. تطبيق الحماية في الخلايا
  bool _canEditRow(int rowIndex) {
    if (rowIndex >= sellerNames.length) {
      return true; // صف جديد لم يحفظ بعد
    }
    if (_isAdmin) {
      return true; // الأدمن يمكنه تعديل أي شيء
    }
    // البائع العادي يعدل سجلاته فقط
    return sellerNames[rowIndex] == widget.sellerName;
  }

  Future<Uint8List> _generatePdfBytes(List<dynamic> items) async {
    final pdf = pw.Document();

    var arabicFont;
    try {
      final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
      arabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      arabicFont = pw.Font.courier();
    }

    double totalCount = 0, totalBase = 0, totalNet = 0, totalGrand = 0;
    for (var controllers in rowControllers) {
      totalCount += double.tryParse(controllers[4].text) ?? 0;
      totalBase += double.tryParse(controllers[6].text) ?? 0;
      totalNet += double.tryParse(controllers[7].text) ?? 0;
      totalGrand += double.tryParse(controllers[9].text) ?? 0;
    }

    final PdfColor headerColor = PdfColor.fromInt(0xFFF57C00);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor rowOddColor = PdfColor.fromInt(0xFFFFE0B2);
    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);
    final PdfColor totalRowColor = PdfColor.fromInt(0xFFFFCC80);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFont),
        build: (pw.Context context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                children: [
                  pw.Center(
                      child: pw.Text('يومية مبيعات رقم /$serialNumber/',
                          style: pw.TextStyle(
                              fontSize: 16, fontWeight: pw.FontWeight.bold))),
                  pw.Center(
                      child: pw.Text(
                          'تاريخ ${widget.selectedDate} - البائع ${widget.sellerName}',
                          style: const pw.TextStyle(
                              fontSize: 16, color: PdfColors.grey700))),
                  pw.SizedBox(height: 10),
                  pw.Table(
                    border: pw.TableBorder.all(color: borderColor, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(2),
                      4: const pw.FlexColumnWidth(3),
                      5: const pw.FlexColumnWidth(2),
                      6: const pw.FlexColumnWidth(2),
                      7: const pw.FlexColumnWidth(1),
                      8: const pw.FlexColumnWidth(3),
                      9: const pw.FlexColumnWidth(4),
                      10: const pw.FlexColumnWidth(3),
                      11: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: headerColor),
                        children: [
                          _buildPdfHeaderCell('نوع', headerTextColor),
                          _buildPdfHeaderCell('فوارغ', headerTextColor),
                          _buildPdfHeaderCell('الإجمالي', headerTextColor),
                          _buildPdfHeaderCell('السعر', headerTextColor),
                          _buildPdfHeaderCell('الصافي', headerTextColor),
                          _buildPdfHeaderCell('القائم', headerTextColor),
                          _buildPdfHeaderCell('العبوة', headerTextColor),
                          _buildPdfHeaderCell('العدد', headerTextColor),
                          _buildPdfHeaderCell('س', headerTextColor),
                          _buildPdfHeaderCell('العائدية', headerTextColor),
                          _buildPdfHeaderCell('المادة', headerTextColor),
                          _buildPdfHeaderCell('ت', headerTextColor),
                        ],
                      ),
                      ...rowControllers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final controllers = entry.value;
                        if (controllers[1].text.isEmpty &&
                            controllers[4].text.isEmpty) {
                          return pw.TableRow(
                              children: List.filled(12, pw.SizedBox()));
                        }
                        final color =
                            index % 2 == 0 ? rowEvenColor : rowOddColor;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: color),
                          children: [
                            _buildPdfCell(cashOrDebtValues[index]),
                            _buildPdfCell(emptiesValues[index]),
                            _buildPdfCell(controllers[9].text, isBold: true),
                            _buildPdfCell(controllers[8].text),
                            _buildPdfCell(controllers[7].text),
                            _buildPdfCell(controllers[6].text),
                            _buildPdfCell(controllers[5].text),
                            _buildPdfCell(controllers[4].text),
                            _buildPdfCell(controllers[3].text),
                            _buildPdfCell(controllers[2].text),
                            _buildPdfCell(controllers[1].text),
                            _buildPdfCell(controllers[0].text),
                          ],
                        );
                      }).toList(),
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: totalRowColor),
                        children: [
                          _buildPdfCell(''),
                          _buildPdfCell(''),
                          _buildPdfCell(totalGrand.toStringAsFixed(2),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(totalNet.toStringAsFixed(2),
                              isBold: true),
                          _buildPdfCell(totalBase.toStringAsFixed(2),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(totalCount.toStringAsFixed(0),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(''),
                          _buildPdfCell('المجموع', isBold: true),
                          _buildPdfCell(''),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return await pdf.save();
  }

  pw.Widget _buildPdfHeaderCell(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _buildPdfCell(String text, {bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String _extractNameFromSuggestion(String suggestion) {
    final dotIndex = suggestion.indexOf('. ');
    if (dotIndex != -1 && dotIndex + 2 < suggestion.length) {
      return suggestion.substring(dotIndex + 2).trim();
    }
    return suggestion.trim();
  }
  // ========== دوال التحكم بالأسهم ==========

  void _attachFocusListeners(int rowIndex) {
    for (int col = 0; col < rowFocusNodes[rowIndex].length; col++) {
      rowFocusNodes[rowIndex][col].removeListener(() {});
      rowFocusNodes[rowIndex][col].addListener(() {
        if (rowFocusNodes[rowIndex][col].hasFocus) {
          _currentFocusRow = rowIndex;
          _currentFocusCol = col;
          _scrollToField(rowIndex, col);
        }
      });
    }
  }

  void _moveFocus(int deltaRow, int deltaCol) {
    if (_currentFocusRow == -1 || _currentFocusCol == -1) {
      if (rowFocusNodes.isNotEmpty && rowFocusNodes[0].length > 1) {
        _currentFocusRow = 0;
        _currentFocusCol = 1; // حقل المادة
        FocusScope.of(context).requestFocus(rowFocusNodes[0][1]);
        _scrollToField(0, 1);
        _adjustScrollPosition(0);
      }
      return;
    }

    int newRow = _currentFocusRow + deltaRow;
    int newCol = _currentFocusCol + deltaCol;

    if (newRow < 0) newRow = 0;
    if (newRow >= rowFocusNodes.length) newRow = rowFocusNodes.length - 1;

    // حدود الأعمدة: المادة(1) حتى السعر(8) - لا نذهب إلى المسلسل(0) أو الإجمالي(9) أو نقدي/دين(10) أو الفوارغ(11)
    const int minCol = 1;
    const int maxCol = 8;
    if (newCol < minCol) newCol = minCol;
    if (newCol > maxCol) newCol = maxCol;

    FocusScope.of(context).requestFocus(rowFocusNodes[newRow][newCol]);
    _currentFocusRow = newRow;
    _currentFocusCol = newCol;

    _scrollToField(newRow, newCol);
    _adjustScrollPosition(newRow);
  }

  void _adjustScrollPosition(int currentRowIndex) {
    final int totalRows = rowFocusNodes.length;
    if (totalRows == 0) return;

    if (currentRowIndex <= 2) {
      _verticalScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (totalRows - currentRowIndex <= 3) {
      _verticalScrollController.animateTo(
        _verticalScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadGrandTotal() async {
    double total = 0.0;
    for (var dateInfo in _availableRecords) {
      final doc = await _storageService.loadSalesDocument(dateInfo['date']!);
      if (doc != null) {
        total += double.tryParse(doc.totals['totalGrand'] ?? '0') ?? 0;
      }
    }
    if (mounted) setState(() => _grandTotal = total);
  }
}

class _StickyTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTableHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => 32.0;

  @override
  double get minExtent => 32.0;

  @override
  bool shouldRebuild(_StickyTableHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}
