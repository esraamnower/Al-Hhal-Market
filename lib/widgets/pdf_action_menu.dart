import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';

class PdfActionMenu extends StatelessWidget {
  final Future<List<dynamic>> Function() getItems;
  final Future<Uint8List> Function(List<dynamic>) generatePdfCallback;
  final String supplierOrCustomerName;
  final String filterDesc;
  final double? balance;
  final String storeName;
  final String selectedDate;
  final String type; // 'supplier', 'customer', 'box', 'purchases', 'bait'
  final double iconSize;

  const PdfActionMenu({
    Key? key,
    required this.getItems,
    required this.generatePdfCallback,
    required this.supplierOrCustomerName,
    required this.filterDesc,
    required this.balance,
    required this.storeName,
    required this.selectedDate,
    required this.type,
    this.iconSize = 35,
  }) : super(key: key);

  Future<Uint8List> _generatePdfBytes() async {
    final items = await getItems();
    if (items.isEmpty) throw Exception('لا توجد بيانات');
    return await generatePdfCallback(items);
  }

  String _buildFileName() {
    final safeDate = selectedDate.replaceAll('/', '-');
    switch (type) {
      case 'customer':
        final safeName = supplierOrCustomerName.replaceAll(' ', '_');
        return 'فاتورة_الزبون_${safeName}_$safeDate.pdf';
      case 'supplier':
        final safeName = supplierOrCustomerName.replaceAll(' ', '_');
        return 'مشتريات_من_المورد_${safeName}_$safeDate.pdf';
      case 'box':
        return 'يومية_صندوق_$safeDate.pdf';
      case 'purchases':
        return 'يومية_مشتريات_$safeDate.pdf';
      case 'bait':
        final fromTo = filterDesc.replaceAll('/', '-').replaceAll(' ', '_');
        return 'تقرير_البايت_$fromTo.pdf';
      case 'sales':
        return 'يومية_مبيعات_$safeDate.pdf';
      default:
        return 'تقرير_$safeDate.pdf';
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdfBytes = await _generatePdfBytes();
      final output = await getTemporaryDirectory();
      final fileName = _buildFileName();
      final file = File("${output.path}/$fileName");
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)],
          text: type == 'supplier'
              ? 'مشتريات المورد $supplierOrCustomerName - $filterDesc'
              : type == 'customer'
                  ? 'فاتورة الزبون $supplierOrCustomerName - $filterDesc'
                  : 'تقرير $type - $filterDesc');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _savePdf() async {
    try {
      final pdfBytes = await _generatePdfBytes();
      final output = await getDownloadsDirectory();
      if (output == null) throw Exception('لا يمكن الوصول إلى مجلد التنزيلات');
      final fileName = _buildFileName();
      final file = File("${output.path}/$fileName");
      await file.writeAsBytes(pdfBytes);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _printPdf() async {
    try {
      final pdfBytes = await _generatePdfBytes();
      final fileName = _buildFileName();
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: fileName,
      );
    } catch (e) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.picture_as_pdf, size: iconSize),
      tooltip: 'خيارات PDF',
      onSelected: (value) async {
        try {
          switch (value) {
            case 'share':
              await _sharePdf();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت المشاركة بنجاح')),
                );
              }
              break;
            case 'save':
              await _savePdf();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم الحفظ في مجلد التنزيلات')),
                );
              }
              break;
            case 'print':
              await _printPdf();
              break;
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('حدث خطأ: ${e.toString()}')),
            );
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share, color: Colors.blue),
              SizedBox(width: 12),
              Text('مشاركة PDF'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save_alt, color: Colors.green),
              SizedBox(width: 12),
              Text('حفظ على الكمبيوتر'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print, color: Colors.purple),
              SizedBox(width: 12),
              Text('طباعة مباشرة'),
            ],
          ),
        ),
      ],
    );
  }
}
