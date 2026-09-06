import 'package:flutter/material.dart';

import '../constants/category_visuals.dart';

/// A `Wrap` of tappable colour swatches — pulled out of the category editor
/// (spec §11.5) once the profile editor (spec §11.13 T-14.2) needed the
/// same picker over the same palette, so both stay pixel-identical instead
/// of drifting into two near-duplicate implementations.
class ColourSwatchPicker extends StatelessWidget {
  const ColourSwatchPicker({
    super.key,
    this.palette = categoryColourPalette,
    required this.selectedHex,
    required this.onSelected,
  });

  final List<String> palette;
  final String selectedHex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in palette)
          _ColourChoice(
            hex: hex,
            selected: hex == selectedHex,
            onTap: () => onSelected(hex),
          ),
      ],
    );
  }
}

class _ColourChoice extends StatelessWidget {
  const _ColourChoice({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = colourFromHex(hex);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 2,
                )
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}
