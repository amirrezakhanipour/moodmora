import 'package:flutter/material.dart';

class ReplyScreen extends StatelessWidget {
  const ReplyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reply')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Text('TODO: Reply form + suggestions'),
      ),
    );
  }
}
