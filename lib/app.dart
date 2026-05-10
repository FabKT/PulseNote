import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/folders_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/instant_transcription_screen.dart';
import 'screens/keywords_screen.dart';
import 'screens/menu_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/recordings_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'ui/app_theme.dart';

class AudioRecorderApp extends StatelessWidget {
  const AudioRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultimate Audio Recorder',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const AuthGate(child: MainNavigation()),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 1;

  final _screens = const [
    ScheduleScreen(),
    HomeScreen(),
    MenuScreen(),
  ];

  void _openStandalone(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuNavigationScope(
      openRecordings: () => _openStandalone(const RecordingsScreen()),
      openKeywords: () => _openStandalone(const KeywordsScreen()),
      openFolders: () => _openStandalone(const FoldersScreen()),
      openInstantTranscription: () =>
          _openStandalone(const InstantTranscriptionScreen()),
      openProfile: () => _openStandalone(const ProfileScreen()),
      openSettings: () => _openStandalone(const SettingsScreen()),
      child: Scaffold(
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const _TopHeader(),
              Expanded(child: _screens[_currentIndex]),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 0, 34, 10),
            child: SizedBox(
              height: 86,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    bottom: 4,
                    child: _BottomGlyph(
                      icon: Icons.schedule_rounded,
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    child: _RecordHomeButton(
                      selected: _currentIndex == 1,
                      homeActive: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 4,
                    child: _BottomGlyph(
                      icon: Icons.grid_view_rounded,
                      selected: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
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
}

class MenuNavigationScope extends InheritedWidget {
  final VoidCallback openRecordings;
  final VoidCallback openKeywords;
  final VoidCallback openFolders;
  final VoidCallback openInstantTranscription;
  final VoidCallback openProfile;
  final VoidCallback openSettings;

  const MenuNavigationScope({
    super.key,
    required this.openRecordings,
    required this.openKeywords,
    required this.openFolders,
    required this.openInstantTranscription,
    required this.openProfile,
    required this.openSettings,
    required super.child,
  });

  static MenuNavigationScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MenuNavigationScope>();
    assert(scope != null, 'MenuNavigationScope introuvable');
    return scope!;
  }

  @override
  bool updateShouldNotify(MenuNavigationScope oldWidget) => false;
}

class _TopHeader extends StatelessWidget {
  const _TopHeader();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, __) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
        child: Row(children: [
          const Expanded(
            child: Text(
              'Ultimate Audio Recorder',
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.hexagon_outlined,
                color: AppTheme.textMuted.withValues(alpha: 0.7),
                size: 28,
              ),
              Positioned(
                right: -1,
                top: -2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned.fill(
                child: Center(
                  child: Icon(
                    state.status == AppStatus.idle
                        ? Icons.circle_outlined
                        : Icons.circle,
                    color: AppTheme.textMuted,
                    size: 10,
                  ),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _BottomGlyph extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _BottomGlyph({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 28,
      color: selected ? AppTheme.primary : AppTheme.textMuted,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        minimumSize: const Size(56, 56),
      ),
    );
  }
}

class _RecordHomeButton extends StatelessWidget {
  final bool selected;
  final bool homeActive;
  final VoidCallback onTap;
  const _RecordHomeButton({
    required this.selected,
    required this.homeActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final canRecord = homeActive &&
            (state.status == AppStatus.sessionActive ||
                state.status == AppStatus.listening ||
                state.status == AppStatus.recording);
        final recording = state.status == AppStatus.recording;
        final bg = canRecord
            ? AppTheme.danger
            : selected
                ? AppTheme.primary
                : AppTheme.surfaceHigh;

        return GestureDetector(
          onTap: canRecord
              ? (recording ? state.stopRecording : state.startRecording)
              : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: canRecord
                  ? AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: recording ? 26 : 30,
                      height: recording ? 26 : 30,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(recording ? 7 : 99),
                      ),
                    )
                  : Icon(
                      Icons.home_rounded,
                      color: selected ? const Color(0xFF04211F) : AppTheme.text,
                      size: 32,
                    ),
            ),
          ),
        );
      },
    );
  }
}
