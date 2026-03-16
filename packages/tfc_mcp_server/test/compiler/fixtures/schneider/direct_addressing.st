PROGRAM SchneiderIO
VAR
  motorStart AT %I0.3.5 : BOOL;
  motorRun AT %Q0.4.0 : BOOL;
  speedCmd AT %MW100 : INT;
  tempSensor AT %IW0.2.0 : INT;
  internalBit AT %M200 : BOOL;
  internalWord AT %MW500 : INT;
END_VAR
  IF motorStart THEN
    motorRun := TRUE;
    speedCmd := 1500;
  ELSE
    motorRun := FALSE;
    speedCmd := 0;
  END_IF;

  // Direct address in expression
  %MW101 := %MW100 + 1;
  IF %I0.3.6 THEN
    %Q0.4.1 := TRUE;
  END_IF;
END_PROGRAM
