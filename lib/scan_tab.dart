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
import 'package:url_launcher/url_launcher.dart';
import 'constants/api_config.dart';
import 'services/session_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/room_selector_chips.dart';
import 'widgets/service_provider_card.dart';
import 'package:geolocator/geolocator.dart';

class ScanTab extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;
  final VoidCallback? onBack;
  final String? homeId;
  final ValueChanged<String>? onHomeCreated;
  final String? initialRoom;
  final bool lockRoom;
  final List<String>? knownRooms; // already-existing rooms for this home

  const ScanTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
    this.onBack,
    this.homeId,
    this.onHomeCreated,
    this.initialRoom,
    this.lockRoom = false,
    this.knownRooms,
  });

  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
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

  // Some labels in labels.txt represent "nothing detected" classes rather
  // than a real appliance (e.g. the model's background/negative class).
  // Treat these as no detection at all, instead of showing an "Unbranded"
  // card and querying the service locator with a meaningless product name.
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

  // Warranty state — auto-detected from OCR text, or manually entered by
  // the user via the "Add/Edit" warranty control on the detected card.
  String? _detectedWarranty;
  String? _manualWarranty;
  String? _warrantyCardUrl;
  String? _manualBrand;

  // Effective brand: matched-from-camera takes priority, else manual entry.
  String? get _effectiveBrand => _matchedCompany ?? _manualBrand;

  // Room selection — which room this appliance belongs to. Defaults to
  // 'Hall'. Fixed chips are offered, plus an "Other" chip that opens a
  // dialog for a custom room name.
  static const List<String> _fixedRooms = ['Hall', 'Kitchen', 'Bedroom', 'Bathroom'];
  String _selectedRoom = 'Hall';

  bool get _isSkipFlow =>
      !widget.lockRoom &&
      widget.address.trim().toLowerCase() == 'default' &&
      (widget.knownRooms == null || widget.knownRooms!.isEmpty);

  List<Map<String, dynamic>> _nearbyServices = [];
  // ---- Service list pagination (5 per page, Next/Previous) ----
  static const int _servicePageSize = 5;
  int _servicePage = 0;

  bool _uploadingWarrantyCard = false;
  bool _isSubmitting = false;
  bool _showDetectedCard = false;

  // AI-assist (Gemini) state for the "Asking Zhini" flow
  bool _aiThinking = false;
  File? _lastCapturedImage;
  String? _currentHomeId;

  // Tracks consecutive frames where product was detected but brand wasn't,
  // so we know when to auto-trigger the Gemini AI-assist fallback.
  int _brandMissCount = 0;
  bool _aiAssistTriedForThisDetection = false;

  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  Timer? _detectionTimer;

  @override
  void initState() {
    super.initState();
    _currentHomeId = widget.homeId;
    if (widget.initialRoom != null && widget.initialRoom!.trim().isNotEmpty) {
      _selectedRoom = widget.initialRoom!.trim();
    } else if (_isSkipFlow) {
      _selectedRoom = 'Default';
    }
    _loadModel();
    _loadCompanyDataset();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCameraView());
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model.tflite');
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels =
          labelData.split('\n').where((e) => e.trim().isNotEmpty).toList();
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
    final lines = ocrText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

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

  // Tries to pull a warranty value out of the raw OCR text captured off the
  // appliance label — either a "X year(s) warranty" phrase or a
  // "warranty upto/till <date>" phrase.
  String? _extractWarranty(String ocrText) {
    if (ocrText.isEmpty) return null;
    final text = ocrText.toLowerCase();

    // Pattern 1: "2 year warranty", "5 years warranty"
    final yearMatch =
        RegExp(r'(\d+)\s*year[s]?\s*warranty').firstMatch(text);
    if (yearMatch != null) {
      final n = yearMatch.group(1);
      return '$n Year${n == '1' ? '' : 's'}';
    }

    // Pattern 2: "warranty upto 12/2027", "warranty till 2027"
    final dateMatch = RegExp(
      r'warrant\w*\s*(?:upto|till|until|valid till)?\s*[:\-]?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}|\d{4})',
    ).firstMatch(text);
    if (dateMatch != null) {
      return dateMatch.group(1);
    }

    return null;
  }

  // -----------------------------------------------------------------------
  // WARRANTY STATUS (drives the backend `isUnderWarranty` tier switch)
  // -----------------------------------------------------------------------
  //
  // Date-parsing logic now lives in WarrantyUtils (shared with home_tab.dart)
  // rather than being duplicated here. This screen has no `createdAt` yet
  // (item isn't saved), so we pass no referenceDate — WarrantyUtils defaults
  // to "now" for the "X Year(s)" case.
  //
  // Whether the currently detected/entered warranty value is still active
  // right now. Used to tell the backend whether to run Tier 1 (Brand
  // Authorized) or fall through to Tier 2/3 (neighbor / general).
  bool get _isUnderWarrantyNow =>
      WarrantyUtils.isActive(_detectedWarranty ?? _manualWarranty);

  Future<void> _openCameraView() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(backCamera, ResolutionPreset.medium,
          enableAudio: false);
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

      // Keep the most recent captured frame around (instead of deleting it
      // immediately) so both the appliance-photo upload and the "Asking
      // Zhini" AI-assist flow have an image to use. We only delete the
      // PREVIOUS frame now, once we know we don't need it anymore.
      final previousImage = _lastCapturedImage;
      _lastCapturedImage = imageFile;
      if (previousImage != null && previousImage.path != imageFile.path) {
        previousImage.delete().catchError((_) => previousImage);
      }

      debugPrint(
        '📸 label=$_resultLabel conf=$_resultConfidence brandText="$_brandText" matchedCompany=$_matchedCompany',
      );

      if (_isValidDetection &&
          (_resultConfidence ?? 0) > 0.6 &&
          !_showDetectedCard) {
        // Low confidence (< 80%) OR brand not matched — ask Zhini AI to
        // double-check and get the correct product/brand value.
        final isLowConfidence = (_resultConfidence ?? 0) < 0.8;

        if (_matchedCompany != null && !isLowConfidence) {
          // Brand matched AND confidence is high (>= 80%) — trust the local
          // model, fetch services and show the card right away.
          _brandMissCount = 0;
          final services = await _fetchNearbyServices();
          if (mounted) {
            await _cameraController?.pausePreview();
            setState(() {
              _nearbyServices = services;
              _servicePage = 0;
              _showDetectedCard = true;
            });
          }
        } else {
          // Brand not matched, or confidence too low. The captured photo
          // is NOT auto-sent to the AI backend anymore — the card just
          // shows "Unbranded", and the user taps "Ask ZHINI" manually if
          // they want an AI check.
          _brandMissCount = 0;
          final services = await _fetchNearbyServices();
          if (mounted) {
            await _cameraController?.pausePreview();
            setState(() {
              _nearbyServices = services;
              _servicePage = 0;
              _showDetectedCard = true;
            });
          }
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
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);
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
  // Silent GPS fetch (mirrors HomeTab's _buildGpsLocationQuery) — no fresh
  // permission prompt in most cases since location is expected to already
  // be tracked/permitted elsewhere in the app. Returns null if location
  // can't be resolved, so the caller can just fall back to pincode-only.
  Future<String?> _buildGpsLocationQuery() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      return '&latitude=${position.latitude}&longitude=${position.longitude}';
    } catch (e) {
      debugPrint('❌ Location fetch error (scan services): $e');
      return null;
    }
  }

