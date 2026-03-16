FUNCTION_BLOCK FB_VarTest
VAR_INPUT
  enable : BOOL;
  setpoint : REAL;
  name : STRING[80];
END_VAR
VAR_OUTPUT
  done : BOOL;
  value : REAL;
END_VAR
VAR_IN_OUT
  counter : INT;
END_VAR
VAR
  internalState : INT;
  timer : INT;
END_VAR
VAR RETAIN
  retainedCount : DINT;
END_VAR
VAR CONSTANT
  MAX_VALUE : REAL := 100.0;
  MIN_VALUE : REAL := 0.0;
END_VAR
  IF enable THEN
    value := setpoint;
    done := TRUE;
  END_IF;
END_FUNCTION_BLOCK
