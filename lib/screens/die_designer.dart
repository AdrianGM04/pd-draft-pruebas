import 'package:flutter/material.dart';
import 'dart:math';                              // ← para json.decode
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart'  as printing;
import 'dart:io' show File;       // ← sólo se compila en móvil/desktop
import 'package:flutter/cupertino.dart';   // para el icono “X”
import 'package:pdf/pdf.dart' as pdf; //
import 'dart:typed_data';

  enum CaptureMode { 
    normal, finishedDie, construction 
  }

  // ─────────  NUEVOS AJUSTES DE ANCHO / ESPACIO  ─────────
const double kFieldWidth   = 150.0;   // antes 240
const double kPartNumberWidth = 260.0;   // ancho deseado
const double kWrapSpacing  = 6.0;     // antes 12

const double kExtraRight = 230;   // margen para la cota vertical
const double kExtraDown  = 160;   // margen inferior
// ───────── Códigos de ángulo (pos. 5-6 del PN) ─────────
const Map<String, double> kAngleByCode = {

  // valores exclusivamente numéricos
  '05': 5,   '06': 6,  '08': 8,  '09': 9,
  '10': 10,  '12': 12, '14': 14, '16': 16,
  '18': 18,  '20': 20,
  // combinaciones con letra
  '6J': 6, '8J': 8, '9J': 9, '12J': 12, '16J': 16, '26J': 26,
  '9P': 9, '12P': 12, '16P': 16, '18P': 18,
  '10B':10, '12B': 12,
  '12S': 12,
  '12F': 12,

  '12T': 12,   
  '16E': 16,   
};

// ─── Color corporativo ─────────────────────────────────────────
const kPdRed = Color(0xFFE51937);

// === Colores de las zonas del inserto (A/B/C) ===
const Color _colA = Color.fromARGB(255, 100, 100, 100);
const Color _colB = Color.fromARGB(255, 140, 140, 140);
const Color _colC = Color.fromARGB(255, 180, 180, 180);

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: kPdRed,

        // ───── 1.  Botones globales ─────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith<Color>(
              (states) => states.contains(WidgetState.disabled)
                  ? Colors.white                 // deshabilitado
                  : kPdRed,                      // habilitado
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color>(
              (states) => states.contains(WidgetState.disabled)
                  ? kPdRed
                  : Colors.white,
            ),
            side: WidgetStateProperty.resolveWith<BorderSide?>(
              (states) => states.contains(WidgetState.disabled)
                  ? const BorderSide(color: kPdRed, width: 1.4)
                  : null,
            ),
          ),
        ),

        // ───── 2.  Switch global ─────
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(Colors.black),
          trackColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.selected)
                ? kPdRed               // ON
                : Colors.white,        // OFF
          ),
          trackOutlineColor:
              WidgetStateProperty.all(kPdRed.withOpacity(0.8)),
        ),

        // ───── 3.  Cursor & selección de texto ─────
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: kPdRed,
          selectionColor: Color(0x1AE51937),      // rojo 10 % opacidad
          selectionHandleColor: kPdRed,
        ),

        // ───── 4.  Borde rojo para TODOS los campos ─────
        inputDecorationTheme: const InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: kPdRed, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black45),
          ),
          floatingLabelStyle:
              TextStyle(color: kPdRed, fontWeight: FontWeight.w600),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        ),

        // ───── 5.  Asegurar mismo borde en DropdownButtonFormField ─────
        dropdownMenuTheme: const DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: kPdRed, width: 1.4),
            ),
          ),
        ),
      ),
      home: const DieDesignerScreen(),
    ),
  );
}

class DieDesignerScreen extends StatefulWidget {
  final double? naranjaL;       // left entry height of the die (in mm)
  final double? barraLength;    // insert length (in mm)
  final double? alturaInicial;  // initial wire diameter at entry (in mm)
  final double? reductionAngle; // reduction angle (in degrees)
  final String? selectedSystem;
  final List<double>? customDeltaRange;

  const DieDesignerScreen({
    super.key,
    this.naranjaL,
    this.barraLength,
    this.alturaInicial,
    this.reductionAngle,
    this.selectedSystem,
    this.customDeltaRange,
    
  });

  @override
  State<DieDesignerScreen> createState() => _DieDesignerScreenState();
}
// Dimensiones físicas del bloque (cuerpo) por die type
class DieDims {
  final double widthMm;
  final double heightMm;
  const DieDims(this.widthMm, this.heightMm);
}

const Map<String, DieDims> kDieDims = {
  'TR4' : DieDims(11.430, 12.700),
  'TR4D': DieDims(11.430, 12.700),
  'TR6' : DieDims(17.780, 18.034),
  'TR8' : DieDims(21.082, 25.400),
};

// ───────── Back-Relief DIÁMETRO FIJO por tipo de dado (mm) ─────────
const Map<String, double> kBackReliefDiaMmByDie = {
  'TR4' :  6.35,   // EJEMPLOS — cámbialos por tus valores nominales
  'TR4D':  3.81,
  'TR6' : 12.70,
  'TR8' : 15.88,
};

double _fixedBackReliefDiaMmFor(String die) =>
    kBackReliefDiaMmByDie[die] ?? kBackReliefDiaMmByDie['TR4']!;

// seguridad: nunca menor que el Finished
double _backReliefDiaMmFromFixed(String die, double finishedMm) {
  final br = _fixedBackReliefDiaMmFor(die);
  return (br >= finishedMm) ? br : finishedMm;
}


class _DieVisual {
  final double dieW, dieH, refW, refH, sx, sy;
  final double angSup, angInf;
  const _DieVisual({
    required this.dieW, required this.dieH,
    required this.refW, required this.refH,
    required this.sx, required this.sy,
    required this.angSup, required this.angInf,
  });
}

class _DieDesignerScreenState extends State<DieDesignerScreen> {
  double naranjaL = 8.106;     // left die height in mm (user-defined or default)
  double barraLength = 1.5;   // insert bar length in mm
  double naranjaR = 4.00;      // right die height in mm (computed from bar length)
  double alturaInicial = 2.0; // initial insert height (wire diameter)
  double reductionAngle = 16;  // reduction angle in degrees
  double angleSuperior = 30; // yellow slope (entrada)
  double angleInferior = 30; // purple slope (salida)
  double blMinPercent = 30;   // Minimum Bearing Length (%)  (0‒100)
  double blMaxPercent = 50;   // Maximum Bearing Length (%)
  double _yOffsetPx = 35; // desplazamiento vertical (px). + sube, - baja
  double _xOffsetPx = -150;
  // en _DieDesignerScreenState
  double _secondCanvasDx = 120; // píxeles adicionales hacia la derecha (ajústalo)

// ——— Rango Δ por material, con fallback a 'Custom' ———
List<double> _rangeOf(String grade) {
  // Si el grade no existe en el mapa, usa 'Custom'
  return _deltaRanges[grade] ?? _deltaRanges['Custom']!;
}
  // Lado izquierdo (principal)
  double get _deltaMin  => _rangeOf(_selectedGrade)[0];
  double get _deltaMax  => _rangeOf(_selectedGrade)[1];

  // Lado derecho (Compare)
  double get _deltaMin2 => _rangeOf(_selectedGrade2)[0];
  double get _deltaMax2 => _rangeOf(_selectedGrade2)[1];
  String _selectedGrade = kGrades.first;   // valor por defecto: 'Custom'
  String _selectedGrade2 = kGrades.first; // por defecto igual al izquierdo
  bool _copyLeftToRight = false; // checkbox
  
  // Reemplaza el método existente _deltaColorFor por este:
  Color _deltaColorFor(String grade, double d) {
    final range = _deltaRanges[grade]!;
    final double min = range[0];
    final double max = range[1];

    if (d.isNaN || d.isInfinite || d <= 0) {
      return Colors.redAccent;
    }

    final bool inGreen       = (d >= min && d <= max);
    final bool inYellowLeft  = (d >= 0.8 * min && d < min);
    final bool inYellowRight = (d >  max && d <= 1.2 * max);

    if (inGreen) return Colors.greenAccent;
    if (inYellowLeft || inYellowRight) return const Color(0xFFFACC15); // amarillo
    return Colors.redAccent;
  }

  // === Δ-Factor UI helpers ===
  static const _kReadOnlyGrey = Color(0xFFEFEFEF);

  bool get _gradeIsNone  => _selectedGrade  == 'None';
  bool get _grade2IsNone => _selectedGrade2 == 'None';

  // Color de fondo del Δ (izquierda)
  Color get _deltaFillLeft {
    if (_gradeIsNone) return _kReadOnlyGrey;
    final d = _deltaFactor;
    return _deltaColorFor(_selectedGrade, d);
  }
  // Color de fondo del Δ (derecha)
  Color _deltaFillRight() {
    if (_grade2IsNone) return _kReadOnlyGrey;
    final d2 = _deltaFactorOf(
      entryMm: alturaInicial2 / 10.0,
      finishedMm: barraLength2 / 10.0,
      angleDeg: reductionAngle2,
    );
    return _deltaColorFor(_selectedGrade2, d2);
  }

  // ====== Estado independiente (lado derecho en Compare) ======
  double naranjaL2       = 8.106 * 10;   // décimas (igual que las tuyas)
  double barraLength2    = 1.6   * 10;   // décimas
  double naranjaR2       = 4.0   * 10;   // décimas (se recalcula por fórmula)
  double alturaInicial2  = 2.0   * 10;   // décimas
  double reductionAngle2 = 16;           // grados
  double blMinPercent2   = 30;
  double blMaxPercent2   = 50;
  double azulOffsetX2    = 0;

  // Controllers del lado derecho
  final TextEditingController barraLengthController2    = TextEditingController();
  final TextEditingController alturaInicialController2  = TextEditingController();
  final TextEditingController reductionAngleController2 = TextEditingController();
  final TextEditingController blMinController2          = TextEditingController();
  final TextEditingController blMaxController2          = TextEditingController();
  final TextEditingController reductionAreaController2  = TextEditingController();
  final TextEditingController deltaController2          = TextEditingController();
  final TextEditingController minDeltaController = TextEditingController();
  final TextEditingController maxDeltaController = TextEditingController();
  // ============================================================

// arriba en tu State (ya importas dart:math)
double get _maxDieWidthMm =>
    kDieDims.values.map((d) => d.widthMm).reduce(max);

  // Tamaño actual del dado (mm). Se setean con _applyDieType()
  double _dieWidthMm  = kDieDims['TR4']!.widthMm;
  double _dieHeightMm = kDieDims['TR4']!.heightMm;

    // Referencia visual: SIEMPRE dibujamos el bloque al tamaño TR4
  double _refWidthMm  = kDieDims['TR4']!.widthMm;   // 11.430
  double _refHeightMm = kDieDims['TR4']!.heightMm;  // 12.700

  // Factores de escala para convertir mm→px cuando el físico ≠ visual
  double _sx = 1.0;  // horizontal (mm→px)
  double _sy = 1.0;  // vertical   (mm→px)

  double _parseMm(TextEditingController c, double fallback) {
    // admite coma o punto
    final s = c.text.trim().replaceAll(',', '.');
    final v = double.tryParse(s);
    return (v != null && v > 0) ? v : fallback;
  }

  double? _pendingBackReliefMm; // Back Relief Diameter in mm (optional, computed from PN)
  String _unit() => _showInches ? 'in' : 'mm';
  int get _dec => _showInches ? 4 : 3;

  static const double kStageW = 1280; // ancho base de tu página
  static const double kStageH = 900;  // alto base de tu página
  static const double kCanvasHNormal  = 420; // alto del área del dibujo
  static const double kCanvasHCapture = 650; // cuando capturas PDF

    // ───── Lista y selección actual del “Grade” ─────
  static const List<String> kGrades = [
    'None', 'Custom', 'Low Carbon', 'High Carbon', 'Stainless'
  ];

  // Separación entre las dos columnas del panel de Compare
  static const double kCompareMiddleGap = 320.0; // ajusta 200–480 a tu gusto

  // Ajustes finos opcionales (desplazamientos pequeños por columna)
  static const double kLeftNudge  = 0.0;   // pon -10, -20 si quieres más a la IZQ
  static const double kRightNudge = 0.0;   // pon 10,  20 si quieres más a la DER

  // Rango Delta Factor Δ para cada grado
  static Map<String, List<double>> _deltaRanges = {
    'None'       : [0.00, 99.99], // sin restricción
    'Custom'     : [1.00, 2.00],
    'Low Carbon' : [1.30, 2.25],
    'High Carbon': [1.20, 1.89],
    'Stainless'  : [1.35, 2.25],
  };

  //  justo debajo de _selectedGrade
  static const List<String> _dieTypes = ['TR4', 'TR4D', 'TR6', 'TR8'];
  String _selectedDieType = _dieTypes.first;     // valor por defecto: TR4

  // ─── Compare Die ───────────────────────────────────────────────
bool _compare = false;
String _secondDieType = 'TR4';

/// Calcula los “visuales” (W/H reales, marco de referencia visual TR4 y escalas) para un die.
_DieVisual _visualForDie(String die) {
  final dims = kDieDims[die]!;
  double refW, refH;
  final areaRef = kDieDims['TR4']!.widthMm * kDieDims['TR4']!.heightMm;
  if (die == 'TR6' || die == 'TR8') {
    final ratio = dims.widthMm / dims.heightMm;
    final wVis  = sqrt(areaRef * ratio);
    final hVis  = areaRef / wVis;
    refW = wVis; refH = hVis;
  } else {
    refW = kDieDims['TR4']!.widthMm;
    refH = kDieDims['TR4']!.heightMm;
  }
  final sx = refW / dims.widthMm;
  final sy = refH / dims.heightMm;
  final angSup = (die == 'TR4D') ? 45.0 : 30.0;
  final angInf = (die == 'TR4D') ? 45.0 : 30.0;
  return _DieVisual(
    dieW: dims.widthMm, dieH: dims.heightMm,
    refW: refW, refH: refH, sx: sx, sy: sy,
    angSup: angSup, angInf: angInf,
  );
}

/// Recalcula la X del inserto (azul) para un die visual dado, manteniendo ±30° (o 45° en TR4D).
double _computeAzulXFor(
  _DieVisual dv, {
  required double naranjaRdec,     // décimas
  required double cafeGrisLenDec,  // décimas
  required double barraLenDec,     // décimas (Finished)
}) {
  double pxX(double dec) => decToMm(dec) * pxPerMm * dv.sx;
  double pxY(double dec) => decToMm(dec) * pxPerMm * dv.sy;

  final centerY       = _borderTopPx + dv.refH * pxPerMm / 2;
  final cafeGrisLenPx = pxX(cafeGrisLenDec);
  final rightRefX     = _borderLeftPx + dv.refW * pxPerMm;

  final p9y    = centerY - pxY(naranjaRdec) / 2;
  final p10y   = centerY + pxY(naranjaRdec) / 2;
  final cafeRy = centerY - pxY(barraLenDec) / 2;
  final grisRy = centerY + pxY(barraLenDec) / 2;

  final dxUp     = (p9y   - cafeRy) / tan(dv.angSup * pi / 180);
  final dxDown   = (grisRy - p10y ) / tan(dv.angInf * pi / 180);
  final dxNeeded = max(dxUp.abs(), dxDown.abs());

  return rightRefX - dxNeeded - cafeGrisLenPx / 2;
}

  final GlobalKey _captureKey = GlobalKey();   // RepaintBoundary
  CaptureMode _mode = CaptureMode.normal;      // modo actual

  // Controllers for handling user input fields
  final TextEditingController barraLengthController = TextEditingController();
  final TextEditingController naranjaLController = TextEditingController();
  final TextEditingController alturaInicialController = TextEditingController();
  final TextEditingController reductionAngleController = TextEditingController();
  final TextEditingController blMinController = TextEditingController();
  final TextEditingController blMaxController = TextEditingController();

  // --- PMP -----------------------------------------------------------
  final TextEditingController _pmpController = TextEditingController();
  String _pmpLabel = '';       
  // -------------------------------------------------------------------
  
  // para pintar en rojo el Finished Die Diameter textbox cuando esté fuera de rango
  bool _fdOutOfRange = false; 

  //Delta Factor
  final TextEditingController deltaController = TextEditingController();

  //Reduction Area (%)
  final TextEditingController reductionAreaController = TextEditingController();

  double azulOffsetX = 0; // horizontal position of insert center (pixels)

  // ──────────  UNIDADES ──────────
  bool _showInches = false;          // false = mm, true = in
  static const double _mmPerIn = 25.4;

  bool _showConstruction = false; // controla visibilidad de los 4 elementos

  double? _lastPmpIn;                              // PMP calculado (in)
  final TextEditingController pmpController =      // textbox de sólo-lectura
      TextEditingController();

  // --- helpers de conversión ---
  static const double pxPerMm = 30.0;          // 30 px = 1 mm
  double decToPx(double dec) => (dec / 10) * pxPerMm;   // décimas → px
  double decToMm(double dec) =>  dec / 10;               // décimas → mm
  // ------------------------------  

  // ­——— coinciden con los que usa el CustomPainter ———
  static const double _borderLeftPx = 475.0;   // X donde empieza el dado
  static const double _borderTopPx  =  50.0;   // Y donde empieza el dado

  // ── Margen para que las cotas no se recorten en el PDF ──
  static const double kExtraRight = 230;  // espacio a la derecha
  static const double kExtraDown  = 160;  // espacio abajo

  // ---------- Helpers longitud (mm ⇄ in) ----------
  /// Devuelve la longitud en la unidad actual (mm ↔ in)
  String _fmtLen(double mm) => _showInches
      ? (mm / _mmPerIn).toStringAsFixed(_dec)  // 4 dec. si son pulgadas
      : mm.toStringAsFixed(_dec);              // 3 dec. si son mm


    double? _parseLen(String txt) {           // lee SIEMPRE en mm
      final v = double.tryParse(txt);
      if (v == null) return null;
      return _showInches ? v * _mmPerIn : v;
    }

  void _applyDieType(String die) {
    final isD = die == 'TR4D';
    angleSuperior = isD ? 45 : 30;
    angleInferior = isD ? 45 : 30;

    final dims = kDieDims[die]!;
    _dieWidthMm  = dims.widthMm;
    _dieHeightMm = dims.heightMm;

    // ── Marco visual: TR6 y TR8 usan el mismo criterio (mantener área TR4 pero con su razón W/H)
    final areaRef = kDieDims['TR4']!.widthMm * kDieDims['TR4']!.heightMm;
    if (die == 'TR6' || die == 'TR8') {
      final ratio = _dieWidthMm / _dieHeightMm; // W/H del tipo
      final wVis  = sqrt(areaRef * ratio);
      final hVis  = areaRef / wVis;
      _refWidthMm  = wVis;
      _refHeightMm = hVis;
    } else {
      _refWidthMm  = kDieDims['TR4']!.widthMm;
      _refHeightMm = kDieDims['TR4']!.heightMm;
  }

  // escalas mm→px
  _sx = _refWidthMm  / _dieWidthMm;
  _sy = _refHeightMm / _dieHeightMm;

  _selectedDieType = die;

  final outDiaMm = barraLength / 10.0;
  setState(() {
    naranjaR = _backReliefDiameterMm(outDiaMm) * 10;
  });

  _recalculateAzulPosition();

  final pn = partNoController.text.trim().toUpperCase();
  if (pn.isNotEmpty && !_pnMatchesSelected(pn)) {
    setState(() {
      _usePart = false; _partFound = false; _partMsg = '';
      partNoController.clear();
      _pendingBackReliefMm = null;
    });
  }

    // Si Custom Die está OFF, forzamos un ángulo permitido
    _syncAngleInputWithMode();
}

  // ──────────  HELPERS pulgadas ↔ milímetros  ──────────
  static const double _inToMm = 25.4;
  double _inchToMm(num inch) => (inch * _inToMm).toDouble();
  double _mmToIn(num mm)     => (mm / _inToMm).toDouble();   // ← añadido
  String _fmtMm(num inch)    => _inchToMm(inch).toStringAsFixed(3);

  // 0.075" = 1.905 mm
  static const double _kBackReliefBaseMm = 1.905;

  /// Back‑Relief DIAMETER (mm) a partir del Finished Ø (mm).
  double _backReliefDiameterMm(double finishedMm) {
    final phi = angleSuperior * pi / 180; // angleSuperior es fijo por die
    final inc = 2 * (_kBackReliefBaseMm * tan(phi));
    return finishedMm + inc;
  }

  // Back-Relief DIAMETER (mm) con ángulo superior “propio” del dado.
double _backReliefDiameterMmWithAngle(double finishedMm, double upAngleDeg) {
  final phi = upAngleDeg * pi / 180;
  final inc = 2 * (_kBackReliefBaseMm * tan(phi));
  return finishedMm + inc;
}

  // 1️⃣  helper global
  void _invalidatePart() {
    if (_usePart) {
      setState(() {
        _usePart          = false;   // apaga el switch
        _partFound        = false;
        _partMsg          = '';
        partNoController.clear();
        _pendingBackReliefMm = null; // descartamos back-relief pendiente
      });
    }
  }

  // -------------- getters dinámicos ------------
  double get cafeGrisFactor => (blMinPercent + blMaxPercent) / 200;
  double get cafeGrisLengthDec => barraLength * cafeGrisFactor;

  //FinishedØ / EntryØ  × 100
// Reduction Area (%) estándar: ((Entry^2 − Finished^2) / Entry^2) × 100
double get _reductionAreaPercent {
  final double entryDiaMm    = alturaInicial / 10.0;  // Entry Diameter (mm)
  final double finishedDiaMm = barraLength  / 10.0;   // Finished Die Diameter (mm)
  if (entryDiaMm <= 0 || finishedDiaMm <= 0) return 0.0;

  final double e2 = entryDiaMm * entryDiaMm;
  final double f2 = finishedDiaMm * finishedDiaMm;
  return 100.0 * (e2 - f2) / e2;
}

    // Δ-Factor  (solo lo usamos para el PDF “Construction”)
  double get _deltaFactor {
    final din = alturaInicial / 10;   // décimas → mm
    final dout = barraLength / 10;

    if (din <= 0 || dout <= 0 || dout >= din) return 0;

    final r = 1 - pow(dout / din, 2);         // fracción de reducción de área
    if (r == 0) return 0;

    final alpha = (reductionAngle / 2) * pi / 180; // radianes
    return (alpha / r) * pow(1 + sqrt(1 - r), 2);
  }

  // lado derecho (Compare Die)==============
  double get cafeGrisFactor2 => (blMinPercent2 + blMaxPercent2) / 200;
  double get cafeGrisLengthDec2 => barraLength2 * cafeGrisFactor2;

  // Helpers paramétricos reutilizables
  double _reductionAreaPercentOf(double entryMm, double finishedMm) {
    if (entryMm <= 0 || finishedMm <= 0) return 0;
    final e2 = entryMm * entryMm, f2 = finishedMm * finishedMm;
    return 100.0 * (e2 - f2) / e2;
  }

  double _deltaFactorOf({
    required double entryMm,
    required double finishedMm,
    required double angleDeg,
  }) {
    if (entryMm <= 0 || finishedMm <= 0 || finishedMm >= entryMm) return 0;
    final r = 1 - pow(finishedMm / entryMm, 2);
    if (r == 0) return 0;
    final alpha = (angleDeg / 2) * pi / 180;
    return (alpha / r) * pow(1 + sqrt(1 - r), 2);
  }
  //=========================================

  /// Color semáforo para Δ-Factor
  Color get deltaColor {
    final d = _deltaFactor;
    final range = _deltaRanges[_selectedGrade]!;
    return (d >= range[0] && d <= range[1])
        ? Colors.greenAccent
        : Colors.redAccent;
  }
  
  // --- «Build by Part Number» ---
  List<Map<String, dynamic>> _rcDb = [];   // base de datos JSON

// ───────── Custom Die (por defecto encendido) ─────────
bool _customDie = true;

// Ángulos permitidos por Die Type cuando Custom Die está OFF
static const Map<String, List<int>> _presetAngles = {
  'TR4' : [9, 12, 16],
  'TR4D': [9],
  'TR6' : [8, 12, 16],
  'TR8' : [12, 16, 18],
};

// Límites de Finished Diameter (mm) por Die Type y ángulo (Custom Die = OFF)
static const Map<String, Map<int, List<List<double>>>> _fdLimitsMm = {
  'TR4': {
    9 : [[0.75, 1.99], [2.00, 5.00]],
    12: [[0.75, 1.99], [2.00, 4.98], [5.00, 5.85]],
    16: [[1.80, 2.99], [3.00, 5.85]],
  },
  'TR4D': { 9: [[0.15, 0.64], [0.65, 1.50]] },
  'TR6': {
    8 : [[4.00, 8.45]],
    12: [[4.00, 8.90]],
    16: [[3.80, 5.49], [5.50, 8.90]],
  },
  'TR8': {
    12: [[5.30, 13.00]],
    16: [[4.50, 7.50]],
    18: [[6.00, 13.00]],
  },
};

List<int> _allowedAnglesForDieType(String die) =>
    _presetAngles[die] ?? const [];

bool _isOutDiaAllowedMm({
  required String die,
  required int angleDeg,
  required double outDiaMm,
}) {
  final m = _fdLimitsMm[die];
  if (m == null) return true;
  final ranges = m[angleDeg];
  if (ranges == null) return true;
  for (final r in ranges) {
    final minMm = r[0], maxMm = r[1];
    if (outDiaMm >= minMm - 1e-9 && outDiaMm <= maxMm + 1e-9) return true;
  }
  return false;
}

// Si Custom Die = OFF, fuerza ángulo permitido y sincroniza el TextField
void _syncAngleInputWithMode() {
  if (_customDie) return; // libre
  final allowed = _allowedAnglesForDieType(_selectedDieType);
  if (allowed.isEmpty) return;
  final current = reductionAngle.round();
  final int chosen = allowed.contains(current) ? current : allowed.first;
  setState(() {
    reductionAngle = chosen.toDouble();
    reductionAngleController.text = chosen.toString();
  });
}

