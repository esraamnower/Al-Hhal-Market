import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/invoice_model.dart';
import '../../services/invoices_service.dart';
import '../../services/customer_index_service.dart';
import '../../widgets/pdf_action_menu.dart';
import 'package:flutter/services.dart';

class InvoicesScreen extends StatefulWidget {
  final String selectedDate;
  final String storeName;
  final String customerName;

  const InvoicesScreen({
    Key? key,
    required this.selectedDate,
    required this.storeName,
    required this.customerName,
  }) : super(key: key);

  @override
  _InvoicesScreenState createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final InvoicesService _invoicesService = InvoicesService();
  final CustomerIndexService _customerIndexService = CustomerIndexService();
  late Future<List<InvoiceItem>> _invoiceDataFuture;
  double? _customerBalance;

  @override
  void initState() {
    super.initState();
    _invoiceDataFuture = _invoicesService.getInvoicesForCustomer(
        widget.selectedDate, widget.customerName);
    _loadCustomerBalance();
  }

  Future<void> _loadCustomerBalance() async {
    final allCustomers = await _customerIndexService.getAllCustomersWithData();
    for (var entry in allCustomers.entries) {
      if (entry.value.name.toLowerCase() ==
          widget.customerName.trim().toLowerCase()) {
        if (mounted) {
          setState(() {
            _customerBalance = entry.value.balance;
          });
        }
        return;
      }
    }
  }

