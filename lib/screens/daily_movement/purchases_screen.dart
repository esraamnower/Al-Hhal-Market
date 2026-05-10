import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import '../../models/purchase_model.dart';
import '../../services/purchase_storage_service.dart';
// استيراد خدمات الفهرس
import '../../services/material_index_service.dart';
import '../../services/packaging_index_service.dart';
import '../../services/supplier_index_service.dart';
import '../../widgets/table_builder.dart' as TableBuilder;
import '../../widgets/table_components.dart' as TableComponents;
import '../../widgets/common_dialogs.dart' as CommonDialogs;
import '../../widgets/suggestions_banner.dart';
import '../../widgets/exit_button.dart';
import '../../services/supplier_balance_tracker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import '../../widgets/pdf_action_menu.dart';

class PurchasesScreen extends StatefulWidget {
  final String sellerName;
  final String selectedDate;
  final String storeName;

  const PurchasesScreen({
    Key? key,
    required this.sellerName,
    required this.selectedDate,
    required this.storeName,
  }) : super(key: key);

  @override
  _PurchasesScreenState createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  // خدمة التخزين
  final PurchaseStorageService _storageService = PurchaseStorageService();

  // خدمات الفهرس
  final MaterialIndexService _materialIndexService = MaterialIndexService();
  final PackagingIndexService _packagingIndexService = PackagingIndexService();
  final SupplierIndexService _supplierIndexService = SupplierIndexService();

  // بيانات الحقول
  String dayName = '';

  // قائمة لتخزين صفوف الجدول
  List<List<TextEditingController>> rowControllers = [];
  List<List<FocusNode>> rowFocusNodes = [];
  List<String> cashOrDebtValues = [];
  List<String> emptiesValues = [];
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
  List<Map<String, String>> _availableDates = [];
  bool _isLoadingDates = false;

  String serialNumber = '';
  // ignore: unused_field
  String? _currentJournalNumber;

  // متغيرات للاقتراحات
  List<String> _materialSuggestions = [];
  List<String> _packagingSuggestions = [];
  List<String> _supplierSuggestions = [];

  List<SuggestionItem> _materialSuggestionItems = [];
  List<SuggestionItem> _packagingSuggestionItems = [];
  List<SuggestionItem> _supplierSuggestionItems = [];

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
  Timer? _calculateRowDebouncer;
  bool _isCalculating = false;
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
      _loadOrCreateJournal();
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
    _materialSuggestionsScrollController.dispose();
    _packagingSuggestionsScrollController.dispose();
    _supplierSuggestionsScrollController.dispose();

    _horizontalSuggestionsController.dispose();
    _addButtonFocusNode?.dispose(); // <-- إضافة

    _balanceTracker.dispose();
    _calculateTotalsDebouncer?.cancel();
    _calculateRowDebouncer?.cancel();
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
        await _storageService.loadPurchaseDocument(widget.selectedDate);

