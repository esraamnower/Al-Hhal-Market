import '../models/sales_model.dart';
import '../models/invoice_model.dart';
import '../models/receipt_model.dart';
import '../models/purchase_model.dart';
import 'sales_storage_service.dart';
import 'receipt_storage_service.dart';
import 'purchase_storage_service.dart';
import '../models/supplier_invoice_model.dart';

// توحيد النصوص العربية لتفادي فروقات المسافات، والهمزات، والتاء المربوطة، إلخ.
String normalizeArabic(String text) {
  var n = text.trim().toLowerCase();
  n = n.replaceAll(RegExp(r'[\u064B-\u065F]'), ''); // إزالة الحركات
  n = n.replaceAll(RegExp(r'[أإآ]'), 'ا'); // توحيد الألف والهمزات
  n = n.replaceAll('ة', 'ه'); // توحيد التاء المربوطة والهاء
  n = n.replaceAll('ى', 'i'); // توحيد الألف المقصورة والياء مؤقتاً أو كلاهما ياء
  n = n.replaceAll('ي', 'ي');
  n = n.replaceAll('ى', 'ي');
  n = n.replaceAll(' ', ''); // إزالة المسافات تماماً لضمان المطابقة اللينة مثل (ابو احمد) و (ابواحمد)
  return n;
}

// نموذج يحتوي على كل البيانات المطلوبة لشاشة المورد
class SupplierReportData {
  final List<InvoiceItem> sales;
  final List<Receipt> receipts;
  final List<MaterialSummary> summary;

  SupplierReportData({
    required this.sales,
    required this.receipts,
    required this.summary,
  });
}

// نموذج بيانات لملخص المواد (البايت)
class MaterialSummary {
  final String material;
  final double receiptCount;
  final double salesCount;
  final double balance;

  MaterialSummary({
    required this.material,
    required this.receiptCount,
    required this.salesCount,
    required this.balance,
  });
}

class InvoicesService {
  final SalesStorageService _salesStorageService = SalesStorageService();
  final ReceiptStorageService _receiptStorageService = ReceiptStorageService();
  final PurchaseStorageService _purchaseStorageService =
      PurchaseStorageService();

  // 1. دالة جلب فواتير الزبائن (صحيحة)
  Future<List<InvoiceItem>> getInvoicesForCustomer(
      String date, String customerName) async {
    final SalesDocument? salesDocument =
        await _salesStorageService.loadSalesDocument(date);

    if (salesDocument == null || salesDocument.sales.isEmpty) {
      return [];
    }

    final List<InvoiceItem> customerInvoices = salesDocument.sales
        .where((sale) =>
            sale.customerName?.trim() == customerName.trim() &&
            sale.cashOrDebt == 'دين')
        .map((sale) => InvoiceItem(
              serialNumber: sale.serialNumber,
              material: sale.material,
              affiliation: sale.affiliation,
              sValue: sale.sValue,
              count: sale.count,
              packaging: sale.packaging,
              standing: sale.standing,
              net: sale.net,
              price: sale.price,
              total: sale.total,
              empties: sale.empties,
              customerName: sale.customerName,
              sellerName: sale.sellerName,
            ))
        .toList();

    return customerInvoices;
  }

