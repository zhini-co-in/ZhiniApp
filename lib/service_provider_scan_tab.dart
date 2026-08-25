import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'constants/api_config.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';

/// Job-site appliance scanner for service providers.
///
/// Reuses the same on-device detection model + OCR brand/warranty
/// extraction as the customer-facing ScanTab, but is READ-ONLY: nothing
/// gets saved to a home/room, and there's no "nearby service centers"
/// list (the provider standing there IS the service). It just tells the
/// provider what the appliance is, its brand, and its warranty status.
class ServiceProviderScanTab extends StatefulWidget {
  const ServiceProviderScanTab({super.key});

  @override
  State<ServiceProviderScanTab> createState() => _ServiceProviderScanTabState();
}

class _ServiceProviderScanTabState extends State<ServiceProviderScanTab>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _busy = false;

  Interpreter? _interpreter;
  List<String> _labels = [];
  String? _resultLabel;
  double? _resultConfidence;
  String? _brandText;

  List<String> _knownCompanies = [];
  String? _matchedCompany;
  String? _manualBrand;

  static const Set<String> _invalidLabels = {
    'no appliance found',
    'no object',
    'no object detected',
    'none',
    'background',
    'unknown',
  };

  bool get _isValidDetection =>
      _resultLabel != null && !_invalidLabels.contains(_resultLabel!.trim().toLowerCase());

  String? get _effectiveBrand => _matchedCompany ?? _manualBrand;

  String? _detectedWarranty;
  String? _manualWarranty;

  bool get _isUnderWarrantyNow =>
      WarrantyUtils.isActive(_detectedWarranty ?? _manualWarranty);

  bool _showDetectedCard = false;
  bool _aiThinking = false;
  File? _lastCapturedImage;

  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadModel();
    _loadCompanyDataset();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCameraView());
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData.split('\n').where((e) => e.trim().isNotEmpty).toList();
    } catch (e) {
      debugPrint('Model load error: $e');
    }
  }

  Future<void> _loadCompanyDataset() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/companies.json');
      final List<dynamic> list = jsonDecode(jsonStr);
      _knownCompanies = list.cast<String>();
    } catch (e) {
      debugPrint('Company dataset load error: $e');
    }
  }

  String? _matchCompanyName(String ocrText, {int threshold = 75}) {
    if (_knownCompanies.isEmpty || ocrText.isEmpty) return null;
    final lines =
        ocrText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    String? bestMatch;
    int bestScore = 0;
    for (var line in lines) {
      for (var company in _knownCompanies) {
        final score = partialRatio(line.toLowerCase(), company.toLowerCase());
        if (score > bestScore) {
          bestScore = score;
          bestMatch = company;
        }
      }
    }
    return bestScore >= threshold ? bestMatch : null;
  }

  String? _extractWarranty(String ocrText) {
    if (ocrText.isEmpty) return null;
    final text = ocrText.toLowerCase();

    final yearMatch = RegExp(r'(\d+)\s*year[s]?\s*warranty').firstMatch(text);
    if (yearMatch != null) {
      final n = yearMatch.group(1);
      return '$n Year${n == '1' ? '' : 's'}';
    }

    final dateMatch = RegExp(
      r'warrant\w*\s*(?:upto|till|until|valid till)?\s*[:\-]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4})',
    ).firstMatch(text);
    if (dateMatch != null) return dateMatch.group(1);

    return null;
  }

  Future<void> _openCameraView() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController =
          CameraController(backCamera, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      _detectionTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
        if (!_showDetectedCard) _captureAndDetect();
      });
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _captureAndDetect() async {
    if (_busy ||
        _interpreter == null ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    _busy = true;
    try {
      final XFile file = await _cameraController!.takePicture();
      final imageFile = File(file.path);
      await _detectProduct(imageFile);
      await _extractText(imageFile);

      final previousImage = _lastCapturedImage;
      _lastCapturedImage = imageFile;
      if (previousImage != null && previousImage.path != imageFile.path) {
        previousImage.delete().catchError((_) => previousImage);
      }

      if (_isValidDetection && (_resultConfidence ?? 0) > 0.6 && !_showDetectedCard) {
        if (mounted) {
          await _cameraController?.pausePreview();
          setState(() => _showDetectedCard = true);
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _detectProduct(File imageFile) async {
    if (_interpreter == null) return;
    try {
      final rawImage = img.decodeImage(await imageFile.readAsBytes());
      if (rawImage == null) return;
      const inputSize = 224;
      final resized = img.copyResize(rawImage, width: inputSize, height: inputSize);

      var input = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (y) => List.generate(inputSize, (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble()];
          }),
        ),
      );

      var output = List.filled(1 * _labels.length, 0.0).reshape([1, _labels.length]);
      _interpreter!.run(input, output);

      final scores = output[0] as List<double>;
      double maxScore = 0;
      int maxIndex = 0;
      for (int i = 0; i < scores.length; i++) {
        if (scores[i] > maxScore) {
          maxScore = scores[i];
          maxIndex = i;
        }
      }
      if (mounted) {
        setState(() {
          _resultLabel = _labels.isNotEmpty ? _labels[maxIndex] : 'Unknown';
          _resultConfidence = maxScore;
        });
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    }
  }

  Future<void> _extractText(File imageFile) async {
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
      final text = recognizedText.text.trim();
      if (mounted) {
        setState(() {
          _brandText = text.isNotEmpty ? text : null;
          _matchedCompany = _matchCompanyName(text);
          final autoWarranty = _extractWarranty(text);
          if (autoWarranty != null) _detectedWarranty = autoWarranty;
        });
      }
    } catch (e) {
      debugPrint('OCR error: $e');
    }
  }

  Future<void> _runAiAssist() async {
    if (_lastCapturedImage == null) {
      _showSnack('No recent photo to analyze. Point the camera and wait a moment.');
      return;
    }

    setState(() => _aiThinking = true);
    try {
      final bytes = await _lastCapturedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(ApiConfig.aiAssistUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'imageBase64': base64Image, 'mimeType': 'image/jpeg'}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          var aiBrand = data['data']['brand']?.toString().trim();
          var aiProduct = data['data']['product']?.toString().trim();

          const unknownValues = {
            'unidentifiable',
            'unknown',
            'n/a',
            'not identifiable',
            'not found',
            'unable to identify',
          };
          if (aiBrand != null && unknownValues.contains(aiBrand.toLowerCase())) aiBrand = null;
          if (aiProduct != null && unknownValues.contains(aiProduct.toLowerCase())) {
            aiProduct = null;
          }

          if (aiBrand == null && aiProduct == null) {
            _showSnack('Zhini could not identify this clearly. Try a closer photo.');
            return;
          }

          if (mounted) {
            setState(() {
              if (aiBrand != null && aiBrand.isNotEmpty) _matchedCompany = aiBrand;
              if (aiProduct != null && aiProduct.isNotEmpty) _resultLabel = aiProduct;
            });
          }
          _showSnack('Updated: ${_matchedCompany ?? "Unbranded"} • ${_resultLabel ?? "—"}');
        } else {
          _showSnack('Zhini could not identify this. Try again with better lighting.');
        }
      } else {
        _showSnack('AI check failed (${response.statusCode}). Try again.');
      }
    } catch (e) {
      debugPrint('❌ AI assist error: $e');
      _showSnack('Network error while checking with Zhini AI. Try again.');
    } finally {
      if (mounted) setState(() => _aiThinking = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openWarrantyDialog() {
    final controller = TextEditingController(text: _detectedWarranty ?? _manualWarranty ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text('Warranty', style: AppText.dialogTitle),
        content: AppDialogField(controller: controller, hint: 'e.g. 2 Years or 12/2027'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final value = controller.text.trim();
              setState(() {
                _manualWarranty = value.isNotEmpty ? value : null;
                _detectedWarranty = null;
              });
              Navigator.pop(dialogContext);
            },
            child: const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _openBrandDialog() {
    final controller = TextEditingController(text: _manualBrand ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text('Brand', style: AppText.dialogTitle),
        content: AppDialogField(controller: controller, hint: 'e.g. LG, Samsung, Godrej'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final value = controller.text.trim();
              setState(() => _manualBrand = value.isNotEmpty ? value : null);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _resetForNextScan() {
    setState(() {
      _showDetectedCard = false;
      _resultLabel = null;
      _resultConfidence = null;
      _matchedCompany = null;
      _manualBrand = null;
      _brandText = null;
      _aiThinking = false;
      _detectedWarranty = null;
      _manualWarranty = null;
    });
    _cameraController?.resumePreview();
    _captureAndDetect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    _interpreter?.close();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return !_isCameraReady || _cameraController == null
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _showDetectedCard
            ? _buildDetectedCard()
            : Stack(
                children: [
                  Positioned.fill(child: CameraPreview(_cameraController!)),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Scan appliance',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('Point your camera at the appliance to identify it.',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
  }

  Widget _buildDetectedCard() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.cardBg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Product Detected',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  OutlinedButton.icon(
                    onPressed: _aiThinking ? null : _runAiAssist,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primaryBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: _aiThinking
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child:
                                CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                          )
                        : const Icon(Icons.edit, size: 14, color: AppColors.primary),
                    label: Text(
                      _aiThinking ? 'Checking...' : 'Ask ZHINI',
                      style: AppText.linkAction,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (_lastCapturedImage != null)
                        ? Image.file(_lastCapturedImage!, fit: BoxFit.cover)
                        : const Icon(Icons.ac_unit, color: AppColors.textFaint),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _effectiveBrand ?? 'Unbranded',
                                style: TextStyle(
                                  color: _effectiveBrand != null
                                      ? AppColors.textPrimary
                                      : AppColors.textFaint,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _openBrandDialog,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                _effectiveBrand != null ? 'Edit' : 'Add',
                                style: AppText.linkAction,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_resultLabel ?? '—', style: AppText.body),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: (_detectedWarranty ?? _manualWarranty) != null
                        ? Text(
                            'Warranty: ${_detectedWarranty ?? _manualWarranty}'
                            '${_isUnderWarrantyNow ? " (Active)" : ""}',
                            style: AppText.body,
                          )
                        : const Text('Warranty not detected', style: AppText.faintCaption),
                  ),
                  TextButton(
                    onPressed: _openWarrantyDialog,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      (_detectedWarranty ?? _manualWarranty) != null ? 'Edit' : 'Add',
                      style: AppText.linkAction,
                    ),
                  ),
                ],
              ),

              if (_aiThinking) ...[
                const SizedBox(height: 16),
                Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Zhini thinking...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _resetForNextScan,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: AppColors.primaryBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Scan Another Appliance',
                      style: TextStyle(color: AppColors.primary, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}