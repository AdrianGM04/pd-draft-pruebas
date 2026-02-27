import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:math' show exp, min;
import 'die_designer.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/sheet_data.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'calculo.dart';
import '../models/globals.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart' as xls;

/// Intent para Undo (Ctrl+Z / Cmd+Z)
class _UndoIntent extends Intent {
  const _UndoIntent();
}

/// Intent para Redo (Ctrl+Y / Cmd+Shift+Z)
class _RedoIntent extends Intent {
  const _RedoIntent();
}

/// Entrada del stack de undo: estado guardado + tipo de cambio para restauración selectiva.
class _UndoEntry {
  final SheetData state;
  /// 'diameters' = al deshacer solo se restauran initial/final diameter (no Product Name, etc.); null = restaurar todo.
  final String? changeType;
  const _UndoEntry({required this.state, this.changeType});
}

// Se crea el estado de a pantalla de PD-Draft
class OtraPantalla extends StatefulWidget {
  const OtraPantalla({super.key});

  @override
  State<OtraPantalla> createState() => _OtraPantallaState();
}

// Se configura el estado del preview del pdf con opción de ver Summary, Part Numbers o Both
class PdfPreviewScreen extends StatefulWidget {
  final Future<Uint8List> Function(String section) buildPdf;

  const PdfPreviewScreen({Key? key, required this.buildPdf}) : super(key: key);

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  static const String _sectionSummary = 'summary';
  static const String _sectionPartNumbers = 'partNumbers';
  static const String _sectionBoth = 'both';

