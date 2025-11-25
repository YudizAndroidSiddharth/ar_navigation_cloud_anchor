import 'package:ar_navigation_cloud_anchor/poc/screens/poc_home_screen/poc_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ar_navigation_cloud_anchor/poc/utils/pref_utiles.dart';
import 'package:ar_navigation_cloud_anchor/utiles/snackbar_utiles.dart';

class DevelopersOptionsScreen extends StatefulWidget {
  const DevelopersOptionsScreen({super.key});

  @override
  State<DevelopersOptionsScreen> createState() =>
      _DevelopersOptionsScreenState();
}

class _DevelopersOptionsScreenState extends State<DevelopersOptionsScreen> {
  final TextEditingController _thresholdController = TextEditingController();
  final TextEditingController _stableSampleController = TextEditingController();

  int _currentThreshold = -70;
  int _currentStableSample = 5;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePrefs();
  }

  Future<void> _initializePrefs() async {
    await PrefUtils().init();
    setState(() {
      _currentThreshold = PrefUtils().getThresholdValue();
      _currentStableSample = PrefUtils().getRequiredStableSample();
      _thresholdController.text = _currentThreshold.toString();
      _stableSampleController.text = _currentStableSample.toString();
      _isLoading = false;
    });
  }

  void _handleSetThreshold() async {
    final text = _thresholdController.text.trim();
    final value = int.tryParse(text);
    if (value == null) {
      SnackBarUtil.showErrorSnackbar(context, 'कृपया मान्य पूर्णांक दर्ज करें');
      return;
    }
    if (value < -100 || value > -40) {
      SnackBarUtil.showErrorSnackbar(
        context,
        'मान -100 और -40 dBm के बीच होना चाहिए',
      );
      return;
    }
    await PrefUtils().setThresholdValue(value);
    setState(() {
      _currentThreshold = value;
    });
    SnackBarUtil.showSuccessSnackbar(
      context,
      'थ्रेशहोल्ड मान अपडेट किया गया: $value dBm',
    );
  }

  void _handleSetStableSample() async {
    final text = _stableSampleController.text.trim();
    final value = int.tryParse(text);
    if (value == null || value <= 0) {
      SnackBarUtil.showErrorSnackbar(
        context,
        'कृपया धनात्मक पूर्णांक दर्ज करें',
      );
      return;
    }
    await PrefUtils().setRequiredStableSample(value);
    setState(() {
      _currentStableSample = value;
    });
    SnackBarUtil.showSuccessSnackbar(
      context,
      'स्टेबल सैंपल मान अपडेट किया गया: $value',
    );
  }

  void _openPlaceholderScreen(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PlaceholderScreen(title: title)),
    );
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _stableSampleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          'Developer Mode',
          style: GoogleFonts.notoSansDevanagari(
            color: const Color(0xFF1F1F1F),
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF3C8C4E)),
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSettingCard(
                  title: 'Threshold Value (dBm)',
                  subtitle: 'Current: $_currentThreshold dBm',
                  controller: _thresholdController,
                  hintText: 'उदा. -70',
                  onSetPressed: _handleSetThreshold,
                ),
                const SizedBox(height: 16),
                _buildSettingCard(
                  title: 'Required Stable Sample',
                  subtitle: 'Current: $_currentStableSample',
                  controller: _stableSampleController,
                  hintText: 'उदा. 5',
                  onSetPressed: _handleSetStableSample,
                ),
                const SizedBox(height: 16),
                _buildActionCard(
                  title: 'Test Navigation',
                  subtitle: 'Navigate to testing workspace',
                  onTap: () => navigator?.push(
                    MaterialPageRoute(
                      builder: (context) => const PocHomeScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildActionCard(
                  title: 'Add Feeding Zone',
                  subtitle: 'Setup feeding zones for cows',
                  onTap: () => _openPlaceholderScreen('Add Feeding Zone'),
                ),
              ],
            ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hintText,
    required VoidCallback onSetPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF3C8C4E).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1F1F1F),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.notoSansDevanagari(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF3C8C4E)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF3C8C4E)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  style: GoogleFonts.notoSansDevanagari(fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onSetPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3C8C4E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'SET',
                  style: GoogleFonts.notoSansDevanagari(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3C8C4E).withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansDevanagari(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F1F1F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansDevanagari(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Color(0xFF3C8C4E),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF3C8C4E),
      ),
      body: Center(
        child: Text(
          'Coming soon',
          style: GoogleFonts.notoSansDevanagari(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
