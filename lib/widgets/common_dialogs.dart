import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// نافذة اختيار طريقة الدفع (نسخة محسنة للكمبيوتر)
void showCashOrDebtDialog({
  required BuildContext context,
  required String currentValue,
  required List<String> options,
  required ValueChanged<String> onSelected,
  required VoidCallback onCancel,
}) {
  int selectedIndex = options.indexOf(currentValue);
  if (selectedIndex == -1) selectedIndex = 0;

  final FocusNode focusNode = FocusNode();

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return RawKeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKey: (RawKeyEvent event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() {
                    selectedIndex = (selectedIndex + 1) % options.length;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() {
                    selectedIndex =
                        (selectedIndex - 1 + options.length) % options.length;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  // إغلاق الحوار باستخدام dialogContext
                  Navigator.of(dialogContext).pop();
                  onSelected(options[selectedIndex]);
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  // إغلاق الحوار فقط باستخدام dialogContext
                  Navigator.of(dialogContext).pop();
                  onCancel();
                  return; // منع انتشار الحدث
                }
              }
            },
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: Container(
                  width: 400,
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // العنوان
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.red[700],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'اختر طريقة الدفع',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(Icons.payment,
                                  color: Colors.white, size: 24),
                            ],
                          ),
                        ),
                      ),
                      // الخيارات
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 8),
                        child: Column(
                          children: List.generate(options.length, (index) {
                            final isSelected = selectedIndex == index;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onSelected(options[index]);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.red[50]
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.red[700]!, width: 1.5)
                                        : null,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    leading: Radio<String>(
                                      value: options[index],
                                      groupValue: options[selectedIndex],
                                      onChanged: (_) {
                                        Navigator.of(dialogContext).pop();
                                        onSelected(options[index]);
                                      },
                                      activeColor: Colors.red[700],
                                    ),
                                    title: Text(
                                      options[index],
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? Colors.red[700]
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // الأزرار
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).then((_) {
    focusNode.dispose();
  });
}

// نافذة اختيار نوع الحساب
Future<void> showAccountTypeDialog({
  required BuildContext context,
  required String currentValue,
  required List<String> options,
  required Function(String) onSelected,
  required Function() onCancel,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          'اختر نوع الحساب',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black), // ✅ إضافة اللون الأسود
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((option) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(
                    option,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: option == currentValue
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: option == currentValue
                          ? Colors.blue
                          : Colors.black, // ✅ تعديل اللون
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(option);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onCancel();
            },
            child: const Text('إلغاء',
                style: TextStyle(color: Colors.black)), // ✅ إضافة اللون الأسود
          ),
        ],
      );
    },
  );
}

// نافذة اختيار الفوارغ
void showEmptiesDialog({
  required BuildContext context,
  required String currentValue,
  required List<String> options,
  required ValueChanged<String> onSelected,
  required VoidCallback onCancel,
}) {
  int selectedIndex = options.indexOf(currentValue);
  if (selectedIndex == -1) selectedIndex = 0;

  final FocusNode focusNode = FocusNode();

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return RawKeyboardListener(
            focusNode: focusNode,
            autofocus: true,
            onKey: (RawKeyEvent event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  setState(() {
                    selectedIndex = (selectedIndex + 1) % options.length;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  setState(() {
                    selectedIndex =
                        (selectedIndex - 1 + options.length) % options.length;
                  });
                } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  Navigator.of(dialogContext).pop();
                  onSelected(options[selectedIndex]);
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.of(dialogContext).pop();
                  onCancel();
                  return;
                }
              }
            },
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                child: Container(
                  width: 400,
                  constraints: const BoxConstraints(maxWidth: 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // العنوان باللون الأزرق
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 14, 82, 184), // أزرق
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'اختر حالة الفوارغ',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(Icons.inventory_2,
                                  color: Colors.white, size: 24),
                            ],
                          ),
                        ),
                      ),
                      // الخيارات
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 8),
                        child: Column(
                          children: List.generate(options.length, (index) {
                            final isSelected = selectedIndex == index;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onSelected(options[index]);
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color.fromARGB(255, 14, 82, 184)
                                            .withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: const Color.fromARGB(
                                                255, 14, 82, 184),
                                            width: 1.5)
                                        : null,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    leading: Radio<String>(
                                      value: options[index],
                                      groupValue: options[selectedIndex],
                                      onChanged: (_) {
                                        Navigator.of(dialogContext).pop();
                                        onSelected(options[index]);
                                      },
                                      activeColor: const Color.fromARGB(
                                          255, 14, 82, 184), // أزرق
                                    ),
                                    title: Text(
                                      options[index],
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? const Color.fromARGB(
                                                255, 14, 82, 184)
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      // الأزرار (فارغة للحفاظ على نفس التنسيق)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  ).then((_) {
    focusNode.dispose();
  });
}

// باقي الدوال كما هي...
void showFilePathDialog({
  required BuildContext context,
  required String filePath,
}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('مسار الملف', style: TextStyle(color: Colors.black)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('يمكنك نسخ المسار أدناه:',
              style: TextStyle(color: Colors.black)),
          const SizedBox(height: 8),
          SelectableText(
            filePath,
            style: const TextStyle(fontSize: 12, color: Colors.blue),
          ),
          const SizedBox(height: 16),
          const Text(
            'يمكنك نقل الملف إلى الحاسوب عبر USB أو البلوتوث',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('موافق', style: TextStyle(color: Colors.black)),
        ),
      ],
    ),
  );
}

Future<bool?> showDeleteConfirmationDialog({
  required BuildContext context,
  required String recordNumber,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.black)),
      content: Text('هل تريد حذف السجل رقم $recordNumber؟',
          style: const TextStyle(color: Colors.black)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء', style: TextStyle(color: Colors.black)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
