import 'package:flutter/material.dart';
import 'package:operador/design/legacy_theme.dart';

import 'application/unified_bundle.dart';
import 'application/unified_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MuleAgentApp());
}

class MuleAgentApp extends StatelessWidget {
  const MuleAgentApp({super.key, this.bundle});
  final UnifiedBundle? bundle;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MuleAgent',
    debugShowCheckedModeBanner: false,
    // Estilo Mule tokens remain the UI contract; applying both themes is stage 3.
    theme: legacyCaptureTheme(),
    home: UnifiedShell(bundle: bundle),
  );
}
