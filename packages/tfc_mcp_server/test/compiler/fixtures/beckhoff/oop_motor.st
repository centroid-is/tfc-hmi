INTERFACE ITF_Drive
  METHOD Start : BOOL
  END_METHOD

  METHOD Stop : BOOL
  END_METHOD

  PROPERTY Speed : REAL
END_INTERFACE

FUNCTION_BLOCK FB_Motor EXTENDS FB_Base IMPLEMENTS ITF_Drive
VAR_INPUT
  bStart : BOOL;
  rSetSpeed : REAL;
END_VAR
VAR_OUTPUT
  bRunning : BOOL;
  rActSpeed : REAL;
END_VAR
VAR
  _state : INT;
  _rampRate : REAL := 10.0;
END_VAR
  IF bStart AND NOT bRunning THEN
    _state := 1;
    bRunning := TRUE;
  END_IF;

  IF bRunning THEN
    IF rActSpeed < rSetSpeed THEN
      rActSpeed := rActSpeed + _rampRate;
    ELSIF rActSpeed > rSetSpeed THEN
      rActSpeed := rActSpeed - _rampRate;
    END_IF;
  END_IF;
END_FUNCTION_BLOCK

// METHOD definitions would be in separate XML nodes in TcPOU
// but for raw .st testing, inline them here
