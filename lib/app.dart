import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/name_setup_screen.dart';
import 'services/progress_service.dart';
import 'services/audio_service.dart';
import 'services/player_settings_service.dart';
import 'services/review_service.dart';
import 'services/streak_service.dart';
import 'widgets/floating_hearts_bg.dart';

class SightWordsApp extends StatefulWidget {
  const SightWordsApp({super.key});

  @override
  State<SightWordsApp> createState() => _SightWordsAppState();
}

class _SightWordsAppState extends State<SightWordsApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ProgressService _progressService;
  late final AudioService _audioService;
  late final PlayerSettingsService _settingsService;
  late final ReviewService _reviewService;
  late final StreakService _streakService;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _progressService = ProgressService();
    _audioService = AudioService();
    _settingsService = PlayerSettingsService();
    _reviewService = ReviewService();
    _streakService = StreakService();

    try {
      await _progressService.init();
    } catch (e) {
      debugPrint('ProgressService init failed: $e');
    }

    try {
      await _audioService.init();
    } catch (e) {
      debugPrint('AudioService init failed (audio will be unavailable): $e');
    }

    try {
      await _settingsService.init();
    } catch (e) {
      debugPrint('PlayerSettingsService init failed: $e');
    }

    try {
      await _reviewService.init();
    } catch (e) {
      debugPrint('ReviewService init failed: $e');
    }

    try {
      await _streakService.init();
    } catch (e) {
      debugPrint('StreakService init failed: $e');
    }

    if (mounted) setState(() => _initialized = true);
  }

  void _onNameSubmitted(String name) async {
    await _settingsService.setPlayerName(name);
    setState(() {});
  }

  void _onChangeName() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => NameSetupScreen(
          onNameSubmitted: (name) {
            _onNameSubmitted(name);
            nav.pop();
          },
          onBack: () => nav.pop(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ReadSprout',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_initialized) {
      return const _SplashScreen();
    }

    // Show name setup on first launch
    if (!_settingsService.setupComplete) {
      return NameSetupScreen(onNameSubmitted: _onNameSubmitted);
    }

    return HomeScreen(
      progressService: _progressService,
      audioService: _audioService,
      streakService: _streakService,
      playerName: _settingsService.playerName,
      onChangeName: _onChangeName,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, AppColors.backgroundEnd],
              ),
            ),
          ),

          // Floating hearts — even the splash is alive
          const Positioned.fill(
            child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
          ),

          // Loading indicator with logo
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 24),
                Text(
                  'ReadSprout',
                  style: GoogleFonts.fredoka(
                    fontSize: 32,
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.electricBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
