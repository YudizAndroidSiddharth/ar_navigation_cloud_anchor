import 'package:ar_navigation_cloud_anchor/poc/screens/feeding_zone_screen/select_feeding_zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';

class CowItem {
  final String name;
  final String imagePath;
  bool isSelected;

  CowItem({
    required this.name,
    required this.imagePath,
    this.isSelected = false,
  });
}

class CowSelctionScreen extends StatefulWidget {
  const CowSelctionScreen({super.key});

  @override
  State<CowSelctionScreen> createState() => _CowSelctionScreenState();
}

class _CowSelctionScreenState extends State<CowSelctionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<CowItem> _allCows = [];
  List<CowItem> _filteredCows = [];
  CowItem? _selectedCow;

  @override
  void initState() {
    super.initState();
    _initializeCows();
    _searchController.addListener(_onSearchChanged);
  }

  void _initializeCows() {
    _allCows.addAll([
      CowItem(name: 'निराली', imagePath: 'assets/images/cow.png'),
      CowItem(name: 'नम्रता', imagePath: 'assets/images/cow.png'),
      CowItem(name: 'यशोदा', imagePath: 'assets/images/cow.png'),
      CowItem(name: 'संध्या', imagePath: 'assets/images/cow.png'),
      CowItem(name: 'सोनम', imagePath: 'assets/images/cow.png'),
      CowItem(name: 'जानकी', imagePath: 'assets/images/cow.png'),
    ]);
    _filteredCows = List.from(_allCows);
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCows = List.from(_allCows);
      } else {
        _filteredCows = _allCows
            .where((cow) => cow.name.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  void _selectCow(CowItem cow) {
    setState(() {
      // Clear previous selection
      if (_selectedCow != null) {
        _selectedCow!.isSelected = false;
      }
      // Select new cow
      cow.isSelected = true;
      _selectedCow = cow;
    });
  }

  void _handleProceedButton() {
    if (_selectedCow == null) {
      SnackBarUtil.showErrorSnackbar(context, 'कृपया एक गाय चुनें।');
    } else {
      SnackBarUtil.showSuccessSnackbar(
        context,
        'आपने ${_selectedCow!.name} चुनी है',
      );
      navigator?.push(
        MaterialPageRoute(
          builder: (context) => const SelectFeedingZoneScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    SnackBarUtil.clearSnackBars(context);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          SnackBarUtil.clearSnackBars(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _renderTopBar(context),
              _renderSearchBar(context),
              Expanded(child: _renderCowList(context)),
            ],
          ),
        ),
        bottomNavigationBar: _renderBottomButton(context),
      ),
    );
  }

  Widget _renderTopBar(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Color(0xFF3C8C4E),
                  ),
                ),
                Expanded(
                  child: Text(
                    'गाय पसंद करे',
                    style: GoogleFonts.notoSansDevanagari(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F1F1F),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    // Menu action
                  },
                  icon: const Icon(
                    Icons.menu,
                    color: Color(0xFF3C8C4E),
                    size: 28,
                  ),
                ),
              ],
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
          borderRadius: BorderRadius.circular(30),
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

  Widget _renderCowList(BuildContext context) {
    if (_filteredCows.isEmpty) {
      return Center(
        child: Text(
          'कोई गाय नहीं मिली',
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filteredCows.length,
      itemBuilder: (context, index) {
        return _renderCowCard(context, _filteredCows[index]);
      },
    );
  }

  Widget _renderCowCard(BuildContext context, CowItem cow) {
    return GestureDetector(
      onTap: () => _selectCow(cow),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF3C8C4E), width: 2),
        ),
        child: Row(
          children: [
            // Cow icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF3C8C4E).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                cow.imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.pets,
                    color: Color(0xFF3C8C4E),
                    size: 30,
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            // Cow name
            Expanded(
              child: Text(
                cow.name,
                style: GoogleFonts.notoSansDevanagari(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F1F1F),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Selection circle
            GestureDetector(
              onTap: () => _selectCow(cow),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cow.isSelected
                      ? const Color(0xFF3C8C4E)
                      : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: cow.isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderBottomButton(BuildContext context) {
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
          onPressed: _handleProceedButton,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3C8C4E),
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
}
