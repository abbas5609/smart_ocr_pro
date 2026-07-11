import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_image_renderer/pdf_image_renderer.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

void main() {
  runApp(const SmartOcrApp());
}

class SmartOcrApp extends StatelessWidget {
  const SmartOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الماسح الذكي OCR',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  String _extractedText = '';
  bool _isLoading = false;
  String _statusMessage = 'اختر الصورة أو الملف لبدء الاستخراج';

  Future<bool> _requestPermissions() async {
    PermissionStatus storage;
    PermissionStatus camera;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        storage = await Permission.photos.request();
      } else {
        storage = await Permission.storage.request();
      }
      camera = await Permission.camera.request();
    } else {
      storage = await Permission.photos.request();
      camera = await Permission.camera.request();
    }

    return storage.isGranted && camera.isGranted;
  }

  Future<String> _recognizeFromImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizer = TextRecognizer();
      final result = await recognizer.processImage(inputImage);
      recognizer.close();
      return result.text;
    } catch (e) {
      return 'خطأ في معالجة الصورة: $e';
    }
  }

  Future<void> _processPdfFile(String filePath) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري تحميل ملف PDF...';
      _extractedText = '';
    });

    try {
      final pdf = await PdfImageRenderer.loadFile(filePath);
      final pageCount = await pdf.getPageCount();
      String fullText = '';

      setState(() => _statusMessage = 'يوجد $pageCount صفحة، جاري المعالجة...');

      for (int i = 0; i < pageCount; i++) {
        setState(() => _statusMessage = 'معالجة الصفحة ${i + 1} من $pageCount...');
        
        final page = await pdf.getPage(i);
        final image = await page.render(
          width: page.width.toInt(),
          height: page.height.toInt(),
          format: PdfImageFormat.png,
        );

        final tempDir = await Directory.systemTemp;
        final tempFile = File('${tempDir.path}/page_$i.png');
        await tempFile.writeAsBytes(image!);

        final pageText = await _recognizeFromImage(tempFile.path);
        fullText += '\n\n=== الصفحة ${i + 1} ===\n$pageText';

        await tempFile.delete();
      }

      await pdf.close();

      setState(() {
        _extractedText = fullText;
        _isLoading = false;
        _statusMessage = 'تم استخراج النص بنجاح من $pageCount صفحة!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'خطأ في معالجة الملف: $e';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!await _requestPermissions()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب منح أذونات الوصول للملفات والكاميرا أولاً')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري اختيار الصورة...';
      _extractedText = '';
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );

      if (image == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'لم يتم اختيار أي صورة';
        });
        return;
      }

      setState(() => _statusMessage = 'جاري استخراج النص...');
      final text = await _recognizeFromImage(image.path);

      setState(() {
        _extractedText = text;
        _isLoading = false;
        _statusMessage = 'تم الاستخراج بنجاح!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'خطأ: $e';
      });
    }
  }

  Future<void> _pickFile() async {
    if (!await _requestPermissions()) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'gif', 'bmp'],
    );

    if (result == null) return;
    final path = result.files.single.path!;

    if (path.toLowerCase().endsWith('.pdf')) {
      await _processPdfFile(path);
    } else {
      setState(() {
        _isLoading = true;
        _statusMessage = 'جاري استخراج النص من الصورة...';
        _extractedText = '';
      });
      final text = await _recognizeFromImage(path);
      setState(() {
        _extractedText = text;
        _isLoading = false;
        _statusMessage = 'تم الاستخراج بنجاح!';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الماسح الذكي للنصوص'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _statusMessage,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('التقاط صورة'),
                  onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo_library),
                  label: const Text('المعرض'),
                  onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(12)),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('ملف PDF / ملفاتي'),
                  onPressed: _isLoading ? null : _pickFile,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Text(
                        _extractedText.isEmpty
                            ? 'سيظهر النص هنا بعد المعالجة...\n\nيدعم:\n• الصور من الكاميرا والمعرض\n• ملفات PDF بعدة صفحات\n• جميع الصور المخزنة في الهاتف'
                            : _extractedText,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
            ),
          ),
          if (_extractedText.isNotEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_all, color: Colors.blue, size: 28),
                    tooltip: 'نسخ النص',
                    onPressed: () => Clipboard.setData(ClipboardData(text: _extractedText)).then((_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ النص!')));
                      }
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.green, size: 28),
                    tooltip: 'مشاركة',
                    onPressed: () => Share.share(_extractedText),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
                    tooltip: 'مسح النتيجة',
                    onPressed: () => setState(() {
                      _extractedText = '';
                      _statusMessage = 'تم المسح، جاهز لملف جديد';
                    }),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