  final TextEditingController partNoController = TextEditingController();

  bool _usePart    = false;   // estado del switch
  bool _partFound  = false;   // si el PN existe
  String _partMsg  = '';      // mensaje verde / rojo

  Future<void> _loadRcDb() async {
    //final str = await rootBundle.loadString('assets/rough_core_db.json');
    //_rcDb = List<Map<String, dynamic>>.from(json.decode(str));

    // ── DEBUG: cuenta por tipo para confirmar que TR6 está cargado ──
    int cTR4  = _rcDb.where((m) =>
        (m['part_number'] ?? '').toString().toUpperCase().startsWith('TR4-')).length;
    int cTR4D = _rcDb.where((m) =>
        (m['part_number'] ?? '').toString().toUpperCase().startsWith('TR4D-')).length;
    int cTR6  = _rcDb.where((m) =>
        (m['part_number'] ?? '').toString().toUpperCase().startsWith('TR6-')).length;

    // ignore: avoid_print
    print('[RC] loaded: TR4=$cTR4  TR4D=$cTR4D  TR6=$cTR6  total=${_rcDb.length}');
  }

  String _normalizePn(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  // --- Filtro por tipo de dado seleccionado (TR4 / TR4D) -------------
bool _pnMatchesSelected(String pnRaw) {
  final pn = _normalizePn(pnRaw);
  switch (_selectedDieType) {
    case 'TR4D': return pn.startsWith('TR4D');
    case 'TR4' : return pn.startsWith('TR4') && !pn.startsWith('TR4D');
    case 'TR6' : return pn.startsWith('TR6');
    case 'TR8' : return pn.startsWith('TR8'); // ← NUEVO
    default    : return false;
  }
}

  Iterable<Map<String, dynamic>> _rcDbForSelected() sync* {
    final pref = _selectedDieType.toUpperCase();
    for (final m in _rcDb) {
      final pn = (m['part_number'] ?? '').toString();
      if (pn.toUpperCase().startsWith(pref)) yield m;
    }
  }

  @override
  void initState() {
    super.initState();
    _showInches = widget.selectedSystem == 'imperial';
    if (widget.customDeltaRange != null && widget.customDeltaRange!.length == 2) {
      _deltaRanges['Custom'] = [
        widget.customDeltaRange![0],
        widget.customDeltaRange![1],
      ];
    }
    // 1) setup inicial del lado izquierdo (principal)
    _applyDieType(_selectedDieType);
    _syncAngleInputWithMode();

    // Si vinieron valores por constructor (en mm)
    if (widget.naranjaL != null)      naranjaL      = widget.naranjaL!;
    if (widget.barraLength != null)   barraLength   = widget.barraLength!;
    if (widget.alturaInicial != null) alturaInicial = widget.alturaInicial!;
    if (widget.reductionAngle != null) reductionAngle = widget.reductionAngle!;

    _selectedGrade2 = _selectedGrade;

    // A décimas una sola vez
    naranjaL      = naranjaL * 10;
    barraLength   = barraLength * 10;
    naranjaR      = naranjaR * 10;
    alturaInicial = alturaInicial * 10;

    // Defaults y posiciones que dependen del Ø de salida
    _applyBearingDefaults(barraLength / 10.0);
    _recalculateAzulPosition();

    // Escribe textfields del izquierdo
    _refreshControllers();
    reductionAngleController.text = reductionAngle.toStringAsFixed(1);
    _refreshDeltaLeft();
    _refreshDeltaRight();

    // Construye el izquierdo una vez después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildDie();
    });

    // 2) setup del lado derecho (compare)
    naranjaL2       = naranjaL;
    barraLength2    = barraLength;
    alturaInicial2  = alturaInicial;
    blMinPercent2   = blMinPercent;
    blMaxPercent2   = blMaxPercent;

    // ⚑ Fuerza 16° para el segundo dado desde el inicio
    reductionAngle2 = 16.0;
    reductionAngleController2.text = '16.0';

    // Back-relief y posición horizontal inicial del derecho
    final outMm2  = barraLength2 / 10.0;
    final dv2init = _visualForDie(_secondDieType);
    naranjaR2     = _backReliefDiameterMmWithAngle(outMm2, dv2init.angSup) * 10.0;
    azulOffsetX2  = _computeAzulXFor(
      dv2init,
      naranjaRdec: naranjaR2,
      cafeGrisLenDec: cafeGrisLengthDec2,
      barraLenDec: barraLength2,
    );

    // Escribe textfields del derecho
    _refreshControllers2();

    // Construye el derecho una vez para que ya salga correcto sin tocar su botón
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildDieRight();
    });
  }

void _applyCopyToRight() {
  // Copiamos desde el dado izquierdo
  final double inMm  = alturaInicial / 10.0;
  final double outMm = barraLength  / 10.0;
  double ang         = reductionAngle;

  // Si Custom Die = OFF, fuerza ángulo permitido para el segundo die type
  if (!_customDie) {
    final allowed = _allowedAnglesForDieType(_secondDieType);
    if (allowed.isNotEmpty && !allowed.contains(ang.round())) {
      ang = allowed.first.toDouble();
    }
  }

  setState(() {
    alturaInicial2   = inMm  * 10;
    barraLength2     = outMm * 10;
    reductionAngle2  = ang;
    blMinPercent2    = blMinPercent;
    blMaxPercent2    = blMaxPercent;
    _selectedGrade2  = _selectedGrade;
  });

  _refreshControllers2();  // actualiza textfields
  _buildDieRight();        // y recalcula dibujo del derecho
}

  // Calculates horizontal center position (azulOffsetX) based on geometry constraints
/// Reposiciona horizontalmente el inserto (café + gris)
/// para que las rampas externas de ±30 ° coincidan con la
/// nueva altura derecha naranjaR.
void _recalculateAzulPosition() {
  // Usa el mismo solver geométrico que el lado derecho
  final _DieVisual dv = _visualForDie(_selectedDieType);

  final double azulX = _computeAzulXFor(
    dv,
    naranjaRdec: naranjaR,              // ya está en décimas
    cafeGrisLenDec: cafeGrisLengthDec,  // décimas
    barraLenDec: barraLength,           // décimas (Finished)
  );

  setState(() => azulOffsetX = azulX);
}

void _recalculateAzulPositionRight() {
  final _DieVisual dv = _visualForDie(_secondDieType);
  final double azulX = _computeAzulXFor(
    dv,
    naranjaRdec: naranjaR2,
    cafeGrisLenDec: cafeGrisLengthDec2,
    barraLenDec: barraLength2,
  );
  setState(() => azulOffsetX2 = azulX);
}



/// Calcula el Prep-Meeting-Point y lo devuelve en **pulgadas**
double _prepMeetingPointInch({
  required double fdMm,          // diámetro de salida en mm
  required double blMinPercent,  // Bearing-Length min  (%)
  required double blMaxPercent,  // Bearing-Length max  (%)
  required double alphaDeg,      // ángulo de reducción total  (°)
  required double gammaDeg,      // ángulo de back-relief total (°)
}) {
  final fdIn        = _mmToIn(fdMm);                        // mm → in
  final blFraction  = (blMinPercent + blMaxPercent) / 200;  // 0–1
  final alphaRad    = (alphaDeg / 2) * pi / 180;            // rad
  final gammaRad    = (gammaDeg  / 2) * pi / 180;           // rad

  final deltaR = blFraction * fdIn *
                 (tan(gammaRad) * tan(alphaRad)) /
                 (tan(gammaRad) + tan(alphaRad));

  return fdIn - deltaR;
}

// Calcula la altura izquierda (naranjaL) necesaria para dibujar
// el ángulo de reducción indicado (θ) manteniendo las rampas externas en ±30°.
void _updateReductionAngle(double angleDeg) {
  if (angleDeg <= 0 || angleDeg >= 89) return;

  final halfRad = (angleDeg / 2) * pi / 180;

  // 👇 usa el visual del die seleccionado (para tomar sx correcto)
  final _DieVisual dv = _visualForDie(_selectedDieType);

  // H → px: dec → mm → px con escala H (sx)
  final double cafeGrisLenPx = decToMm(cafeGrisLengthDec) * pxPerMm * dv.sx;

  final double cafeLeftPx = azulOffsetX - cafeGrisLenPx / 2;

  // px → mm (H): divide por pxPerMm * sx
  final double dMm = (cafeLeftPx - _borderLeftPx) / (pxPerMm * dv.sx);

  final double barraMm  = decToMm(barraLength);
  final double newlMm   = barraMm + 2 * dMm * tan(halfRad);

  setState(() {
    reductionAngle = angleDeg;
    naranjaL       = newlMm * 10;
    reductionAngleController.text = angleDeg.toStringAsFixed(1);
    naranjaLController.text       = newlMm.toStringAsFixed(3);
  });

  _recalculateAzulPosition();
  _refreshControllers();
}

void _buildDie() {
  // ── 1. Lee valores introducidos ────────────────────────────────
  final redAng = double.tryParse(reductionAngleController.text);
  final inDiaMm  = _parseLen(alturaInicialController.text);   // mm
  final outDiaMm = _parseLen(barraLengthController.text);     // mm

  // Validaciones básicas
  if (redAng == null || redAng <= 0 || redAng >= 89) return;
  if (inDiaMm == null || outDiaMm == null) return;

  // 3.a Finished debe ser menor que Entry
  if (outDiaMm >= inDiaMm) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Finished Diameter must be smaller than Entry Diameter.',
        )),
      );
    }
    return; // no actualices dibujo ni estado
  }

// 3.b Si Custom Die = OFF, validar por Die Type + Angle
if (!_customDie) {
  final int ang = reductionAngle.round();
  final ok = _isOutDiaAllowedMm(
    die: _selectedDieType,
    angleDeg: ang,
    outDiaMm: outDiaMm, // ya está en mm por _parseLen()
  );

  if (!ok) {
    if (mounted) {
      setState(() => _fdOutOfRange = true); // 🔴 marca el campo como error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finished Diameter out of limit')),
      );
    }
    return; // NO actualices dibujo ni estado
  } else {
    // ✅ válido: limpia el error si estuviera activo
    if (_fdOutOfRange) setState(() => _fdOutOfRange = false);
  }
} else {
  // Si Custom Die vuelve a ON, limpiamos cualquier marca de error
  if (_fdOutOfRange) setState(() => _fdOutOfRange = false);
}

  // 🔴 NUEVA REGLA: Finished debe ser menor que Entry
  if (outDiaMm >= inDiaMm) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Finished Diameter must be smaller than Entry Diameter.'),
        ),
      );
    }
    return; // ⟵ NO cambiamos nada del dibujo ni del estado
  }

// ── 2. Determinar BL-min / BL-max ─────────────────────────────
double autoMin, autoMax;

/// 2.a  Intentar leer lo que el usuario escribió
final double? userMin = double.tryParse(blMinController.text);
final double? userMax = double.tryParse(blMaxController.text);

final bool userTypedOk = userMin != null &&
                         userMax != null &&
                         userMin > 0 &&
                         userMax <= 100 &&
                         userMin <= userMax;

if (userTypedOk) {
  // ─── Usamos lo que escribió ───────────────────────────────
  autoMin = userMin;
  autoMax = userMax;
} else {
  // ─── Aplicamos la tabla de defaults según Ø de salida ─────
  if      (outDiaMm >= 0.15 && outDiaMm <= 0.499)  { autoMin = 20; autoMax = 50; }
  else if (outDiaMm >= 0.50 && outDiaMm <= 0.649)  { autoMin = 25; autoMax = 50; }
  else if (outDiaMm >= 0.65 && outDiaMm <= 0.749)  { autoMin = 25; autoMax = 50; }
  else if (outDiaMm >= 0.75 && outDiaMm <= 2.499)  { autoMin = 30; autoMax = 50; }
  else if (outDiaMm >= 2.50 && outDiaMm <= 4.999)  { autoMin = 30; autoMax = 50; }
  else if (outDiaMm >= 5.00 && outDiaMm <= 7.499)  { autoMin = 25; autoMax = 45; }
  else if (outDiaMm >= 7.50 && outDiaMm <= 9.99)   { autoMin = 20; autoMax = 40; }
  else if (outDiaMm >= 10.00 && outDiaMm <= 12.69) { autoMin = 20; autoMax = 35; }
  else /* ≥ 12.70 mm */                       { autoMin = 20; autoMax = 30; }

  // Reflejamos los defaults SOLO cuando los usamos
  blMinController.text = autoMin.toStringAsFixed(0);
  blMaxController.text = autoMax.toStringAsFixed(0);
}

/// 2.c  Guardamos el resultado para el resto del flujo
setState(() {
  blMinPercent = autoMin;
  blMaxPercent = autoMax;
});

  // ── 3. Back‑Relief Diameter (naranjaR) por FÓRMULA ─────────────
  final double backReliefMm = _backReliefDiameterMm(outDiaMm);
  // guardamos en décimas para tu modelo interno (dec = mm*10)
  final double naranjaRdec = backReliefMm * 10;

  // ── 4. Actualiza estado global y redibuja ──────────────────────
  setState(() {
    reductionAngle  = redAng;
    alturaInicial   = inDiaMm  * 10;   // mm → décimas
    barraLength     = outDiaMm * 10;   // mm → décimas
    naranjaR        = naranjaRdec;   // décimas
    blMinPercent    = autoMin;
    blMaxPercent    = autoMax;
  });

// ── 5. Cálculo y aviso del Prep-Meeting-Point ──────────────────
if (!_usePart) {                      // solo si NO es por PN
// 5. Cálculo del Prep-Meeting-Point (en pulgadas) ────────────
final double kBackReliefDeg = _selectedDieType == 'TR4D' ? 90 : 60;
_lastPmpIn = _prepMeetingPointInch(
  fdMm: outDiaMm,
  blMinPercent: autoMin,
  blMaxPercent: autoMax,
  alphaDeg: redAng,
  gammaDeg: kBackReliefDeg,
);
pmpController.text = _lastPmpIn!.toStringAsFixed(4);
} else {
  // si el usuario construye por PN vaciamos/ocultamos
  setState(() {
    _pmpController.clear();
    _pmpLabel = '';
  });
}
  _refreshControllers();
  _recalculateAzulPosition();   // mantiene ±30° externos
  _updateReductionAngle(redAng);
  // ⬇ NUEVO: si Copy First está activo, replica al segundo dado
  if (_copyLeftToRight) {
    _applyCopyToRight();  // copia Entry/Finished/Angle/BL/Grade y reconstruye el derecho
  }

}

// Construye el dado derecho (Compare Die) con sus propios valores
void _buildDieRight() {
  final redAng = double.tryParse(reductionAngleController2.text);
  final inDiaMm  = _parseLen(alturaInicialController2.text);
  final outDiaMm = _parseLen(barraLengthController2.text);

  if (redAng == null || redAng <= 0 || redAng >= 89) return;
  if (inDiaMm == null || outDiaMm == null) return;
  if (outDiaMm >= inDiaMm) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Finished must be smaller than Entry (Right).')),
    );
    return;
  }

  // Defaults BL si el usuario no escribe bien
  double autoMin, autoMax;
  final userMin = double.tryParse(blMinController2.text);
  final userMax = double.tryParse(blMaxController2.text);
  final userTypedOk = userMin != null && userMax != null &&
                      userMin > 0 && userMax <= 100 && userMin <= userMax;

  if (userTypedOk) {
    autoMin = userMin!;
    autoMax = userMax!;
  } else {
    // misma tabla que usas
    if      (outDiaMm >= 0.15 && outDiaMm <= 0.499)  { autoMin = 20; autoMax = 50; }
    else if (outDiaMm >= 0.50 && outDiaMm <= 0.649)  { autoMin = 25; autoMax = 50; }
    else if (outDiaMm >= 0.65 && outDiaMm <= 0.749)  { autoMin = 25; autoMax = 50; }
    else if (outDiaMm >= 0.75 && outDiaMm <= 2.499)  { autoMin = 30; autoMax = 50; }
    else if (outDiaMm >= 2.50 && outDiaMm <= 4.999)  { autoMin = 30; autoMax = 50; }
    else if (outDiaMm >= 5.00 && outDiaMm <= 7.499)  { autoMin = 25; autoMax = 45; }
    else if (outDiaMm >= 7.50 && outDiaMm <= 9.99)   { autoMin = 20; autoMax = 40; }
    else if (outDiaMm >= 10.00 && outDiaMm <= 12.69) { autoMin = 20; autoMax = 35; }
    else                                             { autoMin = 20; autoMax = 30; }
    blMinController2.text = autoMin.toStringAsFixed(0);
    blMaxController2.text = autoMax.toStringAsFixed(0);
  }

  // Back-Relief del derecho con su ángulo superior propio
  final dv2 = _visualForDie(_secondDieType);
  final double backReliefMm2 = _backReliefDiameterMmWithAngle(outDiaMm, dv2.angSup);
  final double naranjaRdec2  = backReliefMm2 * 10;

  setState(() {
    reductionAngle2 = redAng;
    alturaInicial2  = inDiaMm  * 10;
    barraLength2    = outDiaMm * 10;
    naranjaR2       = naranjaRdec2;
    blMinPercent2   = autoMin;
    blMaxPercent2   = autoMax;
    // reposición horizontal del inserto derecho (con sus propios datos)
    azulOffsetX2    = _computeAzulXFor(
      dv2,
      naranjaRdec: naranjaRdec2,
      cafeGrisLenDec: cafeGrisLengthDec2,
      barraLenDec: barraLength2,
    );
  });

  // Ajusta la altura izquierda (naranjaL2) para mantener ±30° externos
  _updateReductionAngleRight(redAng);

  _refreshControllers2();
}

Widget _copyCheckbox() {
  return SizedBox(
    width: 85,
    child: CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: const Text('Copy First', style: TextStyle(fontSize: 12)),
      value: _copyLeftToRight,
      onChanged: (v) {
        if (v == null) return;
        setState(() => _copyLeftToRight = v);
        if (v) _applyCopyToRight();
      },

      // <<< colores
      activeColor: kPdRed,              // relleno de la cajita cuando está checked
      checkColor: Colors.white,         // color del “✓”
      side: const BorderSide(           // borde cuando NO está checked
        color: kPdRed,
        width: 1.4,
      ),
    ),
  );
}

// Ajusta la altura izquierda (naranjaL2) para mantener ±30° externos
void _updateReductionAngleRight(double angleDeg) {
  if (angleDeg <= 0 || angleDeg >= 89) return;

  final halfRad = (angleDeg / 2) * pi / 180;

  // 👇 usa el visual del segundo die
  final _DieVisual dv2 = _visualForDie(_secondDieType);

  // H → px con sx del segundo die
  final double cafeGrisLenPx = decToMm(cafeGrisLengthDec2) * pxPerMm * dv2.sx;
  final double cafeLeftPx    = azulOffsetX2 - cafeGrisLenPx / 2;

  // px → mm (H) con sx del segundo die
  final double dMm = (cafeLeftPx - _borderLeftPx) / (pxPerMm * dv2.sx);

  final double barraMm = decToMm(barraLength2);
  final double newlMm  = barraMm + 2 * dMm * tan(halfRad);

  setState(() {
    reductionAngle2 = angleDeg;
    naranjaL2       = newlMm * 10;
    reductionAngleController2.text = angleDeg.toStringAsFixed(1);
  });

  _recalculateAzulPositionRight();
  _refreshControllers2();
}

// ─────────────────── SETTINGS MODAL ───────────────────
Future<void> _openSettings() async {
  // copiamos el estado actual a una variable temporal
  bool tempShowInches = _showInches;
  bool tempCustomDie  = _customDie;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,          // obliga a usar los botones
    barrierLabel: 'Settings',
    barrierColor: Colors.black54,       // oscurece el fondo
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) {
      return Center(                    // dialog centrado y más pequeño
        child: StatefulBuilder(
          builder: (context, setLocalState) {
            return Material(
              elevation: 12,
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 320,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ─── encabezado + “X” ───
                      Stack(
                        children: [
                          const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              iconSize: 20,
                              splashRadius: 18,
                              icon: const Icon(CupertinoIcons.xmark),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ─── Units ───
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Units',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('mm'),
                          const SizedBox(width: 6),
                          Switch(
                            value: tempShowInches,
                            onChanged: (v) =>
                                setLocalState(() => tempShowInches = v),
                            thumbColor:
                                WidgetStateProperty.all(Colors.black),
                            trackColor:
                                WidgetStateProperty.resolveWith<Color>(
                              (s) =>
                                  s.contains(WidgetState.selected)
                                      ? kPdRed
                                      : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('in'),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ─── Custom Die ───
const Align(
  alignment: Alignment.centerLeft,
  child: Text(
    'Custom Die',
    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  ),
),
const SizedBox(height: 6),

Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    const Text('Off'),
    const SizedBox(width: 6),
    Switch(
      value: tempCustomDie,
      onChanged: (v) => setLocalState(() => tempCustomDie = v),
      thumbColor: WidgetStateProperty.all(Colors.black),
      trackColor: WidgetStateProperty.resolveWith<Color>(
        (s) => s.contains(WidgetState.selected) ? kPdRed : Colors.white,
      ),
    ),
    const SizedBox(width: 6),
    const Text('On'),
  ],
),

// ─── Campos Min & Max Delta (solo cuando ON) ───
if (tempCustomDie) ...[
  const SizedBox(height: 10),

  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // MIN DELTA
      SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Min Delta",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: minDeltaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),

              // ← Aquí actualiza el mapa
              onChanged: (val) {
                double v = double.tryParse(val) ?? 0.0;
                setLocalState(() {
                  _deltaRanges['Custom']![0] = v;
                });
              },
            ),
          ],
        ),
      ),

      const SizedBox(width: 20),

      // MAX DELTA
      SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Max Delta",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: maxDeltaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),

              // ← Aquí actualiza el mapa
              onChanged: (val) {
                double v = double.tryParse(val) ?? 0.0;
                setLocalState(() {
                  _deltaRanges['Custom']![1] = v;
                });
              },
            ),
          ],
        ),
      ),
    ],
  ),
],

                      
                      const SizedBox(height: 24),

                      // ─── botones ───
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Cancel
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kPdRed,
                              side: const BorderSide(color: kPdRed),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          // Apply
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _showInches = tempShowInches;
                                _customDie  = tempCustomDie;
                                _syncAngleInputWithMode();   // fuerza ángulo permitido si está OFF
                                _refreshControllers();
                                 _fdOutOfRange = false;
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Apply Settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

Future<void> _makeCapture(CaptureMode newMode) async {
  try {
    // 👉 Activa modo captura solo para el frame
    setState(() => _mode = newMode);
    await WidgetsBinding.instance.endOfFrame;

    final boundary = _captureKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return;

    if (boundary.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 16));
    }

    final dpr = View.of(context).devicePixelRatio;
    final image = await boundary.toImage(
      pixelRatio: (dpr * 2).clamp(1.0, 4.0),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();

    final doc = pw.Document()
      ..addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) {
            final maxW = ctx.page.pageFormat.availableWidth;
            return pw.Center(
              child: pw.FittedBox(
                fit: pw.BoxFit.contain,
                child: pw.Image(pw.MemoryImage(bytes), width: maxW),
              ),
            );
          },
        ),
      );
    final pdfBytes = await doc.save();

    if (kIsWeb) {
      await printing.Printing.layoutPdf(
        name: '${newMode.name}.pdf',
        onLayout: (_) async => pdfBytes,
      );
    } else {
      await printing.Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${newMode.name}.pdf',
      );
    }
  } catch (e, st) {
    debugPrint('Error al generar PDF: $e\n$st');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo generar el PDF')),
      );
    }
  } finally {
    if (mounted) setState(() => _mode = CaptureMode.normal);
  }
}

// -----------------------------------------------------------
// Busca el PN y rellena sólo las claves presentes
// -----------------------------------------------------------

Future<void> _usePmpToLoadPart() async {
  if (_lastPmpIn == null) return;
  if (_rcDb.isEmpty) await _loadRcDb();

  const double kTol = 1e-4;                     // ±0.0001" de tolerancia
  final int angNeeded = reductionAngle.round(); // ángulo buscado

  Map<String, dynamic>? best;
  double bestDiff = double.infinity;

  for (final m in _rcDbForSelected()) {
    // 1) Coincide el ángulo
    if ((m['reduction_angle_deg'] as num).round() != angNeeded) continue;

    final dia  = (m['finished_dia_in'] as num).toDouble();
    final diff = _lastPmpIn! - dia;             // positivo si dia ≤ PMP

    // 2) ¿Coincidencia “exacta” dentro de la tolerancia?
    if (diff.abs() <= kTol) {                   // igual (≈)
      best = m;
      break;                                    // la tomamos y salimos
    }

    // 3) Si es menor y el más cercano hasta ahora → candidato
    if (diff > 0 && diff < bestDiff) {
      bestDiff = diff;
      best = m;
    }
  }

  if (best == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No matching rough-core found')),
    );
    return;
  }

  // Carga el PN hallado como si lo hubiera escrito el usuario
  setState(() {
    _usePart = true;
    partNoController.text = best!['part_number']; // ← best!  asegura no-nulo
  });
  await _checkPart();   // rellena campos con ese PN
}

