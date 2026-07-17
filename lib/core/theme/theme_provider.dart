import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'profile_tab_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'isDarkMode';

  ThemeMode _mode = ThemeMode.light; // default: light

  ThemeProvider() {
    _loadSavedMode();
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> _loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIsDark = prefs.getBool(_prefsKey);
    if (savedIsDark == null) return;
    _mode = savedIsDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDark(bool isDark) async {
    _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, isDark);
  }

  void toggle() => setDark(!isDark);

  static ThemeData get lightTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B6CA8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFE2E8F0),
        fontFamily: GoogleFonts.inter().fontFamily,
        extensions: const [ProfileTabTokens.light],
      );

  static ThemeData get darkTheme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B6CA8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: kBg,
        cardColor: kCard,
        dividerColor: kBorder,
        fontFamily: GoogleFonts.inter().fontFamily,
        extensions: const [ProfileTabTokens.dark],
      );
}
