import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Real Roboto weights + MaterialIcons from the Flutter SDK, so golden
/// captures show true glyphs instead of empty squares.
String flutterMaterialFontsPath() {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages']
          as List;
  final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final packageRoot = config.uri.resolve('${flutter['rootUri']}/');
  return Directory.fromUri(
    packageRoot.resolve('../../bin/cache/artifacts/material_fonts/'),
  ).path;
}

Future<void> loadTestFonts() async {
  final path = flutterMaterialFontsPath();
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    final f = File('$path/Roboto-$weight.ttf');
    roboto.addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          await File('$path/MaterialIcons-Regular.otf').readAsBytes(),
        ),
      ),
    );
  await icons.load();
}
