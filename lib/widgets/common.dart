import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/theme.dart';
import '../models/route_models.dart';
import '../models/stage.dart';
import '../models/trip.dart';

/// One-line snackbar — replaces the private _toast() helpers that
/// existed in several screens.
void nkToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Small icon + muted text used for metadata on cards (distance,
/// ascent, dates…). Replaces the duplicated _chip/_meta helpers.
Widget metaChip(IconData icon, String text, {Color? color}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color ?? NkColors.textSecondary),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(fontSize: 12, color: color ?? NkColors.textSecondary),
      ),
    ],
  );
}

/// Route polylines styled by honesty: solid forest green = verified
/// trail section, dashed amber = estimated straight-line stretch.
/// Shared by the planner map and the hiking-mode map so both tell
/// the same visual story.
List<Polyline> routePolylines(HikingRoute route) {
  return [
    for (final s in route.polylineSegments())
      Polyline(
        points: s.points,
        strokeWidth: 4,
        color: s.straight ? NkColors.warningAmber : NkColors.forestGreen,
        borderStrokeWidth: 6,
        borderColor: Colors.white.withValues(alpha: 0.6),
        pattern: s.straight
            ? StrokePattern.dashed(segments: const [12, 8])
            : const StrokePattern.solid(),
      ),
  ];
}

