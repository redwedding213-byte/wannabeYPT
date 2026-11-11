import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'ca_setup.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

// YPT 브랜드 컬러
const kBrand = Color(0xFFE8552D); // 주황빨강
const kBg = Color(0xFF0D0D0F);
const kCard = Color(0xFF18181B);
const kCard2 = Color(0xFF222227);

// White mode surfaces (Tara51 + AL.. asked for a light theme).
// Light keeps the same orange accent; only surfaces/text flip.
const kBgLight = Color(0xFFF4F4F2);
const kCardLight = Colors.white;
const kCard2Light = Color(0xFFE9E9E6);

/// Theme-aware card surfaces, read from the active ThemeData so
/// dark and light stay consistent. Dark keeps the classic YPT blacks.
Color yptCardColor(BuildContext context) =>
    Theme.of(context).cardTheme.color ?? kCard;
Color yptCard2Color(BuildContext context) =>
    Theme.of(context).inputDecorationTheme.fillColor ?? kCard2;

/// Theme-aware greys. The screens were written for the dark theme, where
/// light greys read fine on black; on the light theme the same values wash
/// out (grey[300] on #F4F4F2 is nearly invisible), so light mode uses the
/// darker Material steps. Dark values are unchanged, so the dark theme is
/// pixel-identical. Light secondary text lands on grey[700] (#616161,
/// ~5.9:1 on the light background) and strong text on grey[800] (~9:1).
Color yptGrey100(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[100]!
    : Colors.grey[800]!;
Color yptGrey200(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[200]!
    : Colors.grey[700]!;
Color yptGrey300(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[300]!
    : Colors.grey[700]!;
Color yptGrey400(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[400]!
    : Colors.grey[700]!;
Color yptGrey500(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[500]!
    : Colors.grey[700]!;
Color yptGrey600(BuildContext context) => Theme.of(context).brightness ==
        Brightness.dark
    ? Colors.grey[600]!
    : Colors.grey[700]!;

/// Theme-aware hairline/divider colours. Dark mode uses white at low alpha;
/// light mode uses black at low alpha (white hairlines vanish on light).
Color yptHairline(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0x0DFFFFFF)
        : Colors.black.withValues(alpha: 0.10);
Color yptDivider(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0x14FFFFFF)
        : Colors.black.withValues(alpha: 0.14);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupCaCerts(); // Windows TLS 루트 보완 (웹/기타 플랫폼은 no-op)
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..tryAutoLogin(),
      child: const YptApp(),
    ),
  );
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? kBg : kBgLight;
  final card = isDark ? kCard : kCardLight;
  final card2 = isDark ? kCard2 : kCard2Light;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrand,
    brightness: brightness,
  ).copyWith(surface: bg);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: kBrand.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBrand, width: 1.5),
      ),
    ),
  );
}

class YptApp extends StatelessWidget {
  const YptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, st, __) => MaterialApp(
        title: 'YPT',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: st.lightTheme ? ThemeMode.light : ThemeMode.dark,
        home: st.loggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
