import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'config.dart';

/// Klien S3-compatible minimal (SigV4): presigned PUT/GET + HEAD/DELETE.
/// Tanpa dependensi baru — HMAC via package:crypto.
class S3Store {
  S3Store({
    required String endpoint,
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
    required this.pathStyle,
  }) : host = endpoint
            .trim()
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'/+$'), '');

  final String host;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;
  final bool pathStyle;

  String _hostFor() => pathStyle ? host : '$bucket.$host';

  String _uriFor(String key) {
    final enc = key.split('/').map(_encode).join('/');
    return pathStyle ? '/$bucket/$enc' : '/$enc';
  }

  static String _encode(String s) => Uri.encodeComponent(s).replaceAll('+', '%20');

  static String _dateStamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

  static String _amzDate(DateTime t) =>
      '${_dateStamp(t)}T${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}${t.second.toString().padLeft(2, '0')}Z';

  List<int> _signingKey(String dateStamp) {
    List<int> h(List<int> k, String d) =>
        Hmac(sha256, k).convert(utf8.encode(d)).bytes;
    var k = h(utf8.encode('AWS4$secretKey'), dateStamp);
    k = h(k, region);
    k = h(k, 's3');
    k = h(k, 'aws4_request');
    return k;
  }

  String _signature(String stringToSign, String dateStamp) =>
      Hmac(sha256, _signingKey(dateStamp))
          .convert(utf8.encode(stringToSign))
          .toString();

  /// URL upload langsung HP -> S3 (PUT). Hanya header `host` yg ditandatangani.
  String presignPut(String key, {int expiresSeconds = 900}) {
    final now = DateTime.now().toUtc();
    final ds = _dateStamp(now);
    final amz = _amzDate(now);
    final scope = '$ds/$region/s3/aws4_request';
    final q = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$accessKey/$scope',
      'X-Amz-Date': amz,
      'X-Amz-Expires': '$expiresSeconds',
      'X-Amz-SignedHeaders': 'host',
    };
    final qs = _canonicalQuery(q);
    final cr = 'PUT\n${_uriFor(key)}\n$qs\nhost:${_hostFor()}\n\nhost\nUNSIGNED-PAYLOAD';
    final sts = 'AWS4-HMAC-SHA256\n$amz\n$scope\n${sha256.convert(utf8.encode(cr))}';
    final sig = _signature(sts, ds);
    return 'https://${_hostFor()}${_uriFor(key)}?$qs&X-Amz-Signature=$sig';
  }

  /// URL baca privat (GET). [filename] tampil inline di browser.
  String presignGet(String key, {String? filename, int expiresSeconds = 900}) {
    final now = DateTime.now().toUtc();
    final ds = _dateStamp(now);
    final amz = _amzDate(now);
    final scope = '$ds/$region/s3/aws4_request';
    final q = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$accessKey/$scope',
      'X-Amz-Date': amz,
      'X-Amz-Expires': '$expiresSeconds',
      'X-Amz-SignedHeaders': 'host',
    };
    if (filename != null && filename.isNotEmpty) {
      q['response-content-disposition'] = 'inline; filename="$filename"';
    }
    final qs = _canonicalQuery(q);
    final cr = 'GET\n${_uriFor(key)}\n$qs\nhost:${_hostFor()}\n\nhost\nUNSIGNED-PAYLOAD';
    final sts = 'AWS4-HMAC-SHA256\n$amz\n$scope\n${sha256.convert(utf8.encode(cr))}';
    final sig = _signature(sts, ds);
    return 'https://${_hostFor()}${_uriFor(key)}?$qs&X-Amz-Signature=$sig';
  }

  /// URL publik (bucket/object public-read).
  String publicUrl(String key) =>
      pathStyle ? 'https://$host/$bucket/${key.split('/').map(_encode).join('/')}'
                : 'https://$bucket.$host/${key.split('/').map(_encode).join('/')}';

  static String _canonicalQuery(Map<String, String> q) {
    final keys = q.keys.toList()..sort();
    return keys.map((k) => '${_encode(k)}=${_encode(q[k]!)}').join('&');
  }

  Map<String, String> _authHeaders(String method, String key, String payloadHash) {
    final now = DateTime.now().toUtc();
    final ds = _dateStamp(now);
    final amz = _amzDate(now);
    const signed = 'host;x-amz-content-sha256;x-amz-date';
    final cr = '$method\n${_uriFor(key)}\n\nhost:${_hostFor()}\n'
        'x-amz-content-sha256:$payloadHash\nx-amz-date:$amz\n\n$signed\n$payloadHash';
    final scope = '$ds/$region/s3/aws4_request';
    final sts = 'AWS4-HMAC-SHA256\n$amz\n$scope\n${sha256.convert(utf8.encode(cr))}';
    return {
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amz,
      'Authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, SignedHeaders=$signed, Signature=${_signature(sts, ds)}',
    };
  }

  /// true bila objek sudah ter-upload (dipakai memvalidasi attachmentKey).
  Future<bool> exists(String key) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
          'HEAD', Uri.parse('https://${_hostFor()}${_uriFor(key)}'));
      const empty = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      _authHeaders('HEAD', key, empty).forEach(req.headers.set);
      final res = await req.close();
      await res.drain();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Hapus objek (bersih-bersih avatar lama). Gagal = diabaikan.
  Future<void> delete(String key) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
          'DELETE', Uri.parse('https://${_hostFor()}${_uriFor(key)}'));
      const empty = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      _authHeaders('DELETE', key, empty).forEach(req.headers.set);
      final res = await req.close();
      await res.drain();
    } catch (_) {
    } finally {
      client.close();
    }
  }
}

/// Dibangun dari env bila lengkap, null = upload file mati.
S3Store? storeOf(Config cfg) => cfg.s3enabled
    ? S3Store(
        endpoint: cfg.s3endpoint,
        bucket: cfg.s3bucket,
        region: cfg.s3region,
        accessKey: cfg.s3accessKey,
        secretKey: cfg.s3secretKey,
        pathStyle: cfg.s3pathStyle,
      )
    : null;
