import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ui/app_theme.dart';

// Etat des autorisations systeme dont depend l'enregistrement en arriere-plan.
// L'app ne peut pas accorder ces droits elle-meme : le seul geste possible est
// de demander l'autorisation, puis de renvoyer vers les reglages Android si
// l'utilisateur l'a refusee definitivement.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with WidgetsBindingObserver {
  PermissionStatus? _notification;
  PermissionStatus? _microphone;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // L'utilisateur revient peut-etre des reglages Android : on relit l'etat
    // reel plutot que d'afficher une valeur perimee.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final notification = await Permission.notification.status;
    final microphone = await Permission.microphone.status;
    if (!mounted) return;
    setState(() {
      _notification = notification;
      _microphone = microphone;
      _loading = false;
    });
  }

  Future<void> _request(Permission permission) async {
    final before = await permission.status;
    if (before.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await permission.request();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: const Text('Notifications'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _PermissionCard(
                  icon: Icons.notifications_rounded,
                  title: 'Notifications',
                  description:
                      'Requises pour afficher la notification permanente '
                      'pendant un enregistrement ou une session d\'écoute. '
                      'Android impose cette notification : sans elle, le '
                      'système peut interrompre l\'enregistrement en '
                      'arrière-plan.',
                  status: _notification,
                  onRequest: () => _request(Permission.notification),
                ),
                const SizedBox(height: 12),
                _PermissionCard(
                  icon: Icons.mic_rounded,
                  title: 'Microphone',
                  description:
                      'Indispensable pour tout enregistrement, ainsi que pour '
                      'la détection de mots-clés.',
                  status: _microphone,
                  onRequest: () => _request(Permission.microphone),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.panel(radius: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enregistrement en arrière-plan',
                        style: TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Certains constructeurs (Samsung, Xiaomi, Huawei…) '
                        'ferment les applications en arrière-plan pour '
                        'économiser la batterie. Si vos enregistrements '
                        'planifiés se coupent, désactivez l\'optimisation de '
                        'batterie pour cette application dans les réglages '
                        'Android.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Ouvrir les réglages Android'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final PermissionStatus? status;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.onRequest,
  });

  bool get _granted => status?.isGranted ?? false;

  String get _label {
    final value = status;
    if (value == null) return 'Inconnu';
    if (value.isGranted) return 'Autorisé';
    if (value.isPermanentlyDenied) return 'Refusé définitivement';
    if (value.isDenied) return 'Non autorisé';
    if (value.isRestricted || value.isLimited) return 'Limité';
    return 'Inconnu';
  }

  @override
  Widget build(BuildContext context) {
    final color = _granted ? AppTheme.primary : AppTheme.danger;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panel(radius: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (!_granted) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRequest,
            icon: const Icon(Icons.lock_open_rounded, size: 18),
            label: Text(
              status?.isPermanentlyDenied == true
                  ? 'Ouvrir les réglages'
                  : 'Autoriser',
            ),
          ),
        ],
      ]),
    );
  }
}
