// lib/presentation/widgets/smart_amount_input.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class SmartAmountInput extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final String? prefixText;
  final String? suffixText;
  final Function(double?)? onChanged;
  final Function(double?)? onSubmitted;
  final String? Function(String?)? validator;
  final bool enabled;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final bool showSuggestions;
  final bool showQuickButtons;
  final List<double>? customSuggestions;
  final String? categoryType;
  final Widget? prefixIcon;

  const SmartAmountInput({
    super.key,
    required this.controller,
    this.labelText = 'Số tiền',
    this.hintText = '0',
    this.prefixText,
    this.suffixText = '₫',
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.enabled = true,
    this.focusNode,
    this.decoration,
    this.showSuggestions = true,
    this.showQuickButtons = true,
    this.customSuggestions,
    this.categoryType,
    this.prefixIcon,
  });

  @override
  State<SmartAmountInput> createState() => _SmartAmountInputState();
}

class _SmartAmountInputState extends State<SmartAmountInput> {
  late FocusNode _focusNode;
  final NumberFormat _currencyFormat = NumberFormat('#,###', 'vi_VN');

  bool _showSuggestions = false;
  List<double> _currentSuggestions = [];

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);

    // Initialize suggestions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSuggestions();
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _showSuggestions = _focusNode.hasFocus && widget.showSuggestions;
    });

    if (_focusNode.hasFocus) {
      _updateSuggestions();
    }
  }

  double _parseAmount(String text) {
    String cleaned = text.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  String _formatAmount(double amount) {
    if (amount == 0) return '';
    return _currencyFormat.format(amount);
  }

  void _updateSuggestions() {
    if (!widget.showSuggestions) return;

    final currentAmount = _parseAmount(widget.controller.text);

    if (widget.customSuggestions != null) {
      _currentSuggestions = widget.customSuggestions!;
    } else if (widget.categoryType != null) {
      _currentSuggestions = _getPresetAmounts(widget.categoryType!);
    } else {
      _currentSuggestions = _generateSmartSuggestions(currentAmount);
    }

    setState(() {});
  }

  List<double> _getPresetAmounts(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'ăn uống':
      case 'ăn trưa':
        return [15000, 25000, 35000, 50000, 80000, 150000];
      case 'transport':
      case 'di chuyển':
      case 'xe':
        return [8000, 15000, 25000, 50000, 100000, 200000];
      case 'shopping':
      case 'mua sắm':
        return [50000, 100000, 200000, 500000, 1000000, 2000000];
      case 'entertainment':
      case 'giải trí':
        return [30000, 50000, 100000, 200000, 300000, 500000];
      case 'bills':
      case 'hóa đơn':
        return [50000, 100000, 200000, 300000, 500000, 1000000];
      case 'income':
      case 'thu nhập':
        return [1000000, 2000000, 5000000, 10000000, 15000000, 20000000];
      case 'transfer':
      case 'chuyển tiền':
        return [100000, 500000, 1000000, 2000000, 5000000, 10000000];
      default:
        return [10000, 50000, 100000, 500000, 1000000, 5000000];
    }
  }

  List<double> _generateSmartSuggestions(double currentAmount) {
    List<double> suggestions = [];

    if (currentAmount == 0) {
      return [10000, 20000, 50000, 100000, 200000, 500000];
    }

    String amountStr = currentAmount.toInt().toString();

    if (amountStr.length <= 2) {
      int base = currentAmount.toInt();
      suggestions = [
        base * 1000,
        base * 5000,
        base * 10000,
        (base + 1) * 1000,
        (base + 5) * 1000,
      ];
    } else if (amountStr.length <= 3) {
      int base = currentAmount.toInt();
      suggestions = [
        base * 10,
        base * 100,
        ((base ~/ 100) + 1) * 100000,
        base + 1000,
        base + 5000,
      ];
    } else {
      int base = currentAmount.toInt();
      int magnitude = _getMagnitude(base);

      suggestions = [
        _roundToNearestMagnitude(base, magnitude),
        _roundToNearestMagnitude(base, magnitude * 10),
        (magnitude + base).toDouble(),
        base + magnitude * 5,
        base * 2,
      ];
    }

    suggestions = suggestions
        .where((s) => s > 0 && s != currentAmount)
        .toSet()
        .toList();

    suggestions.sort();
    return suggestions.take(6).toList();
  }

  int _getMagnitude(int number) {
    if (number < 1000) return 100;
    if (number < 10000) return 1000;
    if (number < 100000) return 10000;
    if (number < 1000000) return 100000;
    return 1000000;
  }

  double _roundToNearestMagnitude(int number, int magnitude) {
    return ((number / magnitude).round() * magnitude).toDouble();
  }

  void _selectSuggestion(double amount) {
    widget.controller.text = _formatAmount(amount);
    widget.onChanged?.call(amount);

    setState(() {
      _showSuggestions = false;
    });

    FocusScope.of(context).unfocus();
  }

  void _addQuickAmount(double amount) {
    final currentAmount = _parseAmount(widget.controller.text);
    final newAmount = currentAmount + amount;

    widget.controller.text = _formatAmount(newAmount);
    widget.onChanged?.call(newAmount);
    _updateSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main input field
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
            _CurrencyInputFormatter(),
          ],
          decoration:
              widget.decoration ??
              InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                prefixText: widget.prefixText,
                suffixText: widget.suffixText,
                prefixIcon: widget.prefixIcon ?? const Icon(Icons.attach_money),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surface.withOpacity(0.5),
              ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          validator: widget.validator,
          onChanged: (value) {
            _updateSuggestions();
            widget.onChanged?.call(_parseAmount(value));
          },
          onFieldSubmitted: (value) {
            widget.onSubmitted?.call(_parseAmount(value));
          },
        ),

        // Quick amount buttons
        if (widget.showQuickButtons && _focusNode.hasFocus) ...[
          const SizedBox(height: 12),
          _buildQuickButtons(),
        ],

        // Smart suggestions
        if (_showSuggestions && _currentSuggestions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSuggestions(),
        ],
      ],
    );
  }

  Widget _buildQuickButtons() {
    List<double> quickAmounts;

    if (widget.categoryType == 'income') {
      quickAmounts = [100000, 500000, 1000000, 5000000, 10000000];
    } else if (widget.categoryType == 'transfer') {
      quickAmounts = [50000, 100000, 500000, 1000000, 5000000];
    } else {
      quickAmounts = [1000, 5000, 10000, 50000, 100000];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flash_on, size: 16, color: Colors.amber.shade600),
            const SizedBox(width: 6),
            Text(
              'Thêm nhanh:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: quickAmounts.map((amount) {
            return ActionChip(
              label: Text(
                '+${_formatAmount(amount)}',
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => _addQuickAmount(amount),
              backgroundColor: Colors.amber.shade50,
              labelStyle: TextStyle(
                color: Colors.amber.shade700,
                fontWeight: FontWeight.w500,
              ),
              side: BorderSide(color: Colors.amber.shade200, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade600),
            const SizedBox(width: 6),
            Text(
              'Gợi ý thông minh:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _currentSuggestions.map((amount) {
            return ActionChip(
              label: Text(
                _formatAmount(amount),
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => _selectSuggestion(amount),
              backgroundColor: Colors.blue.shade50,
              labelStyle: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
              side: BorderSide(color: Colors.blue.shade200, width: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
      ],
    );
  }
}

// Custom formatter for currency input
class _CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,###', 'vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanText.isEmpty) {
      return const TextEditingValue(text: '');
    }

    int? number = int.tryParse(cleanText);
    if (number == null) return oldValue;

    String formattedText = _formatter.format(number);
    int cursorPosition = formattedText.length;

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: cursorPosition),
    );
  }
}

// Helper function to parse amount
double parseAmount(String text) {
  String cleaned = text.replaceAll(RegExp(r'[^\d.]'), '');
  return double.tryParse(cleaned) ?? 0;
}
