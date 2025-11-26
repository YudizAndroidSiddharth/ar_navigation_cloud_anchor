import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ar_navigation_cloud_anchor/poc/utils/pref_utiles.dart';

class CreditRechargeScreen extends StatefulWidget {
  const CreditRechargeScreen({super.key});

  @override
  State<CreditRechargeScreen> createState() => _CreditRechargeScreenState();
}

class _CreditRechargeScreenState extends State<CreditRechargeScreen> {
  int _selectedAmount = 0;
  int _availableBalance = 0;
  bool _isLoading = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeBalance();
  }

  Future<void> _initializeBalance() async {
    await PrefUtils().init();
    setState(() {
      _availableBalance = PrefUtils().getAvailableBalance();
      _isInitialized = true;
    });
  }

  void _incrementAmount() {
    setState(() {
      if (_selectedAmount < 100) {
        _selectedAmount += 10;
      }
    });
  }

  void _decrementAmount() {
    setState(() {
      if (_selectedAmount > 0) {
        _selectedAmount -= 10;
      }
    });
  }

  Future<void> _purchaseCredit() async {
    if (_selectedAmount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an amount'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Simulate processing delay
    await Future.delayed(const Duration(seconds: 2));

    // Update balance
    final newBalance = _availableBalance + _selectedAmount;
    await PrefUtils().setAvailableBalance(newBalance);

    setState(() {
      _isLoading = false;
      _availableBalance = newBalance;
      _selectedAmount = 0;
    });

    if (mounted) {
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Recharge successful. Credit added.'),
      //     backgroundColor: Colors.green,
      //     duration: Duration(seconds: 2),
      //   ),
      // );
      SnackBarUtil.showSuccessSnackbar(
        context,
        'क्रेडिट खरीदें सफलतापूर्वक हुआ',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                _renderHeader(context),
                _renderCurvedSpacer(),
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: _renderBottomSection(context),
                  ),
                ),
              ],
            ),
            if (_isLoading) _renderLoader(context),
          ],
        ),
      ),
    );
  }

  Widget _renderHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final headerHeight = size.height * 0.55;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        children: [
          // Green gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF3C8C4E).withOpacity(0.9),
                  const Color(0xFF66A86A).withOpacity(0.9),
                ],
              ),
            ),
          ),
          Positioned(
            top: statusBarHeight + 16,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              color: Colors.white,
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 200,
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                // App name
                Text(
                  'GOVALIYO',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    color: Colors.white,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // White circular area with checkmark

                // Hindi text and balance
                Text(
                  'उपलब्ध क्रेडिट',
                  style: GoogleFonts.notoSansDevanagari(
                    fontSize: 18,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₹$_availableBalance',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderCurvedSpacer() {
    return Transform.translate(
      offset: const Offset(0, -24),
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
      ),
    );
  }

  Widget _renderBottomSection(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _renderCreditPurchaseControls(context),
          const SizedBox(height: 24),
          _renderPurchaseButton(context),
        ],
      ),
    );
  }

  Widget _renderCreditPurchaseControls(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F8),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFF3C8C4E), width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Minus button
            IconButton(
              onPressed: _decrementAmount,
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 40,
              color: const Color(0xFF3C8C4E),
            ),
            // Amount display
            Text(
              '₹$_selectedAmount',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF3C8C4E),
              ),
            ),
            // Plus button
            IconButton(
              onPressed: _incrementAmount,
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 40,
              color: const Color(0xFF3C8C4E),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderPurchaseButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _purchaseCredit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3C8C4E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          elevation: 4,
        ),
        child: Text(
          'क्रेडिट खरीदें',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _renderLoader(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3C8C4E)),
              ),
              const SizedBox(height: 16),
              Text(
                'Processing…',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF1F1F1F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