// ---------------------------------------------------------------------------
// Busca el PN y (solo) rellena los TextFields correspondientes
// Guarda, pero NO aplica aún, el back-relief encontrado.
// ---------------------------------------------------------------------------
Future<void> _checkPart() async {
  // 1) Cargar DB la primera vez
  if (_rcDb.isEmpty) await _loadRcDb();

  // Si el usuario eligió TR6 pero no hay PNs TR6 en la DB cargada, avisa claro
// dentro de _checkPart()
if ((_selectedDieType == 'TR6' || _selectedDieType == 'TR8') &&
    !_rcDb.any((m) => (m['part_number'] ?? '')
        .toString()
        .toUpperCase()
        .startsWith('${_selectedDieType}-'))) {

  final parsed = parseRoughCorePn(partNoController.text);
  if (parsed != null) {
    if (parsed['reduction_angle'] != null) {
      reductionAngleController.text =
          (parsed['reduction_angle'] as num).toStringAsFixed(0);
    }
    if (parsed['finished_dia'] != null) {
      barraLengthController.text =
          _fmtLen((parsed['finished_dia'] as num).toDouble());
    }
    if (parsed['back_relief_dia'] != null) {
      _pendingBackReliefMm = (parsed['back_relief_dia'] as num).toDouble();
    }
    setState(() { _partFound = true; _partMsg = 'Using PN parser (no ${_selectedDieType} DB)'; });
    return;
  } else {
    setState(() {
      _partFound = false;
      _partMsg   = 'No ${_selectedDieType} DB and PN format not recognized';
      _pendingBackReliefMm = null;
    });
    return;
  }
}

  // 2) PN normalizado y validaciones básicas
  final String raw = partNoController.text;
  final String pn  = _normalizePn(raw); // quita espacios y guiones
  if (pn.isEmpty) {
    setState(() {
      _partFound = false;
      _partMsg   = 'Enter a Part Number';
      _pendingBackReliefMm = null;
    });
    return;
  }

  // Debe corresponder al Die Type seleccionado (TR4 / TR4D)
  if (!_pnMatchesSelected(pn)) {
    _pendingBackReliefMm = null;
    setState(() {
      _partFound = false;
      _partMsg   = 'Use a ${_selectedDieType} Part Number';
    });
    return;
  }

  // Helper: base sin sufijo de revisión (soporta con o sin guion)
  String _baseWithoutRevision(String s) {
    // s ya viene normalizado (sin guiones). El sufijo queda como \d[A-Z]
    // Ej: TR4D10F.0060-178N-0B  → normalizado → TR4D10F.0060-178N0B
    // Base: TR4D10F.0060-178N
    return s.replaceFirst(RegExp(r'[0-9][A-Z]$'), '');
  }

  Map<String, dynamic>? match;

  // 3) Intento 1: coincidencia exacta (comparando normalizados)
  try {
    match = _rcDb.firstWhere(
      (m) => _normalizePn((m['part_number'] ?? '').toString()) == pn,
    );
  } catch (_) {
    match = null;
  }

  // 4) Intento 2: por "base" (sin sufijo de revisión)
  if (match == null) {
    final String base = _baseWithoutRevision(pn);
    // Debug útil
    // ignore: avoid_print
    print('[RC] Fallback base="$base" desde pn="$pn" (raw="$raw")');

    for (final m in _rcDb) {
      final cand = _normalizePn((m['part_number'] ?? '').toString());
      if (!_pnMatchesSelected(cand)) continue; // respeta TR4/TR4D
      if (cand.startsWith(base)) {
        match = m;
        break;
      }
    }
  }

  // 5) Resultado
  if (match == null) {
    setState(() {
      _partFound = false;
      _partMsg   = 'Part Number not found';
      _pendingBackReliefMm = null;
    });
    // Debug: lista breves candidatos con la misma base para inspección
    final String base = _baseWithoutRevision(pn);
    final candidates = _rcDb
        .map((m) => (m['part_number'] ?? '').toString())
        .where((s) => _normalizePn(s).startsWith(base))
        .take(6)
        .toList();
    // ignore: avoid_print
    print('[RC] No match. Sugerencias con misma base: $candidates');
    return;
  }

  // 6) Rellenar SOLO los campos disponibles en la DB
  if (match['reduction_angle_deg'] != null) {
    reductionAngleController.text =
        (match['reduction_angle_deg'] as num).toString();
  }

  _pendingBackReliefMm = match['back_relief_in'] == null
      ? null
      : _inchToMm(match['back_relief_in']);

  setState(() {
    _partFound = true;
    _partMsg   = 'Rough Core found';
  });

  // Debug
  // ignore: avoid_print
  print('[RC] Match: ${match['part_number']}  angle=${match['reduction_angle_deg']}  BR_in=${match['back_relief_in']}');
}

/// Intenta deducir datos del PN aunque no exista en el JSON.
///  • Devuelve null si el PN no cumple el formato mínimo.
///  • Si devuelve mapa, las claves presentes pueden ser:
///      reduction_angle   (double   °)
///      finished_dia      (double   mm)
///      bl_min            (double   %)
Map<String, dynamic>? parseRoughCorePn(String raw) {
  final pn = raw.trim().toUpperCase();
  // sólo aceptamos prefijos válidos y acordes al tipo elegido
  final okPrefix = pn.startsWith('TR4-') || pn.startsWith('TR4D-') || pn.startsWith('TR6-') || pn.startsWith('TR8-');;
  if (!okPrefix) return null;
  if (!_pnMatchesSelected(pn)) return null;   // sigue respetando el die seleccionado

  final cleaned = pn.replaceAll(RegExp(r'[^A-Z0-9.,]'), '');
  if (!cleaned.startsWith('TR') || cleaned.length < 10) return null;

  // ── (A) Ángulo de reducción ────────────────────────
  final match = RegExp(r'^[A-Z0-9]*-(\d{2}[A-Z]?)').firstMatch(raw.toUpperCase());
  if (match == null) return null;
  final angCode = match.group(1)!;           // "16P" en tu ejemplo
  final angle   = kAngleByCode[angCode];
  if (angle == null) return null;

  // ── (B) Ø acabado (finished_dia) ───────────────────
  final dot = cleaned.indexOf(RegExp(r'[.,]'));
  if (dot == -1 || dot + 5 > cleaned.length) return null;
  final diaRaw = cleaned.substring(dot, dot + 5);   // ".0740"  ó ",0740"
  final finishedDiaMm = double.parse(
        diaRaw.replaceFirst(',', '.')) *
        (diaRaw.startsWith('.') ? 25.4 : 1);

  // ── (C) Back-Relief vertical ───────────────────────
  double? backRelMm;
  final relMatch = RegExp(r'(\d{3})').firstMatch(cleaned.substring(dot + 5));
  if (relMatch != null) {
    final thouIn = int.parse(relMatch.group(1)!);      // 150, 200, …
    backRelMm = thouIn / 1000 * 25.4;                  // → mm
  }

  // ¡Ya NO leemos BL-min aquí!
  return {
    'reduction_angle' : angle,
    'finished_dia'    : finishedDiaMm,
    if (backRelMm != null) 'back_relief_dia': backRelMm,
  };
}

// ───────────────── Bearing-Length defaults según Ø de salida ─────────────────
void _applyBearingDefaults(double outDiaMm) {
  double min, max;

  if (outDiaMm >= 0.15 && outDiaMm <= 0.499) {
    min = 20;  max = 50;
  } else if (outDiaMm >= 0.50 && outDiaMm <= 0.649) {
    min = 25;  max = 50;
  } else if (outDiaMm >= 0.65 && outDiaMm <= 0.749) {
    min = 25;  max = 50;
  } else if (outDiaMm >= 0.75 && outDiaMm <= 2.499) {
    min = 30;  max = 50;
  } else if (outDiaMm >= 2.5 && outDiaMm <= 4.999) {
    min = 30;  max = 50;
  } else if (outDiaMm >= 5.0 && outDiaMm <= 7.499) {
    min = 25;  max = 45;
  } else if (outDiaMm >= 7.5 && outDiaMm <= 9.99) {
    min = 20;  max = 40;
  } else if (outDiaMm >= 10.0 && outDiaMm <= 12.69) {
    min = 20;  max = 35;
  } else { // ≥ 12.70 mm
    min = 20;  max = 30;
  }

  // Actualiza estado y controles
  blMinPercent = min;
  blMaxPercent = max;
  blMinController.text = min.toStringAsFixed(0);
  blMaxController.text = max.toStringAsFixed(0);
}

// ─── Selector Die Type con acentos rojos ─────────────────────────
Widget _buildDieTypeSelector() {
  return SizedBox(
    width: 100,                       // el mismo ancho que “Grade”
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Die Type',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
DropdownButtonFormField<String>(
  value: _selectedDieType,
  isDense: true,
  iconEnabledColor: kPdRed,               // chevron rojo
  decoration: const InputDecoration(
    border: OutlineInputBorder(),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: kPdRed, width: 1.4),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black45, width: 1.0),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
  ),
  items: const [
    DropdownMenuItem(value: 'TR4',  child: Text('TR4')),
    DropdownMenuItem(value: 'TR4D', child: Text('TR4D')),
    DropdownMenuItem(value: 'TR6', child: Text('TR6')),
    DropdownMenuItem(value: 'TR8',  child: Text('TR8')),
  ],

  // ─── Corrección: refrescar el dado en cuanto cambie el tipo ───
  onChanged: (v) {
    if (v == null) return;

    // 1️⃣  Actualiza ángulos, cotas, etc.
    setState(() => _applyDieType(v));

    // 2️⃣  Ejecuta el mismo flujo que el botón “Build Die”
    //     (salvo que esté deshabilitado por el RC-Tool)
    if (!(_usePart && !_partFound)) {
      _buildDie();
    }
  },
),

      ],
    ),
  );
}

Widget _buildSecondDieTypeSelector() {
  return SizedBox(
    width: 100,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Second Die Type',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: _secondDieType,
          isDense: true,
          iconEnabledColor: kPdRed,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: kPdRed, width: 1.4),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.black45, width: 1.0),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          ),
          items: const [
            DropdownMenuItem(value: 'TR4',  child: Text('TR4')),
            DropdownMenuItem(value: 'TR4D', child: Text('TR4D')),
            DropdownMenuItem(value: 'TR6',  child: Text('TR6')),
            DropdownMenuItem(value: 'TR8',  child: Text('TR8')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _secondDieType = v);
            if (_copyLeftToRight) {
              _applyCopyToRight();
            } else {
              _buildDieRight(); // recalcula BR, azulOffsetX2, etc.
            }
          },
        ),
      ],
    ),
  );
}

// === Constantes compartidas por canvas y selectores ===
static const double _kPairSpacingPx     = 100.0; // ya la tenías
static const double _kFirstLeftShiftPx  = 400.0; // ya la tenías
static const double _kSelectorsHeight   = 90.0;  // alto del bloque
static const double _kCanvasShiftX      = 60.0;  // <<< el mismo que usas en el canvas
static const double _kRightUiNormalPx   = 300.0; // margen derecho (cuando NO capturas)

// ── Espaciados/offsets verticales para los dropdowns ──
static const double _kGapCanvasToSelectors   = 0.0; // distancia canvas → selectores
static const double _kSelectorsTopOffsetPx   = 0.0;  // sube/baja ambos dentro del Stack
static const double _kSelector1ExtraDyPx     = 0.0;  // ajuste fino solo izq
static const double _kSelector2ExtraDyPx     = 0.0;  // ajuste fino solo der
// ── Ajustes finos HORIZONTALES (px) para los selectores en Compare ──
static const double _kSelector1ExtraDxPx = -70.0; // 1º (Die Type) → más a la IZQUIERDA
static const double _kSelector2ExtraDxPx =  330.0; // 2º (Second Die Type) → más a la DERECHA

// cuánto subir (negativo) o bajar (positivo) los controles respecto al canvas
static const double _kControlsUpShiftPx = -20.0; // súbelos ~40 px; ajusta a gusto

Widget _buildCompareSelectorsAligned() {
  final _DieVisual dv1 = _visualForDie(_selectedDieType);
  final _DieVisual dv2 = _visualForDie(_secondDieType);

  final double w1 = dv1.refW * pxPerMm; // ancho visible del bloque 1
  final double w2 = dv2.refW * pxPerMm; // ancho visible del bloque 2
  const double selW = 100.0;            // coincide con _buildDieTypeSelector()

  // márgenes del canvas (cuando NO capturas)
  final double leftMarginPx  = _borderLeftPx;
  final double rightMarginPx = _kRightUiNormalPx;

  // Ancho total del "stage" que contiene ambos dibujos
  final double totalW = leftMarginPx + w1 + _kPairSpacingPx + w2 + rightMarginPx;

  // X del centro del selector 1 = mismos desplazamientos del canvas:
  //   margen izq + (−shift del 1er bloque) + desplazamiento global del canvas
  final double firstCenterX = leftMarginPx
      - _kFirstLeftShiftPx
      + _kCanvasShiftX
      + (w1 / 2);

  final double secondCenterX = firstCenterX + w1 + _kPairSpacingPx;
final double baseTop = _kSelectorsTopOffsetPx;

return SizedBox(
  width: totalW,                     // como lo tienes calculado
  height: _kSelectorsHeight,
  child: Stack(
    clipBehavior: Clip.none,        // ← por si sobresalen un poco
    children: [
      // Selector 1 (Die Type)
      Positioned(
        left:  firstCenterX - selW / 2 + _kSelector1ExtraDxPx,  // ← offset H
        top:   baseTop + _kSelector1ExtraDyPx,                  // offset V ya existente
        width: selW,
        child: _buildDieTypeSelector(),
      ),

      // Selector 2 (Second Die Type)
      Positioned(
        left:  secondCenterX - selW / 2 + _kSelector2ExtraDxPx, // ← offset H
        top:   baseTop + _kSelector2ExtraDyPx,                  // offset V ya existente
        width: selW,
        child: _buildSecondDieTypeSelector(),
      ),
    ],
  ),
);

}

// en tu State ⇒ añade la variable:
String _dieType = 'TR4';

Widget buildGradeDropdown() => SizedBox(
  width: 150, // ← sube de 140 a 160
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Drawn Material', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        value: _selectedGrade,
        isDense: true,
        isExpanded: true,                // 👈 que ocupe todo el ancho útil
        iconEnabledColor: kPdRed,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: kPdRed, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black45, width: 1.0),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10, vertical: 10), // ← un poco menos alto
        ),
        items: kGrades
            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _selectedGrade = v;
            _refreshDeltaLeft(); // ← actualiza texto y fondo del Δ
          });
        },
      ),
    ],
  ),
);

Widget buildGradeDropdownRight({bool enabled = true}) => SizedBox(
  width: 150,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Drawn Material', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        value: _selectedGrade2,
        isDense: true,
        isExpanded: true,
        iconEnabledColor: kPdRed,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: kPdRed, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black45, width: 1.0),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        items: kGrades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
        onChanged: enabled ? (v) {
          if (v == null) return;
          setState(() {
            _selectedGrade2 = v;
            _refreshDeltaRight(); // ← actualiza Δ derecho
          });
        } : null,
      ),
    ],
  ),
);

Widget _buildDeltaAndGrade() {
  const double kGap = 6.0;
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260), // margen de seguridad
    child: Row(
      mainAxisSize: MainAxisSize.min,                 // no fuerces ancho
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Δ Factor
        SizedBox(
          width: 96,
          child: buildReadOnlyField(
            "Δ Factor",
            deltaController,
            width: 96,
            fill: _deltaFillLeft, // ← antes: deltaColor
          ),
        ),
        const SizedBox(width: kGap),

        // Drawn Material (flexible)
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Drawn Material', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _selectedGrade,
                isDense: true,
                isExpanded: true, // ← evita overflow del dropdown
                iconEnabledColor: kPdRed,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: kPdRed, width: 1.4),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black45, width: 1.0),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: kGrades
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedGrade = v;
                    _refreshDeltaLeft();   // ← vacía si None, o calcula y muestra si no
                  });
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildReductionAngleInput() {
  if (_customDie) {
    // Modo libre (como ahora)
    return buildCompactField(
      "Reduction Angle (°)",
      reductionAngleController,
      (_) {},
    );
  } else {
    // Modo limitado: dropdown por Die Type
    final allowed = _allowedAnglesForDieType(_selectedDieType);
    final int value = allowed.contains(reductionAngle.round())
        ? reductionAngle.round()
        : (allowed.isNotEmpty ? allowed.first : 12);

    return SizedBox(
      width: kFieldWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reduction Angle (°)',
              style: TextStyle(fontSize: 13, color: Colors.black87)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            value: value,
            isDense: true,
            iconEnabledColor: kPdRed,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kPdRed, width: 1.4),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black45, width: 1.0),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            ),
            items: allowed
                .map((a) => DropdownMenuItem(value: a, child: Text(a.toString())))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                reductionAngle = v.toDouble();
                reductionAngleController.text = v.toString();
              });
            },
          ),
        ],
      ),
    );
  }
}

Widget _buildShownFields() => Wrap(
  alignment: WrapAlignment.center,
  spacing: kWrapSpacing,
  runSpacing: 8,
  children: [
    buildCompactField("Finished Diameter (${_unit()})", barraLengthController, (_){}),
    buildInputDiameterField(),
    _buildReductionAngleInput(),
    buildCompactField("Min Bearing Length (%)", blMinController, (_){}),
    buildCompactField("Max Bearing Length (%)", blMaxController, (_){}),
  ],
);

Widget _buildReductionAngleInputFor({
  required String die,
  required bool right,
  bool enabled = true,
}) {
  if (_customDie) {
    return buildCompactField(
      "Reduction Angle (°)",
      right ? reductionAngleController2 : reductionAngleController,
      (_) {},
      enabled: enabled,
    );
  } else {
    final allowed = _allowedAnglesForDieType(die);
    final curr = right ? reductionAngle2.round() : reductionAngle.round();
    final int value = allowed.contains(curr)
        ? curr
        : (allowed.isNotEmpty ? allowed.first : 12);

    return SizedBox(
      width: kFieldWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Reduction Angle (°)', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            value: value,
            isDense: true,
            iconEnabledColor: kPdRed,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: kPdRed, width: 1.4),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black45, width: 1.0),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            ),
            items: allowed
                .map((a) => DropdownMenuItem(value: a, child: Text(a.toString())))
                .toList(),
            onChanged: enabled
                ? (v) {
                    if (v == null) return;
                    setState(() {
                      if (right) {
                        reductionAngle2 = v.toDouble();
                        reductionAngleController2.text = v.toString();
                      } else {
                        reductionAngle = v.toDouble();
                        reductionAngleController.text = v.toString();
                      }
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

Widget buildInputDiameterFieldForRight({bool enabled = true}) {
  return SizedBox(
    width: kFieldWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entry Diameter (${_unit()})',
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: alturaInicialController2,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ],
    ),
  );
}

// Fila compacta: Entry, Finished, Angle
List<Widget> _row1Fields({
  required bool right,
}) => [
  SizedBox(width: 40, height: 90,
    child: right ? const SizedBox() : Center( // engrane SOLO izq
      child: IconButton(
        tooltip: 'Settings',
        icon: const Icon(Icons.settings),
        color: kPdRed,
        splashRadius: 20,
        padding: EdgeInsets.zero,
        onPressed: _openSettings,
      ),
    ),
  ),
  right
    ? buildInputDiameterFieldForRight()
    : buildInputDiameterField(),
  right
    ? buildCompactField("Finished Diameter (${_unit()})",
        barraLengthController2, (_) {})
    : buildCompactField("Finished Diameter (${_unit()})",
        barraLengthController, (_){}),
  right
    ? _buildReductionAngleInputFor(die: _secondDieType, right: true)
    : _buildReductionAngleInputFor(die: _selectedDieType, right: false),
];

// Fila 2: BL min, BL max, Reduction Area (readonly)
List<Widget> _row2Fields({required bool right}) => [
  right
    ? buildCompactField("Min Bearing Length (%)", blMinController2, (_){})
    : buildCompactField("Min Bearing Length (%)", blMinController, (_){ }),
  right
    ? buildCompactField("Max Bearing Length (%)", blMaxController2, (_){})
    : buildCompactField("Max Bearing Length (%)", blMaxController, (_){ }),
  right
    ? buildReadOnlyField("Reduction Area (%)", reductionAreaController2, width: 120)
    : buildReadOnlyField("Reduction Area (%)", reductionAreaController, width: 120),
];

// Fila 3: Δ Factor (+ en la izquierda también el Grade)
List<Widget> _row3Fields({required bool right}) => [
  SizedBox(
    width: 96,
    child: buildReadOnlyField(
      "Δ Factor",
      right ? deltaController2 : deltaController,
      width: 96,
      fill: right ? _deltaFillRight() : _deltaFillLeft, // ← condicional
    ),
  ),
  if (!right) // Grade solo una vez (izquierda)
    Expanded(child: buildGradeDropdown()),
];

// Ancho visual del panel de inputs (ajústalo a tu gusto)
double kPanelWidth = 560;

Widget _sidePanel({required bool right}) {
  final bool enabledRight = right ? !_copyLeftToRight : true;

  return SizedBox(
    width: kPanelWidth,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FILA 1: Settings (solo izq) + campos principales
        Stack(
          children: [
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: kWrapSpacing,
                runSpacing: 8,
                children: [
                // ⬅️ Agrupamos checkbox + Entry en una fila y bajamos el checkbox con padding
                right
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 20), // ↓ muévelo más/menos con este valor
                            child: _copyCheckbox(),
                          ),
                          const SizedBox(width: 10),
                          buildInputDiameterFieldForRight(enabled: enabledRight),
                        ],
                      )
                    : buildInputDiameterField(),
                  right
                      ? buildCompactField(
                          "Finished Diameter (${_unit()})",
                          barraLengthController2,
                          (_) {},
                          enabled: enabledRight,
                        )
                      : buildCompactField(
                          "Finished Diameter (${_unit()})",
                          barraLengthController,
                          (_){},
                          isError: (!_customDie && _fdOutOfRange),
                        ),

                  right
                      ? _buildReductionAngleInputFor(
                          die: _secondDieType,
                          right: true,
                          enabled: enabledRight,
                        )
                      : _buildReductionAngleInputFor(
                          die: _selectedDieType,
                          right: false,
                        ),
                ],
              ),
            ),

            if (!right)
              Positioned(
                left: 0, top: 6,
                child: IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings),
                  color: kPdRed,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  onPressed: _openSettings,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // FILA 2: BL min/max + Reduction Area (RO)
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: kWrapSpacing,
            runSpacing: 8,
            children: [
              right
                  ? buildCompactField("Min Bearing Length (%)", blMinController2, (_){}, enabled: enabledRight)
                  : buildCompactField("Min Bearing Length (%)", blMinController, (_){ }),

              right
                  ? buildCompactField("Max Bearing Length (%)", blMaxController2, (_){}, enabled: enabledRight)
                  : buildCompactField("Max Bearing Length (%)", blMaxController, (_){ }),

              right
                  ? buildReadOnlyField("Reduction Area (%)", reductionAreaController2, width: 120)
                  : buildReadOnlyField("Reduction Area (%)", reductionAreaController,  width: 120),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // FILA 3: Δ factor + Grade (en ambos)
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: kWrapSpacing,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 96,
                child: buildReadOnlyField(
                  "Δ Factor",
                  right ? deltaController2 : deltaController,
                  width: 96,
                  fill: right ? _deltaFillRight() : _deltaFillLeft, // ← condicional
                ),
              ),
              if (right)
                buildGradeDropdownRight(enabled: enabledRight)
              else
                Expanded(child: buildGradeDropdown()),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Build Die
        Center(
          child: ElevatedButton(
            onPressed: right
                ? (_copyLeftToRight ? null : _buildDieRight) // bloquea si está copiando
                : ((_usePart && !_partFound) ? null : _buildDie),
            child: const Text('Build Die'),
          ),
        ),
      ],
    ),
  );
}

// --- Escribe de nuevo los TextFields en la unidad actual ---
void _refreshControllers() {
  barraLengthController.text    = _fmtLen(barraLength / 10);
  alturaInicialController.text  = _fmtLen(alturaInicial / 10);
  naranjaLController.text       = _fmtLen(naranjaL / 10);
  reductionAngleController.text = reductionAngle.toStringAsFixed(1);
  reductionAreaController.text  = _reductionAreaPercent.toStringAsFixed(1);

  // Δ: vacío si None; valor si no
  _refreshDeltaLeft();
}

void _refreshControllers2() {
  barraLengthController2.text    = _fmtLen(barraLength2 / 10);
  alturaInicialController2.text  = _fmtLen(alturaInicial2 / 10);
  reductionAngleController2.text = reductionAngle2.toStringAsFixed(1);
  blMinController2.text          = blMinPercent2.toStringAsFixed(0);
  blMaxController2.text          = blMaxPercent2.toStringAsFixed(0);

  final inMm  = alturaInicial2 / 10.0;
  final outMm = barraLength2  / 10.0;
  reductionAreaController2.text =
      _reductionAreaPercentOf(inMm, outMm).toStringAsFixed(1);

  final d2 = _deltaFactorOf(entryMm: inMm, finishedMm: outMm, angleDeg: reductionAngle2);
  // Δ: vacío si None; valor si no
  _refreshDeltaRight();
}

void _refreshDeltaLeft() {
  if (_selectedGrade == 'None') {
    deltaController.text = '';
    return;
  }

  // Lee directamente de los TextFields para no depender de “Build Die”
  final inDiaMm  = _parseLen(alturaInicialController.text);
  final outDiaMm = _parseLen(barraLengthController.text);
  final ang      = double.tryParse(reductionAngleController.text);

  double d;
  if (inDiaMm != null && outDiaMm != null && ang != null) {
    d = _deltaFactorOf(entryMm: inDiaMm, finishedMm: outDiaMm, angleDeg: ang);
  } else {
    // Fallback al getter si algo no se pudo parsear
    d = _deltaFactor;
  }
  deltaController.text = d > 0 ? d.toStringAsFixed(2) : '0.00';
}

