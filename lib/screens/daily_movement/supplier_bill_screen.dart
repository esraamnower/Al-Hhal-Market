import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // يشمل rootBundle و FilteringTextInputFormatter
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/invoices_service.dart';
import '../../services/supplier_index_service.dart';
import '../../services/supplier_bill_storage_service.dart';
import '../../models/supplier_invoice_model.dart';
import '../../widgets/pdf_action_menu.dart';
import '../../widgets/exit_button.dart';
import '../../services/receipt_storage_service.dart';
import '../../services/box_storage_service.dart'; // استيراد خدمة الصندوق

/// ============================================================================
/// حوار إدخال شرط فاتورة المورد (اسم المورد + س + التاريخ)
/// يُفتح من شاشة نوع التقرير عند الضغط على زر "فاتورة المورد".
/// عند الموافقة ينتقل إلى شاشة محتوى الفاتورة SupplierBillScreen.
/// ============================================================================
class SupplierBillEntryDialog extends StatefulWidget {
  final String selectedDate; // التاريخ المحدد مسبقاً (يُعبّأ تلقائياً)
  final String storeName;
  final String sellerName;

  const SupplierBillEntryDialog({
    Key? key,
    required this.selectedDate,
    required this.storeName,
    required this.sellerName,
  }) : super(key: key);

  @override
  State<SupplierBillEntryDialog> createState() =>
      _SupplierBillEntryDialogState();
}

class _SupplierBillEntryDialogState extends State<SupplierBillEntryDialog> {
  final SupplierIndexService _supplierIndexService = SupplierIndexService();

  final TextEditingController _supplierController = TextEditingController();
  final TextEditingController _sController = TextEditingController();

