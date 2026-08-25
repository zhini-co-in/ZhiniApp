import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Unified "service provider" card. Styling driven by AppColors/AppDecor/
/// AppText instead of hardcoded values.
class ServiceProviderCard extends StatelessWidget {
  final String name;
  final String? address;
  final String? phone;
  final double? rating;
  final int? reviewsCount;
  final String? badge;
  final VoidCallback? onCall;
  final VoidCallback? onDirections;
  final bool showStarRow;

  const ServiceProviderCard({
    super.key,
    required this.name,
    this.address,
    this.phone,
    this.rating,
    this.reviewsCount,
    this.badge,
    this.onCall,
    this.onDirections,
    this.showStarRow = false,
  });

  bool get _hasAddress =>
      address != null && address!.isNotEmpty && address != 'Address not available';
  bool get _hasPhone => phone != null && phone!.isNotEmpty && phone != 'N/A';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppDecor.outlinedCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.cardTitle),
                if (badge != null) ...[
                  const SizedBox(height: 3),
                  Text(badge!,
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w500)),
                ],
                if (rating != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (showStarRow)
                        ...List.generate(
                          5,
                          (i) => Icon(
                            i < rating!.round() ? Icons.star : Icons.star_border,
                            size: 14,
                            color: AppColors.star,
                          ),
                        )
                      else
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.star),
                      const SizedBox(width: 6),
                      Text(
                        reviewsCount != null
                            ? '${rating!.toStringAsFixed(1)} ($reviewsCount reviews)'
                            : rating!.toStringAsFixed(1),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ],
                if (_hasAddress) ...[
                  const SizedBox(height: 4),
                  Text(address!, style: AppText.faintCaption),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              if (_hasPhone && onCall != null) _actionButton(icon: Icons.phone, onTap: onCall!),
              if (_hasPhone && onCall != null && _hasAddress && onDirections != null)
                const SizedBox(height: 8),
              if (_hasAddress && onDirections != null)
                _actionButton(icon: Icons.directions, onTap: onDirections!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}