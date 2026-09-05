import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/repositories/attachment_repository.dart';

/// Full-screen receipt viewer (spec §11.9/§10.1, T-10.4): pinch-zoom via
/// `InteractiveViewer`, a share button, and the local-cache-first
/// resolution order implemented by `AttachmentRepository.resolveLocalFile`.
class ReceiptViewerScreen extends ConsumerStatefulWidget {
  const ReceiptViewerScreen({super.key, required this.attachmentId});

  final String attachmentId;

  @override
  ConsumerState<ReceiptViewerScreen> createState() =>
      _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends ConsumerState<ReceiptViewerScreen> {
  File? _file;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(attachmentRepositoryProvider);
    try {
      final attachment = await repo.findById(widget.attachmentId);
      if (attachment == null) {
        setState(() {
          _loading = false;
          _error = 'This receipt no longer exists.';
        });
        return;
      }
      final file = await repo.resolveLocalFile(attachment);
      if (!mounted) return;
      setState(() {
        _file = file;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the receipt photo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
        actions: [
          if (_file != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(
                ShareParams(files: [XFile(_file!.path)]),
              ),
            ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white))
            : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.file(_file!),
              ),
      ),
    );
  }
}
