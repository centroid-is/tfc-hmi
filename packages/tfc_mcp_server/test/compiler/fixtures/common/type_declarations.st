TYPE MotorState :
(
  Idle := 0,
  Starting := 1,
  Running := 2,
  Stopping := 3,
  Faulted := 4
);
END_TYPE

TYPE ST_MotorData :
STRUCT
  speed : REAL;
  current : REAL;
  temperature : REAL;
  state : MotorState;
  faultCode : DINT;
  name : STRING[32];
END_STRUCT
END_TYPE

TYPE AliasType : REAL;
END_TYPE