void _refreshDeltaRight() {
  if (_selectedGrade2 == 'None') {
    deltaController2.text = '';
    return;
  }

  final inMm  = _parseLen(alturaInicialController2.text);
  final outMm = _parseLen(barraLengthController2.text);
  final ang   = double.tryParse(reductionAngleController2.text);

  double d;
  if (inMm != null && outMm != null && ang != null) {
    d = _deltaFactorOf(entryMm: inMm, finishedMm: outMm, angleDeg: ang);
  } else {
    // Fallback a tus valores de estado
    d = _deltaFactorOf(
      entryMm: alturaInicial2 / 10.0,
      finishedMm: barraLength2 / 10.0,
      angleDeg: reductionAngle2,
    );
  }
  deltaController2.text = d > 0 ? d.toStringAsFixed(2) : '0.00';
}

// ═════════════════════════════════════════════════════════════════
// Dibuja el canvas + (opcionalmente) los campos de texto que deben
// verse en el PDF.  Desactiva el scroll mientras estamos capturando
// para que nada quede fuera del RepaintBoundary.
// ═════════════════════════════════════════════════════════════════
// ──────────────────────────────────────────────────────────────
// * Devuelve el “lienzo completo” (campos + dibujo)             |
// * Se hace scrollable SIEMPRE, así nunca desborda.             |
// ──────────────────────────────────────────────────────────────
Widget _buildCanvas() {
  final bool capturing = _mode != CaptureMode.normal;

  const double _captureBottomBleed = 260.0;
  const double rightUiNormalPx = 300.0;
  final double rightMarginPx   = capturing ? kExtraRight : rightUiNormalPx;
  final double leftMarginPx    = _borderLeftPx;
  
  const double kHeightNormal   = 400.0;
  const double kHeightCapturer = 650.0;

  // 1er dado (siempre)
  final _DieVisual dv1 = _visualForDie(_selectedDieType);

  // Ancho visible de cada bloque (en px)
  final double block1WidthPx = dv1.refW * pxPerMm;

  // Si hay segundo dado, calcula visuales y separaciones
  final bool hasSecond = _compare;

  final double finishedMm = barraLength / 10.0;
  // Ø acabados
  final double finishedMm1 = barraLength / 10.0;
  final double finishedMm2 = barraLength2 / 10.0;

  _DieVisual? dv2;
  double? nR2dec;
  if (hasSecond) {
    dv2   = _visualForDie(_secondDieType);
    nR2dec = _backReliefDiameterMmWithAngle(finishedMm2, dv2.angSup) * 10.0;
  }

  // Ancho visible del 2º bloque (si hay)
  final double block2WidthPx = hasSecond ? (dv2!.refW * pxPerMm) : 0.0;
  // Espacio entre bloques (si hay)
  final double pairSpacingPx    = hasSecond ? _kPairSpacingPx     : 0.0;
  // Ø acabado actual en mm (sale de tu textbox)
  final double outDiaMm = barraLength / 10.0;
  // Desplazamiento extra a la izquierda del 1er bloque (si hay compare)
  final double firstExtraLeftPx = hasSecond ? 400.0 : 0.0; // ← ajuste al gusto
  // Ancho total de la “escena”
  final double sceneWidthPx =
      leftMarginPx + block1WidthPx + (hasSecond ? pairSpacingPx + block2WidthPx : 0.0) + rightMarginPx;
  // Alto total de la “escena”
  final double sceneHeightPx =
      capturing ? (kHeightCapturer + kExtraDown) : kHeightNormal;
  // Prefijo según el estado de Custom Die
  final String _labelPrefix = _customDie ? 'Custom' : 'Stock';
  // Títulos para cada dibujo
  final String dieTitle1 = '$_labelPrefix $_selectedDieType';
  // final String dieTitle1 = hasSecond ? '$_labelPrefix $_selectedDieType (1st)' : '$_labelPrefix $_selectedDieType';
  final String dieTitle2 = '$_labelPrefix $_secondDieType'; // si hay compare
  // Back-relief por dado (en décimas) usando su ángulo superior propio
  final double nR1dec = _backReliefDiameterMmWithAngle(finishedMm1, dv1.angSup) * 10.0;

// Painter 1 (izq) – SIN cambios relevantes salvo finishedMm1
final painter1 = AdjustableShapePainter(
  naranjaL          : naranjaL,
  naranjaR          : nR1dec,
  barraLength       : barraLength,
  azulOffsetX       : azulOffsetX,
  alturaInicial     : alturaInicial,
  reductionAngle    : reductionAngle,
  angleSuperior     : dv1.angSup,
  angleInferior     : dv1.angInf,
  cafeGrisLengthDec : cafeGrisLengthDec,
  showInches        : _showInches,
  hideRightCota     : !_showConstruction,
  dieType           : _selectedDieType,
  dieWidthMm        : dv1.dieW,
  dieHeightMm       : dv1.dieH,
  sx                : dv1.sx,
  sy                : dv1.sy,
  refWidthMm        : dv1.refW,
  refHeightMm       : dv1.refH,
  borderLeftPx      : _borderLeftPx,
  showDieWidthDim   : _showConstruction,
  yOffsetPx         : _yOffsetPx,
  xOffsetPx         : _xOffsetPx,
  dieTitle          : '$_labelPrefix $_selectedDieType',
  showDeltaRails    : _showConstruction && _selectedGrade != 'None',
  grade             : _selectedGrade,
  delta             : _deltaFactor,           // ← el de la izquierda (tu getter)
  deltaMin          : _deltaMin,
  deltaMax          : _deltaMax,
  finishedDiameterMm: finishedMm1,
);

// Painter 2 (der) – usa TODOS los “2”
AdjustableShapePainter? painter2;
double secondTranslateX = 0.0;

if (hasSecond) {
  // OPCIÓN A: usa un local no-nulo (recomendado)
  final _DieVisual dv2Local = _visualForDie(_secondDieType);
  final double nR2decLocal =
      _backReliefDiameterMmWithAngle(finishedMm2, dv2Local.angSup) * 10.0;

  painter2 = AdjustableShapePainter(
    naranjaL          : naranjaL2,
    naranjaR          : nR2decLocal,
    barraLength       : barraLength2,
    azulOffsetX       : azulOffsetX2,
    alturaInicial     : alturaInicial2,
    reductionAngle    : reductionAngle2,
    angleSuperior     : dv2Local.angSup,
    angleInferior     : dv2Local.angInf,
    cafeGrisLengthDec : cafeGrisLengthDec2,
    showInches        : _showInches,
    hideRightCota     : !_showConstruction,
    dieType           : _secondDieType,
    dieWidthMm        : dv2Local.dieW,
    dieHeightMm       : dv2Local.dieH,
    sx                : dv2Local.sx,
    sy                : dv2Local.sy,
    refWidthMm        : dv2Local.refW,
    refHeightMm       : dv2Local.refH,
    borderLeftPx      : _borderLeftPx,
    showDieWidthDim   : _showConstruction,
    yOffsetPx         : _yOffsetPx,
    xOffsetPx         : _xOffsetPx,
    dieTitle          : '$_labelPrefix $_secondDieType',
    showDeltaRails    : _showConstruction && _selectedGrade2 != 'None',
    grade             : _selectedGrade2,
    delta             : _deltaFactorOf(
    entryMm           : alturaInicial2 / 10.0,
    finishedMm        : finishedMm2,
    angleDeg          : reductionAngle2),
    deltaMin          : _deltaMin2,
    deltaMax          : _deltaMax2,
    finishedDiameterMm: finishedMm2,
  );

  secondTranslateX = dv1.refW * pxPerMm + _kPairSpacingPx + _secondCanvasDx;
}

  // Composición visual (ambos centrados dentro del “stage” con un pequeño shift)
  final Widget bothCanvases = Transform.translate(
    offset: const Offset(_kCanvasShiftX, 0),
    child: SizedBox(
      width:  sceneWidthPx,
      height: sceneHeightPx,
      child: Stack(
        children: [
          // Primer dibujo
          // Primer dibujo (mover más a la izquierda sólo en compare)
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(-firstExtraLeftPx, 0), // ← desplazamiento del 1er dado
              child: CustomPaint(painter: painter1),
            ),
          ),
          // Segundo dibujo (si aplica), trasladado a la derecha
          if (hasSecond)
            Transform.translate(
              offset: Offset(secondTranslateX, 0),
              child: CustomPaint(painter: painter2),
            ),
        ],
      ),
    ),
  );

  // Al capturar, ponemos el canvas centrado y debajo los chips/resumen
  return Stack(
    children: [
      if (capturing)
        SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: bothCanvases),
              const SizedBox(height: 18),
              _buildParamSummary(),
              const SizedBox(height: _captureBottomBleed),
            ],
          ),
        )
      else
        Center(child: bothCanvases),
    ],
  );
}

// ─── resumen que irá dentro del PDF ─────────────────────────────
Widget _buildParamSummary() {
  // lista base (siempre)
  final chips = <Widget>[
    _paramChip('Finished Ø', _fmtLen(barraLength / 10)),
    _paramChip('Entry Ø',    _fmtLen(alturaInicial / 10)),
    _paramChip('Red. Angle', '${reductionAngle.toStringAsFixed(1)}°'),
    _paramChip('Reduction Area', '${_reductionAreaPercent.toStringAsFixed(1)} %'),
    _paramChip('BL min',     '${blMinPercent.toStringAsFixed(0)} %'),
    _paramChip('BL max',     '${blMaxPercent.toStringAsFixed(0)} %'),
    
  ];

  // ► Sólo para “Show Construction”
if (_showConstruction) {
  chips.add(_paramChip('Delta', _deltaFactor.toStringAsFixed(2)));
  chips.add(_paramChip('Grade', _selectedGrade));

  final pn  = partNoController.text.trim();
  final pmp = pmpController.text.trim();

  if (pn.isNotEmpty)  chips.add(_paramChip('Part #', pn));
  if (pmp.isNotEmpty) chips.add(_paramChip('PMP',    pmp));
}

  return Wrap(
    alignment: WrapAlignment.center,
    spacing: kWrapSpacing,
    runSpacing: 6,
    children: chips,
  );
}

// pill visual
Widget _paramChip(String label, String value) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: Colors.grey.shade200,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.black54),
  ),
  child: RichText(
    text: TextSpan(
      style: const TextStyle(color: Colors.black, fontSize: 12),
      children: [
        TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(text: value),
      ],
    ),
  ),
);

// ──────────────────────────────────────────────────────────────
// Limpia los TextEditingController y otros recursos al cerrar
@override
void dispose() {
  barraLengthController.dispose();
  naranjaLController.dispose();
  alturaInicialController.dispose();
  reductionAngleController.dispose();
  blMinController.dispose();
  blMaxController.dispose();
  partNoController.dispose();
  pmpController.dispose();
  reductionAreaController.dispose();

  // controladores del segundo dado (compare)
  barraLengthController2.dispose();
  alturaInicialController2.dispose();
  reductionAngleController2.dispose();
  blMinController2.dispose();
  blMaxController2.dispose();
  reductionAreaController2.dispose();
  deltaController2.dispose();
  // fin controladores segundo dado

  super.dispose();
}
// ──────────────────────────────────────────────────────────────

Widget _buildControls() {
  // ── Ajustes locales para Compare ───────────────────────────────
  const double kCompareMiddleGap = 320.0; // separación entre columnas
  const double kLeftNudge  = 0.0;         // empuja la col. izquierda a la IZQ (negativo)
  const double kRightNudge = 0.0;         // empuja la col. derecha a la DER (positivo)
  // ───────────────────────────────────────────────────────────────

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 24),
      const SizedBox(height: _kGapCanvasToSelectors),

      // Die Type(s) — solo el de un dado cuando NO hay compare
      if (!_compare)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildDieTypeSelector(),
          ],
        ),
      const SizedBox(height: 12),

      // CUERPO DE FORMULARIOS
      if (_compare)
        Center(
          child: SizedBox(
            // ancho total para poder separar las dos columnas
            width: kPanelWidth * 2 + kCompareMiddleGap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // COLUMNA IZQUIERDA
                Transform.translate(
                  offset: const Offset(kLeftNudge, 0),
                  child: SizedBox(
                    width: kPanelWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: _buildDieTypeSelector(),
                        ),
                        const SizedBox(height: 12),
                        _sidePanel(right: false),
                      ],
                    ),
                  ),
                ),

                // COLUMNA DERECHA
                Transform.translate(
                  offset: const Offset(kRightNudge, 0),
                  child: SizedBox(
                    width: kPanelWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: _buildSecondDieTypeSelector(),
                        ),
                        const SizedBox(height: 12),
                        _sidePanel(right: true),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
      else
        // Layout original de una sola columna
        Wrap(
          alignment: WrapAlignment.center,
          spacing: kWrapSpacing,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 40,
              height: 90,
              child: Center(
                child: IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings),
                  color: kPdRed,
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  onPressed: _openSettings,
                ),
              ),
            ),
            //buildPartNumberBlock(), //DESCOMENTAR PARA ACTIVAR RC TOOL
            buildInputDiameterField(),
            buildCompactField(
              "Finished Diameter (${_unit()})",
              barraLengthController,
              (_){},
              isError: (!_customDie && _fdOutOfRange),
            ),
            _buildReductionAngleInput(),
            buildCompactField("Min Bearing Length (%)", blMinController, (_){ }),
            buildCompactField("Max Bearing Length (%)", blMaxController, (_){ }),
            buildReadOnlyField("Reduction Area (%)", reductionAreaController, width: 120),
            _buildDeltaAndGrade(),
            const SizedBox(height: 0),
          ],
        ),

      const SizedBox(height: 8),

      // BOTONES: en compare sólo se muestran centrados los toggles;
      // los Build Die están dentro de cada columna
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (!_compare)
            OutlinedButton(
              onPressed: (_usePart && !_partFound) ? null : _buildDie,
              child: const Text('Build Die', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          OutlinedButton(
            onPressed: () => setState(() => _showConstruction = !_showConstruction),
            child: Text(_showConstruction ? 'Hide Construction' : 'Show Construction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          OutlinedButton(
            onPressed: () => setState(() => _compare = !_compare),
            child: Text(_compare ? 'Hide Comparison' : 'Compare Die', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
        ],
      ),
    ],
  );
}

// ──────────────────────────────────────────────────────────────
//  UI principal
// ──────────────────────────────────────────────────────────────
@override
Widget build(BuildContext context) {
  final bool capturing = _mode != CaptureMode.normal;

  return Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
       backgroundColor: const Color.fromARGB(255, 160, 164, 167),
      centerTitle: true,
      toolbarHeight: 100,
      title: Image.asset(
        'assets/images/titulo5-logo.png',
        height: 60,
        fit: BoxFit.contain,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(3, 3),
                  ),
                ],
              ),
              child: const Text(
                "V 1.3.2",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ),
      ],
    ),

    // ───────── CUERPO ─────────
body: LayoutBuilder(
  builder: (context, constraints) {
    final bool capturing = _mode != CaptureMode.normal;

    // ── Stage a tamaño de diseño fijo (se escalará y centrará) ──
    final stage = SizedBox(
      width: kStageW,
      height: kStageH,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Zona del dibujo con alto fijo
          SizedBox(
            height: capturing ? kCanvasHCapture : kCanvasHNormal,
            child: Center(
              child: RepaintBoundary(
                key: _captureKey,
                child: _buildCanvas(),
              ),
            ),
          ),

          const SizedBox(height: 16),

        // Panel de controles (solo cuando NO capturas)
        if (!capturing)
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, _kControlsUpShiftPx),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1500),
                    child: _buildControls(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // ── FittedBox: centra y escala el stage para que SIEMPRE quepa ──
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: stage,
      ),
    );
  },
),

  );
}

/// Selector de unidades (mm / in) independiente
Widget buildUnitSwitch() {
  const double switchZoneWidth = 90;
  const double fieldHeight = 48;

  return SizedBox(
    width: switchZoneWidth,
    height: fieldHeight,
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('mm', style: TextStyle(fontSize: 10)),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _showInches,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) {
                setState(() {
                  _showInches = v;
                  _refreshControllers();
                });
              },
            ),
          ),
          const Text('in', style: TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
}

Widget buildCompactField(
  String label,
  TextEditingController controller,
  void Function(String) onChanged, {
  double width = kFieldWidth,
  bool enabled = true,
  bool isError = false, // 👈 NUEVO
}) {
  return SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: isError ? Colors.red : Colors.black45, // borde rojo en error
                width: 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: isError ? Colors.red : kPdRed, // rojo también en foco si error
                width: 1.4,
              ),
            ),
            filled: isError,
            fillColor: isError ? const Color(0xFFFFE5E5) : null, // fondo rojo claro
          ),
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

// ─── CAMPO «Input Diameter» con selector mm / in ──────────────────────────
Widget buildInputDiameterField() {
  const double fieldHeight     = 48;   // altura estándar del TextField

  return SizedBox(
    width: kFieldWidth,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      Text(
        'Entry Diameter (${_unit()})',
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
      const SizedBox(height: 4),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,   // alinea arriba
          children: [
            // ❶ TextField
            Expanded(
              child: TextField(
                controller: alturaInicialController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => _invalidatePart(),     
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ],
    ),
  );
}

// ─── CAMPO SOLO-LECTURA (ancho ajustable) ──────────────────────
Widget buildReadOnlyField(
  String label,
  TextEditingController c, {
  double width = kFieldWidth,
  Color? fill,                         // 👈 NUEVO
}) {
  return SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          readOnly: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: fill ?? const Color(0xFFEFEFEF), // usa color si llega
          ),
        ),
      ],
    ),
  );
}

///  Bloque «Build by Part Number» listo para meterse en el Wrap de FILA 1
Widget buildPartNumberBlock() {
  return IntrinsicWidth( // permite que el ancho crezca/encoga y empuje a los vecinos
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'RC Tool',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black87),
        ),
        const SizedBox(height: 6),

        // Fila: Switch + (textbox a la derecha cuando ON)
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: _usePart,
                onChanged: (v) {
                  setState(() {
                    _usePart   = v;
                    _partFound = false;
                    _partMsg   = '';
                    if (!v) {
                      partNoController.clear();
                      FocusScope.of(context).unfocus();
                    }
                  });
                },
              ),
              const SizedBox(width: 8),

              // TextField aparece a la derecha del switch
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    SizeTransition(sizeFactor: anim, axis: Axis.horizontal, child: child),
                child: _usePart
                    ? SizedBox(
                        key: const ValueKey('pn-field'),
                        width: 200, // ajusta si quieres
                        child: TextField(
                          controller: partNoController,
                          decoration: const InputDecoration(
                            labelText: 'Part Number',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _checkPart(),
                        ),
                      )
                    : const SizedBox(key: ValueKey('pn-empty')),
              ),
            ],
          ),
        ),

        if (_partMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _partMsg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _partFound ? Colors.green : Colors.red,
              ),
            ),
          ),
      ],
    ),
  );
}

  // Builds labeled input field with controller and callback
Widget buildTextField(
  String label,
  TextEditingController controller,
  Function(String) onChanged, {
  double maxWidth = 300,          // ←  ajuste a tu gusto
}) {
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 160,              // ancho uniforme
            child: Text(
              label,
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(border: OutlineInputBorder()),
              //onSubmitted: onChanged,
            ),
          ),
        ],
      ),
    ),
  );
}

void _onPnEntered(String pn) {
  final spec = parsePartNumber(pn);
  if (spec == null) {
    // mostrar error PN inválido
    return;
  }
  // usar spec para llenar UI / dibujar
}


}

// ===================== TOP-LEVEL: modelos y parser PN =====================

class DieSpec {
  final String series;
  final int reductionAngleDeg;
  final String materialCode;
  final double finishedDiaIn;
  final double? backReliefIn;
  final int? blMinPct;
  final int? blMaxPct;
  final String? operationCode;
  final double? tolerPlusIn;
  final double? tolerMinusIn;

  const DieSpec({
    required this.series,
    required this.reductionAngleDeg,
    required this.materialCode,
    required this.finishedDiaIn,
    this.backReliefIn,
    this.blMinPct,
    this.blMaxPct,
    this.operationCode,
    this.tolerPlusIn,
    this.tolerMinusIn,
  });
}

class DieTolerance {
  final double plus;
  final double minus;
  const DieTolerance(this.plus, this.minus);
}

// A: estándar con back relief y op: TR6-12P.2054-320N-0C
final RegExp _reStd = RegExp(
  r'^TR(\d+)-(\d{2})([A-Z])\.(\d{4})-(\d{3,4})([A-Z])-0([A-Z#])$'
);

// B: con BL% (MMNN): TR4-18P.1100-2535-0C
final RegExp _reWithBLPct = RegExp(
  r'^TR(\d+)-(\d{2})([A-Z])\.(\d{4})-(\d{4})-0([A-Z])$'
);

// C: familia TRxD...: TR4D10F.0200-178N-0B
final RegExp _reTRxD = RegExp(
  r'^TR(\d+)D(\d{2})([A-Z])\.(\d{4})-(\d{3,4})([A-Z])-0([A-Z])$'
);

DieSpec? parsePartNumber(String pn) {
  pn = pn.trim();

  // Caso C: TRxD...
  final mC = _reTRxD.firstMatch(pn);
  if (mC != null) {
    final series = 'TR${mC.group(1)!}D';
    final angle  = int.parse(mC.group(2)!);
    final mat    = mC.group(3)!;
    final fd     = int.parse(mC.group(4)!)/10000.0;
    final br     = int.parse(mC.group(5)!)/1000.0;
    final op     = mC.group(6)!;
    final tol    = mC.group(7)!;

    var tolPair = _toleranceFromSuffix(series, angle, mat, fd, tol);
    if (series == 'TR4D' && angle == 10 && mat == 'F') {
      tolPair = DieTolerance(0.0, _minusTolTR4D10F(fd));
    }

    return DieSpec(
      series: series,
      reductionAngleDeg: angle,
      materialCode: mat,
      finishedDiaIn: fd,
      backReliefIn: br,
      operationCode: op,
      tolerPlusIn: tolPair.plus,
      tolerMinusIn: tolPair.minus,
    );
  }

  // Caso A: estándar con back relief y op
  final mA = _reStd.firstMatch(pn);
  if (mA != null) {
    final series = 'TR${mA.group(1)!}';
    final angle  = int.parse(mA.group(2)!);
    final mat    = mA.group(3)!;
    final fd     = int.parse(mA.group(4)!)/10000.0;
    final br     = int.parse(mA.group(5)!)/1000.0;
    final op     = mA.group(6)!;
    final tol    = mA.group(7)!;

    final tolPair = _toleranceFromSuffix(series, angle, mat, fd, tol);
    return DieSpec(
      series: series,
      reductionAngleDeg: angle,
      materialCode: mat,
      finishedDiaIn: fd,
      backReliefIn: br,
      operationCode: op,
      tolerPlusIn: tolPair.plus,
      tolerMinusIn: tolPair.minus,
    );
  }

  // Caso B: BL% MMNN (sin op, sin back relief)
  final mB = _reWithBLPct.firstMatch(pn);
  if (mB != null) {
    final series = 'TR${mB.group(1)!}';
    final angle  = int.parse(mB.group(2)!);
    final mat    = mB.group(3)!;
    final fd     = int.parse(mB.group(4)!)/10000.0;
    final blStr  = mB.group(5)!; // p.ej. "2535"
    final blMin  = int.parse(blStr.substring(0,2));
    final blMax  = int.parse(blStr.substring(2,4));
    final tol    = mB.group(6)!;

    final tolPair = _toleranceFromSuffix(series, angle, mat, fd, tol);
    return DieSpec(
      series: series,
      reductionAngleDeg: angle,
      materialCode: mat,
      finishedDiaIn: fd,
      blMinPct: blMin,
      blMaxPct: blMax,
      operationCode: null,
      tolerPlusIn: tolPair.plus,
      tolerMinusIn: tolPair.minus,
    );
  }

  return null; // PN no reconocido
}

DieTolerance _toleranceFromSuffix(String series, int angle, String mat, double fd, String tolCode) {
  switch (tolCode) {
    case '#':  return const DieTolerance(0.0, 0.0025);
    case 'B':  return const DieTolerance(0.0, 0.0);
    case 'C':  return const DieTolerance(0.0, 0.0);
    case 'A':  // TR4D10F micros
      return const DieTolerance(0.0, 0.0008);
    default:
      return const DieTolerance(0.0, 0.0);
  }
}

// Regla especial para la subfamilia TR4D10F (microdiámetros)
double _minusTolTR4D10F(double fd) {
  if (fd <= 0.0100) return 0.0008;
  if (fd <= 0.0200) return 0.0010;
  if (fd <= 0.0330) return 0.0012;
  if (fd <= 0.0480) return 0.0014;
  return 0.0016; // ≥ 0.0515
}


// Radios nominales (mm) por tipo de dado
const Map<String, double> kFilletRadiusByDie = {
  'TR4' : 2.5,
  'TR4D': 2.5,
  'TR6' : 6,
  'TR8' : 4,
};

// =================== Filete: arranque fijo + tangencia a rampa ===================
class _FixedFilletSolution {
  final double r;
  final Offset c;
  final Offset t;
  const _FixedFilletSolution(this.r, this.c, this.t);
}

