import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/base_scaffold.dart';
import '../tech_docs/tech_doc_library_section.dart';

class TechDocLibraryPage extends ConsumerWidget {
  const TechDocLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BaseScaffold(
      title: 'Knowledge Base',
      body: const TechDocLibrarySection(embedded: false),
    );
  }
}
