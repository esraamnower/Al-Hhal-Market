import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// زر قائمة موحد يستخدم في شاشات القوائم الرئيسية (مثل الحركة اليومية واختيار نوع الفاتورة)
/// يوفر:
/// - تأثير التكبير عند التركيز
/// - إطار ذهبي عند التركيز
/// - تدرج لوني احترافي
/// - دعم أيقونة ونص متعدد الأسطر
class SharedMenuButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isFocused;
  final bool isEnabled;
  final double? height;
  final bool showAdminStar;

  const SharedMenuButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isFocused = false,
    this.isEnabled = true,
    this.height,
    this.showAdminStar = false,
  }) : super(key: key);

  @override
  State<SharedMenuButton> createState() => _SharedMenuButtonState();
}

class _SharedMenuButtonState extends State<SharedMenuButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
    if (widget.isFocused) {
      _scaleController.forward();
    }
  }

  @override
  void didUpdateWidget(SharedMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused != oldWidget.isFocused) {
      if (widget.isFocused) {
        _scaleController.forward();
      } else {
        _scaleController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = widget.isFocused;
    final isEnabled = widget.isEnabled;
    final color = widget.color;
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonHeight = widget.height ?? (screenWidth / 4) / 1.5;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            elevation: isFocused ? 20 : 8,
            borderRadius: BorderRadius.circular(20),
            shadowColor: isFocused
                ? const Color(0xFFFFD700).withOpacity(0.8)
                : color.withOpacity(0.5),
            child: InkWell(
              onTap: isEnabled ? widget.onTap : null,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: buttonHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isFocused
                        ? [
                            const Color(0xFF1B5E20),
                            const Color(0xFF2E7D32),
                            const Color(0xFF388E3C),
                            const Color(0xFF4CAF50),
                          ]
                        : [
                            isEnabled ? color : Colors.grey[400]!,
                            isEnabled
                                ? color.withOpacity(0.7)
                                : Colors.grey[300]!,
                          ],
                    stops: isFocused ? const [0.0, 0.3, 0.7, 1.0] : null,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: isFocused
                      ? Border.all(color: const Color(0xFFFFD700), width: 6)
                      : Border.all(
                          color: const Color.fromARGB(0, 241, 66, 66),
                          width: 4,
                        ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFD700).withOpacity(0.8),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                          BoxShadow(
                            color: const Color(0xFF4CAF50).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: const Color(0xFF81C784).withOpacity(0.4),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ]
                      : isEnabled
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                ),
                child: Stack(
                  children: [
                    // الإطار اللامع
                    if (isFocused)
                      Positioned(
                        top: -2,
                        left: -2,
                        right: -2,
                        bottom: -2,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFFFFD700).withOpacity(0.6),
                                const Color(0xFFFFF176).withOpacity(0.4),
                                const Color(0xFF4CAF50).withOpacity(0.5),
                                const Color(0xFFFFD700).withOpacity(0.6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.icon,
                            size: isFocused ? 85 : 70,
                            color: isFocused
                                ? const Color(0xFFFFD700)
                                : (isEnabled ? Colors.white : Colors.grey[200]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isFocused
                                  ? const Color(0xFFFFF9C4)
                                  : (isEnabled
                                      ? Colors.white
                                      : Colors.grey[200]),
                              fontSize: isFocused ? 30 : 25,
                              fontWeight: FontWeight.bold,
                              letterSpacing: isFocused ? 1.5 : 1.0,
                              shadows: isFocused
                                  ? [
                                      Shadow(
                                        color: const Color(0xFFFFD700)
                                            .withOpacity(0.9),
                                        blurRadius: 15,
                                      ),
                                      const Shadow(
                                        color: Colors.black54,
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          if (widget.showAdminStar)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Icon(
                                Icons.star,
                                size: isFocused ? 35 : 30,
                                color: isFocused
                                    ? const Color(0xFFFFD700)
                                    : Colors.yellow,
                              ),
                            ),
                          if (isFocused)
                            Padding(
                              padding: const EdgeInsets.only(top: 15),
                              child: Container(
                                width: 60,
                                height: 5,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFF176),
                                      Color(0xFF4CAF50),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700)
                                          .withOpacity(0.9),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
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
      },
    );
  }
}

/// مزيج (Mixin) للتحكم في التنقل بين الأزرار باستخدام الأسهم والمؤشر الذهبي
/// يجب استخدامه في State مع المتغيرات التالية:
/// - List<FocusNode> focusNodes
/// - int focusedIndex
/// - bool isSmallScreen
/// - int columns (عدد الأعمدة في الشبكة)
mixin MenuNavigationMixin<T extends StatefulWidget> on State<T> {
  late List<FocusNode> focusNodes;
  int focusedIndex = 0;
  bool isSmallScreen = false;
  int get columns => 5; // يُعاد تعريفه في كل شاشة حسب عدد الأعمدة

  void initMenuNavigation(int buttonCount) {
    focusNodes = List.generate(buttonCount, (_) => FocusNode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        focusNodes[0].requestFocus();
        focusedIndex = 0;
        setState(() {});
      }
    });
  }

  void disposeMenuNavigation() {
    for (var node in focusNodes) {
      node.dispose();
    }
  }

  void handleKeyEvent(RawKeyEvent event, int totalButtons) {
    if (event is! RawKeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveFocusLeft(totalButtons);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveFocusRight(totalButtons);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocusUp(totalButtons);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocusDown(totalButtons);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _executeCurrentFocus();
    }
  }

  void _moveFocusLeft(int totalButtons) {
    if (isSmallScreen) return;
    if (focusedIndex % columns < columns - 1 &&
        focusedIndex + 1 < totalButtons) {
      _setFocus(focusedIndex + 1);
    }
  }

  void _moveFocusRight(int totalButtons) {
    if (isSmallScreen) return;
    if (focusedIndex % columns > 0) {
      _setFocus(focusedIndex - 1);
    }
  }

  void _moveFocusUp(int totalButtons) {
    if (isSmallScreen) {
      if (focusedIndex > 0) _setFocus(focusedIndex - 1);
      return;
    }
    if (focusedIndex >= columns) {
      _setFocus(focusedIndex - columns);
    }
  }

  void _moveFocusDown(int totalButtons) {
    if (isSmallScreen) {
      if (focusedIndex < totalButtons - 1) _setFocus(focusedIndex + 1);
      return;
    }
    if (focusedIndex + columns < totalButtons) {
      _setFocus(focusedIndex + columns);
    }
  }

  void _setFocus(int index) {
    if (!mounted) return;
    setState(() {
      focusedIndex = index;
    });
    focusNodes[index].requestFocus();
  }

  void _executeCurrentFocus() {
    // تُنفذ في الشاشة نفسها عبر تمرير callback
  }

  /// يجب استدعاؤها من الشاشة لتنفيذ الزر الحالي
  void executeButtonAt(int index, List<dynamic> buttons) {
    if (index < 0 || index >= buttons.length) return;
    final button = buttons[index];
    if (button is Map && button['onTap'] != null) {
      (button['onTap'] as VoidCallback)();
    }
  }
}
