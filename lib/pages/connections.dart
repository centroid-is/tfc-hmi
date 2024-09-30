import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';
import '../app_colors.dart'; // Import the AppColors class

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
              style: TextStyle(color: AppColors.primaryTextColor), // Text color
              decoration: InputDecoration(
                labelText: 'Search Name...',
                labelStyle: TextStyle(color: AppColors.secondaryTextColor),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                suffixIcon:
                    Icon(Icons.search, color: AppColors.primaryIconColor),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 10, // Replace with your data length
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Icon(Icons.note,
                      color: AppColors.primaryIconColor), // Icon color
                  title: Text(
                    'bool.in_${index + 1}', // Name
                    style: TextStyle(color: AppColors.primaryTextColor),
                  ),
                  subtitle: Text(
                    'Second input of or_e logic gate', // Description
                    style: TextStyle(color: AppColors.secondaryTextColor),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.add, color: AppColors.secondaryIconColor),
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
      backgroundColor:
          AppColors.backgroundColor, // Background color of the dialog
      title: Text(
        'Add slots to stopping',
        style: TextStyle(color: AppColors.primaryTextColor), // Title text color
      ),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: 10, // Replace with your data length
          itemBuilder: (context, index) {
            return CheckboxListTile(
              activeColor: AppColors.selectedItemColor, // Active checkbox color
              checkColor:
                  AppColors.elevatedButtonTextColor, // Checkbox check color
              title: Text(
                'in_${index + 1}', // Name
                style: TextStyle(color: AppColors.primaryTextColor),
              ),
              subtitle: Text(
                'Input ${index + 1} of AND gate', // Description
                style: TextStyle(color: AppColors.secondaryTextColor),
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
            style: TextStyle(
                color: AppColors.secondaryTextColor), // Button text color
          ),
        ),
        ElevatedButton(
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all(
                AppColors.elevatedButtonColor), // Button color
          ),
          onPressed: () {
            // Handle Add action
            Navigator.pop(context);
          },
          child: Text(
            'Add',
            style: TextStyle(
                color: AppColors.elevatedButtonTextColor), // Button text color
          ),
        ),
      ],
    );
  }
}
