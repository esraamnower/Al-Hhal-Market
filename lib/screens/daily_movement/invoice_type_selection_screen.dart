import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'customer_selection_screen.dart';
import 'supplier_selection_screen.dart';
import '../../widgets/exit_button.dart';
import 'supplier_bill_screen.dart';
import '../../widgets/shared_menu_button.dart';

class InvoiceTypeSelectionScreen extends StatefulWidget {
  final String selectedDate;
  final String storeName;
  final String sellerName;

  const InvoiceTypeSelectionScreen({
    Key? key,
    required this.selectedDate,
    required this.storeName,
    required this.sellerName,
  }) : super(key: key);

  @override
  State<InvoiceTypeSelectionScreen> createState() =>
      _InvoiceTypeSelectionScreenState();
}

class _InvoiceTypeSelectionScreenState extends State<InvoiceTypeSelectionScreen>
    with MenuNavigationMixin {
  // 4 أزرار في شبكة 2×2
  late final List<Map<String, dynamic>> _buttons;
  bool _isNavigating = false;
  final FocusNode _screenFocusNode = FocusNode();

  @override
  int get columns => 2;

  @override
  void initState() {
    super.initState();
    _initButtons();
    initMenuNavigation(_buttons.length);
  }

  @override
  void dispose() {
    _screenFocusNode.dispose();
    disposeMenuNavigation();
    super.dispose();
  }

  void _initButtons() {
    _buttons = [
      // الصف الأول (عمودين)
      {
        'icon': Icons.person,
        'label': 'فاتورة زبون',
        'color': Colors.indigo[700]!,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerSelectionScreen(
                selectedDate: widget.selectedDate,
                storeName: widget.storeName,
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.local_shipping,
        'label': 'مبيعات مورد',
        'color': Colors.teal[700]!,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupplierSelectionScreen(
                selectedDate: widget.selectedDate,
                storeName: widget.storeName,
                reportType: 'sales',
              ),
            ),
          );
        },
      },
      // الصف الثاني (عمودين)
      {
        'icon': Icons.shopping_cart_checkout,
        'label': 'مشتريات من\nمورد',
        'color': Colors.red[700]!,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SupplierSelectionScreen(
                selectedDate: widget.selectedDate,
                storeName: widget.storeName,
                reportType: 'purchases',
              ),
            ),
          );
        },
      },
      {
        'icon': Icons.shopping_basket_sharp,
        'label': 'فاتورة مورد',
        'color': const Color.fromARGB(255, 95, 109, 18),
        'onTap': () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => SupplierBillEntryDialog(
              selectedDate: widget.selectedDate,
              storeName: widget.storeName,
              sellerName: widget.sellerName,
            ),
          ));
        },
      },
    ];
  }

  void _handleKeyEvent(RawKeyEvent event) {
    // التحقق من أن هذه الشاشة هي الشاشة النشطة حالياً وليست مغطاة بصفحة أخرى
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;

    if (_isNavigating) return;

    handleKeyEvent(event, _buttons.length);
    if (event is RawKeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _isNavigating = true;
      executeButtonAt(focusedIndex, _buttons);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _isNavigating = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKey: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نوع التقرير'),
          centerTitle: true,
          backgroundColor: Colors.blueGrey[800],
          foregroundColor: Colors.white,
          leadingWidth: 100,
          leading: ExitButton(
            onPressed: () => Navigator.of(context).pop(),
            width: 80,
            height: 40,
            text: 'خروج',
          ),
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 500;
              if (isSmall) {
                return _buildSmallScreen();
              }
              return _buildLargeScreen();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLargeScreen() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 60.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // الصف الأول (2 زر)
          Row(
            children: [
              Expanded(
                child: _buildMenuButton(index: 0),
              ),
              const SizedBox(width: 20), // <-- تباعد
              Expanded(
                child: _buildMenuButton(index: 1),
              ),
            ],
          ),
          const SizedBox(height: 40),
          // الصف الثاني (2 زر)
          Row(
            children: [
              Expanded(
                child: _buildMenuButton(index: 2),
              ),
              const SizedBox(width: 20), // <-- تباعد
              Expanded(
                child: _buildMenuButton(index: 3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Column(
        children: List.generate(_buttons.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _buildMenuButton(index: index),
          );
        }),
      ),
    );
  }

  Widget _buildMenuButton({required int index}) {
    final button = _buttons[index];
    final isFocused = focusedIndex == index;

    return SharedMenuButton(
      icon: button['icon'],
      label: button['label'],
      color: button['color'],
      isFocused: isFocused,
      isEnabled: true,
      onTap: () {
        if (_isNavigating) return;
        _isNavigating = true;
        setState(() {
          focusedIndex = index;
        });
        if (button['onTap'] != null) {
          (button['onTap'] as VoidCallback)();
        }
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _isNavigating = false;
          }
        });
      },
    );
  }
}
