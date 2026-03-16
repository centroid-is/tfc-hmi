PROGRAM ExpressionTests
VAR
  a, b, c : INT;
  x, y : REAL;
  flag1, flag2, flag3 : BOOL;
  str1 : STRING[80];
  arr : ARRAY[1..10] OF INT;
END_VAR
  // Arithmetic
  a := 1 + 2;
  a := b - c;
  a := b * c;
  a := b / c;
  a := b MOD c;
  x := -y;

  // Comparison
  flag1 := a = b;
  flag1 := a <> b;
  flag1 := a < b;
  flag1 := a > b;
  flag1 := a <= b;
  flag1 := a >= b;

  // Boolean
  flag1 := flag2 AND flag3;
  flag1 := flag2 OR flag3;
  flag1 := flag2 XOR flag3;
  flag1 := NOT flag2;

  // Parenthesized
  a := (b + c) * 2;

  // Array access
  a := arr[1];
  arr[b + 1] := c;

  // Typed literals
  a := INT#42;
  x := REAL#3.14;

  // Time literal
  // (comment out for now - just have the file ready)

  // Nested expressions with precedence
  x := 1.0 + 2.0 * 3.0;
  flag1 := (a > 0) AND (b < 10) OR (c = 5);
END_PROGRAM