  final FocusNode _supplierFocus = FocusNode();
  final FocusNode _sFocus = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();

  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _parseDate(widget.selectedDate);
  }

  @override
  void dispose() {
    _supplierController.dispose();
    _sController.dispose();
    _supplierFocus.dispose();
    _sFocus.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  DateTime _parseDate(String dateString) {
    try {
      final parts = dateString.split('/');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return DateTime.now();
  }

  String get _formattedDate =>
      '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}';

  void _updateDate({int? year, int? month, int? day}) {
    final currentYear = year ?? _selectedDate.year;
    final currentMonth = month ?? _selectedDate.month;
    var currentDay = day ?? _selectedDate.day;

    final daysInMonth = DateUtils.getDaysInMonth(currentYear, currentMonth);
    if (currentDay > daysInMonth) currentDay = daysInMonth;
    if (currentDay < 1) currentDay = 1;
    if (currentMonth < 1 || currentMonth > 12) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(currentYear, currentMonth, currentDay);
    });
  }

  Future<void> _confirm() async {
    final supplier = _supplierController.text.trim();
    final sValue = _sController.text.trim();

    if (supplier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال اسم المورد')),
      );
      return;
    }

    final normalizedInput = normalizeArabic(supplier);
    final allSuppliersList = await _supplierIndexService.getAllSuppliers();
    
    // التحقق من المطابقة اللينة للغة العربية للتسهيل على المستخدم
    final matchedSupplierName = allSuppliersList.firstWhere(
      (s) => normalizeArabic(s) == normalizedInput,
      orElse: () => '',
    );

    if (matchedSupplierName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ هذا المورد غير موجود بالفهرس، يرجى اختيار مورد موجود بالفعل')),
      );
      return;
    }

    // معالجة قيمة س: إذا كانت فارغة تصبح "0" تلقائياً
    final cleanS = sValue.isEmpty ? "0" : sValue;
    final parsedS = int.tryParse(cleanS);
    final normalizedS = parsedS != null ? parsedS.toString() : cleanS;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SupplierBillScreen(
          selectedDate: _formattedDate,
          storeName: widget.storeName,
          supplierName: matchedSupplierName, // نمرر الاسم الرسمي الصحيح من الفهرس
          sValue: normalizedS,
          sellerName: widget.sellerName,
        ),
      ),
    );
  }

  // أزرار تقليب التاريخ (بنفس نمط شاشة اختيار التاريخ)
  Widget _buildCompactPicker(
    String label,
    int currentValue,
    VoidCallback onIncrement,
    VoidCallback onDecrement, {
    bool isMonth = false,
  }) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    final String displayValue =
        isMonth ? months[currentValue - 1] : currentValue.toString();

    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_drop_up),
                  onPressed: onIncrement,
                  color: Colors.green[600],
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                SizedBox(
                  height: 26,
                  child: Center(
                    child: Text(
                      displayValue,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: onDecrement,
                  color: Colors.red[600],
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {},
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            toolbarHeight: kToolbarHeight + 20,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 140),
                const Text(
                  'فاتورة المورد - تحديد البيانات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                ExitButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            centerTitle: true,
            backgroundColor: Colors.teal[700],
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // --- حقل اسم المورد مع الإكمال التلقائي ---
                    const Text('اسم المورد',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    RawAutocomplete<String>(
                      textEditingController: _supplierController,
                      focusNode: _supplierFocus,
                      optionsBuilder: (TextEditingValue value) async {
                        if (value.text.trim().isEmpty) {
                          return const Iterable<String>.empty();
                        }
                        return await _supplierIndexService
                            .getEnhancedSuggestions(value.text.trim());
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.next,
                          textDirection: TextDirection.rtl,
                          onSubmitted: (_) {
                            // enter ينقل للحقل التالي (س)
                            onFieldSubmitted();
                            FocusScope.of(context).requestFocus(_sFocus);
                          },
                          decoration: _fieldDecoration('اكتب اسم المورد أو رقمه'),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topRight,
                          child: Material(
                            elevation: 4,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxHeight: 180, maxWidth: 320),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () {
                                      onSelected(option);
                                      FocusScope.of(context)
                                          .requestFocus(_sFocus);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      alignment: Alignment.centerRight,
                                      child: Text(option,
                                          textDirection: TextDirection.rtl),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // --- حقل س (أرقام وفواصل فقط) ---
                    const Text('س',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _sController,
                      focusNode: _sFocus,
                      textDirection: TextDirection.rtl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        // أرقام وفواصل رقمية فقط
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _confirm(),
                      decoration: _fieldDecoration('قيمة س'),
                    ),
                    const SizedBox(height: 16),

                    // --- التاريخ بأزرار التقليب ---
                    const Text('التاريخ',
                        style:
                            TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildCompactPicker(
                            'اليوم',
                            _selectedDate.day,
                            () => _updateDate(day: _selectedDate.day + 1),
                            () => _updateDate(day: _selectedDate.day - 1),
                          ),
                          _buildCompactPicker(
                            'الشهر',
                            _selectedDate.month,
                            () => _updateDate(month: _selectedDate.month + 1),
                            () => _updateDate(month: _selectedDate.month - 1),
                            isMonth: true,
                          ),
                          _buildCompactPicker(
                            'السنة',
                            _selectedDate.year,
                            () => _updateDate(year: _selectedDate.year + 1),
                            () => _updateDate(year: _selectedDate.year - 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- زرّا الإلغاء والموافقة ---
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red[700],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.red.shade300),
                            ),
                            child: const Text('إلغاء الأمر',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _confirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('موافق',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
    );
  }
}

/// ============================================================================
/// شاشة محتوى فاتورة المورد (تظهر بعد الموافقة على حوار الإدخال)
/// تشبه شاشة مبيعات المورد لكنها مستقلة ومحسّنة وفق طلب المحاسب.
/// ============================================================================
class SupplierBillScreen extends StatefulWidget {
  final String selectedDate;
  final String storeName;
  final String supplierName;
  final String sValue;
  final String sellerName;

  const SupplierBillScreen({
    Key? key,
    required this.selectedDate,
    required this.storeName,
    required this.supplierName,
    required this.sValue,
    required this.sellerName,
  }) : super(key: key);

  @override
  State<SupplierBillScreen> createState() => _SupplierBillScreenState();
}

class _SupplierBillScreenState extends State<SupplierBillScreen> {
  final InvoicesService _invoicesService = InvoicesService();
  final SupplierBillStorageService _billStorage = SupplierBillStorageService();

  late Future<SupplierInvoice> _invoiceFuture;
  SupplierInvoice? _invoice;
  bool _isLoading = true;

  // نسبة المعلوم وقيمة العتالة قابلة للكتابة
  final TextEditingController _maloomPercentController =
      TextEditingController();
  final FocusNode _maloomPercentFocusNode = FocusNode();

  // معلومات الفاتورة المحفوظة (إن وُجدت)
  SupplierBill? _savedBill;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _invoiceFuture = _loadInvoice().then((val) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return val;
    }).catchError((err, st) {
      debugPrint('❌ Error in initState loadInvoice: $err\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      throw err;
    });
  }

  @override
  void dispose() {
    _maloomPercentController.dispose();
    _maloomPercentFocusNode.dispose();
    super.dispose();
  }

  DateTime _parseDate(String dateString) {
    try {
      final parts = dateString.split('/');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return DateTime.now();
  }

  String _getArabicDayName(DateTime date) {
    final days = [
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    return days[date.weekday - 1];
  }

  String _extractDayName(String dateString) {
    final date = _parseDate(dateString);
    return _getArabicDayName(date);
  }

  Future<SupplierInvoice> _loadInvoice() async {
    try {
      final invoice = await _invoicesService.generateSupplierInvoice(
        widget.selectedDate,
        widget.supplierName,
        widget.sValue,
      );
      _invoice = invoice;

      // تحميل الفاتورة المحفوظة إن وجدت
      final saved = await _billStorage.loadBill(
        widget.selectedDate,
        widget.supplierName,
        widget.sValue,
      );
      if (saved != null) {
        _savedBill = saved;
        invoice.maloomPercent = saved.maloomPercent;
        invoice.maloomValue = saved.maloomValue;
        invoice.loadValue = saved.loadValue;
        invoice.paymentValue = saved.paymentValue;
        invoice.portageValue = saved.portageValue; // <-- العتالة من الفاتورة المحفوظة
        _maloomPercentController.text = saved.maloomPercent.toStringAsFixed(2);
      } else {
        _maloomPercentController.text = '';
      }

      debugPrint('✅ تم تحميل فاتورة المورد بنجاح');
      return invoice;
    } catch (e, st) {
      debugPrint('❌ خطأ في تحميل فاتورة المورد: $e\n$st');
      // إنشاء نموذج فارغ لتجنب تعليق الشاشة
      final fallbackInvoice = SupplierInvoice(
        supplierName: widget.supplierName,
        sValue: widget.sValue,
        date: widget.selectedDate,
        groupedSales: [],
        comparison: [],
        totalSalesValue: 0,
      );
      _invoice = fallbackInvoice;
      return fallbackInvoice;
    }
  }

  void _recalculateMaloom() {
    final invoice = _invoice;
    if (invoice == null || _savedBill != null) return;
    final percent = double.tryParse(_maloomPercentController.text) ?? 0;
    setState(() {
      invoice.maloomPercent = percent;
      invoice.maloomValue =
          _invoicesService.calculateMaloom(invoice.totalSalesValue, percent);
    });
  }



  Future<void> _saveBill() async {
    final invoice = _invoice;
    if (invoice == null) return;

    setState(() => _saving = true);

    final billNumber = await _billStorage.saveBill(
      date: widget.selectedDate,
      supplierName: widget.supplierName,
      sValue: widget.sValue,
      totalSalesValue: invoice.totalSalesValue,
      maloomPercent: invoice.maloomPercent,
      maloomValue: invoice.maloomValue,
      loadValue: invoice.loadValue,
      paymentValue: invoice.paymentValue,
      portageValue: invoice.portageValue, // <-- إضافة العتالة
      totalExpenses: invoice.totalExpenses,
      netInvoice: invoice.netInvoice,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (billNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ هذه الفاتورة موجودة مسبقاً ولا يمكن إنشاؤها مرتين'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // تسجيل العتالة في الصندوق إذا كانت أكبر من 0
    if (invoice.portageValue > 0) {
      await BoxStorageService().addPortageEntry(
        date: widget.selectedDate,
        supplierName: widget.supplierName,
        portageValue: invoice.portageValue,
        sellerName: widget.sellerName,
        storeName: widget.storeName,
        dayName: _extractDayName(widget.selectedDate),
        notes: 'عتالة فاتورة المورد ${widget.supplierName} رقم الفاتورة $billNumber',
      );
    }

    final saved = await _billStorage.loadBill(
      widget.selectedDate,
      widget.supplierName,
      widget.sValue,
    );
    setState(() => _savedBill = saved);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ تم حفظ الفاتورة رقم $billNumber وتم تسجيل العتالة بالصندوق'),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  Future<void> _deleteBill() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الفاتورة'),
          content: const Text(
              'سيؤدي الحذف إلى فتح التعديل على المبيعات والاستلام التابعة لها. هل تريد المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final String? billNumToDelete = _savedBill?.billNumber;

    final success = await _billStorage.deleteBill(
      widget.selectedDate,
      widget.supplierName,
      widget.sValue,
    );

    if (!mounted) return;
    if (success) {
      // حذف حركة العتالة المرتبطة من الصندوق
      if (billNumToDelete != null) {
        await BoxStorageService().deletePortageEntry(
          date: widget.selectedDate,
          notesPattern: 'رقم الفاتورة $billNumToDelete',
        );
      }

      setState(() {
        _savedBill = null;
        _maloomPercentController.text = '';
        _isLoading = true;
      });

      // إعادة تحميل الفاتورة الافتراضية
      final freshInvoice = await _loadInvoice();
      if (mounted) {
        setState(() {
          _invoice = freshInvoice;
          _isLoading = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ تم حذف الفاتورة وإلغاء العتالة من الصندوق'),
          backgroundColor: Colors.green[700],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❌ فشل حذف الفاتورة'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  // التاريخ بصيغة:  التاريخ  •  س
  String get _headerLine =>
      'التاريخ: ${widget.selectedDate}   •   س: ${widget.sValue}';

  Future<Uint8List> _generatePdfBytes(SupplierInvoice invoice) async {
    final pdf = pw.Document();

    var arabicFont;
    try {
      final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
      arabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      arabicFont = pw.Font.courier();
    }

    double salesTotalCount = 0,
        salesTotalStanding = 0,
        salesTotalNet = 0,
        salesTotalValue = 0;
    for (var line in invoice.groupedSales) {
      salesTotalCount += line.totalCount;
      salesTotalStanding += line.totalStanding;
      salesTotalNet += line.totalNet;
      salesTotalValue += line.totalValue;
    }

    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor salesHeader = PdfColor.fromInt(0xFF5C6BC0);
    final PdfColor salesRowOdd = PdfColor.fromInt(0xFFE8EAF6);
    final PdfColor salesTotalRow = PdfColor.fromInt(0xFFC5CAE9);
    final PdfColor salesGrandColor = PdfColor.fromInt(0xFF283593);
    final PdfColor summaryHeader = PdfColor.fromInt(0xFFFFA726);
    final PdfColor summaryRowOdd = PdfColor.fromInt(0xFFFFF3E0);

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
                      child: pw.Text('فاتورة المورد ${widget.supplierName}',
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text(_headerLine,
                          style: const pw.TextStyle(
                              fontSize: 14, color: PdfColors.grey700))),
                  pw.SizedBox(height: 15),

                  // جدول المبيعات المجمّع (بدون عنوان "المبيعات المجمّعة")
                  if (invoice.groupedSales.isNotEmpty) ...[
                    pw.Table(
                      border:
                          pw.TableBorder.all(color: borderColor, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(2),
                        4: const pw.FlexColumnWidth(2),
                        5: const pw.FlexColumnWidth(4),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: salesHeader),
                          children: [
                            _buildPdfHeaderCell('الإجمالي', headerTextColor),
                            _buildPdfHeaderCell('السعر', headerTextColor),
                            _buildPdfHeaderCell('الصافي', headerTextColor),
                            _buildPdfHeaderCell('القائم', headerTextColor),
                            _buildPdfHeaderCell('العدد', headerTextColor),
                            _buildPdfHeaderCell('المادة', headerTextColor),
                          ],
                        ),
                        ...invoice.groupedSales.asMap().entries.map((entry) {
                          final index = entry.key;
                          final line = entry.value;
                          final color =
                              index % 2 == 0 ? rowEvenColor : salesRowOdd;
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: color),
                            children: [
                              _buildPdfCell(line.totalValue.toStringAsFixed(2),
                                  textColor: salesGrandColor, isBold: true),
                              _buildPdfCell(line.price),
                              _buildPdfCell(line.totalNet.toStringAsFixed(2)),
                              _buildPdfCell(
                                  line.totalStanding.toStringAsFixed(2)),
                              _buildPdfCell(line.totalCount.toStringAsFixed(0)),
                              _buildPdfCell(line.material),
                            ],
                          );
                        }).toList(),
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: salesTotalRow),
                          children: [
                            _buildPdfCell(salesTotalValue.toStringAsFixed(2),
                                textColor: salesGrandColor, isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(salesTotalNet.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(salesTotalStanding.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(salesTotalCount.toStringAsFixed(0),
                                isBold: true),
                            _buildPdfCell('المجموع', isBold: true),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                  ],

                  // جدول المقارنة
                  if (invoice.comparison.isNotEmpty) ...[
                    _buildPdfSectionTitle(
                        'الاستلام - المبيعات', PdfColor.fromInt(0xFFEF6C00)),
                    pw.Table(
                      border:
                          pw.TableBorder.all(color: borderColor, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(4),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: summaryHeader),
                          children: [
                            _buildPdfHeaderCell('البايت', PdfColors.black),
                            _buildPdfHeaderCell(
                                'صادر (مبيعات)', PdfColors.black),
                            _buildPdfHeaderCell(
                                'وارد (استلام)', PdfColors.black),
                            _buildPdfHeaderCell('المادة', PdfColors.black),
                          ],
                        ),
                        ...invoice.comparison.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final color =
                              index % 2 == 0 ? rowEvenColor : summaryRowOdd;
                          final balanceColor = item.difference >= 0
                              ? PdfColor.fromInt(0xFF2E7D32)
                              : PdfColor.fromInt(0xFFC62828);
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: color),
                            children: [
                              _buildPdfCell(item.difference.toStringAsFixed(0),
                                  textColor: balanceColor, isBold: true),
                              _buildPdfCell(item.salesCount.toStringAsFixed(0)),
                              _buildPdfCell(
                                  item.receiptCount.toStringAsFixed(0)),
                              _buildPdfCell(item.material),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                  ],

                  // لوحة المصاريف والصافي
                  _buildPdfSectionTitle(
                      'المصاريف والصافي', PdfColor.fromInt(0xFF455A64)),
                  pw.Table(
                    border: pw.TableBorder.all(color: borderColor, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(3),
                    },
                    children: [
                      _buildPdfSummaryRow('إجمالي المبيعات',
                          invoice.totalSalesValue.toStringAsFixed(2)),
                      _buildPdfSummaryRow(
                          'المعلوم (${invoice.maloomPercent.toStringAsFixed(2)}%)',
                          invoice.maloomValue.toStringAsFixed(2)),
                      _buildPdfSummaryRow(
                          'الدفعة', invoice.paymentValue.toStringAsFixed(2)),
                      _buildPdfSummaryRow(
                          'الحمولة', invoice.loadValue.toStringAsFixed(2)),
                      _buildPdfSummaryRow(
                          'العتالة', invoice.portageValue.toStringAsFixed(2)),
                      _buildPdfSummaryRow('إجمالي المصاريف',
                          invoice.totalExpenses.toStringAsFixed(2),
                          isBold: true),
                      _buildPdfSummaryRow('صافي الفاتورة',
                          invoice.netInvoice.toStringAsFixed(2),
                          isBold: true,
                          valueColor: PdfColor.fromInt(0xFF1B5E20)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF00695C),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'صافي الفاتورة فقط ${invoice.netInvoice.toStringAsFixed(2)} ل.س',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
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

  // --- دوال مساعدة للـ PDF ---
  pw.Widget _buildPdfSectionTitle(String title, PdfColor bgColor) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      margin: const pw.EdgeInsets.only(bottom: 5),
      decoration: pw.BoxDecoration(
        color: bgColor,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Center(
        child: pw.Text(
          title,
          style: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 12,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      ),
    );
  }

  pw.Widget _buildPdfHeaderCell(String text, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold, color: color, fontSize: 10),
      ),
    );
  }

  pw.Widget _buildPdfCell(String text,
      {PdfColor textColor = PdfColors.black, bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.TableRow _buildPdfSummaryRow(String label, String value,
      {bool isBold = false, PdfColor valueColor = PdfColors.black}) {
    return pw.TableRow(
      children: [
        _buildPdfCell(value, textColor: valueColor, isBold: isBold),
        _buildPdfCell(label, isBold: isBold),
      ],
    );
  }

  // --- دوال بناء الواجهة UI ---
  Widget _buildHeaderCell(String text, int flex, {Color color = Colors.white}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style:
            TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12),
      ),
    );
  }

  Widget _buildDataCell(String text, int flex,
      {Color color = Colors.black87,
      FontWeight fontWeight = FontWeight.normal}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: fontWeight, fontSize: 12),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color bgColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(top: 16, bottom: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        title,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        textAlign: TextAlign.right,
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'فاتورة المورد ${widget.supplierName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        leadingWidth: 100,
        leading: ExitButton(
          onPressed: () => Navigator.of(context).pop(),
          width: 80,
          height: 40,
          text: 'خروج',
        ),
        actions: [
          PdfActionMenu(
            type: 'supplier',
            supplierOrCustomerName: widget.supplierName,
            filterDesc: widget.selectedDate,
            balance: null,
            storeName: widget.storeName,
            selectedDate: widget.selectedDate,
            iconSize: 60,
            getItems: () async {
              final data = await _invoiceFuture;
              return [data];
            },
            generatePdfCallback: (items) async {
              final data = items[0] as SupplierInvoice;
              return _generatePdfBytes(data);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              _headerLine,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: _isLoading || _invoice == null
            ? const Center(child: CircularProgressIndicator())
            : Builder(
                builder: (context) {
                  final invoice = _invoice!;
                  final bool hasSales = invoice.groupedSales.isNotEmpty;
                  final bool hasComparison = invoice.comparison.isNotEmpty;

                  if (!hasSales && !hasComparison) {
                    return const Center(
                      child: Text(
                        'لا توجد حركات لهذا المورد وفق الشرط المحدد',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    );
                  }

                  double salesTotalCount = 0;
                  double salesTotalStanding = 0;
                  double salesTotalNet = 0;
                  double salesTotalValue = 0;
                  for (var line in invoice.groupedSales) {
                    salesTotalCount += line.totalCount;
                    salesTotalStanding += line.totalStanding;
                    salesTotalNet += line.totalNet;
                    salesTotalValue += line.totalValue;
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [


                        // --- جدول المبيعات المجمّع (بدون عنوان "المبيعات المجمّعة") ---
                        if (hasSales) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.indigo.shade200),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  color: Colors.indigo.shade400,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      _buildHeaderCell('المادة', 4),
                                      _buildHeaderCell('العدد', 2),
                                      _buildHeaderCell('القائم', 2),
                                      _buildHeaderCell('الصافي', 2),
                                      _buildHeaderCell('السعر', 2),
                                      _buildHeaderCell('الإجمالي', 3),
                                    ],
                                  ),
                                ),
                                ...invoice.groupedSales.map((line) => Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                            bottom: BorderSide(
                                                color: Colors.grey.shade300)),
                                      ),
                                      child: Row(
                                        children: [
                                          _buildDataCell(line.material, 4),
                                          _buildDataCell(
                                              line.totalCount.toStringAsFixed(0), 2),
                                          _buildDataCell(
                                              line.totalStanding.toStringAsFixed(2),
                                              2),
                                          _buildDataCell(
                                              line.totalNet.toStringAsFixed(2), 2),
                                          _buildDataCell(line.price, 2),
                                          _buildDataCell(
                                              line.totalValue.toStringAsFixed(2), 3,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.indigo),
                                        ],
                                      ),
                                    )),
                                Container(
                                  color: Colors.indigo.shade100,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      _buildDataCell('المجموع', 4,
                                          fontWeight: FontWeight.bold),
                                      _buildDataCell(
                                          salesTotalCount.toStringAsFixed(0), 2,
                                          fontWeight: FontWeight.bold),
                                      _buildDataCell(
                                          salesTotalStanding.toStringAsFixed(2), 2,
                                          fontWeight: FontWeight.bold),
                                      _buildDataCell(
                                          salesTotalNet.toStringAsFixed(2), 2,
                                          fontWeight: FontWeight.bold),
                                      _buildDataCell('', 2),
                                      _buildDataCell(
                                          salesTotalValue.toStringAsFixed(2), 3,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // --- جدول المقارنة ---
                        if (hasComparison) ...[
                          _buildSectionTitle(
                              'الاستلام - المبيعات', Colors.orange[800]!),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.orange.shade200),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  color: Colors.orange.shade300,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    children: [
                                      _buildHeaderCell('المادة', 4,
                                          color: Colors.black87),
                                      _buildHeaderCell('وارد (استلام)', 2,
                                          color: Colors.black87),
                                      _buildHeaderCell('صادر (مبيعات)', 2,
                                          color: Colors.black87),
                                      _buildHeaderCell('البايت', 2,
                                          color: Colors.black87),
                                    ],
                                  ),
                                ),
                                ...invoice.comparison.map((item) => Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                            bottom: BorderSide(
                                                color: Colors.grey.shade300)),
                                      ),
                                      child: Row(
                                        children: [
                                          _buildDataCell(item.material, 4),
                                          _buildDataCell(
                                              item.receiptCount.toStringAsFixed(0),
                                              2),
                                          _buildDataCell(
                                              item.salesCount.toStringAsFixed(0), 2),
                                          _buildDataCell(
                                            item.difference.toStringAsFixed(0),
                                            2,
                                            fontWeight: FontWeight.bold,
                                            color: item.difference >= 0
                                                ? Colors.green[800]!
                                                : Colors.red[800]!,
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                        ],

                        // --- لوحة المصاريف (تنسيق أفقي احترافي) ---
                        _buildExpensesRow(invoice),

                        // --- صافي الفاتورة (في نهاية الشاشة) ---
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16.0),
                          margin: const EdgeInsets.only(top: 16.0),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'صافي الفاتورة فقط ${invoice.netInvoice.toStringAsFixed(2)} ل.س',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // --- أزرار حفظ / حذف الفاتورة ---
                        if (_savedBill == null)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _saveBill,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('حفظ الفاتورة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _deleteBill,
                              icon: const Icon(Icons.delete),
                              label: const Text('حذف الفاتورة'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildExpensesRow(SupplierInvoice invoice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          _buildExpenseItem(
            label: 'المعلوم %',
            value: invoice.maloomPercent.toStringAsFixed(2),
            isEditable: _savedBill == null,
            controller: _maloomPercentController,
            focusNode: _maloomPercentFocusNode,
            onChanged: (_) => _recalculateMaloom(),
          ),
          _buildExpenseItem(
            label: 'الدفعة',
            value: invoice.paymentValue.toStringAsFixed(2),
            isEditable: false,
          ),
          _buildExpenseItem(
            label: 'الحمولة',
            value: invoice.loadValue.toStringAsFixed(2),
            isEditable: false,
          ),
          _buildExpenseItem(
            label: 'العتالة',
            value: invoice.portageValue.toStringAsFixed(2),
            isEditable: false,
          ),
          _buildExpenseItem(
            label: 'المصاريف',
            value: invoice.totalExpenses.toStringAsFixed(2),
            isEditable: false,
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseItem({
    required String label,
    required String value,
    bool isEditable = false,
    TextEditingController? controller,
    FocusNode? focusNode,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(minWidth: 80),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isEditable ? Colors.white : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isEditable ? Colors.blueGrey.shade300 : Colors.grey.shade300,
            ),
          ),
          child: isEditable && controller != null
              ? SizedBox(
                  width: 80,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
        ),
      ],
    );
  }
}
