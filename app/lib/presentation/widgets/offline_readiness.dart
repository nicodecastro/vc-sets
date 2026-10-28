import 'package:flutter/material.dart';

import '../../application/offline_status.dart';

class OfflineReadiness extends StatelessWidget {
  const OfflineReadiness({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: offlineStatus,
    builder: (context, status, _) {
      if (status == 'native') return const SizedBox.shrink();
      final message = switch (status) {
        'ready' => 'Ready for offline use',
        'failed' => 'Offline preparation failed. Reconnect and retry.',
        'unsupported' =>
          'Offline loading is unavailable in this browser or preview.',
        'storage-unavailable' => 'This browser cannot save data between visits. Export a backup before closing.',
        _ => 'Preparing offline use. Keep this app open and connected.',
      };
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                status == 'ready'
                    ? Icons.offline_pin_outlined
                    : Icons.info_outline,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
              if (status == 'failed')
                TextButton(
                  onPressed: retryOfflinePreparation,
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    },
  );
}