  String _pdfSection = _sectionBoth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("PDF Preview")),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (format) => widget.buildPdf(_pdfSection),
              allowPrinting: true,
              allowSharing: true,
              initialPageFormat: PdfPageFormat.letter,
              canChangeOrientation: true,
              pdfFileName: "trefilado.pdf",
              maxPageWidth: 700,
            ),
          ),
          // Selector de sección: Summary (hoja 1), Part Numbers (hoja 2), Both
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Show:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  SizedBox(width: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: _sectionSummary, label: Text("Summary"), icon: Icon(Icons.summarize, size: 18)),
                      ButtonSegment(value: _sectionPartNumbers, label: Text("Part Numbers"), icon: Icon(Icons.numbers, size: 18)),
                      ButtonSegment(value: _sectionBoth, label: Text("Both"), icon: Icon(Icons.picture_as_pdf, size: 18)),
                    ],
                    selected: {_pdfSection},
                    onSelectionChanged: (Set<String> selected) {
                      setState(() => _pdfSection = selected.first);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Se inicializan todas las variables, listas, arrays, y controladores de texto para que la app funcione
class _OtraPantallaState extends State<OtraPantalla> {
  // ───── Zoom ─────
  double _zoomLevel = 1.0;
  Offset _panOffset = Offset.zero;
  double _zoomAtPinchStart = 1.0;
  Offset _panAtPinchStart = Offset.zero;
  Size _viewportSize = Size.zero;
  Offset _centeringOffset = Offset.zero;

  static const double _kStageW = 1500;
  static const double _kStageH = 920;
  static const double _zoomMin = 0.5;
  static const double _zoomMax = 3.0;
  static const double _zoomBtnStep = 0.10;
  static const double _zoomScrollSensitivity = 600.0;

  bool get _isCtrlOrMeta => HardwareKeyboard.instance.logicalKeysPressed.any((k) =>
      k == LogicalKeyboardKey.controlLeft  || k == LogicalKeyboardKey.controlRight ||
      k == LogicalKeyboardKey.metaLeft     || k == LogicalKeyboardKey.metaRight);

  void _zoomAtPoint(double newZoom, Offset focal) {
    newZoom = newZoom.clamp(_zoomMin, _zoomMax);
    if ((newZoom - _zoomLevel).abs() < 0.0005) return;
    final ratio = newZoom / _zoomLevel;
    setState(() {
      _panOffset = focal * (1 - ratio) + _panOffset * ratio;
      _zoomLevel = newZoom;
    });
  }

  Offset get _fittedContentCenter {
    final fitScale = min(_viewportSize.width / _kStageW, _viewportSize.height / _kStageH);
    return Offset(_kStageW * fitScale / 2, _kStageH * fitScale / 2);
  }

  void _zoomIn()  => _zoomAtPoint((_zoomLevel + _zoomBtnStep).clamp(_zoomMin, _zoomMax), _fittedContentCenter);
  void _zoomOut() => _zoomAtPoint((_zoomLevel - _zoomBtnStep).clamp(_zoomMin, _zoomMax), _fittedContentCenter);
  void _zoomReset() => setState(() { _zoomLevel = 1.0; _panOffset = Offset.zero; });
  final TextEditingController diesController = TextEditingController();
  final TextEditingController initialDiameterController = TextEditingController();
  final TextEditingController finalDiameterController = TextEditingController();
  final TextEditingController finalSpeedController = TextEditingController();
  final TextEditingController decimalsController = TextEditingController();
  final TextEditingController limitController = TextEditingController();
  final TextEditingController maxTensileController = TextEditingController();
  final TextEditingController minTensileController = TextEditingController();
  final TextEditingController productNameController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController clientNameController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController advisorController = TextEditingController();

  // FocusNodes para Product Name, Description, Client Name, Advisor (Date se maneja en _selectDate)
  final FocusNode _productNameFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  final FocusNode _clientNameFocusNode = FocusNode();
  final FocusNode _advisorFocusNode = FocusNode();
  // Valores "antes de editar" para poder hacer push del undo al salir del campo
  String _productNameBeforeEdit = '';
  String _descriptionBeforeEdit = '';
  String _clientNameBeforeEdit = '';
  String _advisorBeforeEdit = '';

  List<dynamic> diameters = [];
  List<dynamic> reductions = [];
  List<dynamic> deltas = [];
  List<dynamic> angles = [];
  List<dynamic> tensiles = [];
  List<dynamic> temperatures = [];
  List<dynamic> speeds = [];
  List<dynamic> pressureDieValues= [];
  List<int> individualAngles = [];
  List<double> manualDiameters = [];
  List<int> manualAngles = [];
  List<bool> stock = [];
  List<bool> diametersModified = [];
  List<bool> anglesModified = [];
  List<String?> selectedDieTypes = [];
  

  double totalReduction = 0.0;
  double avgReduction = 0.0;
  double firstReduction = 0.0;
  double lastReduction = 0.0;
  double maxReduction = 0.0;
  double minReduction = 0.0;
  double maxTemp = 0.0;
  double maxDelta = 0.0;
  double minDelta = 0.0;

  String selectedMaterial = 'High Carbon Steel, Stelmor';
  String selectedCarbon = '0.40%';
  int chartType = 2; // 0 = Temp, 1 = Delta, 2 = Red

  final List<String> materialOptions = ['High Carbon Steel, Stelmor', 'High Carbon Steel, Lead Patented', 'High Carbon Steel, Salt Patented', 'Low Carbon Steel, Rod', 'Low Carbon Steel, Annealed', 'Stainless Steel, Rod', 'Stainless Steel, Annealed', 'User Defined Start/Finish Tensile'];
  final List<String> carbonOptions = ['0%', '0.01%', '0.03%', '0.05%', '0.08%', '0.10%', '0.12%', '0.15%', '0.18%', '0.20%', '0.25%', '0.30%', '0.35%', '0.40%', '0.45%', '0.50%', '0.55%', '0.60%', '0.65%', '0.70%', '0.72%', '0.75%', '0.80%', '0.85%', '0.90%', '1.00%'];

  final TextEditingController taperPercentageController = TextEditingController();
  final TextEditingController semitaperPercentageController = TextEditingController();
  String draftingType = 'Full Taper';
  bool semiActive = false;

  List<SheetData> sheets = [SheetData()];
  int currentSheetIndex = 0;

  // Entrada del stack de undo: estado + tipo de cambio para restaurar solo lo afectado
  static const String _undoKindDiameters = 'diameters';

  // Stack para undo (guarda snapshots del estado y tipo de cambio)
  List<_UndoEntry> _undoStack = [];
  // Stack para redo: estado actual antes de un undo, para poder "rehacer"
  List<_UndoEntry> _redoStack = [];
  static const int _maxUndoStackSize = 20; // Limitar a 20 estados para no consumir mucha memoria
  bool _isInitialized = false; // Flag para saber si ya se inicializó la pantalla

  int? editingDiameterIndex;
  int? editingAnglesIndex;
  String? errorMessage;
  int numberOfDies = 5;
  int decimalsdisplay = 2;
  double speeddisplay = 0.0;
  double temperatureLimit = 120;
  double finalReductionPercentage = 15.0;
  double maximumReductionPercentage = 25.0;
  double finalReductionPercentageSkinPass = 10.0;
  double customMinDelta = 0;
  double customMaxDelta = 999;

  double? ultimoValorReduccion;

  bool esperandoRespuesta = false;

  final firstDieController = TextEditingController();
  final middleDiesController = TextEditingController();
  final lastDieController = TextEditingController();
  final TextEditingController minDeltaController = TextEditingController();
  final TextEditingController maxDeltaController = TextEditingController();

  int firstPressuredisplay = 10;
  int middlePressuredisplay = 8;
  int lastPressuredisplay = 8;

  int firstPressure = 10;
  int middlePressure = 8;
  int lastPressure = 8;

  double totalWeight = 0.0;
  String selectedAngleMode = 'auto'; // other values: 'same', 'single'
  int selectedAngle = 12;
  bool usingStockDies = false;

  String selectedSystem = globalSelectedSystem;

  bool isSkinPass = false;
  final TextEditingController skinPassReductionController = TextEditingController();

  double tensileMin = 400;
  double tensileMax = 1200;

  String selectedSpeedUnit = 'm/s';
  String selectedOutputUnit = 'kg/h';
  
  bool showExtraTable = false;
  bool showPressureTable = false;
  bool isManual = false;
  bool isManualAngle = false;
  bool isCustomDelta = false;

  int? editingSheetIndex; 
  TextEditingController johnStunlock = TextEditingController();

  List<String> filteredCarbonOptions = [];

  double limInfTR4D = 0;
  double limInfTR4 = 0;
  double limInfTR6 = 0;
  double limInfTR8 = 0;

  double limSupTR4D = 0;
  double limSupTR4 = 0;
  double limSupTR6 = 0;
  double limSupTR8 = 0;



  // Funcion para generar el numero de parte que se puede ver en la tabla bajo el boton "Part Number"
  String generatePartNumber(double angle, double diameter, String selectedSystem, String prefix) {
    String angleStr = angle.toStringAsFixed(0);
    String sizeLetter;

    switch (prefix) {
      case "TR4D":
        sizeLetter = "F"; // siempre F
        break;

      case "TR4":
        double dia = (selectedSystem == "metric") ? diameter : diameter / 25.4;
        sizeLetter = (dia <= 2.50) ? "J" : "P";
        break;

      case "TR6":
        if (angle >= 16) {
          sizeLetter = "E"; // 16 o más
        } else {
          sizeLetter = "P"; // menos de 16
        }
        break;

      default:
        sizeLetter = "?"; // prefijo desconocido
    }

    // Formato del diámetro
    String formattedDiameter = diameter.toStringAsFixed(3);
    if (selectedSystem == "metric") {
      formattedDiameter = formattedDiameter.replaceAll('.', ',');
    }

    return "$prefix-$angleStr$sizeLetter$formattedDiameter";
  }

  // Funcion para generar el numero de parte que se puede ver en la tabla bajo el boton "Pressure Number"
  String generatePressureNumber(double angle, double diameter, String selectedSystem, String prefix) {
    String angleStr;
    String sizeLetter;

    if (prefix == "PN5") {
      angleStr = "16";
    } else {
      angleStr = "18";
    }

    switch (prefix) {
      case "TR4D":
        sizeLetter = "U";
        break;

      default:
        sizeLetter = "U"; // prefijo desconocido
    }

    // Formato del diámetro
    String formattedDiameter = diameter.toStringAsFixed(3);
    if (selectedSystem == "metric") {
      formattedDiameter = formattedDiameter.replaceAll('.', ',');
    }

    return "$prefix-$angleStr$sizeLetter$formattedDiameter";
  }

  // Valores iniciales al momento de abrir PD-Draft o una nueva sheet
  @override
  void initState() {
    super.initState();
    limitController.text = temperatureLimit.toString();
    finalReductionPercentage = sheets[0].finalReductionPercentage;
    maximumReductionPercentage = sheets[0].maximumReductionPercentage;
    taperPercentageController.text = finalReductionPercentage.toString();
    semitaperPercentageController.text = maximumReductionPercentage.toString();
    firstDieController.text = firstPressuredisplay.toString();      
    middleDiesController.text = middlePressuredisplay.toString();  
    lastDieController.text = lastPressuredisplay.toString();
    maxTensileController.text = tensileMax.toString();
    minTensileController.text = tensileMin.toString();
    selectedDieTypes = List<String?>.filled(99, "TR4");
    filteredCarbonOptions = List.from(carbonOptions);
    selectedSystem = globalSelectedSystem;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (selectedSystem == 'metric') {
        _applyMetricDefaults();
      } else {
        _applyImperialDefaults();
      }
      if (dateController.text.isEmpty) {
        DateTime hoy = DateTime.now();
        String mushySNS = DateFormat('yyyy-MMM-dd').format(hoy);
        dateController.text = mushySNS;
      }
      loadRanges(selectedSystem);
    });
    loadSheetData(0);
    // Marcar como inicializado después de cargar la sheet inicial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isInitialized = true;
      _undoStack.clear(); // Limpiar cualquier estado guardado durante la inicialización
      _redoStack.clear();
    });

    // Al entrar/salir de Product Name, Description, Client Name, Advisor: guardar "antes" y, al salir, push undo si cambió
    _productNameFocusNode.addListener(() {
      if (_productNameFocusNode.hasFocus) {
        _productNameBeforeEdit = productNameController.text;
      } else if (productNameController.text != _productNameBeforeEdit) {
        _pushUndoForMetadataField(productName: _productNameBeforeEdit);
      }
    });
    _descriptionFocusNode.addListener(() {
      if (_descriptionFocusNode.hasFocus) {
        _descriptionBeforeEdit = descriptionController.text;
      } else if (descriptionController.text != _descriptionBeforeEdit) {
        _pushUndoForMetadataField(description: _descriptionBeforeEdit);
      }
    });
    _clientNameFocusNode.addListener(() {
      if (_clientNameFocusNode.hasFocus) {
        _clientNameBeforeEdit = clientNameController.text;
      } else if (clientNameController.text != _clientNameBeforeEdit) {
        _pushUndoForMetadataField(clientName: _clientNameBeforeEdit);
      }
    });
    _advisorFocusNode.addListener(() {
      if (_advisorFocusNode.hasFocus) {
        _advisorBeforeEdit = advisorController.text;
      } else if (advisorController.text != _advisorBeforeEdit) {
        _pushUndoForMetadataField(advisor: _advisorBeforeEdit);
      }
    });
  }

  @override
  void dispose() {
    _productNameFocusNode.dispose();
    _descriptionFocusNode.dispose();
    _clientNameFocusNode.dispose();
    _advisorFocusNode.dispose();
    super.dispose();
  }

  // Funcion que actualiza el valor de "# Dies"
  void updateDiesCount() {
    final int? dies = int.tryParse(diesController.text);
    if (dies != null && dies >= 1 && dies != numberOfDies) {
      // Guardar estado ANTES del cambio usando los valores actuales
      if (_isInitialized && !_isLoadingSheet && !_isUndoing) {
        // Usar los valores actuales pero con numberOfDies anterior
        final snapshot = SheetData(
          numberOfDies: numberOfDies, // Valor anterior
          initialDiameter: initialDiameterController.text,
          finalDiameter: finalDiameterController.text,
          finalSpeed: speeddisplay,
          decimals: decimalsdisplay,
          selectedMaterial: selectedMaterial,
          selectedCarbon: selectedCarbon,
          temperatureLimit: temperatureLimit,
          draftingType: draftingType,
          semiActive: semiActive,
          finalReductionPercentage: finalReductionPercentage,
          maximumReductionPercentage: maximumReductionPercentage,
          finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
          firstPressure: firstPressuredisplay,
          middlePressure: middlePressuredisplay,
          lastPressure: lastPressuredisplay,
          tensileMin: tensileMin,
          tensileMax: tensileMax,
          pressureDieValues: List<String>.from(pressureDieValues),
          selectedAngleMode: selectedAngleMode,
          selectedAngle: selectedAngle,
          individualAngles: List<int>.from(individualAngles),
          selectedSystem: selectedSystem,
          usingStockDies: usingStockDies,
          isSkinPass: isSkinPass,
          selectedSpeedUnit: selectedSpeedUnit,
          selectedOutputUnit: selectedOutputUnit,
          productName: productNameController.text,
          description: descriptionController.text,
          clientName: clientNameController.text,
          date: dateController.text,
          advisor: advisorController.text,
          isManual: isManual,
          isManualAngle: isManualAngle,
          diametersModified: List<bool>.from(diametersModified),
          anglesModified: List<bool>.from(anglesModified),
          isCustomDelta: isCustomDelta,
          customMinDelta: customMinDelta,
          customMaxDelta: customMaxDelta,
        manualDiameters: List<double>.from(manualDiameters),
        manualAngles: List<int>.from(manualAngles),
        );
        
        _undoStack.add(_UndoEntry(state: snapshot, changeType: null));
        _redoStack.clear();
        if (_undoStack.length > _maxUndoStackSize) {
          _undoStack.removeAt(0);
        }
      }
      
      setState(() {
        numberOfDies = dies;
        firstDieController.text = firstPressure.toString();
        middleDiesController.text = middlePressure.toString();
        lastDieController.text = lastPressure.toString();
      });
      applyPressureDieValues();   
      enviarDatosAlBackend();     
    }
  }

  // Funcion que aplica los valores metricos default
  void _applyMetricDefaults() {
    setState(() {
      selectedSystem = 'metric'; // Cambia al sistema seleccionado, no al global
      decimalsdisplay = memoryDecimals;
      decimalsController.text = memoryDecimals.toString();
      limitController.text = "120";
      initialDiameterController.text = "5.5";
      finalDiameterController.text = "2";
      temperatureLimit = 120;
      isManual = false;
      semiActive = false;
      isManualAngle = false;
      diametersModified = List.filled(manualDiameters.length, false);
      anglesModified = List.filled(manualAngles.length, false);
      
      enviarDatosAlBackend();
    });
  }

  // Al momento de picarle a "metric" en la ventana settings se aplican estos cambios
  void _applyMetric() {
    setState(() {
      selectedSystem = 'metric'; // Cambia al sistema seleccionado, no al global
      decimalsdisplay = memoryDecimals;
      decimalsController.text = memoryDecimals.toString();
      limitController.text = "120";
      double initialIn = double.tryParse(initialDiameterController.text) ?? 0;
      double finalIn = double.tryParse(finalDiameterController.text) ?? 0;
      initialDiameterController.text = (initialIn * 25.4).toStringAsFixed(2);
      finalDiameterController.text = (finalIn * 25.4).toStringAsFixed(3);
      temperatureLimit = 120;
      isManual = false;
      semiActive = false;
      isManualAngle = false;
      diametersModified = List.filled(manualDiameters.length, false);
      anglesModified = List.filled(manualAngles.length, false);
      
      enviarDatosAlBackend();
    });
  }

  // Funcion que aplica los valores imperiales default
  void _applyImperialDefaults() {
    setState(() {
      selectedSystem = 'imperial'; // Cambia al sistema seleccionado, no al global
      decimalsdisplay = memoryDecimals;
      decimalsController.text = memoryDecimals.toString();
      limitController.text = "210";
      initialDiameterController.text = "0.218";
      finalDiameterController.text = "0.080";
      temperatureLimit = 210;
      isManual = false;
      semiActive = false;
      isManualAngle = false;
      diametersModified = List.filled(manualDiameters.length, false);
      anglesModified = List.filled(manualAngles.length, false);
      
      enviarDatosAlBackend();
    });
  }

  // Al momento de picarle a "imperial" en la ventana settings se aplican estos cambios
  void _applyImperial() {
    setState(() {
      selectedSystem = 'imperial'; // Cambia al sistema seleccionado, no al global
      decimalsdisplay = memoryDecimals;
      decimalsController.text = memoryDecimals.toString();
      limitController.text = "210";
      double initialMm = double.tryParse(initialDiameterController.text) ?? 0;
      double finalMm = double.tryParse(finalDiameterController.text) ?? 0;
      initialDiameterController.text = (initialMm / 25.4).toStringAsFixed(3);
      finalDiameterController.text = (finalMm / 25.4).toStringAsFixed(3);
      isManual = false;
      semiActive = false;
      isManualAngle = false;
      diametersModified = List.filled(manualDiameters.length, false);
      anglesModified = List.filled(manualAngles.length, false);
      
      enviarDatosAlBackend();
    });
  }

   // Funcion que actualiza el valor de "Decimals"
  void updateDecimals() {
    final int? decimals = int.tryParse(decimalsController.text);
    if (decimals != null && decimals >= 1 && decimals != decimalsdisplay) {
      _saveStateBeforeChange(); // Guardar estado ANTES del cambio
      
      setState(() {
        decimalsdisplay = decimals;
        sheets[currentSheetIndex].decimals = decimals; // Para que se desplieguen correctamente los decimales por cada sheet
      });
      enviarDatosAlBackend();
    }
  }

   // Funcion que actualiza el valor de "Input Speed"
  void updateSpeed() {
    final double? finalSpeed= double.tryParse(finalSpeedController.text);
    if (finalSpeed != null && finalSpeed >= 1 && finalSpeed != speeddisplay) {
      _saveStateBeforeChange(); // Guardar estado ANTES del cambio
      
      setState(() {
        speeddisplay = finalSpeed;
      });
      enviarDatosAlBackend();
    }
  }

   // Funcion que actualiza el valor de "firstPressure"
  void updatePressurefirst() {
    final int? firstPressure = int.tryParse(firstDieController.text);
    if (firstPressure != null && firstPressure >= 1 && firstPressure != firstPressuredisplay) {
      _saveStateBeforeChange();
      setState(() {
        firstPressuredisplay = firstPressure;
      });
    }
  }

   // Funcion que actualiza el valor de "middlePressure"
  void updatePressuremiddle() {
    final int? middlePressure= int.tryParse(middleDiesController.text);
    if (middlePressure != null && middlePressure >= 1 && middlePressure != middlePressuredisplay) {
      _saveStateBeforeChange();
      setState(() {
        middlePressuredisplay = middlePressure;
      });
    }
  }

   // Funcion que actualiza el valor de "lastPressure"
  void updatePressurelast() {
    final int? lastPressure = int.tryParse(lastDieController.text);
    if (lastPressure != null && lastPressure >= 1 && lastPressure != lastPressuredisplay) {
      _saveStateBeforeChange();
      setState(() {
        lastPressuredisplay = lastPressure;
      });
    }
  }

   // Funcion que verifica que al editar diametros de manera manual sean posibles
  void validateDiameters() {
    // Leer los nuevos valores del TextField
    final double? newInitial = double.tryParse(initialDiameterController.text);
    final double? newFinal = double.tryParse(finalDiameterController.text);
    
    // Comparar con los valores guardados en la sheet (valores anteriores)
    final double? oldInitial = double.tryParse(sheets[currentSheetIndex].initialDiameter);
    final double? oldFinal = double.tryParse(sheets[currentSheetIndex].finalDiameter);
    
    // Solo guardar estado si los valores realmente cambiaron
    final bool valuesChanged = (newInitial != null && newFinal != null && 
                                (newInitial != oldInitial || newFinal != oldFinal));
    
    if (valuesChanged && _isInitialized && !_isLoadingSheet && !_isUndoing) {
      // Guardar el snapshot ANTES del cambio: solo el diámetro que cambia usa valor anterior;
      // el otro conserva el actual para que al deshacer no se borre un cambio previo en ese campo.
      final bool initialChanged = newInitial != oldInitial;
      final bool finalChanged = newFinal != oldFinal;
      final snapshot = SheetData(
        numberOfDies: numberOfDies,
        initialDiameter: initialChanged ? sheets[currentSheetIndex].initialDiameter : initialDiameterController.text,
        finalDiameter: finalChanged ? sheets[currentSheetIndex].finalDiameter : finalDiameterController.text,
        finalSpeed: speeddisplay,
        decimals: decimalsdisplay,
        selectedMaterial: selectedMaterial,
        selectedCarbon: selectedCarbon,
        temperatureLimit: temperatureLimit,
        draftingType: draftingType,
        semiActive: semiActive,
        finalReductionPercentage: finalReductionPercentage,
        maximumReductionPercentage: maximumReductionPercentage,
        finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
        firstPressure: firstPressuredisplay,
        middlePressure: middlePressuredisplay,
        lastPressure: lastPressuredisplay,
        tensileMin: tensileMin,
        tensileMax: tensileMax,
        pressureDieValues: List<String>.from(pressureDieValues),
        selectedAngleMode: selectedAngleMode,
        selectedAngle: selectedAngle,
        individualAngles: List<int>.from(individualAngles),
        selectedSystem: selectedSystem,
        usingStockDies: usingStockDies,
        isSkinPass: isSkinPass,
        selectedSpeedUnit: selectedSpeedUnit,
        selectedOutputUnit: selectedOutputUnit,
        productName: productNameController.text,
        description: descriptionController.text,
        clientName: clientNameController.text,
        date: dateController.text,
        advisor: advisorController.text,
        isManual: isManual,
        isManualAngle: isManualAngle,
        diametersModified: List<bool>.from(diametersModified),
        anglesModified: List<bool>.from(anglesModified),
        isCustomDelta: isCustomDelta,
        customMinDelta: customMinDelta,
        customMaxDelta: customMaxDelta,
        manualDiameters: List<double>.from(manualDiameters),
        manualAngles: List<int>.from(manualAngles),
      );
      
      _undoStack.add(_UndoEntry(state: snapshot, changeType: _undoKindDiameters));
      _redoStack.clear();
      if (_undoStack.length > _maxUndoStackSize) {
        _undoStack.removeAt(0);
      }
    }
    
    setState(() {
      if (newInitial == null || newFinal == null) {
        errorMessage = "Please enter valid numbers for diameters.";
      } else if (newInitial <= newFinal) {
        errorMessage = "Initial diameter must be greater than final diameter.";
      } else {
        errorMessage = null;
        // Actualizar la sheet con los diámetros aceptados para que el próximo snapshot
        // use los valores correctos y el undo de "solo final" no deshaga también el initial.
        saveCurrentSheetData();
        enviarDatosAlBackend();
      }
    });
  }

   // Funcion que actualiza el valor de "temperatureLimit"
  void updateTemperatureLimit() {
    final double? limit = double.tryParse(limitController.text);
    if (limit != null && limit > 0 && limit != temperatureLimit) {
      _saveStateBeforeChange(); // Guardar estado ANTES del cambio
      
      setState(() {
        temperatureLimit = limit;
      });
      enviarDatosAlBackend();
    }
  }

  // Funcion que ingresa los valores de presion puestos por el usuario
  void applyPressureDieValues() {
    setState(() {
      pressureDieValues = List.generate(numberOfDies + 1, (index) {
        if (index == 1) return "$firstPressuredisplay";
        if (index == numberOfDies && index != 0) return "$lastPressuredisplay";
        if (index == 0) return "-";
        return "$middlePressuredisplay";
      });

      // Guarda también por hoja
      sheets[currentSheetIndex].pressureDieValues = List<String>.from(pressureDieValues);
    });
    
  }

  // Guarda un snapshot del estado actual en el stack de undo
  // IMPORTANTE: Esta función debe llamarse ANTES de modificar valores, no después
  void _saveStateForUndo() {
    // Crear snapshot directamente desde los valores actuales (TextFields y variables de estado)
    // NO usar saveCurrentSheetData() porque actualizaría la sheet con valores nuevos
    final snapshot = SheetData(
      numberOfDies: numberOfDies,
      initialDiameter: initialDiameterController.text,
      finalDiameter: finalDiameterController.text,
      finalSpeed: speeddisplay,
      decimals: decimalsdisplay,
      selectedMaterial: selectedMaterial,
      selectedCarbon: selectedCarbon,
      temperatureLimit: temperatureLimit,
      draftingType: draftingType,
      semiActive: semiActive,
      finalReductionPercentage: finalReductionPercentage,
      maximumReductionPercentage: maximumReductionPercentage,
      finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
      firstPressure: firstPressuredisplay,
      middlePressure: middlePressuredisplay,
      lastPressure: lastPressuredisplay,
      tensileMin: tensileMin,
      tensileMax: tensileMax,
      pressureDieValues: List<String>.from(pressureDieValues),
      selectedAngleMode: selectedAngleMode,
      selectedAngle: selectedAngle,
      individualAngles: List<int>.from(individualAngles),
      selectedSystem: selectedSystem,
      usingStockDies: usingStockDies,
      isSkinPass: isSkinPass,
      selectedSpeedUnit: selectedSpeedUnit,
      selectedOutputUnit: selectedOutputUnit,
      productName: productNameController.text,
      description: descriptionController.text,
      clientName: clientNameController.text,
      date: dateController.text,
      advisor: advisorController.text,
      isManual: isManual,
      isManualAngle: isManualAngle,
      diametersModified: List<bool>.from(diametersModified),
      anglesModified: List<bool>.from(anglesModified),
      isCustomDelta: isCustomDelta,
      customMinDelta: customMinDelta,
      customMaxDelta: customMaxDelta,
      manualDiameters: List<double>.from(manualDiameters),
      manualAngles: List<int>.from(manualAngles),
    );
    
    _undoStack.add(_UndoEntry(state: snapshot, changeType: null));
    _redoStack.clear(); // Cualquier nuevo cambio borra la cola de redo
    if (_undoStack.length > _maxUndoStackSize) {
      _undoStack.removeAt(0);
    }
  }

  /// Guarda el estado actual en el stack de redo (se usa antes de aplicar un undo).
  void _pushCurrentStateToRedoStack() {
    final snapshot = SheetData(
      numberOfDies: numberOfDies,
      initialDiameter: initialDiameterController.text,
      finalDiameter: finalDiameterController.text,
      finalSpeed: speeddisplay,
      decimals: decimalsdisplay,
      selectedMaterial: selectedMaterial,
      selectedCarbon: selectedCarbon,
      temperatureLimit: temperatureLimit,
      draftingType: draftingType,
      semiActive: semiActive,
      finalReductionPercentage: finalReductionPercentage,
      maximumReductionPercentage: maximumReductionPercentage,
      finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
      firstPressure: firstPressuredisplay,
      middlePressure: middlePressuredisplay,
      lastPressure: lastPressuredisplay,
      tensileMin: tensileMin,
      tensileMax: tensileMax,
      pressureDieValues: List<String>.from(pressureDieValues),
      selectedAngleMode: selectedAngleMode,
      selectedAngle: selectedAngle,
      individualAngles: List<int>.from(individualAngles),
      selectedSystem: selectedSystem,
      usingStockDies: usingStockDies,
      isSkinPass: isSkinPass,
      selectedSpeedUnit: selectedSpeedUnit,
      selectedOutputUnit: selectedOutputUnit,
      productName: productNameController.text,
      description: descriptionController.text,
      clientName: clientNameController.text,
      date: dateController.text,
      advisor: advisorController.text,
      isManual: isManual,
      isManualAngle: isManualAngle,
      diametersModified: List<bool>.from(diametersModified),
      anglesModified: List<bool>.from(anglesModified),
      isCustomDelta: isCustomDelta,
      customMinDelta: customMinDelta,
      customMaxDelta: customMaxDelta,
      manualDiameters: List<double>.from(manualDiameters),
      manualAngles: List<int>.from(manualAngles),
    );
    _redoStack.add(_UndoEntry(state: snapshot, changeType: null));
    if (_redoStack.length > _maxUndoStackSize) _redoStack.removeAt(0);
  }

  // Helper para guardar estado antes de hacer cambios (solo si es necesario)
  void _saveStateBeforeChange() {
    if (_isInitialized && !_isLoadingSheet && !_isUndoing) {
      _saveStateForUndo();
    }
  }

  /// Empuja un snapshot de undo con los valores "anteriores" de Product Name, Description, etc.,
  /// para que al deshacer se restauren esos campos sin borrar el resto.
  void _pushUndoForMetadataField({
    String? productName,
    String? description,
    String? clientName,
    String? date,
    String? advisor,
  }) {
    if (!_isInitialized || _isLoadingSheet || _isUndoing) return;
    final snapshot = SheetData(
      numberOfDies: numberOfDies,
      initialDiameter: initialDiameterController.text,
      finalDiameter: finalDiameterController.text,
      finalSpeed: speeddisplay,
      decimals: decimalsdisplay,
      selectedMaterial: selectedMaterial,
      selectedCarbon: selectedCarbon,
      temperatureLimit: temperatureLimit,
      draftingType: draftingType,
      semiActive: semiActive,
      finalReductionPercentage: finalReductionPercentage,
      maximumReductionPercentage: maximumReductionPercentage,
      finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
      firstPressure: firstPressuredisplay,
      middlePressure: middlePressuredisplay,
      lastPressure: lastPressuredisplay,
      tensileMin: tensileMin,
      tensileMax: tensileMax,
      pressureDieValues: List<String>.from(pressureDieValues),
      selectedAngleMode: selectedAngleMode,
      selectedAngle: selectedAngle,
      individualAngles: List<int>.from(individualAngles),
      selectedSystem: selectedSystem,
      usingStockDies: usingStockDies,
      isSkinPass: isSkinPass,
      selectedSpeedUnit: selectedSpeedUnit,
      selectedOutputUnit: selectedOutputUnit,
      productName: productName ?? productNameController.text,
      description: description ?? descriptionController.text,
      clientName: clientName ?? clientNameController.text,
      date: date ?? dateController.text,
      advisor: advisor ?? advisorController.text,
      isManual: isManual,
      isManualAngle: isManualAngle,
      diametersModified: List<bool>.from(diametersModified),
      anglesModified: List<bool>.from(anglesModified),
      isCustomDelta: isCustomDelta,
      customMinDelta: customMinDelta,
      customMaxDelta: customMaxDelta,
      manualDiameters: List<double>.from(manualDiameters),
      manualAngles: List<int>.from(manualAngles),
    );
    _undoStack.add(_UndoEntry(state: snapshot, changeType: null));
    _redoStack.clear();
    if (_undoStack.length > _maxUndoStackSize) _undoStack.removeAt(0);
  }

  // Restaura el último estado guardado (undo)
  Future<void> _performUndo() async {
    if (_undoStack.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to undo'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // Guardar estado actual en redo antes de deshacer
    _pushCurrentStateToRedoStack();

    // Activar ANTES de cualquier setState para que los onChanged/callbacks
    // de los TextField no guarden estado al restaurar los controladores
    _isUndoing = true;

    final entry = _undoStack.removeLast();
    final previousState = entry.state;

    if (entry.changeType == _undoKindDiameters) {
      // Undo solo de diámetros: restaurar únicamente initial/final diameter.
      // No tocar Product Name, Description, Client, Date, Advisor.
      setState(() {
        initialDiameterController.text = previousState.initialDiameter;
        finalDiameterController.text = previousState.finalDiameter;
      });
      saveCurrentSheetData();
      await enviarDatosAlBackend();
    } else {
      // Undo completo: restaurar todo el estado
      setState(() {
        diesController.text = previousState.numberOfDies.toString();
        initialDiameterController.text = previousState.initialDiameter;
        finalDiameterController.text = previousState.finalDiameter;
        decimalsController.text = previousState.decimals.toString();
        finalSpeedController.text = previousState.finalSpeed.toString();
        speeddisplay = previousState.finalSpeed;
        selectedMaterial = previousState.selectedMaterial;
        selectedCarbon = previousState.selectedCarbon;
        numberOfDies = previousState.numberOfDies;
        temperatureLimit = previousState.temperatureLimit;
        limitController.text = previousState.temperatureLimit.toStringAsFixed(0);
        draftingType = previousState.draftingType;
        semiActive = previousState.semiActive;
        finalReductionPercentage = previousState.finalReductionPercentage;
        taperPercentageController.text = previousState.finalReductionPercentage.toString();
        maximumReductionPercentage = previousState.maximumReductionPercentage;
        semitaperPercentageController.text = previousState.maximumReductionPercentage.toString();
        pressureDieValues = List<String>.from(previousState.pressureDieValues);
        firstPressuredisplay = previousState.firstPressure;
        middlePressuredisplay = previousState.middlePressure;
        lastPressuredisplay = previousState.lastPressure;
        firstDieController.text = previousState.firstPressure.toString();
        middleDiesController.text = previousState.middlePressure.toString();
        lastDieController.text = previousState.lastPressure.toString();
        selectedAngleMode = previousState.selectedAngleMode;
        selectedAngle = previousState.selectedAngle;
        individualAngles = List<int>.from(previousState.individualAngles);
        manualDiameters = List<double>.from(previousState.manualDiameters);
        manualAngles = List<int>.from(previousState.manualAngles);
        usingStockDies = previousState.usingStockDies;
        selectedSystem = previousState.selectedSystem;
        isSkinPass = previousState.isSkinPass;
        finalReductionPercentageSkinPass = previousState.finalReductionPercentageSkinPass;
        selectedSpeedUnit = previousState.selectedSpeedUnit;
        selectedOutputUnit = previousState.selectedOutputUnit;
        productNameController.text = previousState.productName;
        descriptionController.text = previousState.description;
        clientNameController.text = previousState.clientName;
        dateController.text = previousState.date;
        advisorController.text = previousState.advisor;
        isManual = previousState.isManual;
        semiActive = previousState.semiActive;
        isCustomDelta = previousState.isCustomDelta;
        customMinDelta = previousState.customMinDelta;
        minDeltaController.text = previousState.customMinDelta.toString();
        customMaxDelta = previousState.customMaxDelta;
        maxDeltaController.text = previousState.customMaxDelta.toString();
        isManualAngle = previousState.isManualAngle;
        diametersModified = List<bool>.from(previousState.diametersModified);
        anglesModified = List<bool>.from(previousState.anglesModified);
        decimalsdisplay = previousState.decimals;
      });
      saveCurrentSheetData();
      applyPressureDieValues();
      await enviarDatosAlBackend();
    }

    _isUndoing = false;
  }

  // Rehace el último cambio que se deshizo (redo)
  Future<void> _performRedo() async {
    if (_redoStack.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to redo'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // Guardar estado actual en undo para poder deshacer después del redo
    _undoStack.add(_UndoEntry(state: _buildCurrentStateSnapshot(), changeType: null));
    if (_undoStack.length > _maxUndoStackSize) _undoStack.removeAt(0);

    _isUndoing = true; // Evitar que callbacks guarden durante la restauración

    final entry = _redoStack.removeLast();
    final nextState = entry.state;

    setState(() {
      diesController.text = nextState.numberOfDies.toString();
      initialDiameterController.text = nextState.initialDiameter;
      finalDiameterController.text = nextState.finalDiameter;
      decimalsController.text = nextState.decimals.toString();
      finalSpeedController.text = nextState.finalSpeed.toString();
      speeddisplay = nextState.finalSpeed;
      selectedMaterial = nextState.selectedMaterial;
      selectedCarbon = nextState.selectedCarbon;
      numberOfDies = nextState.numberOfDies;
      temperatureLimit = nextState.temperatureLimit;
      limitController.text = nextState.temperatureLimit.toStringAsFixed(0);
      draftingType = nextState.draftingType;
      semiActive = nextState.semiActive;
      finalReductionPercentage = nextState.finalReductionPercentage;
      taperPercentageController.text = nextState.finalReductionPercentage.toString();
      maximumReductionPercentage = nextState.maximumReductionPercentage;
      semitaperPercentageController.text = nextState.maximumReductionPercentage.toString();
      pressureDieValues = List<String>.from(nextState.pressureDieValues);
      firstPressuredisplay = nextState.firstPressure;
      middlePressuredisplay = nextState.middlePressure;
      lastPressuredisplay = nextState.lastPressure;
      firstDieController.text = nextState.firstPressure.toString();
      middleDiesController.text = nextState.middlePressure.toString();
      lastDieController.text = nextState.lastPressure.toString();
      selectedAngleMode = nextState.selectedAngleMode;
      selectedAngle = nextState.selectedAngle;
      individualAngles = List<int>.from(nextState.individualAngles);
      manualDiameters = List<double>.from(nextState.manualDiameters);
      manualAngles = List<int>.from(nextState.manualAngles);
      usingStockDies = nextState.usingStockDies;
      selectedSystem = nextState.selectedSystem;
      isSkinPass = nextState.isSkinPass;
      finalReductionPercentageSkinPass = nextState.finalReductionPercentageSkinPass;
      selectedSpeedUnit = nextState.selectedSpeedUnit;
      selectedOutputUnit = nextState.selectedOutputUnit;
      productNameController.text = nextState.productName;
      descriptionController.text = nextState.description;
      clientNameController.text = nextState.clientName;
      dateController.text = nextState.date;
      advisorController.text = nextState.advisor;
      isManual = nextState.isManual;
      semiActive = nextState.semiActive;
      isCustomDelta = nextState.isCustomDelta;
      customMinDelta = nextState.customMinDelta;
      minDeltaController.text = nextState.customMinDelta.toString();
      customMaxDelta = nextState.customMaxDelta;
      maxDeltaController.text = nextState.customMaxDelta.toString();
      isManualAngle = nextState.isManualAngle;
      diametersModified = List<bool>.from(nextState.diametersModified);
      anglesModified = List<bool>.from(nextState.anglesModified);
      decimalsdisplay = nextState.decimals;
    });
    saveCurrentSheetData();
    applyPressureDieValues();
    await enviarDatosAlBackend();

    _isUndoing = false;
  }

  SheetData _buildCurrentStateSnapshot() {
    return SheetData(
      numberOfDies: numberOfDies,
      initialDiameter: initialDiameterController.text,
      finalDiameter: finalDiameterController.text,
      finalSpeed: speeddisplay,
      decimals: decimalsdisplay,
      selectedMaterial: selectedMaterial,
      selectedCarbon: selectedCarbon,
      temperatureLimit: temperatureLimit,
      draftingType: draftingType,
      semiActive: semiActive,
      finalReductionPercentage: finalReductionPercentage,
      maximumReductionPercentage: maximumReductionPercentage,
      finalReductionPercentageSkinPass: finalReductionPercentageSkinPass,
      firstPressure: firstPressuredisplay,
      middlePressure: middlePressuredisplay,
      lastPressure: lastPressuredisplay,
      tensileMin: tensileMin,
      tensileMax: tensileMax,
      pressureDieValues: List<String>.from(pressureDieValues),
      selectedAngleMode: selectedAngleMode,
      selectedAngle: selectedAngle,
      individualAngles: List<int>.from(individualAngles),
      selectedSystem: selectedSystem,
      usingStockDies: usingStockDies,
      isSkinPass: isSkinPass,
      selectedSpeedUnit: selectedSpeedUnit,
      selectedOutputUnit: selectedOutputUnit,
      productName: productNameController.text,
      description: descriptionController.text,
      clientName: clientNameController.text,
      date: dateController.text,
      advisor: advisorController.text,
      isManual: isManual,
      isManualAngle: isManualAngle,
      diametersModified: List<bool>.from(diametersModified),
      anglesModified: List<bool>.from(anglesModified),
      isCustomDelta: isCustomDelta,
      customMinDelta: customMinDelta,
      customMaxDelta: customMaxDelta,
      manualDiameters: List<double>.from(manualDiameters),
      manualAngles: List<int>.from(manualAngles),
    );
  }

  // Funcion que guarda todas las variables de la app en mapas para poder utilizar multiples sheets
  void saveCurrentSheetData() {
    final current = sheets[currentSheetIndex];
    current.numberOfDies = int.tryParse(diesController.text) ?? 5;
    current.initialDiameter = initialDiameterController.text;
    current.finalDiameter = finalDiameterController.text;
    current.finalSpeed = double.tryParse(finalSpeedController.text) ?? 0.0;
    current.decimals = int.tryParse(decimalsController.text) ?? 3;
    current.selectedMaterial = selectedMaterial;
    current.selectedCarbon = selectedCarbon;
    current.temperatureLimit = temperatureLimit;
    current.finalReductionPercentage = finalReductionPercentage;
    current.maximumReductionPercentage = maximumReductionPercentage;
    current.pressureDieValues = List<String>.from(pressureDieValues);
    current.selectedAngleMode = selectedAngleMode;
    current.selectedAngle = selectedAngle;
    current.individualAngles = List<int>.from(individualAngles);
    current.manualDiameters = List<double>.from(manualDiameters);
    current.manualAngles = List<int>.from(manualAngles);
    current.usingStockDies = usingStockDies;
    current.selectedSystem = selectedSystem;
    current.isSkinPass = isSkinPass;
    current.finalReductionPercentageSkinPass = finalReductionPercentageSkinPass;
    current.selectedOutputUnit = selectedOutputUnit;
    current.selectedSpeedUnit = selectedSpeedUnit;
    current.productName = productNameController.text;
    current.description = descriptionController.text;
    current.clientName = clientNameController.text;
    current.date = dateController.text;
    current.advisor = advisorController.text;
    current.isManual = isManual;
    current.semiActive = semiActive;
    current.draftingType = draftingType;
    current.isManualAngle = isManualAngle;
    current.diametersModified = List<bool>.from(diametersModified);
    current.anglesModified = List<bool>.from(anglesModified);
    current.isCustomDelta = isCustomDelta;
    current.customMinDelta = double.tryParse(minDeltaController.text) ?? 0.0;
    current.customMaxDelta = double.tryParse(maxDeltaController.text) ?? 0.0;

  }

  // Funcion helper para copiar todos los valores de una SheetData a otra
  SheetData _copySheetData(SheetData source) {
    return SheetData(
      numberOfDies: source.numberOfDies,
      initialDiameter: source.initialDiameter,
      finalDiameter: source.finalDiameter,
      finalSpeed: source.finalSpeed,
      decimals: source.decimals,
      selectedMaterial: source.selectedMaterial,
      selectedCarbon: source.selectedCarbon,
      temperatureLimit: source.temperatureLimit,
      draftingType: source.draftingType,
      semiActive: source.semiActive,
      finalReductionPercentage: source.finalReductionPercentage,
      maximumReductionPercentage: source.maximumReductionPercentage,
      finalReductionPercentageSkinPass: source.finalReductionPercentageSkinPass,
      firstPressure: source.firstPressure,
      middlePressure: source.middlePressure,
      lastPressure: source.lastPressure,
      tensileMin: source.tensileMin,
      tensileMax: source.tensileMax,
      pressureDieValues: List<String>.from(source.pressureDieValues),
      selectedAngleMode: source.selectedAngleMode,
      selectedAngle: source.selectedAngle,
      individualAngles: List<int>.from(source.individualAngles),
      selectedSystem: source.selectedSystem,
      usingStockDies: source.usingStockDies,
      isSkinPass: source.isSkinPass,
      selectedSpeedUnit: source.selectedSpeedUnit,
      selectedOutputUnit: source.selectedOutputUnit,
      productName: source.productName,
      description: source.description,
      clientName: source.clientName,
      date: source.date,
      advisor: source.advisor,
      manualDiameters: List<double>.from(source.manualDiameters),
      manualAngles: List<int>.from(source.manualAngles),
      isManual: source.isManual,
      isManualAngle: source.isManualAngle,
      diametersModified: List<bool>.from(source.diametersModified),
      anglesModified: List<bool>.from(source.anglesModified),
      isCustomDelta: source.isCustomDelta,
      customMinDelta: source.customMinDelta,
      customMaxDelta: source.customMaxDelta,
    );
  }

  // Funcion que muestra el dialogo para elegir si copiar valores o usar defaults
  Future<void> _showAddSheetDialog() async {
    final result = await showDialog<bool>( // Mostrar dialogo y esperar una respuesta del usuario
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Sheet'),
        content: const Text(
          'Do you want to copy all values from the current sheet or start with default values?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [ // Botones
          OutlinedButton( // Boton de valores default
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Default Values', style: TextStyle(fontSize: 16)),
          ),
          OutlinedButton( // Boton de copiar los valores actuales a la nueva sheet
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Copy Values', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );

    if (result == null) return; // Usuario cancelo

    // Guardar la sheet actual antes de crear la nueva
    saveCurrentSheetData();

    setState(() {
      if (result == true) {
        // Copiar valores de la sheet actual
        final newSheet = _copySheetData(sheets[currentSheetIndex]);
        newSheet.name = "Sheet ${sheets.length + 1}";
        sheets.add(newSheet);
      } else {
        // Usar valores default
        sheets.add(SheetData(
          name: "Sheet ${sheets.length + 1}",
          selectedSystem: globalSelectedSystem,
        ));
      }

      loadSheetData(sheets.length - 1);

      // Si se usaron defaults, aplicar valores segun el sistema
      if (result == false) {
        if (globalSelectedSystem == 'metric') { // Aplicar valores metricos
          selectedSystem = 'metric';
          decimalsdisplay = memoryDecimals;
          decimalsController.text = memoryDecimals.toString();
          limitController.text = "120";
          initialDiameterController.text = "5.5";
          finalDiameterController.text = "2";
          temperatureLimit = 120;
        } else {
          selectedSystem = 'imperial'; // Aplicar valores imperiales
          decimalsdisplay = memoryDecimals;
          decimalsController.text = memoryDecimals.toString();
          limitController.text = "210";
          initialDiameterController.text = "0.218";
          finalDiameterController.text = "0.080";
          temperatureLimit = 210;
        }
        // Resetear flags manuales
        isManual = false;
        isManualAngle = false;
        diametersModified = List.filled(manualDiameters.length, false);
        anglesModified = List.filled(manualAngles.length, false);
      }

      if (dateController.text.isEmpty) {
        DateTime hoy = DateTime.now();
        String rajang = DateFormat('yyyy-MMM-dd').format(hoy);
        dateController.text = rajang;
      }

      enviarDatosAlBackend();
    });
  }

  // Funcion que carga los valores de las variables obtenidas de los mapas de sheets
  void loadSheetData(int index) {
    _isLoadingSheet = true; // Marcar que estamos cargando una sheet
    // Limpiar los stacks cuando se cambia de sheet
    _undoStack.clear();
    _redoStack.clear();
    final data = sheets[index];
    setState(() {
      diesController.text = data.numberOfDies.toString();
      initialDiameterController.text = data.initialDiameter;
      finalDiameterController.text = data.finalDiameter;
      decimalsController.text = data.decimals.toString();
      decimalsdisplay = data.decimals; // Para que se desplieguen correctamente los decimales por cada sheet
      finalSpeedController.text = data.finalSpeed.toString();
      selectedMaterial = data.selectedMaterial;
      selectedCarbon = data.selectedCarbon;
      numberOfDies = data.numberOfDies;
      temperatureLimit = data.temperatureLimit;
      limitController.text = data.temperatureLimit.toStringAsFixed(0);
      currentSheetIndex = index;
      draftingType = data.draftingType;
      semiActive = data.semiActive;
      finalReductionPercentage = data.finalReductionPercentage;
      taperPercentageController.text = data.finalReductionPercentage.toString();
      maximumReductionPercentage = data.maximumReductionPercentage;
      semitaperPercentageController.text = data.maximumReductionPercentage.toString();
      pressureDieValues = List<String>.from(data.pressureDieValues);
      selectedAngleMode = data.selectedAngleMode;
      selectedAngle = data.selectedAngle;
      individualAngles = List<int>.from(data.individualAngles);
      manualDiameters = List<double>.from(data.manualDiameters);
      manualAngles = List<int>.from(data.manualAngles);
      usingStockDies = data.usingStockDies;
      selectedSystem = data.selectedSystem;
      isSkinPass = data.isSkinPass;
      finalReductionPercentageSkinPass = data.finalReductionPercentageSkinPass;
      selectedSpeedUnit = data.selectedSpeedUnit;
      selectedOutputUnit = data.selectedOutputUnit;
      productNameController.text = data.productName;
      descriptionController.text = data.description;
      clientNameController.text = data.clientName;
      dateController.text = data.date;
      advisorController.text = data.advisor;
      isManual = data.isManual;
      semiActive = data.semiActive;
      isCustomDelta = data.isCustomDelta;
      customMinDelta = data.customMinDelta;
      minDeltaController.text = data.customMinDelta.toString();
      customMaxDelta = data.customMaxDelta;
      maxDeltaController.text = data.customMaxDelta.toString();
      isManualAngle = data.isManualAngle;
      diametersModified = List<bool>.from(
        data.diametersModified.isNotEmpty
            ? data.diametersModified
            : List.filled(data.numberOfDies + 1, false),
        growable: true,
      );
      anglesModified = List<bool>.from(
        data.anglesModified.isNotEmpty
            ? data.anglesModified
            : List.filled(data.numberOfDies + 1, false),
        growable: true,
      );

    });

    applyPressureDieValues();
    enviarDatosAlBackend();
    _isLoadingSheet = false; // Ya terminamos de cargar
  }

  // Funcion que inicializa el proceso de exportacion de datos
  void onExportPressed() async {
    saveCurrentSheetData();  
    await exportSheetsToCSV(sheets);
  }

  // Funcion que inicializa el proceso de exportacion de datos
  void onExportXLSXPressed() async {
    saveCurrentSheetData();  
    await exportSheetsToXLSX(sheets,selectedDieTypes);
    await exportSheetsToXLSXP(sheets,selectedDieTypes);
  }

  Future<void> _selectDate() async {
    _saveStateBeforeChange(); // Guardar estado antes de cambiar la fecha para que entre en la cola del undo
    DateTime hoy = DateTime.now();
    int anio = hoy.year;

    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(anio - 5),
      lastDate: DateTime(anio + 5),
    );

    if (picked != null) {
      setState(() {
        dateController.text =
            DateFormat('yyyy-MMM-dd').format(picked);
      });
    }
  }

  // Funcion para obtener los limites de cada tipo de inserto obtenido del xslx
  Future<void> loadRanges(String unitSystem) async {
    // Leer manifest para encontrar el archivo xlsx real
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);

    // Buscar automáticamente cualquier archivo .xlsx dentro de assets/data/
    final xlsxFiles = manifestMap.keys
        .where((path) => path.contains('data/flutter_assets/assets/excel/') && path.endsWith('.xlsx'))  // 'assets/excel/' DEBUG
        .toList();                                                                  // 'data/flutter_assets/assets/excel/' RELEASE               

    if (xlsxFiles.isEmpty) {
      print("No se encontró ningún archivo XLSX en assets/data/");
      return;
    }

    // Tomamos el primero encontrado
    final String xlsxPath = xlsxFiles.first;
    print("Usando archivo XLSX: $xlsxPath");

    // Cargar bytes del archivo detectado
    ByteData data = await rootBundle.load(xlsxPath);
    List<int> bytes = data.buffer.asUint8List();
    var excel = xls.Excel.decodeBytes(bytes);

    var sheet = excel['Module Variants'];

    double read(int row, int col) {
      var cell = sheet.cell(
        xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      return double.tryParse(cell.value.toString()) ?? 0.0;
    }

    // Columnas para imperial o metric
    int colMin = (unitSystem == "imperial") ? 6 : 8;
    int colMax = (unitSystem == "imperial") ? 7 : 9;

    // FILAS
    limInfTR4  = read(7,  colMin);
    limSupTR4  = read(7,  colMax);

    limInfTR4D = read(8,  colMin);
    limSupTR4D = read(8,  colMax);

    limInfTR6  = read(9,  colMin);
    limSupTR6  = read(9,  colMax);

    limInfTR8  = read(10, colMin);
    limSupTR8  = read(10, colMax);

    
  }

  // Flag para evitar guardar estado cuando se carga una sheet
  bool _isLoadingSheet = false;
  // Flag para evitar guardar estado cuando se está haciendo undo
  bool _isUndoing = false;
  // Flag para indicar si hubo un cambio del usuario que requiere guardar estado
  bool _shouldSaveStateForUndo = false;

  // Funcion que envia los valores de la app al archivo calculo para hacer los calculos
  Future<Map<String, dynamic>?> enviarDatosAlBackend() async {
    // NO guardar estado aquí - cada función debe guardar su propio estado antes de hacer cambios
    final int? dies = int.tryParse(diesController.text);
    final double? initial = double.tryParse(initialDiameterController.text);
    final double? finalD = double.tryParse(finalDiameterController.text);
    final int? decimals = int.tryParse(decimalsController.text);
    final double? finalspeed = double.tryParse(finalSpeedController.text);

    if (dies == null || initial == null || finalD == null || decimals == null) {
      setState(() {
        errorMessage = "Verifica los datos ingresados.";
      });
      return null;
    }

    final materialIndex = materialOptions.indexOf(selectedMaterial);
    final carbonValue = double.tryParse(selectedCarbon.replaceAll('%', ''));

    final body = {
      "initialDiameter": initial,
      "finishDiameter": finalD,
      "dies": dies,
      "materialIndex": materialIndex,
      "carbon": (carbonValue ?? 0),
      "tensileMin": tensileMin,
      "tensileMax": tensileMax,
      "draftingType": draftingType,
      "finalReductionPercentage": finalReductionPercentage,
      "finalReductionPercentageSkinPass": finalReductionPercentageSkinPass,
      "maximumReductionPercentage": maximumReductionPercentage,
      "usingStockDies": usingStockDies,
      "decimals": decimals,
      "finalspeed": finalspeed,
      "pressureDies": pressureDieValues,
      "angleMode": selectedAngleMode,
      "angle": selectedAngle,
      "anglesPerDie": individualAngles,
      "selectedSystem": selectedSystem,
      "isSkinPass": isSkinPass,
      "selectedSpeed": selectedSpeedUnit,
      "selectedOutput": selectedOutputUnit,
      "isManual": isManual,
      "isManualAngle": isManualAngle,
      "manualDiameters": manualDiameters,
      "manualAngles":manualAngles,
    };

    try {
      final resultado = await performCalculations(body);

      // ignore: unnecessary_null_comparison
      if (resultado != null) {
        setState(() {
          diameters = (resultado['diameters'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          manualDiameters = (resultado['diameters'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          manualAngles = (resultado['angles'] as List)
              .map((item) => (item['value'] as num).toInt())
              .toList()
              .sublist(1);

          reductions = (resultado['reductions'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          deltas = (resultado['deltas'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          angles = (resultado['angles'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          tensiles = (resultado['tensiles'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          temperatures = (resultado['temperatures'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          speeds = (resultado['speeds'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .toList();

          totalWeight = (resultado['totalweight'] as List)
              .map((item) => (item['value'] as num).toDouble())
              .first;
            
          stock = (resultado['stock'] as List)
              .map((item) => item is bool ? item : false)
              .toList();

          totalReduction = (resultado['total_reduction'] as num?)?.toDouble() ?? 0.0;

          errorMessage = '';

          List<double> parsedTemperatures = temperatures.length > 1
            ? temperatures.sublist(1).map((item) => (item as num).toDouble()).toList()
            : [];

          if (parsedTemperatures.isNotEmpty) {
            maxTemp = parsedTemperatures.reduce((a, b) => a > b ? a : b);
          }

          List<double> parsedDeltas = deltas.length > 1
            ? deltas.sublist(1).map((item) => (item as num).toDouble()).toList()
            : [];

          if (parsedDeltas.isNotEmpty) {
            maxDelta = parsedDeltas.reduce((a, b) => a > b ? a : b);
          }

          List<double> parsedReductions = reductions.length > 1
            ? reductions.sublist(1).map((item) => (item as num).toDouble()).toList()
            : [];

          if (parsedReductions.isNotEmpty) {
            avgReduction = parsedReductions.reduce((a, b) => a + b) / parsedReductions.length;
            firstReduction = parsedReductions.first;
            lastReduction = parsedReductions.last;
            maxReduction = parsedReductions.reduce((a, b) => a > b ? a : b);
            minReduction = parsedReductions.reduce((a, b) => a < b ? a : b);
          } else {
            avgReduction = firstReduction = lastReduction = maxReduction = minReduction = 0.0;
          }
        });

        print('Datos calculados correctamente con Dart');
        print('--------------------------------');
        return resultado;
      } else {
        setState(() {
          errorMessage = 'Error en el cálculo con Dart';
        });
      }
    } catch (e) {
      print('Error ejecutando cálculo Dart: $e');
      setState(() {
        errorMessage = 'Error ejecutando cálculo Dart: $e';
      });
    }
    return null;
  }

  // Funcion que genera el numero de parte dentro del pdf
  String PDFPartNumber(double angle, double diameter, String selectedSystem, String prefix) {
    String angleStr = angle.toStringAsFixed(0);
    String sizeLetter;

    switch (prefix) {
      case "TR4D":
        sizeLetter = "F"; // siempre F
        break;

      case "TR4":
        sizeLetter = (diameter <= 2.50) ? "J" : "P";
        break;

      case "TR6":
        if (angle >= 16) {
          sizeLetter = "E"; // 16 o más
        } else {
          sizeLetter = "P"; // menos de 16
        }
        break;

      default:
        sizeLetter = "?"; // prefijo desconocido
    }

    // Formato del diámetro
    String formattedDiameter = diameter.toStringAsFixed(3);
    if (selectedSystem == "metric") {
      formattedDiameter = formattedDiameter.replaceAll('.', ',');
    }

    return "$prefix-$angleStr$sizeLetter$formattedDiameter";
  }

  // Funcion que genera el numero de parte de presion dentro del pdf
  String PDFPressureNumber(double angle, double diameter, String selectedSystem, String? dieType,) {
    String prefix;
    switch (dieType) {
      case "TR4D":
      case "TR4":
        prefix = "PN5";
        break;
      case "TR6":
        prefix = "PN8";
        break;
      case "TR8":
        prefix = "PN9";
        break;
      default:
        prefix = "U";
        break;
    }

    String angleStr;
    String sizeLetter;

    if (prefix == "PN5") {
      angleStr = "16";
    } else {
      angleStr = "18";
    }

    switch (prefix) {
      case "TR4D":
        sizeLetter = "U";
        break;

      default:
        sizeLetter = "U"; // prefijo desconocido
    }

    String formattedDiameter = diameter.toStringAsFixed(3);
    if (selectedSystem == "metric") {
      formattedDiameter = formattedDiameter.replaceAll('.', ',');
    }

    return "$prefix-$angleStr$sizeLetter$formattedDiameter";
  }

  // Funcion que limita el espacio que tiene la descripcion dentro del pdf
  String wrapDescription(String text, {int limit = 80}) {
    final words = text.split(' ');
    final buffer = StringBuffer();
    var line = '';

    for (final word in words) {
      // Si la palabra cabe en la línea actual
      if ((line + word).length <= limit) {
        line += (line.isEmpty ? '' : ' ') + word;
      } else {
        // Si ya no cabe, escribimos la línea y empezamos otra
        buffer.writeln(line);
        line = word;
      }
    }

    // Agregar última línea pendiente
    if (line.isNotEmpty) {
      buffer.writeln(line);
    }

    return buffer.toString().trim();
  }

  // Función principal de exportación PDF
  Future<void> generarYExportarPDF(
    List<double> diametros,
    List<dynamic> reductions,
  ) async {
    final pdf = pw.Document();

    // Preparamos datos
    final tableData = List.generate(
      diametros.length,
      (i) {
        String pressDies = '-';

        if (i != 0 && i < pressureDieValues.length && i < diametros.length) {
          final pressureVal = double.tryParse(
            pressureDieValues[i].toString().replaceAll('%', '').trim(),
          ) ?? 0.0;

          final rounded = _pressureDieSizeRounded(i, diametros) ?? 0.0;

          pressDies =
              '${rounded.toStringAsFixed(decimalsdisplay)} (${pressureVal.toStringAsFixed(0)}%)';
        }

        return [
          i == 0 ? '-' : ('$i'),
          diametros[i].toStringAsFixed(decimalsdisplay),
          i == 0 ? '-' : (i < reductions.length ? reductions[i].toStringAsFixed(1) : '-'),
          i == 0 ? '-' : (i < deltas.length ? deltas[i].toStringAsFixed(2) : '-'),
          i == 0 ? '-' : (i < angles.length ? angles[i].toStringAsFixed(0) : '-'),
          i < tensiles.length ? tensiles[i].toStringAsFixed(0) : '-',
          i == 0 ? '-' : (i < temperatures.length ? temperatures[i].toStringAsFixed(0) : '-'),
          i < speeds.length ? speeds[i].toStringAsFixed(2) : '-',
          pressDies,
        ].map((e) => e.toString()).toList();
      },
    );

    final partNumberData = List.generate(diametros.length - 1, (index) {
      final n = index + 1;
      final angle = angles[n];
      final diameter = diametros[n];

      final diameterpressure = _pressureDieSizeRounded(n, diametros) ?? 0.0;

      final prefix = selectedDieTypes.length > index && selectedDieTypes[index] != null
          ? selectedDieTypes[index]!
          : "TR4";

      final dieType = selectedDieTypes.length > index && selectedDieTypes[index] != null
          ? selectedDieTypes[index]!
          : "TR4";

      final partNumber = PDFPartNumber(angle, diameter, selectedSystem, prefix);
      final pressureNumber = PDFPressureNumber(angle, diameterpressure, selectedSystem, dieType);

      return [
        n.toString(),
        partNumber,
        pressureNumber,
      ];
    });

    final imageBytes = await rootBundle.load('assets/images/titulo5-logo.png');
    final image = pw.MemoryImage(imageBytes.buffer.asUint8List());

    // MultiPage PRINCIPAL con header en todas las páginas
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,

        // HEADER que se repetirá en TODAS las páginas
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Logo centrado
            pw.Center(
              child: pw.Image(image, width: 300, height: 240),
            ),
            pw.SizedBox(height: 12),

            // Fila principal con dos columnas
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Columna izquierda: Product Name y Description
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Product Name: ${productNameController.text}",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      "Description: ",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      wrapDescription(descriptionController.text, limit: 80),
                      style: pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),

                // Columna derecha: Date, Client Name y Technical Rep
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Date: ${dateController.text}",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      "Client Name: ${clientNameController.text}",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      "Technical Rep: ${advisorController.text}",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 5),
            pw.Divider(),
          ],
        ),

        // CONTENIDO PRINCIPAL
        build: (context) => [

          // TABLA MATERIAL
          pw.Table.fromTextArray(
            columnWidths: const {
              0: pw.FractionColumnWidth(0.2),
              1: pw.FractionColumnWidth(0.2),
              2: pw.FractionColumnWidth(0.2),
              3: pw.FractionColumnWidth(0.2),
              4: pw.FractionColumnWidth(0.2),
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center, 
            cellAlignment: pw.Alignment.center,   
            headers: [
              'Material', 
              'Carbon %', 
              'Skim Pass %', 
              'Final Speed (${selectedSpeedUnit})', 
              'Output (${selectedOutputUnit})'
            ],
            data: [
              [
                selectedMaterial,
                selectedCarbon,
                isSkinPass == true ? skinPassReductionController.text : '-',
                speeds[numberOfDies].toStringAsFixed(2),
                totalWeight.toStringAsFixed(2),
              ]
            ],
          ),
          pw.SizedBox(height: 10),

          // TABLA REDUCCIONES
          pw.Center(
            child: pw.Container(
              width: 320,
              child: pw.Table.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(),
                  1: pw.FlexColumnWidth(),
                  2: pw.FlexColumnWidth(),
                  3: pw.FlexColumnWidth(),
                  4: pw.FlexColumnWidth()
                },
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
                cellStyle: pw.TextStyle(fontSize: 9),
                headerAlignment: pw.Alignment.center, 
                cellAlignment: pw.Alignment.center,   
                headers: [
                  'Drafting Type', 'Total %', 'Average %', 'First %', 'Last %'
                ],
                data: [
                  [
                    draftingType,
                    totalReduction.toStringAsFixed(1),
                    avgReduction.toStringAsFixed(1),
                    firstReduction.toStringAsFixed(1),
                    lastReduction.toStringAsFixed(1),
                  ]
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 10),

          // TABLA GRANDE DE DATOS
          pw.Table.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center, // Centramos encabezados
            cellAlignment: pw.Alignment.center,   // Centramos celdas
            headers: [
              'Die',
              selectedSystem == 'metric' ? 'Diameter (mm)' : 'Diameter (in)',
              'Reduction (%)',
              'Delta',
              'Angle',
              'Tensile Strength (MPa)',
              selectedSystem == 'metric' ? 'Temperature (°C)' : 'Temperature (°F)',
              'Speed (${selectedSpeedUnit})',
              'Press Dies'
            ],
            columnWidths: const {
              0: pw.FractionColumnWidth(0.06),
              1: pw.FractionColumnWidth(0.13),
              2: pw.FractionColumnWidth(0.14),
              3: pw.FractionColumnWidth(0.08),
              4: pw.FractionColumnWidth(0.09),
              5: pw.FractionColumnWidth(0.12),
              6: pw.FractionColumnWidth(0.17),
              7: pw.FractionColumnWidth(0.10),
              8: pw.FractionColumnWidth(0.12),
            },
            data: tableData,
          ),
          pw.SizedBox(height: 20),

          // GRÁFICAS
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Temperatura
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text("Temperature", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 42),
                    ..._buildChartBars(
                      temperatures.map((e) => (e as num).toDouble()).toList(),
                      chartType: 0,
                    ),
                  ],
                ),
              ),
              pw.Container(width: 1, color: PdfColors.grey, height: 180),
              // Reducción + Delta
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text("Reduction (%) + Delta", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    ..._buildChartBars(
                      reductions.map((e) => (e as num).toDouble()).toList(),
                      chartType: 2,
                      secondaryValues: deltas.map((e) => (e as num).toDouble()).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // SEGUNDO MultiPage solo para Part Numbers (también con header automático)
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(child: pw.Image(image, width: 150, height: 120)),
            pw.SizedBox(height: 5),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.Text("Part Numbers", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            columnWidths: const {
              0: pw.FractionColumnWidth(0.1),
              1: pw.FractionColumnWidth(0.25),
              2: pw.FractionColumnWidth(0.65),
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center, 
            cellAlignment: pw.Alignment.center,   
            headers: ['# Die', 'Part Number', 'Pressure Number'],
            data: partNumberData,
          ),
        ],
      ),
    );

    // Guardar o imprimir
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  /// Valores para mostrar solo una sección del PDF en el preview: 'summary' (hoja 1), 'partNumbers' (hoja 2), 'both'.
  static const String pdfSectionSummary = 'summary';
  static const String pdfSectionPartNumbers = 'partNumbers';
  static const String pdfSectionBoth = 'both';

  // Funcion que genera todo el cuerpo de las paginas de pdf
  Future<Uint8List> generarPDFBytes(
    List<double> diametros,
    List<dynamic> reductions, {
    String pdfSection = 'both',
  }) async {
    final pdf = pw.Document();

    final tableData = List.generate(
      diametros.length,
      (i) {
        String pressureDisplay;

      if (i < pressureDieValues.length && i < diametros.length && i != 0) {
        final pressureVal = double.tryParse(
          pressureDieValues[i].toString().replaceAll('%', '').trim(),
        ) ?? 0.0;

        final rounded = _pressureDieSizeRounded(i, diametros) ?? 0.0;

        pressureDisplay =
            '${rounded.toStringAsFixed(decimalsdisplay)} (${pressureVal.toStringAsFixed(0)}%)';
      } else {
        pressureDisplay = '-';
      }

        return [
          i == 0 ? '-' : ('$i'),
          diametros[i].toStringAsFixed(decimalsdisplay),
          i == 0 ? '-' : (i < reductions.length ? reductions[i].toStringAsFixed(1) : '-'),
          i == 0 ? '-' : (i < deltas.length ? deltas[i].toStringAsFixed(2) : '-'),
          i == 0 ? '-' : (i < angles.length ? angles[i].toStringAsFixed(0) : '-'),
          i < tensiles.length ? tensiles[i].toStringAsFixed(0) : '-',
          i == 0 ? '-' : (i < temperatures.length ? temperatures[i].toStringAsFixed(0) : '-'),
          i < speeds.length ? speeds[i].toStringAsFixed(2) : '-',
          pressureDisplay,
        ].map((e) => e.toString()).toList();
      },
    );

    /*
    // Preparamos datos
    final tableData = List.generate(
      diametros.length,
      (i) => [
        i == 0 ? '-' : ('$i'),
        diametros[i].toStringAsFixed(decimalsdisplay),
        i == 0 ? '-' : (i < reductions.length ? reductions[i].toStringAsFixed(1) : '-'),
        i == 0 ? '-' : (i < deltas.length ? deltas[i].toStringAsFixed(2) : '-'),
        i == 0 ? '-' : (i < angles.length ? angles[i].toStringAsFixed(0) : '-'),
        i < tensiles.length ? tensiles[i].toStringAsFixed(0) : '-',
        i == 0 ? '-' : (i < temperatures.length ? temperatures[i].toStringAsFixed(0) : '-'),
        i < speeds.length ? speeds[i].toStringAsFixed(2) : '-',
        i < pressureDieValues.length ? pressureDieValues[i].toString() : '-',
      ].map((e) => e.toString()).toList(),
    );
    */

    final partNumberData = List.generate(diametros.length - 1, (index) {
      final n = index + 1;
      final angle = angles[n];
      final diameter = diametros[n];

      final diameterpressure = _pressureDieSizeRounded(n, diametros) ?? 0.0;


      final prefix = selectedDieTypes.length > index && selectedDieTypes[index] != null
          ? selectedDieTypes[index]!
          : "TR4";

      final dieType = selectedDieTypes.length > index && selectedDieTypes[index] != null
          ? selectedDieTypes[index]!
          : "TR4";

      final partNumber = PDFPartNumber(angle, diameter, selectedSystem, prefix);
      final pressureNumber = PDFPressureNumber(angle, diameterpressure, selectedSystem, dieType);

      return [
        n.toString(),
        partNumber,
        pressureNumber,
        "---------"
      ];
    });

    final imageBytes = await rootBundle.load('assets/images/titulo5-logo.png');
    final image = pw.MemoryImage(imageBytes.buffer.asUint8List());

    // Hoja 1: Summary
    if (pdfSection == pdfSectionSummary || pdfSection == pdfSectionBoth) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Image(image, width: 300, height: 240),
            ),
            pw.SizedBox(height: 12),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Product Name: ${productNameController.text}",
                      style: pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text("Description: ", style: pw.TextStyle(fontSize: 9)),
                    pw.Text(
                      wrapDescription(descriptionController.text, limit: 80),
                      style: pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Date: ${dateController.text}", style: pw.TextStyle(fontSize: 9)),
                    pw.Text("Client Name: ${clientNameController.text}", style: pw.TextStyle(fontSize: 9)),
                    pw.Text("Technical Rep: ${advisorController.text}", style: pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(),
          ],
        ),
        build: (context) => [

          pw.Table.fromTextArray(
            columnWidths: const {
              0: pw.FractionColumnWidth(0.2),
              1: pw.FractionColumnWidth(0.2),
              2: pw.FractionColumnWidth(0.2),
              3: pw.FractionColumnWidth(0.2),
              4: pw.FractionColumnWidth(0.2),
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.center,
            headers: [
              'Material',
              'Carbon %',
              'Skim Pass %',
              'Final Speed (${selectedSpeedUnit})',
              'Output (${selectedOutputUnit})'
            ],
            data: [
              [
                selectedMaterial,
                selectedCarbon,
                isSkinPass == true ? skinPassReductionController.text : '-',
                speeds[numberOfDies].toStringAsFixed(2),
                totalWeight.toStringAsFixed(2),
              ]
            ],
          ),
          pw.SizedBox(height: 10),

          pw.Center(
            child: pw.Container(
              width: 320,
              child: pw.Table.fromTextArray(
                columnWidths: const {
                  0: pw.FlexColumnWidth(),
                  1: pw.FlexColumnWidth(),
                  2: pw.FlexColumnWidth(),
                  3: pw.FlexColumnWidth(),
                  4: pw.FlexColumnWidth(),
                },
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: pw.TextStyle(fontSize: 9),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.center,
                headers: ['Drafting Type', 'Total %', 'Average %', 'First %', 'Last %'],
                data: [
                  [
                    draftingType,
                    totalReduction.toStringAsFixed(1),
                    avgReduction.toStringAsFixed(1),
                    firstReduction.toStringAsFixed(1),
                    lastReduction.toStringAsFixed(1),
                  ]
                ],
              ),
            ),
          ),
          pw.SizedBox(height: 10),

          pw.Table.fromTextArray(
            columnWidths: const {
              0: pw.FractionColumnWidth(0.06),
              1: pw.FractionColumnWidth(0.13),
              2: pw.FractionColumnWidth(0.14),
              3: pw.FractionColumnWidth(0.08),
              4: pw.FractionColumnWidth(0.09),
              5: pw.FractionColumnWidth(0.12),
              6: pw.FractionColumnWidth(0.17),
              7: pw.FractionColumnWidth(0.10),
              8: pw.FractionColumnWidth(0.12),
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.center,
            headers: [
              'Die',
              selectedSystem == 'metric' ? 'Diameter (mm)' : 'Diameter (in)',
              'Reduction (%)',
              'Delta',
              'Angle',
              'Tensile Strength (MPa)',
              selectedSystem == 'metric' ? 'Temperature (°C)' : 'Temperature (°F)',
              'Speed (${selectedSpeedUnit})',
              'Press Dies'
            ],
            data: tableData,
          ),
          pw.SizedBox(height: 20),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text("Temperature", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 42),
                    ..._buildChartBars(
                      temperatures.map((e) => (e as num).toDouble()).toList(),
                      chartType: 0,
                    ),
                  ],
                ),
              ),
              pw.Container(width: 1, color: PdfColors.grey, height: 180),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text("Reduction (%) + Delta", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 5),
                    ..._buildChartBars(
                      reductions.map((e) => (e as num).toDouble()).toList(),
                      chartType: 2,
                      secondaryValues: deltas.map((e) => (e as num).toDouble()).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
    }

    // Hoja 2: Part Numbers
    if (pdfSection == pdfSectionPartNumbers || pdfSection == pdfSectionBoth) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(child: pw.Image(image, width: 150, height: 120)),
            pw.SizedBox(height: 5),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.Text("Part Numbers", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            columnWidths: const {
              0: pw.FractionColumnWidth(0.1),
              1: pw.FractionColumnWidth(0.25),
              2: pw.FractionColumnWidth(0.25),
              3: pw.FractionColumnWidth(0.65),
            },
            headerDecoration: pw.BoxDecoration(color: PdfColor.fromInt(0xE51837)),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: pw.TextStyle(fontSize: 9),
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.center,
            headers: ['# Die', 'Part Number', 'Pressure Number', 'Price'],
            data: partNumberData,
          ),
        ],
      ),
    );
    }

    return pdf.save();
  }

  // Funcion que controla los limite de las graficas dentro del pdf
  List<pw.Widget> _buildChartBars(
      List<double> values, {
      required int chartType,
      List<double>? secondaryValues,
    }) {
      final List<pw.Widget> bars = [];

      // Valores máximos y ancho total
      final maxValue = chartType == 0
          ? 300 // Temperatura
          : chartType == 1
              ? 3.7 // Delta
              : 200; // Reducción

      // Valor de ancho de píxeles
      final barMaxWidth = chartType == 0
          ? 200.0
          : chartType == 1
              ? 200.0
              : 600.0;

      // Intervalos de tick
      final tickStep = chartType == 0
          ? 50.0
          : chartType == 1
              ? 0.5
              : 15.0;

      // Colores para las barras
      final greenColor = chartType == 0
          ? PdfColors.green
          : chartType == 1
              ? PdfColor.fromInt(0xFF103E64)
              : PdfColor.fromInt(0xFF7556CA);

      // Color para el rectángulo después del límite
      final redColor = chartType == 0 ? PdfColors.red : null;

      // Valor que controla la calibración entre tick y gráfico
      final factorH = chartType == 0
          ? 1.07
          : chartType == 1
              ? 1.02
              : 1.04;

      // Ticks superiores (solo para Delta)
      if (chartType == 2 && secondaryValues != null) {
        const deltaMax = 11.5;
        const deltaStep = 0.5;
        final upperTickWidgets = <pw.Widget>[];

        for (double tick = 0; tick <= deltaMax; tick += deltaStep) {
          final tickPosition = (tick / deltaMax) * barMaxWidth + 13.2;
          upperTickWidgets.add(
            pw.Positioned(
              left: tickPosition,
              top: 0,
              child: pw.Column(
                children: [
                  pw.Text(tick.toStringAsFixed(1), style: pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 2),
                  pw.Container(width: 1, height: 5, color: PdfColors.black),
                ],
              ),
            ),
          );
        }

        // Leyenda de Delta (arriba)
        bars.add(
          pw.Container(
            width: barMaxWidth,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(
              "Delta (black)",
              style: pw.TextStyle(fontSize: 9, color: PdfColors.black),
            ),
          ),
        );

        // Añadir ticks superiores antes de la gráfica
        bars.add(
          pw.Container(
            width: barMaxWidth,
            height: 20,
            child: pw.Stack(children: upperTickWidgets),
          ),
        );

      }

      // Añadimos todas las barras de datos
      for (int i = 1; i < values.length; i++) {
        double value = values[i];

        // Método de calibración individual de cada gráfico
        if (chartType == 5) {
          value = 30.0;
        }

        // Controlador del ancho del primer rectángulo de los gráficos
        final greenWidth = value <= temperatureLimit
            ? value * barMaxWidth * factorH / maxValue
            : temperatureLimit * barMaxWidth * factorH / maxValue;

        // Controlador del ancho del segundo rectángulo de los gráficos
        final redWidth = value > temperatureLimit
            ? (value - temperatureLimit) / maxValue * barMaxWidth
            : 0.0;

        // Modificador de posicionamiento en X de los ticks de los gráficos
        final double xpos =
            chartType == 0 ? 18 : chartType == 1 ? 4.7 : 16.3;

        bars.add(
          pw.Container(
            height: 14,
            margin: pw.EdgeInsets.symmetric(vertical: 2, horizontal: xpos),
            child: pw.Stack(
              children: [
                // Barra de temperatura y reducción
                pw.Positioned(
                  left: 0,
                  top: 0,
                  child: pw.Row(
                    children: [
                      pw.Container(width: greenWidth, height: 10, color: greenColor),
                      if (redWidth > 0)
                        pw.Container(width: redWidth, height: 10, color: redColor),
                    ],
                  ),
                ),
                // Punto de delta
                if (chartType == 2 &&
                    secondaryValues != null &&
                    i < secondaryValues.length)
                  pw.Positioned(
                    left: (secondaryValues[i] / 11.5) * barMaxWidth,
                    top: 1,
                    child: pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.black,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      // Ticks inferiores (para la métrica principal)
      final tickWidgets = <pw.Widget>[];
      for (double tick = 0; tick <= maxValue; tick += tickStep) {
        final tickPosition = chartType == 0
            ? (tick / maxValue) * barMaxWidth
            : (tick / maxValue) * barMaxWidth + 15;
        tickWidgets.add(
          pw.Positioned(
            left: tickPosition,
            top: 0,
            child: pw.Column(
              children: [
                pw.Container(width: 1, height: 5, color: PdfColors.black),
                pw.SizedBox(height: 2),
                pw.Text(
                  chartType == 1 ? tick.toStringAsFixed(1) : tick.toStringAsFixed(0),
                  style: pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        );
      }

      // Añadir ticks inferiores después de la gráfica
      bars.add(
        pw.Container(
          width: barMaxWidth,
          height: 20,
          child: pw.Stack(children: tickWidgets),
        ),
      );

      // Leyenda de Reducción (debajo)
      if (chartType == 2) {
        bars.add(
          pw.Container(
            width: barMaxWidth,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.only(top: 2, bottom: 6),
            child: pw.Text(
              "Reduction (purple)",
              style: pw.TextStyle(
                fontSize: 9,
                color: PdfColor.fromInt(0xFF7556CA),
              ),
            ),
          ),
        );
      }

      bars.add(pw.SizedBox(height: 10));

      return bars;
  }

  // Función externa para redondeo personalizado
  double redondearCuartoDecimal(double value) {
    
    // Multiplicamos por 10000 para trabajar con enteros
    double valueX10000 = value * 10000;
    int valueInt = valueX10000.round();
    
    // Obtenemos el cuarto decimal (último dígito)
    int fourthDecimal = valueInt % 10;
    
    // Obtenemos la base (primeros 3 decimales)
    int base = valueInt ~/ 10;
    double resultado;
    
    if (fourthDecimal <= 2) {
      resultado = base / 1000.0;
    } else if (fourthDecimal <= 5) {
      resultado = (base + 0.5) / 1000.0;
    } else {
      resultado = (base + 1) / 1000.0;
    }
    
    return resultado;
  }

// --- Paramount Standard Pressure Die rounding helpers ---

double _asDouble(dynamic x) {
  if (x == null) return double.nan;
  if (x is num) return x.toDouble();
  return double.tryParse(x.toString()) ?? double.nan;
}

double _roundUpToMultiple(double value, double step) {
  if (step <= 0) return value;

  final q = value / step;

  // Si ya es múltiplo (tolerancia por floats), se queda igual.
  final isMultiple = (q - q.roundToDouble()).abs() < 1e-9;
  if (isMultiple) return value;

  return q.ceilToDouble() * step;
}

/// Decide el "step" basado en el PRIMER Pressure Die (die #1).
/// Reglas (en mm):
///  - 1.00–2.54 => step 0.02
///  - 2.55–6.05 => step 0.05
double? _paramountPressureStepMm(List<dynamic> diametros) {
  if (!usingStockDies) return null;

  if (diametros.length < 2) return null;
  if (pressureDieValues.length < 2) return null;

  // Parse robusto (por si trae espacios o %)
  final p1 = double.tryParse(
    pressureDieValues[1].toString().replaceAll('%', '').trim(),
  );
  if (p1 == null) return null;

  final incoming = _asDouble(diametros[0]);
  if (incoming.isNaN) return null;

  final rawFirst = incoming * (1.0 + p1 / 100.0);

  // Reglas en mm
  final firstMm = (selectedSystem == "imperial") ? rawFirst * 25.4 : rawFirst;

  const eps = 1e-9; // <- CLAVE para que 6.050000000000001 cuente como 6.05

  if (firstMm >= 1.00 - eps && firstMm <= 2.54 + eps) return 0.02;
  if (firstMm >= 2.55 - eps && firstMm <= 6.05 + eps) return 0.05;

  return null;
}

double? _pressureDieSizeRounded(int index, List<dynamic> diametros) {
  if (index <= 0) return null;
  if (index >= diametros.length) return null;
  if (index >= pressureDieValues.length) return null;

  final p = double.tryParse(pressureDieValues[index].toString());
  if (p == null) return null;

  final prev = _asDouble(diametros[index - 1]);
  if (prev.isNaN) return null;

  // Cálculo original (igual que hoy)
  final raw = prev * (1.0 + p / 100.0);

  final stepMm = _paramountPressureStepMm(diametros);
  if (stepMm == null) return raw;

  // Aplicar redondeo en mm (aunque estés mostrando imperial)
  if (selectedSystem == "imperial") {
    final rawMm = raw * 25.4;
    final roundedMm = _roundUpToMultiple(rawMm, stepMm);
    return roundedMm / 25.4;
  } else {
    return _roundUpToMultiple(raw, stepMm);
  }
}


  // Exportar CSV 
  Future<void> exportSheetsToCSV(List<SheetData> sheets) async {
    StringBuffer buffer = StringBuffer();

    for (int i = 0; i < sheets.length; i++) {
      final sheet = sheets[i];

      // Línea "Sheet N" para compatibilidad (Sheet 1, Sheet 2, ...)
      buffer.writeln("Sheet ${i + 1}");

      // Línea con el nombre real de la hoja
      buffer.writeln("Sheet Name, ${sheet.name.isNotEmpty ? sheet.name : ''}");

      buffer.writeln("Client Name, ${sheet.clientName}");
      buffer.writeln("Product Name, ${sheet.productName}");
      buffer.writeln("Description, ${sheet.description}");
      buffer.writeln("Date, ${sheet.date}");
      buffer.writeln("Sales Rep, ${sheet.advisor}");
      buffer.writeln("Number of Dies, ${sheet.numberOfDies}");
      buffer.writeln("Initial Diameter, ${sheet.initialDiameter}");
      buffer.writeln("Final Diameter, ${sheet.finalDiameter}");
      buffer.writeln("Manual Diameters, ${sheet.manualDiameters.join('|')}");
      buffer.writeln("Manual Angles, ${sheet.manualAngles.join('|')}");
      buffer.writeln("Is Manual Diameters, ${sheet.isManual}");
      buffer.writeln("Is Manual Angles, ${sheet.isManualAngle}");
      buffer.writeln("Decimals, ${sheet.decimals}");
      buffer.writeln("Final Speed, ${sheet.finalSpeed}");
      buffer.writeln("Selected Material, \"${sheet.selectedMaterial}\"");
      buffer.writeln("Selected Carbon, ${sheet.selectedCarbon}");
      buffer.writeln("Temperature Limit, ${sheet.temperatureLimit}");
      buffer.writeln("Drafting Type, ${sheet.draftingType}");
      buffer.writeln("Active Semi Taper, ${sheet.semiActive}");
      buffer.writeln("Final Reduction Percentage, ${sheet.finalReductionPercentage}");
      buffer.writeln("Final Reduction Percentage Skim Pass, ${sheet.finalReductionPercentageSkinPass}");
      buffer.writeln("Maximum Reduction Percentage, ${sheet.maximumReductionPercentage}");
      buffer.writeln("First Pressure, ${sheet.firstPressure}");
      buffer.writeln("Middle Pressure, ${sheet.middlePressure}");
      buffer.writeln("Last Pressure, ${sheet.lastPressure}");
      buffer.writeln("Tensile Minimum, ${sheet.tensileMin}");
      buffer.writeln("Tensile Maximum, ${sheet.tensileMax}");
      buffer.writeln("Pressure Die Values, ${sheet.pressureDieValues.join('|')}");
      buffer.writeln("Selected Angle Mode, ${sheet.selectedAngleMode}");
      buffer.writeln("Selected Angle, ${sheet.selectedAngle}");
      buffer.writeln("Individual Angles, ${sheet.individualAngles.join('|')}");
      buffer.writeln("Using Stock Dies, ${sheet.usingStockDies}");
      buffer.writeln("Selected System, ${sheet.selectedSystem}");
      buffer.writeln("Is Skim Pass, ${sheet.isSkinPass}");
      buffer.writeln("Selected Speed Unit, ${sheet.selectedSpeedUnit}");
      buffer.writeln("Selected Output Unit, ${sheet.selectedOutputUnit}");
      buffer.writeln("Is Custom Delta, ${sheet.isCustomDelta}");
      buffer.writeln("Custom Min Delta, ${sheet.customMinDelta}");
      buffer.writeln("Custom Max Delta, ${sheet.customMaxDelta}");
      buffer.writeln(""); // Línea vacía entre sheets
    }

    final bytes = utf8.encode(buffer.toString());

    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd_HH-mm');
    final formattedDate = formatter.format(now);

    final fileName = 'pd_draft_$formattedDate';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.text,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('CSV exported succesfully, check Downloads'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Exportar XLSXP
  Future<void> exportSheetsToXLSXP(List<SheetData> sheets, selectedDieTypes) async {
    var excel = xls.Excel.createExcel();
    xls.Sheet sheet = excel['Sheet1'];

    int currentRow = 0;
    List<double> pressureDieValuesDouble =
    pressureDieValues.map((e) {
      if (e.trim().isEmpty) return 0.0;
      return double.tryParse(e) ?? 0.0;
    }).toList(); 

    for (int i = 0; i < sheets.length; i++) {
      final sheetData = sheets[i];

      final headers = [
        "Customer Name",
        "Customer Preferred Units",
        "Units",
        "Size (in)",
        "Size (mm)",
        "Quantity",
        "Insert Type",
        "Short Version",
      ];

      for (int col = 0; col < headers.length; col++) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow))
            .value = headers[col];
      }
      currentRow++;

      for (int die = 0; die < sheetData.numberOfDies; die++) {
        
        // Column 0: Customer Name
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow))
            .value = sheetData.clientName;
        
        // Column 1: Customer Preferred Unit
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow))
            .value = sheetData.selectedSystem;
        
        // Column 2: Units
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow))
            .value = sheetData.selectedSystem;
        
        // Column 3: Size (in)
        switch (sheetData.selectedSystem) {
          case "metric":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 3,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = ((sheetData.manualDiameters[die]+(sheetData.manualDiameters[die]*pressureDieValuesDouble[die+1])/100)/25.4).toStringAsFixed(sheetData.decimals);
            break;
          case "imperial":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 3,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die]+(sheetData.manualDiameters[die]*(pressureDieValuesDouble[die+1])/100)).toStringAsFixed(sheetData.decimals);
            break;
        }

        // Column 4: Size (mm)
        switch (sheetData.selectedSystem) {
          case "metric":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 4,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die]+(sheetData.manualDiameters[die]*pressureDieValuesDouble[die+1]/100)).toStringAsFixed(sheetData.decimals);
            break;
          case "imperial":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 4,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = ((sheetData.manualDiameters[die]+(sheetData.manualDiameters[die]*pressureDieValuesDouble[die+1])/100)*25.4).toStringAsFixed(sheetData.decimals);
            break;
        }

        // Column 5: Quantity
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow))
            .value = "";

        // Column 6: Insert Type   
        switch (selectedDieTypes[die]) {
          case "TR4D":
          case "TR4":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "PN5";
            break;
          case "TR6":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "PN8";
            break;
          case "TR8":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "PN9";
            break;
          case "TR9":
          case "T30":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "PN10";
            break;
          case "TR10":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "PN11";
            break;
          case "TR11":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = "*";
            break;
        }
        
        // Column 7: Short Version
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: currentRow))
            .value = "";

        currentRow++;
      }
    currentRow++;
    }

    // Convertir List<int> a Uint8List
    final Uint8List bytes = Uint8List.fromList(excel.encode()!);

    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd_HH-mm').format(now);
    final fileName = 'pd_draft_pressure_xlsx_$formattedDate';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: "xlsx",
      mimeType: MimeType.microsoftExcel,
    );
  }

  // Exportar XLSX
  Future<void> exportSheetsToXLSX(List<SheetData> sheets, selectedDieTypes) async {
    var excel = xls.Excel.createExcel();
    xls.Sheet sheet = excel['Sheet1'];

    int currentRow = 0; 

    for (int i = 0; i < sheets.length; i++) {
      final sheetData = sheets[i];

      final headers = [
        "Customer Name",
        "Customer Preferred Units",
        "Sourced from Mexico",
        "Units",
        "Insert Type",
        "Quantity",
        "Diameter (mm)",
        "Diameter (in)",
        "Angle",
        "Material",
        "Bearing Length",
        "Casing",
        "Finish",
        "Diameter Tolerance (in)",
        "Diameter Tolerance (mm)"
      ];

      for (int col = 0; col < headers.length; col++) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: currentRow))
            .value = headers[col];
      }
      currentRow++;

      for (int die = 0; die < sheetData.numberOfDies; die++) {
        
        // Column 0: Customer Name
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow))
            .value = sheetData.clientName;

        // Column 1: Customer Preferred Unit
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: currentRow))
            .value = sheetData.selectedSystem;
        
        // Column 2: Sourced From Mexico
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow))
            .value = "";

        // Column 3: Units
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow))
            .value = sheetData.selectedSystem;

        // Column 4: Insert Type
        sheet
            .cell(
            xls.CellIndex.indexByColumnRow(
                    columnIndex: 4,         
                    rowIndex: currentRow,
                  ),
                )
            .value = selectedDieTypes[die];

        // Column 5: Quantity
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow))
            .value = "";

        // Column 6: Diameter (mm)
        switch (sheetData.selectedSystem) {
          case "metric":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die+1]).toStringAsFixed(sheetData.decimals);
            break;
          case "imperial":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 6,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die+1]* 25.4).toStringAsFixed(sheetData.decimals);
            break;
        }

        // Column 7: Diameter (in)
        switch (sheetData.selectedSystem) {
          case "metric":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 7,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die+1]/ 25.4).toStringAsFixed(sheetData.decimals);
            break;
          case "imperial":
            sheet
              .cell(
              xls.CellIndex.indexByColumnRow(
                      columnIndex: 7,         
                      rowIndex: currentRow,
                    ),
                  )
              .value = (sheetData.manualDiameters[die+1]).toStringAsFixed(sheetData.decimals);
            break;
        }

        // Column 8: Angle
        sheet
            .cell(
            xls.CellIndex.indexByColumnRow(
                    columnIndex: 8,         
                    rowIndex: currentRow,
                  ),
                )
            .value = sheetData.manualAngles[die];

        // Column 9: Material
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: currentRow))
            .value = sheetData.selectedMaterial;  

        // Column 10: Bearing Length    
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: currentRow))
            .value = ""; 

        // Column 11: Casing  
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: currentRow))
            .value = "";

        // Column 12: Finish 
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: currentRow))
            .value = "";

        // Column 13: Diameter Tolerance (in)
        switch (sheetData.selectedSystem) {
          case "metric":
            switch(selectedDieTypes[die]){
              case "TR4D":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]/ 25.4) > 0.0250){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }
                    break;
                }
                break;
              case "TR4":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]/ 25.4) > 0.08){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    }
                    break;

                  case 12:
                    if((sheetData.manualDiameters[die+1]/ 25.4) < 0.08){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    } else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;

                  case 16:
                    if((sheetData.manualDiameters[die+1]/ 25.4) < 0.1180){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;
                }
                break;
              case "TR6":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 12:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 16:
                    if((sheetData.manualDiameters[die+1]/ 25.4) < 0.1850){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;
                }
                break;
              case "TR8":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR9":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR10":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "T30":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR11":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
            }
          case "imperial":
            switch(selectedDieTypes[die]){
              case "TR4D":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]) > 0.0250){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }
                    break;
                }
                break;
              case "TR4":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]) > 0.08){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    }
                    break;

                  case 12:
                    if((sheetData.manualDiameters[die+1]) < 0.08){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0005";
                    } else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;

                  case 16:
                    if((sheetData.manualDiameters[die+1]) < 0.1180){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;
                }
                break;
              case "TR6":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 12:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 16:
                    if((sheetData.manualDiameters[die+1]) < 0.1850){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                        .value = "0.0010";
                    }
                    break;
                }
                break;
              case "TR8":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR9":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR10":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "T30":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR11":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: currentRow))
                  .value = "*";
                break;
          }
            break;
        } 

        // Column 14: Diameter Tolerance (mm)
        switch (sheetData.selectedSystem) {
          case "metric":
            switch(selectedDieTypes[die]){
              case "TR4D":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if(sheetData.manualDiameters[die+1] > 0.64){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }
                    break;
                }
                break;
              case "TR4":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if(sheetData.manualDiameters[die+1] > 1.99){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.02";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }
                    break;

                  case 12:
                    if(sheetData.manualDiameters[die+1] < 2.00){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }else if (sheetData.manualDiameters[die+1] < 4.99){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.02";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;

                  case 16:
                    if(sheetData.manualDiameters[die+1] < 3.00){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;
                }
                break;
              case "TR6":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 12:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 16:
                    if(sheetData.manualDiameters[die+1] < 5.50){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;
                }
                break;
              case "TR8":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR9":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR10":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "T30":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR11":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
            }
            break;
          case "imperial":
            switch(selectedDieTypes[die]){
              case "TR4D":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]* 25.4) > 0.64){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }
                    break;
                }
                break;
              case "TR4":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    if((sheetData.manualDiameters[die+1]* 25.4) > 1.99){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.02";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }
                    break;

                  case 12:
                    if((sheetData.manualDiameters[die+1]* 25.4) < 2.00){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.01";
                    }else if ((sheetData.manualDiameters[die+1]* 25.4) < 4.99){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.02";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;

                  case 16:
                    if((sheetData.manualDiameters[die+1]* 25.4) < 3.00){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;
                }
                break;
              case "TR6":
                switch(sheetData.manualAngles[die]){
                  case 9:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 12:
                    sheet
                      .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                      .value = "0.05";
                    break;
                  case 16:
                    if((sheetData.manualDiameters[die+1]* 25.4) < 5.50){
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "*";
                    }else{
                      sheet
                        .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                        .value = "0.05";
                    }
                    break;
                }
                break;
              case "TR8":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR9":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR10":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "T30":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
              case "TR11":
                sheet
                  .cell(xls.CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: currentRow))
                  .value = "*";
                break;
            }
            break;
        }

        currentRow++;
      }

      // Línea vacía entre Sheets
      currentRow++;
    }

    // Convertir List<int> a Uint8List
    final Uint8List bytes = Uint8List.fromList(excel.encode()!);

    final now = DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd_HH-mm').format(now);
    final fileName = 'pd_draft_insert_xlsx_$formattedDate';

    await FileSaver.instance.saveFile(
      name: fileName,
      bytes: bytes,
      ext: "xlsx",
      mimeType: MimeType.microsoftExcel,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('XSLX exported succesfully, check Downloads'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  // Importar CSV
  Future<List<SheetData>> importSheetsFromCustomCSV() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result == null || result.files.isEmpty) return [];

    final file = result.files.single;

    String content;

    if (kIsWeb) {
      final fileBytes = file.bytes;
      if (fileBytes == null) return [];
      content = utf8.decode(fileBytes);
    } else {
      final path = file.path;
      if (path == null) return [];
      final fileOnDisk = io.File(path);
      content = await fileOnDisk.readAsString();
    }

    final lines = LineSplitter().convert(content);

    List<SheetData> importedSheets = [];
    Map<String, String> currentSheetMap = {};

    for (final line in lines) {
      if (line.trim().isEmpty) {
        if (currentSheetMap.isNotEmpty) {
          importedSheets.add(sheetFromMap(currentSheetMap));
          currentSheetMap = {};
        }
      } else if (line.contains(',')) {
        final split = line.split(',');
        final key = split[0].trim();
        final value = split.sublist(1).join(',').trim();
        currentSheetMap[key] = value;
      } else if (line.startsWith('Sheet')) {
        // Guardamos Sheet N para fallback
        currentSheetMap['Sheet N'] = line.trim();
      }
    }


    if (currentSheetMap.isNotEmpty) {
      importedSheets.add(sheetFromMap(currentSheetMap));
    }

    return importedSheets;
  }

  // Funcion que acomoda todas las variables en su debida posicion
  SheetData sheetFromMap(Map<String, dynamic> map) {
    return SheetData(
      // Si hay nombre asignado, lo usamos; si no, dejamos vacío y se generará Sheet N al mostrar
      name: map['Sheet Name'] ?? '',
      clientName: map['Client Name'] ?? '',
      productName: map['Product Name'] ?? '',
      description: map['Description'] ?? '',
      date: map['Date'] ?? '',
      advisor: map['Sales Rep'] ?? '',

      numberOfDies: int.tryParse('${map['Number of Dies'] ?? '0'}') ?? 0,
      initialDiameter: '${map['Initial Diameter'] ?? '0'}',
      finalDiameter: '${map['Final Diameter'] ?? '0'}',
      decimals: int.tryParse('${map['Decimals'] ?? '0'}') ?? 0,
      finalSpeed: double.tryParse('${map['Final Speed'] ?? '0'}') ?? 0,

      selectedMaterial: map['Selected Material']?.replaceAll('"', '') ?? '',
      selectedCarbon: map['Selected Carbon'] ?? '',

      temperatureLimit: double.tryParse('${map['Temperature Limit'] ?? '0'}') ?? 0,
      draftingType: map['Drafting Type'] ?? '',
      

      finalReductionPercentage:
          double.tryParse('${map['Final Reduction Percentage'] ?? '0'}') ?? 0,
      finalReductionPercentageSkinPass:
          double.tryParse('${map['Final Reduction Percentage Skim Pass'] ?? '0'}') ?? 0,
      maximumReductionPercentage: 
          double.tryParse('${map['Maximum Reduction Percentage'] ?? '0'}') ?? 0,

      firstPressure: int.tryParse('${map['First Pressure'] ?? '0'}') ?? 0,
      middlePressure: int.tryParse('${map['Middle Pressure'] ?? '0'}') ?? 0,
      lastPressure: int.tryParse('${map['Last Pressure'] ?? '0'}') ?? 0,

      tensileMin: double.tryParse('${map['Tensile Minimum'] ?? '0'}') ?? 0,
      tensileMax: double.tryParse('${map['Tensile Maximum'] ?? '0'}') ?? 0,

      pressureDieValues: (map['Pressure Die Values'] ?? '').split('|'),

      selectedAngleMode: map['Selected Angle Mode'] ?? '',
      selectedAngle: int.tryParse('${map['Selected Angle'] ?? '0'}') ?? 0,

      individualAngles: (map['Individual Angles'] ?? '')
          .split('|')
          .map((e) => int.tryParse(e) ?? 0)
          .toList()
          .cast<int>(),

      manualDiameters: (map['Manual Diameters'] ?? '')
          .split('|')
          .map((e) => double.tryParse(e) ?? 0)
          .toList()
          .cast<double>(),

      manualAngles: (map['Manual Angles'] ?? '')
          .split('|')
          .map((e) => int.tryParse(e) ?? 0)
          .toList()
          .cast<int>(),

      usingStockDies: '${map['Using Stock Dies'] ?? 'false'}'.toLowerCase() == 'true',
      selectedSystem: map['Selected System'] ?? '',
      isSkinPass: '${map['Is Skim Pass'] ?? 'false'}'.toLowerCase() == 'true',
      isManual: '${map['Is Manual Diameters'] ?? 'false'}'.toLowerCase() == 'true',
      isManualAngle: '${map['Is Manual Angles'] ?? 'false'}'.toLowerCase() == 'true',
      semiActive: '${map['Active Semi Taper'] ?? 'false'}'.toLowerCase() == 'true',
      isCustomDelta: '${map['Is Custom Delta'] ?? 'false'}'.toLowerCase() == 'true',
      customMinDelta: double.tryParse('${map['Custom Min Delta'] ?? '0'}') ?? 0,
      customMaxDelta: double.tryParse('${map['Custom Max Delta'] ?? '0'}') ?? 0,

      selectedSpeedUnit: map['Selected Speed Unit'] ?? '',
      selectedOutputUnit: map['Selected Output Unit'] ?? '',
    );
  }

  // Funny
  void magicDoohickey({required double paso, required bool esIncremento, }) async {
      // Esto era un arreglo un bug que habia en donde se dba el valor incorrecto al hacer full taper
      const int maxIntentos = 10;
      int intentos = 0;

      double valorOriginal = finalReductionPercentage;
      double nuevaReduccion = valorOriginal;
      Map<String, dynamic>? resultado;

      setState(() {
        esperandoRespuesta = true;
        taperPercentageController.text = '';
      });

      while (intentos < maxIntentos) {
        finalReductionPercentage += paso;

        resultado = await enviarDatosAlBackend();

        if (resultado != null && resultado.containsKey('reductions')) {
          final List reductions = resultado['reductions'];

          if (reductions.isNotEmpty) {
            nuevaReduccion = (reductions.last['value'] as num).toDouble();

            bool cambioValido = esIncremento
                ? nuevaReduccion > valorOriginal
                : nuevaReduccion < valorOriginal;

            if (cambioValido) {
              break; // Salimos del loop si el cambio va en la dirección correcta
            }
          }
        }

        intentos++;
      }

      // Si después de intentar varias veces no hubo cambio válido, restauramos
      if (esIncremento && nuevaReduccion <= valorOriginal ||
          !esIncremento && nuevaReduccion >= valorOriginal) {
        finalReductionPercentage = valorOriginal;
        nuevaReduccion = valorOriginal;
      }

      setState(() {
        taperPercentageController.text = nuevaReduccion.toStringAsFixed(1);
        finalReductionPercentage = nuevaReduccion;
        ultimoValorReduccion = nuevaReduccion;
        esperandoRespuesta = false;
      });
    }

  // Funcion que limita la vista de porcentaje de carbones
  void actualizarCarbonOptions() {
    setState(() {
      // Obtenemos el índice del material seleccionado
      final int materialIndex = materialOptions.indexOf(selectedMaterial);

      switch (materialIndex) {
        // Si es 0, 1 o 2 → mostrar >= 0.40%
        case 0:
        case 1:
        case 2:
          filteredCarbonOptions = carbonOptions.where((c) {
            double valor = double.tryParse(c.replaceAll('%', '')) ?? 0;
            return valor >= 0.40;
          }).toList();
          break;

        // Si es 3 o 4 → mostrar <= 0.35%
        case 3:
        case 4:
          filteredCarbonOptions = carbonOptions.where((c) {
            double valor = double.tryParse(c.replaceAll('%', '')) ?? 0;
            return valor <= 0.35;
          }).toList();
          break;

        // Si es 5, 6 o 7 → mostrar todo
        case 5:
        case 6:
        case 7:
          filteredCarbonOptions = List.from(carbonOptions);
          break;

        // Si es cualquier otro valor → mostrar todo
        default:
          filteredCarbonOptions = List.from(carbonOptions);
          break;
      }

      // Si el valor actual no está en la lista filtrada, seleccionar el primero válido
      if (!filteredCarbonOptions.contains(selectedCarbon)) {
        selectedCarbon =
            filteredCarbonOptions.isNotEmpty ? filteredCarbonOptions.first : '';
        enviarDatosAlBackend();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final int tableRows = numberOfDies + 1;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Undo: Ctrl+Z (Windows/Linux), Cmd+Z (Mac)
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): const _UndoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true): const _UndoIntent(),
        // Redo: Ctrl+Y (Windows/Linux), Cmd+Shift+Z (Mac)
        SingleActivator(LogicalKeyboardKey.keyY, control: true): const _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): const _RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
            _performUndo();
            return null;
          }),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
            _performRedo();
            return null;
          }),
        },
        child: WillPopScope(
      onWillPop: () async {
        final salir = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Before you go'),
            content: const Text(
              'If you leave, the draft will reset\nWe suggest exporting first.', style: TextStyle(fontSize: 16,)
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Return',style: TextStyle(fontSize: 16,)),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Exit',style: TextStyle(fontSize: 16,)),
              ),
            ],
          ),
        );

        return salir ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 160, 164, 167),
          centerTitle: true,
          toolbarHeight: 70,
          title: Image.asset(
            'assets/images/titulo5-logo.png',
            height: 60,
            fit: BoxFit.contain,
          ),
          actions: [
            // Botón de Undo
            IconButton(
              icon: const Icon(Icons.undo, color: Colors.white),
              tooltip: 'Undo',
              onPressed: _performUndo,
            ),
            // Botón de Redo
            IconButton(
              icon: const Icon(Icons.redo, color: Colors.white),
              tooltip: 'Redo',
              onPressed: _performRedo,
            ),
            const SizedBox(width: 8),
            // ── Zoom controls ──
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
              tooltip: 'Zoom Out',
              onPressed: _zoomOut,
            ),
            Tooltip(
              message: 'Reset Zoom',
              child: GestureDetector(
                onTap: _zoomReset,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '${(_zoomLevel * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              tooltip: 'Zoom In',
              onPressed: _zoomIn,
            ),
            const SizedBox(width: 8),
            // Cuadro de versión
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            _viewportSize = constraints.biggest;
            final fitScale = min(constraints.maxWidth / _kStageW, constraints.maxHeight / _kStageH);
            final fittedW  = _kStageW * fitScale;
            final fittedH  = _kStageH * fitScale;
            _centeringOffset = Offset(
              (constraints.maxWidth  - fittedW) / 2,
              (constraints.maxHeight - fittedH) / 2,
            );

            final stage = SizedBox(
              width: _kStageW,
              height: _kStageH,
              child: Column(
          children: [
            Container(
              color: Color(0xFFF1F4F8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                      if (errorMessage != null) // Mensaje de errror al momento de hacer los calculos
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            errorMessage!,
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),

                  // ===================== ROW 1 =====================
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Technical Rep
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Technical Rep", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            TextField(
                              controller: advisorController,
                              focusNode: _advisorFocusNode,
                              style: TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 6),

                      // Date
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Date", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

                            SizedBox(
                              height: 28, 
                              child: TextField(
                                controller: dateController,
                                style: TextStyle(fontSize: 17,fontWeight: FontWeight.bold,),
                                decoration: InputDecoration(
                                  filled: true,
                                  prefixIcon: Icon(Icons.calendar_today, size: 14),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide.none),
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.red)),
                                ),
                                readOnly: true,
                                onTap: () => _selectDate(),
                              ),
                            ),

                          ],
                        ),
                      ),

                      SizedBox(width: 6),

                      // Product Name
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Product Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            TextField(
                              controller: productNameController,
                              focusNode: _productNameFocusNode,
                              style: TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 6),

                      // Client Name
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Client Name", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            TextField(
                              controller: clientNameController,
                              focusNode: _clientNameFocusNode,
                              style: TextStyle(fontSize: 15),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 6),

                      // Description
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Description", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            
                            TextField(
                              controller: descriptionController,
                              focusNode: _descriptionFocusNode,
                              style: TextStyle(fontSize: 15),
                              minLines: 1,       
                              maxLines: 5,       
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 6),
                    
                      

                      // Final Speed + Output
                      Expanded(
                        flex: 1,
                        child: Row(
                          children: [
                            // Final Speed
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Speed ($selectedSpeedUnit)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  
                                  TextField(
                                    controller: finalSpeedController,
                                    style: TextStyle(fontSize: 16),
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    onChanged: (_) => updateSpeed(),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(width: 12),

                            // Output
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                            
                                  Text("Output ($selectedOutputUnit)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Color(0xFFe51937)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      totalWeight.toStringAsFixed(decimalsdisplay),
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    ],
                  ),

                  SizedBox(height: 10),

                  // ===================== ROW 2 =====================
                  Wrap(
                    alignment: WrapAlignment.center,  
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: 12, 
                    runSpacing: 6, 
                    children: [
                      // Initial, Final, # of Dies
                      for (var item in [
                        ["Initial Diameter", initialDiameterController, () => validateDiameters()],
                        ["Final Diameter", finalDiameterController, () => validateDiameters()],
                        ["# of Dies", diesController, () => updateDiesCount()],
                      ])
                        SizedBox(
                          width: 130,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${item[0]} ${item[0].toString().contains('Diameter') ? (selectedSystem == 'metric' ? '(mm)' : '(in)') : ''}",
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              TextField(
                                controller: item[1] as TextEditingController,
                                style: TextStyle(fontSize: 17),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                onChanged: (_) {
                                  setState(() {
                                    isManual = false;
                                    isManualAngle = false;
                                    semiActive = false;
                                    diametersModified = List.filled(manualDiameters.length, false);
                                    anglesModified = List.filled(manualAngles.length, false);
                                  });
                                  (item[2] as Function)();
                                },
                              ),
                            ],
                          ),
                        ),

                      // Skin Pass
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Skim Pass", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            DropdownButtonFormField<String>(
                              value: isSkinPass ? 'Yes' : 'No',
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              ),
                              items: ['Yes', 'No']
                                  .map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(fontSize: 16))))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  isSkinPass = value == 'Yes';
                                  if (isSkinPass && skinPassReductionController.text.isEmpty) {
                                    skinPassReductionController.text = '10';
                                    sheets[currentSheetIndex].finalReductionPercentageSkinPass = 10;
                                  }
                                  enviarDatosAlBackend();
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      if (isSkinPass)
                        SizedBox(
                          width: 100,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Reduction (%)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              TextField(
                                controller: skinPassReductionController,
                                style: TextStyle(fontSize: 15),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value);
                                  if (parsed != null && parsed >= 0) {
                                    setState(() {
                                      finalReductionPercentageSkinPass = parsed;
                                      sheets[currentSheetIndex].finalReductionPercentageSkinPass = parsed;
                                    });
                                    enviarDatosAlBackend();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                      // Material
                      SizedBox(
                        width: 240,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Material", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            DropdownButtonFormField<String>(
                              value: selectedMaterial,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              ),
                              onChanged: (value) {
                                setState(() => selectedMaterial = value!);
                                actualizarCarbonOptions();
                                enviarDatosAlBackend();
                              },
                              items: materialOptions
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(fontSize: 16))))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),

                      if (materialOptions.indexOf(selectedMaterial) == 7) ...[
                        // First Tensile
                        SizedBox(
                          width: 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("First Tensile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              TextField(
                                controller: minTensileController,
                                style: TextStyle(fontSize: 15),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value);
                                  if (parsed != null) {
                                    setState(() => tensileMin = parsed);
                                    enviarDatosAlBackend();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // Last Tensile
                        SizedBox(
                          width: 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Last Tensile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              TextField(
                                controller: maxTensileController,
                                style: TextStyle(fontSize: 15),
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.all(8),
                                ),
                                onChanged: (value) {
                                  final parsed = double.tryParse(value);
                                  if (parsed != null) {
                                    setState(() => tensileMax = parsed);
                                    enviarDatosAlBackend();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Carbon
                      SizedBox(
                        width: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Carbon (%)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            DropdownButtonFormField<String>(
                              value: filteredCarbonOptions.contains(selectedCarbon) ? selectedCarbon : null,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              ),
                              onChanged: (value) {
                                setState(() => selectedCarbon = value!);
                                enviarDatosAlBackend();
                              },
                              items: filteredCarbonOptions
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 16))))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),

                      // Decimals
                      SizedBox(
                        width: 60,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Decimals", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            TextField(
                              controller: decimalsController,
                              style: TextStyle(fontSize: 16),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[2-4]$'))],
                              onChanged: (_) => updateDecimals(),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.all(8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: Row(
              children: [
                // Tabla + gráfica
                Expanded(
                  flex: 40,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    color: Colors.grey.shade100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Data Table", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: tableRows+1,
                            itemBuilder: (context, index) {
                              if (index == tableRows) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(width: 8),

                                        // Botón de mostrar tabla de Part Numbers, boton booleano
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              showExtraTable = !showExtraTable;
                                            });
                                          },
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: showExtraTable ? const Color(0xFFe51937) : Colors.grey.shade100,
                                            foregroundColor: showExtraTable ? Colors.white : Colors.black,
                                            side: BorderSide(color: const Color(0xFF58585a)),
                                          ),
                                          child: Text("Part Numbers", style: TextStyle(fontSize: 16)),
                                          
                                        ),

                                        SizedBox(width: 8),

                                        // Botón de mostrar tabla de Pressure Numbers, boton booleano
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              showPressureTable = !showPressureTable;
                                            });
                                          },
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: showPressureTable ? const Color(0xFFe51937) : Colors.grey.shade100,
                                            foregroundColor: showPressureTable ?  Colors.white : Colors.black,
                                            side: BorderSide(color: const Color(0xFF58585a)),
                                          ),
                                          child: Text("Pressure Table", style: TextStyle(fontSize: 16)),
                                        ),

                                        SizedBox(width: 8),

                                        // Botón Paramount Standard Dies
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              decimalsdisplay = 2;
                                              decimalsController.text = "2";
                                              usingStockDies = true;
                                            });
                                            updateDecimals();
                                            enviarDatosAlBackend();
                                          },
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: usingStockDies ? const Color(0xFFe51937) : Colors.grey.shade100,
                                            foregroundColor: usingStockDies ? Colors.white : Colors.black,
                                            side: const BorderSide(color: Color(0xFF58585a)),
                                          ),
                                          child: const Text("Paramount Standard Dies", style: TextStyle(fontSize: 16)),
                                        ),

                                        SizedBox(width: 8),

                                        // Botón Regular Dies
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              usingStockDies = false;
                                            });
                                            enviarDatosAlBackend();
                                          },
                                          style: OutlinedButton.styleFrom(
                                            backgroundColor: !usingStockDies ? const Color(0xFFe51937) : Colors.grey.shade100,
                                            foregroundColor: !usingStockDies ? Colors.white : Colors.black,
                                            side: const BorderSide(color: Color(0xFF58585a)),
                                          ),
                                          child: const Text("Regular Dies", style: TextStyle(fontSize: 16)),
                                        ),
                                      ],
                                    ),
                                    
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (showExtraTable)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 500), 
                                            child: Padding(
                                              padding: const EdgeInsets.only(top: 24, bottom: 12),
                                              child: Table(
                                                border: TableBorder.all(width: 0.5),
                                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                                columnWidths: const {
                                                  0: IntrinsicColumnWidth(), // # of Die
                                                  1: IntrinsicColumnWidth(), // Nuevo Dropdown
                                                  2: FlexColumnWidth(),      // Part Number
                                                  3: IntrinsicColumnWidth(), // Action
                                                },
                                                children: [
                                                  // Encabezado de la tabla
                                                  const TableRow(
                                                    children: [
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "# of Die",
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "Die Type", 
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "Part Number",
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "Action",
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  // Filas dinámicas
                                                  for (int i = 1; i < numberOfDies + 1; i++)
                                                    TableRow(
                                                      children: [
                                                        // Columna "# of Die"
                                                        Padding(
                                                          padding: const EdgeInsets.all(6.0),
                                                          child: Text(
                                                            i.toString(),
                                                            style: const TextStyle(fontSize: 16),
                                                          ),
                                                        ),

                                                        // Dropdown tipo de dado (String)
                                                        Padding(
                                                          padding: const EdgeInsets.all(4.0),
                                                          child: Builder(
                                                            builder: (context) {
                                                              if (i - 1 >= diameters.length) {
                                                                return DropdownButton<String>(
                                                                  value: "TR",
                                                                  isDense: true,
                                                                  underline: const SizedBox(),
                                                                  items: const [
                                                                    DropdownMenuItem(
                                                                      value: "TR",
                                                                      child: Text("TR", style: TextStyle(fontSize: 12)),
                                                                    ),
                                                                  ],
                                                                  onChanged: null,
                                                                );
                                                              }

                                                              final double diametro = diameters[i];

                                                              List<String> opciones;

                                                              // ─── RANGOS SEGÚN SISTEMA ───
                                                              if (selectedSystem == 'metric') {
                                                                if (diametro >= limInfTR4D && diametro < limInfTR4) {
                                                                  opciones = ["TR4D"];
                                                                } else if (diametro >= limInfTR4 && diametro < limSupTR4D) {
                                                                  opciones = ["TR4D", "TR4"];
                                                                } else if (diametro >= limSupTR4D && diametro < limInfTR6) {
                                                                  opciones = ["TR4"];
                                                                } else if (diametro >= limInfTR6 && diametro < limInfTR8) {
                                                                  opciones = ["TR4", "TR6"];
                                                                } else if (diametro >= limInfTR8 && diametro < 4.9) {
                                                                  opciones = ["TR4", "TR6", "TR8"];
                                                                } else if (diametro >= 4.9 && diametro < limSupTR4) {
                                                                  opciones = ["TR4", "TR6", "TR8", "T30"];
                                                                } else if (diametro >= limSupTR4 && diametro < limSupTR6) {
                                                                  opciones = ["TR6", "TR8", "T30"];
                                                                } else if (diametro >= limSupTR6 && diametro < 12.6) {
                                                                  opciones = ["TR8", "T30"];
                                                                } else if (diametro >= 12.6 && diametro < limSupTR8) {
                                                                  opciones = ["TR8", "T30", "TR9"];
                                                                } else if (diametro >= limSupTR8 && diametro < 16.5) {
                                                                  opciones = ["T30", "TR9"];
                                                                } else if (diametro >= 16.5 && diametro < 22.5) {
                                                                  opciones = ["TR10"];
                                                                } else {
                                                                  opciones = ["TR11"];
                                                                }
                                                              } else {
                                                                if (diametro >= limInfTR4D && diametro < limInfTR4) {
                                                                  opciones = ["TR4D"];
                                                                } else if (diametro >= limInfTR4 && diametro < limSupTR4D) {
                                                                  opciones = ["TR4D", "TR4"];
                                                                } else if (diametro >= limSupTR4D && diametro < limInfTR6) {
                                                                  opciones = ["TR4"];
                                                                } else if (diametro >= limInfTR6 && diametro < limInfTR8) {
                                                                  opciones = ["TR4", "TR6"];
                                                                } else if (diametro >= limInfTR8 && diametro < 0.1929) {
                                                                  opciones = ["TR4", "TR6", "TR8"];
                                                                } else if (diametro >= 0.1929 && diametro < limSupTR4) {
                                                                  opciones = ["TR4", "TR6", "TR8", "T30"];
                                                                } else if (diametro >= limSupTR4 && diametro < limSupTR6) {
                                                                  opciones = ["TR6", "TR8", "T30"];
                                                                } else if (diametro >= limSupTR6 && diametro < 0.4961) {
                                                                  opciones = ["TR8", "T30"];
                                                                } else if (diametro >= 0.4961 && diametro < limSupTR8) {
                                                                  opciones = ["TR8", "T30", "TR9"];
                                                                } else if (diametro >= limSupTR8 && diametro < 0.6496) {
                                                                  opciones = ["T30", "TR9"];
                                                                } else if (diametro >= 0.6496 && diametro < 0.8858) {
                                                                  opciones = ["TR10"];
                                                                } else {
                                                                  opciones = ["TR11"];
                                                                }
                                                              }

                                                              String value = selectedDieTypes[i - 1] ?? opciones.first;
                                                              if (!opciones.contains(value)) {
                                                                value = opciones.first;
                                                                selectedDieTypes[i - 1] = value;
                                                              }

                                                              return DropdownButton<String>(
                                                                value: value,
                                                                isDense: true,
                                                                underline: const SizedBox(),
                                                                items: opciones
                                                                    .map((val) => DropdownMenuItem<String>(
                                                                          value: val,
                                                                          child: Text(val, style: const TextStyle(fontSize: 16)),
                                                                        ))
                                                                    .toList(),
                                                                onChanged: (newValue) {
                                                                  setState(() {
                                                                    selectedDieTypes[i - 1] = newValue!;
                                                                  });
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),

                                                        // Columna "Part Number" 
                                                        Padding(
                                                          padding: const EdgeInsets.all(6.0),
                                                          child: Text(
                                                            i < diameters.length && i < angles.length
                                                                ? generatePartNumber(
                                                                    angles[i],
                                                                    diameters[i],
                                                                    selectedSystem,
                                                                    selectedDieTypes[i - 1] ?? "TR4",
                                                                  )
                                                                : "-",
                                                            style: const TextStyle(fontSize: 16),
                                                          ),
                                                        ),

                                                        // Columna Action
                                                        Padding(
                                                          padding: const EdgeInsets.all(4.0),
                                                          child: SizedBox(
                                                            width: 100,
                                                            child: ElevatedButton(
                                                              onPressed: () {
                                                                if (i < diameters.length && i - 1 >= 0) {
                                                                  Navigator.push(
                                                                    context,
                                                                    MaterialPageRoute(
                                                                      builder: (_) => DieDesignerScreen(
                                                                        reductionAngle: angles[i],
                                                                        alturaInicial: selectedSystem == 'metric' 
                                                                            ? diameters[i - 1] 
                                                                            : diameters[i - 1] * 25.4,
                                                                        barraLength: selectedSystem == 'metric' 
                                                                            ? diameters[i] 
                                                                            : diameters[i] * 25.4,
                                                                        selectedSystem: selectedSystem,
                                                                        customDeltaRange: [minDelta,maxDelta],
                                                                      ),
                                                                    ),
                                                                  );
                                                                } else {
                                                                  print("Invalid Index: i=$i, diameters.length=${diameters.length}");
                                                                }
                                                              },
                                                              style: ElevatedButton.styleFrom(
                                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                                textStyle: const TextStyle(fontSize: 16),
                                                                minimumSize: Size.zero,
                                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                              ),
                                                              child: const Text(
                                                                "Drawing",
                                                                textAlign: TextAlign.center,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),

                                        SizedBox(width: 24),

                                        if (showPressureTable)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 350), 
                                            child: Padding(
                                              padding: const EdgeInsets.only(top: 24, bottom: 15),
                                              child: Table(
                                                border: TableBorder.all(width: 0.5),
                                                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                                columnWidths: const {
                                                  0: IntrinsicColumnWidth(), // # of Die
                                                  1: IntrinsicColumnWidth(), // Nuevo Dropdown
                                                  2: FlexColumnWidth(),      // Part Number
                                                },
                                                children: [
                                                  // Encabezado de la tabla
                                                  const TableRow(
                                                    children: [
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "# of Die",
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "Die Type", // Nuevo encabezado
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                      Padding(
                                                        padding: EdgeInsets.all(6.0),
                                                        child: Text(
                                                          "Pressure Number",
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                        ),
                                                      ),
                                                    ],
                                                  ),

                                                  // Filas dinámicas
                                                  for (int i = 1; i < numberOfDies + 1; i++)
                                                    TableRow(
                                                      children: [
                                                        // Columna "# of Die"
                                                        Padding(
                                                          padding: const EdgeInsets.all(6.0),
                                                          child: Text(
                                                            i.toString(),
                                                            style: const TextStyle(fontSize: 16),
                                                          ),
                                                        ),

                                                        // Nueva columna: Dropdown tipo de dado
                                                        Padding(
                                                          padding: const EdgeInsets.all(6.0),
                                                          child: Text(
                                                            (() {
                                                              if (i - 1 < selectedDieTypes.length) {
                                                                final dieType = selectedDieTypes[i - 1];
                                                                switch (dieType) {
                                                                  case "TR4D":
                                                                  case "TR4":
                                                                    return "PN5";
                                                                  case "TR6":
                                                                    return "PN8";
                                                                  case "TR8":
                                                                    return "PN9";
                                                                  case "TR9":
                                                                  case "T30":
                                                                    return "PN10";
                                                                  case "TR10":
                                                                    return "PN11";
                                                                  default:
                                                                    return "?";
                                                                }
                                                              } else {
                                                                return "?";
                                                              }
                                                            })(),
                                                            style: const TextStyle(fontSize: 16),
                                                          ),
                                                        ),

                                                        // Columna "Part Number" 
                                                        Padding(
                                                          padding: const EdgeInsets.all(6.0),
                                                          child: Text(
                                                            i < diameters.length && i < angles.length
                                                                ? (() {
                                                                    double baseDiameter = diameters[i - 1];
                                                                    double adjustedDiameter = baseDiameter;

                                                                    // Aplica el porcentaje de presión si existe
                                                                    if (i < pressureDieValues.length) {
                                                                      final pressureValue = double.tryParse(pressureDieValues[i] ?? "");
                                                                      if (pressureValue != null) {
                                                                        adjustedDiameter = baseDiameter * (1 + pressureValue / 100);
                                                                      }
                                                                    }

                                                                    // Genera el número de parte con el diámetro ajustado
                                                                    return generatePressureNumber(
                                                                      angles[i],
                                                                      adjustedDiameter,
                                                                      selectedSystem,
                                                                      (() {
                                                                        if (i - 1 < selectedDieTypes.length) {
                                                                          final dieType = selectedDieTypes[i - 1];
                                                                          switch (dieType) {
                                                                            case "TR4D":
                                                                            case "TR4":
                                                                              return "PN5";
                                                                            case "TR6":
                                                                              return "PN8";
                                                                            case "TR8":
                                                                              return "PN9";
                                                                            case "TR9":
                                                                            case "T30":
                                                                              return "PN10";
                                                                            case "TR10":
                                                                              return "PN11";
                                                                            default:
                                                                              return "?";
                                                                          }
                                                                        } else {
                                                                          return "?";
                                                                        }
                                                                      })(),
                                                                    );
                                                                  })()
                                                                : "-",
                                                            style: const TextStyle(fontSize: 15),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        )
                                      ] 
                                    )    
                                  ],
                                );
                              }
                              final value = chartType == 0
                                ? (index < temperatures.length ? temperatures[index] : 0.0)
                                : chartType == 1
                                    ? (index < deltas.length ? deltas[index] : 0.0)
                                    : (index < reductions.length ? reductions[index] : 0.0);
                              final maxValue = chartType == 0
                                ? 220.0        // Temperatura
                                : chartType == 1
                                    ? 4.0     // Delta
                                    : 130.0;
                              final barMaxWidth = chartType == 0
                                ? (selectedSystem == 'metric' ? 100000/maxTemp : 100000/maxTemp ) // Temperatura
                                : chartType == 1
                                    ? 1700/maxDelta // Delta
                                    : 60000/maxReduction; // Reducción u otro tipo
                              final greenWidth = value <= temperatureLimit
                                  ? value / maxValue * barMaxWidth
                                  : temperatureLimit / maxValue * barMaxWidth;
                              final redWidth = value > temperatureLimit
                                  ? (value - temperatureLimit) / maxValue * barMaxWidth
                                  : 0.0;

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: Table(
                                      border: TableBorder.all(color: Colors.grey),
                                      columnWidths: {
                                        0: FixedColumnWidth(10),
                                        1: FixedColumnWidth(25),
                                        2: FixedColumnWidth(25),
                                        3: FixedColumnWidth(15),
                                        4: FixedColumnWidth(15),
                                        5: FixedColumnWidth(30),
                                        6: FixedColumnWidth(30),
                                        7: FixedColumnWidth(30),
                                        8: FixedColumnWidth(35),
                                      },
                                      children: [
                                        if (index == 0)
                                          TableRow(
                                            decoration: BoxDecoration(color: Colors.grey.shade300),
                                            children: [
                                              for (var header in selectedSystem == 'metric'
                                                  ? ['#', 'Diameter (mm)', 'Reduction', 'Delta', 'Angle', 'Tensile Strength (MPa)', 'Temperature (°C)', 'Speed (${selectedSpeedUnit})', 'Pressure Dies (%)      (mm)']
                                                  : ['#', 'Diameter (in)', 'Reduction', 'Delta', 'Angle', 'Tensile Strength (Kpsi)', 'Temperature (°F)', 'Speed (${selectedSpeedUnit})', 'Pressure Dies (%)      (in)'])
                                                Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                                  child: Text(
                                                    header,
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey.shade100),
                                          children: [
                                            for (var cellIndex = 0; cellIndex < 8; cellIndex++)
                                              Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                                child: (() {
                                                  // Columna de índice
                                                  if (cellIndex == 0) {           
                                                    return Text(                        
                                                      index == 0 ? "Incoming" : "$index",
                                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                      textAlign: TextAlign.center,
                                                    );
                                                  }

                                                // Columna de diámetro
                                                if (cellIndex == 1) {
                                                  
                                                  return GestureDetector(
                                                    onDoubleTap: () {
                                                      setState(() {
                                                        editingDiameterIndex = index;
                                                      });
                                                    },
                                                    child: editingDiameterIndex == index
                                                        ? TextField(
                                                            autofocus: true,
                                                            controller: TextEditingController(
                                                              text: index < manualDiameters.length
                                                                  ? manualDiameters[index].toStringAsFixed(decimalsdisplay)
                                                                  : '',
                                                            ),
                                                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                            onSubmitted: (value) {
                                                              final parsed = double.tryParse(value);
                                                              if (parsed != null) {
                                                                bool isValid = true;

                                                                if (index == 0) {
                                                                  if (manualDiameters.length > 1 &&
                                                                      parsed <= manualDiameters[1]) {
                                                                    isValid = false;
                                                                  }
                                                                } else if (index == manualDiameters.length - 1) {
                                                                  if (parsed >= manualDiameters[index - 1]) {
                                                                    isValid = false;
                                                                  }
                                                                } else {
                                                                  if (parsed >= manualDiameters[index - 1] ||
                                                                      parsed <= manualDiameters[index + 1]) {
                                                                    isValid = false;
                                                                  }
                                                                }

                                                                if (isValid) {
                                                                  setState(() {
                                                                    if (index < manualDiameters.length) {
                                                                      manualDiameters[index] = parsed;
                                                                    } else {
                                                                      while (manualDiameters.length <= index) {
                                                                        manualDiameters.add(0);
                                                                      }
                                                                      manualDiameters[index] = parsed;
                                                                    }
                                                                    diametersModified[index] = true;
                                                                    editingDiameterIndex = null;
                                                                  });
                                                                } else {
                                                                  setState(() {
                                                                    editingDiameterIndex = null;
                                                                  });
                                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                                    SnackBar(
                                                                      content: Text('Invalid Value on Die $index.'),
                                                                      backgroundColor: Colors.red,
                                                                    ),
                                                                  );
                                                                }
                                                              } else {
                                                                setState(() {
                                                                  editingDiameterIndex = null;
                                                                });
                                                              }
                                                            },
                                                            onEditingComplete: () {
                                                              setState(() {
                                                                editingDiameterIndex = null;
                                                                isManual = true;
                                                              });
                                                              Future.microtask(() => enviarDatosAlBackend());
                                                            },
                                                          )
                                                        : Container(
                                                            decoration: BoxDecoration(
                                                              color: (index < diametersModified.length &&
                                                                      diametersModified[index])
                                                                  ? Colors.yellow.shade200
                                                                  : null,
                                                              border: usingStockDies
                                                                  ? Border.all(
                                                                      color: index < stock.length && stock[index] == true
                                                                          ? Colors.green
                                                                          : Colors.red,
                                                                      width: 1.5,
                                                                    )
                                                                  : null,
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            padding: EdgeInsets.all(4),
                                                            child: Text(
                                                              index < manualDiameters.length
                                                                ? (() {
                                                                    final value = manualDiameters[index];
                                                                    double roundedValue;

                                                                    switch (selectedSystem) {
                                                                      case 'metric':
                                                                        if (value < 0.65) {
                                                                          roundedValue = redondearCuartoDecimal(value);
                                                                          return roundedValue.toStringAsFixed(4);
                                                                        } else {
                                                                          return value.toStringAsFixed(decimalsdisplay);
                                                                        }
                                                                      case 'imperial':
                                                                      default:
                                                                        
                                                                        if (value <= 0.08) {
                                                                          roundedValue = redondearCuartoDecimal(value);
                                                                          return roundedValue.toStringAsFixed(4);
                                                                        } else {
                                                                          return value.toStringAsFixed(decimalsdisplay);
                                                                        }
                                                                    }
                                                                  })()
                                                                : "-",
                                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ),
                                                    );
                                                  }
                                                  
                                                  // Columna de reducción
                                                  if (cellIndex == 2) {
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: (index < diametersModified.length && diametersModified[index])
                                                          ? Colors.yellow.shade200
                                                          : null,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    padding: EdgeInsets.all(4),
                                                    child: Text(
                                                      index < reductions.length && reductions[index] > 0
                                                          ? "${reductions[index].toStringAsFixed(1)}%"
                                                          : "-",
                                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  );
                                                }

                                                  // Columna de delta
                                                  if (cellIndex == 3) {
                                                    final int materialIndex = materialOptions.indexOf(selectedMaterial);

                                                    // Determinar rango según materialIndex
                                                    minDelta = 0.0;
                                                    maxDelta = 999.0;

                                                    if (isCustomDelta) {
                                                      // Usar valores del usuario si está activo el modo Custom
                                                      minDelta = double.tryParse(minDeltaController.text) ?? 0.0;
                                                      maxDelta = double.tryParse(maxDeltaController.text) ?? 999.0;
                                                    } else {
                                                      // Usar rangos automáticos según material
                                                      if (materialIndex >= 0 && materialIndex <= 2) {
                                                        // High Carbon
                                                        minDelta = 1.20;
                                                        maxDelta = 1.89;
                                                      } else if (materialIndex >= 3 && materialIndex <= 4) {
                                                        // Low Carbon
                                                        minDelta = 1.30;
                                                        maxDelta = 2.25;
                                                      } else if (materialIndex >= 5 && materialIndex <= 6) {
                                                        // Stainless
                                                        minDelta = 1.35;
                                                        maxDelta = 2.25;
                                                      } else if (materialIndex == 7) {
                                                        // Custom Material
                                                        minDelta = 1.20;
                                                        maxDelta = 2.00;
                                                      }
                                                    }

                                                    // Obtener valor de delta actual
                                                    double? deltaValue = index < deltas.length ? deltas[index] : null;
                                                    bool isOutOfRange = false;

                                                    if (deltaValue != null && deltaValue > 0) {
                                                      if (deltaValue < minDelta || deltaValue > maxDelta) {
                                                        isOutOfRange = true;
                                                      }
                                                    }

                                                    return Container(
                                                      decoration: BoxDecoration(
                                                        color: (index < diametersModified.length && diametersModified[index] ||
                                                                index < anglesModified.length && anglesModified[index])
                                                            ? Colors.yellow.shade200
                                                            : null,
                                                        border: isOutOfRange
                                                            ? Border.all(color: Colors.red, width: 1.5) // borde rojo si está fuera del rango
                                                            : null,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      padding: const EdgeInsets.all(4),
                                                      child: Text(
                                                        (deltaValue != null && deltaValue > 0)
                                                            ? "${deltaValue.toStringAsFixed(2)}"
                                                            : "-",
                                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    );
                                                  }

                                                  // Columna de ángulo 
                                                  if (cellIndex == 4) {
                                                  // el índice 0 es el encabezado/sentinel (value 0) — no editable
                                                  if (index == 0) {
                                                    return Container(
                                                      padding: EdgeInsets.all(4),
                                                      child: Text(
                                                        index < angles.length && angles[index] > 0
                                                            ? "${angles[index].toStringAsFixed(0)}"
                                                            : "-",
                                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    );
                                                  }

                                                  final targetIndex = index - 1; // mapeo al array manualAngles

                                                  return GestureDetector(
                                                    onDoubleTap: () {
                                                      setState(() {
                                                        editingAnglesIndex = index;
                                                      });
                                                    },
                                                    child: editingAnglesIndex == index
                                                        ? TextField(
                                                            autofocus: true,
                                                            controller: TextEditingController(
                                                              text: (targetIndex < manualAngles.length)
                                                                  ? manualAngles[targetIndex].toString()
                                                                  : '',
                                                            ),
                                                            keyboardType: TextInputType.number,
                                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                                            textAlign: TextAlign.center,
                                                            onSubmitted: (value) {
                                                              final parsed = int.tryParse(value);
                                                              if (parsed != null && parsed > 0) {
                                                                setState(() {
                                                                  if (targetIndex < manualAngles.length) {
                                                                    manualAngles[targetIndex] = parsed;
                                                                  } else {
                                                                    while (manualAngles.length <= targetIndex) {
                                                                      manualAngles.add(0);
                                                                    }
                                                                    manualAngles[targetIndex] = parsed;
                                                                  }
                                                                  if (index < anglesModified.length) {
                                                                    anglesModified[index] = true;
                                                                  }
                                                                  editingAnglesIndex = null;
                                                                });
                                                              } else {
                                                                setState(() {
                                                                  editingAnglesIndex = null;
                                                                });
                                                                ScaffoldMessenger.of(context).showSnackBar(
                                                                  SnackBar(
                                                                    content: Text('Invalid Angle on Die $index.'),
                                                                    backgroundColor: Colors.red,
                                                                  ),
                                                                );
                                                              }
                                                            },
                                                            onEditingComplete: () {
                                                              setState(() {
                                                                editingAnglesIndex = null;
                                                                isManualAngle = true;
                                                              });
                                                              Future.microtask(() => enviarDatosAlBackend());
                                                            },
                                                          )
                                                        : Container(
                                                            decoration: BoxDecoration(
                                                              color: (index < anglesModified.length && anglesModified[index])
                                                                  ? Colors.yellow.shade200
                                                                  : null,
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            padding: EdgeInsets.all(4),
                                                            child: Text(
                                                              index < angles.length && angles[index] > 0
                                                                  ? "${angles[index].toStringAsFixed(0)}"
                                                                  : "-",
                                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                              textAlign: TextAlign.center,
                                                            ),
                                                          ),
                                                  );
                                                }


                                                  // Columna de tensión
                                                  if (cellIndex == 5) {
                                                     return Container(
                                                      decoration: BoxDecoration(
                                                        color: (index < diametersModified.length && diametersModified[index])
                                                            ? Colors.yellow.shade200
                                                            : null,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      padding: EdgeInsets.all(4),
                                                      child: Text(
                                                        index < tensiles.length && tensiles[index] > 0
                                                          ? tensiles[index].toStringAsFixed(0)
                                                          : "-",
                                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    );
                                                  }

                                                  // Columna de temperatura
                                                  if (cellIndex == 6) {
                                                     return Container(
                                                      decoration: BoxDecoration(
                                                        color: (index < diametersModified.length && diametersModified[index])
                                                            ? Colors.yellow.shade200
                                                            : null,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      padding: EdgeInsets.all(4),
                                                      child: Text(
                                                        index < temperatures.length && temperatures[index] > 0
                                                          ? temperatures[index].toStringAsFixed(0)
                                                          : "-",
                                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    );
                                                  }

                                                  // Columna de velocidad
                                                  return Text(
                                                    index < speeds.length && speeds[index] > 0
                                                        ? speeds[index].toStringAsFixed(1)
                                                        : "-",
                                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                    textAlign: TextAlign.center,
                                                  );
                                                })(),
                                              ),

                                              

                                            // Celda especial: Pressure Dies con operación y color dinámico
                                            Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: (index < diametersModified.length && diametersModified[index])
                                                      ? Colors.yellow.shade200
                                                      : null, // color condicional
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                padding: EdgeInsets.all(4),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    // Valor original
                                                    Text(
                                                      index < pressureDieValues.length
                                                          ? pressureDieValues[index] + "%"
                                                          : "-",
                                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                    ),

                                                    // Resultado del cálculo
                                                    Text(
                                                      (() {
                                                        if (index == 0 ||
                                                            index >= diameters.length ||
                                                            index >= pressureDieValues.length) return "-";

                                                        final v = _pressureDieSizeRounded(index, diameters);
                                                        if (v == null) return "-";

                                                        return v.toStringAsFixed(decimalsdisplay);
                                                      })(),
                                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Expanded(
                                    flex: 4,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (index == 0)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 6.0),
                                            child: Center(
                                              child: Container(
                                                width: 270,
                                                child: Text(
                                                  selectedSystem == 'metric'
                                                    ? chartType == 0
                                                        ? "Temperature (°C)"
                                                        : chartType == 1
                                                            ? "Delta"
                                                            : "Reduction (%)"
                                                    : chartType == 0
                                                        ? "Temperature (°F)"
                                                        : chartType == 1
                                                            ? "Delta"
                                                            : "Reduction (%)",
                                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (index != 0)
                                          Column(
                                            children: [
                                              Container(
                                                height: 12,
                                                margin: EdgeInsets.symmetric(vertical: 6),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: greenWidth,
                                                      color: chartType == 0
                                                          ? Colors.green           // Temperatura
                                                          : chartType == 1
                                                              ? const Color.fromARGB(255, 16, 62, 100)        // Delta
                                                              : const Color.fromARGB(255, 117, 86, 202),     // Reducción
                                                    ),
                                                    Container(
                                                      width: redWidth,
                                                      color: chartType == 0
                                                          ? Colors.red            // Exceso en Temperatura
                                                          : chartType == 1
                                                              ? Colors.lightBlue   // Exceso en Delta
                                                              : Colors.deepOrange, // Exceso en Reducción
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Línea separadora
                                              Divider(
                                                height: 1,
                                                color: Colors.grey.shade400,
                                              ),
                                            ],
                                          ),
                                        if (index == tableRows - 1)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (chartType == 0) ...[
                                                  if (selectedSystem == 'metric')
                                                    Text("Temp. Limit (°C)")
                                                  else
                                                    Text("Temp. Limit (°F)"),
                                                  TextField(
                                                    controller: limitController,
                                                    keyboardType: TextInputType.number,
                                                    decoration: InputDecoration(border: OutlineInputBorder()),
                                                    onChanged: (_) => updateTemperatureLimit(),
                                                  ),
                                                ],
                                                Divider(),
                                                Text("Graph:", style: TextStyle(fontWeight: FontWeight.bold)),
                                                SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                  children: [
                                                    ChoiceChip(
                                                      label: Text("Temperature", style: TextStyle(fontSize: 16,)),
                                                      selected: chartType == 0,
                                                      onSelected: (_) => setState(() => chartType = 0),
                                                    ),
                                                    ChoiceChip(
                                                      label: Text("Delta", style: TextStyle(fontSize: 16,)),
                                                      selected: chartType == 1,
                                                      onSelected: (_) => setState(() => chartType = 1),
                                                    ),
                                                    ChoiceChip(
                                                      label: Text("Reduction", style: TextStyle(fontSize: 16,)),
                                                      selected: chartType == 2,
                                                      onSelected: (_) => setState(() => chartType = 2),
                                                    ),
                                                  ],
                                                )
                                              ],
                                            ),           
                                          ),  
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Botón de Configuración a la izquierda
                            OutlinedButton.icon(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return Dialog(
                                      insetPadding: EdgeInsets.symmetric(horizontal: 100, vertical: 80),
                                      child: Container(
                                        width: 600,
                                        padding: EdgeInsets.all(24),
                                        child: StatefulBuilder(
                                          builder: (context, setState) {
                                            // Asegurar tamaño de lista para "Single"
                                            if (individualAngles.length != tableRows - 1) {
                                              individualAngles = List<int>.filled(tableRows - 1, selectedAngle);
                                            }

                                            return SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Center(
                                                    child: Text(
                                                      "Pressure Dies",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),

                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      Column(
                                                        children: [
                                                          Text("First Die"),
                                                          SizedBox(height: 6),
                                                          SizedBox(
                                                            width: 80,
                                                            child: TextField(
                                                              controller: firstDieController,
                                                              decoration: InputDecoration(
                                                                isDense: true,
                                                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                                                border: OutlineInputBorder(),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Column(
                                                        children: [
                                                          Text("Middle Dies"),
                                                          SizedBox(height: 6),
                                                          SizedBox(
                                                            width: 80,
                                                            child: TextField(
                                                              controller: middleDiesController,
                                                              decoration: InputDecoration(
                                                                isDense: true,
                                                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                                                border: OutlineInputBorder(),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Column(
                                                        children: [
                                                          Text("Last Die"),
                                                          SizedBox(height: 6),
                                                          SizedBox(
                                                            width: 80,
                                                            child: TextField(
                                                              controller: lastDieController,
                                                              decoration: InputDecoration(
                                                                isDense: true,
                                                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                                                border: OutlineInputBorder(),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),

                                                  SizedBox(height: 32),
                                                  Center(
                                                    child: Text(
                                                      "Unit System",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),
                                                  Align(
                                                    alignment: Alignment.center,
                                                    child: Wrap(
                                                      spacing: 10,
                                                      alignment: WrapAlignment.center,
                                                      children: [
                                                        ChoiceChip(
                                                          label: const Text("Metric"),
                                                          selected: selectedSystem == 'metric',
                                                          onSelected: (_) {
                                                            setState(() {
                                                              selectedSystem = 'metric'; 
                                                            });
                                                            _applyMetric();
                                                            loadRanges(selectedSystem); 
                                                          },
                                                        ),
                                                        ChoiceChip(
                                                          label: const Text("Imperial/English"),
                                                          selected: selectedSystem == 'imperial',
                                                          onSelected: (_) {
                                                            setState(() {
                                                              selectedSystem = 'imperial'; 
                                                            });
                                                            _applyImperial();
                                                            loadRanges(selectedSystem); 
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),

                                                  SizedBox(height: 32),
                                                  Center(
                                                    child: Text(
                                                      "Delta Range",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),
                                                  Align(
                                                    alignment: Alignment.center,
                                                    child: Wrap(
                                                      spacing: 10,
                                                      crossAxisAlignment: WrapCrossAlignment.center,
                                                      children: [
                                                        ChoiceChip(
                                                          label: const Text("Custom"),
                                                          selected: isCustomDelta,
                                                          onSelected: (selected) {
                                                            setState(() {
                                                              isCustomDelta = selected;
                                                            });
                                                          },
                                                        ),
                                                        if (isCustomDelta) ...[
                                                          SizedBox(
                                                            width: 100,
                                                            child: TextField(
                                                              controller: minDeltaController,
                                                              decoration: const InputDecoration(
                                                                labelText: "Min Δ",
                                                                border: OutlineInputBorder(),
                                                              ),
                                                              keyboardType: TextInputType.number,
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 100,
                                                            child: TextField(
                                                              controller: maxDeltaController,
                                                              decoration: const InputDecoration(
                                                                labelText: "Max Δ",
                                                                border: OutlineInputBorder(),
                                                              ),
                                                              keyboardType: TextInputType.number,
                                                            ),
                                                          ),
                                                        ] else ...[
                                                          SizedBox(
                                                            width: 100,
                                                            child: TextField(
                                                              enabled: false,
                                                              decoration: const InputDecoration(
                                                                labelText: "Min Δ",
                                                                border: OutlineInputBorder(),
                                                              ),
                                                            ),
                                                          ),
                                                          SizedBox(
                                                            width: 100,
                                                            child: TextField(
                                                              enabled: false,
                                                              decoration: const InputDecoration(
                                                                labelText: "Max Δ",
                                                                border: OutlineInputBorder(),
                                                              ),
                                                            ),
                                                          ),
                                                        ]
                                                      ],
                                                    ),
                                                  ),

                                                  SizedBox(height: 32),

                                                  Center(
                                                    child: Text(
                                                      "Angles",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),
                                                  Align(
                                                    alignment: Alignment.center,
                                                    child: Wrap(
                                                      spacing: 10,
                                                      alignment: WrapAlignment.center,
                                                      children: [
                                                        ChoiceChip(
                                                          label: Text("All the same"),
                                                          selected: selectedAngleMode == 'same',
                                                          onSelected: (_) => setState(() => selectedAngleMode = 'same'),
                                                        ),
                                                        ChoiceChip(
                                                          label: Text("Single"),
                                                          selected: selectedAngleMode == 'single',
                                                          onSelected: (_) => setState(() => selectedAngleMode = 'single'),
                                                        ),
                                                        ChoiceChip(
                                                          label: Text("Automatic"),
                                                          selected: selectedAngleMode == 'auto',
                                                          onSelected: (_) => setState(() => selectedAngleMode = 'auto'),
                                                        ),
                                                        
                                                      ],
                                                    ),
                                                  ),

                                                  if (selectedAngleMode == 'same') ...[
                                                    SizedBox(height: 16),
                                                    Text("Select Angle:", style: TextStyle(fontWeight: FontWeight.bold)),
                                                    SizedBox(height: 8),
                                                    Center(
                                                      child: Wrap(
                                                        spacing: 24,
                                                        children: [9, 12, 16].map((angle) {
                                                          return Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Radio<int>(
                                                                value: angle,
                                                                groupValue: selectedAngle,
                                                                onChanged: (val) => setState(() => selectedAngle = val!),
                                                              ),
                                                              Text("$angle°"),
                                                            ],
                                                          );
                                                        }).toList(),
                                                      ),
                                                    ),
                                                  ],
                                                  if (selectedAngleMode == 'single') ...[
                                                    SizedBox(height: 16),
                                                    Text("Set angle per die:", style: TextStyle(fontWeight: FontWeight.bold)),
                                                    LayoutBuilder(
                                                      builder: (context, constraints) {
                                                        int itemsPerRow = 5;
                                                        double spacing = 16;
                                                        double itemWidth = (constraints.maxWidth - spacing * (itemsPerRow - 1)) / itemsPerRow;

                                                        return Wrap(
                                                          spacing: spacing,
                                                          runSpacing: 12,
                                                          children: List.generate(tableRows - 1, (i) {
                                                            final dieNumber = i + 1;

                                                            if (individualAngles.length != tableRows - 1) {
                                                              individualAngles = List.filled(tableRows - 1, 12);
                                                            }

                                                            return SizedBox(
                                                              width: itemWidth,
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text("Die $dieNumber:"),
                                                                  TextField(
                                                                    keyboardType: TextInputType.number,
                                                                    decoration: InputDecoration(
                                                                      isDense: true,
                                                                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                                                      border: OutlineInputBorder(),
                                                                    ),
                                                                    onChanged: (value) {
                                                                      final regex = RegExp(r"^([6-9]|1[0-9]|2[0-6])$");
                                                                      if (regex.hasMatch(value)) {
                                                                        setState(() => individualAngles[i] = int.parse(value));
                                                                      }
                                                                    },
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                  SizedBox(height: 32),
                                                  Center(
                                                    child: Text(
                                                      "Speed Units",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),
                                                  Align(
                                                    alignment: Alignment.center,
                                                    child: Wrap(
                                                      spacing: 10,
                                                      alignment: WrapAlignment.center,
                                                      children: ['ft/s', 'ft/min', 'm/s', 'm/min'].map((unit) {
                                                        return ChoiceChip(
                                                          label: Text(unit),
                                                          selected: selectedSpeedUnit == unit,
                                                          onSelected: (_) {
                                                            setState(() {
                                                              selectedSpeedUnit = unit;
                                                              sheets[currentSheetIndex].selectedSpeedUnit = unit;
                                                              enviarDatosAlBackend();
                                                            });
                                                          },
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),

                                                  SizedBox(height: 32),
                                                  Center(
                                                    child: Text(
                                                      "Output Units",
                                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                  Divider(thickness: 1, height: 24),
                                                  Align(
                                                    alignment: Alignment.center,
                                                    child: Wrap(
                                                      spacing: 10,
                                                      alignment: WrapAlignment.center,
                                                      children: ['m-ton/h', 'kg/h', 'lb/h', 'us-ton/h', 'lb/min'].map((Ounit) {
                                                        return ChoiceChip(
                                                          label: Text(Ounit),
                                                          selected: selectedOutputUnit == Ounit,
                                                          onSelected: (_) {
                                                            setState(() {
                                                              selectedOutputUnit = Ounit;
                                                              sheets[currentSheetIndex].selectedOutputUnit = Ounit;
                                                              enviarDatosAlBackend();
                                                            });
                                                          },
                                                        );
                                                      }).toList(),
                                                    ),
                                                  ),
                                                  SizedBox(height: 24),
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      OutlinedButton(
                                                        onPressed: () => Navigator.of(context).pop(),
                                                        child: Text("Cancel"),
                                                      ),
                                                      OutlinedButton(
                                                        onPressed: () {
                                                          final firstValue = firstDieController.text;
                                                          final middleValue = middleDiesController.text;
                                                          final lastValue = lastDieController.text;

                                                          setState(() {
                                                            if (pressureDieValues.length != tableRows) {
                                                              pressureDieValues = List.filled(tableRows, "-");
                                                            }

                                                            if (tableRows >= 2) {
                                                              pressureDieValues[1] = firstValue;
                                                              for (int i = 2; i < tableRows - 1; i++) {
                                                                pressureDieValues[i] = middleValue;
                                                              }
                                                              pressureDieValues[tableRows - 1] = lastValue;
                                                            }

                                                            // ANGLE LOGIC
                                                            sheets[currentSheetIndex].selectedAngleMode = selectedAngleMode;

                                                            if (selectedAngleMode == 'same') {
                                                              sheets[currentSheetIndex].selectedAngle = selectedAngle;
                                                              sheets[currentSheetIndex].individualAngles =
                                                                  List<int>.filled(tableRows - 1, selectedAngle);
                                                            } else if (selectedAngleMode == 'single') {
                                                              sheets[currentSheetIndex].individualAngles = List<int>.from(individualAngles);
                                                              if (individualAngles.isNotEmpty) {
                                                                sheets[currentSheetIndex].selectedAngle = individualAngles[0];
                                                              } 
                                                            }
                                                          });

                                                          enviarDatosAlBackend();
                                                          loadRanges(selectedSystem); // Recalcular con nuevos valores
                                                          Navigator.of(context).pop();
                                                        },
                                                        
                                                        child: Text("Apply"),
                                                      ),
                                                    ],
                                                  )
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              icon: const Icon(Icons.settings),
                              label: const Text("Settings"),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.grey.shade100,         // Fondo blanco
                                foregroundColor: const Color.fromARGB(255, 110, 83, 207),         // Texto e ícono negros
                                side: const BorderSide(color: Color(0xFF58585a)), // Borde gris oscuro, opcional
                              ), 
                            ),
                            
                            // Botones de Importar y Exportar 
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: onExportPressed,
                                  icon: Icon(Icons.download),
                                  label: Text("Export CSV"),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,         // Fondo blanco
                                    foregroundColor: const Color.fromARGB(255, 110, 83, 207),         // Texto e ícono negros
                                    side: const BorderSide(color: Color(0xFF58585a)), // Borde gris oscuro, opcional
                                  ), 
                                ),
                                SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: onExportXLSXPressed,
                                  icon: Icon(Icons.download),
                                  label: Text("Export POINT"),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,         // Fondo blanco
                                    foregroundColor: const Color.fromARGB(255, 110, 83, 207),         // Texto e ícono negros
                                    side: const BorderSide(color: Color(0xFF58585a)), // Borde gris oscuro, opcional
                                  ), 
                                ),
                                SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final imported = await importSheetsFromCustomCSV();
                                    if (imported.isNotEmpty) {
                                      setState(() {
                                        sheets = imported;
                                        skinPassReductionController.text = finalReductionPercentageSkinPass.toString();
                                        currentSheetIndex = 0;
                                        
                                      });
                                      
                                      loadSheetData(0);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Imported Succesfully")),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.upload),
                                  label: Text("Import CSV"),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,         // Fondo blanco
                                    foregroundColor: const Color.fromARGB(255, 110, 83, 207),         // Texto e ícono negros
                                    side: const BorderSide(color: Color(0xFF58585a)), // Borde gris oscuro, opcional
                                  ), 
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Selector lateral
                Expanded(
                  flex: 6,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFFF5F5F5),
                    child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Center(
                                        child: Text(
                                          "Area Reductions",
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Table(
                                        columnWidths: const {
                                          0: FlexColumnWidth(2),
                                          1: FlexColumnWidth(1),
                                        },
                                        border: TableBorder.all(
                                          color: const Color.fromARGB(255, 0, 0, 0),
                                          width: 1,
                                        ),
                                        children: [
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 56, 53, 53),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "Total",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color(0xFFe51937),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${totalReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 83, 79, 79),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "Average",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color.fromARGB(255, 221, 51, 77),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${avgReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 56, 53, 53),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "First",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color(0xFFe51937),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${firstReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 83, 79, 79),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "Last",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color.fromARGB(255, 221, 51, 77),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${lastReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 56, 53, 53),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "Maximum",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color(0xFFe51937),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${maxReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          TableRow(
                                            children: [
                                              Container(
                                                color: const Color.fromARGB(255, 83, 79, 79),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "Minimum",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                color: const Color.fromARGB(255, 221, 51, 77),
                                                padding: const EdgeInsets.all(6.0),
                                                child: Text(
                                                  "${minReduction.toStringAsFixed(1)}%",
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 16),
                                    ],
                                  ),

                                  SizedBox(height: 16),

                                  // Botón Linear
                                  OutlinedButton(
                                    onPressed: () {
                                      if (draftingType != 'Linear') {
                                        _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                      }
                                      setState(() {
                                        draftingType = 'Linear';
                                        sheets[currentSheetIndex].draftingType = draftingType;
                                        isManual = false;
                                        isManualAngle = false;
                                        semiActive = false;
                                        diametersModified =
                                            List.filled(manualDiameters.length, false);
                                        anglesModified = List.filled(manualAngles.length, false);
                                        enviarDatosAlBackend();
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: draftingType == 'Linear'
                                          ? const Color(0xFFe51937)
                                          : Colors.grey[300],
                                      foregroundColor: draftingType == 'Linear'
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    child: Text("Linear", style: TextStyle(fontSize: 16)),
                                  ),
                                  SizedBox(height: 8),

                                  // Botón Full Taper
                                  OutlinedButton(
                                    onPressed: () {
                                      if (draftingType != 'Full Taper') {
                                        _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                      }
                                      setState(() {
                                        draftingType = 'Full Taper';
                                        sheets[currentSheetIndex].draftingType = draftingType;

                                        if (taperPercentageController.text.isEmpty) {
                                          taperPercentageController.text = '15';
                                          sheets[currentSheetIndex].finalReductionPercentage = 15;
                                          finalReductionPercentage = 15;
                                        }
                                        isManual = false;
                                        isManualAngle = false;
                                        semiActive = false;
                                        diametersModified =
                                            List.filled(manualDiameters.length, false);
                                        anglesModified = List.filled(manualAngles.length, false);
                                        enviarDatosAlBackend();
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: draftingType == 'Full Taper'
                                          ? const Color(0xFFe51937)
                                          : Colors.grey[300],
                                      foregroundColor: draftingType == 'Full Taper'
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    child: Text("Full Taper", style: TextStyle(fontSize: 16)),
                                  ),

                                  if (draftingType == 'Full Taper') ...[
                                    SizedBox(height: 8),
                                    Text("Final Reduction Percentage (%)",
                                        style: TextStyle(fontSize: 15)),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: taperPercentageController,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              border: OutlineInputBorder(),
                                              hintText: esperandoRespuesta ? 'Loading...' : null,
                                            ),
                                            onChanged: (value) {
                                              final double? parsed = double.tryParse(value);
                                              if (parsed != null && parsed >= 0) {
                                                setState(() {
                                                  finalReductionPercentage = parsed;
                                                  sheets[currentSheetIndex]
                                                      .finalReductionPercentage = parsed;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 32,
                                              height: 24,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                    padding: EdgeInsets.zero),
                                                onPressed: () {
                                                  setState(() {
                                                    double value = double.tryParse(
                                                            taperPercentageController.text) ??
                                                        0;
                                                    value += 0.1;
                                                    value =
                                                        double.parse(value.toStringAsFixed(2));
                                                    taperPercentageController.text =
                                                        value.toString();
                                                    finalReductionPercentage = value;
                                                    sheets[currentSheetIndex]
                                                        .finalReductionPercentage = value;
                                                  });
                                                  enviarDatosAlBackend();
                                                },
                                                child:
                                                    Icon(Icons.arrow_drop_up, size: 16),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 32,
                                              height: 24,
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                    padding: EdgeInsets.zero),
                                                onPressed: () {
                                                  setState(() {
                                                    double value = double.tryParse(
                                                            taperPercentageController.text) ??
                                                        0;
                                                    value -= 0.1;
                                                    if (value < 0) value = 0;
                                                    value =
                                                        double.parse(value.toStringAsFixed(2));
                                                    taperPercentageController.text =
                                                        value.toString();
                                                    finalReductionPercentage = value;
                                                    sheets[currentSheetIndex]
                                                        .finalReductionPercentage = value;
                                                  });
                                                  enviarDatosAlBackend();
                                                },
                                                child:
                                                    Icon(Icons.arrow_drop_down, size: 16),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed: () {
                                      final double? parsed = double.tryParse(
                                          taperPercentageController.text);
                                      if (parsed != null && parsed >= 0 && parsed != finalReductionPercentage) {
                                        _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                        setState(() {
                                          finalReductionPercentage = parsed;
                                          sheets[currentSheetIndex]
                                              .finalReductionPercentage = parsed;
                                        });
                                        enviarDatosAlBackend();
                                      }
                                    },
                                    child: Text("Update", style: TextStyle(fontSize: 16)),
                                    ),
                                  ],

                                  SizedBox(height: 8),

                                  // Botón Semi Taper
                                  OutlinedButton(
                                    onPressed: (draftingType == 'Linear' ||
                                            draftingType == 'Optimized')
                                        ? null
                                        : () {
                                            if (!semiActive) {
                                              _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                            }
                                            setState(() {
                                              semiActive = true;
                                              sheets[currentSheetIndex].draftingType =
                                                  draftingType;

                                              if (semitaperPercentageController
                                                  .text.isEmpty) {
                                                semitaperPercentageController.text = '25';
                                                sheets[currentSheetIndex]
                                                    .maximumReductionPercentage = 25;
                                                maximumReductionPercentage = 25;
                                              }

                                              isManual = false;
                                              isManualAngle = false;
                                              diametersModified =
                                                  List.filled(manualDiameters.length, false);
                                              anglesModified =
                                                  List.filled(manualAngles.length, false);
                                              isSkinPass = false;
                                              enviarDatosAlBackend();
                                            });
                                          },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: draftingType == 'Semi Taper'
                                          ? const Color(0xFFe51937)
                                          : Colors.grey[300],
                                      foregroundColor: draftingType == 'Semi Taper'
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    child: Text("Semi Taper", style: TextStyle(fontSize: 16)),
                                  ),

                                  if (semiActive) ...[
                                    SizedBox(height: 8),
                                    Row(
                                      children: [
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text("Max Reduction %"),
                                              SizedBox(height: 4),
                                              TextField(
                                                controller: semitaperPercentageController,
                                                keyboardType: TextInputType.number,
                                                decoration: InputDecoration(
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (value) {
                                                  final double? loft =
                                                      double.tryParse(value);
                                                  if (loft != null && loft >= 0) {
                                                    setState(() {
                                                      maximumReductionPercentage = loft;
                                                      sheets[currentSheetIndex]
                                                          .maximumReductionPercentage = loft;
                                                    });
                                                  }
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(height: 20),
                                              OutlinedButton(
                                                onPressed: () {
                                                  final double? parsed = double.tryParse(
                                                      semitaperPercentageController.text);
                                                  if (parsed != null && parsed >= 0 && parsed != maximumReductionPercentage) {
                                                    _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                                    setState(() {
                                                      draftingType = 'Semi Taper';
                                                      maximumReductionPercentage = parsed;
                                                      sheets[currentSheetIndex]
                                                          .finalReductionPercentage = parsed;
                                                    });
                                                    enviarDatosAlBackend();
                                                  }
                                                },
                                                child: Text("Update",
                                                    style: TextStyle(fontSize: 16)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 8),
                                  ],

                                  SizedBox(height: 8),

                                  OutlinedButton(
                                    onPressed: () {
                                      if (draftingType != 'Optimized') {
                                        _saveStateBeforeChange(); // Guardar estado ANTES del cambio
                                      }
                                      setState(() {
                                        draftingType = 'Optimized';
                                        sheets[currentSheetIndex].draftingType = draftingType;
                                        isManual = false;
                                        isManualAngle = false;
                                        semiActive = false;
                                        diametersModified =
                                            List.filled(manualDiameters.length, false);
                                        anglesModified = List.filled(manualAngles.length, false);
                                        enviarDatosAlBackend();
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: draftingType == 'Optimized'
                                          ? const Color(0xFFe51937)
                                          : Colors.grey[300],
                                      foregroundColor: draftingType == 'Optimized'
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                    child: Text("Optimized", style: TextStyle(fontSize: 16)),
                                  ),

                                  // ❌ NO uses Spacer() en scroll. Usa espacio fijo.
                                  SizedBox(height: 16),

                                  SizedBox(height: 4),

                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PdfPreviewScreen(
                                            buildPdf: (section) =>
                                                generarPDFBytes(manualDiameters, reductions, pdfSection: section),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: Icon(Icons.visibility),
                                    label: Text("Preview PDF", style: TextStyle(fontSize: 16)),
                                  ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
          // Footer Sheets
          Container(
            height: 50,
            color: const Color(0xFF58585a),
            child: Row(
              children: [
                // Botón Add Sheet
                TextButton(
                  onPressed: () {
                    _showAddSheetDialog(); // Aplicar la funcion de Add Sheet (aplicar valores default o copiar los actuales a la nueva sheet)
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text("+ Add Sheet", style: TextStyle(fontSize: 16,)),
                ),

                // Botones de cada hoja
                for (int i = 0; i < sheets.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onDoubleTap: () {
                        setState(() {
                          editingSheetIndex = i;
                          johnStunlock.text = sheets[i].name.isEmpty
                              ? "Sheet ${i + 1}"
                              : sheets[i].name;
                        });
                      },
                      child: editingSheetIndex == i
                          ? Container(
                              width: 120,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade700,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: TextField(
                                controller: johnStunlock,
                                autofocus: true,
                                style: const TextStyle(color: Colors.white),
                                onSubmitted: (value) {
                                  setState(() {
                                    sheets[i].name =
                                        value.trim().isEmpty ? "Sheet ${i + 1}" : value;
                                    editingSheetIndex = null;
                                  });
                                },
                                onTapOutside: (_) {
                                  setState(() {
                                    sheets[i].name = johnStunlock.text.trim().isEmpty
                                        ? "Sheet ${i + 1}"
                                        : johnStunlock.text;
                                    editingSheetIndex = null;
                                  });
                                },
                              ),
                            )
                          : TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: currentSheetIndex == i
                                    ? Colors.grey.shade600
                                    : Colors.transparent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                saveCurrentSheetData();
                                loadSheetData(i);
                              },
                              child: Text(
                                sheets[i].name.isEmpty
                                    ? "Sheet ${i + 1}"
                                    : sheets[i].name,
                              ),
                            ),
                    ),
                  ),

                const Spacer(),

                // Botón Close Sheet
                TextButton(
                  onPressed: () {
                    if (sheets.length <= 1) return;
                    setState(() {
                      sheets.removeAt(currentSheetIndex);

                      // 👇 Renumerar solo los nombres por defecto
                      for (int j = 0; j < sheets.length; j++) {
                        if (sheets[j].name.startsWith("Sheet")) {
                          sheets[j].name = "Sheet ${j + 1}";
                        }
                      }

                      final newIndex =
                          currentSheetIndex > 0 ? currentSheetIndex - 1 : 0;
                      loadSheetData(newIndex);
                    });
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text("- Close Sheet", style: TextStyle(fontSize: 16,)),
                ),
              ],
            ),
          ),
            ],
          ),
        ); // end stage SizedBox

            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScaleEvent) {
                  final focal = event.localPosition - _centeringOffset;
                  _zoomAtPoint(_zoomLevel * event.scale, focal);
                } else if (event is PointerScrollEvent && _isCtrlOrMeta) {
                  final factor = exp(-event.scrollDelta.dy / _zoomScrollSensitivity);
                  final focal = event.localPosition - _centeringOffset;
                  _zoomAtPoint(_zoomLevel * factor, focal);
                }
              },
              onPointerPanZoomStart: (_) {
                _zoomAtPinchStart = _zoomLevel;
                _panAtPinchStart  = _panOffset;
              },
              onPointerPanZoomUpdate: (event) {
                final newZoom = (_zoomAtPinchStart * event.scale).clamp(_zoomMin, _zoomMax);
                final ratio = newZoom / _zoomAtPinchStart;
                final focal = event.localPosition - _centeringOffset;
                setState(() {
                  _panOffset = focal * (1 - ratio) + _panAtPinchStart * ratio;
                  _zoomLevel = newZoom;
                });
              },
              child: Center(
                child: Transform(
                  transform: Matrix4.identity()
                    ..translate(_panOffset.dx, _panOffset.dy)
                    ..scale(_zoomLevel, _zoomLevel),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: stage,
                  ),
                ),
              ),
            );
          },
        ), // end LayoutBuilder (body)
      ),    // Scaffold
      ),    // WillPopScope
    ),      // Actions
    );      // Shortcuts
  }
}
