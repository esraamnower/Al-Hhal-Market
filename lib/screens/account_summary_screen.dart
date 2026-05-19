import 'package:flutter/material.dart';
import '../services/app_settings_service.dart';
import '../services/customer_index_service.dart';
import '../services/supplier_index_service.dart';
import '../services/sales_storage_service.dart';
import '../services/purchase_storage_service.dart';
import '../services/box_storage_service.dart';
import '../widgets/exit_button.dart';

class AccountSummaryScreen extends StatefulWidget {
  final String selectedDate;
  const AccountSummaryScreen({super.key, required this.selectedDate});

  @override
  State<AccountSummaryScreen> createState() => _AccountSummaryScreenState();
}

class _AccountSummaryScreenState extends State<AccountSummaryScreen> {
  final CustomerIndexService _customerIndexService = CustomerIndexService();
  final SupplierIndexService _supplierIndexService = SupplierIndexService();
  final SalesStorageService _salesStorageService = SalesStorageService();
  final PurchaseStorageService _purchasesStorageService =
      PurchaseStorageService();
  final BoxStorageService _boxStorageService = BoxStorageService();

  double _salesTotal = 0;
  double _purchasesTotal = 0;
  double _boxReceived = 0;
  double _expensesTotal = 0;
  double _customersBalance = 0;
  double _suppliersBalance = 0;
  double _openingBoxBalance = 0;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      double sales = 0;
      double purchases = 0;
      double expensesTotalPaid = 0, expensesTotalReceived = 0;

      // ── 1. سجلات الصندوق اليدوية + المصروفات ──
      final allBoxDates =
          await _boxStorageService.getAvailableDatesWithNumbers();
      double boxManualReceived = 0, boxManualPaid = 0;
      for (var dateInfo in allBoxDates) {
        final doc =
            await _boxStorageService.loadBoxDocumentForDate(dateInfo['date']!);
        if (doc != null) {
          for (var trans in doc.transactions) {
            boxManualReceived += double.tryParse(trans.received) ?? 0;
            boxManualPaid += double.tryParse(trans.paid) ?? 0;
            if (trans.accountType == 'مصروف') {
              expensesTotalPaid += double.tryParse(trans.paid) ?? 0;
              expensesTotalReceived += double.tryParse(trans.received) ?? 0;
            }
          }
        }
      }
      final double expenses = expensesTotalPaid - expensesTotalReceived;

      // ── 2. إجمالي المبيعات (نقدي + دين) ──
      final salesAllDates = await _salesStorageService.getAllAvailableDates();
      double cashSalesTotal = 0;
      for (var date in salesAllDates) {
        final doc = await _salesStorageService.loadDocumentForDate(date);
        if (doc != null) {
          sales += double.tryParse(doc.totals['totalGrand'] ?? '0') ?? 0;
          for (var sale in doc.sales) {
            if (sale.cashOrDebt == 'نقدي') {
              cashSalesTotal += double.tryParse(sale.total) ?? 0;
            }
          }
        }
      }

// ── 3. إجمالي المشتريات (نقدي + دين) ──
      final purchasesAllDates =
          await _purchasesStorageService.getAllAvailableDates();
      double cashPurchasesTotal = 0;
      for (var date in purchasesAllDates) {
        final doc = await _purchasesStorageService.loadDocumentForDate(date);
        if (doc != null) {
          purchases += double.tryParse(doc.totals['totalGrand'] ?? '0') ?? 0;
          for (var purchase in doc.purchases) {
            if (purchase.cashOrDebt == 'نقدي') {
              cashPurchasesTotal += double.tryParse(purchase.total) ?? 0;
            }
          }
        }
      }
      // ── 4. رصيد الصندوق الكلي = يدوي + مبيعات نقدية - مشتريات نقدية ──
      final double fullBoxReceived = boxManualReceived + cashSalesTotal;
      final double fullBoxPaid = boxManualPaid + cashPurchasesTotal;
      final double boxBalance = fullBoxReceived - fullBoxPaid;

