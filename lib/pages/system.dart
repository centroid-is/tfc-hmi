import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';

class SystemsPage extends StatelessWidget {
  const SystemsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Controls Page',
      body: Container(
        child: const Center(
          child: Text(
            'Controls Page',
          ),
        ),
      ),
    );
  }
}
