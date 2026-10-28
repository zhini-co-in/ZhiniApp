import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'constants/app_strings.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'constants/api_config.dart';
import 'services/session_manager.dart';
import 'services/api_client.dart';
import 'package:image_picker/image_picker.dart';
import 'theme/app_theme.dart';
import 'utils/warranty_utils.dart';
import 'widgets/app_dialog_field.dart';
import 'widgets/service_provider_card.dart';
import 'package:geolocator/geolocator.dart';
import 'widgets/scan_shutter_button.dart';
import 'widgets/zhini_thinking_view.dart';
import 'widgets/warranty_badge.dart';

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

  // ---- Result from the backend AI (no local ML anymore) ----
  String? _resultLabel; // product
  String? _aiBrand; // brand returned by AI
  String? _manualBrand; // brand typed by the user (wins over AI brand)

  // Values the AI sometimes returns when it can't identify something.
  static const Set<String> _unknownValues = {
    'unidentifiable',
    'unknown',
    'n/a',
    'not identifiable',
    'not found',
    'unable to identify',
    'no appliance found',
    'no object',
    'no object detected',
    'none',
    'background',
  };

  bool get _isValidDetection =>
      _resultLabel != null &&
      _resultLabel!.trim().isNotEmpty &&
      !_unknownValues.contains(_resultLabel!.trim().toLowerCase());

  // Effective brand: user-entered value wins, else AI brand.
  String? get _effectiveBrand => _manualBrand ?? _aiBrand;

  // Warranty state — from AI (if backend returns it) or manual entry.
  String? _detectedWarranty;
  String? _manualWarranty;
  String? _warrantyCardUrl;

  bool get _isUnderWarrantyNow =>
      WarrantyUtils.isActive(_detectedWarranty ?? _manualWarranty);


  List<Map<String, dynamic>> _nearbyServices = [];
  static const int _servicePageSize = 5;
  int _servicePage = 0;

  bool _uploadingWarrantyCard = false;
  bool _isSubmitting = false;
  bool _showDetectedCard = false;

  // true while a photo is being captured + sent to the backend AI
  bool _aiThinking = false;
  File? _lastCapturedImage;
  String? _currentHomeId;

  // ---- Capture flow: 3s countdown -> photo review (OK / Cancel, 6s) -> AI ----
  static const int _reviewSecs = 6;
  Timer? _liveTimer;
  Timer? _reviewTimer;
  int _reviewCountdown = _reviewSecs;
  bool _capturing = false;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    _currentHomeId = widget.homeId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCameraView());
  }

  Future<void> _openCameraView() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _isCameraReady = true);

      _startLiveCountdown();
    } catch (e) {
      debugPrint('Camera init error: $e');
      _showSnack(AppStrings.couldNotOpenCamera);
    }
  }

  // ---------------------------------------------------------------------
  // SCAN — take a photo and send it straight to the backend AI endpoint.
  // ---------------------------------------------------------------------
  // Live camera: count 3..2..1, then take a photo and show it for review.
