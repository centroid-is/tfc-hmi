import 'package:flutter/material.dart';

class UnknownPage extends StatelessWidget {
  const UnknownPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('404 - Page Not Found', style: TextStyle(fontSize: 24)),
    );
  }
}
