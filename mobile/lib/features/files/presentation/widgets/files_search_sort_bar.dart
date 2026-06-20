import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import 'files_view_models.dart';

class FilesSearchSortBar extends StatelessWidget {
  const FilesSearchSortBar({
    super.key,
    required this.searchController,
    required this.sort,
    required this.onSearchChanged,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final FilesSort sort;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<FilesSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              labelText: 'Search current directory',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<FilesSort>(
            initialValue: sort,
            decoration: const InputDecoration(labelText: 'Sort'),
            items: const [
              DropdownMenuItem(value: FilesSort.name, child: Text('Name')),
              DropdownMenuItem(
                value: FilesSort.modified,
                child: Text('Modified'),
              ),
              DropdownMenuItem(value: FilesSort.size, child: Text('Size')),
            ],
            onChanged: (value) {
              if (value != null) {
                onSortChanged(value);
              }
            },
          ),
        ),
      ],
    );
  }
}
