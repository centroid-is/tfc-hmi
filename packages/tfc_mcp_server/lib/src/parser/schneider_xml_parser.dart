import 'package:xml/xml.dart';

import '../interfaces/plc_code_index.dart';
import 'structured_text_parser.dart';

/// Supported Schneider PLC export formats.
enum SchneiderFormat {
  /// Control Expert XEF/XML export format.
  ///
  /// Uses `<FBSource>` / `<STSource>` elements with `<objectName>` and
  /// `<sourceCode>` children. Variables in `<variables>` with `<variable>`
  /// elements.
  controlExpert,

  /// Machine Expert PLCopen XML format.
  ///
  /// Uses `<pou>` elements under `<pous>` with `<interface>` for variable
  /// declarations and `<body><ST><xhtml>` for implementation. Follows the
  /// PLCopen TC6 XML schema.
  plcopenXml,
}

/// Detect whether an XML string is a Schneider export and which format.
///
/// Returns null if the XML does not match any known Schneider format.
SchneiderFormat? detectSchneiderFormat(String xmlContent) {
  // Quick string-based checks before full parse to avoid expense
  if (xmlContent.contains('<FBSource') || xmlContent.contains('<STSource')) {
    return SchneiderFormat.controlExpert;
  }
  if (xmlContent.contains('http://www.plcopen.org/xml/tc6') ||
      xmlContent.contains('<project') && xmlContent.contains('<pous>')) {
    return SchneiderFormat.plcopenXml;
  }
  // Try to detect PLCopen by element structure
  if (xmlContent.contains('<pou ') && xmlContent.contains('<body>')) {
    return SchneiderFormat.plcopenXml;
  }
  return null;
}

/// Parse a Schneider XML export file into [ParsedCodeBlock] instances.
///
/// Auto-detects the format (Control Expert XEF or PLCopen XML) and
/// dispatches to the appropriate parser. Returns an empty list if the
/// format is unrecognized or contains no parseable blocks.
List<ParsedCodeBlock> parseSchneiderXml(String xmlContent, String filePath) {
  final format = detectSchneiderFormat(xmlContent);
  if (format == null) return [];

  switch (format) {
    case SchneiderFormat.controlExpert:
      return _parseControlExpert(xmlContent, filePath);
    case SchneiderFormat.plcopenXml:
      return _parsePlcopenXml(xmlContent, filePath);
  }
}

// ---------------------------------------------------------------------------
// Control Expert XEF format parser
// ---------------------------------------------------------------------------

/// Parse Schneider Control Expert XEF/XML export.
///
/// Control Expert exports contain `<FBSource>` elements for function blocks
/// and `<STSource>` elements for structured text sections. Each has:
/// - `<objectName>` — the block name
/// - `<sourceCode>` — the full ST source code
/// - `<variables>` / `<variable>` — variable declarations
///
/// Also handles `<program>` elements with `<section>` children that
/// reference ST code sections.
List<ParsedCodeBlock> _parseControlExpert(
    String xmlContent, String filePath) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlContent);
  } catch (_) {
    return [];
  }

  final blocks = <ParsedCodeBlock>[];

  // Parse FBSource elements (Function Blocks)
  for (final fbSource in doc.findAllElements('FBSource')) {
    final block = _parseControlExpertSource(fbSource, filePath, 'FBSource');
    if (block != null) blocks.add(block);
  }

  // Parse STSource elements (standalone ST sections / programs)
  for (final stSource in doc.findAllElements('STSource')) {
    final block = _parseControlExpertSource(stSource, filePath, 'STSource');
    if (block != null) blocks.add(block);
  }

  // Parse program sections if present
  for (final program in doc.findAllElements('program')) {
    final block = _parseControlExpertProgram(program, filePath);
    if (block != null) blocks.add(block);
  }

  return blocks;
}

