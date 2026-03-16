import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';

// ---------------------------------------------------------------------------
// Color Mix Lab — A paint mixing sandbox for kids
// ---------------------------------------------------------------------------
// Kids pick colors from a palette and drag/tap on a canvas to paint.
// When two color blobs overlap they blend into a new color.
// Includes a set of "discovery" challenges (mix red+blue = purple, etc.)
// and a free-paint mode where they can draw anything.
// ---------------------------------------------------------------------------

/// Cost in star coins for initial 3-minute session.
const int kColorMixLabCost = 5;

/// Cost in star coins for a 2-minute extension.
const int kColorMixExtensionCost = 3;

/// Initial session duration.
const Duration kColorMixSessionDuration = Duration(minutes: 3);

/// Extension duration.
const Duration kColorMixExtensionDuration = Duration(minutes: 2);

/// A color that has been "discovered" by mixing.
class _DiscoveredColor {
  final String name;
  final Color color;
  final Color parent1;
  final Color parent2;
  bool found = false;

  _DiscoveredColor({
    required this.name,
    required this.color,
    required this.parent1,
    required this.parent2,
  });
}

/// A paint stroke on the canvas.
class _PaintStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _PaintStroke({
    required this.points,
    required this.color,
    this.width = 24.0,
  });
}

/// A color blob for the mixing area.
class _ColorBlob {
  Offset position;
  Color color;
  double radius;
  _ColorBlob({
    required this.position,
    required this.color,
    this.radius = 40.0,
  });
}

/// Primary palette colors available to the child.
const List<Color> _paletteColors = [
  Color(0xFFFF0000), // Red
  Color(0xFF0000FF), // Blue
  Color(0xFFFFFF00), // Yellow
  Color(0xFFFFFFFF), // White
  Color(0xFF000000), // Black
];

const List<String> _paletteNames = [
  'red',
  'blue',
  'yellow',
  'white',
  'black',
];

/// Discoverable color mixes.
List<_DiscoveredColor> _buildDiscoveries() => [
      _DiscoveredColor(
        name: 'orange',
        color: const Color(0xFFFF8000),
        parent1: const Color(0xFFFF0000),
        parent2: const Color(0xFFFFFF00),
      ),
      _DiscoveredColor(
        name: 'purple',
        color: const Color(0xFF8000FF),
        parent1: const Color(0xFFFF0000),
        parent2: const Color(0xFF0000FF),
      ),
      _DiscoveredColor(
        name: 'green',
        color: const Color(0xFF00CC00),
        parent1: const Color(0xFF0000FF),
        parent2: const Color(0xFFFFFF00),
      ),
      _DiscoveredColor(
        name: 'pink',
        color: const Color(0xFFFF80C0),
        parent1: const Color(0xFFFF0000),
        parent2: const Color(0xFFFFFFFF),
      ),
      _DiscoveredColor(
        name: 'gray',
        color: const Color(0xFF808080),
        parent1: const Color(0xFFFFFFFF),
        parent2: const Color(0xFF000000),
      ),
    ];

class ColorMixLabGame extends StatefulWidget {
  final ProgressService progressService;
  final AudioService audioService;
  final String playerName;
  final bool freePlay;

  const ColorMixLabGame({
    super.key,
    required this.progressService,
    required this.audioService,
    required this.playerName,
    this.freePlay = false,
  });

  @override
  State<ColorMixLabGame> createState() => _ColorMixLabGameState();
}

