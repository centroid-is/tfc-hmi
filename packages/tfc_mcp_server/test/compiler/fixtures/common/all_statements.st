PROGRAM StatementTests
VAR
  i, j, state : INT;
  running : BOOL;
  speed, temp : REAL;
END_VAR
  // Simple assignment
  i := 42;

  // IF statement
  IF running THEN
    speed := 100.0;
  END_IF;

  // IF-ELSIF-ELSE
  IF temp > 80.0 THEN
    speed := 0.0;
  ELSIF temp > 60.0 THEN
    speed := 50.0;
  ELSIF temp > 40.0 THEN
    speed := 75.0;
  ELSE
    speed := 100.0;
  END_IF;

  // CASE statement
  CASE state OF
    0: speed := 0.0;
    1: speed := 50.0;
    2, 3: speed := 75.0;
    4..10: speed := 100.0;
  ELSE
    speed := 0.0;
  END_CASE;

  // FOR loop
  FOR i := 0 TO 9 DO
    j := j + i;
  END_FOR;

  // FOR with BY
  FOR i := 10 TO 0 BY -1 DO
    j := j + i;
  END_FOR;

  // WHILE loop
  WHILE running DO
    i := i + 1;
    IF i > 100 THEN
      running := FALSE;
    END_IF;
  END_WHILE;

  // REPEAT loop
  REPEAT
    i := i - 1;
  UNTIL i <= 0
  END_REPEAT;

  // EXIT
  FOR i := 0 TO 100 DO
    IF i = 50 THEN
      EXIT;
    END_IF;
  END_FOR;

  // RETURN
  RETURN;
END_PROGRAM
