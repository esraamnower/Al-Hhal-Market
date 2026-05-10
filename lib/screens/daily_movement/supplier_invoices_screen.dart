import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../services/invoices_service.dart';
import '../../services/supplier_index_service.dart';
import '../../widgets/pdf_action_menu.dart';
import 'package:flutter/services.dart';

class SupplierInvoicesScreen extends StatefulWidget {
  final String selectedDate;
  final String storeName;
  final String supplierName;

  const SupplierInvoicesScreen({
    Key? key,
    required this.selectedDate,
    required this.storeName,
    required this.supplierName,
  }) : super(key: key);

  @override
  _SupplierInvoicesScreenState createState() => _SupplierInvoicesScreenState();
}

class _SupplierInvoicesScreenState extends State<SupplierInvoicesScreen> {
  final InvoicesService _invoicesService = InvoicesService();
  final SupplierIndexService _supplierIndexService = SupplierIndexService();
  late Future<SupplierReportData> _reportDataFuture;
  double? _supplierBalance;

  @override
  void initState() {
    super.initState();
    _reportDataFuture = _invoicesService.getSupplierReport(
        widget.selectedDate, widget.supplierName);
    _loadSupplierBalance();
  }

  Future<void> _loadSupplierBalance() async {
    final allSuppliers = await _supplierIndexService.getAllSuppliersWithData();
    for (var entry in allSuppliers.entries) {
      if (entry.value.name.toLowerCase() ==
          widget.supplierName.trim().toLowerCase()) {
        if (mounted) {
          setState(() {
            _supplierBalance = entry.value.balance;
          });
        }
        return;
      }
    }
  }

