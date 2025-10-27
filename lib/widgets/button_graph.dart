import 'package:flutter/material.dart';
import 'package:board_datetime_picker/board_datetime_picker.dart';

Future<DateTimeRange?> showSetDatePicker(
    BuildContext context, DateTimeRange? dateRange) async {
  final result = await showBoardDateTimeMultiPicker(
    context: context,
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    maximumDate: DateTime.now(),
    pickerType: DateTimePickerType.datetime,
    useRootNavigator: true,
    breakpoint: 1000,
    customCloseButtonBuilder: (context, isModal, onClose) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context).colorScheme.onSurface, width: 1),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 20, color: Theme.of(context).colorScheme.onSurface),
                  SizedBox(width: 8),
                  Text("Apply",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            ),
          ),
        ),
      );
    },
    options: BoardDateTimeOptions(
      textColor: Theme.of(context).colorScheme.onSurface,
      activeTextColor: Theme.of(context).colorScheme.onTertiary,
      activeColor: Theme.of(context).colorScheme.tertiary,
      languages: BoardPickerLanguages(
        locale: 'en',
        today: 'Today',
        tomorrow: 'Tomorrow',
        now: 'Now',
      ),
      boardTitle: 'Select Date & Time Range',
      showDateButton: true,
      inputable: true,
      withSecond: true,
      pickerSubTitles: BoardDateTimeItemTitles(
        year: 'Year',
        month: 'Month',
        day: 'Day',
        hour: 'Hour',
        minute: 'Minute',
        second: 'Second',
        multiFrom: 'From',
        multiTo: 'To',
      ),
      separators: BoardDateTimePickerSeparators(
        date: PickerSeparator.slash,
        time: PickerSeparator.colon,
      ),
    ),
  );

  if (result != null) {
    return DateTimeRange(
      start: result.start,
      end: result.end,
    );
  }
  return null;
}

class ButtonGraph extends StatelessWidget {
  final bool showZoomIn;
  final bool showZoomOut;
  final bool showSetDate;
  final bool showNow;
  final bool showSave;
  final bool nowDisabled;
  final Function()? onZoomOut;
  final Function()? onZoomIn;
  final DateTimeRange? dateRange;
  final Function()? onSetDatePressed;
  final Function(DateTimeRange? dateRange)? onSetDateResult;
  final Function()? onNow;
  final Function()? onSave;

  const ButtonGraph({
    super.key,
    this.nowDisabled = false,
    this.onZoomOut,
    this.onZoomIn,
    this.dateRange,
    this.onSetDatePressed,
    this.onSetDateResult,
    this.onNow,
    this.onSave,
  })  : showZoomIn = onZoomIn != null,
        showZoomOut = onZoomOut != null,
        showSetDate = onSetDatePressed != null || onSetDateResult != null,
        showNow = onNow != null,
        showSave = onSave != null;

  @override
  Widget build(BuildContext context) {
    // Overlay the button in the bottom-right corner. This avoids touching Cristalyse internals
    // and visually places the control beneath the right-side legend.
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Theme.of(context).colorScheme.onSurface, width: 1),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom out button
            if (showZoomOut)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onZoomOut,
                  borderRadius:
                      BorderRadius.horizontal(left: Radius.circular(20)),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Icon(Icons.zoom_out,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
            // Divider
            if (showZoomOut)
              Container(
                height: 30,
                width: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            // Set date button
            if (showSetDate)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    onSetDatePressed?.call();
                    final result = await showSetDatePicker(context, dateRange);

                    if (result != null) {
                      onSetDateResult?.call(result);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month,
                            size: 20,
                            color: Theme.of(context).colorScheme.onSurface),
                        SizedBox(width: 8),
                        Text("Set date",
                            style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.onSurface)),
                      ],
                    ),
                  ),
                ),
              ),
            if (showSetDate)
              // Divider
              Container(
                height: 30,
                width: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            // Now button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: nowDisabled ? null : onNow,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          size: 20,
                          color: nowDisabled
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(80)
                              : Theme.of(context).colorScheme.onSurface),
                      SizedBox(width: 8),
                      Text("Now",
                          style: TextStyle(
                              color: nowDisabled
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withAlpha(80)
                                  : Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                ),
              ),
            ),
            // Divider
            if (showZoomIn)
              Container(
                height: 30,
                width: 1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            // // Save button
            // Material(
            //   color: Colors.transparent,
            //   child: InkWell(
            //     onTap: () {
            //       _chart.exportAsSvg();
            //     },
            //     child: Container(
            //       padding:
            //           EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            //       child: Row(
            //         mainAxisSize: MainAxisSize.min,
            //         children: [
            //           Icon(Icons.save,
            //               size: 20,
            //               color: Theme.of(context).colorScheme.onSurface),
            //           SizedBox(width: 8),
            //           Text("Save",
            //               style: TextStyle(
            //                   color: Theme.of(context)
            //                       .colorScheme
            //                       .onSurface)),
            //         ],
            //       ),
            //     ),
            //   ),
            // ),
            // // Divider
            // Container(
            //   height: 30,
            //   width: 1,
            //   color: Theme.of(context).colorScheme.onSurface,
            // ),
            // Zoom in button
            if (showZoomIn)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onZoomIn,
                  borderRadius:
                      BorderRadius.horizontal(right: Radius.circular(20)),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Icon(Icons.zoom_in,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
