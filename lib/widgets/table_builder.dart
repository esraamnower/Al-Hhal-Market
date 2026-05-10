import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// بناء خلية جدول مشتركة (النسخة المدمجة)
Widget buildTableCell({
  required TextEditingController controller,
  required FocusNode focusNode,
  required bool isSerialField,
  required bool isNumericField,
  required int rowIndex,
  required int colIndex,
  required Function(int, int) scrollToField,
  required Function(String, int, int) onFieldSubmitted,
  required Function(String, int, int) onFieldChanged,
  List<TextInputFormatter>? inputFormatters,
  bool isSField = false,
  double fontSize = 16,
  TextAlign textAlign = TextAlign.center,
  TextDirection textDirection = TextDirection.rtl,
  bool enabled = true,
}) {
  return Container(
    padding: const EdgeInsets.all(1),
    constraints: const BoxConstraints(minHeight: 25),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: isSerialField,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        border: InputBorder.none,
      ),
      style: TextStyle(
        fontSize: fontSize,
        color: enabled ? Colors.black : Colors.grey[700],
      ),
      keyboardType: isSField
          ? TextInputType.number
          : (isNumericField
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text),
      textInputAction: TextInputAction.next,
      textAlign: textAlign,
      textDirection: textDirection,
      inputFormatters: inputFormatters,
      onTap: () {
        scrollToField(rowIndex, colIndex);
      },
      onSubmitted: (value) => onFieldSubmitted(value, rowIndex, colIndex),
      onChanged: (value) => onFieldChanged(value, rowIndex, colIndex),
    ),
  );
}

// بناء خلية نقدي أو دين مع وظيفة خاصة بالمبيعات
Widget buildCashOrDebtCell({
  required int rowIndex,
  required int colIndex,
  required String cashOrDebtValue,
  required String customerName,
  required TextEditingController customerController,
  required FocusNode focusNode,
  required bool hasUnsavedChanges,
  required ValueChanged<bool> setHasUnsavedChanges,
  required VoidCallback onTap,
  required Function(int, int) scrollToField,
  required ValueChanged<String> onCustomerNameChanged,
  required Function(String, int, int) onCustomerSubmitted,
  bool isSalesScreen = false,
  bool enabled = true,
}) {
  // إذا كانت الخلية غير مفعلة، نعرض نصاً بسيطاً للقراءة فقط
  if (!enabled) {
    String displayText = cashOrDebtValue;
    if (isSalesScreen && cashOrDebtValue == 'دين' && customerName.isNotEmpty) {
      displayText = customerName;
    } else if (cashOrDebtValue.isEmpty) {
      displayText = '-';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      constraints: const BoxConstraints(minHeight: 25),
      alignment: Alignment.center,
      child: Text(
        displayText,
        style: const TextStyle(
          fontSize: 16,
          color: Colors.grey,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // إذا كانت شاشة المبيعات والقيمة "دين" (والخلية مفعلة)
  if (isSalesScreen && cashOrDebtValue == 'دين') {
    return Container(
      padding: const EdgeInsets.all(1),
      constraints: const BoxConstraints(minHeight: 25),
      child: TextField(
        controller: customerController,
        focusNode: focusNode,
        decoration: InputDecoration(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 0.5),
          ),
          hintText: 'اسم الزبون',
          hintStyle: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
        style: const TextStyle(
          fontSize: 16,
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        textInputAction: TextInputAction.next,
        onTap: () {
          scrollToField(rowIndex, colIndex);
        },
        onChanged: (value) {
          onCustomerNameChanged(value);
          setHasUnsavedChanges(true);
        },
        onSubmitted: (value) => onCustomerSubmitted(value, rowIndex, colIndex),
      ),
    );
  }

  // بقية الحالات (نقدي، دين للمشتريات، فارغ) تستخدم InkWell
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
            color: _getCashOrDebtColor(cashOrDebtValue),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
          color: _getCashOrDebtColor(cashOrDebtValue).withOpacity(0.05),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Center(
          child: cashOrDebtValue.isEmpty
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
                  cashOrDebtValue,
                  style: TextStyle(
                    fontSize: 16,
                    color: _getCashOrDebtColor(cashOrDebtValue),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    ),
  );
}

// دالة مساعدة للحصول على لون خلية نقدي/دين
Color _getCashOrDebtColor(String value) {
  switch (value) {
    case 'نقدي':
      return Colors.green;
    case 'دين':
      return Colors.red;
    default:
      return Colors.grey;
  }
}
