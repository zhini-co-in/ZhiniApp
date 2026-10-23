import 'package:flutter/foundation.dart';

/// HomeTab sets this to 'All' | 'Warranty' | 'Attention'.
/// DevicesTab consumes it and resets it to null.
final ValueNotifier<String?> devicesFilterRequest = ValueNotifier<String?>(null);