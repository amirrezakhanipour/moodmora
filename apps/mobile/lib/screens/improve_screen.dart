import 'package:flutter/material.dart';

class ImproveScreen extends StatelessWidget {
  const ImproveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Improve')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('TODO: Improve form + output'),
      ),
    );
  }
}
