{attribute 'qualified_only'}
VAR_GLOBAL
  GVL_Main : INT;
  GVL_Counter : DINT;
END_VAR

{attribute 'pack_mode' := '1'}
TYPE ST_Packed :
STRUCT
  field1 : BYTE;
  field2 : DWORD;
  field3 : BOOL;
END_STRUCT
END_TYPE
