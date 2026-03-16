FUNCTION FC_Clamp : REAL
VAR_INPUT
  value : REAL;
  minVal : REAL;
  maxVal : REAL;
END_VAR
  IF value < minVal THEN
    FC_Clamp := minVal;
  ELSIF value > maxVal THEN
    FC_Clamp := maxVal;
  ELSE
    FC_Clamp := value;
  END_IF;
END_FUNCTION