_FixedFilletSolution _solveFixedStartFillet({
  required double xWall,   // x de la pared (p1.dx o p2.dx)
  required double yStart,  // y fijo donde arranca (en px)
  required double m,       // pendiente de la rampa
  required double b,       // ordenada de la rampa
  required double rMax,    // radio máximo permitido (px)
}) {
  final root = sqrt(1 + m * m);

  double bestR = 0;
  for (final s in const [1.0, -1.0]) {
    final nume = yStart - (m * xWall + b);
    final deno = (m - s * root);
    if (deno.abs() < 1e-9) continue;
    final r = nume / deno;
    if (r > 0 && (bestR == 0 || r < bestR)) bestR = r;
  }

  if (bestR <= 0) bestR = 0;
  if (bestR > rMax) bestR = rMax;

  final cx = xWall + bestR;
  final cy = yStart;
  final xt = (cx + m * (cy - b)) / (1 + m * m);
  final yt = m * xt + b;

  return _FixedFilletSolution(bestR, Offset(cx, cy), Offset(xt, yt));
}

// ===== Nuevo helper para TR6: NO tangente a pared; SÍ tangente a rampa =====
class _FilletNT {
  final double r;   // radio
  final Offset c;   // centro del círculo
  final Offset t;   // punto de tangencia en la rampa
  const _FilletNT(this.r, this.c, this.t);
}

/// Resuelve un círculo que:
///   • pasa por 'start' (arranque en pared)
///   • es tangente a la rampa y = m x + b en un punto T dentro [xMin, xMax]
///   • r <= rMax
_FilletNT? _solveStartNonTangent({
  required Offset start,
  required double m,
  required double b,
  required double xMin,
  required double xMax,
  required double rMax,
  double minStartAngleDeg = 10, // ⬅️ ángulo mínimo vs. vertical
}) {
  final double R = sqrt(1 + m * m);
  final double minA = minStartAngleDeg * pi / 180.0;
  _FilletNT? best;

  const int N = 48;
  for (int i = 0; i <= N; i++) {
    final double x = xMin + (xMax - xMin) * i / N;
    final double y = m * x + b;

    final double A = start.dx - x;
    final double B = start.dy - y;
    final double denom = (A * m - B);
    if (denom.abs() < 1e-9) continue;

    final double r = (R * (A * A + B * B)) / (2.0 * denom.abs());
    if (!r.isFinite || r <= 0 || r > rMax) continue;

    final double s = denom >= 0 ? 1.0 : -1.0;
    final Offset nHat = Offset(-m, 1) / R;
    final Offset t = Offset(x, y);
    final Offset c = t - nHat * (s * r);

    // ⬅️ chequeo de “no tangente” en el arranque:
    // ángulo del radio en el arranque vs. horizontal (0 = peor caso)
    final double angFromHorizontal =
        (atan2(start.dy - c.dy, start.dx - c.dx)).abs();
    if (angFromHorizontal < minA) continue; // descarta casi tangentes

    if (best == null || r > best!.r) best = _FilletNT(r, c, t);
  }
  return best;
}

/// Dibuja un arco circular (corto) entre start→end con centro y radio dados.
void _addArcWithCenter(Path p, Offset start, Offset end, Offset center, double r) {
  double a0 = atan2(start.dy - center.dy, start.dx - center.dx);
  double a1 = atan2(end.dy   - center.dy, end.dx   - center.dx);
  double sweep = a1 - a0;
  if (sweep <= -pi) sweep += 2 * pi;  // arco corto
  if (sweep >   pi) sweep -= 2 * pi;
  p.arcTo(Rect.fromCircle(center: center, radius: r), a0, sweep, false);
}

class AdjustableShapePainter extends CustomPainter {
  final double naranjaL;
  final double naranjaR;
  final double barraLength;
  final double azulOffsetX;
  final double alturaInicial;
  final TextEditingController reductionAngleController = TextEditingController();
  final double reductionAngle;
  final double angleSuperior;
  final double angleInferior;
  final double cafeGrisLengthDec; // en décimas
  final bool showInches;  
  final bool hideRightCota;  
  final String dieType;  
  final double dieWidthMm;
  final double dieHeightMm;
  final double sx;        // escala horizontal mm→px
  final double sy;        // escala vertical   mm→px
  final double refWidthMm;
  final double refHeightMm;
  final double borderLeftPx;
  final bool showDieWidthDim;
  final double yOffsetPx;
  final double xOffsetPx;
  bool get isTR6Family => dieType == 'TR6' || dieType == 'TR8';
  final String dieTitle;
  final bool showDeltaRails;
  final String grade;
  final double delta;
  final double deltaMin;
  final double deltaMax;
  final double finishedDiameterMm;

  AdjustableShapePainter({
    required this.naranjaL,
    required this.naranjaR,
    required this.barraLength,
    required this.azulOffsetX,
    required this.alturaInicial,
    required this.reductionAngle,
    required this.angleSuperior,
    required this.angleInferior,
    required this.cafeGrisLengthDec,
    required this.showInches,
    required this.hideRightCota, 
    required this.dieType,
    required this.dieWidthMm,
    required this.dieHeightMm,
    required this.sx,
    required this.sy,
    required this.refWidthMm,
    required this.refHeightMm,
    required this.borderLeftPx,
    required this.showDieWidthDim,
    required this.yOffsetPx,
    required this.xOffsetPx,
    required this.dieTitle,
    required this.showDeltaRails,
    required this.grade,
    required this.delta,
    required this.deltaMin,
    required this.deltaMax,
    required this.finishedDiameterMm,

  });

// ─────────────────────────────────────────────────────────────
/// Devuelve el mayor radio que aún mantiene tangencia con la
/// pared vertical (corner) y la rampa que pasa por slopePoint.
/// wantRpx = radio nominal que te gustaría usar.
double _bestFilletRadiusPx({
  required Offset corner,
  required Offset slopePoint,
  required double wantRpx,
}) {
  final dx    = slopePoint.dx - corner.dx;
  final dyAbs = (slopePoint.dy - corner.dy).abs();
  final theta = atan2(dyAbs, dx);          // 0..π/2 rad
  final rMax  = min(dx / cos(theta), dyAbs / sin(theta));
  return min(wantRpx, rMax);
}
// ─────────────────────────────────────────────────────────────

// === Δ-rails: configuración por Die Type **y** Drawn Material ============

// Baseline de Entry del que parten los pads (ajústalo si quieres)
static const double _railPadBaselineEntryMm = 2.0;

// Límites de seguridad (px)
static const double _railPadMinPx = 2.0;
static const double _railPadMaxPx = 48.0;

// ⚠️ MAPAS *por DIE TYPE* y *por MATERIAL* -------------------------------
// (Pon aquí los números que quieras para cada die/material. Dejo iniciales.)
static const Map<String, Map<String, double>> _railPadBasePxByDieAndGrade = {
  'TR4' :      { 'Custom': 9.0, 'Low Carbon': 4.0, 'High Carbon': 4.0, 'Stainless': 4.0 },
  'TR4D':      { 'Custom': 9.0, 'Low Carbon': 4.0, 'High Carbon': 4.0, 'Stainless': 4.0 },
  'TR6' :      { 'Custom': 9.0, 'Low Carbon': 4.0, 'High Carbon': 4.0, 'Stainless': 4.0 },
  'TR8' :      { 'Custom': 9.0, 'Low Carbon': 4.0, 'High Carbon': 4.0, 'Stainless': 4.0 },
};

// Pendiente (px por cada 1 mm de Entry por encima/debajo del baseline)
static const Map<String, Map<String, double>> _railPadGrowPxPerMmByDieAndGrade = {
  'TR4' :      { 'Custom': 6.5, 'Low Carbon': 5.0, 'High Carbon': 4.5, 'Stainless': 4.5 },
  'TR4D':      { 'Custom': 6.5, 'Low Carbon': 5.0, 'High Carbon': 4.5, 'Stainless': 4.5 },
  'TR6' :      { 'Custom': 6.5, 'Low Carbon': 5.0, 'High Carbon': 4.5, 'Stainless': 4.5 },
  'TR8' :      { 'Custom': 6.5, 'Low Carbon': 5.0, 'High Carbon': 4.5, 'Stainless': 4.5 },
};

// Valores *por material* de respaldo (si no pones entrada para algún die/material)
static const Map<String, double> _railPadBasePxByGradeFallback = {
  'Custom': 9.0, 'Low Carbon': 4.0, 'High Carbon': 4.0, 'Stainless': 4.0,
};
static const Map<String, double> _railPadGrowPxPerMmByGradeFallback = {
  'Custom': 6.5, 'Low Carbon': 5.0, 'High Carbon': 4.5, 'Stainless': 4.5,
};

// Entry actual en mm (alturaInicial llega en décimas)
double get _entryMm => alturaInicial / 10.0;

// Helpers de lectura con *fallback* elegante
double _padBasePxFor(String die, String grade) {
  final m = _railPadBasePxByDieAndGrade[die];
  return (m != null && m[grade] != null)
      ? m[grade]!
      : (_railPadBasePxByGradeFallback[grade] ?? 6.0);
}
double _padGrowPxPerMmFor(String die, String grade) {
  final m = _railPadGrowPxPerMmByDieAndGrade[die];
  return (m != null && m[grade] != null)
      ? m[grade]!
      : (_railPadGrowPxPerMmByGradeFallback[grade] ?? 1.0);
}

// Pad final (px) = base(die,grade) + slope(die,grade) * (Entry - baseline)
double get _railPadPx {
  final base   = _padBasePxFor(dieType, grade);
  final slope  = _padGrowPxPerMmFor(dieType, grade);
  final deltaM = _entryMm - _railPadBaselineEntryMm;
  final pad    = base + slope * deltaM;
  return pad.clamp(_railPadMinPx, _railPadMaxPx);
}

