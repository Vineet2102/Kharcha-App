import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/errors/failure.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../widgets/category_editor_sheet.dart';

/// Category management (spec §11.5, T-5.2): drag-to-reorder, archive
/// toggle, edit — admin-only actions, RLS-backed. Members get a read-only
/// list (no add/edit/drag/delete controls).
class CategoryListScreen extends ConsumerWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => showCategoryEditorSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load categories: $error')),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: Text('No categories yet.'));
          }
          final active = categories.where((c) => !c.isArchived).toList();
          final archived = categories.where((c) => c.isArchived).toList();
          return ListView(
            children: [
              if (isAdmin)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: active.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final reordered = List<domain.Category>.from(active);
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    ref.read(categoryRepositoryProvider).reorder(reordered);
                  },
                  itemBuilder: (context, index) => _CategoryTile(
                    key: ValueKey(active[index].id),
                    category: active[index],
                    isAdmin: isAdmin,
                  ),
                )
              else
                for (final category in active)
                  _CategoryTile(
                    key: ValueKey(category.id),
                    category: category,
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
                for (final category in archived)
                  _CategoryTile(
                    key: ValueKey(category.id),
                    category: category,
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

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({
    super.key,
    required this.category,
    required this.isAdmin,
  });

  final domain.Category category;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colour = colourFromHex(category.colourHex);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colour,
        foregroundColor: Colors.white,
        child: Icon(iconForKey(category.iconKey)),
      ),
      title: Text(
        category.name,
        style: category.isArchived
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(category.kind.name),
      trailing: isAdmin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      showCategoryEditorSheet(context, existing: category),
                ),
                IconButton(
                  icon: Icon(
                    category.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  onPressed: () => ref
                      .read(categoryRepositoryProvider)
                      .setArchived(category.id, !category.isArchived),
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
        title: const Text('Delete category?'),
        content: Text('This removes "${category.name}" permanently.'),
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
        .read(categoryRepositoryProvider)
        .delete(category.id);
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
                      .read(categoryRepositoryProvider)
                      .setArchived(category.id, true),
                )
              : null,
        ),
      );
    });
  }
}
