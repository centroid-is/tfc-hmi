FUNCTION_BLOCK FB_Heater
VAR
  _temperature : REAL;
  _setpoint : REAL;
  _output : REAL;
  _enabled : BOOL;
END_VAR
  IF _enabled THEN
    _output := (_setpoint - _temperature) * 0.5;
  ELSE
    _output := 0.0;
  END_IF;
END_FUNCTION_BLOCK

METHOD PUBLIC Start : BOOL
VAR_INPUT
  initialSetpoint : REAL;
END_VAR
  _setpoint := initialSetpoint;
  _enabled := TRUE;
  Start := TRUE;
END_METHOD

METHOD PUBLIC Stop : BOOL
  _enabled := FALSE;
  _output := 0.0;
  Stop := TRUE;
END_METHOD

PROPERTY PUBLIC Temperature : REAL
// GET accessor
GET
VAR
END_VAR
  Temperature := _temperature;
END_GET
// SET accessor
SET
VAR
END_VAR
  _temperature := Temperature;
END_SET
END_PROPERTY