   @override
  void paint(Canvas canvas, Size size) {
  canvas.save();
  canvas.translate(xOffsetPx, -yOffsetPx); // desplaza todo el dibujo
  // Al inicio de paint()
  const mmToPx = 30.0;
  // ↑ al inicio de paint(), junto a otras vars locales
  Offset? _tr4dRedEndTop; // extremo interior de la línea roja superior
  Offset? _tr4dRedEndBot; // extremo interior de la línea roja inferior
  final bool isTR6Family = (dieType == 'TR6' || dieType == 'TR8');  // ✅

  final int dec = showInches ? 4 : 3;
  //final bool _showGreen = showDeltaRails && (grade != 'None');

  String lenStr(double mm) => showInches
      ? "${(mm / 25.4).toStringAsFixed(dec)} in"
      : "${mm.toStringAsFixed(dec)} mm";

    double mm(double decimas) => (decimas / 10.0) * mmToPx;

  final rectMargin = 10.0;
  final extraWidth = 20.0;
  
  final borderRect = Rect.fromLTWH(
    borderLeftPx, 50,
    refWidthMm  * mmToPx,
    refHeightMm * mmToPx,
  );

  final double anchoRealMm = dieWidthMm;
  final altoEnMM = borderRect.height / mmToPx;

  final borderRadius = Radius.circular(20);

  // AHORA sí calcula centerY basado en borderRect
  final centerY = borderRect.top + borderRect.height / 2;

  final textStyleCota = TextStyle(color: Colors.black, fontSize: 10);
  final tpCota = TextPainter(textDirection: TextDirection.ltr);

  void drawCota(String txt, Offset pos) {
    tpCota.text = TextSpan(text: txt, style: textStyleCota);
    tpCota.layout();
    tpCota.paint(canvas, pos);
  }

double mmX(double decimas) => (decimas / 10.0) * mmToPx * sx; // horiz
double mmY(double decimas) => (decimas / 10.0) * mmToPx * sy; // vert

double pxToMmX(double px) => px / (mmToPx * sx); // horiz: px → mm reales
double pxToMmY(double px) => px / (mmToPx * sy); // vert : px → mm reales

// Alturas y largos
final barraPx        = mmY(barraLength);          // (vertical)
final alturaPx       = mmY(alturaInicial);        // (vertical)
final cafeGrisLength = mmX(cafeGrisLengthDec);    // (horizontal)

// Coordenadas que usan alturas → mmY(...)
final p1 = Offset(borderRect.left,  centerY - mmY(naranjaL) / 2);
final p2 = Offset(borderRect.left,  centerY + mmY(naranjaL) / 2);
final p9 = Offset(borderRect.right, centerY - mmY(naranjaR) / 2);
final p10= Offset(borderRect.right, centerY + mmY(naranjaR) / 2);

// ahora usa esas escaladas:
final azulTop = Offset(azulOffsetX, centerY - barraPx / 2);
final azulBottom = Offset(azulOffsetX, centerY + barraPx / 2);

final cafeLeft = Offset(azulOffsetX - cafeGrisLength / 2, azulTop.dy);
final cafeRight = Offset(azulOffsetX + cafeGrisLength / 2, azulTop.dy);

final grisLeft = Offset(azulOffsetX - cafeGrisLength / 2, azulBottom.dy);
final grisRight = Offset(azulOffsetX + cafeGrisLength / 2, azulBottom.dy);

// === BASES QUE SE USAN EN MUCHAS PARTES (deben ir ANTES de su primer uso) ===
final double topY = centerY - alturaPx / 2;
final double botY = centerY + alturaPx / 2;

// Rampas de reducción (superior e inferior)
final double mReduceSup = (cafeLeft.dy - p1.dy) / (cafeLeft.dx - p1.dx);
final double bReduceSup = p1.dy - mReduceSup * p1.dx;

final double mReduceInf = (grisLeft.dy - p2.dy) / (grisLeft.dx - p2.dx);
final double bReduceInf = p2.dy - mReduceInf * p2.dx;


// --- Cota roja izquierda (longitud horizontal junto a la pared) ---
// Medimos sobre la rampa superior: desde la pared (p1) hasta el inicio de la zona B (xB)
final double xBsup = (topY - bReduceSup) / mReduceSup;    // ya calculaste mReduceSup/bReduceSup
final Offset leftCotaA = p1;                               // pared izq. arriba
final Offset leftCotaB = Offset(xBsup, mReduceSup * xBsup + bReduceSup);

// ---- NUEVO: vértices de la pared derecha a partir de naranjaR ----
final halfbrPx = mm(naranjaR / 2);            // naranjaR está en décimas

// Pendientes para mantener los 30° en las rampas externa-interna
final deltaSuperior = p9.dy - cafeRight.dy;    // vertical real
final deltaInferior = grisRight.dy - p10.dy;   // negativo

// Cálculo de longitudes y ángulos (pueden usarse para etiquetas)
final amarilloLen = (p9 - cafeRight).distance;
final amarilloAng = angleSuperior;
final moradoLen = (p10 - grisRight).distance;
final moradoAng = angleInferior;


// === BLOQUE COMPLETO PARA FONDO CON TAPER VERTICAL (con filetes) ===

// 2.5° para TR4/TR4D/TR6, 3.0° para TR8
final double angleDeg = (dieType == 'TR8') ? 3.0 : 2.5;
final double angleRad = angleDeg * pi / 180;
final double taperVertical = tan(angleRad) * borderRect.width;

final double leftTop = borderRect.top;
final double leftBottom = borderRect.bottom;
final double rightTop = borderRect.top + taperVertical;
final double rightBottom = borderRect.bottom - taperVertical;

final double radius = 20.0;

final pathFondo = Path()
  ..moveTo(borderRect.left + radius, leftTop)
  ..arcToPoint(
    Offset(borderRect.left + 1, leftTop + radius),
    radius: Radius.circular(radius),
    clockwise: false,
  )
  ..lineTo(borderRect.left, leftBottom - radius)
  ..arcToPoint(
    Offset(borderRect.left + radius, leftBottom),
    radius: Radius.circular(radius),
    clockwise: false,
  )
  ..lineTo(borderRect.right - radius, rightBottom)
  ..arcToPoint(
    Offset(borderRect.right, rightBottom - radius),
    radius: Radius.circular(radius),
    clockwise: false,
  )
  ..lineTo(borderRect.right, rightTop + radius)
  ..arcToPoint(
    Offset(borderRect.right - radius, rightTop),
    radius: Radius.circular(radius),
    clockwise: false,
  )
  ..close();

final borderFill = Paint()
  ..color = Colors.grey.shade800
  ..isAntiAlias = true  
  ..style = PaintingStyle.fill;

canvas.drawPath(pathFondo, borderFill);

// 1.  Preparamos el texto
final textDie = TextPainter(
  text: TextSpan(
    // ⬇️ antes: text: dieType,
    text: dieTitle, // 👈 usa el label nuevo
    style: const TextStyle(
      fontFamily: 'MYRIAD',
      color: Colors.white,
      fontSize: 48,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      height: 0.5,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();

// 2.  Posición centrada (igual que antes)
final double xDie = (borderRect.left + borderRect.right - textDie.width) / 2;
final double yDie = borderRect.top + 40;

// 3.  Dibujamos
canvas.save();
canvas.clipPath(pathFondo);
textDie.paint(canvas, Offset(xDie, yDie));
canvas.restore();

//==
  // el resto de tu path
  final path = Path()
    ..moveTo(p1.dx, p1.dy)
    ..lineTo(cafeLeft.dx, cafeLeft.dy)
    ..lineTo(cafeRight.dx, cafeRight.dy)
    ..lineTo(p9.dx,  p9.dy)    // respeta la posición exacta
    ..lineTo(p10.dx, p10.dy)
    ..lineTo(grisRight.dx, grisRight.dy)
    ..lineTo(grisLeft.dx, grisLeft.dy)
    ..lineTo(p2.dx, p2.dy)
    ..close();

  final paintFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  canvas.drawPath(path, paintFill);
//==
//==========================================================================================================

// ========== BLOQUE PARA INSERTAR EN paint() ==========

// paint del inserto
final insertoPaint = Paint()
  ..color = Colors.grey.withOpacity(0.5)
  ..style = PaintingStyle.fill;

// *** NUEVO – utilidades globales para el resto de cotas ***
final double dimensionY = (topY + botY) / 2;

// ─── utilidades de cota ─────────────────────────────
const double arrowSize = 5.0;

final Paint dimensionPaint = Paint()
  ..color = Colors.black
  ..strokeWidth = 1;
// ─────────────────────────────────────────────────────

/// Flecha vertical reutilizable
void drawDimLine(Offset p, bool haciaArriba) {
  final double puntaY = haciaArriba ? dimensionY - arrowSize : dimensionY + arrowSize;
  final Path flecha = Path()
    ..moveTo(p.dx - arrowSize, puntaY)
    ..lineTo(p.dx + arrowSize, puntaY)
    ..lineTo(p.dx, dimensionY)
    ..close();
  canvas.drawPath(flecha, dimensionPaint);
}

// pendiente rosa (superior)
final mRosa = (cafeLeft.dy - p1.dy) / (cafeLeft.dx - p1.dx);
final bRosa = p1.dy - mRosa * p1.dx;

// pendiente rojo (inferior)
final mRojo = (grisLeft.dy - p2.dy) / (grisLeft.dx - p2.dx);
final bRojo = p2.dy - mRojo * p2.dx;

// intersección horizontal-inserto con rosa
final xIntersectRosa = (topY - bRosa) / mRosa;
// intersección horizontal-inserto con rojo
final xIntersectRojo = (botY - bRojo) / mRojo;

// ================== INSERTO CON ADHERENCIA A LÍNEAS ROJAS (TR4D) ==================
final insertoPath = Path();

const double gapPx = 40.0;        // margen izquierdo del inserto
final double salidaX = borderRect.right + gapPx;
final double startX  = p1.dx - 30;

// intersecciones horizontales del inserto con la reducción (fallback)
final double xHitReduceTop = (topY - bReduceSup) / mReduceSup;
final double xHitReduceBot = (botY - bReduceInf) / mReduceInf;

if (dieType == 'TR4D') {
  // ---------- SEGMENTOS ROJOS REALES ----------
  Offset? redStartSup, redEndSup, redStartInf, redEndInf;
  double? xHitRedTopSeg, xTransTopSeg;   Offset? pHitRedTopSeg;
  double? xHitRedBotSeg, xTransBotSeg;   Offset? pHitRedBotSeg;

  // Superior (+20°)
  const double kRedDeg = 20.0;
  const double kRedStroke = 4.0;
  const double kLiftSup   = 2.0;
  final  double kRedHalf  = kRedStroke / 2.0;
  const double kRedShiftRightPx = 5.0;
  final double xMidSup = (p1.dx + cafeLeft.dx) / 2;
  final double yMidSup = mReduceSup * xMidSup + bReduceSup;
  final Offset redEnd = Offset(xMidSup, yMidSup).translate(0, kRedHalf - kLiftSup);

  Offset s = redEnd;
  for (double t = 0.5; t < 2000; t += 0.5) {
    final p = redEnd + Offset(-cos(kRedDeg*pi/180), -sin(kRedDeg*pi/180)) * t;
    if (!pathFondo.contains(p)) { s = redEnd + Offset(-cos(kRedDeg*pi/180), -sin(kRedDeg*pi/180)) * (t - 0.5); break; }
  }
  redStartSup = s; redEndSup = redEnd;

  // corte horizontal superior con el SEGMENTO
Offset? hitTop = (() {
  if (redEndSup == null || redStartSup == null) return null; // ← protección
  if ((redEndSup!.dy - redStartSup!.dy).abs() < 1e-6) return null;
  final a = redStartSup!, b = redEndSup!;
  final double y = topY;
  final double yMin = min(a.dy, b.dy) - 3, yMax = max(a.dy, b.dy) + 3;
  if (y < yMin || y > yMax) return null;
  final double t = (y - a.dy) / (b.dy - a.dy);
  if (t < -3 || t > 1 + 3) return null;
  return Offset(a.dx + t * (b.dx - a.dx), y);
})();

  if (hitTop != null && hitTop.dx > startX + 0.5) {
    xHitRedTopSeg = hitTop.dx; pHitRedTopSeg = hitTop;
    final double mRedTop = tan(kRedDeg * pi / 180.0);
    final double bRedTop = redEndSup.dy - mRedTop * redEndSup.dx;
    final double xTrans  = (bReduceSup - bRedTop) / (mRedTop - mReduceSup);
    if (xTrans >= min(redStartSup.dx, redEndSup.dx) - 2 &&
        xTrans <= max(redStartSup.dx, redEndSup.dx) + 2) {
      xTransTopSeg = xTrans;
    }
  } else if (topY <= redEndSup.dy + 2.0) {
    xHitRedTopSeg = redEndSup.dx;
    pHitRedTopSeg = Offset(redEndSup.dx, topY);
    final double mRedTop = tan(kRedDeg * pi / 180.0);
    final double bRedTop = redEndSup.dy - mRedTop * redEndSup.dx;
    final double xTrans  = (bReduceSup - bRedTop) / (mRedTop - mReduceSup);
    if (xTrans >= min(redStartSup.dx, redEndSup.dx) - 2 &&
        xTrans <= max(redStartSup.dx, redEndSup.dx) + 2) {
      xTransTopSeg = xTrans;
    }
  }

  // Inferior (−20°)
  const double kRedStrokeInf = 4.0;
  final double kRedHalfInf   = kRedStrokeInf / 2.0;

  final double xMidInf = (p2.dx + grisLeft.dx) / 2;
  final double yMidInf = mReduceInf * xMidInf + bReduceInf;
  // aplica el corrimiento hacia la derecha
  final Offset redEndInfLoc = Offset(xMidInf, yMidInf)
      .translate(kRedShiftRightPx, -kRedHalfInf);

  Offset s2 = redEndInfLoc;
  for (double t = 0.5; t < 2000; t += 0.5) {
    final p = redEndInfLoc + Offset(-cos(kRedDeg*pi/180),  sin(kRedDeg*pi/180)) * t;
    if (!pathFondo.contains(p)) { s2 = redEndInfLoc + Offset(-cos(kRedDeg*pi/180),  sin(kRedDeg*pi/180)) * (t - 0.5); break; }
  }
  redStartInf = s2; redEndInf = redEndInfLoc;

Offset? hitBot = (() {
  if (redEndInf == null || redStartInf == null) return null; // ← protección
  if ((redEndInf!.dy - redStartInf!.dy).abs() < 1e-6) return null;
  final a = redStartInf!, b = redEndInf!;
  final double y = botY;
  final double yMin = min(a.dy, b.dy) - 3, yMax = max(a.dy, b.dy) + 3;
  if (y < yMin || y > yMax) return null;
  final double t = (y - a.dy) / (b.dy - a.dy);
  if (t < -3 || t > 1 + 3) return null;
  return Offset(a.dx + t * (b.dx - a.dx), y);
})();

  if (hitBot != null && hitBot.dx > startX + 0.5) {
    xHitRedBotSeg = hitBot.dx; pHitRedBotSeg = hitBot;
    final double mRedBot = -tan(kRedDeg * pi / 180.0);
    final double bRedBot = redEndInf.dy - mRedBot * redEndInf.dx;
    final double xTrans  = (bReduceInf - bRedBot) / (mRedBot - mReduceInf);
    if (xTrans >= min(redStartInf.dx, redEndInf.dx) - 2 &&
        xTrans <= max(redStartInf.dx, redEndInf.dx) + 2) {
      xTransBotSeg = xTrans;
    }
  } else if (botY >= redEndInf.dy - 2.0) {
    xHitRedBotSeg = redEndInf.dx;
    pHitRedBotSeg = Offset(redEndInf.dx, botY);
    final double mRedBot = -tan(kRedDeg * pi / 180.0);
    final double bRedBot = redEndInf.dy - mRedBot * redEndInf.dx;
    final double xTrans  = (bReduceInf - bRedBot) / (mRedBot - mReduceInf);
    if (xTrans >= min(redStartInf.dx, redEndInf.dx) - 2 &&
        xTrans <= max(redStartInf.dx, redEndInf.dx) + 2) {
      xTransBotSeg = xTrans;
    }
  }

  // Elegibilidad usando el SEGMENTO (no la recta infinita)
  const double eps = 0.6;
  final bool canUseRedTop =
      xHitRedTopSeg != null && xTransTopSeg != null &&
      xTransTopSeg! > xHitRedTopSeg! + eps && xTransTopSeg! < cafeLeft.dx - eps;
  final bool canUseRedBot =
      xHitRedBotSeg != null && xTransBotSeg != null &&
      xTransBotSeg! > xHitRedBotSeg! + eps && xTransBotSeg! < grisLeft.dx - eps;

  // ---------- Trazo del INSERTO con los tres tramos ----------
  insertoPath.moveTo(startX, topY);

  // TOP EDGE
  if (canUseRedTop) {
    insertoPath.lineTo(pHitRedTopSeg!.dx, pHitRedTopSeg!.dy);                 // horizontal → roja
    final double yTransTop = mReduceSup * xTransTopSeg! + bReduceSup;         // roja → reducción
    insertoPath.lineTo(xTransTopSeg!, yTransTop);
  } else {
    insertoPath.lineTo(xHitReduceTop, topY);                                  // directo a reducción
  }
  insertoPath.lineTo(cafeLeft.dx, cafeLeft.dy);                               // reducción → vértice café

  // RIGHT SIDE
  insertoPath.lineTo(salidaX, cafeRight.dy);
  insertoPath.lineTo(salidaX, grisRight.dy);

  // BOTTOM EDGE (derecha→izquierda)
  insertoPath.lineTo(grisLeft.dx, grisLeft.dy);
  if (canUseRedBot) {
    final double yTransBot = mReduceInf * xTransBotSeg! + bReduceInf;         // reducción → roja
    insertoPath.lineTo(xTransBotSeg!, yTransBot);
    insertoPath.lineTo(pHitRedBotSeg!.dx, pHitRedBotSeg!.dy);                 // roja → horizontal
  } else {
    insertoPath.lineTo(xHitReduceBot, botY);
  }
  insertoPath.lineTo(startX, botY);
  insertoPath.close();
  canvas.drawPath(insertoPath, insertoPaint);

} else {
  // ========= TR4 SIN CAMBIOS =========
  insertoPath
    ..moveTo(startX, topY)
    ..lineTo(xHitReduceTop, topY)          // directo a la reducción
    ..lineTo(cafeLeft.dx, cafeLeft.dy)
    ..lineTo(salidaX, cafeRight.dy)
    ..lineTo(salidaX, grisRight.dy)
    ..lineTo(grisLeft.dx, grisLeft.dy)
    ..lineTo(xHitReduceBot, botY)
    ..lineTo(startX, botY)
    ..close();

  canvas.drawPath(insertoPath, insertoPaint);
}
// ================== FIN INSERTO CON ADHERENCIA A LÍNEAS ROJAS ==================

// ========== FIN BLOQUE ==========

// Paint blanco para los filetes (anti-alias activado)
final Paint paintFilet = Paint()
  ..color = Colors.white
  ..style = PaintingStyle.fill
  ..isAntiAlias = true;
  
// === helpers usadas por los filetes (pegar antes del bloque de filetes) ===
Offset _projectOnLine(Offset p, double m, double b) {
  final x = (p.dx + m * (p.dy - b)) / (1 + m * m);
  final y = m * x + b;
  return Offset(x, y);
}

Offset _centerToLine(double r, double m, double b, Offset corner) {
  final double xc = corner.dx + r;
  final double s  = m.sign;                  // +1 arriba, -1 abajo
  final double yc = b + m * xc - s * r * sqrt(1 + m * m);
  return Offset(xc, yc);
}

Offset _center(double r, double m, Offset corner) {
  final s = m.sign;
  return Offset(
    corner.dx + r,
    corner.dy + r * (m - s * sqrt(1 + m * m)),
  );
}

double _tParam(double r, double m) =>
    r * (1 + m * m - m.abs() * sqrt(1 + m * m)) / (1 + m * m);

Offset _tRamp(double t, double m, Offset corner) =>
    Offset(corner.dx + t, corner.dy + m * t);

// ───────── FILETES IZQUIERDOS CON DISTANCIA FIJA ─────────

// 1) Gap objetivo según Die Type (mm reales)
double targetGapMm;
if (dieType == 'TR8') {
  targetGapMm = 18.0;        // ⬅︎ Aumenta este valor para “abrir” más los filetes en TR8
} else if (dieType == 'TR6') {
  targetGapMm = 14.478;
} else { // TR4 / TR4D
  targetGapMm = 9.5504;
}

// 2) Conversión a píxeles (vertical respeta sy)
final double fixedGapPx = targetGapMm * mmToPx * sy;

// 3) Arranques fijos en la pared izquierda
final double xWall     = p1.dx;
final double yTopStart = centerY - fixedGapPx / 2;  // más arriba
final double yBotStart = centerY + fixedGapPx / 2;  // más abajo


// 4) Pendientes de las rampas a las que ser tangente
final double mUpReal   = (cafeLeft.dy - p1.dy)  / (cafeLeft.dx - p1.dx);
final double mDownReal = (grisLeft.dy - p2.dy)  / (grisLeft.dx - p2.dx);

// Para TR4D: usamos las rampas rojas ±20° como ya tenías
double mUp, bUp, mDown, bDown;
if (dieType == 'TR4D') {
  const double kRedDeg = 20;
  mUp   =  tan(kRedDeg * pi / 180);
  mDown = -tan(kRedDeg * pi / 180);

  final double xMidSup = (p1.dx + cafeLeft.dx) / 2;
  final double yMidSup = mUpReal * xMidSup + (p1.dy - mUpReal * p1.dx);
  bUp = yMidSup - mUp * xMidSup;

  final double xMidInf = (p2.dx + grisLeft.dx) / 2;
  final double yMidInf = mDownReal * xMidInf + (p2.dy - mDownReal * p2.dx);
  bDown = yMidInf - mDown * xMidInf;
} else {
  // TR4 y TR6: rampa real del wedge
  mUp   = mUpReal;   bUp   = p1.dy - mUp   * p1.dx;
  mDown = mDownReal; bDown = p2.dy - mDown * p2.dx;
}

// 5) Radio nominal (cap). En TR4 lo ignoramos si hace falta para doble tangencia.
final double dxAvail = cafeLeft.dx - xWall;
final double rNomPx  = (kFilletRadiusByDie[dieType] ?? 3.0) * mmToPx;
final double rMaxCap = min(rNomPx, dxAvail - 1);

// ---------- Solver de círculo con doble tangencia ----------
double _solveRadiusFor(double y0, double m, double b) {
  final double C = m * (xWall) + b - y0;
  final double R = sqrt(1 + m * m);
  double r1 = (-C) / (m - R);
  double r2 = (-C) / (m + R);
  double best = double.infinity;
  if (r1.isFinite && r1 > 0) best = min(best, r1.abs());
  if (r2.isFinite && r2 > 0) best = min(best, r2.abs());
  if (!best.isFinite) best = 0;
  return best;
}

Offset _tangentPoint(double r, double m, double b, double y0) {
  final double cx = xWall + r;
  final double cy = y0;
  final double xt = (cx + m * (cy - b)) / (1 + m * m);
  final double yt = m * xt + b;
  return Offset(xt, yt);
}

// ---------- Construcción de filetes ----------
// ---------- Construcción de filetes ----------
Path filetUpPath = Path();         
Path filetDnPath = Path();            


// ⬅️  Estos cuatro puntos los usa código posterior:
late Offset tVertUp, tVertDn, tRampUp, tRampDn;

if (dieType == 'TR4') {
  // 🔹 TR4: tu doble tangencia EXACTA (SIN CAMBIOS)
  double rUp = _solveRadiusFor(yTopStart, mUp, bUp);
  if (rUp > 0) {
    Offset tUp = _tangentPoint(rUp, mUp, bUp, yTopStart);
    final double segMin = min(p1.dx, cafeLeft.dx) - 0.5;
    final double segMax = max(p1.dx, cafeLeft.dx) + 0.5;
    if (tUp.dx < segMin || tUp.dx > segMax) {
      rUp = min(rUp, rMaxCap);
      tUp = _tangentPoint(rUp, mUp, bUp, yTopStart);
    }
    tVertUp = Offset(xWall, yTopStart);
    tRampUp = tUp;
    filetUpPath = Path()
      ..moveTo(tVertUp.dx, tVertUp.dy)
      ..arcToPoint(tRampUp, radius: Radius.circular(rUp), clockwise: false)
      ..lineTo(p1.dx, p1.dy)
      ..close();
  } else {
    final _FixedFilletSolution fUp = _solveFixedStartFillet(
      xWall: xWall, yStart: yTopStart, m: mUp, b: bUp, rMax: rMaxCap,
    );
    tVertUp = Offset(xWall, fUp.c.dy);
    tRampUp = fUp.t;
    filetUpPath = Path()
      ..moveTo(tVertUp.dx, tVertUp.dy)
      ..arcToPoint(tRampUp, radius: Radius.circular(fUp.r), clockwise: false)
      ..lineTo(p1.dx, p1.dy)
      ..close();
  }

  double rDn = _solveRadiusFor(yBotStart, mDown, bDown);
  if (rDn > 0) {
    Offset tDn = _tangentPoint(rDn, mDown, bDown, yBotStart);
    final double segMin = min(p2.dx, grisLeft.dx) - 0.5;
    final double segMax = max(p2.dx, grisLeft.dx) + 0.5;
    if (tDn.dx < segMin || tDn.dx > segMax) {
      rDn = min(rDn, rMaxCap);
      tDn = _tangentPoint(rDn, mDown, bDown, yBotStart);
    }
    tVertDn = Offset(xWall, yBotStart);
    tRampDn = tDn;
    filetDnPath = Path()
      ..moveTo(tVertDn.dx, tVertDn.dy)
      ..arcToPoint(tRampDn, radius: Radius.circular(rDn), clockwise: true)
      ..lineTo(p2.dx, p2.dy)
      ..close();
  } else {
    final _FixedFilletSolution fDn = _solveFixedStartFillet(
      xWall: xWall, yStart: yBotStart, m: mDown, b: bDown, rMax: rMaxCap,
    );
    tVertDn = Offset(xWall, fDn.c.dy);
    tRampDn = fDn.t;
    filetDnPath = Path()
      ..moveTo(tVertDn.dx, tVertDn.dy)
      ..arcToPoint(tRampDn, radius: Radius.circular(fDn.r), clockwise: true)
      ..lineTo(p2.dx, p2.dy)
      ..close();
  }

} else if (dieType == 'TR4D') {
  // 🔹 TR4D: tu arranque fijo tangente a pared y rampa (SIN CAMBIOS)
  final _FixedFilletSolution fUp = _solveFixedStartFillet(
    xWall: xWall, yStart: yTopStart, m: mUp, b: bUp, rMax: rMaxCap,
  );
  final _FixedFilletSolution fDn = _solveFixedStartFillet(
    xWall: xWall, yStart: yBotStart, m: mDown, b: bDown, rMax: rMaxCap,
  );

  tVertUp = Offset(xWall, fUp.c.dy);
  tVertDn = Offset(xWall, fDn.c.dy);
  tRampUp = fUp.t;
  tRampDn = fDn.t;

  filetUpPath = Path()
    ..moveTo(tVertUp.dx, tVertUp.dy)
    ..arcToPoint(tRampUp, radius: Radius.circular(fUp.r), clockwise: false)
    ..lineTo(p1.dx, p1.dy)
    ..close();

  filetDnPath = Path()
    ..moveTo(tVertDn.dx, tVertDn.dy)
    ..arcToPoint(tRampDn, radius: Radius.circular(fDn.r), clockwise: true)
    ..lineTo(p2.dx, p2.dy)
    ..close();

} else if (isTR6Family) { // 🔹 TR6: SOLO tangente a RAMPA (NO tangente a pared)
  // Rango válido de la rampa (para buscar el punto de tangencia)
  final double xMinUp = min(p1.dx,  cafeLeft.dx);
  final double xMaxUp = max(p1.dx,  cafeLeft.dx);
  final double xMinDn = min(p2.dx,  grisLeft.dx);
  final double xMaxDn = max(p2.dx,  grisLeft.dx);

final _FilletNT? sUp = _solveStartNonTangent(
  start: Offset(xWall, yTopStart),
  m: mUp, b: bUp,
  xMin: xMinUp, xMax: xMaxUp,
  rMax: rMaxCap,
  minStartAngleDeg: 20, // ← antes 10
);

final _FilletNT? sDn = _solveStartNonTangent(
  start: Offset(xWall, yBotStart),
  m: mDown, b: bDown,
  xMin: xMinDn, xMax: xMaxDn,
  rMax: rMaxCap,
  minStartAngleDeg: 20, // ← antes 10
);

  // ---------- Superior ----------
  if (sUp != null) {
    tVertUp = Offset(xWall, yTopStart); // arranque en pared (sin tangencia)
    tRampUp = sUp.t;
    filetUpPath = Path()..moveTo(tVertUp.dx, tVertUp.dy);
    _addArcWithCenter(filetUpPath, tVertUp, tRampUp, sUp.c, sUp.r);
    filetUpPath..lineTo(p1.dx, p1.dy)..close();
  } else {
    // Fallback: pequeño lead-in recto y luego arco (rompe tangencia visual)
    const double kLeadPx = 12.0; // ajusta 4–12 px si quieres
    final Offset start2 = Offset(xWall + kLeadPx, yTopStart);
    final _FilletNT? sUp2 = _solveStartNonTangent(
      start: start2, m: mUp, b: bUp,
      xMin: xMinUp, xMax: xMaxUp,
      rMax: rMaxCap, minStartAngleDeg: 10,
    );
    if (sUp2 != null) {
      tVertUp = Offset(xWall, yTopStart);
      tRampUp = sUp2.t;
      filetUpPath = Path()
        ..moveTo(tVertUp.dx, tVertUp.dy)
        ..lineTo(start2.dx, start2.dy); // ← rompe la tangencia en la pared
      _addArcWithCenter(filetUpPath, start2, tRampUp, sUp2.c, sUp2.r);
      filetUpPath..lineTo(p1.dx, p1.dy)..close();
    } else {
      // Último recurso: método anterior (tangente a pared y rampa)
      final _FixedFilletSolution fUp = _solveFixedStartFillet(
        xWall: xWall, yStart: yTopStart, m: mUp, b: bUp, rMax: rMaxCap,
      );
      tVertUp = Offset(xWall, fUp.c.dy);
      tRampUp = fUp.t;
      filetUpPath = Path()
        ..moveTo(tVertUp.dx, tVertUp.dy)
        ..arcToPoint(tRampUp, radius: Radius.circular(fUp.r), clockwise: false)
        ..lineTo(p1.dx, p1.dy)
        ..close();
    }
  }

  // ---------- Inferior ----------
  if (sDn != null) {
    tVertDn = Offset(xWall, yBotStart);
    tRampDn = sDn.t;
    filetDnPath = Path()..moveTo(tVertDn.dx, tVertDn.dy);
    _addArcWithCenter(filetDnPath, tVertDn, tRampDn, sDn.c, sDn.r);
    filetDnPath..lineTo(p2.dx, p2.dy)..close();
  } else {
    const double kLeadPx = 8.0;
    final Offset start2 = Offset(xWall + kLeadPx, yBotStart);
    final _FilletNT? sDn2 = _solveStartNonTangent(
      start: start2, m: mDown, b: bDown,
      xMin: xMinDn, xMax: xMaxDn,
      rMax: rMaxCap, minStartAngleDeg: 10,
    );
    if (sDn2 != null) {
      tVertDn = Offset(xWall, yBotStart);
      tRampDn = sDn2.t;
      filetDnPath = Path()
        ..moveTo(tVertDn.dx, tVertDn.dy)
        ..lineTo(start2.dx, start2.dy);
      _addArcWithCenter(filetDnPath, start2, tRampDn, sDn2.c, sDn2.r);
      filetDnPath..lineTo(p2.dx, p2.dy)..close();
    } else {
      final _FixedFilletSolution fDn = _solveFixedStartFillet(
        xWall: xWall, yStart: yBotStart, m: mDown, b: bDown, rMax: rMaxCap,
      );
      tVertDn = Offset(xWall, fDn.c.dy);
      tRampDn = fDn.t;
      filetDnPath = Path()
        ..moveTo(tVertDn.dx, tVertDn.dy)
        ..arcToPoint(tRampDn, radius: Radius.circular(fDn.r), clockwise: true)
        ..lineTo(p2.dx, p2.dy)
        ..close();
    }
  }
}

// Dibuja los filetes
canvas.drawPath(filetUpPath, paintFilet);
canvas.drawPath(filetDnPath, paintFilet);

// ── pasada de limpieza para matar picos (antialias) ──
final Paint cleanup = Paint()
  ..color = Colors.white
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2.0
  ..isAntiAlias = true;

// --- Borra el borde antialiased de las rampas dentro de la zona blanca ---
final Paint eraseSlope = Paint()
  ..color = Colors.white
  ..style = PaintingStyle.stroke
  ..strokeWidth = 2          // un par de píxeles bastan
  ..isAntiAlias = true;

// rampa superior (p9 ↔ cafeRight)
canvas.drawLine(p9, cafeRight, eraseSlope);

// rampa inferior (p10 ↔ grisRight)
canvas.drawLine(p10, grisRight, eraseSlope);

// ─── MÁSCARA BLANCA (rampas + filetes + pared) ────────────────

// grosor (px) hacia el interior del área blanca
final double kHalo = isTR6Family ? 8.0 : 50.0;

Path _slopeMask(Offset a, Offset b) {
  final v   = b - a;
  final len = v.distance;
  if (len == 0) return Path();               // seguridad
  var n = Offset(-v.dy, v.dx) / len;         // normal a la izquierda
  if (n.dx > 0) n = -n;                      // fuerza x negativa
  final d = n * kHalo;                       // desplazamiento ±kHalo
  return Path()..addPolygon([a + d, a - d, b - d, b + d], true);
}

// 1) Polígonos planos de cada rampa
final Path maskSup = _slopeMask(p1,  cafeLeft);   // rampa superior
final Path maskInf = _slopeMask(p2,  grisLeft);   // rampa inferior

// 2) Franja vertical pegada a la pared
final Path maskWall = isTR6Family
  ? (Path()..addRect(Rect.fromLTRB(p1.dx - 2, min(tVertUp.dy, tVertDn.dy) - 1, p1.dx, max(tVertUp.dy, tVertDn.dy) + 1)))
  : (Path()..addRect(Rect.fromLTRB(p1.dx - kHalo, min(tVertUp.dy, tVertDn.dy), p1.dx, max(tVertUp.dy, tVertDn.dy))));

// 3) Unimos rampas + filetes + pared => máscara completa
final Path maskFull = Path()
  ..addPath(maskSup,      Offset.zero)
  ..addPath(maskInf,      Offset.zero)
  ..addPath(filetUpPath,  Offset.zero)   // filete superior
  ..addPath(filetDnPath,  Offset.zero)   // filete inferior
  ..addPath(maskWall,     Offset.zero);  // franja vertical junto a pared

// 4) Corredor blanco completo = (recta) + (filetes)
final Path corridorFull = Path()
  ..addPath(path,         Offset.zero)   // polígono recto (sin curvar)
  ..addPath(filetUpPath,  Offset.zero)
  ..addPath(filetDnPath,  Offset.zero);

// 5) Zona blanca a proteger: corredor − inserto
final Path whiteZone = Path.combine(
  PathOperation.difference,
  corridorFull,
  insertoPath,
);

// 6) Pintura de máscara
final Paint maskPaint = Paint()
  ..color       = Colors.white
  ..style       = PaintingStyle.fill
  ..blendMode   = BlendMode.src
  ..isAntiAlias = false;

// 7) Aplicación con clip
if (isTR6Family) {
  // En TR6/TR8 borra SOLO dentro del wedge (pathFondo) y SOLO dentro del corredor
  final Path safeWhite = Path.combine(
    PathOperation.intersect,
    whiteZone,   // corredor (corredorFull - inserto)
    pathFondo,   // cuerpo gris
  );

  canvas.save();
  canvas.clipPath(pathFondo);   // 1º: límites del bloque
  canvas.clipPath(safeWhite);   // 2º: corredor sin inserto
  canvas.drawPath(maskFull, maskPaint);
  canvas.restore();

  // ⚠️ No repintes el wedge aquí para no tapar textos/rojo TR4D.
} else {
  // TR4 / TR4D (comportamiento original)
  canvas.save();
  canvas.clipPath(whiteZone);   // nunca invade el inserto
  canvas.drawPath(maskFull, maskPaint);
  canvas.restore();
}

// ───────────────────────────── FIN FILETS ─────────────────────────────

// === LONGITUDES EN mm PARA EL RATIO (siempre inicializadas) ===============
// helper: distancia entre dos puntos convertida a mm respetando sx/sy
// Conversión exacta a mm (respeta sx en X y sy en Y)
double _lenMm(Offset a, Offset b) {
  final dxMm = pxToMmX(b.dx - a.dx);
  final dyMm = pxToMmY(b.dy - a.dy);
  return sqrt(dxMm * dxMm + dyMm * dyMm);
}

final double leftCotaMm = _lenMm(leftCotaA, leftCotaB);

// Cuando dibujes el número, formatea SOLO aquí:
final String leftCotaTxt = showInches
    ? "${(leftCotaMm / 25.4).toStringAsFixed(dec)} in"
    : "${leftCotaMm.toStringAsFixed(dec)} mm";


// 1) Longitud TOTAL del “reduction cone” (amarillo) = dos rampas
final double lenYellowMm =
    _lenMm(cafeRight, p9) + _lenMm(grisRight, p10);

// 2) Longitud de CONTACTO (verde) = tramo B en ambas rampas
//    Usamos las mismas X que delimitan A/B/C sobre las rampas: xB y xC.
//    Ya tienes xIntersectRosa (=xB) y cafeLeft.dx (=xC) más arriba.
final double xB = xIntersectRosa;
final double xC = cafeLeft.dx;

final Offset topB = Offset(xB, mReduceSup * xB + bReduceSup);
final Offset topC = Offset(xC, mReduceSup * xC + bReduceSup);
final Offset botB = Offset(xB, mReduceInf * xB + bReduceInf);
final Offset botC = Offset(xC, mReduceInf * xC + bReduceInf);



final double lenGreenMm = _lenMm(topB, topC) + _lenMm(botB, botC);

// Evita división por cero por seguridad
//final double ratio = (lenYellowMm / (lenYellowMm + lenGreenMm));



// === ETIQUETAS A LA DERECHA (texto negro) =================================
// ====== Posición de las etiquetas de la derecha (AJUSTABLE) ======
const double labelsBaseDx = 120; // distancia a la derecha del borde
const double labelsBaseDy = 70;  // distancia debajo del centro

// Nudges manuales: negativo = izquierda/arriba, positivo = derecha/abajo
const double labelsNudgeX = -100; // mueve 30 px a la IZQUIERDA
const double labelsNudgeY =  40; // mueve 40 px hacia ABAJO

final double infoX = borderRect.right + labelsBaseDx + labelsNudgeX;
double infoY = centerY + labelsBaseDy + labelsNudgeY;

const TextStyle infoStyle = TextStyle(
  color: Colors.black,
  fontSize: 12,
  fontWeight: FontWeight.w600,
);

final TextPainter tpInfo = TextPainter(textDirection: TextDirection.ltr);
void drawInfo(String text) {
  tpInfo.text = TextSpan(text: text, style: infoStyle);
  tpInfo.layout();
  tpInfo.paint(canvas, Offset(infoX, infoY));
  infoY += tpInfo.height + 8;
}

drawInfo('Reduction Angle: ${reductionAngle.toStringAsFixed(0)}°');


//==========================================================================================================

// ───────── COTA HORIZONTAL DEL ANCHO DEL DADO (toggle) ─────────
if (showDieWidthDim) {
  // Línea horizontal (longitud total)
  canvas.drawLine(
    Offset(borderRect.left, borderRect.bottom + 30),
    Offset(borderRect.right, borderRect.bottom + 30),
    dimensionPaint,
  );

  // Flecha izquierda (hacia derecha)
  Path arrowRight = Path()
    ..moveTo(borderRect.left + 5, borderRect.bottom + 25)
    ..lineTo(borderRect.left + 5, borderRect.bottom + 35)
    ..lineTo(borderRect.left, borderRect.bottom + 30)
    ..close();
  canvas.drawPath(arrowRight, dimensionPaint);

  // Flecha derecha (hacia izquierda)
  Path arrowLeft = Path()
    ..moveTo(borderRect.right - 5, borderRect.bottom + 25)
    ..lineTo(borderRect.right - 5, borderRect.bottom + 35)
    ..lineTo(borderRect.right, borderRect.bottom + 30)
    ..close();
  canvas.drawPath(arrowLeft, dimensionPaint);

  // Líneas de extensión verticales
  canvas.drawLine(
    Offset(borderRect.left, borderRect.bottom),
    Offset(borderRect.left, borderRect.bottom + 30),
    dimensionPaint,
  );
  canvas.drawLine(
    Offset(borderRect.right, borderRect.bottom),
    Offset(borderRect.right, borderRect.bottom + 30),
    dimensionPaint,
  );

  // Texto centrado con la longitud en la unidad actual
  final double anchoRealMm = dieWidthMm;
  drawCota(
    lenStr(anchoRealMm),
    Offset((borderRect.left + borderRect.right) / 2 - 25, borderRect.bottom + 35),
  );
}

// ───────── COTA VERTICAL DE LA ALTURA DEL DADO (lado izquierdo) ─────────
if (showDieWidthDim) {
  // Deja espacio con la cota de "Entry Height"
  final double xDim = borderRect.left - 190;  // ajusta -60 / -100 si hace falta

  // Línea principal
  canvas.drawLine(
    Offset(xDim, borderRect.top),
    Offset(xDim, borderRect.bottom),
    dimensionPaint,
  );

  // Líneas de extensión a la pared izquierda del dado
  canvas.drawLine(Offset(borderRect.left, borderRect.top),    Offset(xDim, borderRect.top),    dimensionPaint);
  canvas.drawLine(Offset(borderRect.left, borderRect.bottom), Offset(xDim, borderRect.bottom), dimensionPaint);

  // Flechas
  Path arrowUp = Path()
    ..moveTo(xDim - arrowSize, borderRect.top + arrowSize)
    ..lineTo(xDim + arrowSize, borderRect.top + arrowSize)
    ..lineTo(xDim,              borderRect.top)
    ..close();
  canvas.drawPath(arrowUp, dimensionPaint);

  Path arrowDown = Path()
    ..moveTo(xDim - arrowSize, borderRect.bottom - arrowSize)
    ..lineTo(xDim + arrowSize, borderRect.bottom - arrowSize)
    ..lineTo(xDim,              borderRect.bottom)
    ..close();
  canvas.drawPath(arrowDown, dimensionPaint);

  // Etiqueta (usa el valor REAL del dado seleccionado: TR4/4D=12.7 mm, TR6=18.034 mm)
  // lenStr(mm) ya respeta _showInches, así que alterna mm ↔ in automáticamente.
  final String altoLabel = lenStr(dieHeightMm);
  final tpH = TextPainter(
    text: const TextSpan(style: TextStyle(color: Colors.black, fontSize: 12)),
    textDirection: TextDirection.ltr,
  );
  tpH.text = TextSpan(text: altoLabel, style: const TextStyle(color: Colors.black, fontSize: 12));
  tpH.layout();

  tpH.paint(
    canvas,
    Offset(
      xDim - tpH.width - 5,
      (borderRect.top + borderRect.bottom - tpH.height) / 2,
    ),
  );
}

// ───────── COTA DESDE FIN DE C HASTA BORDE DERECHO ─────────
if (showDieWidthDim) {
  final double xLeft  = cafeRight.dx;       // fin de C
  final double xRight = borderRect.right;   // borde derecho del dado

  // ↓ más arriba: antes era bottom + 18
  const double kDimYOffset = 8.0;           // ajusta 6–12 a tu gusto
  final double yDim = borderRect.bottom + kDimYOffset;

  // línea principal
  canvas.drawLine(Offset(xLeft, yDim), Offset(xRight, yDim), dimensionPaint);

  // flecha izquierda (hacia la izquierda)
  Path arrowLeft2 = Path()
    ..moveTo(xLeft + 5, yDim - 5)
    ..lineTo(xLeft + 5, yDim + 5)
    ..lineTo(xLeft,     yDim)
    ..close();
  canvas.drawPath(arrowLeft2, dimensionPaint);

  // flecha derecha (hacia la derecha)
  Path arrowRight2 = Path()
    ..moveTo(xRight - 5, yDim - 5)
    ..lineTo(xRight - 5, yDim + 5)
    ..lineTo(xRight,     yDim)
    ..close();
  canvas.drawPath(arrowRight2, dimensionPaint);

  // líneas de extensión verticales
  canvas.drawLine(Offset(xLeft,  borderRect.bottom), Offset(xLeft,  yDim), dimensionPaint);
  canvas.drawLine(Offset(xRight, borderRect.bottom), Offset(xRight, yDim), dimensionPaint);

  // texto (debajo de la línea)
  final double lenMm = pxToMmX(xRight - xLeft);   // respeta sx
  final String label = lenStr(lenMm);

  final tpLocal = TextPainter(
    text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 10)),
    textDirection: TextDirection.ltr,
  )..layout();

  const double kLabelGap = 4.0; // separación bajo la línea
  tpLocal.paint(
    canvas,
    Offset((xLeft + xRight) / 2 - tpLocal.width / 2, yDim + kLabelGap),
  );
}

// ───────── COTA VERTICAL (TR4/TR6). TR4D se pinta en el bloque final ─────────
if (showDieWidthDim && dieType != 'TR4D') {
  const double kDimOffset = 120.0;        // mueve la cota a la izq/der
  final double xDim = borderRect.left - kDimOffset;

  // TR4/TR6: final de filetes
  final Offset extTop   = tRampUp;
  final Offset extBot   = tRampDn;
  final double yTopMeas = tRampUp.dy;
  final double yBotMeas = tRampDn.dy;

  // Línea principal
  canvas.drawLine(Offset(xDim, yTopMeas), Offset(xDim, yBotMeas), dimensionPaint);

  // Extensiones
  canvas.drawLine(extTop, Offset(xDim, yTopMeas), dimensionPaint);
  canvas.drawLine(extBot, Offset(xDim, yBotMeas), dimensionPaint);

  // Flechas
  const double arrowSize = 5.0;
  final Path arrowUp = Path()
    ..moveTo(xDim - arrowSize, yTopMeas + arrowSize)
    ..lineTo(xDim + arrowSize, yTopMeas + arrowSize)
    ..lineTo(xDim,             yTopMeas)
    ..close();
  canvas.drawPath(arrowUp, dimensionPaint);

  final Path arrowDown = Path()
    ..moveTo(xDim - arrowSize, yBotMeas - arrowSize)
    ..lineTo(xDim + arrowSize, yBotMeas - arrowSize)
    ..lineTo(xDim,             yBotMeas)
    ..close();
  canvas.drawPath(arrowDown, dimensionPaint);

  // Etiqueta (mm/in respetando sy)
  final double deltaPx = (yBotMeas - yTopMeas).abs();
  final double deltaMm = pxToMmY(deltaPx);
  final String label   = lenStr(deltaMm);

  final tp = TextPainter(
    text: TextSpan(text: label, style: const TextStyle(color: Colors.black, fontSize: 12)),
    textDirection: TextDirection.ltr,
  )..layout();

  tp.paint(
    canvas,
    Offset(xDim - tp.width - 6, (yTopMeas + yBotMeas)/2 - tp.height/2),
  );
}

// ───────────────── PUNTOS DE COTA + TRAMOS A‑B‑C ──────────────────
// inicio de A:
//  • TR4D  → donde TERMINA la línea roja superior (su x es el punto medio entre p1 y cafeLeft)
//  • TR4   → como estaba: tangencia del filete con la rampa
final double xStartA = (dieType == 'TR4D')
    ? (p1.dx + cafeLeft.dx) / 2
    : tRampUp.dx;

// 1)  Cota roja  (filete)
final Offset pInicioRoja = tVertUp;                // vértice vertical
final Offset pFinRoja    = Offset(xStartA, topY);  // tangencia con la rampa

// 2)  Cota azul  (entre filete y vertical verde)
final Offset pInicioAzul = pFinRoja;
final Offset pFinAzul    = cafeLeft;               // pared verde

// 3)  Cota café  (bloque rojo)
final Offset pInicioCafe = cafeLeft;
final Offset pFinCafe    = cafeRight;

// ───── LÍMITES X DE CADA TRAMO ─────────────────────────────────────
final double xA = xStartA;           // inicio real de A   (verde)
//final double xB = xIntersectRosa;    // fin de A / inicio de B
//final double xC = cafeLeft.dx;       // fin de B / inicio de C
final double xD = cafeRight.dx;      // fin de C

// A y B horizontales en px
final double lenGreenPx  = (xB - xA).abs();   // A
final double lenYellowPx = (xC - xB).abs();   // B

// B / (A + B)
final double ratio = (lenGreenPx + lenYellowPx) > 0
    ? (lenYellowPx / (lenGreenPx + lenYellowPx))
    : 0.0;

// Semáforo como en tu lógica original
String icono;
if (ratio <= 0.33) {
  icono = ' ✅';
} else if (ratio >= 0.34 && ratio < 0.49) {
  icono = ' ⚠️';
} else {
  icono = ' ❌';
}
drawInfo('Reduction cone/Contact length: ${ratio.toStringAsFixed(2)}$icono');

// ====== Δ-rails basados en Finished fijo + ángulo fijo + rango Δ del material ======
// ===== COTAS HORIZONTALES EN ESCALERA (siempre visibles) =====
{
  final double xa = xA;  // inicio A
  final double xb = xB;  // fin A / inicio B
  final double xc = xC;  // fin B / inicio C

  double yAt(double x) => mReduceInf * x + bReduceInf;

  const double kGapFirst = 14.0;
  const double kStep     = 16.0;
  const double kTextGap  = 6.0;
  const double kArrow    = 5.0;

  final double yMax  = [xa, xb, xc].map(yAt).reduce(max);
  final double baseA = yMax + kGapFirst;
  final double baseB = yMax + kGapFirst + kStep;

  final Paint wStroke = Paint()
    ..color = Colors.white
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  final Paint wFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  // ⇣ ahora acepta un label opcional para forzar el texto
  void drawHorizDim(double x1, double x2, double baseY,
      {double fontSize = 12, String? labelOverride}) {
    final double y1 = yAt(x1), y2 = yAt(x2);

    canvas.drawLine(Offset(x1, y1), Offset(x1, baseY), wStroke);
    canvas.drawLine(Offset(x2, y2), Offset(x2, baseY), wStroke);
    canvas.drawLine(Offset(x1, baseY), Offset(x2, baseY), wStroke);

    final Path left = Path()
      ..moveTo(x1 + kArrow, baseY - kArrow)
      ..lineTo(x1 + kArrow, baseY + kArrow)
      ..lineTo(x1,          baseY);
    final Path right = Path()
      ..moveTo(x2 - kArrow, baseY - kArrow)
      ..lineTo(x2 - kArrow, baseY + kArrow)
      ..lineTo(x2,          baseY);
    canvas.drawPath(left,  wFill);
    canvas.drawPath(right, wFill);

    final String label = labelOverride ?? lenStr(pxToMmX(x2 - x1));
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset((x1 + x2) / 2 - tp.width / 2, baseY + kTextGap),
    );
  }

  // A y B
  drawHorizDim(xa, xb, baseA, fontSize: 12); // A
  drawHorizDim(xb, xc, baseB, fontSize: 12); // B

  // A + B (mismo trazo xa→xc, pero el texto es la suma de A y B)
  const double kTotalExtra = 22.0;
  final double baseTotal   = baseB + kTotalExtra;

  final double aMm = pxToMmX(xb - xa);
  final double bMm = pxToMmX(xc - xb);
  drawHorizDim(
    xa, xc, baseTotal,
    fontSize: 12,
    labelOverride: lenStr(aMm + bMm), // ← solo el valor A+B
  );
}



// Δ en función de r (misma que usas en el resto)
double _deltaOfR(double r) {
  final double alpha = (reductionAngle / 2.0) * pi / 180.0;
  final double t = 1.0 + sqrt(1.0 - r);
  return (alpha / r) * t * t;
}

// Inversa Δ → r (bisección)
double _rFromDelta(double dTarget) {
  double lo = 1e-6, hi = 1.0 - 1e-6;
  for (int i = 0; i < 48; i++) {
    final mid  = 0.5 * (lo + hi);
    final dMid = _deltaOfR(mid);
    // Δ(r) decrece con r
    if (dMid > dTarget) { lo = mid; } else { hi = mid; }
  }
  return 0.5 * (lo + hi);
}

// Con Δ y Finished fijos → ENTRY permitido (mm)
//   r = 1 - (d_out/d_in)^2  =>  d_in = d_out / sqrt(1 - r)
double _entryDiaFromDelta(double delta) {
  final double dout = finishedDiameterMm; // 👈 ahora usamos el finished real
  final double r    = _rFromDelta(delta).clamp(1e-6, 1-1e-6);
  return dout / sqrt(1.0 - r);
}

// Diámetro local del cono en x (mm) usando tus rampas actuales
double _localDiaAt(double x) {
  final yt = mReduceSup * x + bReduceSup;
  final yb = mReduceInf * x + bReduceInf;
  return pxToMmY(yb - yt);
}

// d(mm) → x en el cono por bisección [xA, xC] (con saturación)
double _xForDiameter(double diaMm, double xA, double xC) {
  final dA = _localDiaAt(xA);
  final dC = _localDiaAt(xC);
  if (diaMm >= dA) return xA;   // satura a la izquierda
  if (diaMm <= dC) return xC;   // satura a la derecha
  double lo = xA, hi = xC;
  final bool decreasing = dC < dA;
  for (int i = 0; i < 46; i++) {
    final mid  = 0.5 * (lo + hi);
    final dMid = _localDiaAt(mid);
    final bool goRight =
        (decreasing && dMid > diaMm) || (!decreasing && dMid < diaMm);
    if (goRight) lo = mid; else hi = mid;
  }
  return 0.5 * (lo + hi);
}

// ⚠️ Aquí usamos tus xA/xB/xC ya definidos más arriba (NO los redeclaramos)

// Entry permitido por material a partir de Δmin/Δmax
final double dinMinMm = _entryDiaFromDelta(deltaMin);
final double dinMaxMm = _entryDiaFromDelta(deltaMax);

// Sus x dentro del cono actual
double xMin = _xForDiameter(min(dinMinMm, dinMaxMm), xA, xC);
double xMax = _xForDiameter(max(dinMinMm, dinMaxMm), xA, xC);

// Garantiza visibilidad mínima
const double kMinLenPx = 8.0;
if (xMax - xMin < kMinLenPx) {
  final mid = 0.5 * (xMin + xMax);
  xMin = (mid - kMinLenPx / 2).clamp(xA, xC);
  xMax = (mid + kMinLenPx / 2).clamp(xA, xC);
}

final double kRailPadPx = _railPadPx;              // ⇠ alárgalas un poquito (ajusta 2–6 px)
final double rxMin = (xMin - kRailPadPx).clamp(xA, xC);
final double rxMax = (xMax + kRailPadPx).clamp(xA, xC);

// Puntos sobre las rampas
Offset _ptTop(double x) => Offset(x, mReduceSup * x + bReduceSup);
//Offset _ptBot(double x) => Offset(x, mReduceInf * x + bReduceInf);

// Muestra rieles solo si estás en modo construcción Y el grade no es None
final bool _showRails = showDeltaRails && grade != 'None';

// ═════════════ Δ-rails SUPERIORES (verticales a 90° respecto a la app) ═════════════
if (grade != 'None') {
  // Punto sobre la rampa superior en X
  Offset _ptSup(double x) => Offset(x, mReduceSup * x + bReduceSup);

  // Dibuja una banda vertical de altura fija entre x0..x1 (hacia -Y)
  void drawVerticalBand(
      Canvas canvas, double x0, double x1, double height, Color color) {
    if (x1 <= x0) return;
    final y0 = _ptSup(x0).dy;
    final y1 = _ptSup(x1).dy;

    final Path band = Path()
      ..moveTo(x0, y0)
      ..lineTo(x1, y1)
      ..lineTo(x1, y1 - height) // extrusión VERTICAL hacia arriba
      ..lineTo(x0, y0 - height)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(band, paint);
  }

  // ── Anclajes geométricos sobre la rampa
  final double xAstartTop = tRampUp.dx;   // inicio de A (arriba)
  final double xCtop      = cafeLeft.dx;  // línea B/C (inicio de C en el cono)

  // Alturas de las bandas
  const double kHGreen  = 24.0;
  const double kHYellow = 24.0;
  const double kHRed    = 24.0;

  // ─────────────────────────────
  // 1) Límites numéricos de Δ
  //    usando tu regla de ±20 %
  //    verde    : [deltaMin, deltaMax]
  //    amarillo : [deltaMin*0.8, deltaMin)  y  (deltaMax, deltaMax*1.2]
  //    rojo     : <deltaMin*0.8  y  >deltaMax*1.2
  // ─────────────────────────────
  final double dGreenMin   = deltaMin;
  final double dGreenMax   = deltaMax;
  final double dYellowLow  = deltaMin * 0.8; // límite rojo↔amarillo izq
  final double dYellowHigh = deltaMax * 1.2; // límite amarillo↔rojo der

  // Seguridad para que no haya valores raros
  final double d0 = dYellowLow.clamp(0.01, 99.0);
  final double d1 = dGreenMin.clamp(d0 + 1e-6, 99.0);
  final double d2 = dGreenMax.clamp(d1 + 1e-6, 99.0);
  final double d3 = dYellowHigh.clamp(d2 + 1e-6, 120.0);

  // Convierte Δ → diámetro de entrada que produciría ese Δ
  double _entryDiaFromDeltaLocal(double d) =>
      _entryDiaFromDelta(d); // usamos tu helper original

  // Diámetros correspondientes a cada frontera
  final double din0 = _entryDiaFromDeltaLocal(d0); // rojo/amarillo izq
  final double din1 = _entryDiaFromDeltaLocal(d1); // amarillo/verde izq
  final double din2 = _entryDiaFromDeltaLocal(d2); // verde/amarillo der
  final double din3 = _entryDiaFromDeltaLocal(d3); // amarillo/rojo der

  // Función auxiliar para quedar dentro [xAstartTop, xCtop]
  double _clampX(double x) =>
      x.clamp(xAstartTop, xCtop);

  // Mapea diámetro → posición X sobre la rampa actual
  double _xForDia(double diaMm) =>
      _clampX(_xForDiameter(diaMm, xAstartTop, xCtop));

  // X de cada frontera de color
  final double x0 = xAstartTop;           // inicio total
  final double x1 = _xForDia(din0);       // fin rojo izq / inicio amarillo izq
  final double x2 = _xForDia(din1);       // fin amarillo izq / inicio verde
  final double x3 = _xForDia(din2);       // fin verde / inicio amarillo der
  final double x4 = _xForDia(din3);       // fin amarillo der / inicio rojo der
  final double x5 = xCtop;                // fin total (en B/C)

  canvas.save();
  canvas.clipPath(pathFondo);

  // ------- Rojo izquierdo -------
  if (x1 - x0 > 0.5) {
    drawVerticalBand(canvas, x0, x1, kHRed, const Color(0xFFE51937));
  }

  // ------- Amarillo izquierdo -------
  if (x2 - x1 > 0.5) {
    drawVerticalBand(canvas, x1, x2, kHYellow, const Color(0xFFFACC15));
  }

  // ------- Verde (zona buena) -------
  if (x3 - x2 > 0.5) {
    drawVerticalBand(canvas, x2, x3, kHGreen, const Color(0xFF22C55E));
  }

  // ------- Amarillo derecho -------
  if (x4 - x3 > 0.5) {
    drawVerticalBand(canvas, x3, x4, kHYellow, const Color(0xFFFACC15));
  }

  // ------- Rojo derecho -------
  if (x5 - x4 > 0.5) {
    drawVerticalBand(canvas, x4, x5, kHRed, const Color(0xFFE51937));
  }

  canvas.restore();
}
// ═══════════════════════════════════════════════════════════════════════════

// ===== longitudes A, B, C (en px y mm) — SIEMPRE disponibles =====
final double lenRedPx    = (xD - xC).abs();

//final double lenGreenMm  = pxToMmX(lenGreenPx);
//final double lenYellowMm = pxToMmX(lenYellowPx);
final double lenRedMm    = pxToMmX(lenRedPx);

if (showDieWidthDim) {
  // ---------- LEYENDA A LA DERECHA ----------
  const double legendSquare = 14.0;                 // un pelín más grande
  final double legendX = borderRect.right + 50;     // separa del dado
  const double legendYOffset = -100;                // posición vertical
  double legendY = topY + legendYOffset;

  // Longitudes de cada tramo A, B, C (en px y mm)
  final double lenGreenPx  = (xB - xA).abs();
  final double lenYellowPx = (xC - xB).abs();
  final double lenRedPx    = (xD - xC).abs();

  final double lenGreenMm  = pxToMmX(lenGreenPx);
  final double lenYellowMm = pxToMmX(lenYellowPx);
  final double lenRedMm    = pxToMmX(lenRedPx);

  // Descripciones
  const Map<String, String> _legendDesc = {
    'A': 'Lubrication zone',
    'B': 'Deformation/contact zone',
    'C': 'Bearing',
  };

  void drawLegend(Color col, double mm, String letter) {
    // cuadrado de color (sin transparencia ni mezcla)
    final rect = Rect.fromLTWH(legendX, legendY, legendSquare, legendSquare);
    final fill = Paint()
      ..color = col
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.src     // ⬅️ evita que el fondo lo “lave”
      ..isAntiAlias = false;
    canvas.drawRect(rect, fill);

    // borde suave para mayor contraste (opcional)
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.black.withOpacity(0.35);
    canvas.drawRect(rect, border);

    // letra centrada dentro del cuadrado
    final tpLetter = TextPainter(
      text: const TextSpan(
        text: '', // se setea abajo
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    tpLetter.text = TextSpan(
      text: letter,
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10),
    );
    tpLetter.layout();
    tpLetter.paint(
      canvas,
      Offset(
        legendX + (legendSquare - tpLetter.width) / 2,
        legendY + (legendSquare - tpLetter.height) / 2,
      ),
    );

    // texto: descripción + valor
    final String label = _legendDesc[letter] ?? '';
    final tp = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          TextSpan(
            text: lenStr(mm), // usa tu helper que respeta mm/in
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(legendX + legendSquare + 6, legendY - 1));
    legendY += legendSquare + 6;
  }

  drawLegend(_colA, lenGreenMm,  'A');
  drawLegend(_colB, lenYellowMm, 'B');
  drawLegend(_colC, lenRedMm,    'C');

}

// ---------- (opcional) Redcone-Ratio sigue funcionando ----------
//final ratio = lenYellowMm / (lenYellowMm + lenGreenMm); // mismo criterio
// ---------- ETIQUETA REDCONE RATIO (blanca sobre fondo gris) ----------
Color ratioColor;
//String icono;
if (ratio <= 0.33) {
  ratioColor = Colors.greenAccent;
  icono = " ✅";
} else if (ratio >= 0.34 && ratio < 0.49) {
  ratioColor = Colors.orangeAccent;
  icono = " ⚠️";
} else {
  ratioColor = Colors.redAccent;
  icono = " ❌";
}

final ratioPainter = TextPainter(
  text: TextSpan(
    children: [
      const TextSpan(
        text: "Reduction cone/Contact length: ",
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      TextSpan(
        text: ratio.toStringAsFixed(2) + icono,
        style: TextStyle(
          color: ratioColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  ),
  textDirection: TextDirection.ltr,
)..layout();

// Configura el estilo en blanco y negritas
final textPainterReduction = TextPainter(
  text: TextSpan(
    text: "Reduction Angle: $reductionAngle°",
    style: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout();   // ¡importante!

// Ancla (top-left) del texto “Reduction Angle”
final double raAnchorX  = (p1.dx + cafeLeft.dx) / 2 + 5;
// Centro horizontal de ese texto
final double raCenterX  = raAnchorX + textPainterReduction.width / 2;

// ───── NUEVO anclaje basado en la pendiente roja (p2 ↔ grisLeft) ─────
// ①  Punto medio de la pendiente roja
final Offset redMid = (p2 + grisLeft) / 2;

// ②  Desplázalo un poco hacia la derecha y <n> px hacia abajo
//     (pon el valor que te guste: 16-20 px suele quedar bien)
const Offset redLabelOffset = Offset(-25, 18);
final Offset ratioPos = redMid + redLabelOffset;

// ③  Pinta el texto
//ratioPainter.paint(canvas, ratioPos);

// Líneas de extensión vertical
canvas.drawLine(pInicioCafe, Offset(pInicioCafe.dx, dimensionY), dimensionPaint);
canvas.drawLine(pFinCafe, Offset(pFinCafe.dx, dimensionY), dimensionPaint);

// Texto de cota verde (longitud del bloque café)
final double longitudCafe = (pFinCafe.dx - pInicioCafe.dx) / mmToPx;

// ---------------------
// INSERT HEIGHT ENTRADA
// ---------------------
final offsetInsert = 20.0;
final cotaInsertX = startX - offsetInsert;

// línea de cota
canvas.drawLine(
  Offset(cotaInsertX, topY),
  Offset(cotaInsertX, botY),
  dimensionPaint,
);

// líneas de extensión
canvas.drawLine(Offset(startX, topY), Offset(cotaInsertX, topY), dimensionPaint);
canvas.drawLine(Offset(startX, botY), Offset(cotaInsertX, botY), dimensionPaint);

// flechas
Path arrowUpInsert = Path()
  ..moveTo(cotaInsertX - arrowSize, topY + arrowSize)
  ..lineTo(cotaInsertX + arrowSize, topY + arrowSize)
  ..lineTo(cotaInsertX, topY)
  ..close();
canvas.drawPath(arrowUpInsert, dimensionPaint);

Path arrowDownInsert = Path()
  ..moveTo(cotaInsertX - arrowSize, botY - arrowSize)
  ..lineTo(cotaInsertX + arrowSize, botY - arrowSize)
  ..lineTo(cotaInsertX, botY)
  ..close();
canvas.drawPath(arrowDownInsert, dimensionPaint);

// texto
final insertText = TextPainter(
  text: TextSpan(
    text: lenStr(alturaInicial/10),
    style: const TextStyle(color: Colors.black, fontSize: 12),
  ),
  textDirection: TextDirection.ltr,
);
insertText.layout();
insertText.paint(
  canvas,
  Offset(
    cotaInsertX - insertText.width - 5,
    (topY + botY) / 2 - insertText.height / 2,
  ),
);

// ---------------------
// INSERT HEIGHT SALIDA
// ---------------------
final salidaTopY = cafeRight.dy;
final salidaBotY = grisRight.dy;

final offsetInsertOut = 20.0;
final cotaInsertOutX = salidaX + offsetInsertOut;

// línea de cota
canvas.drawLine(
  Offset(cotaInsertOutX, salidaTopY),
  Offset(cotaInsertOutX, salidaBotY),
  dimensionPaint,
);

// líneas de extensión
canvas.drawLine(Offset(salidaX, salidaTopY), Offset(cotaInsertOutX, salidaTopY), dimensionPaint);
canvas.drawLine(Offset(salidaX, salidaBotY), Offset(cotaInsertOutX, salidaBotY), dimensionPaint);

// flechas
Path arrowUpInsertOut = Path()
  ..moveTo(cotaInsertOutX - arrowSize, salidaTopY + arrowSize)
  ..lineTo(cotaInsertOutX + arrowSize, salidaTopY + arrowSize)
  ..lineTo(cotaInsertOutX, salidaTopY)
  ..close();
canvas.drawPath(arrowUpInsertOut, dimensionPaint);

Path arrowDownInsertOut = Path()
  ..moveTo(cotaInsertOutX - arrowSize, salidaBotY - arrowSize)
  ..lineTo(cotaInsertOutX + arrowSize, salidaBotY - arrowSize)
  ..lineTo(cotaInsertOutX, salidaBotY)
  ..close();
canvas.drawPath(arrowDownInsertOut, dimensionPaint);

// texto
final salidaHeightMM = barraLength / 10.0;  // décimas → mm

final insertOutText = TextPainter(
  text: TextSpan(
    text: lenStr(salidaHeightMM),
    style: const TextStyle(color: Colors.black, fontSize: 12),
  ),

  textDirection: TextDirection.ltr,
);
insertOutText.layout();
insertOutText.paint(
  canvas,
  Offset(
    cotaInsertOutX + 5,
    (salidaTopY + salidaBotY) / 2 - insertOutText.height / 2,
  ),
);
    // textos
    final textStyle = TextStyle(color: Colors.black, fontSize: 10);
    final tp = TextPainter(textDirection: TextDirection.ltr);

    void drawText(String txt, Offset pos, {Color color = Colors.black}) {
      tp.text = TextSpan(text: txt, style: textStyle.copyWith(color: color));
      tp.layout();
      tp.paint(canvas, pos);
    }

// -------------- COTA VERTICAL BACK-RELIEF (naranjaR) --------------

if (!hideRightCota) {  
// ❶ Puntos extremos del back-relief (ya los tienes calculados)
final Offset brTop = p9;          // vértice superior (derecha)
final Offset brBot = p10;         // vértice inferior (derecha)

// ❷ Coloca la línea de cota un poco a la derecha del dado
const double brOffset = 200.0;               // distancia horizontal
final double cotaBRx = borderRect.right + brOffset;

// ❸ Línea principal de la cota
canvas.drawLine(
  Offset(cotaBRx, brTop.dy),
  Offset(cotaBRx, brBot.dy),
  dimensionPaint,
);

// ❹ Líneas de extensión horizontales
canvas.drawLine(brTop, Offset(cotaBRx, brTop.dy), dimensionPaint);
canvas.drawLine(brBot, Offset(cotaBRx, brBot.dy), dimensionPaint);

// ❺ Flechas (arriba y abajo)
Path arrowUpBR = Path()
  ..moveTo(cotaBRx - arrowSize, brTop.dy + arrowSize)
  ..lineTo(cotaBRx + arrowSize, brTop.dy + arrowSize)
  ..lineTo(cotaBRx, brTop.dy)
  ..close();
canvas.drawPath(arrowUpBR, dimensionPaint);

Path arrowDownBR = Path()
  ..moveTo(cotaBRx - arrowSize, brBot.dy - arrowSize)
  ..lineTo(cotaBRx + arrowSize, brBot.dy - arrowSize)
  ..lineTo(cotaBRx, brBot.dy)
  ..close();
canvas.drawPath(arrowDownBR, dimensionPaint);

// ❻ Etiqueta con la longitud (mm)
final backRelief = lenStr(naranjaR / 10.0);   // décimas → mm
final brText = TextPainter(
  text: TextSpan(
    text: backRelief,
    style: const TextStyle(color: Colors.black, fontSize: 12),
  ),
  textDirection: TextDirection.ltr,
)..layout();

// Centrar el texto sobre la línea de cota
brText.paint(
  canvas,
  Offset(
    cotaBRx - brText.width - 5,                       // a la izquierda de la línea
    (brTop.dy + brBot.dy) / 2 - brText.height / 2,    // centrado vertical
  ),
);
  } 
    // textos de las longitudes y ángulos
 /*   drawText(
        "Back Relief Top: ${amarilloLen.toStringAsFixed(3)} mm, ${amarilloAng.toStringAsFixed(1)}°",
        (p9 + cafeRight) / 2 + Offset(-80, -15));
    drawText(
        "Back Relief Bot: ${moradoLen.toStringAsFixed(3)} mm, ${moradoAng.toStringAsFixed(1)}°",
        (p10 + grisRight) / 2 + Offset(-80, 5));

// ------------ BLOCK OF DIMENSIONS / TEXTS ------------
drawCota("Cafe: ${(cafeRight - cafeLeft).distance.toStringAsFixed(3)} mm", 
  (cafeLeft + cafeRight)/2 + Offset(-40,-10));

drawCota("Gray: ${(grisRight - grisLeft).distance.toStringAsFixed(3)} mm", 
  (grisLeft + grisRight)/2 + Offset(-40,5));
*/
// Calcula el ángulo de reducción
//final double alpha = atan2(cafeLeft.dy - p1.dy, cafeLeft.dx - p1.dx) * 180 / pi;

/*
drawCota("Red: ${(grisLeft - p2).distance.toStringAsFixed(3)} mm, "
  "${(atan2(grisLeft.dy - p2.dy, grisLeft.dx - p2.dx)*180/pi).toStringAsFixed(1)}°",
  (p2 + grisLeft)/2 + Offset(5,5));

drawCota("Yellow: ${(p9 - cafeRight).distance.toStringAsFixed(3)} mm, "
  "${(atan2(p9.dy - cafeRight.dy, p9.dx - cafeRight.dx)*180/pi).toStringAsFixed(1)}°",
  (p9 + cafeRight)/2 + Offset(-110,-10));

drawCota("Purple: ${(p10 - grisRight).distance.toStringAsFixed(3)} mm, "
  "${(atan2(p10.dy - grisRight.dy, p10.dx - grisRight.dx)*180/pi).toStringAsFixed(1)}°",
  (p10 + grisRight)/2 + Offset(-110,5));
*/

if(dieType == 'TR4D'){
  
// ─────  Punto azul  = intersección vertical con la arista de reducción ─────
final double xMid = (p1.dx + cafeLeft.dx) / 2;

//   arista superior = segmento p1 → cafeLeft
final double mReduce = (cafeLeft.dy - p1.dy) / (cafeLeft.dx - p1.dx);
final double bReduce = p1.dy - mReduce * p1.dx;

final double yMid = mReduce * xMid + bReduce;
final Offset bluePoint = Offset(xMid, yMid);   // ← nuevo punto de anclaje

// ═════════════════ LINEA ROJA (40° ↖ desde punto azul) ═══════════════
const double kRedDeg = 20;
const double kRedStroke = 4.0;            // grosor deseado
final  double kRedHalf   = kRedStroke / 2;
final double kRedRad = kRedDeg * pi / 180;
final Offset dirUpLeft = Offset(-cos(kRedRad), -sin(kRedRad)); // unidad ↖

// ❶   Extremo derecho = punto azul (ancla que sube/baja con el wedge)
//      Levantamos la línea roja superior kLiftSup píxeles.
const double kLiftSup = 2;                       // ajusta 2–4 si hace falta
final Offset redEnd = bluePoint.translate(0, kRedHalf - kLiftSup);
_tr4dRedEndTop = redEnd; // ⟵ guarda el extremo interior superior

// ❷   Avanza sobre dirUpLeft hasta salir del cuerpo gris (pathFondo)
Offset redStart = redEnd;
for (double t = 0.5; t < 2000; t += 0.5) {
  final p = redEnd + dirUpLeft * t;
  if (!pathFondo.contains(p)) {          // acaba de salir
    redStart = redEnd + dirUpLeft * (t - 0.5);   // último punto “dentro”
    break;
  }
}

// ─── PUNTO DE CORTE 20° ↘ con la rampa de reducción ───
final double m20 = -tan(kRedDeg * pi / 180);          // pendiente -20°
final double b20 = redEnd.dy - m20 * redEnd.dx;       // y = m·x + b

final double xCut    = (bReduce - b20) / (m20 - mReduce);
final Offset cutPoint = Offset(xCut, mReduce * xCut + bReduce);

// ❸   Dibuja la línea
final Paint redPaint = Paint()
  ..color       = Colors.grey.shade800
  ..strokeWidth = kRedStroke          // antes 4
  ..style       = PaintingStyle.stroke
  ..strokeCap   = StrokeCap.butt;     // puntas planas

canvas.drawLine(redStart, redEnd, redPaint);

// ─────────  MÁSCARA BLANCA ENTRE LÍNEA ROJA Y BASE (solo TR4D) ─────────
if (dieType == 'TR4D') {
  // 1)  Semiplano bajo la línea roja (limitado a yLimit alto)
  final double yLimit = redEnd.dy + 1;                 // apenas debajo
  final Path underLine = Path()
    ..moveTo(redStart.dx, redStart.dy)
    ..lineTo(redEnd.dx,   redEnd.dy)
    ..lineTo(redEnd.dx + 2000, yLimit)
    ..lineTo(redStart.dx - 2000, yLimit)
    ..close();

  // 2)  Semiplano bajo la BASE (p1 → cafeLeft)
  final double mBase = (cafeLeft.dy - p1.dy) /
                       (cafeLeft.dx - p1.dx);
  final double bBase = p1.dy - mBase * p1.dx;

  // construimos 2 puntos muy a la derecha e izquierda sobre la base
  final Offset bLeft  = Offset(p1.dx - 2000, p1.dy - mBase * 2000);
  final Offset bRight = Offset(cafeLeft.dx + 2000,
                               cafeLeft.dy + mBase * 2000);

  final Path underBase = Path()
    ..moveTo(p1.dx, p1.dy)
    ..lineTo(cafeLeft.dx, cafeLeft.dy)
    ..lineTo(bRight.dx, bRight.dy)
    ..lineTo(bLeft.dx,  bLeft.dy)
    ..close();

  // 3)  Regiones dentro del wedge
  final Path wedgeUnderLine =
      Path.combine(PathOperation.intersect, pathFondo, underLine);

  final Path wedgeUnderBase =
      Path.combine(PathOperation.intersect, pathFondo, underBase);

  // 4)  Zona definitiva = (wedgeUnderLine – wedgeUnderBase) – inserto
  Path maskFinal  =
      Path.combine(PathOperation.difference,
                   wedgeUnderLine, wedgeUnderBase);

  maskFinal = Path.combine(PathOperation.difference,
                           maskFinal, insertoPath);

  // 5)  Pintamos de blanco
  canvas.drawPath(maskFinal, Paint()..color = Colors.white);
}

// ═══ Parche horizontal gris que va EXACTO de redEnd a la rampa ═════
{
  final Paint patchPaint = Paint()
    ..color = borderFill.color          // gris del wedge
    ..style = PaintingStyle.fill;

  // 1) intersección con la rampa de back-relief (caféRight ↔ p9)
  final double mBack = (p9.dy - cafeRight.dy) / (p9.dx - cafeRight.dx);
  final double xIntersect =
      (redEnd.dy - cafeRight.dy) / mBack + cafeRight.dx;

// 2)  Rectángulo de 7 px  (2 px arriba, 5 px abajo)
//     ─ topOffset    = -3  → sube 2 px para cubrir la muesca
//     ─ bottomOffset =  5  → baja un poco menos
//     ─ se amplía 2 px a la IZQ y 6 px a la DER para tapar el borde
const double topOffset    = -3.0;
const double bottomOffset =  5.0;


final Rect bandRect = Rect.fromLTRB(
  redEnd.dx - 4,              // 4 px a la izquierda del vértice
  redEnd.dy + topOffset,
  xIntersect + 2,             // ***solo 2 px más allá de la rampa***
  redEnd.dy + bottomOffset,
);

  // 3) recorte al contorno gris (seguridad) y pintado
  final Path clippedBand = Path.combine(
    PathOperation.intersect,
    pathFondo,
    Path()..addRect(bandRect),
  );
  canvas.drawPath(clippedBand, patchPaint);

  // ── 4) Borra por antialias la rampa del back-relief ────────────────
final Paint eraseBack = Paint()
  ..color       = Colors.white          // mismo color de máscara
  ..strokeWidth = 2                     // 2‒3 px bastan
  ..style       = PaintingStyle.stroke
  ..isAntiAlias = true;

canvas.drawLine(cafeRight, p9, eraseBack);
}

// ═══ Repinta de nuevo el corredor blanco (sin tocar el inserto) ═══
canvas.save();
canvas.clipPath(pathFondo);                    // nunca fuera del wedge
canvas.drawPath(
  whiteZone,                                   // corridorFull – insertoPath
  Paint()
    ..color     = Colors.white
    ..style     = PaintingStyle.fill
    ..blendMode = BlendMode.src,
);
canvas.restore();

// ═════════════════ LINEA ROJA INFERIOR (20° ↘ desde filete inferior) ═══════════════

// (1) Punto azul inferior = intersección entre filete y rampa inferior
final double xMidInf = (p2.dx + grisLeft.dx) / 2;
final double mRedInferior = (grisLeft.dy - p2.dy) / (grisLeft.dx - p2.dx);
final double bRedInferior = p2.dy - mRedInferior * p2.dx;

// usa exactamente el mismo xMid que arriba
final double yMidInf = mRedInferior * xMid + bRedInferior;
// --- ancla inferior (blue point) desplazada a la derecha ---
const double kRedShiftRightPx = 5; // ← ajusta el valor (px) a tu gusto
final Offset redAnchorInf = Offset(xMid + kRedShiftRightPx, yMidInf);

// Ángulo en radianes y dirección hacia ↘
const double kRedDegInf = 20;
const double kRedStrokeInf = 4.0;
final double kRedHalfInf = kRedStrokeInf / 2;
final double kRedRadInf = kRedDegInf * pi / 180;
final Offset dirDownRight = Offset(-cos(kRedRadInf), sin(kRedRadInf)); // unidad ↘

// extremo izquierdo (ancla inferior) con el pequeño “lift” del grosor
final Offset redEndInf = redAnchorInf.translate(0, -kRedHalfInf);
_tr4dRedEndBot = redEndInf; // ⟵ guarda el extremo interior inferior

// busca hasta que salga del wedge
Offset redStartInf = redEndInf;
for (double t = 0.5; t < 2000; t += 0.5) {
  final p = redEndInf + dirDownRight * t;
  if (!pathFondo.contains(p)) {
    redStartInf = redEndInf + dirDownRight * (t - 0.5);
    break;
  }
}

// pendiente del 20° negativo
final double m20Inf = tan(kRedDegInf * pi / 180); // positiva hacia ↘
final double b20Inf = redEndInf.dy - m20Inf * redEndInf.dx;

// intersección con la rampa inferior (mRedInferior)
final double xCutInf = (b20Inf - bRedInferior) / (mRedInferior - m20Inf);
final Offset cutPointInf = Offset(xCutInf, mRedInferior * xCutInf + bRedInferior);

// dibuja línea inferior
final Paint redPaintInf = Paint()
  ..color = Colors.grey.shade800
  ..strokeWidth = kRedStrokeInf
  ..style = PaintingStyle.stroke
  ..strokeCap = StrokeCap.butt;

canvas.drawLine(redStartInf, redEndInf, redPaintInf);

// ══════════════════ MÁSCARA BLANCA INFERIOR (TR4D) ═══════════════════
{
  final double yLimitInf = redEndInf.dy - 1;
  final Path underLineInf = Path()
    ..moveTo(redStartInf.dx, redStartInf.dy)
    ..lineTo(redEndInf.dx,   redEndInf.dy)
    ..lineTo(redEndInf.dx + 2000, yLimitInf)
    ..lineTo(redStartInf.dx - 2000, yLimitInf)
    ..close();

  // semiplano inferior base
  final double mBaseInf = (grisLeft.dy - p2.dy) /
                          (grisLeft.dx - p2.dx);
  final double bBaseInf = p2.dy - mBaseInf * p2.dx;
  final Offset bLeftInf  = Offset(p2.dx - 2000, p2.dy - mBaseInf * 2000);
  final Offset bRightInf = Offset(grisLeft.dx + 2000,
                                  grisLeft.dy + mBaseInf * 2000);
  final Path underBaseInf = Path()
    ..moveTo(p2.dx, p2.dy)
    ..lineTo(grisLeft.dx, grisLeft.dy)
    ..lineTo(bRightInf.dx, bRightInf.dy)
    ..lineTo(bLeftInf.dx,  bLeftInf.dy)
    ..close();

  final Path wedgeUnderLineInf =
      Path.combine(PathOperation.intersect, pathFondo, underLineInf);
  final Path wedgeUnderBaseInf =
      Path.combine(PathOperation.intersect, pathFondo, underBaseInf);
  Path maskFinalInf = Path.combine(PathOperation.difference,
                                   wedgeUnderLineInf, wedgeUnderBaseInf);
  maskFinalInf = Path.combine(PathOperation.difference,
                              maskFinalInf, insertoPath);

  canvas.drawPath(maskFinalInf, Paint()..color = Colors.white);
}

// ══════════════════ PARCHE HORIZONTAL INFERIOR (gris) ═══════════════════
{
  final Paint patchPaintInf = Paint()
    ..color = borderFill.color
    ..style = PaintingStyle.fill;

  final double mBackInf = (p10.dy - grisRight.dy) /
                          (p10.dx - grisRight.dx);
  final double xIntersectInf =
      (redEndInf.dy - grisRight.dy) / mBackInf + grisRight.dx;

  const double topOffset    = -3.0;
  const double bottomOffset =  5.0;

  final Rect bandRectInf = Rect.fromLTRB(
    redEndInf.dx - 4,
    redEndInf.dy + topOffset,
    xIntersectInf + 2,
    redEndInf.dy + bottomOffset,
  );

  final Path clippedBandInf = Path.combine(
    PathOperation.intersect,
    pathFondo,
    Path()..addRect(bandRectInf),
  );
  canvas.drawPath(clippedBandInf, patchPaintInf);

  // borra rampa de salida
  final Paint eraseBackInf = Paint()
    ..color = Colors.white
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  canvas.drawLine(grisRight, p10, eraseBackInf);
}

// ══ Repinta el corredor blanco (como en el superior) ══
canvas.save();
canvas.clipPath(pathFondo);
canvas.drawPath(
  whiteZone,
  Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.src,
);
canvas.restore();

}   // ← cierra el if(dieType == 'TR4D')

// ===== BLOQUE A-B-C — PÉGALO DESPUÉS DEL if(dieType=='TR4D') =====

// Utilidades locales
void drawVerticalDim(double x) {
  canvas.drawLine(Offset(x, topY), Offset(x, botY), dimensionPaint);
}

void drawAxLabel(double xLeft, double xRight, String letter) {
  const double gap = 2;
  final double yMid = (topY + botY) / 2;

  final tp = TextPainter(
    text: TextSpan(
      text: letter,
      style: const TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final double txtLeft  = (xLeft + xRight - tp.width) / 2;
  final double txtRight = txtLeft + tp.width;

  final Paint linePaint = Paint()
    ..color = Colors.black
    ..strokeWidth = 1;

  canvas.drawLine(Offset(xLeft, yMid), Offset(txtLeft - gap, yMid), linePaint);
  canvas.drawLine(Offset(txtRight + gap, yMid), Offset(xRight, yMid), linePaint);
  tp.paint(canvas, Offset(txtLeft, yMid - tp.height / 2));
}

// --- 1) Tramos A-B-C SOLO dentro del “wedge” central ---
final Path _inside =
    Path.combine(PathOperation.intersect, insertoPath, pathFondo);

canvas.save();
canvas.clipPath(_inside);

// limpiar
canvas.drawRect(Rect.fromLTRB(xA, topY, xD, botY), Paint()..color = Colors.white);

// ⬅️ Relleno previo: del inicio del inserto hasta donde empieza A (dentro del wedge)
if (xA > startX) {
  canvas.drawRect(Rect.fromLTRB(startX, topY, xA, botY), Paint()..color = _colA);
}

// A, B normales…
canvas.drawRect(Rect.fromLTRB(xA, topY, xB, botY), Paint()..color = _colA);
canvas.drawRect(Rect.fromLTRB(xB, topY, xC, botY), Paint()..color = _colB);

// ⬇️ C se extiende hasta el final del inserto (salidaX) dentro del wedge
canvas.drawRect(Rect.fromLTRB(xC, topY, salidaX, botY), Paint()..color = _colC);

canvas.restore();

// --- 2) Colas fuera del wedge para igualar colores en los extremos ---
final Path _outside =
    Path.combine(PathOperation.difference, insertoPath, pathFondo);

canvas.save();
canvas.clipPath(_outside);

// Izquierda: desde el inicio del inserto hasta donde comienza A
if (xA > startX) {
  canvas.drawRect(Rect.fromLTRB(startX, topY, xA, botY), Paint()..color = _colA);
}
// Derecha: desde donde empieza C hasta el final del inserto
if (salidaX > xC) {
  canvas.drawRect(Rect.fromLTRB(xC, topY, salidaX, botY), Paint()..color = _colC);
}
canvas.restore();

// --- 3) Líneas internas y letras arriba de todo ---
// recorta SIEMPRE las verticales a la silueta real del inserto
canvas.save();
canvas.clipPath(insertoPath);

final Paint pA    = Paint()..color = Colors.black87..strokeWidth = 2.5..isAntiAlias = false;
final Paint pThin = Paint()..color = Colors.black  ..strokeWidth = 1.0..isAntiAlias = false;

// pequeño margen para que no toque el wedge
const double insetA = 3.0;
const double inset  = 1.5;

// inicio de A (más gruesa, y SOLO a la altura del inserto)
canvas.drawLine(Offset(xA, topY + insetA), Offset(xA, botY - insetA), pA);

// B, C y D normales
canvas.drawLine(Offset(xB, topY + inset), Offset(xB, botY - inset), pThin);
canvas.drawLine(Offset(xC, topY + inset), Offset(xC, botY - inset), pThin);
canvas.drawLine(Offset(xD, topY + inset), Offset(xD, botY - inset), pThin);

canvas.restore();

// Letras
drawAxLabel(xA, xB, 'A');
drawAxLabel(xB, xC, 'B');
drawAxLabel(xC, xD, 'C');

// ===== FIN BLOQUE A-B-C =====

// ===== COTA VERTICAL ESPECIAL TR4D (se pinta AL FINAL, por encima de todo) =====
if (showDieWidthDim && dieType == 'TR4D') {
  // Línea de cota a la izquierda
  final double xDim = borderRect.left - 120.0;   // mueve a izq/der si quieres

  // Inicio de "A" (donde TERMINAN las rojas)
  final double xA     = (p1.dx + cafeLeft.dx) / 2.0;
  final double yA_top = mReduceSup * xA + bReduceSup;   // sobre rampa sup
  final double yA_bot = mReduceInf * xA + bReduceInf;   // sobre rampa inf

  // Mételo un poco dentro del wedge para que “toque” (evita que lo tape la máscara)
  const double kTouchPx = 8.0; // si ves huequito, sube a 10–12
  final Offset extTop = Offset(xA + kTouchPx, yA_top);
  final Offset extBot = Offset(xA + kTouchPx, yA_bot);

  // Pinturas (explicita srcOver por claridad)
  final Paint dim = Paint()
    ..color = Colors.black
    ..strokeWidth = 1
    ..blendMode = BlendMode.srcOver;

  // Línea principal
  canvas.drawLine(Offset(xDim, yA_top), Offset(xDim, yA_bot), dim);

  // Extensiones largas (desde el DADO hacia la cota)
  canvas.drawLine(extTop, Offset(xDim, yA_top), dim);
  canvas.drawLine(extBot, Offset(xDim, yA_bot), dim);

  // Flechas
  const double arrow = 5.0;
  final Path up = Path()
    ..moveTo(xDim - arrow, yA_top + arrow)
    ..lineTo(xDim + arrow, yA_top + arrow)
    ..lineTo(xDim,          yA_top)
    ..close();
  final Path dn = Path()
    ..moveTo(xDim - arrow, yA_bot - arrow)
    ..lineTo(xDim + arrow, yA_bot - arrow)
    ..lineTo(xDim,          yA_bot)
    ..close();
  canvas.drawPath(up, dim);
  canvas.drawPath(dn, dim);

  // Etiqueta (usa conversión vertical que respeta 'sy' y mm/in)
  double pxToMmY(double px) => px / (30.0 * sy);
  String lenStr(double mm)  => showInches
      ? "${(mm / 25.4).toStringAsFixed(dec)} in"
      : "${mm.toStringAsFixed(dec)} mm";

  final double deltaMm = pxToMmY((yA_bot - yA_top).abs());
  final tp = TextPainter(
    text: TextSpan(
      text: lenStr(deltaMm),
      style: const TextStyle(color: Colors.black, fontSize: 12),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  tp.paint(
    canvas,
    Offset(xDim - tp.width - 6, (yA_top + yA_bot) / 2 - tp.height / 2),
  );
}

  // -----------------------------------------
  canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}