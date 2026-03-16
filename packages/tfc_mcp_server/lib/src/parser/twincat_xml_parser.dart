import 'package:xml/xml.dart';

import '../interfaces/plc_code_index.dart';
import 'structured_text_parser.dart';

/// Parse a TcPOU XML file into a [ParsedCodeBlock].
///
/// Extracts the POU name, type (FunctionBlock/Program/Function),
/// declaration, implementation, child blocks (Method/Action/Property/
/// Transition), and variables from CDATA sections.
///
/// Returns null if the XML contains no `<POU>` element.
ParsedCodeBlock? parseTcPou(String xmlContent, String filePath) {
  final doc = XmlDocument.parse(xmlContent);
  final pouElement = doc.findAllElements('POU').firstOrNull;
  if (pouElement == null) return null;

  final name = pouElement.getAttribute('Name') ?? '';

  final declaration =
      pouElement.findElements('Declaration').firstOrNull?.innerText ?? '';

  // Navigate: POU -> Implementation -> ST -> CDATA text
  final implementation = pouElement
      .findElements('Implementation')
      .firstOrNull
      ?.findElements('ST')
      .firstOrNull
      ?.innerText;

  final type = _detectPouType(declaration);
  final variables = parseVariables(declaration);

  // Parse child elements: Method, Action, Property, Transition
  final children = <ParsedChildBlock>[];

  for (final childType in ['Method', 'Action', 'Property', 'Transition']) {
    for (final element in pouElement.findElements(childType)) {
      final childName = element.getAttribute('Name') ?? '';
      final childDecl =
          element.findElements('Declaration').firstOrNull?.innerText ?? '';

      // For Property, implementation is in Get/Set sub-elements
      String? childImpl;
      if (childType == 'Property') {
        final getElement = element.findElements('Get').firstOrNull;
        childImpl = getElement
            ?.findElements('Implementation')
            .firstOrNull
            ?.findElements('ST')
            .firstOrNull
            ?.innerText;
      } else {
        childImpl = element
            .findElements('Implementation')
            .firstOrNull
            ?.findElements('ST')
            .firstOrNull
            ?.innerText;
      }

      children.add(ParsedChildBlock(
        name: childName,
        childType: childType,
        declaration: childDecl,
        implementation: childImpl,
      ));
    }
  }

  // Build fullSource from declaration + implementation + children
  final buffer = StringBuffer(declaration);
  if (implementation != null && implementation.isNotEmpty) {
    buffer.writeln();
    buffer.write(implementation);
  }
  for (final child in children) {
    buffer.writeln();
    buffer.writeln('// ${child.childType}: ${child.name}');
    if (child.declaration.isNotEmpty) {
      buffer.writeln(child.declaration);
    }
    if (child.implementation != null) {
      buffer.writeln(child.implementation);
    }
  }

  return ParsedCodeBlock(
    name: name,
    type: type,
    declaration: declaration,
    implementation: implementation,
    fullSource: buffer.toString(),
    filePath: filePath,
    variables: variables,
    children: children,
  );
}

/// Parse a TcGVL XML file into a [ParsedCodeBlock].
///
/// Extracts the GVL name, declaration, and variables. GVLs have no
/// implementation (always null).
///
/// Returns null if the XML contains no `<GVL>` element.
ParsedCodeBlock? parseTcGvl(String xmlContent, String filePath) {
  final doc = XmlDocument.parse(xmlContent);
  final gvlElement = doc.findAllElements('GVL').firstOrNull;
  if (gvlElement == null) return null;

  final name = gvlElement.getAttribute('Name') ?? '';

  final declaration =
      gvlElement.findElements('Declaration').firstOrNull?.innerText ?? '';

  final variables = parseVariables(declaration);

  return ParsedCodeBlock(
    name: name,
    type: 'GVL',
    declaration: declaration,
    implementation: null,
    fullSource: declaration,
    filePath: filePath,
    variables: variables,
    children: [],
  );
}

/// Detect POU type from the declaration text.
///
/// Checks for FUNCTION_BLOCK, PROGRAM, or FUNCTION keywords at the
/// start of the declaration (case-insensitive).
String _detectPouType(String declaration) {
  final trimmed = declaration.trimLeft();
  final upper = trimmed.toUpperCase();

  // Check FUNCTION_BLOCK before FUNCTION (longer match first)
  if (upper.startsWith('FUNCTION_BLOCK')) return 'FunctionBlock';
  if (upper.startsWith('PROGRAM')) return 'Program';
  if (upper.startsWith('FUNCTION')) return 'Function';

  return 'Unknown';
}
