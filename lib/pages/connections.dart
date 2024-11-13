import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';

class ConnectionPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Connections',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search Name...',
                suffixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 10, // Replace with your data length
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Icon(Icons.note),
                  title: Text(
                    'bool.in_${index + 1}', // Name
                  ),
                  subtitle: Text(
                    'Second input of or_e logic gate', // Description
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.add),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AddSlotDialog(),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AddSlotDialog extends StatefulWidget {
  @override
  _AddSlotDialogState createState() => _AddSlotDialogState();
}

class _AddSlotDialogState extends State<AddSlotDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Add slots to stopping',
      ),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: 10, // Replace with your data length
          itemBuilder: (context, index) {
            return CheckboxListTile(
              title: Text(
                'in_${index + 1}', // Name
              ),
              subtitle: Text(
                'Input ${index + 1} of AND gate', // Description
              ),
              value: false, // Replace with actual state
              onChanged: (value) {
                setState(() {
                  // Handle check state
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
          ),
        ),
        ElevatedButton(
          onPressed: () {
            // Handle Add action
            Navigator.pop(context);
          },
          child: Text(
            'Add',
          ),
        ),
      ],
    );
  }
}
