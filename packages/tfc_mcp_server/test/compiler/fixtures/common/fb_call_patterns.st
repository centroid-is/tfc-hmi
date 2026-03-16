PROGRAM FbCallTest
VAR
  timer1 : TON;
  motor : FB_Motor;
  result : REAL;
  elapsed : BOOL;
  capturedOutput : REAL;
END_VAR
  // Simple FB call
  timer1(IN := TRUE, PT := T#5s);
  elapsed := timer1.Q;

  // FB call with output capture
  motor(bStart := TRUE, rSetSpeed := 75.0, rActSpeed => capturedOutput);

  // Function call (positional)
  result := ABS(-42.0);

  // Function call (named)
  result := LIMIT(MN := 0.0, IN := result, MX := 100.0);

  // Chained member access
  result := motor.rActSpeed;
END_PROGRAM
