import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'services/kakao_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.init();
  await AppTheme.load();

  // 카카오 OAuth 콜백 감지 (웹에서 code 파라미터 확인)
  if (kIsWeb) {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    if (code != null) KakaoService.pendingCode = code;
  }

  runApp(const LoveApp());
}

class LoveApp extends StatelessWidget {
  const LoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 테마가 바뀌면 앱 전체(열려 있는 화면 포함)를 다시 그린다.
    return ValueListenableBuilder<AppPalette>(
      valueListenable: AppTheme.current,
      builder: (context, palette, _) {
        return MaterialApp(
          title: 'Love App',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: NotificationService.scaffoldKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: palette.primary,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: const LoginScreen(),
        );
      },
    );
  }
}