/// Parse a single `<FBSource>` or `<STSource>` element.
ParsedCodeBlock? _parseControlExpertSource(
    XmlElement element, String filePath, String sourceType) {
  // Extract name from objectName child or Name attribute
  final name = element.findElements('objectName').firstOrNull?.innerText ??
      element.getAttribute('Name') ??
      element.getAttribute('name') ??
      '';
  if (name.isEmpty) return null;

  // Extract source code
  final sourceCode =
      element.findElements('sourceCode').firstOrNull?.innerText ?? '';

  // Extract variables from <variables>/<variable> structure
  final variableElements = element
      .findAllElements('variables')
      .expand((v) => v.findElements('variable'));

  final xmlVariables = <ParsedVariable>[];
  for (final varElem in variableElements) {
    final varName = varElem.getAttribute('name') ??
        varElem.findElements('name').firstOrNull?.innerText ??
        '';
    final varType = varElem.getAttribute('typeName') ??
        varElem.findElements('type').firstOrNull?.innerText ??
        '';
    final varSection = varElem.getAttribute('class') ??
        varElem.findElements('class').firstOrNull?.innerText ??
        'VAR';

    if (varName.isNotEmpty && varType.isNotEmpty) {
      xmlVariables.add(ParsedVariable(
        name: varName,
        type: varType,
        section: _normalizeVarSection(varSection),
      ));
    }
  }

  // Also parse variables from the source code itself (ST VAR blocks)
  final stVariables = parseVariables(sourceCode);

  // Merge: XML-declared variables take precedence, add any from ST parsing
  // that are not already in XML variables
  final allVariables = <ParsedVariable>[...xmlVariables];
  final xmlVarNames = xmlVariables.map((v) => v.name).toSet();
  for (final stVar in stVariables) {
    if (!xmlVarNames.contains(stVar.name)) {
      allVariables.add(stVar);
    }
  }

  // Detect type from source code or source element type
  final type = _detectTypeFromSource(sourceCode, sourceType);

  // Split source into declaration and implementation
  final (declaration, implementation) = _splitDeclarationImpl(sourceCode);

  return ParsedCodeBlock(
    name: name,
    type: type,
    declaration: declaration,
    implementation: implementation,
    fullSource: sourceCode.isNotEmpty ? sourceCode : declaration,
    filePath: filePath,
    variables: allVariables,
    children: const [],
  );
}

/// Parse a `<program>` element from Control Expert export.
ParsedCodeBlock? _parseControlExpertProgram(
    XmlElement element, String filePath) {
  final name = element.getAttribute('name') ??
      element.findElements('name').firstOrNull?.innerText ??
      '';
  if (name.isEmpty) return null;

  // Collect all ST code from section children
  final buffer = StringBuffer();
  for (final section in element.findElements('section')) {
    final sectionCode = section.innerText;
    if (sectionCode.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(sectionCode);
    }
  }

  final sourceCode = buffer.toString();
  if (sourceCode.isEmpty) return null;

  final variables = parseVariables(sourceCode);
  final (declaration, implementation) = _splitDeclarationImpl(sourceCode);

  return ParsedCodeBlock(
    name: name,
    type: 'Program',
    declaration: declaration,
    implementation: implementation,
    fullSource: sourceCode,
    filePath: filePath,
    variables: variables,
    children: const [],
  );
}

// ---------------------------------------------------------------------------
// PLCopen XML format parser (Machine Expert)
// ---------------------------------------------------------------------------

/// Parse Schneider Machine Expert PLCopen XML export.
///
/// PLCopen XML follows TC6 schema with:
/// - `<project>` root element
/// - `<types><pous>` containing `<pou>` elements
/// - Each `<pou>` has `pouType` attribute and contains:
///   - `<interface>` with variable declarations
///   - `<body><ST><xhtml>` with implementation code
/// - `<actions>`, `<methods>` as child elements of `<pou>`
List<ParsedCodeBlock> _parsePlcopenXml(String xmlContent, String filePath) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlContent);
  } catch (_) {
    return [];
  }

  final blocks = <ParsedCodeBlock>[];

  // Find all <pou> elements (case-insensitive search for robustness)
  for (final pou in doc.findAllElements('pou')) {
    final block = _parsePlcopenPou(pou, filePath);
    if (block != null) blocks.add(block);
  }

  // Also check for <globalVars> sections
  for (final gvl in doc.findAllElements('globalVars')) {
    final block = _parsePlcopenGlobalVars(gvl, filePath);
    if (block != null) blocks.add(block);
  }

  return blocks;
}

