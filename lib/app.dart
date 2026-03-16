import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/name_setup_screen.dart';
import 'screens/onboarding_tutorial_screen.dart';
import 'screens/profile_picker_screen.dart';
import 'services/progress_service.dart';
import 'services/audio_service.dart';
import 'services/deepgram_tts_service.dart';
import 'services/player_settings_service.dart';
import 'services/profile_service.dart';
import 'services/review_service.dart';
import 'services/streak_service.dart';
import 'services/high_score_service.dart';
import 'services/adaptive_music_service.dart';
import 'services/avatar_personality_service.dart';
import 'services/stats_service.dart';
import 'services/adaptive_difficulty_service.dart';
import 'services/first_time_hints_service.dart';
import 'avatar/shader_loader.dart';
import 'widgets/floating_hearts_bg.dart';

class ReadingSproutApp extends StatefulWidget {
  const ReadingSproutApp({super.key});

  @override
  State<ReadingSproutApp> createState() => _ReadingSproutAppState();
}

class _ReadingSproutAppState extends State<ReadingSproutApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycleListener;
  late final ProgressService _progressService;
  late final AudioService _audioService;
  late final PlayerSettingsService _settingsService;
  late final ProfileService _profileService;
  late final ReviewService _reviewService;
  late final StreakService _streakService;
  late final HighScoreService _highScoreService;
  late final StatsService _statsService;
  late final DeepgramTtsService _deepgramTtsService;
  late final AvatarPersonalityService _personalityService;
  late final AdaptiveDifficultyService _adaptiveDifficultyService;
  late final AdaptiveMusicService _adaptiveMusicService;
  late final FirstTimeHintsService _hintsService;
  late SharedPreferences _prefs;
  bool _initialized = false;
  bool _showOnboarding = false;

  static const _hasSeenTutorialKey = 'has_seen_onboarding_tutorial';

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onPause: () {
        if (!_initialized) return;
        _adaptiveMusicService.pause();
        _progressService.flushSave();
      },
      onInactive: () {
        if (!_initialized) return;
        _adaptiveMusicService.pause();
        _progressService.flushSave();
      },
      onResume: () {
        if (!_initialized) return;
        _adaptiveMusicService.resume();
      },
    );
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
    _deepgramTtsService = DeepgramTtsService();
    _personalityService = AvatarPersonalityService();
    _adaptiveDifficultyService = AdaptiveDifficultyService();
    _adaptiveMusicService = AdaptiveMusicService();
    _hintsService = FirstTimeHintsService();

    // Get SharedPreferences once, share across all services
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    // Initialize all services in parallel for faster startup
    final initSw = Stopwatch()..start();
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
      _deepgramTtsService.init(prefs).catchError((e) {
        debugPrint('DeepgramTtsService init failed: $e');
      }),
      _personalityService.init().catchError((e) {
        debugPrint('AvatarPersonalityService init failed: $e');
      }),
      _adaptiveDifficultyService.init(prefs).catchError((e) {
        debugPrint('AdaptiveDifficultyService init failed: $e');
      }),
      _adaptiveMusicService.init().catchError((e) {
        debugPrint('AdaptiveMusicService init failed: $e');
      }),
      ShaderLoader.init().catchError((e) {
        debugPrint('ShaderLoader init failed: $e');
      }),
      _hintsService.init(prefs).catchError((e) {
        debugPrint('FirstTimeHintsService init failed: $e');
      }),
    ]);
    debugPrint('All services initialized in ${initSw.elapsedMilliseconds}ms');

    // Connect Deepgram TTS to AudioService for runtime phrase playback
    _audioService.setDeepgramTts(_deepgramTtsService);

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
    _adaptiveDifficultyService.switchProfile(profileId);
    _personalityService.switchProfile(profileId);
    _profileService.switchProfile(profileId);
    _audioService.setActiveProfile(profileId.isEmpty ? null : profileId);
  }

  void _onNameSubmitted(String name) async {
    await _settingsService.setPlayerName(name);
    // Show onboarding tutorial if this is the user's first time
    final hasSeenTutorial = _prefs.getBool(_hasSeenTutorialKey) ?? false;
    setState(() {
      _showOnboarding = !hasSeenTutorial;
    });
    // Generate personalized phrases in background (if Deepgram is configured)
    _generatePhrasesInBackground(name);
  }

  void _onOnboardingComplete() async {
    await _prefs.setBool(_hasSeenTutorialKey, true);
    setState(() => _showOnboarding = false);
  }

  void _onChangeName() {
    final nav = _navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => NameSetupScreen(
          onNameSubmitted: (name) async {
            final profileId = _settingsService.activeProfileId;
            if (profileId != null) {
              // Rename the active profile instead of creating a new one
              await _settingsService.renameProfile(profileId, name);
            } else {
              await _settingsService.setPlayerName(name);
            }
            setState(() {});
            _generatePhrasesInBackground(name);
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
    // Generate personalized phrases in background (if Deepgram is configured)
    _generatePhrasesInBackground(name);
  }

  /// Generate personalized TTS phrases for a player in the background.
  /// Runs silently — does not block the UI or show errors to the child.
  void _generatePhrasesInBackground(String name) {
    final profileId = _settingsService.activeProfileId;
    if (profileId == null || profileId.isEmpty) return;
    if (!_deepgramTtsService.isReady) return;
    if (!_deepgramTtsService.canGenerate(profileId)) return;

    debugPrint('Generating personalized phrases for "$name" (profile: $profileId)...');
    _deepgramTtsService
        .generatePhrasesForName(profileId: profileId, name: name)
        .then((result) {
      debugPrint('Phrase generation: ${result.generated} new, ${result.skipped} skipped, ${result.failed} failed');
    }).catchError((e) {
      debugPrint('Phrase generation error: $e');
    });
  }

  void _onSignOut() async {
    await _settingsService.signOut();
    setState(() {});
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _progressService.dispose();
    _audioService.dispose();
    _adaptiveMusicService.dispose();
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

    // Show onboarding tutorial after first name setup
    if (_showOnboarding) {
      return OnboardingTutorialScreen(
        onComplete: _onOnboardingComplete,
        audioService: _audioService,
      );
    }

    // Profiles exist but none is active → profile picker
    if (_settingsService.activeProfileId == null) {
      return ProfilePickerScreen(
        settingsService: _settingsService,
        audioService: _audioService,
        profileService: _profileService,
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
      personalityService: _personalityService,
      reviewService: _reviewService,
      adaptiveDifficultyService: _adaptiveDifficultyService,
      musicService: _adaptiveMusicService,
      settingsService: _settingsService,
      hintsService: _hintsService,
      playerName: _settingsService.playerName,
      profileId: _settingsService.activeProfileId ?? '',
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
            child: ExcludeSemantics(
              child: FloatingHeartsBackground(cloudZoneHeight: 0.18),
            ),
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
                  cacheWidth: 280,
                  cacheHeight: 280,
                ),
                const SizedBox(height: 24),
                Text(
                  'Reading Sprout',
                  style: AppFonts.fredoka(
                    fontSize: 32,
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // Bouncing dots loader
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.electricBlue,
                        ),
                      )
                          .animate(
                            onPlay: (c) => c.repeat(reverse: true),
                            delay: Duration(milliseconds: i * 150),
                          )
                          .scaleXY(
                            begin: 0.6,
                            end: 1.0,
                            duration: 400.ms,
                            curve: Curves.easeInOut,
                          )
                          .fadeIn(
                            begin: 0.4,
                            duration: 400.ms,
                          ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
