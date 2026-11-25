import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/benchmark/presentation/benchmark_lab_screen.dart';
import '../features/camera/presentation/live_monitor_screen.dart';
import '../features/gate/presentation/gate_mode_screen.dart';
import '../features/models/presentation/model_import_screen.dart';
import '../features/models/presentation/model_library_screen.dart';
import '../features/safety/presentation/safety_profiles_screen.dart';
import '../features/settings/presentation/settings_privacy_screen.dart';
import '../features/statistics/presentation/statistics_dashboard_screen.dart';
import 'app_state.dart';
import 'theme.dart';

class SafeZoneMobileApp extends StatefulWidget {
  final AppState appState;

  const SafeZoneMobileApp({super.key, required this.appState});

  @override
  State<SafeZoneMobileApp> createState() => _SafeZoneMobileAppState();
}

class _SafeZoneMobileAppState extends State<SafeZoneMobileApp>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.appState.handleAppLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.appState,
      builder: (context, _) {
        final screens = <Widget>[
          LiveMonitorScreen(appState: widget.appState),
          ModelLibraryScreen(appState: widget.appState),
          ModelImportScreen(appState: widget.appState),
          SafetyProfilesScreen(appState: widget.appState),
          BenchmarkLabScreen(appState: widget.appState),
          GateModeScreen(appState: widget.appState),
          StatisticsDashboardScreen(appState: widget.appState),
          SettingsPrivacyScreen(appState: widget.appState),
        ];

        return MaterialApp(
          title: 'SafeZone AI Mobile',
          debugShowCheckedModeBanner: false,
          theme: SafeZoneTheme.darkRtlTheme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            // Apply system text scale factor constraints (1.0 – 1.3 max)
            final mq = MediaQuery.of(context);
            final clampedMq = mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.3,
              ),
            );
            return Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: clampedMq,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B342C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF6C9C63)),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Color(0xFFB8F66A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SafeZone AI',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: 0.3,
                            color: Color(0xFFEBF2FC),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'نظام المراقبة الذكية',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                            color: Color(0xFF96ADC7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            body: SafeArea(
              bottom: false,
              child: screens[_selectedIndex],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) =>
                  setState(() => _selectedIndex = idx),
              backgroundColor: const Color(0xFF0B1524),
              indicatorColor: const Color(0xFF1B342C),
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              height: 64,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.videocam_outlined),
                  label: 'الرئيسية',
                ),
                NavigationDestination(
                  icon: Icon(Icons.layers_outlined),
                  label: 'النماذج',
                ),
                NavigationDestination(
                  icon: Icon(Icons.file_upload_outlined),
                  label: 'استيراد',
                ),
                NavigationDestination(
                  icon: Icon(Icons.rule_folder_outlined),
                  label: 'القواعد',
                ),
                NavigationDestination(
                  icon: Icon(Icons.speed_outlined),
                  label: 'الأداء',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sensor_door_outlined),
                  label: 'البوابة',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  label: 'الإحصائيات',
                ),
                NavigationDestination(
                  icon: Icon(Icons.privacy_tip_outlined),
                  label: 'الخصوصية',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