      // ── 5. رصيد الافتتاح ──
      final settings = AppSettingsService();
      final openingBox = double.tryParse(
              await settings.getString('opening_box_balance') ?? '0') ??
          0;

      // ── 6. أرصدة الزبائن والموردين ──
      final customers = await _customerIndexService.getAllCustomersWithData();
      final suppliers = await _supplierIndexService.getAllSuppliersWithData();
      final custBalance = customers.values.fold(0.0, (s, c) => s + c.balance);
      final suppBalance = suppliers.values.fold(0.0, (s, c) => s + c.balance);

      if (mounted) {
        setState(() {
          _salesTotal = sales;
          _purchasesTotal = purchases;
          _boxReceived = boxBalance;
          _expensesTotal = expenses;
          _customersBalance = custBalance;
          _suppliersBalance = suppBalance;
          _openingBoxBalance = openingBox;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _cell(String label, String value,
      {Color bgColor = Colors.white,
      Color textColor = Colors.black87,
      bool isBold = false,
      Color? valueColor}) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: Colors.grey.shade300, width: 0.5),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: valueColor ?? textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _twoColRow(Widget right, Widget left) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [right, left],
      ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }

  Widget _totalRow(String rightLabel, String rightVal, String leftLabel,
      String leftVal, Color color) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cell(rightLabel, rightVal,
              bgColor: color.withOpacity(0.15),
              textColor: color,
              isBold: true,
              valueColor: color),
          _cell(leftLabel, leftVal,
              bgColor: color.withOpacity(0.15),
              textColor: color,
              isBold: true,
              valueColor: color),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double tradingX = _salesTotal - _purchasesTotal;
    final bool isTradingProfit = tradingX > 0;
    final bool isTradingEqual = tradingX == 0;

    double plRight = _expensesTotal +
        (isTradingProfit || isTradingEqual ? 0 : tradingX.abs());
    double plLeft = isTradingProfit ? tradingX : 0;
    double netResult = plLeft - plRight;
    final bool isNetProfit = netResult > 0;
    final bool isNetEqual = netResult == 0;

    final double totalBoxBalance = _openingBoxBalance + _boxReceived;
    double balanceRight = _customersBalance +
        totalBoxBalance +
        (isNetProfit || isNetEqual ? 0 : netResult.abs());
    double capital =
        balanceRight - _suppliersBalance - (isNetProfit ? netResult : 0);
    double balanceLeft =
        _suppliersBalance + capital + (isNetProfit ? netResult : 0);

    final Color tradingColor = Colors.blueGrey.shade700;
    final Color plColor = Colors.purple.shade700;
    final Color balColor = const Color.fromARGB(255, 37, 18, 105);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 70,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ExitButton(
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Text(
              'تفصيلات الحساب',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            const SizedBox(width: 140),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Directionality(
              textDirection: TextDirection.rtl,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── العمود الأيسر: حساب المتاجرة + حساب الأرباح والخسائر فوق بعض ──
                      SizedBox(
                        width: (MediaQuery.of(context).size.width / 3) * 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // حساب المتاجرة
                            _sectionHeader('حساب المتاجرة', tradingColor),
                            _twoColRow(
                              _cell('المشتريات',
                                  _purchasesTotal.toStringAsFixed(2)),
                              _cell('المبيعات', _salesTotal.toStringAsFixed(2)),
                            ),
                            if (!isTradingEqual)
                              _twoColRow(
                                isTradingProfit
                                    ? _cell('ربح المتاجرة',
                                        tradingX.toStringAsFixed(2),
                                        bgColor: Colors.green.shade50,
                                        textColor: Colors.green.shade800,
                                        isBold: true,
                                        valueColor: Colors.green.shade800)
                                    : _cell('', ''),
                                isTradingProfit
                                    ? _cell('', '')
                                    : _cell('خسارة المتاجرة',
                                        tradingX.abs().toStringAsFixed(2),
                                        bgColor: Colors.red.shade50,
                                        textColor: Colors.red.shade800,
                                        isBold: true,
                                        valueColor: Colors.red.shade800),
                              ),
                            _totalRow(
                              'المجموع',
                              isTradingProfit
                                  ? _salesTotal.toStringAsFixed(2)
                                  : _purchasesTotal.toStringAsFixed(2),
                              'المجموع',
                              isTradingProfit
                                  ? _salesTotal.toStringAsFixed(2)
                                  : _purchasesTotal.toStringAsFixed(2),
                              tradingColor,
                            ),
                            const SizedBox(height: 16),
                            // حساب الأرباح والخسائر
                            _sectionHeader('حساب الأرباح والخسائر', plColor),
                            _twoColRow(
                              _cell(
                                  'المصروف', _expensesTotal.toStringAsFixed(2)),
                              isTradingProfit
                                  ? _cell('الربح التجاري',
                                      tradingX.toStringAsFixed(2))
                                  : _cell('', ''),
                            ),
                            if (!isTradingProfit && !isTradingEqual)
                              _twoColRow(
                                _cell('الخسارة التجارية',
                                    tradingX.abs().toStringAsFixed(2)),
                                _cell('', ''),
                              ),
                            if (!isNetEqual)
                              _twoColRow(
                                isNetProfit
                                    ? _cell('صافي الربح',
                                        netResult.toStringAsFixed(2),
                                        bgColor: Colors.green.shade50,
                                        textColor: Colors.green.shade800,
                                        isBold: true,
                                        valueColor: Colors.green.shade800)
                                    : _cell('', ''),
                                isNetProfit
                                    ? _cell('', '')
                                    : _cell('صافي الخسارة',
                                        netResult.abs().toStringAsFixed(2),
                                        bgColor: Colors.red.shade50,
                                        textColor: Colors.red.shade800,
                                        isBold: true,
                                        valueColor: Colors.red.shade800),
                              ),
                            _totalRow(
                              'المجموع',
                              (isNetProfit ? plLeft : plRight)
                                  .toStringAsFixed(2),
                              'المجموع',
                              (isNetProfit ? plLeft : plRight)
                                  .toStringAsFixed(2),
                              plColor,
                            ),
                          ],
                        ),
                      ),
                      // ── العمود الأيمن: الميزانية الختامية ──
                      SizedBox(
                        width: MediaQuery.of(context).size.width / 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionHeader('الميزانية الختامية', balColor),
                            _twoColRow(
                              _cell('الزبائن',
                                  _customersBalance.toStringAsFixed(2)),
                              _cell('الموردين',
                                  _suppliersBalance.toStringAsFixed(2)),
                            ),
                            _twoColRow(
                              _cell('الصندوق',
                                  totalBoxBalance.toStringAsFixed(2)),
                              _cell('رأس المال', capital.toStringAsFixed(2)),
                            ),
                            if (!isNetEqual)
                              _twoColRow(
                                !isNetProfit
                                    ? _cell('صافي الخسارة',
                                        netResult.abs().toStringAsFixed(2),
                                        bgColor: Colors.red.shade50,
                                        textColor: Colors.red.shade800,
                                        isBold: true,
                                        valueColor: Colors.red.shade800)
                                    : _cell('', ''),
                                isNetProfit
                                    ? _cell('صافي الربح',
                                        netResult.toStringAsFixed(2),
                                        bgColor: Colors.green.shade50,
                                        textColor: Colors.green.shade800,
                                        isBold: true,
                                        valueColor: Colors.green.shade800)
                                    : _cell('', ''),
                              ),
                            _totalRow(
                              'المجموع',
                              balanceRight.toStringAsFixed(2),
                              'المجموع',
                              balanceLeft.toStringAsFixed(2),
                              balColor,
                            ),
                            if ((balanceRight - balanceLeft).abs() > 0.01)
                              Container(
                                color: Colors.orange.shade100,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 8),
                                child: Text(
                                  'الفرق: ${(balanceRight - balanceLeft).toStringAsFixed(2)}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