/// Parse a single `<pou>` element from PLCopen XML.
ParsedCodeBlock? _parsePlcopenPou(XmlElement pouElement, String filePath) {
  final name = pouElement.getAttribute('name') ?? '';
  if (name.isEmpty) return null;

  final pouType = pouElement.getAttribute('pouType') ?? '';

  // Extract variable declarations from <interface>
  final interfaceElem = pouElement.findElements('interface').firstOrNull;
  final variables = <ParsedVariable>[];
  final declarationBuffer = StringBuffer();

  if (interfaceElem != null) {
    // PLCopen groups vars by section: <localVars>, <inputVars>, <outputVars>,
    // <inOutVars>, <tempVars>
    for (final sectionMap in {
      'localVars': 'VAR',
      'inputVars': 'VAR_INPUT',
      'outputVars': 'VAR_OUTPUT',
      'inOutVars': 'VAR_IN_OUT',
      'tempVars': 'VAR_TEMP',
      'globalVars': 'VAR_GLOBAL',
    }.entries) {
      for (final section in interfaceElem.findElements(sectionMap.key)) {
        final sectionVars = _parsePlcopenVarSection(section, sectionMap.value);
        variables.addAll(sectionVars);

        // Build declaration text
        if (sectionVars.isNotEmpty) {
          declarationBuffer.writeln(sectionMap.value);
          for (final v in sectionVars) {
            final commentSuffix = v.comment != null ? ' // ${v.comment}' : '';
            declarationBuffer.writeln('    ${v.name} : ${v.type};$commentSuffix');
          }
          declarationBuffer.writeln('END_VAR');
        }
      }
    }
  }

  // Extract implementation from <body><ST><xhtml>
  final bodyElement = pouElement.findElements('body').firstOrNull;
  String? implementation;
  if (bodyElement != null) {
    // Try ST body first
    final stElement = bodyElement.findElements('ST').firstOrNull;
    if (stElement != null) {
      implementation = stElement.findElements('xhtml').firstOrNull?.innerText ??
          stElement.innerText;
    }
  }

  final declaration = declarationBuffer.toString().trimRight();

  // Also parse variables from the implementation text itself if present
  if (implementation != null) {
    final implVars = parseVariables(implementation);
    final existingNames = variables.map((v) => v.name).toSet();
    for (final v in implVars) {
      if (!existingNames.contains(v.name)) {
        variables.add(v);
      }
    }
  }

  // Map pouType to our type system
  final type = _mapPlcopenPouType(pouType);

  // Build fullSource
  final fullSourceBuffer = StringBuffer();
  if (declaration.isNotEmpty) {
    fullSourceBuffer.writeln(declaration);
  }
  if (implementation != null && implementation.isNotEmpty) {
    if (fullSourceBuffer.isNotEmpty) fullSourceBuffer.writeln();
    fullSourceBuffer.write(implementation);
  }

  // Parse child elements: actions, methods
  final children = <ParsedChildBlock>[];

  for (final action in pouElement.findAllElements('action')) {
    final actionName = action.getAttribute('name') ?? '';
    final actionBody = action.findElements('body').firstOrNull;
    String? actionImpl;
    if (actionBody != null) {
      final st = actionBody.findElements('ST').firstOrNull;
      if (st != null) {
        actionImpl = st.findElements('xhtml').firstOrNull?.innerText ??
            st.innerText;
      }
    }
    if (actionName.isNotEmpty) {
      children.add(ParsedChildBlock(
        name: actionName,
        childType: 'Action',
        declaration: '',
        implementation: actionImpl,
      ));
    }
  }

  for (final method in pouElement.findAllElements('method')) {
    final methodName = method.getAttribute('name') ?? '';
    final methodInterface = method.findElements('interface').firstOrNull;
    final methodBody = method.findElements('body').firstOrNull;

    String methodDecl = '';
    if (methodInterface != null) {
      methodDecl = methodInterface.innerText;
    }

    String? methodImpl;
    if (methodBody != null) {
      final st = methodBody.findElements('ST').firstOrNull;
      if (st != null) {
        methodImpl = st.findElements('xhtml').firstOrNull?.innerText ??
            st.innerText;
      }
    }

    if (methodName.isNotEmpty) {
      children.add(ParsedChildBlock(
        name: methodName,
        childType: 'Method',
        declaration: methodDecl,
        implementation: methodImpl,
      ));
    }
  }

  // Append children to fullSource
  for (final child in children) {
    fullSourceBuffer.writeln();
    fullSourceBuffer.writeln('// ${child.childType}: ${child.name}');
    if (child.declaration.isNotEmpty) {
      fullSourceBuffer.writeln(child.declaration);
    }
    if (child.implementation != null) {
      fullSourceBuffer.writeln(child.implementation);
    }
  }

  return ParsedCodeBlock(
    name: name,
    type: type,
    declaration: declaration,
    implementation: implementation,
    fullSource: fullSourceBuffer.toString(),
    filePath: filePath,
    variables: variables,
    children: children,
  );
}

