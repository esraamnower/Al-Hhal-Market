import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../models/receipt_model.dart';
import '../../services/receipt_storage_service.dart';
// استيراد خدمات الفهرس
import '../../services/material_index_service.dart';
import '../../services/packaging_index_service.dart';
import '../../services/supplier_index_service.dart';

import '../../widgets/table_builder.dart' as TableBuilder;
import '../../widgets/table_components.dart' as TableComponents;
import '../../widgets/suggestions_banner.dart';
import '../../services/supplier_balance_tracker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../widgets/exit_button.dart';
import '../../widgets/pdf_action_menu.dart';

class ReceiptScreen extends StatefulWidget {
  final String sellerName;
  final String selectedDate;
  final String storeName;

  const ReceiptScreen({
    Key? key,
    required this.sellerName,
    required this.selectedDate,
    required this.storeName,
  }) : super(key: key);

  @override
  _ReceiptScreenState createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  // خدمة التخزين
  final ReceiptStorageService _storageService = ReceiptStorageService();

  // خدمات الفهرس
  final MaterialIndexService _materialIndexService = MaterialIndexService();
  final PackagingIndexService _packagingIndexService = PackagingIndexService();
  final SupplierIndexService _supplierIndexService = SupplierIndexService();

  // بيانات الحقول
  String dayName = '';

  // قائمة لتخزين صفوف الجدول
  List<List<TextEditingController>> rowControllers = [];
  List<List<FocusNode>> rowFocusNodes = [];
  List<String> sellerNames = []; // <-- تخزين اسم البائع لكل صف

  // متحكمات صف المجموع
  late TextEditingController totalCountController;
  late TextEditingController totalStandingController;
  late TextEditingController totalPaymentController;
  late TextEditingController totalLoadController;

  // متحكمات للتمرير
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final _scrollController = ScrollController(); // للتمرير

  // حالة الحفظ
  bool _isSaving = false;
  bool _hasUnsavedChanges = false;

  // التواريخ المتاحة
  List<Map<String, String>> _availableDates = [];
  bool _isLoadingDates = false;

  String serialNumber = '';
  // ignore: unused_field
  String? _currentJournalNumber;

  // متغيرات للاقتراحات
  List<String> _materialSuggestions = [];
  List<String> _packagingSuggestions = [];
  List<String> _supplierSuggestions = [];

  // مؤشرات الصفوف النشطة للاقتراحات
  int? _activeMaterialRowIndex;
  int? _activePackagingRowIndex;
  int? _activeSupplierRowIndex;

  // متحكمات التمرير الأفقي للاقتراحات
  final ScrollController _materialSuggestionsScrollController =
      ScrollController();
  final ScrollController _packagingSuggestionsScrollController =
      ScrollController();
  final ScrollController _supplierSuggestionsScrollController =
      ScrollController();
  bool _showFullScreenSuggestions = false;
  String _currentSuggestionType = '';
  late ScrollController
      _horizontalSuggestionsController; // في initState قم بتعريفه: _horizontalSuggestionsController = ScrollController();
  final SupplierBalanceTracker _balanceTracker = SupplierBalanceTracker();

  // متغير لتأخير حساب المجاميع (debouncing)
  Timer? _calculateTotalsDebouncer;
  bool _isCalculating = false;
  bool _isAdmin = false;

  List<SuggestionItem> _materialSuggestionItems = [];
  List<SuggestionItem> _packagingSuggestionItems = [];
  List<SuggestionItem> _supplierSuggestionItems = [];

  double _grandTotal = 0.0;
  FocusNode? _addButtonFocusNode;
  int _currentFocusRow = -1;
  int _currentFocusCol = -1;