  // 2. دالة جلب تقرير المورد الشامل (صحيحة)
  Future<SupplierReportData> getSupplierReport(
      String date, String supplierName) async {
    final cleanSupplierName = supplierName.trim();
    List<InvoiceItem> supplierSales = [];
    List<Receipt> supplierReceipts = [];
    Map<String, MaterialSummary> summaryMap = {};

    // أ) جلب المبيعات الخاصة بالمورد
    final SalesDocument? salesDocument =
        await _salesStorageService.loadSalesDocument(date);

    if (salesDocument != null) {
      for (var sale in salesDocument.sales) {
        if (normalizeArabic(sale.affiliation) == normalizeArabic(supplierName)) {
          supplierSales.add(InvoiceItem(
            serialNumber: sale.serialNumber,
            material: sale.material,
            affiliation: sale.affiliation,
            sValue: sale.sValue,
            count: sale.count,
            packaging: sale.packaging,
            standing: sale.standing,
            net: sale.net,
            price: sale.price,
            total: sale.total,
            empties: sale.empties,
            customerName: sale.customerName,
            sellerName: sale.sellerName,
          ));

          // *** بداية التعديل: استخدام اسم المادة فقط كمفتاح للتجميع ***
          final key = sale.material.trim();
          final count = double.tryParse(sale.count) ?? 0;
          summaryMap.update(
            key,
            (value) => MaterialSummary(
              material: value.material,
              receiptCount: value.receiptCount,
              salesCount: value.salesCount + count,
              balance: value.receiptCount - (value.salesCount + count),
            ),
            ifAbsent: () => MaterialSummary(
              material: key, // استخدام اسم المادة مباشرة
              receiptCount: 0,
              salesCount: count,
              balance: -count,
            ),
          );
          // *** نهاية التعديل ***
        }
      }
    }

    // ب) جلب الاستلام الخاص بالمورد
    final ReceiptDocument? receiptDocument =
        await _receiptStorageService.loadReceiptDocumentForDate(date);

    if (receiptDocument != null) {
      for (var receipt in receiptDocument.receipts) {
        if (normalizeArabic(receipt.affiliation) == normalizeArabic(supplierName)) {
          supplierReceipts.add(receipt);

          // *** بداية التعديل: استخدام اسم المادة فقط كمفتاح للتجميع ***
          final key = receipt.material.trim();
          final count = double.tryParse(receipt.count) ?? 0;
          summaryMap.update(
            key,
            (value) => MaterialSummary(
              material: value.material,
              receiptCount: value.receiptCount + count,
              salesCount: value.salesCount,
              balance: (value.receiptCount + count) - value.salesCount,
            ),
            ifAbsent: () => MaterialSummary(
              material: key, // استخدام اسم المادة مباشرة
              receiptCount: count,
              salesCount: 0,
              balance: count,
            ),
          );
          // *** نهاية التعديل ***
        }
      }
    }

    final summaryList = summaryMap.values.toList();
    summaryList.sort((a, b) => a.material.compareTo(b.material));

    return SupplierReportData(
      sales: supplierSales,
      receipts: supplierReceipts,
      summary: summaryList,
    );
  }

  // 3. دالة جلب مشتريات مورد معين (تم التصحيح هنا)
  Future<List<Purchase>> getPurchasesForSupplier(
      String date, String supplierName) async {
    final PurchaseDocument? purchaseDocument =
        await _purchaseStorageService.loadPurchaseDocument(date);

    if (purchaseDocument == null || purchaseDocument.purchases.isEmpty) {
      return [];
    }

    // البحث في حقل "affiliation" (العائدية) بدلاً من "supplierName" غير الموجود
    final List<Purchase> supplierPurchases =
        purchaseDocument.purchases.where((purchase) {
      final purchaseAffiliation = purchase.affiliation.trim();
      final targetSupplierName = supplierName.trim();

      // المقارنة تتم الآن مع الحقل الصحيح
      return purchaseAffiliation.toLowerCase() ==
          targetSupplierName.toLowerCase();
    }).toList();

    return supplierPurchases;
  }

