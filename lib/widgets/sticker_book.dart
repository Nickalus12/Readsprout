import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/sticker_definitions.dart';
import '../models/player_profile.dart';
import '../services/audio_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';

/// A kid-friendly sticker book with categorized sections, large tappable
/// sticker tiles, audio playback, and hint icons for unearned stickers.
class StickerBook extends StatefulWidget {
  final ProfileService profileService;
  final AudioService? audioService;

  const StickerBook({
    super.key,
    required this.profileService,
    this.audioService,
  });

  @override
  State<StickerBook> createState() => _StickerBookState();
}

class _StickerBookState extends State<StickerBook> {
  @override
  Widget build(BuildContext context) {
    final earnedStickers = widget.profileService.allStickers;
    final earnedIds = {for (final s in earnedStickers) s.stickerId};

    // Find most recent sticker for "NEW!" badge
    StickerRecord? mostRecent;
    for (final s in earnedStickers) {
      if (s.isNew) {
        if (mostRecent == null ||
            s.dateEarned.isAfter(mostRecent.dateEarned)) {
          mostRecent = s;
        }
      }
    }

    final totalEarned = earnedIds.length;
    final totalAvailable = StickerDefinitions.all.length;

    // Category sections
    final sections = <_CategorySection>[
      _CategorySection(
        title: 'Levels',
        icon: Icons.local_florist_rounded,
        color: const Color(0xFF7BD4A8),
        stickers: StickerDefinitions.levelStickers,
      ),
      const _CategorySection(
        title: 'Milestones',
        icon: Icons.emoji_events_rounded,
        color: Color(0xFFFFD700),
        stickers: StickerDefinitions.milestoneStickers,
      ),
      const _CategorySection(
        title: 'Streaks',
        icon: Icons.local_fire_department_rounded,
        color: Color(0xFFFF8C42),
        stickers: StickerDefinitions.streakStickers,
      ),
      const _CategorySection(
        title: 'Perfect',
        icon: Icons.verified_rounded,
        color: Color(0xFF00E68A),
        stickers: StickerDefinitions.perfectStickers,
      ),
      const _CategorySection(
        title: 'Evolution',
        icon: Icons.auto_awesome_rounded,
        color: Color(0xFF8B5CF6),
        stickers: StickerDefinitions.evolutionStickers,
      ),
      const _CategorySection(
        title: 'Special',
        icon: Icons.bolt_rounded,
        color: Color(0xFFFFBF69),
        stickers: StickerDefinitions.specialStickers,
      ),
      const _CategorySection(
        title: 'Mini Games',
        icon: Icons.sports_esports_rounded,
        color: Color(0xFF00D4FF),
        stickers: StickerDefinitions.miniGameStickers,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => widget.audioService?.playWord('stickers'),
                child: Text(
                  'Stickers',
                  style: GoogleFonts.fredoka(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.starGold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.starGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalEarned / $totalAvailable',
                  style: GoogleFonts.fredoka(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.starGold.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Category sections
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.border.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              for (int si = 0; si < sections.length; si++) ...[
                if (si > 0) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(
                      color: AppColors.border.withValues(alpha: 0.2),
                      height: 1,
                    ),
                  ),
                ],
                _buildCategorySection(
                  sections[si],
                  earnedIds,
                  earnedStickers,
                  mostRecent,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection(
    _CategorySection section,
    Set<String> earnedIds,
    List<StickerRecord> earnedStickers,
    StickerRecord? mostRecent,
  ) {
    final earnedInCategory =
        section.stickers.where((s) => earnedIds.contains(s.id)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Icon(section.icon, size: 18, color: section.color),
              const SizedBox(width: 6),
              Text(
                section.title,
                style: GoogleFonts.fredoka(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: section.color,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$earnedInCategory/${section.stickers.length}',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: AppColors.secondaryText.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),

        // Sticker grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final def in section.stickers)
              _StickerTile(
                definition: def,
                isEarned: earnedIds.contains(def.id),
                isNew: mostRecent?.stickerId == def.id,
                record: earnedIds.contains(def.id)
                    ? earnedStickers.firstWhere((s) => s.stickerId == def.id)
                    : null,
                profileService: widget.profileService,
                audioService: widget.audioService,
              ),
          ],
        ),
      ],
    );
  }
}

class _CategorySection {
  final String title;
  final IconData icon;
  final Color color;
  final List<StickerDefinition> stickers;

  const _CategorySection({
    required this.title,
    required this.icon,
    required this.color,
    required this.stickers,
  });
}

// ── Individual sticker tile ─────────────────────────────────────────────

class _StickerTile extends StatefulWidget {
  final StickerDefinition definition;
  final bool isEarned;
  final bool isNew;
  final StickerRecord? record;
  final ProfileService profileService;
  final AudioService? audioService;

  const _StickerTile({
    required this.definition,
    required this.isEarned,
    required this.isNew,
    this.record,
    required this.profileService,
    this.audioService,
  });

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!widget.isEarned) return;

    // Play audio
    widget.audioService?.playWord(widget.definition.audioKey);

    // Bounce animation
    _bounceController.forward(from: 0);

    // Mark as seen
    if (widget.record != null && widget.record!.isNew) {
      widget.profileService.markStickerSeen(widget.definition.id);
    }

    // Show details dialog
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => _StickerDetailsDialog(
        definition: widget.definition,
        record: widget.record!,
        audioService: widget.audioService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEarned = widget.isEarned;
    final color = widget.definition.color;

    return GestureDetector(
      onTap: _onTap,
      child: AnimatedBuilder(
        animation: _bounceController,
        builder: (context, child) {
          final t = _bounceController.value;
          final bounce = 1.0 + sin(t * pi) * 0.12;
          return Transform.scale(scale: bounce, child: child);
        },
        child: SizedBox(
          width: 64,
          height: 76,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Sticker body
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isEarned
                        ? color.withValues(alpha: 0.18)
                        : AppColors.surface.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isEarned
                          ? color.withValues(alpha: 0.55)
                          : AppColors.border.withValues(alpha: 0.15),
                      width: 2,
                    ),
                    boxShadow: isEarned
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    widget.definition.icon,
                    size: isEarned ? 26 : 20,
                    color: isEarned
                        ? color
                        : AppColors.secondaryText.withValues(alpha: 0.12),
                  ),
                ),
              ),

              // "NEW!" dot
              if (widget.isNew)
                Positioned(
                  top: 0,
                  right: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.surface,
                        width: 1.5,
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(begin: 0.8, end: 1.2, duration: 800.ms),
                ),

              // Hint question mark for unearned
              if (!isEarned)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      '?',
                      style: GoogleFonts.fredoka(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Details dialog ──────────────────────────────────────────────────────

class _StickerDetailsDialog extends StatelessWidget {
  final StickerDefinition definition;
  final StickerRecord record;
  final AudioService? audioService;

  const _StickerDetailsDialog({
    required this.definition,
    required this.record,
    this.audioService,
  });

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: definition.color.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: definition.color.withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sticker icon (large)
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: definition.color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: definition.color.withValues(alpha: 0.6),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: definition.color.withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  definition.icon,
                  size: 36,
                  color: definition.color,
                ),
              ),
              const SizedBox(height: 14),

              // Name + speaker icon
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      definition.name,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fredoka(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: definition.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () =>
                        audioService?.playWord(definition.audioKey),
                    child: Icon(
                      Icons.volume_up_rounded,
                      size: 22,
                      color: definition.color.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                definition.description,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),

              // Date earned
              Text(
                'Earned ${_formatDate(record.dateEarned)}',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: AppColors.secondaryText.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        )
            .animate()
            .fadeIn(duration: 200.ms)
            .scaleXY(
              begin: 0.8,
              end: 1.0,
              duration: 250.ms,
              curve: Curves.easeOutBack,
            ),
      ),
    );
  }
}
