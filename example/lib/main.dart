import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: LicenseExample()));

class LicenseExample extends StatelessWidget {
  const LicenseExample({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
            child: Text('Configure trusted keys before importing a license.')),
      );
}
