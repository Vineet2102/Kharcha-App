import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Full-screen receipt viewer with pinch-zoom (spec §11.9). Built out in
/// Phase 10.
class ReceiptViewerScreen extends StatelessWidget {
  const ReceiptViewerScreen({super.key, required this.attachmentId});

  final String attachmentId;

  @override
  Widget build(BuildContext context) =>
      PlaceholderScreen(title: 'Receipt', subtitle: attachmentId);
}
