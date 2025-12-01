import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/saved_location.dart';
import 'controller/poc_navigation_controller.dart';
import 'widgets/mini_map_widget.dart';
import 'widgets/signal_analytics_card.dart';
import 'widgets/vertical_progress_line.dart';

class PocNavigationScreen extends StatefulWidget {
  final SavedLocation target;

  const PocNavigationScreen({super.key, required this.target});

  @override
  State<PocNavigationScreen> createState() => _PocNavigationScreenState();
}

class _PocNavigationScreenState extends State<PocNavigationScreen> {
  late PocNavigationController controller;

  @override
  void initState() {
    super.initState();
    // Delete existing controller if any
    if (Get.isRegistered<PocNavigationController>()) {
      Get.delete<PocNavigationController>();
    }
    // Create and register new controller
    controller = Get.put(PocNavigationController(widget.target));
  }

  @override
  void dispose() {
    // Ensure controller is properly disposed when screen is disposed
    _cleanupController();
    super.dispose();
  }

  void _cleanupController() {
    if (Get.isRegistered<PocNavigationController>()) {
      final controllerToCleanup = Get.find<PocNavigationController>();
      // Manually call cleanup to ensure scanning stops immediately
      controllerToCleanup.cleanup();
      // Then delete the controller
      Get.delete<PocNavigationController>();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) {
          // Cleanup controller immediately when navigating back
          _cleanupController();
        }
      },
      child: Scaffold(appBar: _renderAppBar(), body: _renderBody()),
    );
  }

  PreferredSizeWidget _renderAppBar() {
    return AppBar(
      title: Text('Navigate to ${widget.target.name}'),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [],
    );
  }

  Widget _renderBody() {
    return Stack(children: [_renderBackground(), _renderMainContent()]);
  }

  Widget _renderBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0a1a2e), Color(0xFF16213e), Color(0xFF1a252f)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _renderMainContent() {
    return Column(
      children: [
        const SizedBox(height: 24),
        _renderNavigationArea(),
        const SizedBox(height: 16),
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 16),
        //   child: SignalAnalyticsCard(controller: controller),
        // ),
        // const SizedBox(height: 12),
        MiniMapWidget(
          controller: controller,
          mapAssetPath: 'assets/images/bhalka2D_map.png',
        ),
        _renderDistanceInfo(),
      ],
    );
  }

  Widget _renderNavigationArea() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(child: VerticalProgressLine(controller: controller)),
            const SizedBox(width: 16),
            Expanded(child: _renderNavigationArrow()),
          ],
        ),
      ),
    );
  }

  Widget _renderNavigationArrow() {
    return Obx(
      () => Center(
        child: Transform.rotate(
          angle: controller.navigationArrowRadians,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: controller.hasHeading ? Colors.white54 : Colors.white24,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.navigation,
              size: 60,
              color: controller.hasHeading ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _renderDistanceInfo() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Obx(
            () => Text(
              controller.distanceText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
