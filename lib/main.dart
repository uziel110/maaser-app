import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'store.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('he');
  final store = Store();
  await store.init();
  runApp(ChangeNotifierProvider.value(value: store, child: const MaaserApp()));
}

class MaaserApp extends StatelessWidget {
  const MaaserApp({super.key});
  @override
  Widget build(BuildContext context) {
    const bar = Color(0xFF1F4E5A);
    return MaterialApp(
      title: 'קופת מעשר',
      debugShowCheckedModeBanner: false,
      locale: const Locale('he'),
      supportedLocales: const [Locale('he')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: bar, primary: bar, secondary: const Color(0xFFF2B108)),
        scaffoldBackgroundColor: const Color(0xFFE9EEF0),
        appBarTheme: const AppBarTheme(backgroundColor: bar, foregroundColor: Colors.white),
      ),
      home: const HomeScreen(),
    );
  }
}
