import 'package:flutter/material.dart';

import 'uvccamera_demo_app.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init((options) {
    options.dsn = 'https://2af026f18409257007bd896ecb9dc39d@o4509869693534213.ingest.de.sentry.io/4509869711556688';
    // Adds request headers and IP for users, for more info visit:
    // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
    options.sendDefaultPii = true;
    options.enableLogs = true;
    // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
    // We recommend adjusting this value in production.
    options.tracesSampleRate = 1.0;
    // Configure Session Replay
    options.replay.sessionSampleRate = 0.1;
    options.replay.onErrorSampleRate = 1.0;
  }, appRunner: () => runApp(SentryWidget(child: const UvcCameraDemoApp())));
  // TODO: Remove this line after sending the first sample event to sentry.
  // await Sentry.captureException(StateError('This is a sample exception.'));
}
