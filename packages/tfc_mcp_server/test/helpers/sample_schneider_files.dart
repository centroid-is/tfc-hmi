// ---------------------------------------------------------------------------
// Sample Schneider PLC export files for testing parsers.
//
// These const strings provide known-good fixtures for testing Schneider
// Control Expert XEF and Machine Expert PLCopen XML parsing.
// ---------------------------------------------------------------------------

/// A Control Expert XEF-style export with a Function Block.
///
/// Contains an `<FBSource>` element with:
/// - objectName: FB_PumpControl
/// - sourceCode with FUNCTION_BLOCK declaration, VAR blocks, and implementation
/// - variables section with XML-declared variables
const String sampleControlExpertFB = '''<?xml version="1.0" encoding="utf-8"?>
<FBSource nameOfFBType="DFB" version="0.04">
  <objectName>FB_PumpControl</objectName>
  <variables>
    <variable name="bEnable" typeName="BOOL" class="INPUT"/>
    <variable name="rSetpoint" typeName="REAL" class="INPUT"/>
    <variable name="rActualSpeed" typeName="REAL" class="OUTPUT"/>
    <variable name="bRunning" typeName="BOOL" class="LOCAL"/>
    <variable name="nErrorCode" typeName="INT" class="LOCAL"/>
  </variables>
  <sourceCode>FUNCTION_BLOCK FB_PumpControl
VAR_INPUT
    bEnable : BOOL;
    rSetpoint : REAL;
END_VAR
VAR_OUTPUT
    rActualSpeed : REAL;
END_VAR
VAR
    bRunning : BOOL;
    nErrorCode : INT;
END_VAR

IF bEnable THEN
    bRunning := TRUE;
    rActualSpeed := rSetpoint * 0.95;
ELSE
    bRunning := FALSE;
    rActualSpeed := 0.0;
    nErrorCode := 0;
END_IF
END_FUNCTION_BLOCK</sourceCode>
</FBSource>
''';

/// A Control Expert XEF-style export with an ST section (Program).
///
/// Contains an `<STSource>` element with:
/// - objectName: MainTask
/// - sourceCode with PROGRAM declaration
const String sampleControlExpertST = '''<?xml version="1.0" encoding="utf-8"?>
<STSource>
  <objectName>MainTask</objectName>
  <sourceCode>PROGRAM MainTask
VAR
    bAutoMode : BOOL;
    rTemperature : REAL;
    nCycleCount : DINT;
END_VAR

IF bAutoMode THEN
    nCycleCount := nCycleCount + 1;
END_IF
END_PROGRAM</sourceCode>
</STSource>
''';

/// A PLCopen XML export with a Function Block (Machine Expert style).
///
/// Contains a `<project>` with `<types><pous><pou>` structure.
/// The pou has:
/// - name: FB_ValveControl
/// - pouType: functionBlock
/// - interface with inputVars, outputVars, localVars
/// - body with ST implementation
/// - An action child: Reset
const String samplePlcopenFB = '''<?xml version="1.0" encoding="utf-8"?>
<project xmlns="http://www.plcopen.org/xml/tc6_0201">
  <types>
    <pous>
      <pou name="FB_ValveControl" pouType="functionBlock">
        <interface>
          <inputVars>
            <variable name="bOpen">
              <type><BOOL/></type>
              <documentation><xhtml>Command to open valve</xhtml></documentation>
            </variable>
            <variable name="rPosition">
              <type><REAL/></type>
            </variable>
          </inputVars>
          <outputVars>
            <variable name="bIsOpen">
              <type><BOOL/></type>
            </variable>
            <variable name="rFeedback">
              <type><REAL/></type>
            </variable>
          </outputVars>
          <localVars>
            <variable name="nState">
              <type><INT/></type>
            </variable>
            <variable name="tDelay">
              <type><TIME/></type>
            </variable>
          </localVars>
        </interface>
        <body>
          <ST>
            <xhtml>IF bOpen THEN
    nState := 1;
    bIsOpen := TRUE;
    rFeedback := rPosition;
ELSE
    nState := 0;
    bIsOpen := FALSE;
    rFeedback := 0.0;
END_IF</xhtml>
          </ST>
        </body>
        <action name="Reset">
          <body>
            <ST>
              <xhtml>nState := 0;
bIsOpen := FALSE;
rFeedback := 0.0;</xhtml>
            </ST>
          </body>
        </action>
      </pou>
    </pous>
  </types>
</project>
''';

