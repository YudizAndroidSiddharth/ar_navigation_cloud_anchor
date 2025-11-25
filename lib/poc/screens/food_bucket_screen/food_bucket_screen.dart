import 'package:ar_navigation_cloud_anchor/poc/screens/cow_selection_screen/cow_selction_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ar_navigation_cloud_anchor/poc/utils/pref_utiles.dart';
import 'package:ar_navigation_cloud_anchor/poc/screens/credit_recharge_screen/credit_recharge_screen.dart';
import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';

class CowFoodItem {
  final String name;
  final String imagePath;
  final double price;
  bool isSelected;

  CowFoodItem({
    required this.name,
    required this.imagePath,
    required this.price,
    this.isSelected = false,
  });
}

class FoodBucketScreen extends StatefulWidget {
  const FoodBucketScreen({super.key});

  @override
  State<FoodBucketScreen> createState() => _FoodBucketScreenState();
}

class _FoodBucketScreenState extends State<FoodBucketScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<CowFoodItem> _allFoodItems = [];
  List<CowFoodItem> _filteredFoodItems = [];
  int _availableCredit = 0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeFoodItems();
    _loadAvailableCredit();
  }

  Future<void> _loadAvailableCredit() async {
    await PrefUtils().init();
    setState(() {
      _availableCredit = PrefUtils().getAvailableBalance();
      _isInitialized = true;
    });
  }

  void _initializeFoodItems() {
    _allFoodItems = [
      CowFoodItem(
        name: 'सूखा चारा',
        imagePath:
            'assets/images/chara.jpeg', // Placeholder - replace with actual food images
        price: 10,
      ),
      CowFoodItem(
        name: 'गीला चारा',
        imagePath: 'assets/images/food_green.jpg',
        price: 30,
      ),
      CowFoodItem(
        name: 'घूघळी',
        imagePath: 'assets/images/mung.jpeg',
        price: 20,
      ),
      CowFoodItem(
        name: 'कपासिया खोळ',
        imagePath: 'assets/images/khol.jpeg',
        price: 40,
      ),
      CowFoodItem(
        name: 'मक्के का भूसा',
        imagePath: 'assets/images/corn.jpg',
        price: 50,
      ),
      CowFoodItem(
        name: 'मग की चुनी',
        imagePath: 'assets/images/mung_chuni.jpeg',
        price: 60,
      ),
    ];
    _filteredFoodItems = List.from(_allFoodItems);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredFoodItems = List.from(_allFoodItems);
      } else {
        // Use the same objects from _allFoodItems to preserve selection state
        _filteredFoodItems = _allFoodItems
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      // Since _filteredFoodItems contains references to the same objects,
      // we can directly toggle the selection
      final item = _filteredFoodItems[index];
      item.isSelected = !item.isSelected;
    });
  }

  List<CowFoodItem> get _selectedItems {
    return _allFoodItems.where((item) => item.isSelected).toList();
  }

  double _getSelectedTotal() {
    return _selectedItems.fold(0.0, (sum, item) => sum + item.price);
  }

  Future<void> _handleProceedButton() async {
    if (_selectedItems.isEmpty) {
      return;
    }

    final total = _getSelectedTotal();

    if (total > _availableCredit) {
      SnackBarUtil.showWarningSnackbar(
        context,
        'क्रेडिट अपर्याप्त है। कृपया क्रेडिट खरीदें।',
        action: SnackBarAction(
          label: 'क्रेडिट खरीदें',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreditRechargeScreen(),
              ),
            ).then((_) => _loadAvailableCredit());
          },
        ),
      );
      return;
    }

    // Deduct amount from credit
    final newBalance = _availableCredit - total.toInt();
    await PrefUtils().setAvailableBalance(newBalance);

    setState(() {
      _availableCredit = newBalance;
      // Clear selections
      for (var item in _allFoodItems) {
        item.isSelected = false;
      }
    });

    SnackBarUtil.showInfoSnackbar(
      context,
      'सफलतापूर्वक खरीदारी की गई। शेष क्रेडिट: ₹$newBalance',
    );
    navigator?.push(
      MaterialPageRoute(builder: (context) => const CowSelctionScreen()),
    );
  }

  @override
  void dispose() {
    // Clear snackbars when leaving the screen
    SnackBarUtil.clearSnackBars(context);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          // Clear snackbars when navigating back
          SnackBarUtil.clearSnackBars(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6F8),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _renderAppBar(context),
              _renderSearchBar(context),
              Expanded(child: _renderFoodGrid(context)),
            ],
          ),
        ),
        bottomNavigationBar: _renderBottomButton(context),
        floatingActionButton: _selectedItems.isNotEmpty
            ? _renderFloatingActionButton(context)
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _renderAppBar(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'फूड बकेट',
                  style: GoogleFonts.notoSansDevanagari(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F1F1F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'उपलब्ध क्रेडिट: ₹$_availableCredit',
                  style: GoogleFonts.notoSansDevanagari(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3C8C4E),
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: () {
                // Menu action
              },
              icon: const Icon(Icons.menu, color: Color(0xFF3C8C4E), size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderSearchBar(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'खोजें',
            hintStyle: GoogleFonts.notoSansDevanagari(color: Colors.grey[600]),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF3C8C4E)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: GoogleFonts.notoSansDevanagari(),
        ),
      ),
    );
  }

  Widget _renderFoodGrid(BuildContext context) {
    if (_filteredFoodItems.isEmpty) {
      return Center(
        child: Text(
          'कोई आइटम नहीं मिला',
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: _filteredFoodItems.length,
      itemBuilder: (context, index) {
        return _renderFoodCard(context, index);
      },
    );
  }

  Widget _renderFoodCard(BuildContext context, int index) {
    final item = _filteredFoodItems[index];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleSelection(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: item.isSelected
                  ? const Color(0xFF3C8C4E)
                  : Colors.grey[300]!,
              width: item.isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                  child: Image.asset(
                    item.imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey,
                          size: 40,
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: GoogleFonts.notoSansDevanagari(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F1F1F),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '₹${item.price.toStringAsFixed(0)}',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF3C8C4E),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            _toggleSelection(index);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3C8C4E),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.isSelected ? Icons.check : Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderBottomButton(BuildContext context) {
    final hasSelection = _selectedItems.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: hasSelection ? _handleProceedButton : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3C8C4E),
            disabledBackgroundColor: Colors.grey[300],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
            elevation: 0,
          ),
          child: Text(
            'आगे बढ़ें',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderFloatingActionButton(BuildContext context) {
    final total = _getSelectedTotal();

    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF3C8C4E),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            'कुल: ₹${total.toStringAsFixed(0)}',
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
