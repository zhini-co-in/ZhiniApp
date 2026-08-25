import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable "pick a room" chip row. Styling driven by AppColors/AppText
/// instead of hardcoded values inside the widget.
class RoomSelectorChips extends StatelessWidget {
  final Set<String> rooms;
  final String selectedRoom;
  final bool isCustomRoom;
  final Set<String> disabledRooms;
  final ValueChanged<String> onSelectRoom;
  final VoidCallback onTapOther;

  const RoomSelectorChips({
    super.key,
    required this.rooms,
    required this.selectedRoom,
    required this.onSelectRoom,
    required this.onTapOther,
    this.isCustomRoom = false,
    this.disabledRooms = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...rooms.map((room) {
          final disabled = disabledRooms.contains(room);
          final isSelected = !isCustomRoom && selectedRoom == room;
          return ChoiceChip(
            label: Text(room),
            selected: isSelected,
            onSelected: disabled ? null : (_) => onSelectRoom(room),
            backgroundColor: AppColors.cardBgAlt,
            disabledColor: AppColors.cardBgAlt.withValues(alpha: 0.4),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: disabled
                  ? AppColors.textDisabled
                  : (isSelected ? AppColors.textPrimary : AppColors.textSecondary),
              fontSize: 12,
            ),
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.borderMuted),
          );
        }),
        ChoiceChip(
          label: Text(isCustomRoom ? selectedRoom : 'Other'),
          selected: isCustomRoom,
          onSelected: (_) => onTapOther(),
          backgroundColor: AppColors.cardBgAlt,
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: isCustomRoom ? AppColors.textPrimary : AppColors.textSecondary,
            fontSize: 12,
          ),
          side: BorderSide(color: isCustomRoom ? AppColors.primary : AppColors.borderMuted),
        ),
      ],
    );
  }
}

/// Opens the small "Room name" text-entry dialog behind every "Other" chip.
Future<String?> showCustomRoomNameDialog(BuildContext context, {String initial = ''}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: AppColors.cardBg,
      shape: AppDecor.dialogShape,
      title: Text('Room name', style: AppText.dialogTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: AppDecor.textFieldDecoration('e.g. Balcony, Store Room'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.pop(c, controller.text.trim()),
          child: const Text('Save', style: TextStyle(color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
  return (result != null && result.isNotEmpty) ? result : null;
}