/// Parse a `<globalVars>` section from PLCopen XML into a GVL block.
ParsedCodeBlock? _parsePlcopenGlobalVars(
    XmlElement gvlElement, String filePath) {
  final name = gvlElement.getAttribute('name') ?? 'GVL';

  final variables = _parsePlcopenVarSection(gvlElement, 'VAR_GLOBAL');
  if (variables.isEmpty) return null;

  final declarationBuffer = StringBuffer('VAR_GLOBAL\n');
  for (final v in variables) {
    final commentSuffix = v.comment != null ? ' // ${v.comment}' : '';
    declarationBuffer.writeln('    ${v.name} : ${v.type};$commentSuffix');
  }
  declarationBuffer.writeln('END_VAR');
  final declaration = declarationBuffer.toString().trimRight();

  return ParsedCodeBlock(
    name: name,
    type: 'GVL',
    declaration: declaration,
    implementation: null,
    fullSource: declaration,
    filePath: filePath,
    variables: variables,
    children: const [],
  );
}

/// Parse variables from a PLCopen variable section element.
///
/// PLCopen variable sections contain `<variable>` elements with:
/// - `name` attribute
/// - `<type>` child containing type element (e.g. `<BOOL/>`, `<INT/>`,
///   `<derived name="MyFB"/>`, `<string length="80"/>`)
/// - Optional `<documentation>` with `<xhtml>` content
List<ParsedVariable> _parsePlcopenVarSection(
    XmlElement sectionElement, String section) {
  final variables = <ParsedVariable>[];

  for (final varElem in sectionElement.findElements('variable')) {
    final name = varElem.getAttribute('name') ?? '';
    if (name.isEmpty) continue;

    // Extract type from the <type> child
    final typeElem = varElem.findElements('type').firstOrNull;
    final type = _extractPlcopenType(typeElem);

    // Extract documentation comment
    final docElem = varElem.findElements('documentation').firstOrNull;
    final comment = docElem?.findElements('xhtml').firstOrNull?.innerText ??
        docElem?.innerText;

    if (type.isNotEmpty) {
      variables.add(ParsedVariable(
        name: name,
        type: type,
        section: section,
        comment: comment?.trim(),
      ));
    }
  }

  return variables;
}

