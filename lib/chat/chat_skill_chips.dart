import 'package:flutter/material.dart';

/// A predefined chat skill/shortcut that appears as a quick-action chip.
///
/// Each skill has a label, icon, and prompt template. When tapped, the prompt
/// is inserted into the chat input for the user to review/edit before sending.
class ChatSkill {
  /// Unique identifier for this skill (used in ValueKey).
  final String id;

  /// The label displayed on the chip.
  final String label;

  /// The icon displayed on the chip.
  final IconData icon;

  /// The prompt template to pre-fill in the chat input.
  final String prompt;

  const ChatSkill({
    required this.id,
    required this.label,
    required this.icon,
    required this.prompt,
  });
}

/// The default set of predefined chat skills.
const defaultChatSkills = [
  ChatSkill(
    id: 'create-alarm',
    label: 'Create alarm',
    icon: Icons.alarm_add,
    prompt: 'Create a new alarm for ',
  ),
  ChatSkill(
    id: 'create-page',
    label: 'Create page',
    icon: Icons.dashboard_customize,
    prompt: 'Create a new page for ',
  ),
  ChatSkill(
    id: 'show-history',
    label: 'Show history',
    icon: Icons.history,
    prompt: 'Show the history for ',
  ),
  ChatSkill(
    id: 'explain-asset',
    label: 'Explain asset',
    icon: Icons.help_outline,
    prompt: 'Explain what this asset does: ',
  ),
];

/// Displays a row of quick-action chips for predefined chat skills.
///
/// Each chip is an [ActionChip] with an icon and label. Tapping a chip
/// invokes [onSkillTapped] with the selected skill's prompt text, which
/// the parent widget uses to pre-fill the chat input field.
///
/// Designed to appear in the empty state of the chat widget, giving
/// operators one-tap access to common AI workflows.
class ChatSkillChips extends StatelessWidget {
  /// The list of skills to display as chips.
  final List<ChatSkill> skills;

  /// Called when a skill chip is tapped, with the skill's prompt text.
  final ValueChanged<String> onSkillTapped;

  const ChatSkillChips({
    super.key,
    this.skills = defaultChatSkills,
    required this.onSkillTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: skills.map((skill) {
          return ActionChip(
            key: ValueKey<String>('chat-skill-${skill.id}'),
            avatar: Icon(
              skill.icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            label: Text(
              skill.label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
            onPressed: () => onSkillTapped(skill.prompt),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: theme.colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        }).toList(),
      ),
    );
  }
}
