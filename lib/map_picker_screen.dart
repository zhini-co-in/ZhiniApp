// lib/map_picker_screen.dart
// FREE version: OpenStreetMap tiles (no API key, no billing).
// Swiggy / Zomato style: fixed centre pin, move the map, address updates.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';

class PickedLocation {
  final double lat;
  final double lng;
  final String address;
  final String pincode;
  const PickedLocation(this.lat, this.lng, this.address, this.pincode);
}

class MapPickerScreen extends StatefulWidget {
  // If lat/lng are given the map opens there (typed address / current location).
  final double? initialLat;
  final double? initialLng;

  // true  -> no start point given: jump to GPS (the "Pick on map" button).
  // false -> user typed an address: NEVER jump to GPS, even if the address
  //          could not be found (map opens at fallback, user moves the pin).
  final bool useGpsIfNoStart;

  const MapPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.useGpsIfNoStart = true,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  // TODO: put your real Android applicationId / iOS bundle id here.
  // OpenStreetMap asks apps to identify themselves in tile requests.
  static const String _appId = 'com.zhini.mobile';

  final MapController _mapController = MapController();
  final LatLng _fallback = LatLng(11.0168, 76.9558); // used if no start point

  late LatLng _center = (widget.initialLat != null && widget.initialLng != null)
      ? LatLng(widget.initialLat!, widget.initialLng!)
      : _fallback;
  String _address = '';
  String _pincode = '';
  bool _loading = true;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _mapController.move(LatLng(pos.latitude, pos.longitude), 17);
    } catch (e) {
      debugPrint('❌ Map GPS error: $e');
    }
  }

  void _onMapReady() {
    _scheduleGeocode();
    final noStart = widget.initialLat == null || widget.initialLng == null;
    if (noStart && widget.useGpsIfNoStart) _goToMyLocation();
  }

  // Map moved -> wait until it stops, then look up the address.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    // setState can't run while the map is building, so do it after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_loading) setState(() => _loading = true);
    });
    _scheduleGeocode();
  }

  void _scheduleGeocode() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _reverseGeocode);
  }

  Future<void> _reverseGeocode() async {
    final target = _center;
    try {
      final list =
          await placemarkFromCoordinates(target.latitude, target.longitude);
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _address = '';
          _pincode = '';
          _loading = false;
        });
        return;
      }
      final p = list.first;
      final parts = <String>[];
      for (final s in [p.name, p.street, p.subLocality, p.locality, p.administrativeArea]) {
        final v = (s ?? '').trim();
        if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }
      setState(() {
        _address = parts.join(', ');
        _pincode = (p.postalCode ?? '').trim();
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Reverse geocode error: $e');
      if (mounted) {
        setState(() {
          _address = '';
          _pincode = '';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = !_loading && _address.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Column(
        children: [
          // ── Map area (pin is fixed at the centre of this area) ──
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 16,
                    minZoom: 4,
                    maxZoom: 19,
                    onMapReady: _onMapReady,
                    onPositionChanged: _onPositionChanged,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: _appId,
                    ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          onTap: () => launchUrl(
                            Uri.parse('https://openstreetmap.org/copyright'),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Fixed centre pin (tip of the pin sits on the map centre)
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -24),
                      child: Icon(Icons.location_on, size: 48, color: AppColors.danger),
                    ),
                  ),
                ),

                // Back button
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircleAvatar(
                      backgroundColor: AppColors.cardBg,
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),

                // My-location button
                Positioned(
                  right: 16,
                  bottom: 40,
                  child: FloatingActionButton.small(
                    heroTag: 'myLoc',
                    backgroundColor: AppColors.cardBg,
                    onPressed: _goToMyLocation,
                    child: Icon(Icons.my_location, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom card ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: const [
                BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Move the map so the pin is on your exact location', style: AppText.lightCaption),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.location_on, color: AppColors.danger, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loading
                              ? 'Finding address...'
                              : (_address.isEmpty
                                  ? 'Address not found here. Move the pin a little.'
                                  : _address),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.lightCardTitle,
                        ),
                      ),
                    ],
                  ),
                  if (_pincode.isNotEmpty && !_loading) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text('Pincode: $_pincode', style: AppText.lightCaption),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: canConfirm
                          ? () => Navigator.pop(
                                context,
                                PickedLocation(_center.latitude, _center.longitude,
                                    _address, _pincode),
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Confirm location',
                          style: TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
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
}