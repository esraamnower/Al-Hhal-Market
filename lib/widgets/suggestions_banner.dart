import 'package:flutter/material.dart';

// إضافة هذه الفئة الجديدة
class SuggestionItem {
  final int number; // رقم الفهرس الحقيقي
  final String name; // اسم العنصر

  const SuggestionItem({
    required this.number,
    required this.name,
  });

  String get displayName => '$number. $name';
}

class SuggestionsBanner extends StatelessWidget {
  final List<SuggestionItem>
      suggestions; // تغيير من List<String> إلى List<SuggestionItem>
  final String type;
  final int currentRowIndex;
  final ScrollController scrollController;
  final Function(String suggestion, int rowIndex) onSelect;
  final VoidCallback onClose;

  const SuggestionsBanner({
    Key? key,
    required this.suggestions,
    required this.type,
    required this.currentRowIndex,
    required this.scrollController,
    required this.onSelect,
    required this.onClose,
  }) : super(key: key);

  Color _getPrimaryColor() {
    switch (type) {
      case 'material':
        return Colors.blue;
      case 'packaging':
        return Colors.green;
      case 'supplier':
        return Colors.orange;
      case 'customer':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty || currentRowIndex < 0)
      return const SizedBox.shrink();
    final primaryColor = _getPrimaryColor();

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Material(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
        elevation: 4,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border:
                Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.5,
            maxHeight: 120,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: onClose,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.grey[700]),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('${suggestions.length} اقتراح',
                            style: TextStyle(
                                fontSize: 10,
                                color: primaryColor,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Icon(Icons.swipe, size: 10, color: primaryColor),
                  ],
                ),
              ),
              // Content
              Container(
                height: 80,
                color: Colors.white,
                child: Row(
                  children: [
                    _buildScrollButton(Icons.chevron_left, primaryColor, false),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: suggestions.length,
                        itemBuilder: (context, index) =>
                            _buildItem(index, primaryColor),
                      ),
                    ),
                    _buildScrollButton(Icons.chevron_right, primaryColor, true),
                  ],
                ),
              ),
              // Footer Indicator
              Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    suggestions.length > 5 ? 5 : suggestions.length,
                    (index) => Container(
                      width: 8,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: index == 0 ? primaryColor : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollButton(IconData icon, Color color, bool forward) {
    return InkWell(
      onTap: () {
        final offset = forward
            ? scrollController.offset + 150
            : scrollController.offset - 150;
        scrollController.animateTo(offset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      },
      child: Container(
          width: 24,
          height: 80,
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color)),
    );
  }

  Widget _buildItem(int index, Color primaryColor) {
    final item =
        suggestions[index]; // الآن نحصل على SuggestionItem بدلاً من String

    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(item.displayName, currentRowIndex),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color:
                  index == 0 ? primaryColor.withOpacity(0.1) : Colors.grey[50],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: index == 0
                      ? primaryColor.withOpacity(0.3)
                      : Colors.grey[200]!,
                  width: 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ التعديل هنا: إزالة CircleAvatar وإضافة Container يعرض رقم الفهرس الحقيقي
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? primaryColor
                        : primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    item.number
                        .toString(), // ✅ رقم الفهرس الحقيقي بدلاً من index+1
                    style: TextStyle(
                      color: index == 0 ? Colors.white : primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.name, // ✅ عرض اسم العنصر فقط
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (index == 0)
                  Icon(Icons.keyboard_arrow_down,
                      size: 12, color: primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