  // 4. دالة بناء فاتورة المورد الكاملة وفق الشرط (المورد + س + التاريخ)
  Future<SupplierInvoice> generateSupplierInvoice(
    String date,
    String supplierName,
    String sValue,
  ) async {
    final normalizedCleanSupplier = normalizeArabic(supplierName);
    final cleanS = sValue.trim();

    String normalizeS(String s) {
      final parsed = int.tryParse(s.trim());
      return parsed != null ? parsed.toString() : s.trim();
    }
    final normalizedCleanS = normalizeS(cleanS);

    // مفتاح التجميع: المادة + السعر
    final Map<String, GroupedSaleLine> salesGroups = {};
    // تجميع المباع لكل مادة (للمقارنة)
    final Map<String, double> salesCountByMaterial = {};
    double totalSalesValue = 0;

    // ===== أ) المبيعات: فلترة بـ (المورد + س) ثم تجميع بـ (المادة + السعر) =====
    final SalesDocument? salesDoc =
        await _salesStorageService.loadSalesDocument(date);

    if (salesDoc != null) {
      for (final sale in salesDoc.sales) {
        final matchSupplier = normalizeArabic(sale.affiliation) == normalizedCleanSupplier;
        final matchS = normalizedCleanS.isEmpty || normalizeS(sale.sValue) == normalizedCleanS;
        if (!matchSupplier || !matchS) continue;

        final material = sale.material.trim();
        final price = sale.price.trim();
        final key = '$material||$price'; // فاصل آمن لتمييز المادة عن السعر

        final count = double.tryParse(sale.count) ?? 0;
        final standing = double.tryParse(sale.standing) ?? 0;
        final net = double.tryParse(sale.net) ?? 0;
        final value = double.tryParse(sale.total) ?? 0;

        totalSalesValue += value;
        salesCountByMaterial.update(
          material,
          (v) => v + count,
          ifAbsent: () => count,
        );

        if (salesGroups.containsKey(key)) {
          final g = salesGroups[key]!;
          salesGroups[key] = g.copyWith(
            totalCount: g.totalCount + count,
            totalStanding: g.totalStanding + standing,
            totalNet: g.totalNet + net,
            totalValue: g.totalValue + value,
            recordsCount: g.recordsCount + 1,
          );
        } else {
          salesGroups[key] = GroupedSaleLine(
            material: material,
            price: price,
            totalCount: count,
            totalStanding: standing,
            totalNet: net,
            totalValue: value,
            recordsCount: 1,
          );
        }
      }
    }

    // ===== ب) الاستلام: فلترة بـ (المورد + س)، جمع الحمولة والدفعة والعتالة، وعدّ المستلم =====
    final Map<String, double> receiptCountByMaterial = {};
    double totalLoad = 0;
    double totalPayment = 0;
    double totalPortage = 0;

    final ReceiptDocument? receiptDoc =
        await _receiptStorageService.loadReceiptDocumentForDate(date);

    if (receiptDoc != null) {
      for (final receipt in receiptDoc.receipts) {
        final matchSupplier = normalizeArabic(receipt.affiliation) == normalizedCleanSupplier;
        final matchS = normalizedCleanS.isEmpty || normalizeS(receipt.sValue) == normalizedCleanS;
        if (!matchSupplier || !matchS) continue;

        final material = receipt.material.trim();
        final count = double.tryParse(receipt.count) ?? 0;

        receiptCountByMaterial.update(
          material,
          (v) => v + count,
          ifAbsent: () => count,
        );

        totalLoad += double.tryParse(receipt.load) ?? 0;
        totalPayment += double.tryParse(receipt.payment) ?? 0;
        totalPortage += double.tryParse(receipt.portage) ?? 0;
      }
    }

    // ===== ج) بناء جدول المقارنة (كل المواد من الطرفين) =====
    final allMaterials = <String>{
      ...salesCountByMaterial.keys,
      ...receiptCountByMaterial.keys,
    };

    final comparison = allMaterials.map((material) {
      final recv = receiptCountByMaterial[material] ?? 0;
      final sold = salesCountByMaterial[material] ?? 0;
      return SupplierComparisonLine(
        material: material,
        receiptCount: recv,
        salesCount: sold,
        difference: recv - sold,
      );
    }).toList()
      ..sort((a, b) => a.material.compareTo(b.material));

    // ترتيب جدول المبيعات المجمّع
    final groupedList = salesGroups.values.toList()
      ..sort((a, b) {
        final byMaterial = a.material.compareTo(b.material);
        if (byMaterial != 0) return byMaterial;
        final pa = double.tryParse(a.price) ?? 0;
        final pb = double.tryParse(b.price) ?? 0;
        return pa.compareTo(pb);
      });

    return SupplierInvoice(
      supplierName: supplierName.trim(), // إعادة الاسم بالشكل الطبيعي مع الحفاظ على التنسيق الأصلي للمورد
      sValue: cleanS,
      date: date,
      groupedSales: groupedList,
      comparison: comparison,
      totalSalesValue: totalSalesValue,
      loadValue: totalLoad, // قابلة للتعديل في الواجهة
      paymentValue: totalPayment, // قابلة للتعديل في الواجهة
      portageValue: totalPortage, // العتالة المجمعة من الاستلام
    );
  }

  /// حساب قيمة المعلوم من النسبة: (إجمالي المبيعات × النسبة) ÷ 100
  double calculateMaloom(double totalSalesValue, double percent) {
    return (totalSalesValue * percent) / 100;
  }
}
