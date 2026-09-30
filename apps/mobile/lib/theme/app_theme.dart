import 'package:flutter/material.dart';

/// Palet warna dari Figma (file Oc2uD5arZR2BK4lsJzLR5p).
class C {
  C._();

  /// Canonical Takt branding asset used by the in-app header.
  static const logoAsset = 'assets/branding/logo.jpg';

  static const bg = Color(0xFF2D3250); // background utama
  static const card = Color(0xFF424769); // card gelap
  static const cardAlt = Color(0xFF424669); // card kalender
  static const accent = Color(0xFFF9BC85); // oranye (aksen)
  static const accentText = Color(0xFF38385C); // teks di atas card oranye
  static const accentSub = Color(0xFF4E5076); // subteks di card oranye
  static const white = Color(0xFFFFFFFF);
  static const muted = Color(0xFFBBBBBB);
  static const muted2 = Color(0xFFC5C5C5);
  static const navInactive = Color(0xFF676F9D);
  static const dayHeader = Color(0xFF7F8499);
  static const detailMuted = Color(0xFFA8ADCC);

  // Heatmap intensity
  static const kosong = Color(0xFF37B464);
  static const ringan = Color(0xFF50A078);
  static const sedang = Color(0xFFE6B450);
  static const sibuk = Color(0xFFE67846);
  static const padat = Color(0xFFC84646);

  // Activity dots
  static const dotGreen = Color(0xFF4CD964);
  static const dotBlue = Color(0xFF5A96FF);
  static const dotPurple = Color(0xFFAF82FF);
  static const dotGray = Color(0xFF787D9B);
}

class AppTheme {
  static ThemeData get dark {
    final scheme = const ColorScheme.dark(
      primary: C.accent,
      secondary: C.accent,
      surface: C.card,
      error: C.padat,
    );
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: C.bg,
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: scheme,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          color: C.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleMedium: const TextStyle(
          color: C.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        bodyMedium: const TextStyle(
          color: C.white,
          fontSize: 14,
          height: 1.4,
        ),
        bodySmall: const TextStyle(
          color: C.detailMuted,
          fontSize: 12,
          height: 1.4,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: C.bg,
          backgroundColor: C.accent,
          disabledForegroundColor: C.detailMuted,
          disabledBackgroundColor: C.navInactive.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: C.accent,
          side: const BorderSide(color: C.accent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: C.accent,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: C.card,
        contentTextStyle: TextStyle(color: C.white),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: C.detailMuted),
        hintStyle: TextStyle(color: C.detailMuted),
      ),
    );
  }
}
