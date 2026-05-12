import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/store_db_service.dart';
import 'package:flutter/services.dart';
import '../widgets/exit_button.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String currentStoreName;
  final Function(String) onStoreNameChanged;

  const ChangePasswordScreen({
    super.key,
    required this.currentStoreName,
    required this.onStoreNameChanged,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  int _currentScreen = 0;

  // متغيرات تعديل بيانات البائع
  final _oldSellerNameController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newSellerNameController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _sellerFormKey = GlobalKey<FormState>();

  // متغيرات اسم المحل
  final _storeNameController = TextEditingController();
  final _storeNameFormKey = GlobalKey<FormState>();

  // FocusNodes
  final _oldSellerFocus = FocusNode();
  final _oldPasswordFocus = FocusNode();
  final _newSellerFocus = FocusNode();
  final _newPasswordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();
  final _storeNameFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  String? _currentSellerName;

  @override
  void initState() {
    super.initState();
    _loadStoreName();
    _loadCurrentSeller();
  }

  @override
  void dispose() {
    _oldSellerNameController.dispose();
    _oldPasswordController.dispose();
    _newSellerNameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _storeNameController.dispose();

    _oldSellerFocus.dispose();
    _oldPasswordFocus.dispose();
    _newSellerFocus.dispose();
    _newPasswordFocus.dispose();
    _confirmPasswordFocus.dispose();
    _storeNameFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSeller() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentSellerName = prefs.getString('current_seller');
      // لا نقوم بتعبئة الحقول تلقائياً
    });
  }

  Future<Map<String, String>> _getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getString('accounts');
    return accounts != null
        ? Map<String, String>.from(json.decode(accounts))
        : {};
  }

  Future<void> _updateSellerData() async {
    if (!_sellerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final oldSellerName = _oldSellerNameController.text;
    final oldPassword = _oldPasswordController.text;
    final newSellerName = _newSellerNameController.text;
    final newPassword = _newPasswordController.text;

    // التحقق من الهوية
    final accounts = await _getAccounts();

    if (!accounts.containsKey(oldSellerName) ||
        accounts[oldSellerName] != oldPassword) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'اسم البائع أو كلمة المرور القديمة غير صحيحة';
      });
      return;
    }

    // إذا لم يتم إدخال اسم جديد، نستخدم الاسم القديم
    final finalNewSellerName =
        newSellerName.isEmpty ? oldSellerName : newSellerName;

    // تحديث البيانات
    final updatedAccounts = Map<String, String>.from(accounts);

    // إذا تم تغيير اسم البائع
    if (oldSellerName != finalNewSellerName) {
      // حفظ الحساب القديم كتاريخ
      final prefs = await SharedPreferences.getInstance();
      final oldAccountsJson = prefs.getString('old_accounts');
      final Map<String, String> oldAccounts = oldAccountsJson != null
          ? Map<String, String>.from(json.decode(oldAccountsJson))
          : {};

      oldAccounts[oldSellerName] = updatedAccounts[oldSellerName]!;
      await prefs.setString('old_accounts', json.encode(oldAccounts));

      // حذف الحساب القديم
      updatedAccounts.remove(oldSellerName);
    }

    // تحديث كلمة المرور إذا تم إدخال كلمة مرور جديدة، وإلا نستخدم القديمة
    final finalPassword = newPassword.isNotEmpty ? newPassword : oldPassword;
    updatedAccounts[finalNewSellerName] = finalPassword;

    // حفظ التغييرات
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('accounts', json.encode(updatedAccounts));

    // إذا كان هذا هو البائع الحالي، تحديثه
    if (_currentSellerName == oldSellerName) {
      await prefs.setString('current_seller', finalNewSellerName);
      _currentSellerName = finalNewSellerName;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تحديث بيانات البائع بنجاح'),
        backgroundColor: Colors.green,
      ),
    );

    // إعادة تعيين الحقول
    setState(() {
      _isLoading = false;
      _errorMessage = null;

      // تنظيف الحقول بعد النجاح
      _oldSellerNameController.clear();
      _oldPasswordController.clear();
      _newSellerNameController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _loadStoreName() async {
    final storeDbService = StoreDbService();
    final savedStoreName = await storeDbService.getStoreName();
    if (savedStoreName != null) {
      setState(() {
        _storeNameController.text = savedStoreName;
      });
    }
  }

  Future<void> _changeStoreName() async {
    if (!_storeNameFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final newStoreName = _storeNameController.text;
    final storeDbService = StoreDbService();

    await storeDbService.saveStoreName(newStoreName);

    // تحديث اسم المحل في الشاشة السابقة
    widget.onStoreNameChanged(newStoreName);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تغيير اسم المحل بنجاح'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _isLoading = false;
      _currentScreen = 0;
    });
  }

  void _resetToSelection() {
    setState(() {
      _currentScreen = 0;
      _errorMessage = null;
      _oldSellerNameController.clear();
      _oldPasswordController.clear();
      _newSellerNameController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).size.width > 600;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_currentScreen == 0) {
            Navigator.of(context).pop();
          } else {
            _resetToSelection();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal[400]!, Colors.teal[700]!],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              toolbarHeight: kToolbarHeight + 20,
              title: Row(
                children: [
                  ExitButton(
                    onPressed: () {
                      if (_currentScreen == 0) {
                        Navigator.of(context).pop();
                      } else {
                        _resetToSelection();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getAppBarTitle(),
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
              backgroundColor: Colors.teal[600],
              foregroundColor: Colors.white,
            ),
            body: _buildCurrentScreen(isLandscape),
          ),
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentScreen) {
      case 0:
        return 'الإعدادات';
      case 1:
        return 'تعديل بيانات البائع';
      case 2:
        return 'تغيير اسم المحل';
      default:
        return 'الإعدادات';
    }
  }

  Widget _buildCurrentScreen(bool isLandscape) {
    switch (_currentScreen) {
      case 0:
        return _buildSelectionScreen();
      case 1:
        return _buildSellerDataScreen(isLandscape);
      case 2:
        return _buildStoreNameChangeScreen(isLandscape);
      default:
        return _buildSelectionScreen();
    }
  }

  Widget _buildSelectionScreen() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSelectionOption(
                icon: Icons.person,
                label: 'بيانات البائع',
                description: 'تغيير الاسم وكلمة المرور',
                onTap: () => setState(() => _currentScreen = 1),
              ),
              _buildSelectionOption(
                icon: Icons.store,
                label: 'اسم المحل',
                description: 'تغيير اسم المحل',
                onTap: () => setState(() => _currentScreen = 2),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSelectionOption({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 35, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerDataScreen(bool isLandscape) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = isLandscape ? 900 : 500;
        final double fontSize = constraints.maxWidth > 800 ? 18 : 14;
        final double iconSize = constraints.maxWidth > 800 ? 24 : 20;
        final double padding = constraints.maxWidth > 800 ? 20.0 : 12.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isLandscape ? 30.0 : 16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Form(
                key: _sellerFormKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // قسم التحقق من الهوية
                    Container(
                      padding: EdgeInsets.all(padding),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'التحقق من الهوية',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: fontSize + 2,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: padding),
                          if (isLandscape)
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInputField(
                                    _oldPasswordController,
                                    'كلمة المرور الحالية',
                                    true,
                                    focusNode: _oldPasswordFocus,
                                    onSubmitted: () => FocusScope.of(context)
                                        .requestFocus(_newSellerFocus),
                                    icon: Icons.lock,
                                    isRequired: true,
                                    fontSize: fontSize,
                                    iconSize: iconSize,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildInputField(
                                    _oldSellerNameController,
                                    'اسم البائع الحالي',
                                    false,
                                    focusNode: _oldSellerFocus,
                                    onSubmitted: () => FocusScope.of(context)
                                        .requestFocus(_oldPasswordFocus),
                                    icon: Icons.person,
                                    isRequired: true,
                                    fontSize: fontSize,
                                    iconSize: iconSize,
                                  ),
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _buildInputField(
                                  _oldSellerNameController,
                                  'اسم البائع الحالي',
                                  false,
                                  focusNode: _oldSellerFocus,
                                  onSubmitted: () => FocusScope.of(context)
                                      .requestFocus(_oldPasswordFocus),
                                  icon: Icons.person,
                                  isRequired: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                                SizedBox(height: padding),
                                _buildInputField(
                                  _oldPasswordController,
                                  'كلمة المرور الحالية',
                                  true,
                                  focusNode: _oldPasswordFocus,
                                  onSubmitted: () => FocusScope.of(context)
                                      .requestFocus(_newSellerFocus),
                                  icon: Icons.lock,
                                  isRequired: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: padding + 8),

                    // قسم التعديل
                    Container(
                      padding: EdgeInsets.all(padding),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'تعديل البيانات',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: fontSize + 2,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: padding),
                          if (isLandscape)
                            Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputField(
                                        _newPasswordController,
                                        'كلمة المرور الجديدة (اختياري)',
                                        true,
                                        focusNode: _newPasswordFocus,
                                        onSubmitted: () =>
                                            FocusScope.of(context).requestFocus(
                                                _confirmPasswordFocus),
                                        icon: Icons.lock_outline,
                                        isRequired: false,
                                        optionalField: true,
                                        fontSize: fontSize,
                                        iconSize: iconSize,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _buildInputField(
                                        _newSellerNameController,
                                        'اسم البائع الجديد (اختياري)',
                                        false,
                                        focusNode: _newSellerFocus,
                                        onSubmitted: () =>
                                            FocusScope.of(context).requestFocus(
                                                _newPasswordFocus),
                                        icon: Icons.person_add,
                                        isRequired: false,
                                        optionalField: true,
                                        fontSize: fontSize,
                                        iconSize: iconSize,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: padding),
                                _buildInputField(
                                  _confirmPasswordController,
                                  'تأكيد كلمة المرور',
                                  true,
                                  focusNode: _confirmPasswordFocus,
                                  onSubmitted: _updateSellerData,
                                  icon: Icons.lock_reset,
                                  isRequired: false,
                                  optionalField: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                              ],
                            )
                          else
                            Column(
                              children: [
                                _buildInputField(
                                  _newSellerNameController,
                                  'اسم البائع الجديد (اختياري)',
                                  false,
                                  focusNode: _newSellerFocus,
                                  onSubmitted: () => FocusScope.of(context)
                                      .requestFocus(_newPasswordFocus),
                                  icon: Icons.person_add,
                                  isRequired: false,
                                  optionalField: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                                SizedBox(height: padding),
                                _buildInputField(
                                  _newPasswordController,
                                  'كلمة المرور الجديدة (اختياري)',
                                  true,
                                  focusNode: _newPasswordFocus,
                                  onSubmitted: () => FocusScope.of(context)
                                      .requestFocus(_confirmPasswordFocus),
                                  icon: Icons.lock_outline,
                                  isRequired: false,
                                  optionalField: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                                SizedBox(height: padding),
                                _buildInputField(
                                  _confirmPasswordController,
                                  'تأكيد كلمة المرور',
                                  true,
                                  focusNode: _confirmPasswordFocus,
                                  onSubmitted: _updateSellerData,
                                  icon: Icons.lock_reset,
                                  isRequired: false,
                                  optionalField: true,
                                  fontSize: fontSize,
                                  iconSize: iconSize,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: padding + 8),

                    if (_errorMessage != null)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(padding),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.yellowAccent,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    SizedBox(height: padding + 8),

                    // أزرار التحكم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                )
                              : ElevatedButton(
                                  onPressed: _updateSellerData,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.teal[700],
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: isLandscape ? 16 : 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'حفظ التغييرات',
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 200
                          : 0,
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

  Widget _buildStoreNameChangeScreen(bool isLandscape) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxWidth = isLandscape ? 700 : 500;
        final double fontSize = constraints.maxWidth > 800 ? 18 : 14;
        final double iconSize = constraints.maxWidth > 800 ? 80 : 60;
        final double padding = constraints.maxWidth > 800 ? 24.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isLandscape ? 40.0 : 20.0),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Form(
                key: _storeNameFormKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: EdgeInsets.all(padding),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.store,
                            size: iconSize,
                            color: Colors.white,
                          ),
                          SizedBox(height: padding),
                          Text(
                            'تغيير اسم المحل',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: fontSize + 4,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'الاسم الحالي: ${widget.currentStoreName}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: fontSize - 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: padding + 8),
                          _buildInputField(
                            _storeNameController,
                            'اسم المحل الجديد',
                            false,
                            focusNode: _storeNameFocus,
                            onSubmitted: _changeStoreName,
                            icon: Icons.store_mall_directory,
                            isRequired: true,
                            fontSize: fontSize,
                            iconSize: iconSize > 24 ? 24 : iconSize,
                          ),
                          if (_errorMessage != null)
                            Padding(
                              padding: EdgeInsets.only(top: padding),
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(padding - 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.yellowAccent,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    SizedBox(height: padding + 8),

                    // أزرار التحكم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white),
                                )
                              : ElevatedButton(
                                  onPressed: _changeStoreName,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.teal[700],
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: isLandscape ? 16 : 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'حفظ',
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 300
                          : 0,
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

  Widget _buildInputField(
    TextEditingController controller,
    String hint,
    bool obscure, {
    required Function()? onSubmitted,
    required FocusNode? focusNode,
    required IconData icon,
    required bool isRequired,
    bool optionalField = false,
    double fontSize = 16,
    double iconSize = 20,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        textInputAction:
            onSubmitted != null ? TextInputAction.done : TextInputAction.next,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
        ),
        onFieldSubmitted: (_) {
          if (onSubmitted != null) onSubmitted();
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white70,
            fontSize: fontSize - 2,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(
            vertical: fontSize + 2,
            horizontal: fontSize + 4,
          ),
          prefixIcon: Icon(icon, color: Colors.white70, size: iconSize),
          errorStyle: const TextStyle(color: Colors.yellowAccent),
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: fontSize - 4,
          ),
        ),
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return 'الرجاء إدخال $hint';
          }

          if (hint.contains('تأكيد') && value!.isNotEmpty) {
            if (value != _newPasswordController.text) {
              return 'كلمتا المرور غير متطابقتين';
            }
          }

          if (hint.contains('كلمة المرور الجديدة') &&
              value!.isNotEmpty &&
              value.length < 4) {
            return 'كلمة المرور قصيرة جداً';
          }

          return null;
        },
      ),
    );
  }
}
