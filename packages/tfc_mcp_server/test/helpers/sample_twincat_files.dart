// ---------------------------------------------------------------------------
// Sample TwinCAT file content for testing parsers and services.
//
// These const strings provide known-good fixtures for testing zip extraction,
// XML parsing, and structured text variable parsing. Formats verified against
// real TwinCAT project files from Beckhoff/ADS and tcunit/TcUnit repositories.
// ---------------------------------------------------------------------------

/// A Function Block TcPOU with VAR/VAR_INPUT/VAR_OUTPUT declarations
/// and a structured text implementation body.
///
/// Known variables for test assertions:
/// - `bStartTest : BOOL` (VAR)
/// - `nCounter : INT` (VAR)
/// - `nInput : INT` (VAR_INPUT)
/// - `bResult : BOOL` (VAR_OUTPUT)
const String sampleTcPouXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">
  <POU Name="FB_TestBlock" Id="{ac002873-776d-4096-82aa-e6da7e9c1d13}" SpecialFunc="None">
    <Declaration><![CDATA[FUNCTION_BLOCK FB_TestBlock
VAR
    bStartTest : BOOL := FALSE;
    nCounter : INT;
END_VAR
VAR_INPUT
    nInput : INT;
END_VAR
VAR_OUTPUT
    bResult : BOOL;
END_VAR
]]></Declaration>
    <Implementation>
      <ST><![CDATA[IF bStartTest THEN
    nCounter := nCounter + nInput;
    bResult := nCounter > 100;
END_IF]]></ST>
    </Implementation>
  </POU>
</TcPlcObject>
''';

/// A Program TcPOU with one Method, one Action, and one Property child
/// element. Tests child block extraction.
///
/// Children:
/// - Method `DoSomething` with VAR_INPUT `param1 : INT`
/// - Action `Reset` with implementation body
/// - Property `IsRunning` with a Get accessor
const String sampleTcPouWithMethodsXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">
  <POU Name="MAIN" Id="{bc002873-776d-4096-82aa-e6da7e9c1d14}" SpecialFunc="None">
    <Declaration><![CDATA[PROGRAM MAIN
VAR
    byByte AT %MB0 : ARRAY [0..1027] OF BYTE;
    bStartTest : BOOL := FALSE;
END_VAR
]]></Declaration>
    <Implementation>
      <ST><![CDATA[IF bStartTest THEN
    DoSomething(param1 := 42);
END_IF]]></ST>
    </Implementation>
    <Method Name="DoSomething" Id="{cd002873-776d-4096-82aa-e6da7e9c1d15}">
      <Declaration><![CDATA[METHOD DoSomething : BOOL
VAR_INPUT
    param1 : INT;
END_VAR]]></Declaration>
      <Implementation>
        <ST><![CDATA[DoSomething := param1 > 0;]]></ST>
      </Implementation>
    </Method>
    <Action Name="Reset" Id="{de002873-776d-4096-82aa-e6da7e9c1d16}">
      <Implementation>
        <ST><![CDATA[bStartTest := FALSE;]]></ST>
      </Implementation>
    </Action>
    <Property Name="IsRunning" Id="{ef002873-776d-4096-82aa-e6da7e9c1d17}">
      <Declaration><![CDATA[PROPERTY IsRunning : BOOL]]></Declaration>
      <Get Name="Get" Id="{f0002873-776d-4096-82aa-e6da7e9c1d18}">
        <Declaration><![CDATA[VAR
END_VAR]]></Declaration>
        <Implementation>
          <ST><![CDATA[IsRunning := bStartTest;]]></ST>
        </Implementation>
      </Get>
    </Property>
  </POU>
</TcPlcObject>
''';

/// A Global Variable List (GVL) with `{attribute 'qualified_only'}` and
/// 3 variables. Tests GVL parsing and qualified name extraction.
///
/// Variables:
/// - `pump3_speed : REAL`
/// - `pump3_running : BOOL`
/// - `tank_level : REAL`
const String sampleTcGvlXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.0">
  <GVL Name="GVL_Main" Id="{4975d35a-db23-4a9a-b95d-73c3ef0475d8}">
    <Declaration><![CDATA[{attribute 'qualified_only'}
VAR_GLOBAL
    pump3_speed : REAL;
    pump3_running : BOOL;
    tank_level : REAL;
END_VAR]]></Declaration>
  </GVL>
</TcPlcObject>
''';

/// Raw structured text file (not XML) with `PROGRAM` header,
/// VAR block, and implementation body. Tests .st file parsing.
///
/// Variables:
/// - `bRunning : BOOL` (VAR)
/// - `nSpeed : INT` (VAR)
/// - `fTemperature : REAL` (VAR)
const String sampleStFile = '''PROGRAM MainProgram
VAR
    bRunning : BOOL;
    nSpeed : INT := 100;
    fTemperature : REAL;
END_VAR

IF bRunning THEN
    nSpeed := nSpeed + 1;
    IF nSpeed > 200 THEN
        nSpeed := 200;
    END_IF
END_IF
END_PROGRAM
''';

/// A Function Block TcPOU with both `(* block comments *)` and
/// `// line comments` in declaration and implementation.
/// Tests that comments are preserved in fullSource for search indexing.
///
/// Comments contain:
/// - Line comment in declaration: `// Motor speed in RPM`
/// - Block comment in declaration: `(* Currently running *)`
/// - Block comment in implementation: `(* This block controls the motor speed. *)`
/// - Line comment in implementation: `// Check if motor is active`
/// - Line comment in implementation: `// Ramp up by 10 RPM`
const String sampleTcPouWithCommentsXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<TcPlcObject Version="1.1.0.1" ProductVersion="3.1.4024.5">
  <POU Name="FB_WithComments" Id="{ab002873-776d-4096-82aa-e6da7e9c1d19}" SpecialFunc="None">
    <Declaration><![CDATA[FUNCTION_BLOCK FB_WithComments
VAR
    nSpeed : INT; // Motor speed in RPM
    bActive : BOOL; (* Currently running *)
END_VAR
]]></Declaration>
    <Implementation>
      <ST><![CDATA[(* This block controls the motor speed.
   It ramps up gradually to avoid mechanical stress. *)
// Check if motor is active
IF bActive THEN
    nSpeed := nSpeed + 10; // Ramp up by 10 RPM
END_IF]]></ST>
    </Implementation>
  </POU>
</TcPlcObject>
''';