/// Extract the type string from a PLCopen `<type>` element.
///
/// PLCopen XML represents types as child elements:
/// - Simple types: `<BOOL/>`, `<INT/>`, `<REAL/>`, `<DINT/>`
/// - String types: `<string length="80"/>`
/// - Array types: `<array>` with `<dimension>` and `<baseType>`
/// - Derived types: `<derived name="MyFunctionBlock"/>`
String _extractPlcopenType(XmlElement? typeElement) {
  if (typeElement == null) return '';

  for (final child in typeElement.children.whereType<XmlElement>()) {
    final tagName = child.name.local;

    // Simple IEC types
    if (['BOOL', 'INT', 'DINT', 'SINT', 'LINT', 'UINT', 'UDINT', 'USINT',
         'ULINT', 'REAL', 'LREAL', 'BYTE', 'WORD', 'DWORD', 'LWORD',
         'STRING', 'WSTRING', 'TIME', 'DATE', 'TOD', 'DT',
         'DATE_AND_TIME', 'TIME_OF_DAY'].contains(tagName.toUpperCase())) {
      final length = child.getAttribute('length');
      if (length != null) {
        return '${tagName.toUpperCase()}($length)';
      }
      return tagName.toUpperCase();
    }

    // String with length
    if (tagName.toLowerCase() == 'string') {
      final length = child.getAttribute('length');
      return length != null ? 'STRING($length)' : 'STRING';
    }

    // Derived type (function block instance, struct, etc.)
    if (tagName.toLowerCase() == 'derived') {
      return child.getAttribute('name') ?? 'UNKNOWN';
    }

    // Array type
    if (tagName.toLowerCase() == 'array') {
      final baseType = _extractPlcopenType(
          child.findElements('baseType').firstOrNull);
      final dims = child.findElements('dimension').map((d) {
        final lower = d.getAttribute('lower') ?? '0';
        final upper = d.getAttribute('upper') ?? '0';
        return '$lower..$upper';
      }).join(', ');
      return 'ARRAY[$dims] OF $baseType';
    }

    // Fall back to tag name
    return tagName.toUpperCase();
  }

  return '';
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Normalize variable section names from Schneider formats to IEC standard.
String _normalizeVarSection(String section) {
  final upper = section.toUpperCase().trim();
  switch (upper) {
    case 'INPUT':
    case 'VAR_INPUT':
      return 'VAR_INPUT';
    case 'OUTPUT':
    case 'VAR_OUTPUT':
      return 'VAR_OUTPUT';
    case 'IN_OUT':
    case 'INOUT':
    case 'VAR_IN_OUT':
      return 'VAR_IN_OUT';
    case 'GLOBAL':
    case 'VAR_GLOBAL':
      return 'VAR_GLOBAL';
    case 'TEMP':
    case 'VAR_TEMP':
      return 'VAR_TEMP';
    case 'LOCAL':
    case 'VAR':
      return 'VAR';
    default:
      return 'VAR';
  }
}

/// Detect POU type from source code content or element type.
String _detectTypeFromSource(String sourceCode, String sourceType) {
  final trimmed = sourceCode.trimLeft().toUpperCase();

  if (trimmed.startsWith('FUNCTION_BLOCK')) return 'FunctionBlock';
  if (trimmed.startsWith('PROGRAM')) return 'Program';
  if (trimmed.startsWith('FUNCTION')) return 'Function';

  // Fall back to element type
  switch (sourceType.toLowerCase()) {
    case 'fbsource':
      return 'FunctionBlock';
    case 'stsource':
      return 'Program';
    default:
      return 'Unknown';
  }
}

/// Map PLCopen pouType attribute to our internal type string.
String _mapPlcopenPouType(String pouType) {
  switch (pouType.toLowerCase()) {
    case 'functionblock':
      return 'FunctionBlock';
    case 'program':
      return 'Program';
    case 'function':
      return 'Function';
    default:
      return 'Unknown';
  }
}

/// Split ST source code into declaration and implementation parts.
///
/// Declaration = everything from start through last END_VAR.
/// Implementation = everything after last END_VAR until END_xxx keyword.
(String declaration, String? implementation) _splitDeclarationImpl(
    String sourceCode) {
  if (sourceCode.isEmpty) return ('', null);

  final upper = sourceCode.toUpperCase();
  final endVarIndex = upper.lastIndexOf('END_VAR');

  if (endVarIndex == -1) {
    // No VAR blocks — entire source is treated as implementation
    return ('', sourceCode.trim().isEmpty ? null : sourceCode.trim());
  }

  final declaration =
      sourceCode.substring(0, endVarIndex + 'END_VAR'.length).trim();
  final afterEndVar = sourceCode.substring(endVarIndex + 'END_VAR'.length);

  // Trim trailing END_FUNCTION_BLOCK / END_PROGRAM / END_FUNCTION
  final endBlockPattern = RegExp(
    r'END_(?:FUNCTION_BLOCK|PROGRAM|FUNCTION)\b',
    caseSensitive: false,
  );
  final endMatch = endBlockPattern.firstMatch(afterEndVar);
  String implementation;
  if (endMatch != null) {
    implementation = afterEndVar.substring(0, endMatch.start).trim();
  } else {
    implementation = afterEndVar.trim();
  }

  return (declaration, implementation.isEmpty ? null : implementation);
}