Future<List<Map<String, dynamic>>> _fetchNearbyServices() async {
    if ((_effectiveBrand == null && _resultLabel == null) || !_isValidDetection) return [];
    debugPrint('📍 widget.pincode = "${widget.pincode}"');
    debugPrint('🛡️ isUnderWarranty = $_isUnderWarrantyNow');

    // Best-effort GPS lat/long alongside the pincode — backend can use
    // whichever it prefers, or fall back if one is missing.
    final locationQuery = await _buildGpsLocationQuery() ?? '';

    try {
      final response = await http.post(
        Uri.parse(
          '${ApiConfig.serviceLocatorUrl}'
          '?brand=${Uri.encodeQueryComponent(_effectiveBrand ?? "")}'
          '&product=${Uri.encodeQueryComponent(_resultLabel ?? "")}'
          '&pincode=${widget.pincode}'
          '&isUnderWarranty=$_isUnderWarrantyNow'
          '$locationQuery',
        ),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      debugPrint('🔍 Service locator status: ${response.statusCode}');
      debugPrint('🔍 Service locator body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          final services = rawList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          services.sort((a, b) {
            final ratingA = double.tryParse(a['rating']?.toString() ?? '') ?? -1;
            final ratingB = double.tryParse(b['rating']?.toString() ?? '') ?? -1;
            return ratingB.compareTo(ratingA);
          });

          return services;
        }
      }
    } catch (e) {
      debugPrint('❌ Service fetch error: $e');
    }
    return [];
  }

  Future<void> _runAiAssist({bool showCardAfter = false}) async {
    if (_lastCapturedImage == null) {
      if (!showCardAfter) {
        _showSnack('No recent photo to analyze. Point the camera and wait a moment.');
      }
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
        body: jsonEncode({
          'imageBase64': base64Image,
          'mimeType': 'image/jpeg',
        }),
      );

      debugPrint('🤖 AI assist status: ${response.statusCode}');
      debugPrint('🤖 AI assist body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          var aiBrand = data['data']['brand']?.toString().trim();
          var aiProduct = data['data']['product']?.toString().trim();

          // Gemini sometimes returns literal placeholder strings instead of
          // an actual brand/product when it can't identify something.
          // Treat those as "not found" so the UI falls back to
          // "Unbranded" / "—" consistently instead of showing the raw
          // placeholder text to the user.
          const unknownValues = {
            'unidentifiable',
            'unknown',
            'n/a',
            'not identifiable',
            'not found',
            'unable to identify',
          };
          if (aiBrand != null && unknownValues.contains(aiBrand.toLowerCase())) {
            aiBrand = null;
          }
          if (aiProduct != null && unknownValues.contains(aiProduct.toLowerCase())) {
            aiProduct = null;
          }

          if (aiBrand == null && aiProduct == null) {
            if (!showCardAfter) {
              _showSnack('Zhini could not identify this clearly. Try a closer photo.');
            }
            if (showCardAfter && mounted) {
              // Still show the card as "Unbranded" using whatever the local
              // model already had, instead of leaving the user stuck.
              final services = await _fetchNearbyServices();
              if (mounted) {
                await _cameraController?.pausePreview();
                setState(() {
                  _nearbyServices = services;
                  _servicePage = 0;
                  _showDetectedCard = true;
                });
              }
            }
            return;
          }

          if (mounted) {
            setState(() {
              if (aiBrand != null && aiBrand.isNotEmpty) _matchedCompany = aiBrand;
              if (aiProduct != null && aiProduct.isNotEmpty) _resultLabel = aiProduct;
            });
          }

          // Re-fetch service centers now that we have a corrected brand/product
          final services = await _fetchNearbyServices();
          if (mounted) {
            await _cameraController?.pausePreview();
            setState(() {
              _nearbyServices = services;
              _servicePage = 0;
              if (showCardAfter) _showDetectedCard = true;
            });
          }
          if (!showCardAfter) {
            _showSnack('Updated: ${_matchedCompany ?? "Unbranded"} • ${_resultLabel ?? "—"}');
          }
        } else {
          if (!showCardAfter) {
            _showSnack('Zhini could not identify this. Try again with better lighting.');
          } else if (mounted) {
            final services = await _fetchNearbyServices();
            if (mounted) {
              await _cameraController?.pausePreview();
              setState(() {
                _nearbyServices = services;
                _servicePage = 0;
                _showDetectedCard = true;
              });
            }
          }
        }
      } else {
        if (!showCardAfter) {
          _showSnack('AI check failed (${response.statusCode}). Try again.');
        } else if (mounted) {
          final services = await _fetchNearbyServices();
          if (mounted) {
            await _cameraController?.pausePreview();
            setState(() {
              _nearbyServices = services;
              _servicePage = 0;
              _showDetectedCard = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ AI assist error: $e');
      if (!showCardAfter) {
        _showSnack('Network error while checking with Zhini AI. Try again.');
      } else if (mounted) {
        final services = await _fetchNearbyServices();
        if (mounted) {
          await _cameraController?.pausePreview();
          setState(() {
            _nearbyServices = services;
            _servicePage = 0;
            _showDetectedCard = true;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _aiThinking = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // WARRANTY CARD UPLOAD (photo of the warranty card / bill)
  // ---------------------------------------------------------------------
  Future<void> _pickAndUploadWarrantyCard() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploadingWarrantyCard = true);
    try {
      final uri = Uri.parse(ApiConfig.mediaUploadUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(await http.MultipartFile.fromPath('file', picked.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('🧾 Warranty card upload status: ${response.statusCode}');
      debugPrint('🧾 Warranty card upload body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          setState(() => _warrantyCardUrl = data['url'].toString());
          _showSnack('Warranty card uploaded ✅');
        } else {
          _showSnack('Could not upload warranty card.');
        }
      } else {
        _showSnack('Upload failed. Try again.');
      }
    } catch (e) {
      debugPrint('❌ Warranty card upload error: $e');
      _showSnack('Network error while uploading.');
    } finally {
      if (mounted) setState(() => _uploadingWarrantyCard = false);
    }
  }

  // ---------------------------------------------------------------------
  // APPLIANCE PHOTO UPLOAD (the photo captured by the scanner camera)
  // ---------------------------------------------------------------------
  // Uploads the last captured camera frame as the appliance's own photo.
  // Called automatically right before submit, so the user doesn't have to
  // do anything extra — the photo the camera already took is reused.
  Future<String?> _uploadApplianceImage() async {
    if (_lastCapturedImage == null) return null;
    try {
      final uri = Uri.parse(ApiConfig.mediaUploadUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = 'true';
      request.files.add(await http.MultipartFile.fromPath('file', _lastCapturedImage!.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('📷 Appliance photo upload status: ${response.statusCode}');
      debugPrint('📷 Appliance photo upload body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          return data['url'].toString();
        }
      }
    } catch (e) {
      debugPrint('❌ Appliance photo upload error: $e');
    }
    return null;
  }

  // Opens a small dialog letting the user type in a warranty value manually
  // (used both for "Add" when nothing was detected, and "Edit" to override
  // an auto-detected value).
  void _openWarrantyDialog() {
    final controller = TextEditingController(
      text: _detectedWarranty ?? _manualWarranty ?? '',
    );

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
            onPressed: () async {
              final value = controller.text.trim();
              setState(() {
                _manualWarranty = value.isNotEmpty ? value : null;
                _detectedWarranty = null; // manual entry overrides auto value
              });
              Navigator.pop(dialogContext);

              // Warranty status may have just flipped (in ↔ out of
              // warranty), which changes which backend tier applies
              // (Authorized vs Neighbor vs General). Re-fetch so the
              // service list on an already-open card stays correct.
              if (_showDetectedCard) {
                final services = await _fetchNearbyServices();
                if (mounted) {
                  setState(() {
                    _nearbyServices = services;
                    _servicePage = 0;
                  });
                }
              }
            },
            child: const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  // Opens a small dialog letting the user manually type the brand when
  // detection missed it (mirrors _openWarrantyDialog).
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
            onPressed: () async {
              final value = controller.text.trim();
              setState(() => _manualBrand = value.isNotEmpty ? value : null);
              Navigator.pop(dialogContext);

              // Brand affects the service-locator query, so re-fetch.
              if (_showDetectedCard) {
                final services = await _fetchNearbyServices();
                if (mounted) {
                  setState(() {
                    _nearbyServices = services;
                    _servicePage = 0;
                  });
                }
              }
            },
            child: const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

Future<void> _confirmAndSubmit() async {
    if (_resultLabel == null || !_isValidDetection || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      // Backend now REQUIRES a valid homeId for every product submission —
      // it no longer auto-creates a home. If we don't have one yet (e.g.
      // this is the very first appliance for a brand-new home), create it
      // first via /createHome, then use the real homeId it returns.
      if (_currentHomeId == null) {
        final createdHomeId = await _ensureHomeExists();
        if (createdHomeId == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not set up your home. Try again.')),
            );
          }
          return;
        }
        _currentHomeId = createdHomeId;
        widget.onHomeCreated?.call(createdHomeId);
        await SessionManager.updateHomeId(createdHomeId);
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.productSubmitUrl),
      );
      request.headers['ngrok-skip-browser-warning'] = 'true';

      request.fields['homeId'] = _currentHomeId!;
      request.fields['address'] = widget.address;
      request.fields['product'] = _resultLabel!;
      request.fields['brand'] = _effectiveBrand ?? 'Unknown';
      request.fields['mobile'] = ApiConfig.stripCountryCode(widget.mobileNumber);
      request.fields['pincode'] = widget.pincode;
      request.fields['warranty'] = _detectedWarranty ?? _manualWarranty ?? 'N/A';
      request.fields['roomName'] = _selectedRoom;
      request.fields['name'] = widget.name;

      // Backend expects the field name "file" — appliance photo captured
      // by the camera goes straight in, no separate upload step needed.
      if (_lastCapturedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('file', _lastCapturedImage!.path),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('📦 Submit status: ${response.statusCode}');
      debugPrint('📦 Submit body: ${response.body}');

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_resultLabel (${_matchedCompany ?? "Unbranded"}) saved ✅')),
        );
        _resetForNextScan();
      } else {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Submit failed. Try again.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Calls /createHome to get a real homeId when this ScanTab was opened
  // without one (e.g. "Add Home" flow's first scan). Mirrors the same
  // call AddressScreen makes.
  Future<String?> _ensureHomeExists() async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.createHomeUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'name': widget.name,
          'mobile': ApiConfig.stripCountryCode(widget.mobileNumber),
          'address': widget.address,
        }),
      );
      debugPrint('🏠 Ensure-home status: ${response.statusCode}');
      debugPrint('🏠 Ensure-home body: ${response.body}');
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return data['data']['homeId']?.toString();
        }
      }
    } catch (e) {
      debugPrint('❌ Ensure-home error: $e');
    }
    return null;
  }

  Future<void> _openDirections(String? address) async {
    if (address == null || address.isEmpty) return;

    final query = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Directions launch error: $e');
      _showSnack('Could not open maps.');
    }
  }
  Future<void> _callService(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showSnack('No phone number available.');
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Call launch error: $e');
      _showSnack('Could not start call.');
    }
  }

void _resetForNextScan() {
  setState(() {
    _showDetectedCard = false;
    _resultLabel = null;
    _resultConfidence = null;
    _matchedCompany = null;
    _manualBrand = null;
    _brandText = null;
    _nearbyServices = [];
    _servicePage = 0;
    _aiThinking = false;
    _brandMissCount = 0;
    _aiAssistTriedForThisDetection = false;
    _detectedWarranty = null;
    _manualWarranty = null;
    _warrantyCardUrl = null;
    _uploadingWarrantyCard = false;
    _selectedRoom = (widget.initialRoom != null && widget.initialRoom!.trim().isNotEmpty)
        ? widget.initialRoom!.trim()
        : (_isSkipFlow ? 'Default' : 'hall');
  });

  // Camera-a resume pannunga (paused-ah irundha)
  _cameraController?.resumePreview();

  // Next timer tick-ku (1.5 sec) wait pannama, udane oru detection cycle
  // kick off pannunga — so user "Scan Another" press panna udane response varum
  _captureAndDetect();
}

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _cameraController?.dispose();
    _interpreter?.close();
    _textRecognizer.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // SERVICE LIST PAGINATION HELPERS (5 per page, Next / Previous)
  // ---------------------------------------------------------------------
  int get _serviceTotalPages => _nearbyServices.isEmpty
      ? 1
      : (_nearbyServices.length / _servicePageSize).ceil();

  List<Map<String, dynamic>> get _servicePageItems {
    final start = _servicePage * _servicePageSize;
    final end = (start + _servicePageSize).clamp(0, _nearbyServices.length);
    return start < end ? _nearbyServices.sublist(start, end) : [];
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: AppColors.scaffoldBg,
    body: !_isCameraReady || _cameraController == null
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _showDetectedCard
            ? _buildDetectedCard()   // full screen card mattum, camera illa
            : Stack(
                children: [
                  Positioned.fill(child: CameraPreview(_cameraController!)),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 44, 16, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () => widget.onBack?.call(),
                            child: const Icon(Icons.arrow_back, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Scan Appliance',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(height: 2),
                                Text('Point your camera at any appliance to identify it.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
    Row(
      children: [
        GestureDetector(
          onTap: () => widget.onBack?.call(),
          child: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 22),
        ),
        const SizedBox(width: 12),
        const Text('Product Detected',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    ),
    OutlinedButton.icon(
      onPressed: _aiThinking ? null : () => _runAiAssist(),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppColors.primaryBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      icon: _aiThinking
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
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
                                  color: _effectiveBrand != null ? AppColors.textPrimary : AppColors.textFaint,
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                        // OCR-la warranty extract aagalanaa clear error
                        // message + manual entry options kaatum.
                        : const Text(
                            'Unable to detect warranty automatically',
                            style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 24), // aligns under the warranty icon
                  if ((_detectedWarranty ?? _manualWarranty) != null) ...[
                    // Warranty already set — single "Edit" action.
                    TextButton(
                      onPressed: _openWarrantyDialog,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Edit', style: AppText.linkAction),
                    ),
                  ] else ...[
                    // Warranty not detected — offer BOTH ways to fill it in.
                    TextButton.icon(
                      onPressed: _openWarrantyDialog,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
                      label: const Text('Add manual', style: AppText.linkAction),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: _uploadingWarrantyCard ? null : _pickAndUploadWarrantyCard,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: _uploadingWarrantyCard
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            )
                          : const Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.primary),
                      label: const Text('Upload warranty card', style: AppText.linkAction),
                    ),
                  ],
                ],
              ),
              // Warranty card already uploaded confirmation (shown regardless
              // of whether warranty text itself was set).
              if (_warrantyCardUrl != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 24),
                    const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    const Text('Warranty card added',
                        style: TextStyle(color: AppColors.success, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      onPressed: _uploadingWarrantyCard ? null : _pickAndUploadWarrantyCard,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Change', style: AppText.linkAction),
                    ),
                  ],
                ),
              ],

              if (_isSkipFlow) ...[
                // Skip-flow: no home/rooms yet — don't show room picker
                // at all, everything files under 'Default' silently.
              ] else ...[
                const SizedBox(height: 14),
                if (widget.lockRoom) ...[
                  Row(
                    children: [
                      const Icon(Icons.door_front_door_outlined, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Text('Room: $_selectedRoom', style: AppText.body),
                    ],
                  ),
                ] else ...[
                  const Text('Room', style: AppText.faintCaption),
                  const SizedBox(height: 8),
                  RoomSelectorChips(
                    rooms: {..._fixedRooms, ...?widget.knownRooms},
                    selectedRoom: _selectedRoom,
                    isCustomRoom: !{..._fixedRooms, ...?widget.knownRooms}.contains(_selectedRoom),
                    onSelectRoom: (room) => setState(() => _selectedRoom = room),
                    onTapOther: () async {
                      final name = await showCustomRoomNameDialog(context, initial: _selectedRoom);
                      if (name != null) setState(() => _selectedRoom = name);
                    },
                  ),
                ],
              ],


              if (_nearbyServices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _isUnderWarrantyNow
                      ? 'Authorized Service Centers (by rating)'
                      : 'Recommended Service Centers (by rating)',
                  style: AppText.faintCaption,
                ),
                const SizedBox(height: 8),
                // ---- Paginated (5 per page) service list ----
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _servicePageItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = _servicePageItems[index];
                    final ratingRaw = s['rating'];
                    final reviewsRaw = s['reviews_count'] ?? s['reviewsCount'];
                    final neighborProof = s['neighborProof'];
                    return ServiceProviderCard(
                      name: s['name']?.toString() ?? 'Not available',
                      address: s['address']?.toString(),
                      phone: s['phone']?.toString(),
                      rating: ratingRaw != null ? double.tryParse(ratingRaw.toString()) : null,
                      reviewsCount: reviewsRaw != null ? int.tryParse(reviewsRaw.toString()) : null,
                      badge: neighborProof is Map ? neighborProof['badge']?.toString() : null,
                      showStarRow: true,
                      onCall: () => _callService(s['phone']?.toString()),
                      onDirections: () => _openDirections(s['address']?.toString()),
                    );
                  },
                ),
                // ---- Previous / Next controls (only when there's more
                // than one page of results) ----
                if (_nearbyServices.length > _servicePageSize) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _servicePage > 0
                            ? () => setState(() => _servicePage--)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        label: const Text('Previous'),
                      ),
                      Text('Page ${_servicePage + 1} of $_serviceTotalPages', style: AppText.caption),
                      TextButton.icon(
                        onPressed: _servicePage < _serviceTotalPages - 1
                            ? () => setState(() => _servicePage++)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ] else if (!_aiThinking) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFaint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _effectiveBrand == null
                        ? 'Brand not identified — tap "Add" above to enter it, or "Ask ZHINI" for a closer AI check.'
                        : 'No authorized service centers found nearby.',
                    style: AppText.faintCaption,
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _confirmAndSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text('OK', style: AppText.button),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _resetForNextScan,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: AppColors.primaryBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Scan Another Appliance', style: TextStyle(color: AppColors.primary, fontSize: 16)),
                ),
              ),
           ],
          ),
        ),
      ),
    );
  }
}