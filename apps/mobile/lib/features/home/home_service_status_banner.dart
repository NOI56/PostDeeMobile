import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization/postdee_localizations.dart';
import '../../core/network/postdee_api_client.dart';
import '../../core/theme/app_theme.dart';
import '../platforms/social_platform.dart';

typedef HomeServiceStatusLoader = Future<List<ServiceIncidentResult>>
    Function();

/// Open service notices from the admin console, shown at the top of Home.
///
/// It renders nothing when the app is running normally. A failed read keeps
/// the last known notices and never adds an error of its own to Home.
class HomeServiceStatusBanner extends StatefulWidget {
  const HomeServiceStatusBanner({
    super.key,
    required this.isActive,
    this.loadStatus,
    this.now,
  });

  final bool isActive;
  final HomeServiceStatusLoader? loadStatus;
  final DateTime Function()? now;

  @override
  State<HomeServiceStatusBanner> createState() =>
      HomeServiceStatusBannerState();
}

class HomeServiceStatusBannerState extends State<HomeServiceStatusBanner>
    with WidgetsBindingObserver {
  List<ServiceIncidentResult> _incidents = const [];
  Future<void>? _loadFuture;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isActive) refresh();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeServiceStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.isActive &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      refresh();
    }
  }

  Future<void> refresh() {
    final pending = _loadFuture;
    if (pending != null) return pending;
    final operation = _performLoad();
    _loadFuture = operation;
    unawaited(operation.whenComplete(() {
      if (identical(_loadFuture, operation)) _loadFuture = null;
    }));
    return operation;
  }

  Future<void> _performLoad() async {
    final generation = ++_generation;
    try {
      final incidents = await (widget.loadStatus ??
          PostDeeApiClient().loadServiceStatus)();
      if (!mounted || generation != _generation) return;
      setState(() => _incidents = incidents);
    } catch (_) {
      // Keep the last known notices; status is best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_incidents.isEmpty) return const SizedBox.shrink();
    final now = (widget.now ?? DateTime.now)();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, incident) in _incidents.indexed) ...[
            if (index > 0) const SizedBox(height: AppTheme.spaceSm),
            _ServiceIncidentCard(incident: incident, now: now),
          ],
        ],
      ),
    );
  }
}

class _ServiceIncidentCard extends StatelessWidget {
  const _ServiceIncidentCard({required this.incident, required this.now});

  final ServiceIncidentResult incident;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final isThai =
        PostDeeLocalizations.of(context).locale.languageCode == 'th';
    final stage = switch (incident.stage) {
      'IDENTIFIED' =>
        isThai ? 'พบสาเหตุแล้ว · กำลังแก้ไข' : 'Cause found · fixing',
      'MONITORING' =>
        isThai ? 'แก้แล้ว · กำลังติดตามผล' : 'Fixed · monitoring',
      _ => isThai ? 'กำลังตรวจสอบปัญหา' : 'Investigating',
    };
    final names = [
      for (final value in incident.platforms)
        ...SocialPlatform.values
            .where((platform) => platform.apiValue == value)
            .map((platform) => platform.label),
    ];
    final updated = incident.updatedAt;
    final time = '${updated.hour.toString().padLeft(2, '0')}:'
        '${updated.minute.toString().padLeft(2, '0')}';
    final sameDay = updated.year == now.year &&
        updated.month == now.month &&
        updated.day == now.day;
    final when = sameDay ? time : '${updated.day}/${updated.month} $time';
    final scope = names.isEmpty
        ? (isThai ? 'ทั้งแอป' : 'Whole app')
        : '${isThai ? 'กระทบ' : 'Affects'} ${names.join(', ')}';
    final meta = isThai ? '$scope · อัปเดต $when น.' : '$scope · updated $when';
    final tone = AppTheme.accentPink;
    final toneInk = AppTheme.accentPinkInk;

    return Semantics(
      container: true,
      child: DecoratedBox(
        key: ValueKey('service-incident-${incident.id}'),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(color: tone.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: toneInk, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stage,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: toneInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      incident.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    if (incident.message.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        incident.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
