PROGRAM SchneiderTypes
VAR
  startButton : EBOOL;
  stopButton : EBOOL;
  motorStatus : EBOOL;
  alarmWord : WORD;
  speedRef : REAL;
  myString : STRING[32] := 'Hello World';
END_VAR
  IF startButton AND NOT stopButton THEN
    motorStatus := TRUE;
    speedRef := 50.0;
  ELSE
    motorStatus := FALSE;
    speedRef := 0.0;
  END_IF;
END_PROGRAM
