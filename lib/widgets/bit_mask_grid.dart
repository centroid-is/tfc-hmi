import 'package:flutter/material.dart';

/// Visual bit grid for configuring bit masks.
///
/// Shows [bitCount] toggle buttons arranged in rows of 8.
/// Selected bits are highlighted. Displays hex mask value and bit range.
class BitMaskGrid extends StatefulWidget {
  /// Number of bits to display (16 or 32).
  final int bitCount;

  /// Current mask value (null = no mask configured).
  final int? currentMask;

  /// Called when the mask changes. Returns null mask/shift when cleared.
  final ValueChanged<({int? mask, int? shift})> onChanged;

  const BitMaskGrid({
    super.key,
    required this.bitCount,
    this.currentMask,
    required this.onChanged,
  }) : assert(bitCount == 16 || bitCount == 32,
            'bitCount must be 16 or 32');

  @override
  State<BitMaskGrid> createState() => _BitMaskGridState();
}

class _BitMaskGridState extends State<BitMaskGrid> {
  late Set<int> _selectedBits;

  @override
  void initState() {
    super.initState();
    _selectedBits = _bitsFromMask(widget.currentMask);
  }

  @override
  void didUpdateWidget(BitMaskGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentMask != widget.currentMask) {
      _selectedBits = _bitsFromMask(widget.currentMask);
    }
  }

  Set<int> _bitsFromMask(int? mask) {
    if (mask == null) return {};
    final bits = <int>{};
    for (var i = 0; i < widget.bitCount; i++) {
      if ((mask >> i) & 1 == 1) bits.add(i);
    }
    return bits;
  }

  int? _maskFromBits() {
    if (_selectedBits.isEmpty) return null;
    var mask = 0;
    for (final bit in _selectedBits) {
      mask |= (1 << bit);
    }
    return mask;
  }

  int? _shiftFromBits() {
    if (_selectedBits.isEmpty) return null;
    // Shift = position of lowest set bit (trailing zeros)
    final sorted = _selectedBits.toList()..sort();
    return sorted.first;
  }

  void _toggleBit(int bit) {
    setState(() {
      if (_selectedBits.contains(bit)) {
        _selectedBits.remove(bit);
      } else {
        _selectedBits.add(bit);
      }
    });
    widget.onChanged((mask: _maskFromBits(), shift: _shiftFromBits()));
  }

  void _clearAll() {
    setState(() {
      _selectedBits.clear();
    });
    widget.onChanged((mask: null, shift: null));
  }

  String _formatBitRange() {
    if (_selectedBits.isEmpty) return 'None';
    final sorted = _selectedBits.toList()..sort();
    if (sorted.length == 1) return 'Bit: ${sorted.first}';

    // Check if contiguous
    bool contiguous = true;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] != sorted[i - 1] + 1) {
        contiguous = false;
        break;
      }
    }

    if (contiguous) {
      return 'Bits: [${sorted.first}:${sorted.last}]';
    }
    return 'Bits: ${sorted.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final rowCount = widget.bitCount ~/ 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bit grid: rows of 8, MSB on left
        for (var row = rowCount - 1; row >= 0; row--)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                // Row label
                SizedBox(
                  width: 28,
                  child: Text(
                    '${row * 8 + 7}',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 4),
                // 8 bit buttons per row, MSB on left
                for (var col = 7; col >= 0; col--)
                  _BitButton(
                    bit: row * 8 + col,
                    selected: _selectedBits.contains(row * 8 + col),
                    primaryColor: primaryColor,
                    onTap: () => _toggleBit(row * 8 + col),
                  ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 16,
                  child: Text(
                    '${row * 8}',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        // Mask summary and clear button
        Row(
          children: [
            if (_selectedBits.isNotEmpty) ...[
              Text(
                'Mask: 0x${_maskFromBits()!.toRadixString(16).toUpperCase().padLeft(widget.bitCount ~/ 4, '0')}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _formatBitRange(),
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
              ),
            ] else
              Text(
                'No bit mask (full value)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BitButton extends StatelessWidget {
  final int bit;
  final bool selected;
  final Color primaryColor;
  final VoidCallback onTap;

  const _BitButton({
    required this.bit,
    required this.selected,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? primaryColor
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? primaryColor
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '$bit',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: selected
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