/// AppBar title that shows the screen name with the current trip name
/// underneath — so it's always clear which trip a screen operates on.
Widget tripScreenTitle(String screen, Trip? trip) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(screen, style: const TextStyle(fontSize: 17)),
      if (trip != null)
        // Follows the app bar's text colour so the subtitle stays readable
        // on the dark blue bar.
        Builder(
          builder: (context) => Text(
            trip.name.isEmpty ? 'Tur uten navn' : trip.name,
            style: TextStyle(
              fontSize: 12,
              color: (DefaultTextStyle.of(context).style.color ?? Colors.white)
                  .withValues(alpha: 0.85),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
  );
}

/// The official MET/Yr weather icon for a Locationforecast symbol
/// code (e.g. "partlycloudy_day"). Icons are bundled locally from
/// metno/weathericons (MIT) — see assets/weathericons/LICENSE.
class MetSymbolIcon extends StatelessWidget {
  final String? code;
  final double size;
  const MetSymbolIcon(this.code, {super.key, this.size = 24});

  /// Filenames bundled under assets/weathericons (without .png).
  static const _known = {
    'clearsky_day',
    'clearsky_night',
    'clearsky_polartwilight',
    'cloudy',
    'fair_day',
    'fair_night',
    'fair_polartwilight',
    'fog',
    'heavyrain',
    'heavyrainandthunder',
    'heavyrainshowers_day',
    'heavyrainshowers_night',
    'heavyrainshowers_polartwilight',
    'heavyrainshowersandthunder_day',
    'heavyrainshowersandthunder_night',
    'heavyrainshowersandthunder_polartwilight',
    'heavysleet',
    'heavysleetandthunder',
    'heavysleetshowers_day',
    'heavysleetshowers_night',
    'heavysleetshowers_polartwilight',
    'heavysleetshowersandthunder_day',
    'heavysleetshowersandthunder_night',
    'heavysleetshowersandthunder_polartwilight',
    'heavysnow',
    'heavysnowandthunder',
    'heavysnowshowers_day',
    'heavysnowshowers_night',
    'heavysnowshowers_polartwilight',
    'heavysnowshowersandthunder_day',
    'heavysnowshowersandthunder_night',
    'heavysnowshowersandthunder_polartwilight',
    'lightrain',
    'lightrainandthunder',
    'lightrainshowers_day',
    'lightrainshowers_night',
    'lightrainshowers_polartwilight',
    'lightrainshowersandthunder_day',
    'lightrainshowersandthunder_night',
    'lightrainshowersandthunder_polartwilight',
    'lightsleet',
    'lightsleetandthunder',
    'lightsleetshowers_day',
    'lightsleetshowers_night',
    'lightsleetshowers_polartwilight',
    'lightsnow',
    'lightsnowandthunder',
    'lightsnowshowers_day',
    'lightsnowshowers_night',
    'lightsnowshowers_polartwilight',
    'lightssleetshowersandthunder_day',
    'lightssleetshowersandthunder_night',
    'lightssleetshowersandthunder_polartwilight',
    'lightssnowshowersandthunder_day',
    'lightssnowshowersandthunder_night',
    'lightssnowshowersandthunder_polartwilight',
    'partlycloudy_day',
    'partlycloudy_night',
    'partlycloudy_polartwilight',
    'rain',
    'rainandthunder',
    'rainshowers_day',
    'rainshowers_night',
    'rainshowers_polartwilight',
    'rainshowersandthunder_day',
    'rainshowersandthunder_night',
    'rainshowersandthunder_polartwilight',
    'sleet',
    'sleetandthunder',
    'sleetshowers_day',
    'sleetshowers_night',
    'sleetshowers_polartwilight',
    'sleetshowersandthunder_day',
    'sleetshowersandthunder_night',
    'sleetshowersandthunder_polartwilight',
    'snow',
    'snowandthunder',
    'snowshowers_day',
    'snowshowers_night',
    'snowshowers_polartwilight',
    'snowshowersandthunder_day',
    'snowshowersandthunder_night',
    'snowshowersandthunder_polartwilight',
  };

  static String? _resolve(String code) {
    if (_known.contains(code)) return code;
    final base = code.replaceAll(RegExp(r'_(day|night|polartwilight)$'), '');
    if (_known.contains(base)) return base;
    final day = '${base}_day';
    if (_known.contains(day)) return day;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = code == null ? null : _resolve(code!);
    if (resolved == null) {
      return Icon(
        Icons.cloud_outlined,
        size: size,
        color: NkColors.textSecondary,
      );
    }
    return Image.asset(
      'assets/weathericons/$resolved.png',
      width: size,
      height: size,
    );
  }
}

/// White rounded card matching the NorgesKompasset visual language.
class NkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  const NkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? NkColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NkColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final IconData? icon;

  const SectionHeader(this.title, {super.key, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: NkColors.primaryBlue),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: NkColors.textPrimary,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Small label:value tile used inside summary cards.
class InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;

  const InfoTile(
    this.label,
    this.value, {
    super.key,
    this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ?icon != null
                ? Icon(icon, size: 14, color: NkColors.textSecondary)
                : null,
            if (icon != null) const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: NkColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: valueColor ?? NkColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Colored status pill (difficulty, warnings, route source).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill(this.label, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    // Bright accent hues (amber, orange) are unreadable as 11 px
    // text on the tinted chip — darken them for light mode while
    // keeping the hue. Dark mode keeps the bright variant.
    final fg = NkColors.dark
        ? color
        : HSLColor.fromColor(color)
              .withLightness(
                (HSLColor.fromColor(color).lightness * 0.55).clamp(0.0, 0.42),
              )
              .toColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

Color difficultyColor(DifficultyLevel level) => switch (level) {
  DifficultyLevel.easy => NkColors.easyGreen,
  DifficultyLevel.moderate => NkColors.moderateAmber,
  DifficultyLevel.challenging => NkColors.challengingOrange,
  DifficultyLevel.demanding => NkColors.demandingRed,
};

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: NkColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: NkColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: NkColors.textSecondary,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Subtle mountain silhouette used as a scenic header fallback
/// (no network dependency).
class MountainHeader extends StatelessWidget {
  final double height;
  final Widget? child;

  const MountainHeader({super.key, this.height = 160, this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _MountainPainter(), child: child),
    );
  }
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF174A78), Color(0xFF2E6DA0)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    final back = Paint()..color = const Color(0xFF1D5A8C);
    final backPath = Path()
      ..moveTo(0, size.height * 0.75)
      ..lineTo(size.width * 0.18, size.height * 0.45)
      ..lineTo(size.width * 0.38, size.height * 0.72)
      ..lineTo(size.width * 0.58, size.height * 0.38)
      ..lineTo(size.width * 0.8, size.height * 0.7)
      ..lineTo(size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(backPath, back);

    final front = Paint()..color = const Color(0xFF10385D);
    final frontPath = Path()
      ..moveTo(0, size.height * 0.9)
      ..lineTo(size.width * 0.25, size.height * 0.58)
      ..lineTo(size.width * 0.5, size.height * 0.88)
      ..lineTo(size.width * 0.72, size.height * 0.6)
      ..lineTo(size.width, size.height * 0.85)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(frontPath, front);

    final snow = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final snowPath = Path()
      ..moveTo(size.width * 0.58, size.height * 0.38)
      ..lineTo(size.width * 0.62, size.height * 0.46)
      ..lineTo(size.width * 0.58, size.height * 0.5)
      ..lineTo(size.width * 0.54, size.height * 0.46)
      ..close();
    canvas.drawPath(snowPath, snow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Scenic mountain photos used in designated areas — Wikimedia
/// Commons (free licenses) plus photos from norgeskompasset.no
/// (hosted on static.wixstatic.com). Falls back to the painted
/// silhouette when offline or an image fails to load — the app
/// never blocks on a photo.
class NkImages {
  NkImages._();
  static const besseggenPano =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/7/71/Bessegen_pano.jpg/1920px-Bessegen_pano.jpg';
  static const hardangerviddaTent =
      'https://upload.wikimedia.org/wikipedia/commons/a/a7/Hiking_tent_Hardangervidda_Norway_%2860.015%2C_6.718%29.JPG';
  static const lofoten =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d0/Sakris%C3%B8y_village_and_mountains_Lofoten_Norway.jpg/1920px-Sakris%C3%B8y_village_and_mountains_Lofoten_Norway.jpg';
  static const besseggenRidge =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/56/Besseggen_ridge.jpg/1920px-Besseggen_ridge.jpg';
  static const jotunheimen =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Jotunheimen_mountains.jpg/1920px-Jotunheimen_mountains.jpg';
  static const primusStove =
      'https://upload.wikimedia.org/wikipedia/commons/thumb/5/55/Primus_stove.jpg/1280px-Primus_stove.jpg';

  // Photos from norgeskompasset.no (Wix media CDN)
  static const nkGroup =
      'https://static.wixstatic.com/media/11062b_d1fb906ee9294c0fbfa7b88a618de5ef~mv2.jpg/v1/fill/w_1200,h_675,al_c,q_85,enc_auto/11062b_d1fb906ee9294c0fbfa7b88a618de5ef~mv2.jpg';
  static const nkTrail =
      'https://static.wixstatic.com/media/9ad4b9_8f85f17149594486830eb1c31699ac09~mv2.jpg/v1/fill/w_1200,h_899,al_c,q_85,enc_auto/9ad4b9_8f85f17149594486830eb1c31699ac09~mv2.jpg';
  static const nkPortrait1 =
      'https://static.wixstatic.com/media/9ad4b9_e74bbe8f738545bfa6f2d43b1ed8635f~mv2.jpg/v1/fill/w_900,h_1954,al_c,q_85,enc_auto/9ad4b9_e74bbe8f738545bfa6f2d43b1ed8635f~mv2.jpg';
  static const nkPortrait2 =
      'https://static.wixstatic.com/media/74bdf3_47ff440e5fda40d6b8effab00d6d7ad4~mv2.jpeg/v1/fill/w_900,h_1198,al_c,q_85,enc_auto/74bdf3_47ff440e5fda40d6b8effab00d6d7ad4~mv2.jpeg';
}

/// Photo header/banner with dark gradient overlay and offline fallback.
class ScenicImage extends StatelessWidget {
  final String url;
  final double height;
  final Widget? child;
  final double overlayOpacity;

  const ScenicImage({
    super.key,
    required this.url,
    required this.height,
    this.child,
    this.overlayOpacity = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: 1600,
              // Disk-cached — instant on revisit and works offline
              // after first load.
              placeholder: (ctx, _) => MountainHeader(height: height),
              errorWidget: (ctx, _, _) => MountainHeader(height: height),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: overlayOpacity),
                  ],
                ),
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}

/// Standard screen banner — scenic photo, bottom-left title with
/// optional subtitle, rounded corners. Keeps every detail screen
/// visually consistent.
class ScreenBanner extends StatelessWidget {
  final String url;
  final String title;
  final String? subtitle;
  final double height;

  const ScreenBanner({
    super.key,
    required this.url,
    required this.title,
    this.subtitle,
    this.height = 110,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ScenicImage(
        url: url,
        height: height,
        overlayOpacity: 0.45,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
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

/// Compact horizontal progress bar.
class NkProgress extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;

  const NkProgress(
    this.value, {
    super.key,
    this.color = NkColors.forestGreen,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: NkColors.border,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}
