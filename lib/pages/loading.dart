import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';

class LoadingPage extends StatelessWidget {
  final String title;
  const LoadingPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: title,
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}