class _ColorMixLabGameState extends State<ColorMixLabGame>
    with TickerProviderStateMixin {
  // -- Session timer ---------------------------------------------------------
  late int _remainingSeconds;
  Timer? _sessionTimer;
  bool _sessionExpired = false;
  bool _showTimeWarning = false;
  String _timeWarningText = '';

  // -- Mode ------------------------------------------------------------------
  // 0 = mixing lab, 1 = free paint
  int _mode = 0;

  // -- Mixing lab state ------------------------------------------------------
  final List<_ColorBlob> _blobs = [];
  int _selectedPaletteIndex = 0;
  late List<_DiscoveredColor> _discoveries;
  bool _showDiscovery = false;
  String _discoveryName = '';
  Color _discoveryColor = Colors.white;
  int _discoveryCount = 0;

  // -- Free paint state ------------------------------------------------------
  final List<_PaintStroke> _strokes = [];
  _PaintStroke? _currentStroke;
  Color _paintColor = const Color(0xFFFF0000);
  double _brushSize = 24.0;

  // -- Animation -------------------------------------------------------------
  late AnimationController _pulseController;
  late AnimationController _discoveryController;
  final Random _rng = Random();

  // -- Drag state for blobs --------------------------------------------------
  int? _draggingBlobIndex;

  // -- Mute ------------------------------------------------------------------
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _discoveries = _buildDiscoveries();
    _remainingSeconds = widget.freePlay
        ? const Duration(minutes: 999).inSeconds
        : kColorMixSessionDuration.inSeconds;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _discoveryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _startSessionTimer();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _pulseController.dispose();
    _discoveryController.dispose();
    super.dispose();
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sessionExpired) return;
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds == 60) {
          _showTimeWarning = true;
          _timeWarningText = '1 Minute Left!';
          _speakWord('one');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        } else if (_remainingSeconds == 30) {
          _showTimeWarning = true;
          _timeWarningText = '30 Seconds Left!';
          _speakWord('thirty');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _showTimeWarning = false);
          });
        }
        if (_remainingSeconds <= 0) {
          _remainingSeconds = 0;
          _sessionExpired = true;
          _speakWord('time');
        }
      });
    });
  }

  void _addMoreTime() {
    if (!widget.freePlay) {
      final balance = widget.progressService.starCoins;
      if (balance < kColorMixExtensionCost) return;
      widget.progressService.spendStarCoins(kColorMixExtensionCost);
    }
    setState(() {
      _remainingSeconds += widget.freePlay
          ? const Duration(minutes: 999).inSeconds
          : kColorMixExtensionDuration.inSeconds;
      _sessionExpired = false;
    });
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _timerColor() {
    if (_remainingSeconds > 60) return AppColors.emerald;
    if (_remainingSeconds > 30) return const Color(0xFFFFBB33);
    return AppColors.error;
  }

  Future<void> _speakWord(String word) async {
    if (_isMuted) return;
    await widget.audioService.playWord(word);
  }

  Future<void> _speakLabel(String text) async {
    if (_isMuted) return;
    final ok = await widget.audioService.playWord(text.toLowerCase());
    if (ok) return;
    for (final letter in text.toLowerCase().split('')) {
      if (!mounted || _isMuted) break;
      await widget.audioService.playLetter(letter);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  // -- Mixing lab interactions -----------------------------------------------

  void _addBlob(Offset position) {
    if (_sessionExpired) return;
    final color = _paletteColors[_selectedPaletteIndex];
    setState(() {
      _blobs.add(_ColorBlob(
        position: position,
        color: color,
        radius: 35.0 + _rng.nextDouble() * 15.0,
      ));
    });
    Haptics.tap();
    _speakLabel(_paletteNames[_selectedPaletteIndex]);
    _checkForMixes();
  }

  void _checkForMixes() {
    // Check all blob pairs for overlaps
    for (int i = 0; i < _blobs.length; i++) {
      for (int j = i + 1; j < _blobs.length; j++) {
        final a = _blobs[i];
        final b = _blobs[j];
        final dist = (a.position - b.position).distance;
        if (dist < (a.radius + b.radius) * 0.6) {
          _mergeBlobs(i, j);
          return; // Only merge one pair per check
        }
      }
    }
  }

  void _mergeBlobs(int i, int j) {
    final a = _blobs[i];
    final b = _blobs[j];

    // Blend colors using non-deprecated API
    final mixed = Color.fromARGB(
      255,
      (((a.color.r + b.color.r) / 2) * 255).round().clamp(0, 255),
      (((a.color.g + b.color.g) / 2) * 255).round().clamp(0, 255),
      (((a.color.b + b.color.b) / 2) * 255).round().clamp(0, 255),
    );

    // Merge into one bigger blob at midpoint
    final midpoint = Offset(
      (a.position.dx + b.position.dx) / 2,
      (a.position.dy + b.position.dy) / 2,
    );
    final newRadius = min(60.0, max(a.radius, b.radius) + 8.0);

    setState(() {
      // Remove both, add merged
      _blobs.removeAt(j);
      _blobs.removeAt(i);
      _blobs.add(_ColorBlob(
        position: midpoint,
        color: mixed,
        radius: newRadius,
      ));
    });

    Haptics.success();

    // Check if this is a discovery
    _checkDiscovery(mixed, a.color, b.color);
  }

  void _checkDiscovery(Color mixed, Color parent1, Color parent2) {
    for (final d in _discoveries) {
      if (d.found) continue;
      // Check if parents match (in either order)
      final match1 = _colorMatch(parent1, d.parent1) &&
          _colorMatch(parent2, d.parent2);
      final match2 = _colorMatch(parent1, d.parent2) &&
          _colorMatch(parent2, d.parent1);
      if (match1 || match2) {
        setState(() {
          d.found = true;
          _discoveryCount++;
          _showDiscovery = true;
          _discoveryName = d.name;
          _discoveryColor = d.color;
        });
        _discoveryController.forward(from: 0);
        _speakLabel(d.name);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showDiscovery = false);
        });
        return;
      }
    }
  }

  bool _colorMatch(Color a, Color b) {
    // Fuzzy match — within 0.12 per channel (float 0-1 range)
    return (a.r - b.r).abs() < 0.12 &&
        (a.g - b.g).abs() < 0.12 &&
        (a.b - b.b).abs() < 0.12;
  }

  void _clearCanvas() {
    setState(() {
      _blobs.clear();
      _strokes.clear();
      _currentStroke = null;
    });
    Haptics.tap();
  }

  // -- Free paint interactions -----------------------------------------------

  void _startPaintStroke(Offset position) {
    if (_sessionExpired) return;
    _currentStroke = _PaintStroke(
      points: [position],
      color: _paintColor,
      width: _brushSize,
    );
  }

  void _continuePaintStroke(Offset position) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke!.points.add(position);
    });
  }

  void _endPaintStroke() {
    if (_currentStroke == null) return;
    setState(() {
      _strokes.add(_currentStroke!);
      _currentStroke = null;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final compact = screenW < 400;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(compact),
                _buildModeSelector(compact),
                Expanded(
                  child: _mode == 0
                      ? _buildMixingLab(compact)
                      : _buildFreePaint(compact),
                ),
                if (_mode == 0) _buildPalette(compact),
                if (_mode == 1) _buildPaintPalette(compact),
              ],
            ),
            if (_showTimeWarning) _buildTimeWarning(compact),
            if (_showDiscovery) _buildDiscoveryOverlay(compact),
            if (_sessionExpired) _buildSessionExpiredOverlay(compact),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final isPulsing = _remainingSeconds <= 30 && !_sessionExpired;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryText,
            iconSize: compact ? 24 : 28,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _speakLabel('Color Mix Lab'),
              child: Text(
                'Color Mix Lab',
                textAlign: TextAlign.center,
                style: AppFonts.fredoka(
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),
          ),
          // Discovery counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.violet.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome,
                    color: AppColors.violet, size: compact ? 14 : 16),
                const SizedBox(width: 4),
                Text(
                  '$_discoveryCount/${_discoveries.length}',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.violet,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Timer
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final scale = isPulsing
                  ? 1.0 + _pulseController.value * 0.08
                  : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _timerColor().withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _formatTime(_remainingSeconds),
                style: AppFonts.fredoka(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: _timerColor(),
                ),
              ),
            ),
          ),
          // Mute
          IconButton(
            onPressed: () {
              setState(() => _isMuted = !_isMuted);
              Haptics.tap();
            },
            icon: Icon(
              _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _isMuted ? AppColors.secondaryText : AppColors.primaryText,
            ),
            iconSize: compact ? 20 : 24,
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(bool compact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildModeButton(0, 'Mix Colors', Icons.science_rounded, compact),
          const SizedBox(width: 8),
          _buildModeButton(1, 'Free Paint', Icons.brush_rounded, compact),
          const Spacer(),
          // Clear button
          GestureDetector(
            onTap: _clearCanvas,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: compact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_rounded,
                      color: AppColors.error, size: compact ? 14 : 16),
                  const SizedBox(width: 4),
                  Text(
                    'Clear',
                    style: AppFonts.fredoka(
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
      int mode, String label, IconData icon, bool compact) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        Haptics.tap();
        _speakLabel(label);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.electricBlue.withValues(alpha: 0.2)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.electricBlue.withValues(alpha: 0.6)
                : AppColors.border.withValues(alpha: 0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.electricBlue
                    : AppColors.secondaryText,
                size: compact ? 14 : 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppFonts.fredoka(
                fontSize: compact ? 11 : 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? AppColors.electricBlue
                    : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mixing Lab ─────────────────────────────────────────────────────────

  Widget _buildMixingLab(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            // Check if tapping on existing blob
            final tapPos = details.localPosition;
            for (int i = _blobs.length - 1; i >= 0; i--) {
              final dist = (_blobs[i].position - tapPos).distance;
              if (dist < _blobs[i].radius) {
                return; // Will handle in pan
              }
            }
            _addBlob(tapPos);
          },
          onPanStart: (details) {
            final tapPos = details.localPosition;
            for (int i = _blobs.length - 1; i >= 0; i--) {
              final dist = (_blobs[i].position - tapPos).distance;
              if (dist < _blobs[i].radius) {
                _draggingBlobIndex = i;
                return;
              }
            }
            _draggingBlobIndex = null;
          },
          onPanUpdate: (details) {
            if (_draggingBlobIndex != null && _draggingBlobIndex! < _blobs.length) {
              setState(() {
                _blobs[_draggingBlobIndex!].position = details.localPosition;
              });
            }
          },
          onPanEnd: (_) {
            if (_draggingBlobIndex != null) {
              _checkForMixes();
              _draggingBlobIndex = null;
            }
          },
          child: CustomPaint(
            painter: _MixingLabPainter(
              blobs: _blobs,
              pulseValue: _pulseController.value,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }

  Widget _buildPalette(bool compact) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tap a color, then tap the canvas!',
            style: AppFonts.fredoka(
              fontSize: compact ? 11 : 13,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_paletteColors.length, (i) {
              final selected = _selectedPaletteIndex == i;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedPaletteIndex = i);
                  Haptics.tap();
                  _speakLabel(_paletteNames[i]);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: selected ? (compact ? 48 : 56) : (compact ? 40 : 48),
                  height: selected ? (compact ? 48 : 56) : (compact ? 40 : 48),
                  decoration: BoxDecoration(
                    color: _paletteColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.electricBlue
                          : Colors.white.withValues(alpha: 0.3),
                      width: selected ? 3 : 2,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: _paletteColors[i].withValues(alpha: 0.5),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          // Discovery hints row
          _buildDiscoveryHints(compact),
        ],
      ),
    );
  }

  Widget _buildDiscoveryHints(bool compact) {
    return SizedBox(
      height: compact ? 28 : 32,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _discoveries.length,
        itemBuilder: (context, i) {
          final d = _discoveries[i];
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: d.found
                  ? d.color.withValues(alpha: 0.3)
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: d.found
                    ? d.color.withValues(alpha: 0.6)
                    : AppColors.border.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.found)
                  Icon(Icons.check_circle_rounded,
                      color: d.color, size: compact ? 12 : 14)
                else
                  Icon(Icons.help_outline_rounded,
                      color: AppColors.secondaryText, size: compact ? 12 : 14),
                const SizedBox(width: 4),
                Text(
                  d.found ? d.name : '???',
                  style: AppFonts.fredoka(
                    fontSize: compact ? 10 : 12,
                    fontWeight: d.found ? FontWeight.w600 : FontWeight.w400,
                    color: d.found ? d.color : AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Free Paint ─────────────────────────────────────────────────────────

  Widget _buildFreePaint(bool compact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (details) =>
              _startPaintStroke(details.localPosition),
          onPanUpdate: (details) =>
              _continuePaintStroke(details.localPosition),
          onPanEnd: (_) => _endPaintStroke(),
          onTapDown: (details) {
            _startPaintStroke(details.localPosition);
            // Add a dot
            setState(() {
              _currentStroke?.points.add(details.localPosition);
            });
            _endPaintStroke();
          },
          child: CustomPaint(
            painter: _FreePaintPainter(
              strokes: _strokes,
              currentStroke: _currentStroke,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }

  Widget _buildPaintPalette(bool compact) {
    // Extended palette with mixed colors
    final allColors = [
      ..._paletteColors,
      const Color(0xFFFF8000), // Orange
      const Color(0xFF8000FF), // Purple
      const Color(0xFF00CC00), // Green
      const Color(0xFFFF80C0), // Pink
      const Color(0xFF808080), // Gray
    ];
    final allNames = [
      ..._paletteNames,
      'orange',
      'purple',
      'green',
      'pink',
      'gray',
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color row
          SizedBox(
            height: compact ? 40 : 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allColors.length,
              itemBuilder: (context, i) {
                final selected = _paintColor == allColors[i];
                return GestureDetector(
                  onTap: () {
                    setState(() => _paintColor = allColors[i]);
                    Haptics.tap();
                    _speakLabel(allNames[i]);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected
                        ? (compact ? 40 : 48)
                        : (compact ? 32 : 38),
                    height: selected
                        ? (compact ? 40 : 48)
                        : (compact ? 32 : 38),
                    decoration: BoxDecoration(
                      color: allColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.electricBlue
                            : Colors.white.withValues(alpha: 0.3),
                        width: selected ? 3 : 1.5,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: allColors[i].withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : [],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Brush size slider
          Row(
            children: [
              const Icon(Icons.circle,
                  size: 8, color: AppColors.secondaryText),
              Expanded(
                child: Slider(
                  value: _brushSize,
                  min: 4.0,
                  max: 48.0,
                  activeColor: _paintColor,
                  inactiveColor: AppColors.border,
                  onChanged: (v) => setState(() => _brushSize = v),
                ),
              ),
              const Icon(Icons.circle,
                  size: 24, color: AppColors.secondaryText),
            ],
          ),
        ],
      ),
    );
  }

  // ── Overlays ────────────────────────────────────────────────────────────

  Widget _buildTimeWarning(bool compact) {
    return Positioned(
      top: compact ? 60 : 80,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 24,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.starGold.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Text(
            _timeWarningText,
            style: AppFonts.fredoka(
              fontSize: compact ? 16 : 20,
              fontWeight: FontWeight.w700,
              color: AppColors.starGold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscoveryOverlay(bool compact) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _discoveryController,
            builder: (context, child) {
              final scale = Curves.elasticOut
                  .transform(_discoveryController.value.clamp(0.0, 1.0));
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              padding: EdgeInsets.all(compact ? 20 : 28),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _discoveryColor.withValues(alpha: 0.6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _discoveryColor.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome,
                      color: _discoveryColor, size: compact ? 40 : 56),
                  SizedBox(height: compact ? 8 : 12),
                  Text(
                    'You made ${_discoveryName.toUpperCase()}!',
                    style: AppFonts.fredoka(
                      fontSize: compact ? 22 : 28,
                      fontWeight: FontWeight.w700,
                      color: _discoveryColor,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 8),
                  Container(
                    width: compact ? 50 : 70,
                    height: compact ? 50 : 70,
                    decoration: BoxDecoration(
                      color: _discoveryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _discoveryColor.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSessionExpiredOverlay(bool compact) {
    final canAfford =
        widget.progressService.starCoins >= kColorMixExtensionCost;
    final hMargin = compact ? 16.0 : 32.0;
    final pad = compact ? 16.0 : 24.0;

    return Positioned.fill(
      child: Container(
        color: AppColors.background.withValues(alpha: 0.9),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: hMargin),
            padding: EdgeInsets.all(pad),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.electricBlue.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.electricBlue.withValues(alpha: 0.1),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off_rounded,
                  color: AppColors.starGold,
                  size: compact ? 36 : 48,
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  "Time's Up!",
                  style: AppFonts.fredoka(
                    fontSize: compact ? 22 : 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Text(
                  'You discovered $_discoveryCount of ${_discoveries.length} colors!',
                  textAlign: TextAlign.center,
                  style: AppFonts.fredoka(
                    fontSize: compact ? 12 : 14,
                    color: AppColors.secondaryText,
                  ),
                ),
                SizedBox(height: compact ? 14 : 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canAfford ? _addMoreTime : null,
                    icon: Icon(Icons.add_rounded, size: compact ? 16 : 20),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add 2 Min  ',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 13 : 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.star_rounded,
                            color: AppColors.starGold,
                            size: compact ? 14 : 16),
                        Text(
                          ' $kColorMixExtensionCost',
                          style: AppFonts.fredoka(
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.starGold,
                          ),
                        ),
                      ],
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAfford
                          ? AppColors.electricBlue
                          : AppColors.surfaceVariant,
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (!canAfford) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Complete words in Adventure Mode\nto earn more Star Coins!',
                    textAlign: TextAlign.center,
                    style: AppFonts.fredoka(
                      fontSize: compact ? 10 : 12,
                      color: AppColors.starGold.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 8 : 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryText,
                      side: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5),
                      ),
                      padding:
                          EdgeInsets.symmetric(vertical: compact ? 8 : 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'Done',
                      style: AppFonts.fredoka(
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Custom Painters ─────────────────────────────────────────────────────────

/// Painter for the mixing lab canvas — draws color blobs with glow effects.
class _MixingLabPainter extends CustomPainter {
  final List<_ColorBlob> blobs;
  final double pulseValue;

  _MixingLabPainter({required this.blobs, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Background — dark with subtle grid
    final bgPaint = Paint()..color = const Color(0xFF0D0D20);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Subtle grid dots
    final gridPaint = Paint()
      ..color = const Color(0xFF1A1A35)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 30) {
      for (double y = 0; y < size.height; y += 30) {
        canvas.drawCircle(Offset(x, y), 1, gridPaint);
      }
    }

    // Draw blobs with glow
    for (final blob in blobs) {
      // Outer glow
      final glowPaint = Paint()
        ..color = blob.color.withValues(alpha: 0.15 + pulseValue * 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(blob.position, blob.radius + 10, glowPaint);

      // Main blob
      final blobPaint = Paint()
        ..shader = ui.Gradient.radial(
          blob.position - Offset(blob.radius * 0.3, blob.radius * 0.3),
          blob.radius * 1.2,
          [
            Color.lerp(blob.color, Colors.white, 0.3)!,
            blob.color,
            Color.lerp(blob.color, Colors.black, 0.2)!,
          ],
          [0.0, 0.5, 1.0],
        );
      canvas.drawCircle(blob.position, blob.radius, blobPaint);

      // Specular highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        blob.position - Offset(blob.radius * 0.25, blob.radius * 0.25),
        blob.radius * 0.25,
        highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MixingLabPainter oldDelegate) => true;
}

/// Painter for free paint mode — draws smooth brush strokes.
class _FreePaintPainter extends CustomPainter {
  final List<_PaintStroke> strokes;
  final _PaintStroke? currentStroke;

  _FreePaintPainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    // White canvas background
    final bgPaint = Paint()..color = const Color(0xFF0D0D20);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Draw all strokes
    final allStrokes = [...strokes, if (currentStroke != null) currentStroke!];
    for (final stroke in allStrokes) {
      if (stroke.points.length < 2) {
        // Single point — draw a dot
        if (stroke.points.isNotEmpty) {
          final dotPaint = Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill;
          canvas.drawCircle(stroke.points[0], stroke.width / 2, dotPaint);
        }
        continue;
      }

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(stroke.points[0].dx, stroke.points[0].dy);

      for (int i = 1; i < stroke.points.length; i++) {
        final p0 = stroke.points[i - 1];
        final p1 = stroke.points[i];
        // Smooth line with midpoints
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
      path.lineTo(
        stroke.points.last.dx,
        stroke.points.last.dy,
      );

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FreePaintPainter oldDelegate) => true;
}

// ── Icon Painter for Mini Games Hub ─────────────────────────────────────────

/// A palette/paint icon for the Color Mix Lab game button.
class ColorMixLabIconPainter extends CustomPainter {
  const ColorMixLabIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.32;

    // Paint palette shape (oval)
    final palettePath = Path();
    palettePath.addOval(Rect.fromCenter(
      center: Offset(cx, cy),
      width: r * 2.2,
      height: r * 1.8,
    ));
    // Thumb hole
    palettePath.addOval(Rect.fromCenter(
      center: Offset(cx + r * 0.7, cy + r * 0.3),
      width: r * 0.5,
      height: r * 0.45,
    ));
    palettePath.fillType = PathFillType.evenOdd;

    final palettePaint = Paint()
      ..color = const Color(0xFF8B6914)
      ..style = PaintingStyle.fill;
    canvas.drawPath(palettePath, palettePaint);

    // Color dots on palette
    final colors = [
      const Color(0xFFFF0000),
      const Color(0xFF0000FF),
      const Color(0xFFFFFF00),
      const Color(0xFF00CC00),
      const Color(0xFFFF8000),
    ];
    final positions = [
      Offset(cx - r * 0.6, cy - r * 0.3),
      Offset(cx - r * 0.2, cy - r * 0.5),
      Offset(cx + r * 0.3, cy - r * 0.35),
      Offset(cx - r * 0.5, cy + r * 0.2),
      Offset(cx, cy + r * 0.1),
    ];

    for (int i = 0; i < colors.length; i++) {
      final dotPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.fill;
      canvas.drawCircle(positions[i], r * 0.18, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ColorMixLabIconPainter oldDelegate) => false;
}
