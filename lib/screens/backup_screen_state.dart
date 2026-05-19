import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../widgets/exit_button.dart';

class _BackupInfo {
  final String path;
  final DateTime date;
  final int sizeBytes;

  _BackupInfo(
      {required this.path, required this.date, required this.sizeBytes});

  String _pad(int v) => v.toString().padLeft(2, '0');

  String get formattedDate =>
      '${date.year}/${_pad(date.month)}/${_pad(date.day)}  ${_pad(date.hour)}:${_pad(date.minute)}';

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024)
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get fileName => path.split('/').last;
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  static const _folders = [
    'ReceiptJournals',
    'BoxJournals',
    'SalesJournals',
    'PurchaseJournals',
    'SupplierIndex',
    'CustomerIndex',
  ];

  bool _isBusy = false;
  String _statusMsg = '';
  bool _isSuccess = false;
  List<_BackupInfo> _backups = [];

  void _handleBackButton() {
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  // ============================================
  // دالة متوافقة مع Android و Windows
  // ============================================
  Future<String?> _getAppDataPath() async {
    try {
      Directory? dir;
      if (Platform.isAndroid) {
        dir = await getExternalStorageDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      // المجلد الجذري للمشروع
      return '${dir!.path}/alhalmarket';
    } catch (_) {
      return null;
    }
  }

  // ============================================
  // دالة الحصول على مجلد النسخ الاحتياطي (متوافق)
  // ============================================
  Future<Directory> _getBackupFolder() async {
    Directory dir;

    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/alhalmarket_Backups');
    } else if (Platform.isWindows) {
      final documents = await getApplicationDocumentsDirectory();
      dir = Directory('${documents.path}/alhalmarket_Backups');
    } else {
      final documents = await getApplicationDocumentsDirectory();
      dir = Directory('${documents.path}/alhalmarket_Backups');
    }

    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _createBackup() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _isSuccess = false;
      _statusMsg = 'جارٍ النسخ الاحتياطي...';
    });

    try {
      final appPath = await _getAppDataPath();
      if (appPath == null) throw Exception('تعذّر الوصول إلى مجلد البيانات');

      final backupDir = await _getBackupFolder();
      final now = DateTime.now();
      final ts =
          '${now.year}-${_pad(now.month)}-${_pad(now.day)}_${_pad(now.hour)}-${_pad(now.minute)}-${_pad(now.second)}';
      final zipPath = '${backupDir.path}/backup_$ts.zip';

      final encoder = ZipFileEncoder()..create(zipPath);
      int count = 0;

      for (final folderName in _folders) {
        final folder = Directory(
            '$appPath${Platform.pathSeparator}$folderName'); // استخدام فاصل النظام

        // استخدام فاصل النظام للتوافق مع أندرويد وويندوز
        final fallbackFolder = Directory('$appPath/$folderName');
        final actualFolder = (await folder.exists())
            ? folder
            : (await fallbackFolder.exists() ? fallbackFolder : null);

        if (actualFolder == null) continue;

        await for (final entity in actualFolder.list(recursive: true)) {
          if (entity is File) {
            // 💡 التعديل الأهم: جلب المسار النسبي بشكل آمن دون الاعتماد على نوع الشرطة المائلة
            final relativePath =
                entity.path.substring(appPath.length + 1).replaceAll('\\', '/');
            encoder.addFile(entity, relativePath);
            count++;
          }
        }
      }

      encoder.close();

      if (count == 0) {
        final emptyZip = File(zipPath);
        if (await emptyZip.exists()) await emptyZip.delete();
        throw Exception('لم يتم العثور على ملفات بيانات لنسخها');
      }

      setState(() {
        _isBusy = false;
        _isSuccess = true;
        _statusMsg = 'تم حفظ $count ملف بنجاح ✓';
      });

      await _loadBackups();

      if (mounted) {
        try {
          await Share.shareXFiles(
            [XFile(zipPath)],
            text: 'نسخة احتياطية – سجل السوق $ts',
          );
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ مشاركة غير مدعومة: $e');
          _showInfoDialog(
            'تم النسخ الاحتياطي ✓',
            'تم حفظ النسخة في:\n${backupDir.path}\n\nاسم الملف: backup_$ts.zip',
          );
        }
      }
    } catch (e) {
      setState(() {
        _isBusy = false;
        _isSuccess = false;
        _statusMsg = 'خطأ: $e';
      });
    }
  }

  Future<void> _restoreFromFile() async {
    final confirm = await _confirmRestoreDialog();
    if (confirm != true) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'اختر ملف النسخة الاحتياطية',
    );
    if (result == null || result.files.single.path == null) return;

    await _doRestore(result.files.single.path!);
  }

  Future<void> _restoreFromList(_BackupInfo backup) async {
    final confirm = await _confirmRestoreDialog();
    if (confirm != true) return;
    await _doRestore(backup.path);
  }

  Future<void> _doRestore(String zipPath) async {
    setState(() {
      _isBusy = true;
      _isSuccess = false;
      _statusMsg = 'جارٍ استرجاع البيانات...';
    });

    try {
      final appPath = await _getAppDataPath();
      if (appPath == null) throw Exception('تعذّر الوصول إلى مجلد البيانات');

      // قراءة ملف ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      int count = 0;

      for (final file in archive) {
        if (!file.isFile) continue;

        final data = file.content as List<int>;
        final targetPath = '$appPath/${file.name}';

        final out = File(targetPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(data);
        count++;
      }

      setState(() {
        _isBusy = false;
        _isSuccess = true;
        _statusMsg = 'تم استرجاع $count ملف بنجاح ✓';
      });

      if (mounted) {
        _showInfoDialog(
          'تم الاسترجاع ✓',
          'تم استرجاع $count ملف.\nأعد تشغيل التطبيق لرؤية البيانات.',
        );
      }
    } catch (e) {
      setState(() {
        _isBusy = false;
        _isSuccess = false;
        _statusMsg = 'خطأ في الاسترجاع: $e';
      });
    }
  }

  Future<void> _loadBackups() async {
    try {
      final dir = await _getBackupFolder();
      final List<_BackupInfo> list = [];

      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.zip')) {
          final stat = await f.stat();
          list.add(_BackupInfo(
            path: f.path,
            date: stat.modified,
            sizeBytes: stat.size,
          ));
        }
      }

      list.sort((a, b) => b.date.compareTo(a.date));
      if (mounted) setState(() => _backups = list);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ خطأ في تحميل النسخ الاحتياطية: $e');
      }
    }
  }

  Future<void> _deleteBackup(_BackupInfo backup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف النسخة'),
        content: Text('حذف ${backup.fileName}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await File(backup.path).delete();
      await _loadBackups();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم حذف النسخة الاحتياطية')),
        );
      }
    }
  }

  Future<bool?> _confirmRestoreDialog() => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 44),
          title: const Text('تأكيد الاسترجاع', textAlign: TextAlign.center),
          content: const Text(
            'سيتم استبدال البيانات الحالية.\nهذا الإجراء لا يمكن التراجع عنه.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child:
                  const Text('متابعة', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  void _showInfoDialog(String title, String msg) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: Text(title, textAlign: TextAlign.center),
          content: Text(msg, textAlign: TextAlign.center),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'))
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          toolbarHeight: 70,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 140),
              const Text(
                'النسخ الاحتياطي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
              ),
              ExitButton(
                onPressed: _handleBackButton,
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: const Color(0xFF0F4C5C),
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _buildMainButton(),
              const SizedBox(height: 16),
              _buildRestoreFromFileButton(),
              if (_statusMsg.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildStatusBanner(),
              ],
              const SizedBox(height: 28),
              _buildBackupsList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton() {
    return Material(
      borderRadius: BorderRadius.circular(18),
      color: Colors.transparent,
      child: InkWell(
        onTap: _isBusy ? null : _createBackup,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isBusy)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Colors.white),
                )
              else
                const Icon(Icons.backup_rounded, color: Colors.white, size: 32),
              const SizedBox(width: 16),
              Text(
                _isBusy ? 'جارٍ النسخ...' : 'نسخ احتياطي الآن',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestoreFromFileButton() {
    return OutlinedButton.icon(
      onPressed: _isBusy ? null : _restoreFromFile,
      icon: const Icon(Icons.folder_open_rounded),
      label: const Text('استرجاع من ملف ZIP', style: TextStyle(fontSize: 16)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.purpleAccent,
        side: const BorderSide(color: Colors.purpleAccent, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: (_isSuccess ? Colors.green : Colors.red).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (_isSuccess ? Colors.greenAccent : Colors.redAccent)
              .withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMsg,
              style: TextStyle(
                color: _isSuccess ? Colors.greenAccent : Colors.redAccent,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded,
                color: Colors.tealAccent, size: 20),
            const SizedBox(width: 8),
            const Text(
              'النسخ المحفوظة',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              onPressed: _loadBackups,
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.tealAccent, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'تحديث',
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_backups.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_rounded,
                    color: Colors.white.withOpacity(0.25), size: 36),
                const SizedBox(height: 8),
                Text(
                  'لا توجد نسخ احتياطية محفوظة بعد',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.35), fontSize: 14),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _backups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _buildBackupTile(_backups[i], i == 0),
          ),
      ],
    );
  }

  Widget _buildBackupTile(_BackupInfo backup, bool isLatest) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLatest
              ? Colors.tealAccent.withOpacity(0.35)
              : Colors.white.withOpacity(0.09),
          width: isLatest ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isLatest ? Colors.tealAccent : Colors.blueGrey)
                .withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.folder_zip_rounded,
              color: isLatest ? Colors.tealAccent : Colors.blueGrey[300],
              size: 22),
        ),
        title: Row(
          children: [
            Text(backup.formattedDate,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('الأحدث',
                    style: TextStyle(color: Colors.tealAccent, fontSize: 10)),
              ),
            ],
          ],
        ),
        subtitle: Text(backup.formattedSize,
            style:
                TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _restoreFromList(backup),
              icon: const Icon(Icons.restore_rounded,
                  color: Colors.orangeAccent, size: 22),
              tooltip: 'استرجاع',
            ),
            IconButton(
              onPressed: () => Share.shareXFiles([XFile(backup.path)]),
              icon: const Icon(Icons.share_rounded,
                  color: Colors.lightBlueAccent, size: 22),
              tooltip: 'مشاركة',
            ),
            IconButton(
              onPressed: () => _deleteBackup(backup),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 22),
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }
}
