import 'dart:collection';

import 'package:shelf/shelf.dart';

/// Batas laju per IP untuk endpoint publik (anti brute-force & spam daftar).
/// In-memory per instance (cukup untuk 1 replika; naikkan ke Redis bila
/// horizontal scaling). Di belakang proxy, IP diambil dari X-Forwarded-For.
class RateLimiter {
  final Map<String, Queue<DateTime>> _buckets = HashMap();

  /// true = lolos (dicatat). false = melebihi [max] dalam [window].
  bool allow(String key, {required int max, required Duration window}) {
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(window);
    final q = _buckets.putIfAbsent(key, Queue.new);
    while (q.isNotEmpty && q.first.isBefore(cutoff)) {
      q.removeFirst();
    }
    if (q.length >= max) return false;
    q.add(now);
    if (_buckets.length > 10000) _buckets.clear();
    return true;
  }

  /// Menit hingga jendela longgar (untuk pesan galat).
  int retryMinutes(String key, Duration window) {
    final q = _buckets[key];
    if (q == null || q.isEmpty) return 1;
    final wait = q.first.add(window).difference(DateTime.now().toUtc());
    return (wait.inSeconds + 59) ~/ 60.clamp(1, 1 << 30);
  }
}

final rateLimiter = RateLimiter();

String clientIp(Request req) {
  final fwd = req.headers['x-forwarded-for'];
  if (fwd != null && fwd.trim().isNotEmpty) {
    return fwd.split(',').first.trim();
  }
  return 'unknown';
}

/// null = lolos; Response 429 bila melewati batas.
Response? limitIp(
  Request req,
  String scope, {
  required int max,
  required Duration window,
}) {
  final key = '$scope:${clientIp(req)}';
  if (rateLimiter.allow(key, max: max, window: window)) return null;
  final mins = rateLimiter.retryMinutes(key, window);
  return Response(
    429,
    body:
        '{"message":"Terlalu banyak percobaan. Silakan mencoba lagi dalam $mins menit."}',
    headers: {'content-type': 'application/json'},
  );
}
