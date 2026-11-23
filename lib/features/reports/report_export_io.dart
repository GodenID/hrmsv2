import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Menu berbagi sistem (Android/iOS/desktop) untuk berkas laporan.
Future<void> shareReportFile(List<int> bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: 'Laporan HRMS'),
  );
}