void _startLiveCountdown() {
  _liveTimer?.cancel();
  _reviewTimer?.cancel();
  if (!mounted) return;
  setState(() {
    _reviewing = false;
    _capturing = false;
  });
  // No auto-capture. User taps the shutter button when ready.
}

  Future<void> _captureForReview() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) {
      _startLiveCountdown();
      return;
    }
    if (mounted) setState(() => _capturing = true);
    try {
      final XFile file = await c.takePicture();
      final previous = _lastCapturedImage;
      _lastCapturedImage = File(file.path);
      if (previous != null && previous.path != file.path) {
        previous.delete().catchError((_) => previous);
      }
      if (!mounted) return;

      setState(() {
        _capturing = false;
        _reviewing = true;
        _reviewCountdown = _reviewSecs;
      });

      // 6..0 — if the user does nothing, the photo is cancelled and the
      // camera starts again automatically.
      _reviewTimer?.cancel();
      _reviewTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _reviewCountdown--);
        if (_reviewCountdown <= 0) {
          t.cancel();
          _cancelReview();
        }
      });
    } catch (e) {
      debugPrint('❌ Capture error: $e');
      _startLiveCountdown();
    }
  }

  void _cancelReview() {
    _reviewTimer?.cancel();
    final img = _lastCapturedImage;
    _lastCapturedImage = null;
    if (img != null) img.delete().catchError((_) => img);
    _startLiveCountdown();
  }

  // User pressed OK — only now is the photo sent to the backend AI.
 Future<void> _confirmReview() async {
  if (_aiThinking) return;
  _reviewTimer?.cancel();
  setState(() {
    _reviewing = false;
    _aiThinking = true;
  });
  await _cameraController?.pausePreview(); // camera background la run aagaadhu
  try {
    final ok = await _identifyWithAi();
    if (!mounted) return;
    if (!ok) {
      setState(() => _aiThinking = false);
      await _cameraController?.resumePreview(); // illana freeze aagum
      _startLiveCountdown();
      return;
    }
    final services = await _fetchNearbyServices();
    if (!mounted) return;
    setState(() {
      _nearbyServices = services;
      _servicePage = 0;
      _showDetectedCard = true;
    });
  } finally {
    if (mounted) setState(() => _aiThinking = false);
  }
}

  // Sends _lastCapturedImage to the AI endpoint and fills product/brand.
  // Returns true only if a valid product was identified.
  Future<bool> _identifyWithAi({bool silent = false}) async {
    if (_lastCapturedImage == null) return false;
    try {
      final bytes = await _lastCapturedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await ApiClient.post(ApiConfig.aiAssistUrl, body: {
        'imageBase64': base64Image,
        'mimeType': 'image/jpeg',
      });

      debugPrint('🤖 AI status: ${response.statusCode}');
      debugPrint('🤖 AI body: ${response.body}');

      if (response.statusCode == 401) {
        _showSnack(AppStrings.sessionExpired);
        return false;
      }
      if (response.statusCode != 200) {
        if (!silent) _showSnack(AppStrings.scanFailed(response.statusCode));
        return false;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['data'] == null) {
        if (!silent) _showSnack(AppStrings.couldNotIdentify);
        return false;
      }

      String? clean(dynamic v) {
        final s = v?.toString().trim();
        if (s == null || s.isEmpty) return null;
        return _unknownValues.contains(s.toLowerCase()) ? null : s;
      }

      final aiProduct = clean(data['data']['product']);
      final aiBrand = clean(data['data']['brand']);
      final aiWarranty = clean(data['data']['warranty']);

      if (aiProduct == null) {
        if (!silent) _showSnack(AppStrings.noApplianceFoundPointCamera);
        return false;
      }

      if (mounted) {
        setState(() {
          _resultLabel = aiProduct;
          _aiBrand = aiBrand;
          if (aiWarranty != null && aiWarranty.toUpperCase() != 'N/A') {
            _detectedWarranty = aiWarranty;
          }
        });
      }
      return true;
    } catch (e) {
      debugPrint('❌ AI error: $e');
      if (!silent) _showSnack(AppStrings.networkErrorWhileScanning);
      return false;
    }
  }

  // "Ask ZHINI" on the result card — re-checks the same photo with AI.
  Future<void> _recheckWithAi() async {
    if (_aiThinking) return;
    setState(() => _aiThinking = true);
    try {
      final ok = await _identifyWithAi();
      if (ok) {
        final services = await _fetchNearbyServices();
        if (mounted) {
          setState(() {
            _nearbyServices = services;
            _servicePage = 0;
          });
          _showSnack(AppStrings.updatedBrandProduct(_effectiveBrand ?? AppStrings.unbranded, _resultLabel ?? '—'));
        }
      }
    } finally {
      if (mounted) setState(() => _aiThinking = false);
    }
  }

  // Silent GPS fetch.
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
    if (!_isValidDetection) return [];
    debugPrint('📍 widget.pincode = "${widget.pincode}"');
    debugPrint('🛡️ isUnderWarranty = $_isUnderWarrantyNow');

    final locationQuery = await _buildGpsLocationQuery() ?? '';

    try {
      final response = await ApiClient.post(
        '${ApiConfig.serviceLocatorUrl}'
        '?brand=${Uri.encodeQueryComponent(_effectiveBrand ?? "")}'
        '&product=${Uri.encodeQueryComponent(_resultLabel ?? "")}'
        '&pincode=${widget.pincode}'
        '&isUnderWarranty=$_isUnderWarrantyNow'
        '$locationQuery',
      );
      debugPrint('🔍 Service locator status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final rawData = data['data'];
          final List<dynamic> rawList = rawData is List ? rawData : [rawData];
          final services =
              rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

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

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------------
  // WARRANTY CARD UPLOAD
  // ---------------------------------------------------------------------
  Future<void> _pickAndUploadWarrantyCard() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploadingWarrantyCard = true);
    try {
      final uri = Uri.parse(ApiConfig.mediaUploadUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(await ApiClient.authHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', picked.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('🧾 Warranty card upload status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          setState(() => _warrantyCardUrl = data['url'].toString());
          _showSnack(AppStrings.warrantyCardUploaded);
        } else {
          _showSnack(AppStrings.couldNotUploadWarrantyCard);
        }
      } else if (response.statusCode == 401) {
        _showSnack(AppStrings.sessionExpired);
      } else {
        _showSnack(AppStrings.uploadFailed);
      }
    } catch (e) {
      debugPrint('❌ Warranty card upload error: $e');
      _showSnack(AppStrings.networkErrorWhileUploading);
    } finally {
      if (mounted) setState(() => _uploadingWarrantyCard = false);
    }
  }

  void _openWarrantyDialog() {
    final controller = TextEditingController(
      text: _detectedWarranty ?? _manualWarranty ?? '',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text(AppStrings.warranty, style: AppText.dialogTitle),
        content: AppDialogField(controller: controller, hint: AppStrings.warrantyDialogHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
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
            child: Text(AppStrings.save, style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _openBrandDialog() {
    final controller = TextEditingController(text: _effectiveBrand ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        shape: AppDecor.dialogShape,
        title: const Text(AppStrings.brandHint, style: AppText.dialogTitle),
        content: AppDialogField(controller: controller, hint: AppStrings.brandDialogHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.cancel, style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final value = controller.text.trim();
              setState(() => _manualBrand = value.isNotEmpty ? value : null);
              Navigator.pop(dialogContext);

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
            child: Text(AppStrings.save, style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SUBMIT
  // ---------------------------------------------------------------------
  Future<void> _confirmAndSubmit() async {
    if (_resultLabel == null || !_isValidDetection || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      if (_currentHomeId == null) {
        final createdHomeId = await _ensureHomeExists();
        if (createdHomeId == null) {
          _showSnack(AppStrings.couldNotSetupHome);
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
      request.headers.addAll(await ApiClient.authHeaders());

      request.fields['homeId'] = _currentHomeId!;
      request.fields['address'] = widget.address;
      request.fields['product'] = _resultLabel!;
      request.fields['brand'] = _effectiveBrand ?? 'Unknown';
      request.fields['mobile'] = ApiConfig.stripCountryCode(widget.mobileNumber);
      request.fields['pincode'] = widget.pincode;
      request.fields['warranty'] = _detectedWarranty ?? _manualWarranty ?? 'N/A';
      request.fields['roomName'] = 'Default';
      request.fields['name'] = widget.name;

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
        _showSnack(AppStrings.applianceSaved(_resultLabel ?? '', _effectiveBrand ?? AppStrings.unbranded));
        _resetForNextScan();
      } else if (response.statusCode == 401) {
        _showSnack(AppStrings.sessionExpired);
      } else {
        String msg = AppStrings.submitFailed;
        try {
          final data = jsonDecode(response.body);
          msg = data['message']?.toString() ?? msg;
        } catch (_) {}
        _showSnack(msg);
      }
    } catch (e) {
      debugPrint('❌ Submit error: $e');
      _showSnack(AppStrings.networkError);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<String?> _ensureHomeExists() async {
    try {
      final response = await ApiClient.post(ApiConfig.createHomeUrl, body: {
        'name': widget.name,
        'mobile': ApiConfig.stripCountryCode(widget.mobileNumber),
        'address': widget.address,
        'pincode': widget.pincode,
        'homeName': widget.address.split(',').first.trim(),
      });
      debugPrint('🏠 Ensure-home status: ${response.statusCode}');
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
      _showSnack(AppStrings.couldNotOpenMaps);
    }
  }

  Future<void> _callService(String? phone) async {
    if (phone == null || phone.isEmpty) {
      _showSnack(AppStrings.noPhoneAvailable);
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Call launch error: $e');
      _showSnack(AppStrings.couldNotStartCall);
    }
  }

  void _resetForNextScan() {
    setState(() {
      _showDetectedCard = false;
      _resultLabel = null;
      _aiBrand = null;
      _manualBrand = null;
      _nearbyServices = [];
      _servicePage = 0;
      _aiThinking = false;
      _reviewing = false;
      _capturing = false;
      _detectedWarranty = null;
      _manualWarranty = null;
      _warrantyCardUrl = null;
      _uploadingWarrantyCard = false;
    });

    // Back to the live camera — the 3s countdown starts again.
    _cameraController?.resumePreview();
    _startLiveCountdown();
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _reviewTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // SERVICE LIST PAGINATION HELPERS
  // ---------------------------------------------------------------------
  int get _serviceTotalPages => _nearbyServices.isEmpty
      ? 1
      : (_nearbyServices.length / _servicePageSize).ceil();

  List<Map<String, dynamic>> get _servicePageItems {
    final start = _servicePage * _servicePageSize;
    final end = (start + _servicePageSize).clamp(0, _nearbyServices.length);
    return start < end ? _nearbyServices.sublist(start, end) : [];
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: !_isCameraReady || _cameraController == null
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _showDetectedCard
              ? _buildDetectedCard()
              : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_cameraController!)),

        // Top bar
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
                  child: Icon(Icons.arrow_back, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(AppStrings.scanAppliance,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600)),
      SizedBox(height: 2),
      Text(AppStrings.scanHint,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
    ],
  ),
),
              ],
            ),
          ),
        ),

        // Live countdown chip
        // Shutter button
if (!_reviewing && !_aiThinking)
  Positioned(
    left: 0,
    right: 0,
    bottom: 36,
    child: Center(
      child: ScanShutterButton(
        busy: _capturing,
        onTap: _capturing ? null : _captureForReview,
      ),
    ),
  ),

        // Photo review: OK / Cancel with 6..0 countdown
        if (_reviewing && _lastCapturedImage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(_lastCapturedImage!, fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 56,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(AppStrings.capturedProduct,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 36,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelReview,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              side: BorderSide(color: AppColors.textSecondary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(AppStrings.cancelWithCount(_reviewCountdown),
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _confirmReview,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(AppStrings.proceed,
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Identifying overlay
                // ZHINI thinking screen
        if (_aiThinking) const Positioned.fill(child: ZhiniThinkingView()),
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
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => widget.onBack?.call(),
                        child: Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(AppStrings.productDetected,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: _aiThinking ? null : _recheckWithAi,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.primaryBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: _aiThinking
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, size: 14, color: AppColors.primary),
                    label: Text(
                      _aiThinking ? AppStrings.checking : AppStrings.askZhini,
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
                        : Icon(Icons.ac_unit, color: AppColors.textFaint),
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
                                _effectiveBrand ?? AppStrings.unbranded,
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
                                _effectiveBrand != null ? AppStrings.edit : AppStrings.add,
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
              Align(
  alignment: Alignment.centerLeft,
  child: WarrantyBadge(
    expiry: WarrantyUtils.parseExpiry(
      _detectedWarranty ?? _manualWarranty,
      referenceDate: DateTime.now(),
    ),
  ),
),
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 24),
                  if ((_detectedWarranty ?? _manualWarranty) != null) ...[
                    TextButton(
                      onPressed: _openWarrantyDialog,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text(AppStrings.edit, style: AppText.linkAction),
                    ),
                  ] else ...[
                    TextButton.icon(
                      onPressed: _openWarrantyDialog,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Icons.edit_outlined, size: 14, color: AppColors.primary),
                      label: const Text(AppStrings.addManual, style: AppText.linkAction),
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
                          ? SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            )
                          : Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.primary),
                      label: const Text(AppStrings.uploadWarrantyCard, style: AppText.linkAction),
                    ),
                  ],
                ],
              ),
              if (_warrantyCardUrl != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 24),
                    Icon(Icons.check_circle, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(AppStrings.warrantyCardAdded,
                        style: TextStyle(color: AppColors.success, fontSize: 12)),
                    const Spacer(),
                    TextButton(
                      onPressed: _uploadingWarrantyCard ? null : _pickAndUploadWarrantyCard,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text(AppStrings.change, style: AppText.linkAction),
                    ),
                  ],
                ),
              ],

              if (_nearbyServices.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _isUnderWarrantyNow
                      ? AppStrings.authorizedCentersByRating
                      : AppStrings.recommendedCentersByRating,
                  style: AppText.faintCaption,
                ),
                const SizedBox(height: 8),
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
                      name: s['name']?.toString() ?? AppStrings.notAvailable,
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
                if (_nearbyServices.length > _servicePageSize) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _servicePage > 0 ? () => setState(() => _servicePage--) : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        label: const Text(AppStrings.previous),
                      ),
                      Text(AppStrings.pageOf(_servicePage + 1, _serviceTotalPages), style: AppText.caption),
                      TextButton.icon(
                        onPressed: _servicePage < _serviceTotalPages - 1
                            ? () => setState(() => _servicePage++)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        label: const Text(AppStrings.next),
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
                        ? AppStrings.brandNotIdentified
                        : AppStrings.noAuthorizedCentersFound,
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
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                        )
                      : const Text(AppStrings.ok, style: AppText.button),
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
                  child: Text(AppStrings.scanAnotherAppliance,
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