import 'package:flutter/material.dart';
import '../models/bait_model.dart';
import '../services/bait_service.dart';
import '../widgets/exit_button.dart';

class BaitScreen extends StatefulWidget {
  final String selectedDate;

  const BaitScreen({
    Key? key,
    required this.selectedDate,
  }) : super(key: key);

  @override
  _BaitScreenState createState() => _BaitScreenState();
}

class _BaitScreenState extends State<BaitScreen> {
  final BaitService _baitService = BaitService();
  late Future<List<BaitData>> _baitDataFuture;

  @override
  void initState() {
    super.initState();
    _baitDataFuture = _baitService.getBaitDataForDate(widget.selectedDate);
  }

  // دالة مساعدة لإنشاء خلية في رأس الجدول
  Widget _buildHeaderCell(String text, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  // دالة مساعدة لإنشاء خلية بيانات
  Widget _buildDataCell(String text, int flex,
      {Color color = Colors.black, FontWeight fontWeight = FontWeight.normal}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: kToolbarHeight + 20,
        title: Row(
          children: [
            ExitButton(
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'شاشة البايت ليوم ${widget.selectedDate}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 80),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<List<BaitData>>(
          future: _baitDataFuture,
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
                  'لا توجد حركة مواد لهذا اليوم',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              );
            }

            final baitList = snapshot.data!;

            // --- التصميم الجديد للجدول ---
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // 1. رأس الجدول
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        border: Border.all(color: Colors.teal.shade200)),
                    child: Row(
                      children: [
                        _buildHeaderCell('المادة', 3), // مساحة أكبر للمادة
                        _buildHeaderCell('الاستلام', 2),
                        _buildHeaderCell('المشتريات', 2),
                        _buildHeaderCell('المبيعات', 2),
                        _buildHeaderCell('البايت', 2),
                      ],
                    ),
                  ),

                  // 2. قائمة البيانات القابلة للتمرير
                  Expanded(
                    child: ListView.builder(
                      itemCount: baitList.length,
                      itemBuilder: (context, index) {
                        final data = baitList[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 10.0),
                          decoration: BoxDecoration(
                            color: index.isEven
                                ? Colors.white
                                : Colors.grey.shade100,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                              left: BorderSide(color: Colors.grey.shade300),
                              right: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildDataCell(data.materialName, 3),
                              _buildDataCell(
                                  data.receiptsCount.toStringAsFixed(0), 2),
                              _buildDataCell(
                                  data.purchasesCount.toStringAsFixed(0), 2),
                              _buildDataCell(
                                  data.salesCount.toStringAsFixed(0), 2),
                              _buildDataCell(
                                data.baitValue.toStringAsFixed(0),
                                2,
                                color: data.baitValue >= 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
            // --- نهاية التصميم الجديد ---
          },
        ),
      ),
    );
  }
}