    if (document != null && document.purchases.isNotEmpty) {
      // تحميل اليومية الموجودة
      _loadJournal(document);
    } else {
      // إنشاء يومية جديدة
      _createNewJournal();
    }
  }

  void _resetTotalValues() {
    totalCountController.text = '0';
    totalBaseController.text = '0.00';
    totalNetController.text = '0.00';
    totalGrandController.text = '0.00';
  }

  void _createNewJournal() {
    setState(() {
      rowControllers.clear();
      rowFocusNodes.clear();
      cashOrDebtValues.clear();
      emptiesValues.clear();
      sellerNames.clear();
      _resetTotalValues();
      _hasUnsavedChanges = false;
      _addNewRow();
    });

    // طلب التركيز على زر الإضافة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addButtonFocusNode?.requestFocus(); // <-- إضافة
    });
  }

  void _addNewRow() {
    setState(() {
      final newSerialNumber = (rowControllers.length + 1).toString();

      List<TextEditingController> newControllers =
          List.generate(11, (index) => TextEditingController());

      List<FocusNode> newFocusNodes = List.generate(11, (index) => FocusNode());

      newControllers[0].text = newSerialNumber;

      _addChangeListenersToControllers(newControllers, rowControllers.length);

      sellerNames.add(widget.sellerName);

      rowControllers.add(newControllers);
      rowFocusNodes.add(newFocusNodes);
      cashOrDebtValues.add('');
      emptiesValues.add('');
    });

    _attachFocusListeners(rowControllers.length - 1); // <-- إضافة

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && rowFocusNodes.isNotEmpty) {
        final newRowIndex = rowFocusNodes.length - 1;
        _currentFocusRow = newRowIndex; // <-- إضافة
        _currentFocusCol = 1; // <-- حقل المادة
        FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
        _scrollToField(newRowIndex, 1);
        _adjustScrollPosition(newRowIndex); // <-- إضافة
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
    controllers[4].addListener(() {
      _hasUnsavedChanges = true;
      _updatePackagingSuggestions(rowIndex);
    });

    // الحقول الرقمية مع التحديث التلقائي
    controllers[3].addListener(() {
      _hasUnsavedChanges = true;
      _calculateRowValues(rowIndex);
      _calculateAllTotals();
    });

    controllers[5].addListener(() {
      _hasUnsavedChanges = true;
      _validateStandingAndNet(rowIndex);
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

  void _updatePackagingSuggestions(int rowIndex) async {
    final query = rowControllers[rowIndex][4].text;
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

// اختيار اقتراح للمادة - معدلة تماماً
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

  void _selectPackagingSuggestion(String suggestion, int rowIndex) {
    _hideAllSuggestionsImmediately();
    final actualName = _extractNameFromSuggestion(suggestion);
    rowControllers[rowIndex][4].text = actualName;
    _hasUnsavedChanges = true;
    if (actualName.trim().length > 1) {
      _savePackagingToIndex(actualName);
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][5]);
      }
    });
  }

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