/// A PLCopen XML export with a Program.
///
/// Contains a single POU of type "program" with simple variables.
const String samplePlcopenProgram = '''<?xml version="1.0" encoding="utf-8"?>
<project xmlns="http://www.plcopen.org/xml/tc6_0201">
  <types>
    <pous>
      <pou name="PLC_PRG" pouType="program">
        <interface>
          <localVars>
            <variable name="bStart">
              <type><BOOL/></type>
            </variable>
            <variable name="nCounter">
              <type><DINT/></type>
            </variable>
            <variable name="sMessage">
              <type><string length="80"/></type>
            </variable>
          </localVars>
        </interface>
        <body>
          <ST>
            <xhtml>IF bStart THEN
    nCounter := nCounter + 1;
END_IF</xhtml>
          </ST>
        </body>
      </pou>
    </pous>
  </types>
</project>
''';

/// A PLCopen XML export with global variables.
///
/// Contains a `<globalVars>` section under `<types>`.
const String samplePlcopenGlobalVars = '''<?xml version="1.0" encoding="utf-8"?>
<project xmlns="http://www.plcopen.org/xml/tc6_0201">
  <types>
    <globalVars name="GVL_Process">
      <variable name="rTankLevel">
        <type><REAL/></type>
        <documentation><xhtml>Tank level in percent</xhtml></documentation>
      </variable>
      <variable name="bAlarmActive">
        <type><BOOL/></type>
      </variable>
      <variable name="nPumpSpeed">
        <type><INT/></type>
        <documentation><xhtml>Pump speed in RPM</xhtml></documentation>
      </variable>
    </globalVars>
    <pous/>
  </types>
</project>
''';

/// A PLCopen XML with a Function Block using derived types and arrays.
///
/// Tests parsing of complex type declarations.
const String samplePlcopenComplexTypes = '''<?xml version="1.0" encoding="utf-8"?>
<project xmlns="http://www.plcopen.org/xml/tc6_0201">
  <types>
    <pous>
      <pou name="FB_DataLogger" pouType="functionBlock">
        <interface>
          <inputVars>
            <variable name="stConfig">
              <type><derived name="ST_LoggerConfig"/></type>
            </variable>
            <variable name="aValues">
              <type>
                <array>
                  <dimension lower="0" upper="9"/>
                  <baseType><REAL/></baseType>
                </array>
              </type>
            </variable>
          </inputVars>
          <localVars>
            <variable name="nIndex">
              <type><INT/></type>
            </variable>
          </localVars>
        </interface>
        <body>
          <ST>
            <xhtml>nIndex := nIndex + 1;</xhtml>
          </ST>
        </body>
      </pou>
    </pous>
  </types>
</project>
''';

/// A Control Expert export with multiple source blocks in one file.
///
/// Contains both an FBSource and an STSource to test multi-block extraction.
const String sampleControlExpertMultiBlock = '''<?xml version="1.0" encoding="utf-8"?>
<ExchangeFile>
  <FBSource nameOfFBType="DFB" version="0.01">
    <objectName>FB_Motor</objectName>
    <sourceCode>FUNCTION_BLOCK FB_Motor
VAR_INPUT
    bStart : BOOL;
END_VAR
VAR
    bRunning : BOOL;
END_VAR

bRunning := bStart;
END_FUNCTION_BLOCK</sourceCode>
  </FBSource>
  <STSource>
    <objectName>ST_Logic</objectName>
    <sourceCode>PROGRAM ST_Logic
VAR
    fbMotor1 : FB_Motor;
END_VAR

fbMotor1(bStart := TRUE);
END_PROGRAM</sourceCode>
  </STSource>
</ExchangeFile>
''';
