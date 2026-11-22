import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore first answers a query from its local cache, which may hold only
/// some of the documents (e.g. just the Self profile). Shown as-is, the Family
/// tab briefly said "1 profile" while the account had 4.
///
/// This waits up to [wait] for the server's answer. If the server is slow or
/// the phone is offline, the cached answer is used after all (DESIGN §6:
/// offline shows the last data). After the first server answer, every
/// snapshot passes through.
Stream<fs.QuerySnapshot<T>> serverFirst<T>(fs.Query<T> query, {Duration wait = const Duration(seconds: 2)}) {
  late StreamController<fs.QuerySnapshot<T>> out;
  StreamSubscription<fs.QuerySnapshot<T>>? sub;
  Timer? timer;
  fs.QuerySnapshot<T>? pending;
  var live = false;

  void release() {
    live = true;
    timer?.cancel();
    if (pending != null) out.add(pending!);
    pending = null;
  }

  out = StreamController<fs.QuerySnapshot<T>>(
    onListen: () {
      timer = Timer(wait, release);
      sub = query.snapshots(includeMetadataChanges: true).listen(
        (s) {
          if (live) {
            out.add(s);
          } else if (!s.metadata.isFromCache) {
            pending = s;
            release();
          } else {
            pending = s; // keep the latest cached answer for the timeout
          }
        },
        onError: out.addError,
        onDone: out.close,
      );
    },
    onCancel: () async {
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return out.stream;
}
