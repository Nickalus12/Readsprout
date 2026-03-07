import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/name_setup_screen.dart';
import 'screens/profile_picker_screen.dart';
import 'services/progress_service.dart';
import 'services/audio_service.dart';
import 'services/player_settings_service.dart';
import 'services/profile_service.dart';
import 'services/review_service.dart';
import 'services/streak_service.dart';
import 'services/high_score_service.dart';
import 'services/stats_service.dart';
import 'widgets/floating_hearts_bg.dart';

class ReadingSproutApp extends StatefulWidget {
  const ReadingSproutApp({super.key});

  @override
  State<ReadingSproutApp> createState() => _ReadingSproutAppState();
}

class _ReadingSproutAppState extends State<ReadingSproutApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ProgressService _progressService;
  late final AudioService _audioService;
  late final PlayerSettingsService _settingsService;
  late final ProfileService _profileService;
  late final ReviewService _reviewService;
  late final StreakService _streakService;
  late final HighScoreService _highScoreService;
  late final StatsService _statsService;
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
    _profileService = ProfileService();
    _reviewService = ReviewService();
    _streakService = StreakService();
    _highScoreService = HighScoreService();
    _statsService = StatsService();

    // Get SharedPreferences once, share across all services
    final prefs = await SharedPreferences.getInstance();

    // Initialize all services in parallel for faster startup
    await Future.wait([
      _progressService.init(prefs).catchError((e) {
        debugPrint('ProgressService init failed: $e');
      }),
      _audioService.init().catchError((e) {
        debugPrint('AudioService init failed: $e');
      }),
      _settingsService.init(prefs).catchError((e) {
        debugPrint('PlayerSettingsService init failed: $e');
      }),
      _profileService.init().catchError((e) {
        debugPrint('ProfileService init failed: $e');
      }),
      _reviewService.init(prefs).catchError((e) {
        debugPrint('ReviewService init failed: $e');
      }),
      _streakService.init(prefs).catchError((e) {
        debugPrint('StreakService init failed: $e');
      }),
      _highScoreService.init(prefs).catchError((e) {
        debugPrint('HighScoreService init failed: $e');
      }),
      _statsService.init(prefs).catchError((e) {
        debugPrint('StatsService init failed: $e');
      }),
    ]);

    // Scope services to active profile
    _applyProfileScope();

    if (mounted) setState(() => _initialized = true);
  }

  /// Apply profile-scoped data keys so each kid has their own progress.
  void _applyProfileScope() {
    final profileId = _settingsService.activeProfileId ?? '';
    _progressService.switchProfile(profileId);
    _streakService.switchProfile(profileId);
    _highScoreService.switchProfile(profileId);
    _reviewService.switchProfile(profileId);
    _statsService.switchProfile(profileId);
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
          audioService: _audioService,
        ),
      ),
    );
  }

  void _onProfileSelected(String profileId) async {
    await _settingsService.switchToProfile(profileId);
    _applyProfileScope();
    setState(() {});
  }

  void _onNewProfile(String name) async {
    await _settingsService.addProfile(name);
    _applyProfileScope();
    setState(() {});
  }

  void _onSignOut() async {
    await _settingsService.signOut();
    setState(() {});
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
      title: 'Reading Sprout',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      // Cap text scaling so the UI doesn't break on devices with large font settings
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final clampedTextScaler = mediaQuery.textScaler.clamp(
          minScaleFactor: 0.8,
          maxScaleFactor: 1.1,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedTextScaler),
          child: child!,
        );
      },
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (!_initialized) {
      return const _SplashScreen();
    }

    // First-ever launch: no profiles, no setup → name entry
    if (!_settingsService.setupComplete && _settingsService.profiles.isEmpty) {
      return NameSetupScreen(
        onNameSubmitted: _onNameSubmitted,
        audioService: _audioService,
      );
    }

    // Profiles exist but none is active → profile picker
    if (_settingsService.activeProfileId == null) {
      return ProfilePickerScreen(
        settingsService: _settingsService,
        audioService: _audioService,
        onProfileSelected: _onProfileSelected,
        onNewProfile: _onNewProfile,
      );
    }

    // Active profile → home screen
    return HomeScreen(
      profileService: _profileService,
      progressService: _progressService,
      audioService: _audioService,
      streakService: _streakService,
      highScoreService: _highScoreService,
      statsService: _statsService,
      playerName: _settingsService.playerName,
      onChangeName: _onChangeName,
      onSignOut: _onSignOut,
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
                  'Reading Sprout',
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
