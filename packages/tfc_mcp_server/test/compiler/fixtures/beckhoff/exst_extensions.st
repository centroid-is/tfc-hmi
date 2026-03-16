PROGRAM ExstTest
VAR
  latchOn : BOOL;
  latchOff : BOOL;
  triggerSet : BOOL;
  triggerReset : BOOL;
  ptrVal : POINTER TO INT;
  refVal : REFERENCE TO REAL;
  someInt : INT;
  someReal : REAL;
  i : INT;
END_VAR
  // S= (set/latch) operator
  latchOn S= triggerSet;

  // R= (reset) operator
  latchOff R= triggerReset;

  // POINTER operations
  ptrVal := ADR(someInt);
  someInt := ptrVal^;

  // REFERENCE operations
  refVal REF= someReal;

  // CONTINUE in loop
  FOR i := 0 TO 10 DO
    IF i = 5 THEN
      CONTINUE;
    END_IF;
    someInt := someInt + i;
  END_FOR;
END_PROGRAM