// تعديل _validateStandingAndNet لإعادة الحساب بشكل صحيح
  void _validateStandingAndNet(int rowIndex) {
    if (rowIndex >= rowControllers.length) return;

    final controllers = rowControllers[rowIndex];

    try {
      double standing = double.tryParse(controllers[5].text) ?? 0;
      double net = double.tryParse(controllers[6].text) ?? 0;

      if (standing < net) {
        // إذا كان الصافي أكبر من القائم، نجعل الصافي يساوي القائم
        controllers[6].text = standing.toStringAsFixed(2);
        _showInlineWarning(rowIndex, 'الصافي لا يمكن أن يكون أكبر من القائم');

        // إعادة الحساب فوراً
        _calculateRowValues(rowIndex);
        _calculateAllTotals();
      } else if (standing == 0 && net > 0) {
        // إذا كان القائم صفر، يجب أن يكون الصافي صفر
        controllers[6].text = '0.00';
        _showInlineWarning(
            rowIndex, 'إذا كان القائم صفر، يجب أن يكون الصافي صفر');

        // إعادة الحساب فوراً
        _calculateRowValues(rowIndex);
        _calculateAllTotals();
      }
    } catch (e) {
      // تجاهل الأخطاء في التحليل
    }
  }

  void _calculateRowValues(int rowIndex) {
    if (rowIndex >= rowControllers.length) return;

    final controllers = rowControllers[rowIndex];

    // حساب فوري بدون تأخير للصف الواحد
    try {
      double count = (double.tryParse(controllers[3].text) ?? 0).abs();
      double net = (double.tryParse(controllers[6].text) ?? 0).abs();
      double price = (double.tryParse(controllers[7].text) ?? 0).abs();

      double baseValue = net > 0 ? net : count;
      double total = baseValue * price;

      final newTotal = total.toStringAsFixed(2);
      if (controllers[8].text != newTotal) {
        controllers[8].text = newTotal;
      }
    } catch (e) {
      if (controllers[8].text.isNotEmpty) {
        controllers[8].text = '';
      }
    }
  }

  void _calculateAllTotals() {
    // إلغاء أي حساب سابق منتظر
    _calculateTotalsDebouncer?.cancel();

    // تأخير الحساب لتجنب التكرار المتعدد
    _calculateTotalsDebouncer = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || _isCalculating) return;

      _isCalculating = true;

      double totalCount = 0;
      double totalBase = 0;
      double totalNet = 0;
      double totalGrand = 0;

      for (var controllers in rowControllers) {
        try {
          totalCount += double.tryParse(controllers[3].text) ?? 0;
          totalBase += double.tryParse(controllers[5].text) ?? 0;
          totalNet += double.tryParse(controllers[6].text) ?? 0;
          totalGrand += double.tryParse(controllers[8].text) ?? 0;
        } catch (e) {
          // تجاهل الأخطاء
        }
      }

      if (mounted) {
        setState(() {
          totalCountController.text = totalCount.toStringAsFixed(0);
          totalBaseController.text = totalBase.toStringAsFixed(2);
          totalNetController.text = totalNet.toStringAsFixed(2);
          totalGrandController.text = totalGrand.toStringAsFixed(2);
        });
      }

      _isCalculating = false;
    });
  }

  void _loadJournal(PurchaseDocument document) {
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
      sellerNames.clear();

      for (int i = 0; i < document.purchases.length; i++) {
        var purchase = document.purchases[i];

        List<TextEditingController> newControllers = [
          TextEditingController(text: purchase.serialNumber),
          TextEditingController(text: purchase.material),
          TextEditingController(text: purchase.affiliation),
          TextEditingController(text: purchase.count),
          TextEditingController(text: purchase.packaging),
          TextEditingController(text: purchase.standing),
          TextEditingController(text: purchase.net),
          TextEditingController(text: purchase.price),
          TextEditingController(text: purchase.total),
          TextEditingController(),
          TextEditingController(),
        ];

        List<FocusNode> newFocusNodes =
            List.generate(11, (index) => FocusNode());

        sellerNames.add(purchase.sellerName);

        final bool isOwnedByCurrentSeller =
            purchase.sellerName == widget.sellerName;

        if (isOwnedByCurrentSeller) {
          _addChangeListenersToControllers(newControllers, i);
        }

        rowControllers.add(newControllers);
        rowFocusNodes.add(newFocusNodes);
        cashOrDebtValues.add(purchase.cashOrDebt);
        emptiesValues.add(purchase.empties);
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

    _calculateAllTotals();
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
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            TableComponents.buildTableHeaderCell('مسلسل'),
            TableComponents.buildTableHeaderCell('المادة'),
            TableComponents.buildTableHeaderCell('العائدية'),
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
            _buildTableCell(rowControllers[i][0], rowFocusNodes[i][0], i, 0,
                isOwnedByCurrentSeller),
            _buildMaterialCell(rowControllers[i][1], rowFocusNodes[i][1], i, 1,
                isOwnedByCurrentSeller),
            _buildSupplierCell(rowControllers[i][2], rowFocusNodes[i][2], i, 2,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][3], rowFocusNodes[i][3], i, 3,
                isOwnedByCurrentSeller),
            _buildPackagingCell(rowControllers[i][4], rowFocusNodes[i][4], i, 4,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][5], rowFocusNodes[i][5], i, 5,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][6], rowFocusNodes[i][6], i, 6,
                isOwnedByCurrentSeller),
            _buildTableCell(rowControllers[i][7], rowFocusNodes[i][7], i, 7,
                isOwnedByCurrentSeller),
            TableComponents.buildTotalValueCell(rowControllers[i][8]),
            _buildCashOrDebtCell(i, 9, isOwnedByCurrentSeller),
            _buildEmptiesCell(i, 10, isOwnedByCurrentSeller),
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
      border: TableBorder.all(color: Colors.grey, width: 0.5),
      children: contentRows,
    );
  }

  Widget _buildTableCell(TextEditingController controller, FocusNode focusNode,
      int rowIndex, int colIndex, bool isOwnedByCurrentSeller) {
    final bool enabled = _canEditRow(rowIndex);
    bool isNumericField =
        colIndex == 3 || colIndex == 5 || colIndex == 6 || colIndex == 7;

    return TableBuilder.buildTableCell(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled, // <--- تمرير القيمة هنا لتعطيل الـ TextField
      isSerialField: colIndex == 0,
      isNumericField: isNumericField,
      rowIndex: rowIndex,
      colIndex: colIndex,
      scrollToField: _scrollToField,
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
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
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
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
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
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
      onFieldSubmitted: (value, rIndex, cIndex) =>
          _handleFieldSubmitted(value, rIndex, cIndex),
      onFieldChanged: (value, rIndex, cIndex) =>
          _handleFieldChanged(value, rIndex, cIndex),
    );
  }

  void _handleFieldSubmitted(String value, int rowIndex, int colIndex) {
    if (!_canEditRow(rowIndex)) return;

    // 1. معالجة حقل المادة
    if (colIndex == 1) {
      if (_materialSuggestions.isNotEmpty) {
        _selectMaterialSuggestion(_materialSuggestions[0], rowIndex);
        return; // توقف لمنع تخزين النص الناقص
      }
      if (value.trim().length > 1) _saveMaterialToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][2]);
    }
    // 2. معالجة حقل العائدية (المورد)
    else if (colIndex == 2) {
      if (_supplierSuggestions.isNotEmpty) {
        _selectSupplierSuggestion(_supplierSuggestions[0], rowIndex);
        return; // توقف
      }
      if (value.trim().length > 1) _saveSupplierToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][3]);
    }
    // 3. معالجة حقل العبوة
    else if (colIndex == 4) {
      if (_packagingSuggestions.isNotEmpty) {
        _selectPackagingSuggestion(_packagingSuggestions[0], rowIndex);
        return; // توقف
      }
      if (value.trim().length > 1) _savePackagingToIndex(value);
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][5]);
    }
    // التنقل العادي لبقية الحقول
    else if (colIndex == 0) {
      FocusScope.of(context).requestFocus(rowFocusNodes[rowIndex][1]);
    } else if (colIndex == 7) {
      _showCashOrDebtDialog(rowIndex);
    } else if (colIndex == 10) {
      _addNewRow();
      if (rowControllers.isNotEmpty) {
        final newRowIndex = rowControllers.length - 1;
        FocusScope.of(context).requestFocus(rowFocusNodes[newRowIndex][1]);
      }
    } else if (colIndex < 10) {
      FocusScope.of(context)
          .requestFocus(rowFocusNodes[rowIndex][colIndex + 1]);
    }

    _hideAllSuggestionsImmediately();
  }

  void _handleFieldChanged(String value, int rowIndex, int colIndex) {
    // التحقق إذا كان السجل مملوكاً للبائع الحالي
    if (!_canEditRow(rowIndex)) {
      return; // لا تفعل شيئاً إذا لم يكن السجل مملوكاً للبائع الحالي
    }

    setState(() {
      _hasUnsavedChanges = true;

      if (colIndex == 0) {
        // عند تغيير الرقم المسلسل، ترقيم كل السجلات
        for (int i = 0; i < rowControllers.length; i++) {
          rowControllers[i][0].text = (i + 1).toString();
        }
      }

      // إذا بدأ المستخدم بالكتابة في حقل آخر، إخفاء اقتراحات الحقول الأخرى
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

  Widget _buildCashOrDebtCell(
      int rowIndex, int colIndex, bool isOwnedByCurrentSeller) {
    Widget cell = TableBuilder.buildCashOrDebtCell(
      rowIndex: rowIndex,
      colIndex: colIndex,
      cashOrDebtValue: cashOrDebtValues[rowIndex],
      customerName: '',
      customerController: TextEditingController(),
      focusNode: rowFocusNodes[rowIndex][colIndex],
      hasUnsavedChanges: _hasUnsavedChanges,
      setHasUnsavedChanges: (value) =>
          setState(() => _hasUnsavedChanges = value),
      onTap: () => _showCashOrDebtDialog(rowIndex),
      scrollToField: _scrollToField,
      onCustomerNameChanged: (value) {},
      onCustomerSubmitted: (value, rIndex, cIndex) {},
      isSalesScreen: false,
    );

    // إذا لم يكن السجل مملوكاً للبائع الحالي، جعل الخلية للقراءة فقط
    if (!isOwnedByCurrentSeller) {
      return IgnorePointer(
        child: Opacity(
          opacity: 0.7,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
            ),
            child: cell,
          ),
        ),
      );
    }

    return cell;
  }

  Widget _buildEmptiesCell(
      int rowIndex, int colIndex, bool isOwnedByCurrentSeller) {
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
            decoration: BoxDecoration(
              color: Colors.grey[100],
            ),
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

          // فتح نافذة الفوارغ مباشرة
          if (value == 'نقدي' || value == 'دين') {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _showEmptiesDialog(rowIndex);
              }
            });
          }
        });
      },
      onCancel: () {
        // لا نقوم بأي شيء عند الإلغاء
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
        _addRowAfterEmptiesSelection(rowIndex);
      },
      onCancel: () {},
    );
  }

  void _addRowAfterEmptiesSelection(int rowIndex) {
    _addNewRow();
    if (rowControllers.isNotEmpty) {
      final newRowIndex = rowControllers.length - 1;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(
              rowFocusNodes[newRowIndex][1]); // <-- تغيير من [0] إلى [1]
          _scrollToField(newRowIndex, 1); // <-- تغيير من 0 إلى 1
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
                      'يومية مشتريات رقم /$serialNumber/ تاريخ ${widget.selectedDate} البائع ${widget.sellerName}',
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
                              color: Colors.lightBlueAccent,
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
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        actions: [
          PdfActionMenu(
            type: 'purchases',
            supplierOrCustomerName: 'المشتريات',
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
                    builder: (context) => PurchasesScreen(
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
                              ? Colors.red
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
                  color: Colors.red[700],
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red[700]!.withOpacity(0.45),
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
                    // المورد — فارغ
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

    setState(() => _isSaving = true);

    // 1. تجميع السجلات الحالية من الواجهة التي تخص البائع الحالي فقط
    final List<Purchase> currentSellerPurchasesFromUI = [];
    for (int i = 0; i < rowControllers.length; i++) {
      // فقط السجلات التي يملكها البائع الحالي هي التي يمكن تعديلها وحفظها
      if (sellerNames[i] == widget.sellerName) {
        final controllers = rowControllers[i];
        if (controllers[1].text.isNotEmpty || controllers[3].text.isNotEmpty) {
          double s = double.tryParse(controllers[5].text) ?? 0;
          double n = double.tryParse(controllers[6].text) ?? 0;
          if (s < n) {
            controllers[6].text = s.toStringAsFixed(2);
            _calculateRowValues(i);
          }

          final p = Purchase(
            serialNumber:
                controllers[0].text, // الحفاظ على الرقم التسلسلي المؤقت
            material: controllers[1].text,
            affiliation: controllers[2].text.trim(),
            count: controllers[3].text,
            packaging: controllers[4].text,
            standing: controllers[5].text,
            net: controllers[6].text,
            price: controllers[7].text,
            total: controllers[8].text,
            cashOrDebt: cashOrDebtValues[i],
            empties: emptiesValues[i],
            sellerName: sellerNames[i],
          );
          currentSellerPurchasesFromUI.add(p);
        }
      }
    }

    // 2. منطق تحديث الأرصدة الجديد (الإلغاء ثم التطبيق)
    Map<String, double> supplierBalanceChanges = {};
    final existingDocument =
        await _storageService.loadPurchaseDocument(widget.selectedDate);

    // الخطوة أ: إلغاء أثر جميع ديون البائع القديمة في هذا اليوم
    if (existingDocument != null) {
      for (var oldPurchase in existingDocument.purchases) {
        if (oldPurchase.sellerName == widget.sellerName &&
            oldPurchase.cashOrDebt == 'دين' &&
            oldPurchase.affiliation.isNotEmpty) {
          double oldAmount = double.tryParse(oldPurchase.total) ?? 0;
          supplierBalanceChanges[oldPurchase.affiliation] =
              (supplierBalanceChanges[oldPurchase.affiliation] ?? 0) -
                  oldAmount;
        }
      }
    }

    // الخطوة ب: تطبيق أثر جميع ديون البائع الجديدة من الواجهة
    for (var newPurchase in currentSellerPurchasesFromUI) {
      if (newPurchase.cashOrDebt == 'دين' &&
          newPurchase.affiliation.isNotEmpty) {
        double newAmount = double.tryParse(newPurchase.total) ?? 0;
        supplierBalanceChanges[newPurchase.affiliation] =
            (supplierBalanceChanges[newPurchase.affiliation] ?? 0) + newAmount;
      }
    }

    // 3. بناء الوثيقة النهائية للحفظ
    // هذه الوثيقة تحتوي فقط على سجلات البائع الحالي ليتم دمجها في خدمة التخزين
    final documentToSave = PurchaseDocument(
      recordNumber: serialNumber,
      date: widget.selectedDate,
      sellerName: widget.sellerName, // إرسال اسم البائع الحالي
      storeName: widget.storeName,
      dayName: dayName,
      purchases: currentSellerPurchasesFromUI, // إرسال سجلات البائع الحالي فقط
      totals: {}, // سيتم حساب المجاميع النهائية في خدمة التخزين
    );

    // 4. الحفظ في الملف وتحديث الأرصدة
    // دالة savePurchaseDocument ستقوم بدمج هذه السجلات مع سجلات الباعة الآخرين
    final success = await _storageService.savePurchaseDocument(documentToSave);

    if (success) {
      // تطبيق التغييرات الصافية على أرصدة الموردين
      for (var entry in supplierBalanceChanges.entries) {
        if (entry.value != 0) {
          await _supplierIndexService.updateSupplierBalance(
              entry.key, entry.value);
        }
      }
      setState(() => _hasUnsavedChanges = false);
      await _loadOrCreateJournal(); // تحديث الواجهة والـ sellerNames
    }

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
        serialNumber = '1'; // الرقم الافتراضي
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

  Future<void> _checkAdminStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final adminSeller = prefs.getString('admin_seller');
    if (mounted) {
      setState(() {
        _isAdmin = (widget.sellerName == adminSeller);
      });
    }
  }

// 1. إضافة دالة التحقق من الصلاحية
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

  pw.Widget _buildPdfHeaderCell(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              color: color, fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _buildPdfCell(String text, {bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 8,
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

  // دالة توليد PDF المعدلة
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
      totalCount += double.tryParse(controllers[3].text) ?? 0;
      totalBase += double.tryParse(controllers[5].text) ?? 0;
      totalNet += double.tryParse(controllers[6].text) ?? 0;
      totalGrand += double.tryParse(controllers[8].text) ?? 0;
    }

    final PdfColor headerColor = PdfColor.fromInt(0xFFD32F2F);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor rowOddColor = PdfColor.fromInt(0xFFFFCDD2);
    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);
    final PdfColor totalRowColor = PdfColor.fromInt(0xFFEF9A9A);

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
                      child: pw.Text('يومية مشتريات رقم /$serialNumber/',
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
                      6: const pw.FlexColumnWidth(3),
                      7: const pw.FlexColumnWidth(4),
                      8: const pw.FlexColumnWidth(2),
                      9: const pw.FlexColumnWidth(3),
                      10: const pw.FlexColumnWidth(1),
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
                          _buildPdfHeaderCell('المورد', headerTextColor),
                          _buildPdfHeaderCell('المادة', headerTextColor),
                          _buildPdfHeaderCell('ت', headerTextColor),
                        ],
                      ),
                      ...rowControllers.asMap().entries.map((entry) {
                        final index = entry.key;
                        final controllers = entry.value;
                        if (controllers[1].text.isEmpty &&
                            controllers[3].text.isEmpty) {
                          return pw.TableRow(
                              children: List.filled(11, pw.SizedBox()));
                        }
                        final color =
                            index % 2 == 0 ? rowEvenColor : rowOddColor;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: color),
                          children: [
                            _buildPdfCell(cashOrDebtValues[index]),
                            _buildPdfCell(emptiesValues[index]),
                            _buildPdfCell(controllers[8].text, isBold: true),
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
  // ========== دوال التحكم بالأسهم ==========

  void _attachFocusListeners(int rowIndex) {
    if (rowIndex >= rowFocusNodes.length) return;

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

    // حدود الأعمدة: المادة(1) حتى السعر(7) - لا نذهب إلى المسلسل(0) أو الإجمالي(8) أو نقدي/دين(9) أو الفوارغ(10)
    const int minCol = 1;
    const int maxCol = 7;
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
      final doc = await _storageService.loadPurchaseDocument(dateInfo['date']!);
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