  @override
  void initState() {
    super.initState();
    dayName = _extractDayName(widget.selectedDate);

    totalCountController = TextEditingController();
    totalStandingController = TextEditingController();
    totalPaymentController = TextEditingController();
    totalLoadController = TextEditingController();

    _resetTotalValues();
    _horizontalSuggestionsController = ScrollController();

    _verticalScrollController.addListener(_hideAllSuggestionsImmediately);
    _horizontalScrollController.addListener(_hideAllSuggestionsImmediately);

    _addButtonFocusNode = FocusNode(); // <-- إضافة

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAdminStatus().then((_) {
        _loadOrCreateJournal();
      });
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
    totalStandingController.dispose();
    totalPaymentController.dispose();
    totalLoadController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _scrollController.dispose();
    _materialSuggestionsScrollController.dispose();
    _packagingSuggestionsScrollController.dispose();
    _supplierSuggestionsScrollController.dispose();

    _horizontalSuggestionsController.dispose();
    _addButtonFocusNode?.dispose(); // <-- إضافة

    _balanceTracker.dispose();

    _calculateTotalsDebouncer?.cancel();
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
      'السبت'
    ];
    final now = DateTime.now();
    return days[now.weekday % 7];
  }

  // تحميل التواريخ المتاحة
  Future<void> _loadAvailableDates() async {
    if (_isLoadingDates) return;

    setState(() {
      _isLoadingDates = true;
    });

    try {
      final dates = await _storageService.getAvailableDatesWithNumbers();
      setState(() {
        _availableDates = dates;
        _isLoadingDates = false;
      });
      _loadGrandTotal(); // <-- إضافة
    } catch (e) {
      setState(() {
        _availableDates = [];
        _isLoadingDates = false;
      });
    }
  }

  // تحميل اليومية إذا كانت موجودة، أو إنشاء جديدة
  Future<void> _loadOrCreateJournal() async {
    final document =
        await _storageService.loadReceiptDocumentForDate(widget.selectedDate);

    if (document != null && document.receipts.isNotEmpty) {
      // تحميل اليومية الموجودة
      _loadJournal(document);
    } else {
      // إنشاء يومية جديدة
      _createNewJournal();
    }
  }

  void _resetTotalValues() {
    totalCountController.text = '0';
    totalStandingController.text = '0.00';
    totalPaymentController.text = '0.00';
    totalLoadController.text = '0.00';
  }

  void _createNewJournal() {
    setState(() {
      rowControllers.clear();
      rowFocusNodes.clear();
      sellerNames.clear();
      _resetTotalValues();
      _hasUnsavedChanges = false;
      _addNewRow();
    });
  }

  void _addNewRow() {
    setState(() {
      final newSerialNumber = (rowControllers.length + 1).toString();

      List<TextEditingController> newControllers =
          List.generate(9, (index) => TextEditingController());

      List<FocusNode> newFocusNodes = List.generate(9, (index) => FocusNode());

      // العمود 0 أصبح للعتالة، نضعه فارغاً أو بقيمة افتراضية
      newControllers[0].text = '0.00'; // <-- قيمة افتراضية للعتالة

      // نضيف مستمع للعتالة (العمود 0) لحساب المجاميع إذا لزم الأمر
      newControllers[0].addListener(() {
        _hasUnsavedChanges = true;
        _calculateAllTotals();
      });

      _addChangeListenersToControllers(newControllers, rowControllers.length);
      sellerNames.add(widget.sellerName);
      rowControllers.add(newControllers);
      rowFocusNodes.add(newFocusNodes);
    });

    _attachFocusListeners(rowControllers.length - 1);

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted && rowFocusNodes.isNotEmpty) {
        final newRowIndex = rowFocusNodes.length - 1;
        _currentFocusRow = newRowIndex;
        _currentFocusCol = 1;
        FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
        _scrollToField(newRowIndex, 1);
        _adjustScrollPosition(newRowIndex);
      }
    });
  }

  // دالة مساعدة لإخفاء جميع الاقتراحات فوراً
  void _hideAllSuggestionsImmediately() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _materialSuggestions = [];
          _packagingSuggestions = [];
          _supplierSuggestions = [];
          _activeMaterialRowIndex = null;
          _activePackagingRowIndex = null;
          _activeSupplierRowIndex = null;
        });
      }
    });
  }

  // دالة مساعدة لإضافة المستمعات
  void _addChangeListenersToControllers(
      List<TextEditingController> controllers, int rowIndex) {
    controllers[0].addListener(() {
      // العتالة
      _hasUnsavedChanges = true;
      _calculateAllTotals();
    });
    controllers[1].addListener(() {
      // المادة
      _hasUnsavedChanges = true;
      _updateMaterialSuggestions(rowIndex);
    });
    controllers[2].addListener(() {
      // العائدية
      _hasUnsavedChanges = true;
      _updateSupplierSuggestions(rowIndex);
    });
    controllers[4].addListener(() {
      // العدد
      _hasUnsavedChanges = true;
      _calculateAllTotals();
    });
    controllers[5].addListener(() {
      // العبوة
      _hasUnsavedChanges = true;
      _updatePackagingSuggestions(rowIndex);
    });
    controllers[6].addListener(() {
      // القائم
      _hasUnsavedChanges = true;
      _calculateAllTotals();
    });
    controllers[7].addListener(() {
      // الدفعة
      _hasUnsavedChanges = true;
      _calculateAllTotals();
    });
    controllers[8].addListener(() {
      // الحمولة
      _hasUnsavedChanges = true;
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

  // اختيار اقتراح للمادة
  void _selectMaterialSuggestion(String suggestion, int rowIndex) {
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][1].text = actualName;
    _hasUnsavedChanges = true;

    if (actualName.trim().length > 1) {
      _saveMaterialToIndex(actualName);
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][2]);
      }
    });
  }

  // اختيار اقتراح للعبوة
  void _selectPackagingSuggestion(String suggestion, int rowIndex) {
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][5].text = actualName;
    _hasUnsavedChanges = true;

    if (actualName.trim().length > 1) {
      _savePackagingToIndex(actualName);
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][6]);
      }
    });
  }

  // اختيار اقتراح للمورد (العائدية)
  void _selectSupplierSuggestion(String suggestion, int rowIndex) {
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][2].text = actualName;
    _hasUnsavedChanges = true;

    if (actualName.trim().length > 1) {
      _saveSupplierToIndex(actualName);
    }

    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][3]);
      }
    });
  }

  // حفظ المادة في الفهرس - معدلة لمنع تخزين حرف واحد
  void _saveMaterialToIndex(String material) {
    final trimmedMaterial = material.trim();
    // منع تخزين حرف واحد أو قيمة فارغة
    if (trimmedMaterial.length > 1) {
      _materialIndexService.saveMaterial(trimmedMaterial);
    }
  }

  // حفظ العبوة في الفهرس - معدلة لمنع تخزين حرف واحد
  void _savePackagingToIndex(String packaging) {
    final trimmedPackaging = packaging.trim();
    // منع تخزين حرف واحد أو قيمة فارغة
    if (trimmedPackaging.length > 1) {
      _packagingIndexService.savePackaging(trimmedPackaging);
    }
  }

  // حفظ المورد في الفهرس - معدلة لمنع تخزين حرف واحد
  void _saveSupplierToIndex(String supplier) {
    final trimmedSupplier = supplier.trim();
    // منع تخزين حرف واحد أو قيمة فارغة
    if (trimmedSupplier.length > 1) {
      _supplierIndexService.saveSupplier(trimmedSupplier);
    }
  }

  void _calculateAllTotals() {
    _calculateTotalsDebouncer?.cancel();
    _calculateTotalsDebouncer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || _isCalculating) return;
      _isCalculating = true;

      double totalCount = 0;
      double totalStanding = 0;
      double totalPayment = 0;
      double totalLoad = 0;

      for (var controllers in rowControllers) {
        try {
          totalCount +=
              double.tryParse(controllers[4].text) ?? 0; // تغيير إلى 4
          totalStanding +=
              double.tryParse(controllers[6].text) ?? 0; // تغيير إلى 6
          totalPayment +=
              double.tryParse(controllers[7].text) ?? 0; // تغيير إلى 7
          totalLoad += double.tryParse(controllers[8].text) ?? 0; // تغيير إلى 8
        } catch (e) {}
      }

      if (mounted) {
        setState(() {
          totalCountController.text = totalCount.toStringAsFixed(0);
          totalStandingController.text = totalStanding.toStringAsFixed(2);
          totalPaymentController.text = totalPayment.toStringAsFixed(2);
          totalLoadController.text = totalLoad.toStringAsFixed(2);
        });
      }
      _isCalculating = false;
    });
  }

  void _loadJournal(ReceiptDocument document) {
    setState(() {
      for (var row in rowControllers) {
        for (var controller in row) controller.dispose();
      }
      for (var row in rowFocusNodes) {
        for (var node in row) node.dispose();
      }
      rowControllers.clear();
      rowFocusNodes.clear();
      sellerNames.clear();

      for (int i = 0; i < document.receipts.length; i++) {
        var receipt = document.receipts[i];
        List<TextEditingController> newControllers = [
          TextEditingController(text: receipt.portage),
          TextEditingController(text: receipt.material),
          TextEditingController(text: receipt.affiliation),
          TextEditingController(text: receipt.sValue),
          TextEditingController(text: receipt.count),
          TextEditingController(text: receipt.packaging),
          TextEditingController(text: receipt.standing),
          TextEditingController(text: receipt.payment),
          TextEditingController(text: receipt.load),
        ];

        List<FocusNode> newFocusNodes =
            List.generate(9, (index) => FocusNode());
        sellerNames.add(receipt.sellerName);
        final bool isOwnedByCurrentSeller =
            receipt.sellerName == widget.sellerName;
        if (isOwnedByCurrentSeller) {
          _addChangeListenersToControllers(newControllers, i);
        }
        rowControllers.add(newControllers);
        rowFocusNodes.add(newFocusNodes);
      }

      // ربط مستمعات التركيز لكل الصفوف المحملة
      for (int i = 0; i < rowFocusNodes.length; i++) {
        _attachFocusListeners(i); // <-- إضافة
      }

      if (document.totals.isNotEmpty) {
        totalCountController.text = document.totals['totalCount'] ?? '0';
        totalStandingController.text =
            document.totals['totalStanding'] ?? '0.00';
        totalPaymentController.text = document.totals['totalPayment'] ?? '0.00';
        totalLoadController.text = document.totals['totalLoad'] ?? '0.00';
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
      columnWidths: const {
        3: FixedColumnWidth(30.0),
      },
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            TableComponents.buildTableHeaderCell('العتالة'), // <-- تغيير
            TableComponents.buildTableHeaderCell('المادة'),
            TableComponents.buildTableHeaderCell('العائدية'),
            TableComponents.buildTableHeaderCell('س'),
            TableComponents.buildTableHeaderCell('العدد'),
            TableComponents.buildTableHeaderCell('العبوة'),
            TableComponents.buildTableHeaderCell('القائم'),
            TableComponents.buildTableHeaderCell('الدفعة'),
            TableComponents.buildTableHeaderCell('الحمولة'),
          ],
        ),
      ],
    );
  }

  Widget _buildTableContent() {
    List<TableRow> contentRows = [];
    for (int i = 0; i < rowControllers.length; i++) {
      final bool isOwnedByCurrentSeller = sellerNames[i] == widget.sellerName;
      contentRows.add(
        TableRow(
          children: [
            _buildPortageCell(rowControllers[i][0], rowFocusNodes[i][0], i, 0,
                isOwnedByCurrentSeller), // <-- دالة جديدة للعتالة
            _buildMaterialCell(rowControllers[i][1], rowFocusNodes[i][1], i, 1,
                isOwnedByCurrentSeller),
            _buildSupplierCell(rowControllers[i][2], rowFocusNodes[i][2], i, 2,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][3], rowFocusNodes[i][3], i, 3,
                isOwnedByCurrentSeller,
                isSField: true),
            _buildTableCell(rowControllers[i][4], rowFocusNodes[i][4], i, 4,
                isOwnedByCurrentSeller),
            _buildPackagingCell(rowControllers[i][5], rowFocusNodes[i][5], i, 5,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][6], rowFocusNodes[i][6], i, 6,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][7], rowFocusNodes[i][7], i, 7,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][8], rowFocusNodes[i][8], i, 8,
                isOwnedByCurrentSeller),
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
            TableComponents.buildTotalCell(totalStandingController),
            TableComponents.buildTotalCell(totalPaymentController),
            TableComponents.buildTotalCell(totalLoadController),
          ],
        ),
      );
    }
    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      columnWidths: const {
        3: FixedColumnWidth(30.0),
      },
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: contentRows,
    );
  }

  Widget _buildTableCell(TextEditingController controller, FocusNode focusNode,
      int rowIndex, int colIndex, bool isOwnedByCurrentSeller,
      {bool isSField = false}) {
    bool isSerialField = colIndex == 0;
    bool isNumericField =
        colIndex == 4 || colIndex == 6 || colIndex == 7 || colIndex == 8;

    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: isSerialField,
      isNumericField: isNumericField,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: _handleFieldSubmitted,
      onFieldChanged: _handleFieldChanged,
      isSField: isSField,
      inputFormatters: isSField
          ? [
              TableComponents.TwoDigitInputFormatter(),
              FilteringTextInputFormatter.digitsOnly,
            ]
          : (isNumericField
              ? [
                  TableComponents.PositiveDecimalInputFormatter(),
                  FilteringTextInputFormatter.deny(RegExp(r'\.\d{3,}')),
                ]
              : null),
      fontSize: isSField ? 11 : 16, // <-- تغيير من 13 إلى 16
      textAlign: isSField
          ? TextAlign.center
          : TextAlign.center, // <-- تغيير إلى center
      textDirection:
          isSField ? TextDirection.ltr : TextDirection.ltr, // <-- تغيير إلى ltr
    );
  }

  Widget _buildMaterialCell(
      TextEditingController controller,
      FocusNode focusNode,
      int rowIndex,
      int colIndex,
      bool isOwnedByCurrentSeller) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: _handleFieldSubmitted,
      onFieldChanged: _handleFieldChanged,
      fontSize: 16, // <-- إضافة
      textAlign: TextAlign.center, // <-- إضافة
      textDirection: TextDirection.ltr, // <-- إضافة
    );
  }

  Widget _buildPackagingCell(
      TextEditingController controller,
      FocusNode focusNode,
      int rowIndex,
      int colIndex,
      bool isOwnedByCurrentSeller) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: _handleFieldSubmitted,
      onFieldChanged: _handleFieldChanged,
      fontSize: 16, // <-- إضافة
      textAlign: TextAlign.center, // <-- إضافة
      textDirection: TextDirection.ltr, // <-- إضافة
    );
  }

  Widget _buildSupplierCell(
      TextEditingController controller,
      FocusNode focusNode,
      int rowIndex,
      int colIndex,
      bool isOwnedByCurrentSeller) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: false,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: _handleFieldSubmitted,
      onFieldChanged: _handleFieldChanged,
      fontSize: 16, // <-- إضافة
      textAlign: TextAlign.center, // <-- إضافة
      textDirection: TextDirection.ltr, // <-- إضافة
    );
  }

  void _handleFieldSubmitted(String value, int rowIndex, int colIndex) {
    if (!_canEditRow(rowIndex)) return;

    if (colIndex == 0) {
      // العتالة ← ننتقل إلى المادة
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][1]);
    } else if (colIndex == 1) {
      // المادة
      if (_materialSuggestions.isNotEmpty) {
        _selectMaterialSuggestion(_materialSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _saveMaterialToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][2]);
    } else if (colIndex == 2) {
      // العائدية
      if (_supplierSuggestions.isNotEmpty) {
        _selectSupplierSuggestion(_supplierSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _saveSupplierToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][3]);
    } else if (colIndex == 5) {
      // العبوة
      if (_packagingSuggestions.isNotEmpty) {
        _selectPackagingSuggestion(_packagingSuggestions[0], rowIndex);
        return;
      }
      if (value.trim().length > 1) _savePackagingToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][6]);
    } else if (colIndex == 8) {
      // الحمولة - إنشاء صف جديد
      _addNewRow();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && rowControllers.isNotEmpty) {
          final newRowIndex = rowControllers.length - 1;
          _currentFocusRow = newRowIndex;
          _currentFocusCol = 1;
          FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
          _scrollToField(newRowIndex, 1);
          _adjustScrollPosition(newRowIndex);
        }
      });
    }
    _hideAllSuggestionsImmediately();
  }

  void _handleFieldChanged(String value, int rowIndex, int colIndex) {
    if (!_canEditRow(rowIndex)) return;

    setState(() {
      _hasUnsavedChanges = true;

      // تحديث المجاميع للحقول الرقمية (بما فيها العتالة)
      if (colIndex == 0 ||
          colIndex == 3 ||
          colIndex == 5 ||
          colIndex == 6 ||
          colIndex == 7 ||
          colIndex == 8) {
        _calculateAllTotals();
      }

      // إخفاء الاقتراحات عند الكتابة في حقول أخرى
      if (colIndex == 1 && _activeMaterialRowIndex != rowIndex) {
        _clearAllSuggestions();
      } else if (colIndex == 2 && _activeSupplierRowIndex != rowIndex) {
        _clearAllSuggestions();
      } else if (colIndex == 4 && _activePackagingRowIndex != rowIndex) {
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasUnsavedChanges) {
          await _saveCurrentRecord(silent: true);
        }
        return true;
      },
      child: Scaffold(
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
                      'يومية استلام رقم /$serialNumber/ تاريخ ${widget.selectedDate} البائع ${widget.sellerName}',
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
                          const Text('إجمالي الدفع والحمولة: ',
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
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          PdfActionMenu(
            type: 'receipt',
            supplierOrCustomerName: 'الاستلام',
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
                  await _saveCurrentRecord(silent: true);
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(
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

              if (_isLoadingDates) {
                items.add(
                  const PopupMenuItem<String>(
                    value: '',
                    enabled: false,
                    child: Text('جاري التحميل...'),
                  ),
                );
              } else if (_availableDates.isEmpty) {
                items.add(
                  const PopupMenuItem<String>(
                    value: '',
                    enabled: false,
                    child: Text('لا توجد يوميات سابقة'),
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

                for (var dateInfo in _availableDates) {
                  final date = dateInfo['date']!;
                  final journalNumber = dateInfo['journalNumber']!;

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
                              ? Colors.blue
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
    ),
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
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue[700]!.withOpacity(0.45),
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
                    // المادة — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // العائدية — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
                    ),
                    Container(width: 1, height: 32, color: Colors.white24),
                    // س — فارغ
                    Expanded(
                      child: const SizedBox.shrink(),
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
                            valueListenable: totalStandingController,
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
                    // الدفعة
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'الدفعة',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalPaymentController,
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
                    // الحمولة
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'الحمولة',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: totalLoadController,
                            builder: (context, value, child) {
                              return Text(
                                value.text,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
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
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
              ),
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

    // 1. تجميع السجلات الحالية من واجهة المستخدم
    final List<Receipt> allReceiptsFromUI = [];
    for (int i = 0; i < rowControllers.length; i++) {
      final controllers = rowControllers[i];
      if (controllers[1].text.isNotEmpty || controllers[4].text.isNotEmpty) {
        allReceiptsFromUI.add(Receipt(
          serialNumber: (allReceiptsFromUI.length + 1)
              .toString(), // إعادة ترقيم لضمان التسلسل
          material: controllers[1].text,
          affiliation: controllers[2].text.trim(),
          sValue: controllers[3].text,
          count: controllers[4].text,
          packaging: controllers[5].text,
          standing: controllers[6].text,
          payment: controllers[7].text,
          load: controllers[8].text,
          sellerName: sellerNames[i],
          portage: controllers[0].text,
        ));
      }
    }

    // إذا لم تكن هناك بيانات فعلية، توقف عن الحفظ
    if (allReceiptsFromUI.isEmpty) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('لا توجد بيانات للحفظ'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    // 2. منطق تحديث الأرصدة الجديد (الإلغاء ثم التطبيق)
    Map<String, double> supplierBalanceChanges = {};
    final existingDocument =
        await _storageService.loadReceiptDocumentForDate(widget.selectedDate);

    // الخطوة أ: إلغاء أثر جميع سجلات الاستلام القديمة لهذا البائع
    if (existingDocument != null) {
      for (var oldReceipt in existingDocument.receipts) {
        if (oldReceipt.sellerName == widget.sellerName &&
            oldReceipt.affiliation.isNotEmpty) {
          double oldPayment = double.tryParse(oldReceipt.payment) ?? 0;
          double oldLoad = double.tryParse(oldReceipt.load) ?? 0;
          // في الاستلام، الدفعة والحمولة تخفض رصيد المورد. لإلغاء هذا الأثر، نعيد إضافة القيمة.
          double totalOldDeduction = oldPayment + oldLoad;
          supplierBalanceChanges[oldReceipt.affiliation] =
              (supplierBalanceChanges[oldReceipt.affiliation] ?? 0) +
                  totalOldDeduction;
        }
      }
    }

    // الخطوة ب: تطبيق أثر جميع سجلات الاستلام الجديدة من الواجهة
    for (var newReceipt in allReceiptsFromUI) {
      if (newReceipt.sellerName == widget.sellerName &&
          newReceipt.affiliation.isNotEmpty) {
        double newPayment = double.tryParse(newReceipt.payment) ?? 0;
        double newLoad = double.tryParse(newReceipt.load) ?? 0;
        // تطبيق الخصم الجديد من رصيد المورد.
        double totalNewDeduction = newPayment + newLoad;
        supplierBalanceChanges[newReceipt.affiliation] =
            (supplierBalanceChanges[newReceipt.affiliation] ?? 0) -
                totalNewDeduction;
      }
    }

    // 3. بناء الوثيقة النهائية وإرسالها للحفظ
    final documentToSave = ReceiptDocument(
      recordNumber: serialNumber,
      date: widget.selectedDate,
      sellerName: "Multiple Sellers", // الاسم العام للملف
      storeName: widget.storeName,
      dayName: dayName,
      receipts: allReceiptsFromUI, // نرسل القائمة الكاملة والمحدثة
      totals: {}, // سيتم حساب المجاميع في خدمة التخزين
    );

    final success = await _storageService.saveReceiptDocument(documentToSave);

    if (success) {
      // 4. تطبيق التغييرات الصافية على أرصدة الموردين
      for (var entry in supplierBalanceChanges.entries) {
        if (entry.value != 0) {
          // دالة updateSupplierBalance تضيف القيمة، لذا نرسل القيمة الصافية مباشرة (موجبة أو سالبة)
          await _supplierIndexService.updateSupplierBalance(
              entry.key, entry.value);
        }
      }

      setState(() => _hasUnsavedChanges = false);
      await _loadOrCreateJournal(); // إعادة تحميل لضمان التناسق
    }
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? 'تم الحفظ بنجاح' : 'فشل الحفظ'),
          backgroundColor: success ? Colors.green : Colors.red));
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

  Future<void> _loadJournalNumber() async {
    try {
      final journalNumber =
          await _storageService.getJournalNumberForDate(widget.selectedDate);
      setState(() {
        serialNumber = journalNumber;
        _currentJournalNumber = journalNumber;
      });
    } catch (e) {
      setState(() {
        serialNumber = '1';
        _currentJournalNumber = '1';
      });
    }
  }

  // دالة مساعدة لإخفاء جميع الاقتراحات
  void _clearAllSuggestions() {
    if (_materialSuggestions.isNotEmpty ||
        _packagingSuggestions.isNotEmpty ||
        _supplierSuggestions.isNotEmpty) {
      setState(() {
        _materialSuggestions = [];
        _packagingSuggestions = [];
        _supplierSuggestions = [];
        _activeMaterialRowIndex = null;
        _activePackagingRowIndex = null;
        _activeSupplierRowIndex = null;
      });
    }
  }

  void _toggleFullScreenSuggestions(
      {required String type, required bool show}) {
    if (mounted) {
      setState(() {
        _showFullScreenSuggestions = show;
        _currentSuggestionType = show ? type : '';
      });
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
      default:
        return [];
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

      default:
        return -1;
    }
  }

  // *** دالة جديدة للتحقق من صلاحيات الأدمن ***
  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final adminSeller = prefs.getString('admin_seller');
    if (mounted) {
      setState(() {
        _isAdmin = (widget.sellerName == adminSeller);
      });
    }
  }

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

  // --- دالة توليد PDF والمشاركة (ReceiptScreen) ---
  Future<Uint8List> _generatePdfBytes(List<dynamic> items) async {
    final pdf = pw.Document();

    var arabicFont;
    try {
      final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
      arabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      arabicFont = pw.Font.courier();
    }

    final PdfColor headerColor = PdfColor.fromInt(0xFF1976D2);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor rowOddColor = PdfColor.fromInt(0xFFBBDEFB);
    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFont),
        build: (pw.Context context) {
          return [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                children: [
                  pw.Center(
                      child: pw.Text('يومية استلام رقم /$serialNumber/',
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
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(3),
                      4: const pw.FlexColumnWidth(2),
                      5: const pw.FlexColumnWidth(1),
                      6: const pw.FlexColumnWidth(3),
                      7: const pw.FlexColumnWidth(4),
                      8: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: headerColor),
                        children: [
                          _buildPdfHeaderCell('الحمولة', headerTextColor),
                          _buildPdfHeaderCell('الدفعة', headerTextColor),
                          _buildPdfHeaderCell('القائم', headerTextColor),
                          _buildPdfHeaderCell('العبوة', headerTextColor),
                          _buildPdfHeaderCell('العدد', headerTextColor),
                          _buildPdfHeaderCell('س', headerTextColor),
                          _buildPdfHeaderCell('العائدية', headerTextColor),
                          _buildPdfHeaderCell('المادة', headerTextColor),
                          _buildPdfHeaderCell('العتالة', headerTextColor),
                        ],
                      ),
                      ...rowControllers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final controllers = entry.value;
                        if (controllers[1].text.isEmpty &&
                            controllers[4].text.isEmpty) {
                          return pw.TableRow(
                              children: List.filled(9, pw.SizedBox()));
                        }
                        final color =
                            index % 2 == 0 ? rowEvenColor : rowOddColor;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: color),
                          children: [
                            _buildPdfCell(controllers[8].text),
                            _buildPdfCell(controllers[7].text),
                            _buildPdfCell(controllers[6].text),
                            _buildPdfCell(controllers[5].text),
                            _buildPdfCell(controllers[4].text),
                            _buildPdfCell(controllers[3].text),
                            _buildPdfCell(controllers[2].text),
                            _buildPdfCell(controllers[1].text),
                            _buildPdfCell(controllers[0].text)
                          ],
                        );
                      }).toList(),
                      pw.TableRow(
                        decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFF90CAF9)),
                        children: [
                          _buildPdfCell(totalLoadController.text, isBold: true),
                          _buildPdfCell(totalPaymentController.text,
                              isBold: true),
                          _buildPdfCell(totalStandingController.text,
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(totalCountController.text,
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(''),
                          _buildPdfCell(''),
                          _buildPdfCell('م', isBold: true),
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
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              color: color, fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _buildPdfCell(String text, {bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
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

    // حدود الأعمدة: المادة(1) حتى الحمولة(8) - لا نذهب إلى المسلسل(0)
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
    for (var dateInfo in _availableDates) {
      final doc =
          await _storageService.loadReceiptDocumentForDate(dateInfo['date']!);
      if (doc != null) {
        total += double.tryParse(doc.totals['totalPayment'] ?? '0') ?? 0;
        total += double.tryParse(doc.totals['totalLoad'] ?? '0') ?? 0;
      }
    }
    if (mounted) setState(() => _grandTotal = total);
  }

  Widget _buildPortageCell(
      TextEditingController controller,
      FocusNode focusNode,
      int rowIndex,
      int colIndex,
      bool isOwnedByCurrentSeller) {
    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: _canEditRow(rowIndex),
      isSerialField: false,
      isNumericField: true, // <-- معاملة كحقل رقمي
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: _handleFieldSubmitted,
      onFieldChanged: _handleFieldChanged,
      isSField: false,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), // أرقام وفواصل
      ],
      fontSize: 16,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
  }
}

class _StickyTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTableHeaderDelegate({required this.child});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
