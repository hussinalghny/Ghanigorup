import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'screens/startup.dart';
import 'state/app_state.dart';
import 'state/cart.dart';
import 'state/notifications.dart';
import 'state/session.dart';
import 'state/theme_state.dart';
import 'widgets/links.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final theme = ThemeState();
  await theme.load();
  SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay(C.dark));

  final api = ApiClient();
  await api.init();
  final cart = CartState();
  await cart.load();
  final session = SessionState(api)..restore();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<ThemeState>.value(value: theme),
        ChangeNotifierProvider(create: (_) => AppState(api)),
        ChangeNotifierProvider<SessionState>.value(value: session),
        ChangeNotifierProvider<CartState>.value(value: cart),
        ChangeNotifierProvider(create: (_) => NotificationsState(api, session), lazy: false),
      ],
      child: const GhaniApp(),
    ),
  );
}

class GhaniApp extends StatefulWidget {
  const GhaniApp({super.key});

  @override
  State<GhaniApp> createState() => _GhaniAppState();
}

/// تبديل الوضع الداكن/الفاتح بحركة دائرية: نلتقط صورة للشاشة الحالية، نطبّق الوضع الجديد،
/// ثم نكشف الوضع الجديد من مكان زر التبديل بدائرة تتوسع.
class _GhaniAppState extends State<GhaniApp> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  ui.Image? _snapshot;
  Offset _center = Offset.zero;
  late final ThemeState _theme = context.read<ThemeState>();

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onTheme);
  }

  @override
  void dispose() {
    _theme.removeListener(_onTheme);
    _reveal.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  void _onTheme() {
    final dark = _theme.isDark;
    if (dark == C.dark) return;
    // صورة للوضع الحالي قبل التبديل
    ui.Image? shot;
    try {
      final b = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (b != null && b.hasSize) {
        shot = b.toImageSync(pixelRatio: View.of(context).devicePixelRatio);
      }
    } catch (_) {
      shot = null;
    }
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    C.dark = dark;
    SystemChrome.setSystemUIOverlayStyle(AppTheme.overlay(dark));
    setState(() {
      _snapshot?.dispose();
      _snapshot = shot;
      _center = _theme.revealFrom ?? Offset(size.width / 2, size.height / 2);
    });
    // إعادة بناء كل الشاشات بالألوان الجديدة (الألوان تُقرأ وقت البناء)
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    if (shot != null) {
      _reveal.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _snapshot?.dispose();
          _snapshot = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeState>();
    final dark = C.dark;
    return MaterialApp(
      title: 'Ghani Group',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(false),
      darkTheme: AppTheme.build(true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: Duration.zero,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // منع تكبير الخط المبالغ فيه من كسر التصميم مع الحفاظ على إمكانية الوصول
        final mq = MediaQuery.of(context);
        final app = MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: child!,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.overlay(dark),
          child: Stack(
            children: [
              RepaintBoundary(key: _boundary, child: app),
              if (_snapshot != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _reveal,
                      builder: (_, __) {
                        final size = mq.size;
                        final maxR = _farthest(_center, size);
                        final t = Curves.easeInOutCubic.transform(_reveal.value);
                        return ClipPath(
                          clipper: _HoleClipper(_center, maxR * t),
                          child: RawImage(image: _snapshot, fit: BoxFit.fill, width: size.width, height: size.height),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      navigatorKey: appNavigator,
      home: const StartupGate(),
    );
  }

  static double _farthest(Offset c, Size s) {
    final xs = [c.dx, s.width - c.dx];
    final ys = [c.dy, s.height - c.dy];
    return math.sqrt(math.pow(xs.reduce(math.max), 2) + math.pow(ys.reduce(math.max), 2)) + 8;
  }
}

/// يقص الصورة القديمة بثقب دائري يتوسع فيظهر الوضع الجديد من تحته
class _HoleClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;
  _HoleClipper(this.center, this.radius);

  @override
  Path getClip(Size size) => Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      );

  @override
  bool shouldReclip(_HoleClipper old) => old.radius != radius || old.center != center;
}
