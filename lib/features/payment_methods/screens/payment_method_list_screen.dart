import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/errors/failure.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/payment_method.dart' as domain;
import '../widgets/payment_method_editor_sheet.dart';

/// Payment method management (spec §11.5, T-5.3) — same shape as
/// [CategoryListScreen]: drag-to-reorder, archive toggle, edit, admin-only.
class PaymentMethodListScreen extends ConsumerWidget {
  const PaymentMethodListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final methodsAsync = ref.watch(paymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment methods')),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => showPaymentMethodEditorSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: methodsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load payment methods: $error')),
        data: (methods) {
          if (methods.isEmpty) {
            return const Center(child: Text('No payment methods yet.'));
          }
          final active = methods.where((m) => !m.isArchived).toList();
          final archived = methods.where((m) => m.isArchived).toList();
          return ListView(
            children: [
              if (isAdmin)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: active.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = List<domain.PaymentMethod>.from(active);
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    ref
                        .read(paymentMethodRepositoryProvider)
                        .reorder(reordered);
                  },
                  itemBuilder: (context, index) => _MethodTile(
                    key: ValueKey(active[index].id),
                    method: active[index],
                    isAdmin: isAdmin,
                  ),
                )
              else
                for (final method in active)
                  _MethodTile(
                    key: ValueKey(method.id),
                    method: method,
                    isAdmin: false,
                  ),
              if (archived.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'ARCHIVED',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                for (final method in archived)
                  _MethodTile(
                    key: ValueKey(method.id),
                    method: method,
                    isAdmin: isAdmin,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MethodTile extends ConsumerWidget {
  const _MethodTile({super.key, required this.method, required this.isAdmin});

  final domain.PaymentMethod method;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(child: Icon(iconForPaymentMethodType(method.type))),
      title: Text(
        method.name,
        style: method.isArchived
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(method.type.name),
      trailing: isAdmin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      showPaymentMethodEditorSheet(context, existing: method),
                ),
                IconButton(
                  icon: Icon(
                    method.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  onPressed: () => ref
                      .read(paymentMethodRepositoryProvider)
                      .setArchived(method.id, !method.isArchived),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete payment method?'),
        content: Text('This removes "${method.name}" permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(paymentMethodRepositoryProvider)
        .delete(method.id);
    if (!context.mounted) return;
    result.fold((_) {}, (failure) {
      final isValidation = failure is ValidationFailure;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: isValidation
              ? SnackBarAction(
                  label: 'Archive',
                  onPressed: () => ref
                      .read(paymentMethodRepositoryProvider)
                      .setArchived(method.id, true),
                )
              : null,
        ),
      );
    });
  }
}
