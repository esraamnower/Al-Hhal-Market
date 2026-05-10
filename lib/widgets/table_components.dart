// widgets/table_components.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// كلاس فلترة الأرقام العشرية الموجبة
class PositiveDecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // التحقق من أن النص يحتوي فقط على أرقام ونقطة عشرية
    final regex = RegExp(r'^[0-9]*\.?[0-9]*$');
    if (!regex.hasMatch(newValue.text)) {
      return oldValue;
    }

    // التحقق من وجود نقطة عشرية واحدة فقط
    final decimalCount = '.'.allMatches(newValue.text).length;
    if (decimalCount > 1) {
      return oldValue;
    }

    // منع الأرقام السالبة
    if (newValue.text.contains('-')) {
      return oldValue;
    }

    return newValue;
  }
}

// كلاس فلترة رقمين بدون فاصلة عشرية
class TwoDigitInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // التحقق من أن النص يحتوي فقط على أرقام
    final regex = RegExp(r'^[0-9]*$');
    if (!regex.hasMatch(newValue.text)) {
      return oldValue;
    }

    // منع الأرقام السالبة
    if (newValue.text.contains('-')) {
      return oldValue;
    }

    // منع أكثر من خانتين (رقمين)
    if (newValue.text.length > 2) {
      return oldValue;
    }

    return newValue;
  }
}

// كلاس لتثبيت رأس الجدول
class StickyTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  StickyTableHeaderDelegate({required this.child, this.height = 32.0});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(StickyTableHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

// خلية رأس الجدول
Widget buildTableHeaderCell(String text) {
  return Container(
    padding: const EdgeInsets.all(2),
    constraints: const BoxConstraints(minHeight: 30),
    alignment: Alignment.center,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
    ),
  );
}

// خلية المجموع - نسخة موحدة (للأرقام فقط)
Widget buildTotalCell(TextEditingController controller) {
  return Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(1),
    constraints: const BoxConstraints(minHeight: 25),
    decoration: BoxDecoration(
      color: Colors.yellow[100],
    ),
    child: TextField(
      controller: controller,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        border: InputBorder.none,
      ),
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: Colors.red,
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      keyboardType: TextInputType.number,
      enabled: false,
      readOnly: true,
    ),
  );
}

// خلية المجموع - نسخة موحدة (للنصوص مثل "المجموع")
Widget buildTotalLabelCell(String label) {
  return Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.all(1),
    constraints: const BoxConstraints(minHeight: 25),
    decoration: BoxDecoration(
      color: Colors.yellow[100],
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: Colors.red,
      ),
      textAlign: TextAlign.center,
    ),
  );
}

// خلية الإجمالي غير القابلة للتعديل
Widget buildTotalValueCell(TextEditingController controller) {
  return Container(
    padding: const EdgeInsets.all(1),
    constraints: const BoxConstraints(minHeight: 25),
    alignment: Alignment.center,
    child: TextField(
      controller: controller,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        border: InputBorder.none,
        hintText: '0.00',
        hintStyle: TextStyle(fontSize: 17, color: Colors.grey),
      ),
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: Colors.blue,
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      keyboardType: TextInputType.number,
      enabled: false,
      readOnly: true,
    ),
  );
}

// خلية الفوارغ - بنفس تنسيق نقدي/دين مع اللون الأزرق
Widget buildEmptiesCell({
  required String value,
  required VoidCallback onTap,
  required int rowIndex,
  required int colIndex,
  required Function(int, int) scrollToField,
}) {
  return Container(
    padding: const EdgeInsets.all(1),
    constraints: const BoxConstraints(minHeight: 25),
    child: InkWell(
      onTap: () {
        onTap();
        scrollToField(rowIndex, colIndex);
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(
            color: _getEmptiesColor(value),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
          color: _getEmptiesColor(value).withOpacity(0.05),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Center(
          child: value.isEmpty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'اختر',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: Colors.grey[600],
                    ),
                  ],
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: _getEmptiesColor(value),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    ),
  );
}

// دالة مساعدة للحصول على لون خلية الفوارغ
Color _getEmptiesColor(String value) {
  if (value.isNotEmpty) {
    return const Color.fromARGB(255, 14, 82, 184); // أزرق
  }
  return Colors.grey;
}