  Future<Uint8List> _generatePdfBytes(List<InvoiceItem> items) async {
    final pdf = pw.Document();

    var arabicFont;
    try {
      final fontData = await rootBundle.load("assets/fonts/Cairo-Regular.ttf");
      arabicFont = pw.Font.ttf(fontData);
    } catch (e) {
      arabicFont = pw.Font.courier();
    }

    double totalCount = 0, totalStanding = 0, totalNet = 0, grandTotal = 0;
    for (var item in items) {
      totalStanding += double.tryParse(item.standing) ?? 0;
      totalNet += double.tryParse(item.net) ?? 0;
      totalCount += double.tryParse(item.count) ?? 0;
      grandTotal += double.tryParse(item.total) ?? 0;
    }

    final PdfColor headerColor = PdfColor.fromInt(0xFF5C6BC0);
    final PdfColor headerTextColor = PdfColors.white;
    final PdfColor rowEvenColor = PdfColors.white;
    final PdfColor rowOddColor = PdfColor.fromInt(0xFFE8EAF6);
    final PdfColor borderColor = PdfColor.fromInt(0xFFE0E0E0);
    final PdfColor totalRowColor = PdfColor.fromInt(0xFFC5CAE9);
    final PdfColor grandTotalColor = PdfColor.fromInt(0xFF283593);

    final String balanceTextPdf =
        _customerBalance != null ? _customerBalance!.toStringAsFixed(2) : '---';

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
                      child: pw.Text('فاتورة الزبون ${widget.customerName}',
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold))),
                  pw.SizedBox(height: 5),
                  pw.Center(
                      child: pw.Text(
                          'بتاريخ ${widget.selectedDate} لمحل ${widget.storeName}',
                          style: const pw.TextStyle(
                              fontSize: 14, color: PdfColors.grey700))),
                  pw.SizedBox(height: 15),
                  pw.Table(
                    border: pw.TableBorder.all(color: borderColor, width: 0.5),
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
                        decoration: pw.BoxDecoration(color: headerColor),
                        children: [
                          _buildPdfHeaderCell('فوارغ', headerTextColor),
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
                      ...items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final color =
                            index % 2 == 0 ? rowEvenColor : rowOddColor;
                        return pw.TableRow(
                          decoration: pw.BoxDecoration(color: color),
                          children: [
                            _buildPdfCell(item.empties),
                            _buildPdfCell(item.total,
                                textColor: PdfColor.fromInt(0xFF1A237E),
                                isBold: true),
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
                        decoration: pw.BoxDecoration(color: totalRowColor),
                        children: [
                          _buildPdfCell(''),
                          _buildPdfCell(grandTotal.toStringAsFixed(2),
                              textColor: PdfColor.fromInt(0xFF1A237E),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(totalNet.toStringAsFixed(2),
                              isBold: true),
                          _buildPdfCell(totalStanding.toStringAsFixed(2),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(totalCount.toStringAsFixed(0),
                              isBold: true),
                          _buildPdfCell(''),
                          _buildPdfCell(''),
                          _buildPdfCell('م', isBold: true),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                        color: grandTotalColor,
                        borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Center(
                      child: pw.Text(
                        'المجموع ${grandTotal.toStringAsFixed(2)} ليرة سورية فقط لا غير  الرصيد : $balanceTextPdf.',
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

  // --- الدوال المساعدة للـ PDF (محدثة) ---
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

  // --- التعديلات على الـ UI (تبقى كما هي RTL بشكل طبيعي) ---
  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'فاتورة الزبون ${widget.customerName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          PdfActionMenu(
            type: 'customer',
            supplierOrCustomerName: widget.customerName,
            filterDesc: widget.selectedDate,
            balance: _customerBalance,
            storeName: widget.storeName,
            selectedDate: widget.selectedDate,
            iconSize: 60,
            getItems: () async => await _invoiceDataFuture,
            generatePdfCallback: (items) =>
                _generatePdfBytes(items as List<InvoiceItem>),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              'بتاريخ ${widget.selectedDate} لمحل ${widget.storeName}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<List<InvoiceItem>>(
          future: _invoiceDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('حدث خطأ: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Text(
                  'لا توجد فواتير دين لهذا الزبون في اليوم المحدد',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            final invoiceItems = snapshot.data!;

            // --- حساب المجاميع ---
            double totalStanding = 0;
            double totalNet = 0;

            double grandTotal = 0;
            int totalCount = 0;
            for (var item in invoiceItems) {
              totalStanding += double.tryParse(item.standing) ?? 0;
              totalNet += double.tryParse(item.net) ?? 0;
              totalCount += int.tryParse(item.count) ?? 0;
              grandTotal += double.tryParse(item.total) ?? 0;
            }

            final String balanceText = _customerBalance != null
                ? _customerBalance!.toStringAsFixed(2)
                : '---';

            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // 1. رأس الجدول (الواجهة العادية - غير معكوسة لأنها تظهر بشكل صحيح)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                        color: Colors.indigo.shade400,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        border: Border.all(color: Colors.indigo.shade200)),
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
                        _buildHeaderCell('فوارغ', 3),
                      ],
                    ),
                  ),

                  // 2. قائمة البيانات
                  Expanded(
                    child: ListView.builder(
                      itemCount:
                          invoiceItems.length + 1, // +1 for the total row
                      itemBuilder: (context, index) {
                        // --- سطر المجموع ---
                        if (index == invoiceItems.length) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10.0, horizontal: 4.0),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade100,
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade300),
                                left: BorderSide(color: Colors.grey.shade300),
                                right: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildDataCell('المجموع', 1,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 4), // المادة
                                _buildDataCell('', 1), // س

                                _buildDataCell(totalCount.toStringAsFixed(0), 2,
                                    fontWeight: FontWeight.bold),

                                _buildDataCell('', 3), // العبوة
                                _buildDataCell(
                                    totalStanding.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell(totalNet.toStringAsFixed(2), 2,
                                    fontWeight: FontWeight.bold),
                                _buildDataCell('', 2,
                                    fontWeight: FontWeight.bold), // السعر فارغ
                                _buildDataCell(grandTotal.toStringAsFixed(2), 3,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade900),
                                _buildDataCell('', 3), // فوارغ
                              ],
                            ),
                          );
                        }

                        // --- أسطر البيانات العادية ---
                        final item = invoiceItems[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10.0, horizontal: 4.0),
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? Colors.white
                                : Colors.indigo.shade50,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                              left: BorderSide(color: Colors.grey.shade300),
                              right: BorderSide(color: Colors.grey.shade300),
                            ),
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
                              _buildDataCell(
                                item.total,
                                3,
                                color: Colors.indigo.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                              _buildDataCell(item.empties, 3),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // 3. المجموع النهائي
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.only(top: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'المجموع ${grandTotal.toStringAsFixed(2)} ليرة سورية فقط لا غير  الرصيد : $balanceText.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
