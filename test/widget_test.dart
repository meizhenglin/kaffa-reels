import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qahwa_tv/main.dart';
import 'package:qahwa_tv/core/storage/storage_service.dart';
import 'package:qahwa_tv/app/providers/app_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/firebase_core'),
      (call) async {
        if (call.method == 'Firebase#initializeCore') {
          return [
            {
              'name': '[DEFAULT]',
              'options': {
                'apiKey': 'test',
                'appId': 'test',
                'messagingSenderId': 'test',
                'projectId': 'test',
              },
              'pluginConstants': <String, Object>{},
            }
          ];
        }
        if (call.method == 'Firebase#initializeApp') {
          return {
            'name': call.arguments['appName'],
            'options': call.arguments['options'],
            'pluginConstants': <String, Object>{},
          };
        }
        return null;
      },
    );
    await Firebase.initializeApp();
  });

  testWidgets('App launches and shows home page', (WidgetTester tester) async {
    final storage = StorageService();
    await storage.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const QahwaTVApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
