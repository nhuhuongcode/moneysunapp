// lib/presentation/widgets/smart_description_autocomplete.dart

import 'package:flutter/material.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SmartDescriptionAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final TransactionType? transactionType;
  final String? categoryId;
  final double? amount;
  final Function(String)? onSelected;
  final Function(String)? onChanged;
  final String? hintText;
  final int maxSuggestions;
  final bool showTrendingChips;
  final bool enableContextualSuggestions;

  const SmartDescriptionAutocomplete({
    super.key,
    required this.controller,
    this.transactionType,
    this.categoryId,
    this.amount,
    this.onSelected,
    this.onChanged,
    this.hintText = 'Nhập mô tả...',
    this.maxSuggestions = 8,
    this.showTrendingChips = true,
    this.enableContextualSuggestions = true,
  });

  @override
  State<SmartDescriptionAutocomplete> createState() =>
      _SmartDescriptionAutocompleteState();
}

class _SmartDescriptionAutocompleteState
    extends State<SmartDescriptionAutocomplete> {
  final OfflineSyncService _syncService = OfflineSyncService();

  List<String> _trendingDescriptions = [];
  List<String> _contextualSuggestions = [];
  bool _isLoadingTrending = false;
  bool _isLoadingContextual = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void didUpdateWidget(SmartDescriptionAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reload contextual suggestions when context changes
    if (oldWidget.transactionType != widget.transactionType ||
        oldWidget.categoryId != widget.categoryId ||
        (oldWidget.amount != widget.amount &&
            (oldWidget.amount == null || widget.amount == null))) {
      _loadContextualSuggestions();
    }
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadTrendingDescriptions(),
      _loadContextualSuggestions(),
    ]);
  }

  Future<void> _loadTrendingDescriptions() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isLoadingTrending = true;
    });

    try {
      final suggestions = await _syncService.getDescriptionSuggestions(
        userId,
        limit: 6,
        type: widget.transactionType,
      );

      setState(() {
        _trendingDescriptions = suggestions;
        _isLoadingTrending = false;
      });
    } catch (e) {
      print('Error loading trending descriptions: $e');
      setState(() {
        _isLoadingTrending = false;
      });
    }
  }

  Future<void> _loadContextualSuggestions() async {
    if (!widget.enableContextualSuggestions) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isLoadingContextual = true;
    });

    try {
      final suggestions = await _syncService.getContextualSuggestions(
        userId,
        type: widget.transactionType,
        categoryId: widget.categoryId,
        amount: widget.amount,
        limit: 4,
      );

      setState(() {
        _contextualSuggestions = suggestions;
        _isLoadingContextual = false;
      });
    } catch (e) {
      print('Error loading contextual suggestions: $e');
      setState(() {
        _isLoadingContextual = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main autocomplete field
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) async {
            if (textEditingValue.text.isEmpty) {
              // Return recent/trending when empty
              return _trendingDescriptions.take(widget.maxSuggestions);
            }

            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId == null) return <String>[];

            // Search with advanced features
            final searchResults = await _syncService.searchDescriptionHistory(
              userId,
              textEditingValue.text,
              limit: widget.maxSuggestions,
              type: widget.transactionType,
              fuzzySearch: true,
            );

            return searchResults;
          },
          onSelected: (String selection) {
            widget.controller.text = selection;
            widget.onSelected?.call(selection);

            // Save usage for learning
            _saveDescriptionUsage(selection);
          },
          fieldViewBuilder:
              (context, controller, focusNode, onEditingComplete) {
                // Sync with external controller
                controller.text = widget.controller.text;
                controller.selection = widget.controller.selection;

                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.description_outlined),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              controller.clear();
                              widget.controller.clear();
                              widget.onChanged?.call('');
                            },
                          )
                        : null,
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) {
                    // Sync with external controller
                    widget.controller.text = value;
                    widget.controller.selection = controller.selection;
                    widget.onChanged?.call(value);
                  },
                );
              },
          optionsViewBuilder: (context, onSelected, options) {
            return _buildOptionsView(context, onSelected, options);
          },
        ),

        // Smart suggestion chips
        if (widget.showTrendingChips) ...[
          const SizedBox(height: 12),
          _buildSuggestionChips(),
        ],
      ],
    );
  }

  Widget _buildOptionsView(
    BuildContext context,
    Function(String) onSelected,
    Iterable<String> options,
  ) {
    if (options.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300),
          width: MediaQuery.of(context).size.width - 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: Colors.grey.shade100),
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              final isRecent = _trendingDescriptions.contains(option);
              final isContextual = _contextualSuggestions.contains(option);

              return ListTile(
                dense: true,
                leading: _buildSuggestionIcon(isRecent, isContextual),
                title: Text(
                  option,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _buildSuggestionBadge(isRecent, isContextual),
                onTap: () => onSelected(option),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionIcon(bool isRecent, bool isContextual) {
    if (isContextual) {
      return Icon(Icons.auto_awesome, size: 18, color: Colors.purple.shade600);
    } else if (isRecent) {
      return Icon(Icons.history, size: 18, color: Colors.blue.shade600);
    } else {
      return Icon(Icons.description, size: 18, color: Colors.grey.shade600);
    }
  }

  Widget? _buildSuggestionBadge(bool isRecent, bool isContextual) {
    if (isContextual) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.purple.shade200, width: 0.5),
        ),
        child: Text(
          'Smart',
          style: TextStyle(
            fontSize: 10,
            color: Colors.purple.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else if (isRecent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200, width: 0.5),
        ),
        child: Text(
          'Gần đây',
          style: TextStyle(
            fontSize: 10,
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildSuggestionChips() {
    final allSuggestions = [
      ..._contextualSuggestions,
      ..._trendingDescriptions,
    ].toSet().take(6).toList();

    if (allSuggestions.isEmpty &&
        !_isLoadingTrending &&
        !_isLoadingContextual) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section headers and chips
        if (_contextualSuggestions.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: Colors.purple.shade600),
              const SizedBox(width: 6),
              Text(
                'Gợi ý thông minh:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _contextualSuggestions.take(3).map((desc) {
              return _buildSuggestionChip(
                desc,
                Colors.purple.shade50,
                Colors.purple.shade600,
                Colors.purple.shade200,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Trending suggestions
        if (_trendingDescriptions.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.trending_up, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 6),
              Text(
                'Thường dùng:',
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
            children: _trendingDescriptions
                .where((desc) => !_contextualSuggestions.contains(desc))
                .take(4)
                .map((desc) {
                  return _buildSuggestionChip(
                    desc,
                    Colors.blue.shade50,
                    Colors.blue.shade600,
                    Colors.blue.shade200,
                  );
                })
                .toList(),
          ),
        ],

        // Loading indicators
        if (_isLoadingTrending || _isLoadingContextual) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Đang tải gợi ý...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSuggestionChip(
    String description,
    Color backgroundColor,
    Color textColor,
    Color borderColor,
  ) {
    return ActionChip(
      label: Text(
        description,
        style: TextStyle(
          fontSize: 12,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: backgroundColor,
      side: BorderSide(color: borderColor, width: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelPadding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        widget.controller.text = description;
        widget.onSelected?.call(description);

        // Save usage for learning
        _saveDescriptionUsage(description);

        // Dismiss keyboard
        FocusScope.of(context).unfocus();
      },
    );
  }

  Future<void> _saveDescriptionUsage(String description) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      await _syncService.saveDescriptionWithContext(
        userId,
        description,
        type: widget.transactionType,
        categoryId: widget.categoryId,
        amount: widget.amount,
      );
    } catch (e) {
      print('Error saving description usage: $e');
    }
  }
}

// ============ ENHANCED DESCRIPTION FIELD WIDGET ============

/// A comprehensive description input widget with smart features
class EnhancedDescriptionField extends StatefulWidget {
  final TextEditingController controller;
  final TransactionType? transactionType;
  final String? categoryId;
  final double? amount;
  final Function(String)? onChanged;
  final String? labelText;
  final String? hintText;
  final bool required;
  final int? maxLength;
  final int maxLines;

  const EnhancedDescriptionField({
    super.key,
    required this.controller,
    this.transactionType,
    this.categoryId,
    this.amount,
    this.onChanged,
    this.labelText = 'Mô tả',
    this.hintText = 'Nhập mô tả giao dịch...',
    this.required = false,
    this.maxLength = 100,
    this.maxLines = 2,
  });

  @override
  State<EnhancedDescriptionField> createState() =>
      _EnhancedDescriptionFieldState();
}

class _EnhancedDescriptionFieldState extends State<EnhancedDescriptionField> {
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _showSuggestions = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with optional indicator
            Row(
              children: [
                Text(
                  widget.labelText!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.required) ...[
                  const SizedBox(width: 4),
                  Text(
                    '*',
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.controller.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '${widget.controller.text.length}${widget.maxLength != null ? '/${widget.maxLength}' : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Smart autocomplete field
            SmartDescriptionAutocomplete(
              controller: widget.controller,
              transactionType: widget.transactionType,
              categoryId: widget.categoryId,
              amount: widget.amount,
              hintText: widget.hintText,
              maxSuggestions: 6,
              showTrendingChips: true,
              enableContextualSuggestions: true,
              onChanged: widget.onChanged,
              onSelected: (description) {
                widget.onChanged?.call(description);
              },
            ),

            // Additional features
            const SizedBox(height: 8),
            _buildAdditionalFeatures(),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalFeatures() {
    return Row(
      children: [
        // Smart categorization hint
        if (widget.transactionType != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getTypeColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getTypeColor().withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_getTypeIcon(), size: 12, color: _getTypeColor()),
                const SizedBox(width: 4),
                Text(
                  _getTypeText(),
                  style: TextStyle(
                    fontSize: 10,
                    color: _getTypeColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        const Spacer(),

        // Smart learning indicator
        if (widget.controller.text.isNotEmpty)
          Tooltip(
            message: 'Mô tả này sẽ được học để gợi ý trong tương lai',
            child: Icon(
              Icons.psychology,
              size: 14,
              color: Colors.purple.shade400,
            ),
          ),
      ],
    );
  }

  Color _getTypeColor() {
    switch (widget.transactionType) {
      case TransactionType.income:
        return Colors.green;
      case TransactionType.expense:
        return Colors.red;
      case TransactionType.transfer:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getTypeIcon() {
    switch (widget.transactionType) {
      case TransactionType.income:
        return Icons.trending_up;
      case TransactionType.expense:
        return Icons.trending_down;
      case TransactionType.transfer:
        return Icons.swap_horiz;
      default:
        return Icons.description;
    }
  }

  String _getTypeText() {
    switch (widget.transactionType) {
      case TransactionType.income:
        return 'Thu nhập';
      case TransactionType.expense:
        return 'Chi tiêu';
      case TransactionType.transfer:
        return 'Chuyển tiền';
      default:
        return 'Giao dịch';
    }
  }
}

// ============ USAGE ANALYTICS WIDGET ============

/// Widget to show description usage analytics (for debug/settings)
class DescriptionAnalyticsWidget extends StatefulWidget {
  const DescriptionAnalyticsWidget({super.key});

  @override
  State<DescriptionAnalyticsWidget> createState() =>
      _DescriptionAnalyticsWidgetState();
}

class _DescriptionAnalyticsWidgetState
    extends State<DescriptionAnalyticsWidget> {
  final OfflineSyncService _syncService = OfflineSyncService();
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      // This would need to be implemented in the local database service
      // final stats = await _localDb.getDescriptionStats(userId);
      final stats = {
        'totalDescriptions': 25,
        'recentDescriptions': 8,
        'topUsedDescriptions': [
          {'description': 'Ăn trưa', 'count': 15},
          {'description': 'Xăng xe', 'count': 12},
          {'description': 'Cafe', 'count': 8},
        ],
      };

      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading description stats: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Thống kê mô tả',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats overview
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Tổng mô tả',
                  '${_stats['totalDescriptions'] ?? 0}',
                  Icons.description,
                  Colors.blue,
                ),
                _buildStatItem(
                  'Dùng gần đây',
                  '${_stats['recentDescriptions'] ?? 0}',
                  Icons.schedule,
                  Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Top used descriptions
            const Text(
              'Mô tả thường dùng nhất:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),

            ...((_stats['topUsedDescriptions'] as List?) ?? [])
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['description'],
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${item['count']}x',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
