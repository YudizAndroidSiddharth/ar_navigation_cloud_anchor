import 'package:ar_navigation_cloud_anchor/poc/screens/credit_recharge_screen/credit_recharge_screen.dart';
import 'package:ar_navigation_cloud_anchor/poc/screens/developer_options_screen/developers_options_screen.dart';
import 'package:ar_navigation_cloud_anchor/poc/screens/food_bucket_screen/food_bucket_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure transparent status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3C8C4E),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3C8C4E), Color(0xFF66A86A)],
            ),
          ),
          child: _renderBody(context),
        ),
      ),
    );
  }

  Widget _renderBody(BuildContext context) {
    return Column(
      children: [
        _renderHeader(context),
        _renderCurvedSpacer(),
        _renderActionCard(
          titleLines: const ['डेवलपर', 'मोड'],
          icon: Icons.android,
          onTap: () {
            navigator?.push(
              MaterialPageRoute(
                builder: (context) => const DevelopersOptionsScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _renderActionCard(
          titleLines: const ['फूड', 'बकेट'],
          icon: Icons.shopping_basket_outlined,
          onTap: () {
            navigator?.push(
              MaterialPageRoute(builder: (context) => const FoodBucketScreen()),
            );
          },
        ),
        const SizedBox(height: 16),
        _renderActionCard(
          titleLines: const ['क्रेडिट', 'रिचार्ज'],
          icon: Icons.currency_rupee,
          onTap: () {
            navigator?.push(
              MaterialPageRoute(builder: (context) => CreditRechargeScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _renderHeader(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final headerHeight = size.height * 0.40;

    return SizedBox(
      height: headerHeight,
      width: double.infinity,
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.white, // header area is white without curved top
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 220,
                  height: 220,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.transparent,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
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
          color: Color.fromARGB(255, 62, 141, 80), // middle green section
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(32),
            topRight: Radius.circular(32),
          ),
        ),
      ),
    );
  }

  Widget _renderActionCard({
    required List<String> titleLines,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final textStyle = GoogleFonts.notoSansDevanagari(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1F1F1F),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.08),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 125,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: titleLines
                        .map((line) => Text(line, style: textStyle))
                        .toList(),
                  ),
                ),
                Icon(icon, size: 60, color: const Color(0xFF3C8C4E)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
