import '../models/globals.dart';

class SheetData {
  int numberOfDies;
  String initialDiameter;
  String finalDiameter;
  double finalSpeed;
  int decimals;
  String selectedMaterial;
  String selectedCarbon;
  double temperatureLimit;
  String draftingType;
  double finalReductionPercentage;
  double maximumReductionPercentage;
  double finalReductionPercentageSkinPass;
  int firstPressure;
  int middlePressure;
  int lastPressure;
  double tensileMin;
  double tensileMax;

  List<String> pressureDieValues;
  String selectedAngleMode;
  int selectedAngle;
  List<int> individualAngles;
  String selectedSystem;
  String selectedSpeedUnit;
  String selectedOutputUnit;

  bool usingStockDies;
  bool isSkinPass;
  bool isManual;
  bool isManualAngle;
  bool semiActive;
  bool isCustomDelta;
  double customMinDelta;
  double customMaxDelta;

  String productName;
  String description;
  String clientName;
  String date;
  String advisor;
  List<double> manualDiameters;
  List<int> manualAngles;
  List<bool> diametersModified;
  List<bool> anglesModified;

  String name;

  SheetData({
    this.numberOfDies = 5,
    this.initialDiameter = '5.5',
    this.finalDiameter = '2',
    this.finalSpeed = 0.0,
    this.decimals = 2,
    this.selectedMaterial = 'High Carbon Steel, Stelmor',
    this.selectedCarbon = '0.40%',
    this.temperatureLimit = 120.0,
    this.draftingType = 'Linear',
    this.semiActive = false,
    this.finalReductionPercentage = 15.0,
    this.maximumReductionPercentage = 25.0,
    this.finalReductionPercentageSkinPass = 10.0,
    this.firstPressure = 10,
    this.middlePressure = 10,
    this.lastPressure = 8,
    this.pressureDieValues = const [],
    this.individualAngles = const [],
    this.selectedAngle = 12,
    this.selectedAngleMode = 'auto',
    this.usingStockDies = false,
    this.isSkinPass = false,
    this.tensileMin = 400,
    this.tensileMax = 1200,
    this.selectedOutputUnit = "kg/h",
    this.selectedSpeedUnit = "m/s",
    this.productName = '',
    this.description = '',
    this.clientName = '',
    this.date = '',
    this.advisor = '',
    this.manualDiameters = const [],
    this.manualAngles = const [],
    this.isManual = false,
    this.isManualAngle = false,
    this.diametersModified = const [],
    this.anglesModified = const[],
    this.isCustomDelta = false,
    this.customMinDelta = 0.0,
    this.customMaxDelta = 0.0,
    this.name = '',
    String? selectedSystem,
  }) : selectedSystem = selectedSystem ?? globalSelectedSystem;
}
