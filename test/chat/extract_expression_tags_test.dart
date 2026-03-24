import 'package:flutter_test/flutter_test.dart';
import 'package:tfc_dart/core/boolean_expression.dart';

import 'package:tfc/chat/asset_context_menu.dart';

void main() {
  group('extractExpressionTags', () {
    // ---------------------------------------------------------------
    // IconConfig — conditional_states[].expression.value.formula
    // ---------------------------------------------------------------
    group('IconConfig conditional_states', () {
      test('extracts tags from fully-serialized JSON (Map path)', () {
        // This is the shape produced when the entire tree is serialized
        // to Maps (e.g., jsonDecode(jsonEncode(iconConfig.toJson()))).
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': 'pump3.running == TRUE',
                },
              },
              'iconData': null,
              'color': null,
            },
            {
              'expression': {
                'value': {
                  'formula': 'pump3.fault == TRUE',
                },
              },
              'iconData': null,
              'color': null,
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, unorderedEquals(['pump3.running', 'pump3.fault']));
      });

      test('extracts tags when value is a live Expression object', () {
        // This is the shape produced by ExpressionConfig.toJson() which
        // does NOT have explicitToJson — 'value' stores the raw Expression.
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': Expression(formula: 'conveyor1.speed > 50'),
              },
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, contains('conveyor1.speed'));
      });

      test('extracts tags from complex boolean expressions', () {
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': 'pump3.running == TRUE AND pump3.fault == FALSE',
                },
              },
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, unorderedEquals(['pump3.running', 'pump3.fault']));
      });

      test('deduplicates tags across multiple conditional states', () {
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': 'pump3.running == TRUE',
                },
              },
            },
            {
              'expression': {
                'value': {
                  'formula': 'pump3.running == FALSE',
                },
              },
            },
          ],
        };

        final tags = extractExpressionTags(json);
        // Should deduplicate — only one 'pump3.running'.
        expect(tags, equals(['pump3.running']));
      });
    });

    // ---------------------------------------------------------------
    // ButtonConfig — nested icon with conditional_states
    // ---------------------------------------------------------------
    group('ButtonConfig with nested IconConfig', () {
      test('extracts tags from icon.conditional_states inside ButtonConfig', () {
        // ButtonConfig.toJson() includes 'icon' which is an IconConfig.
        final json = <String, dynamic>{
          'key': 'start_button',
          'outward_color': {'value': 4283215696},
          'inward_color': {'value': 4288585374},
          'button_type': 'circle',
          'icon': {
            'iconData': {'codePoint': 57490, 'fontFamily': 'MaterialIcons'},
            'conditional_states': [
              {
                'expression': {
                  'value': {
                    'formula': 'motor1.running == TRUE',
                  },
                },
                'color': {'value': 4283215696},
              },
            ],
          },
        };

        final tags = extractExpressionTags(json);
        expect(tags, contains('motor1.running'));
      });
    });

    // ---------------------------------------------------------------
    // Assets WITHOUT expressions — should return empty
    // ---------------------------------------------------------------
    group('assets without expressions', () {
      test('LEDConfig returns empty (key-based, no formulas)', () {
        final json = <String, dynamic>{
          'key': 'pump3.running',
          'on_color': {'value': 4283215696},
          'off_color': {'value': 4288585374},
          'led_type': 'circle',
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('LEDColumnConfig returns empty', () {
        final json = <String, dynamic>{
          'leds': [
            {
              'key': 'pump1.running',
              'on_color': {'value': 4283215696},
              'off_color': {'value': 4288585374},
              'led_type': 'circle',
            },
            {
              'key': 'pump2.running',
              'on_color': {'value': 4283215696},
              'off_color': {'value': 4288585374},
              'led_type': 'circle',
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('NumberConfig returns empty', () {
        final json = <String, dynamic>{
          'key': 'tank1.level',
          'showDecimalPoint': true,
          'decimalPlaces': 2,
          'units': 'L',
          'scale': 1.0,
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('GraphAssetConfig returns empty (keys in series, no formulas)', () {
        final json = <String, dynamic>{
          'graph_type': 'timeseries',
          'primary_series': [
            {'key': 'tank1.level', 'label': 'Level'},
            {'key': 'tank1.temp', 'label': 'Temperature'},
          ],
          'secondary_series': [],
          'x_axis': {'unit': 's'},
          'y_axis': {'unit': 'L'},
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('ButtonConfig without icon returns empty', () {
        final json = <String, dynamic>{
          'key': 'start_button',
          'outward_color': {'value': 4283215696},
          'inward_color': {'value': 4288585374},
          'button_type': 'circle',
          'feedback': {
            'key': 'start_button.fb',
            'color': {'value': 4283215696},
          },
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });
    });

    // ---------------------------------------------------------------
    // Edge cases
    // ---------------------------------------------------------------
    group('edge cases', () {
      test('empty map returns empty', () {
        expect(extractExpressionTags({}), isEmpty);
      });

      test('null expression in conditional state is skipped', () {
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': null,
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('empty formula is skipped', () {
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': '',
                },
              },
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('no conditional_states key returns empty', () {
        final json = <String, dynamic>{
          'iconData': {'codePoint': 57490, 'fontFamily': 'MaterialIcons'},
          'color': null,
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('conditional_states as empty list returns empty', () {
        final json = <String, dynamic>{
          'conditional_states': [],
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('malformed formula is skipped gracefully', () {
        // Expression.extractVariables() may throw on malformed formulas.
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': '== INVALID ==',
                },
              },
            },
          ],
        };

        // Should not throw — malformed formulas are skipped.
        final tags = extractExpressionTags(json);
        // Depending on parser, may return empty or partial results.
        expect(tags, isA<List<String>>());
      });

      test('Expression object with empty formula is skipped', () {
        final json = <String, dynamic>{
          'conditional_states': [
            {
              'expression': {
                'value': Expression(formula: ''),
              },
            },
          ],
        };

        final tags = extractExpressionTags(json);
        expect(tags, isEmpty);
      });

      test('top-level expression field (non-conditional) is found', () {
        // Some future asset type might have a top-level expression field.
        final json = <String, dynamic>{
          'expression': {
            'value': {
              'formula': 'sensor1.value > 100',
            },
          },
        };

        final tags = extractExpressionTags(json);
        expect(tags, contains('sensor1.value'));
      });

      test('deeply nested formula is found', () {
        // Formula buried 5 levels deep in arbitrary structure.
        final json = <String, dynamic>{
          'some_config': {
            'nested': {
              'items': [
                {
                  'expression': {
                    'value': {
                      'formula': 'deep.tag == TRUE',
                    },
                  },
                },
              ],
            },
          },
        };

        final tags = extractExpressionTags(json);
        expect(tags, contains('deep.tag'));
      });

      test('multiple formulas across different nesting levels', () {
        final json = <String, dynamic>{
          'expression': {
            'value': {
              'formula': 'top.level.tag == TRUE',
            },
          },
          'conditional_states': [
            {
              'expression': {
                'value': {
                  'formula': 'state.tag > 5',
                },
              },
            },
          ],
          'nested': {
            'expression': {
              'value': {
                'formula': 'nested.tag == FALSE',
              },
            },
          },
        };

        final tags = extractExpressionTags(json);
        expect(
          tags,
          unorderedEquals(['top.level.tag', 'state.tag', 'nested.tag']),
        );
      });
    });
  });
}
