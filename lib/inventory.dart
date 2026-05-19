import 'dart:convert';

import 'package:flutter/material.dart';
import 'odoo_service.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final OdooService _odoo = OdooService();
  final TextEditingController _search = TextEditingController();

  static const Color _primary = Color(0xFF282454);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _loadProducts();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await _odoo.checkAndLoadUserCredentials();
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _error = 'Not signed in. Please log in again.';
          _loading = false;
        });
        return;
      }
      final list = await _odoo.fetchInventoryProductList();
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where((p) => (p['name']?.toString() ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final surface = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final borderColor = isDark ? Colors.white24 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text('Inventory'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadProducts,
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _primary,
                  onRefresh: _loadProducts,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: TextField(
                            controller: _search,
                            decoration: InputDecoration(
                              hintText: 'Search products…',
                              prefixIcon: const Icon(Icons.search, size: 22),
                              filled: true,
                              fillColor: surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            '${_filteredProducts.length} product${_filteredProducts.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ),
                      ),
                      if (_filteredProducts.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              _products.isEmpty
                                  ? 'No products found. Check Inventory access in Odoo.'
                                  : 'No matches for your search.',
                              style: TextStyle(color: muted),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ProductCard(
                                  row: _filteredProducts[index],
                                  isDark: isDark,
                                  headerColor: _primary,
                                ),
                              ),
                              childCount: _filteredProducts.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.row,
    required this.isDark,
    required this.headerColor,
  });

  final Map<String, dynamic> row;
  final bool isDark;
  final Color headerColor;

  @override
  Widget build(BuildContext context) {
    final name = (row['name']?.toString() ?? '—').trim().isEmpty
        ? '—'
        : row['name'].toString();
    final price = row['list_price'] is num
        ? (row['list_price'] as num).toDouble()
        : double.tryParse(row['list_price']?.toString() ?? '') ?? 0.0;
    final qty = row['qty_available'] is num
        ? (row['qty_available'] as num).toDouble()
        : double.tryParse(row['qty_available']?.toString() ?? '') ?? 0.0;
    final uom = (row['uom']?.toString() ?? '').trim();
    final imgB64 = (row['image_base64']?.toString() ?? '').trim();

    ImageProvider? thumb;
    if (imgB64.isNotEmpty) {
      try {
        thumb = MemoryImage(base64Decode(imgB64));
      } catch (_) {
        thumb = null;
      }
    }

    final border = isDark ? Colors.white24 : Colors.grey.shade300;
    final cardBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF374151);
    final subColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
              image: thumb != null
                  ? DecorationImage(image: thumb, fit: BoxFit.cover)
                  : null,
            ),
            child: thumb == null
                ? Icon(
                    Icons.inventory_2_outlined,
                    color: headerColor.withOpacity(0.55),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Price: RM ${price.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
                const SizedBox(height: 2),
                Text(
                  'On hand: ${qty.toStringAsFixed(2)}${uom.isEmpty ? '' : ' $uom'}',
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
