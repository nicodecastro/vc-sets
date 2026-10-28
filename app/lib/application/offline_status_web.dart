import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import '../data/connection/connection_web.dart' show hasPersistentWebStorage;

@JS('vcSetsOffline')
external JSObject? get _bridge;
@JS('vcSetsOffline.subscribe')
external void _subscribe(JSFunction callback);
@JS('vcSetsOffline.databaseReady')
external void _databaseReady(JSBoolean storageAvailable);
@JS('vcSetsOffline.retry')
external void _retry();

final offlineStatus = ValueNotifier<String>('preparing');
void initializeOfflineStatus() {
  if (_bridge == null) {
    offlineStatus.value = 'unsupported';
    return;
  }
  _subscribe(((JSString state) => offlineStatus.value = state.toDart).toJS);
  _databaseReady(hasPersistentWebStorage.toJS);
}

void retryOfflinePreparation() {
  if (_bridge != null) _retry();
}