  Future<Uint8List> _generatePdfBytes(SupplierReportData data) async {
    final pdf = pw.Document();

    var arabicFont;
    try {
      final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
      arabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      arabicFont = pw.Font.courier();
    }

    // حساب المجاميع
    double salesTotalStanding = 0,
        salesTotalNet = 0,
        salesTotalCount = 0,
        salesTotalGrand = 0;
    for (var item in data.sales) {
      salesTotalStanding += double.tryParse(item.standing) ?? 0;
      salesTotalNet += double.tryParse(item.net) ?? 0;
      salesTotalCount += double.tryParse(item.count) ?? 0;
      salesTotalGrand += double.tryParse(item.total) ?? 0;
    }

    double receiptTotalCount = 0,
        receiptTotalStanding = 0,
        receiptTotalPayment = 0,
        receiptTotalLoad = 0;
    for (var item in data.receipts) {
      receiptTotalCount += double.tryParse(item.count) ?? 0;
      receiptTotalStanding += double.tryParse(item.standing) ?? 0;
      receiptTotalPayment += double.tryParse(item.payment) ?? 0;
      receiptTotalLoad += double.tryParse(item.load) ?? 0;
    }

    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor salesHeader = PdfColor.fromInt(0xFF5C6BC0);
    final PdfColor salesRowOdd = PdfColor.fromInt(0xFFE8EAF6);
    final PdfColor salesTotalRow = PdfColor.fromInt(0xFFC5CAE9);
    final PdfColor salesGrandColor = PdfColor.fromInt(0xFF283593);
    final PdfColor receiptHeader = PdfColor.fromInt(0xFF66BB6A);
    final PdfColor receiptRowOdd = PdfColor.fromInt(0xFFE8F5E9);
    final PdfColor receiptTotalRow = PdfColor.fromInt(0xFFC8E6C9);
    final PdfColor summaryHeader = PdfColor.fromInt(0xFFFFA726);
    final PdfColor summaryRowOdd = PdfColor.fromInt(0xFFFFF3E0);

    final String balanceTextPdf =
        _supplierBalance != null ? _supplierBalance!.toStringAsFixed(2) : '---';

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
                      child: pw.Text('مبيعات المورد ${widget.supplierName}',
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text('بتاريخ ${widget.selectedDate}',
                          style: const pw.TextStyle(
                              fontSize: 14, color: PdfColors.grey700))),
                  pw.SizedBox(height: 15),

                  // جدول المبيعات
                  if (data.sales.isNotEmpty) ...[
                    _buildPdfSectionTitle('المبيعات', salesGrandColor),
                    pw.Table(
                      border:
                          pw.TableBorder.all(color: borderColor, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(3),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(2),
                        4: const pw.FlexColumnWidth(2),
                        5: const pw.FlexColumnWidth(3),
                        6: const pw.FlexColumnWidth(2),
                        7: const pw.FlexColumnWidth(1),
                        8: const pw.FlexColumnWidth(4),
                        9: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: salesHeader),
                          children: [
                            _buildPdfHeaderCell('الزبون', headerTextColor),
                            _buildPdfHeaderCell('الإجمالي', headerTextColor),
                            _buildPdfHeaderCell('السعر', headerTextColor),
                            _buildPdfHeaderCell('الصافي', headerTextColor),
                            _buildPdfHeaderCell('القائم', headerTextColor),
                            _buildPdfHeaderCell('العبوة', headerTextColor),
                            _buildPdfHeaderCell('العدد', headerTextColor),
                            _buildPdfHeaderCell('س', headerTextColor),
                            _buildPdfHeaderCell('المادة', headerTextColor),
                            _buildPdfHeaderCell('ت', headerTextColor),
                          ],
                        ),
                        ...data.sales.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final color =
                              index % 2 == 0 ? rowEvenColor : salesRowOdd;
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: color),
                            children: [
                              _buildPdfCell(item.customerName ?? '-'),
                              _buildPdfCell(item.total,
                                  textColor: salesGrandColor, isBold: true),
                              _buildPdfCell(item.price),
                              _buildPdfCell(item.net),
                              _buildPdfCell(item.standing),
                              _buildPdfCell(item.packaging),
                              _buildPdfCell(item.count),
                              _buildPdfCell(item.sValue),
                              _buildPdfCell(item.material),
                              _buildPdfCell(item.serialNumber),
                            ],
                          );
                        }).toList(),
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: salesTotalRow),
                          children: [
                            _buildPdfCell(''),
                            _buildPdfCell(salesTotalGrand.toStringAsFixed(2),
                                textColor: salesGrandColor, isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(salesTotalNet.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(salesTotalStanding.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(salesTotalCount.toStringAsFixed(0),
                                isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(''),
                            _buildPdfCell('م', isBold: true),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                  ],

                  // جدول الاستلام
                  if (data.receipts.isNotEmpty) ...[
                    _buildPdfSectionTitle(
                        'الاستلام', PdfColor.fromInt(0xFF388E3C)),
                    pw.Table(
                      border:
                          pw.TableBorder.all(color: borderColor, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(3),
                        4: const pw.FlexColumnWidth(2),
                        5: const pw.FlexColumnWidth(1),
                        6: const pw.FlexColumnWidth(4),
                        7: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: receiptHeader),
                          children: [
                            _buildPdfHeaderCell('الحمولة', headerTextColor),
                            _buildPdfHeaderCell('الدفعة', headerTextColor),
                            _buildPdfHeaderCell('القائم', headerTextColor),
                            _buildPdfHeaderCell('العبوة', headerTextColor),
                            _buildPdfHeaderCell('العدد', headerTextColor),
                            _buildPdfHeaderCell('س', headerTextColor),
                            _buildPdfHeaderCell('المادة', headerTextColor),
                            _buildPdfHeaderCell('ت', headerTextColor),
                          ],
                        ),
                        ...data.receipts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final color =
                              index % 2 == 0 ? rowEvenColor : receiptRowOdd;
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: color),
                            children: [
                              _buildPdfCell(item.load),
                              _buildPdfCell(item.payment),
                              _buildPdfCell(item.standing),
                              _buildPdfCell(item.packaging),
                              _buildPdfCell(item.count),
                              _buildPdfCell(item.sValue),
                              _buildPdfCell(item.material),
                              _buildPdfCell(item.serialNumber),
                            ],
                          );
                        }).toList(),
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: receiptTotalRow),
                          children: [
                            _buildPdfCell(receiptTotalLoad.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(
                                receiptTotalPayment.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(
                                receiptTotalStanding.toStringAsFixed(2),
                                isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(receiptTotalCount.toStringAsFixed(0),
                                isBold: true),
                            _buildPdfCell(''),
                            _buildPdfCell(''),
                            _buildPdfCell('م', isBold: true),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 20),
                  ],

                  // جدول الملخص
                  if (data.summary.isNotEmpty) ...[
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
                        ...data.summary.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final color =
                              index % 2 == 0 ? rowEvenColor : summaryRowOdd;
                          final balanceColor = item.balance >= 0
                              ? PdfColor.fromInt(0xFF2E7D32)
                              : PdfColor.fromInt(0xFFC62828);
                          return pw.TableRow(
                            decoration: pw.BoxDecoration(color: color),
                            children: [
                              _buildPdfCell(item.balance.toStringAsFixed(0),
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
                  ],

                  pw.SizedBox(height: 20),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFE65100),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        'الرصيد : $balanceTextPdf',
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

  // --- دوال بناء الواجهة UI (تبقى كما هي) ---
  Widget _buildHeaderCell(String text, int flex, {Color color = Colors.white}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 12,
        ),
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
        style: TextStyle(
          color: color,
          fontWeight: fontWeight,
          fontSize: 12,
        ),
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
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'مبيعات المورد ${widget.supplierName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          PdfActionMenu(
            type: 'supplier',
            supplierOrCustomerName: widget.supplierName,
            filterDesc: widget.selectedDate,
            balance: _supplierBalance,
            storeName: widget.storeName,
            selectedDate: widget.selectedDate,
            iconSize: 60,
            getItems: () async {
              final data = await _reportDataFuture;
              return [data]; // نمرر كائن التقرير كاملاً
            },
            generatePdfCallback: (items) async {
              final data = items[0] as SupplierReportData;
              return _generatePdfBytes(data);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'بتاريخ ${widget.selectedDate}',
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
        child: FutureBuilder<SupplierReportData>(
          future: _reportDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('حدث خطأ: ${snapshot.error}'));
            }

            if (!snapshot.hasData) {
              return const Center(child: Text('لا توجد بيانات'));
            }

            final data = snapshot.data!;
            final bool hasSales = data.sales.isNotEmpty;
            final bool hasReceipts = data.receipts.isNotEmpty;
            final bool hasSummary = data.summary.isNotEmpty;

            if (!hasSales && !hasReceipts && !hasSummary) {
              return const Center(
                child: Text(
                  'لا توجد حركات لهذا المورد في اليوم المحدد',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            // --- حساب مجاميع المبيعات UI ---
            double salesTotalStanding = 0;
            double salesTotalNet = 0;
            double salesTotalCount = 0;
            double salesTotalGrand = 0;
            if (hasSales) {
              for (var item in data.sales) {
                salesTotalStanding += double.tryParse(item.standing) ?? 0;
                salesTotalNet += double.tryParse(item.net) ?? 0;
                salesTotalCount += double.tryParse(item.count) ?? 0;
                salesTotalGrand += double.tryParse(item.total) ?? 0;
              }
            }

            // --- حساب مجاميع الاستلام UI ---
            double receiptTotalCount = 0;
            double receiptTotalStanding = 0;
            double receiptTotalPayment = 0;
            double receiptTotalLoad = 0;
            if (hasReceipts) {
              for (var item in data.receipts) {
                receiptTotalCount += double.tryParse(item.count) ?? 0;
                receiptTotalStanding += double.tryParse(item.standing) ?? 0;
                receiptTotalPayment += double.tryParse(item.payment) ?? 0;
                receiptTotalLoad += double.tryParse(item.load) ?? 0;
              }
            }

            final String balanceText = _supplierBalance != null
                ? _supplierBalance!.toStringAsFixed(2)
                : '---';

            return SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // --- جدول المبيعات ---
                  if (hasSales) ...[
                    _buildSectionTitle('المبيعات', Colors.indigo),
                    Container(
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
                                _buildHeaderCell('ت', 1),
                                _buildHeaderCell('المادة', 4),
                                _buildHeaderCell('س', 1),
                                _buildHeaderCell('العدد', 2),
                                _buildHeaderCell('العبوة', 3),
                                _buildHeaderCell('القائم', 2),
                                _buildHeaderCell('الصافي', 2),
                                _buildHeaderCell('السعر', 2),
                                _buildHeaderCell('الإجمالي', 3),
                                _buildHeaderCell('الزبون', 3),
                              ],
                            ),
                          ),
                          ...data.sales.map((item) => Container(
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
                                    _buildDataCell(item.serialNumber, 1),
                                    _buildDataCell(item.material, 4),
                                    _buildDataCell(item.sValue, 1),
                                    _buildDataCell(item.count, 2),
                                    _buildDataCell(item.packaging, 3),
                                    _buildDataCell(item.standing, 2),
                                    _buildDataCell(item.net, 2),
                                    _buildDataCell(item.price, 2),
                                    _buildDataCell(item.total, 3,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.indigo),
                                    _buildDataCell(item.customerName ?? '-', 3),
                                  ],
                                ),
                              )),
                          // سطر المجموع المبيعات
                          Container(
                            color: Colors.indigo.shade100,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _buildDataCell('المجموع', 1,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 4),
                                _buildDataCell('', 1),
                                _buildDataCell(
                                    salesTotalCount.toStringAsFixed(0), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 3),
                                _buildDataCell(
                                    salesTotalStanding.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell(
                                    salesTotalNet.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell(
                                    salesTotalGrand.toStringAsFixed(2), 3,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo),
                                _buildDataCell('', 3),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // --- جدول الاستلام ---
                  if (hasReceipts) ...[
                    _buildSectionTitle('الاستلام', Colors.green[700]!),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green.shade200),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        children: [
                          Container(
                            color: Colors.green.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _buildHeaderCell('ت', 1),
                                _buildHeaderCell('المادة', 4),
                                _buildHeaderCell('س', 1),
                                _buildHeaderCell('العدد', 2),
                                _buildHeaderCell('العبوة', 3),
                                _buildHeaderCell('القائم', 2),
                                _buildHeaderCell('الدفعة', 2),
                                _buildHeaderCell('الحمولة', 2),
                              ],
                            ),
                          ),
                          ...data.receipts.map((item) => Container(
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
                                    _buildDataCell(item.serialNumber, 1),
                                    _buildDataCell(item.material, 4),
                                    _buildDataCell(item.sValue, 1),
                                    _buildDataCell(item.count, 2),
                                    _buildDataCell(item.packaging, 3),
                                    _buildDataCell(item.standing, 2),
                                    _buildDataCell(item.payment, 2),
                                    _buildDataCell(item.load, 2),
                                  ],
                                ),
                              )),
                          // سطر المجموع الاستلام
                          Container(
                            color: Colors.green.shade100,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                _buildDataCell('المجموع', 1,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 4),
                                _buildDataCell('', 1),
                                _buildDataCell(
                                    receiptTotalCount.toStringAsFixed(0), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 3),
                                _buildDataCell(
                                    receiptTotalStanding.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell(
                                    receiptTotalPayment.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell(
                                    receiptTotalLoad.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // --- جدول المقارنة ---
                  if (hasSummary) ...[
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
                          ...data.summary.map((item) => Container(
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
                                      item.balance.toStringAsFixed(0),
                                      2,
                                      fontWeight: FontWeight.bold,
                                      color: item.balance >= 0
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

                  // --- رصيد المورد ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.only(top: 16.0),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'الرصيد : $balanceText',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
}
