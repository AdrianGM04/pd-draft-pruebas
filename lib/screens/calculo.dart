import 'dart:math';
import 'dart:convert';
import 'dart:io';

const List<String> MATERIALS = [
  "High Carbon - Low",      // index 0
  "High Carbon - Mid",      // index 1
  "High Carbon - High",     // index 2
  "Low Carbon - High",      // index 3
  "Low Carbon - Low",       // index 4
  "Stainless - 300",        // index 5
  "Stainless - 400",        // index 6
  "Custom",                 // index 7 (para usar `tensile_min` y `tensile_max`)
];

Map<String, dynamic> table = {}; // Se cargará desde el JSON

String resourcePath(String relativePath) {
  return relativePath;
}

List<dynamic> jsonList = []; // Cambiar a List en lugar de Map

Future<void> loadTable() async {
  try {
    final jsonPath = resourcePath('assets/sdtcvbnm.json');  // assets/sdtcvbnm.json DEBUG 
    final file = File(jsonPath);                                                // data/flutter_assets/assets/sdtcvbnm.json RELEASE
    final contents = await file.readAsString();
    final decoded = jsonDecode(contents);
    
    if (decoded is Map<String, dynamic>) {
      table = decoded;
    } else if (decoded is List<dynamic>) {
      table = {};
      for (int i = 0; i < decoded.length; i++) {
        if (decoded[i] is Map<String, dynamic>) {
          table['item_$i'] = decoded[i];
        }
      }
    }
  } catch (e) {
    print('Error loading JSON: $e');
    table = {};
  }
}

double powerN(double base, double exponent) {
  if (base != 0) {
    return exp(exponent * log(base));
  } else {
    return 1.0;
  }
}

double rootN(double value, double root) {
  if (root == 0) {
    root = 1.0;
  }
  return powerN(value, 1 / root);
}

List<double> calculateLinear(double inputVal, double finish, int steps, int decimals) {
  List<double> arrDie = List.filled(steps + 1, 0.0);
  arrDie[0] = inputVal;
  arrDie[steps] = finish;
  
  if (arrDie[0] * arrDie[steps] == 0) {
    throw Exception("¡Falta el diámetro inicial o final!");
  }
  
  double ratioLinear = rootN(arrDie[0] / arrDie[steps], steps.toDouble());
  for (int i = 1; i < steps; i++) {
    arrDie[i] = arrDie[i - 1] / ratioLinear;
  }
  
  return arrDie.map((v) => double.parse(v.toStringAsFixed(decimals))).toList();
}

List<double> calculateSkinPassLinear(double initialDiameter, double finishDiameter, double finalReduction, int dies, int decimals) {
  if (finalReduction <= 0 || finalReduction >= 100) {
    throw Exception("Final reduction must be between 0 and 100");
  }

  double x = finalReduction / 100;
  double dPenultimate = double.parse((finishDiameter / sqrt(1 - x)).toStringAsFixed(decimals));

  List<double> diametersToPenultimate = calculateLinear(
    initialDiameter, dPenultimate, dies - 1, decimals);

  List<double> diameters = List.from(diametersToPenultimate)..add(finishDiameter);

  return diameters;
}

List<double> calculateFullTaper(double initialDiameter, double finishDiameter, double lastReduction, int steps, int decimals) {
  double ratioi = rootN(finishDiameter / initialDiameter, steps.toDouble());
  double avgReduction2 = 100 * (1 - pow(ratioi, 2)) as double;

  double drAv = rootN(1 - avgReduction2 / 100, 2);
  double drMin = rootN(1 - lastReduction / 100, 2);
  double drMax = pow(drAv, 2) / drMin;
  double dDrat = rootN(drMin / drMax, (steps - 1).toDouble());
  
  List<double> diameters = List.filled(steps, 0.0);
  diameters[0] = initialDiameter;
  
  for (int x = 1; x < steps; x++) {
    diameters[x] = diameters[x - 1] * drMax * powerN(dDrat, (x - 1).toDouble());
  }
  
  double ultimo = diameters[steps - 1] * drMax * powerN(dDrat, (steps - 1).toDouble());
  drMax = drMax * rootN(finishDiameter / ultimo, steps.toDouble());
  
  for (int x = 1; x < steps; x++) {
    diameters[x] = diameters[x - 1] * drMax * powerN(dDrat, (x - 1).toDouble());
  }
  
  return diameters.map((v) => double.parse(v.toStringAsFixed(decimals))).toList();
}

List<double> calculateSkinPassFullTaper(double initialDiameter, double finishDiameter, double finalReduction, double lastReduction, int dies, int decimals) {
  if (finalReduction <= 0 || finalReduction >= 100) {
    throw Exception("Final reduction must be between 0 and 100");
  }
  
  double x = finalReduction / 100;
  double dPenultimate = double.parse((finishDiameter / sqrt(1 - x)).toStringAsFixed(decimals));

  List<double> fullTaperToPenultimate = calculateFullTaper(
    initialDiameter, dPenultimate, lastReduction, dies - 1, decimals
  );
  
  List<double> fullTaper = List.from(fullTaperToPenultimate)..add(dPenultimate);

  return fullTaper;
}

Map<String, List<double>> calculateOptimization(List<double> temperatures, int materialIndex, int dies, double carbon, double finishDiameter, double initialDiameter, double minTensile, double maxTensile, List<double> tensileTemp) {
  double averageTemp = temperatures.reduce((a, b) => a + b) / dies;
  double tensfact = 1;
  
  List<double> farr = List.filled(dies + 1, 0.0);
  List<double> rarr = List.filled(dies + 1, 0.0);
  List<double> darr = List.filled(dies + 1, 0.0);
  
  darr[dies] = finishDiameter;
  darr[0] = initialDiameter;
  farr[dies] = tensileTemp[dies] * tensfact;
  
  for (int x = dies; x > 0; x--) {
    double c = (x == 1) ? 25 * 9.81 : 30 * 9.81;
    rarr[x] = averageTemp * c / farr[x];
    
    if (x != 1) {
      darr[x - 1] = rootN((pow(darr[x], 2) * 100) / (100 - rarr[x]), 2);
      
      if (materialIndex >= 0 && materialIndex < 7) {
        farr[x - 1] = tensMat(darr[0], darr[x - 1], carbon, materialIndex) * tensfact;
      } else if (materialIndex == 7) {
        farr[x - 1] = tensileMinMax(darr[0], darr[x - 1], darr[dies], minTensile, maxTensile);
      }
    }
  }

  rarr[1] = 100 - (100 * pow((darr[1]/darr[0]), 2.0).toDouble());
  
  return {
    "diameters": darr,
    "reductions": rarr,
    "tensions": farr
  };
}

Map<String, List<double>> calculateOptimizationSkinPass(List<double> temperatures, int materialIndex, int dies, double carbon, double finishDiameter, double initialDiameter, double minTensile, double maxTensile, List<double> tensileTemp, double finalReduction, int decimals) {
  if (finalReduction <= 0 || finalReduction >= 100) {
    throw Exception("Final reduction must be between 0 and 100");
  }

  int iteracion = 0;
  
  double x = finalReduction / 100;
  double dPenultimate = double.parse((finishDiameter / sqrt(1 - x)).toStringAsFixed(decimals));

  List<double> newTemp = List.from(temperatures);

  while(iteracion < 30){
    iteracion ++;

    Map<String, List<double>> optimizedSkinPass = calculateOptimization(
      newTemp, materialIndex, dies, carbon,
      dPenultimate, initialDiameter,
      minTensile, maxTensile, tensileTemp
    );

    List<double> reductionValues = [];
    List<double> tensileValues = [];

    reductionValues = optimizedSkinPass["reductions"]!;
    tensileValues = optimizedSkinPass["tensions"]!;

    List<String> temperaturesTemp = calculateTemperatures(dies, reductionValues, tensileValues);
    List<double> temperaturesTempDouble = temperaturesTemp.map((v) => double.parse(v)).toList();

    double diferenciaT = temperaturesTempDouble[2] - temperaturesTempDouble[1];

    for(int i = 1; i < newTemp.length; i++){
      newTemp[i] -= diferenciaT * 0.05;
    };

  };

  Map<String, List<double>> optimizedSkinPass2 = calculateOptimization(
    newTemp, materialIndex, dies, carbon,
    dPenultimate, initialDiameter,
    minTensile, maxTensile, tensileTemp
  );

  List<double> diameters = List<double>.from(optimizedSkinPass2["diameters"]!);
  List<double> reductions = List<double>.from(optimizedSkinPass2["reductions"]!);
  List<double> tensions = List<double>.from(optimizedSkinPass2["tensions"]!);

  diameters.add(finishDiameter);
  reductions.add(finalReduction);

  double finalTension;
  if (materialIndex < 7) {
    finalTension = tensMat(diameters[0], finishDiameter, carbon, materialIndex);
  } else {
    finalTension = tensileMinMax(diameters[0], finishDiameter, finishDiameter, minTensile, maxTensile);
  }

  tensions.add(finalTension);

  return {
    "diameters": diameters,
    "reductions": reductions,
    "tensions": tensions
  };
}

List<double> calculateSemiTaper(double initialDiameter, double finishDiameter, double maximumReductionPercentage,
    double finalReductionPercentage, int dies, int decimals) {
  
  if (dies < 3) {
    throw Exception("Semi Taper necesita al menos 3 dados");
  }

  // Validaciones iniciales
  if (maximumReductionPercentage == 0) {
    throw Exception("La reducción máxima no puede ser cero");
  }

  // Calcular factores de reducción
  double drMax = rootN(1 - maximumReductionPercentage / 100, 2);
  double drAve = rootN(finishDiameter / initialDiameter, dies.toDouble());
  double drMinLeft = rootN(1 - finalReductionPercentage / 100, 2);

  // Validar que la reducción máxima sea mayor que la promedio
  if (drMax > drAve) {
    throw Exception("La reducción máxima debe ser mayor que la reducción promedio");
  }

  List<double> diameters = List.filled(dies + 1, 0.0);
  diameters[0] = initialDiameter;
  diameters[dies] = finishDiameter;

  int d = dies;
  int xSemi = 1;

  for (int x = 1; x <= dies - 2; x++) {
    diameters[x] = diameters[x - 1] * drMax;
    d--; // Dados restantes

    double drAvLeft = rootN(diameters[dies] / diameters[x], d.toDouble());
    double drMaxLeft = drAvLeft * drAvLeft / drMinLeft;
    double test = 100 - 100 * drMaxLeft * drMaxLeft;
    xSemi = x;

    if ((test * 10).round() / 10 < maximumReductionPercentage) {
      break;
    }
  }

  // Recalcular factores para la sección final
  double drAvLeft = rootN(diameters[dies] / diameters[xSemi], d.toDouble());
  double drMaxLeft = drAvLeft * drAvLeft / drMinLeft;
  double ddRat = rootN(drMinLeft / drMaxLeft, d - 1);

  // Calcular los diámetros restantes (desde xSemi+1 hasta dies-1)
  for (int x = xSemi + 1; x <= dies - 1; x++) {
    int exponent = x - xSemi - 1;
    double factor = (exponent >= 0) ? powerN(ddRat, exponent.toDouble()) : 1.0;
    diameters[x] = diameters[x - 1] * drMaxLeft * factor;
  }

  // Asegurar que el penúltimo dado conduzca exactamente al diámetro final
  // con la reducción final especificada
  double finalReductionFactor = 1 - finalReductionPercentage / 100;
  diameters[dies - 1] = diameters[dies] / sqrt(finalReductionFactor);

  // Redondear resultados
  List<double> result = diameters.map((diameter) => 
      double.parse(diameter.toStringAsFixed(decimals))).toList();
  
  return result;
}

List<double> calculateSemiTaperSkinPass(
    double initialDiameter,
    double finishDiameter,
    double maximumReductionPercentage,
    double finalReductionPercentage,
    double finalSkinPassReduction,
    int dies,
    int decimals) {
  
  if (finalReductionPercentage <= 0 || finalReductionPercentage >= 100) {
    throw Exception("La reducción final debe estar entre 0 y 100");
  }

  double x = finalSkinPassReduction / 100;
  double penultimate = double.parse(
      (finishDiameter / sqrt(1 - x)).toStringAsFixed(decimals));

  // Usamos el semi taper normal, pero hasta penúltimo
  List<double> semiResult = calculateSemiTaper(
    initialDiameter,
    penultimate,
    maximumReductionPercentage,
    finalReductionPercentage,
    dies - 1, // un dado menos porque dejamos el último para Skin Pass
    decimals,
  );

  // Agregar el diámetro final original
  List<double> diameters = List.from(semiResult);
  diameters.add(finishDiameter);

  return diameters;
}

double calculateReduction(double initial, double finalVal, int n) {
  if (initial * finalVal * n <= 0) {
    return 0.0;
  }
  return 100 - 100 * pow(finalVal, 2) / pow(initial, 2);
}

List<double> calculateReductions(List<double> diameters, int decimals) {
  List<double> reductions = List.filled(diameters.length, 0.0);
  for (int i = 1; i < diameters.length; i++) {
    double initial = diameters[i - 1];
    double finalVal = diameters[i];
    double reduction = calculateReduction(initial, finalVal, 1);
    
    if (reduction < 1) {
      diameters[i - 1] = finalVal;
      initial = diameters[i - 1];
      finalVal = diameters[i];
      reduction = calculateReduction(initial, finalVal, 1);
    }
    
    reductions[i] = reduction;
  }
  
  return reductions.map((v) => double.parse(v.toStringAsFixed(decimals))).toList();
}

double tensMat(double initialDiameter, double finishDiameter, double coefficient, int materialIndex) {
  double highCarbon() {
    if (finishDiameter == 0) return 0;
    return (5.83 * sqrt(coefficient)) +
        100 * (coefficient - 0.7) +
        120 * sqrt(initialDiameter / finishDiameter);
  }
  
  double lowCarbon() {
    return 88 + 77 * coefficient - 50 * pow(finishDiameter / initialDiameter, 2) - 12;
  }
  
  double stainlessSteel() {
    return 75 + 1667 * coefficient * (1 - pow(finishDiameter / initialDiameter, 2));
  }
  
  switch (materialIndex) {
    case 0:
      return (highCarbon() - 15) * 9.81;
    case 1:
      return highCarbon() * 9.81;
    case 2:
      return (highCarbon() - 7.5) * 9.81;
    case 3:
      return (lowCarbon() + 12) * 9.81;
    case 4:
      return lowCarbon() * 9.81;
    case 5:
    case 6:
      return stainlessSteel() * 9.81;
    default:
      return 0;
  }
}

double tensileMinMax(double initialDiameter, double middleDiameter, double finishDiameter, double minTensile, double maxTensile) {
  double reductionMiddle = calculateReduction(initialDiameter, middleDiameter, 1);
  double reductionFinish = calculateReduction(initialDiameter, finishDiameter, 1);
  return minTensile + reductionMiddle * ((maxTensile - minTensile) / reductionFinish);
}

List<int> calculateTensileStrength(int materialIndex, double carbon, List<double> diameters, double tmin, double tmax) {
  int dies = diameters.length - 1;
  List<double> tensileList;
  
  if (materialIndex < 7) {
    tensileList = diameters.map((d) => tensMat(diameters[0], d, carbon, materialIndex)).toList();
  } else {
    tensileList = diameters.map((d) => tensileMinMax(diameters[0], d, diameters[dies], tmin, tmax)).toList();
  }
  
  return tensileList.map((v) => v.round()).toList();
}

List<double> calculateDelta(List<double> diameters, List<int> angles) {
  List<double> deltas = [];
  for (int i = 1; i < diameters.length; i++) {
    double d0 = diameters[i - 1];
    double d1 = diameters[i];
    
    if (d0 <= d1 || angles[i - 1] == 0) {
      deltas.add(0.0);
      continue;
    }
    
    double alpha = angles[i - 1].toDouble();
    double angleRad = (alpha / 2) * (pi / 180);
    double sinComp = sin(angleRad);
    double delta = ((d0 + d1) / (d0 - d1)) * sinComp;
    deltas.add(delta > 0 ? delta : 0.0);
  }
  
  return deltas;
}

List<String> calculateTemperatures(int numDiameters, List<double> reductions, List<double> tensions) {
  List<int> temps = List.filled(numDiameters, 0);
  for (int i = 2; i < numDiameters; i++) {
    temps[i] = ((reductions[i] * tensions[i]) / 30 / 9.81).round();
  }
  
  if (numDiameters > 1) {
    temps[1] = ((reductions[1] * tensions[1]) / 25 / 9.81).round();
  }
  
  return temps.map((t) => t.toString()).toList();
}

List<int> calculateAngles(List<double> deltas, List<int> angles, int deltaLo, int deltaHi) {
  for (int i = 0; i < deltas.length; i++) {
    double d = deltas[i];
    if ((d * 100).round() < deltaLo) {
      angles[i] = 16;
    }
    if ((d * 100).round() > deltaHi) {
      angles[i] = 9;
    }
  }
  return angles;
}

Future<Map<String, dynamic>> selectStandardDies(
    List<int> memoAngles, List<double> arrDieVals) async {
  // Inicializar listas de salida
  List<bool> stockArray = List.filled(arrDieVals.length, false);
  List<double> stockDiameters = List.from(arrDieVals);

  if (table.isEmpty) {
    await loadTable(); // Asegúrate que tu tabla esté cargada
  }

  for (var row in table.values) {
    // Solo consideramos inserciones tipo 'D' (dados estándar)
    if (row["insert"] != "D") continue;

    for (int idx = 0; idx < memoAngles.length; idx++) {
      int currentAngle = memoAngles[idx];
      
      // Verificar si el ángulo de la fila coincide con el ángulo actual
      if (row["angle"] == currentAngle) {
        double ri = double.parse(row["step"].toString());    // ri = step
        double rl = double.parse(row["lower"].toString());  // rl = lower
        double rh = double.parse(row["upper"].toString());  // rh = upper
        double rd = arrDieVals[idx];                        // diámetro actual
        
        // Verificar si está dentro del rango permitido
        if (rl - ri/2 <= rd && rd <= rh + ri/2) {
          // Calcular el diámetro estándar más cercano
          double sm = (rd / ri).roundToDouble() * ri;
          stockDiameters[idx] = sm;
          stockArray[idx] = row["inStock"] ?? false;
        }
      }
    }
  }

  return {
    "stock_diameters": stockDiameters,
    "stock_array": stockArray,
  };
}


int getDeltaLow(int materialIndex) {
  if (materialIndex <= 2) {
    return (1.2 * 100).round();
  } else if (materialIndex <= 4) {
    return (1.3 * 100).round();
  } else if (materialIndex <= 6) {
    return (1.35 * 100).round();
  } else {
    return (1.0 * 100).round();
  }
}

int getDeltaHigh(int materialIndex) {
  if (materialIndex <= 2) {
    return (1.89 * 100).round();
  } else if (materialIndex <= 4) {
    return (2.25 * 100).round();
  } else if (materialIndex <= 6) {
    return (2.25 * 100).round();
  } else {
    return (2.0 * 100).round();
  }
}

List<double> getSpeed(double finalSpeed, List<double> diameters) {
  if (finalSpeed == 0) {
    return List.filled(diameters.length, 0.0);
  }
  
  double df = diameters.last;
  List<double> speed = [];
  
  for (double da in diameters) {
    if (da == 0) {
      speed.add(0.0);
    } else {
      double sa = pow(df / da, 2) * finalSpeed;
      speed.add(sa);
    }
  }
  
  return speed;
}

double getWeight(double finalSpeed, double finishDiameter) {
  if (finalSpeed == 0) {
    return 0.0;
  } else {
    return 22.195352 * pow(finishDiameter, 2) * finalSpeed;
  }
}

double inchesToMm(double value) {
  return value * 25.4;
}

double mmToInches(double value) {
  return value / 25.4;
}

double mPaTOKpsi(double value) {
  return value * 0.145038;
}

Future<Map<String, dynamic>> performCalculations(Map<String, dynamic> state) async {
  // Detectar sistema de unidades
  String unitSystem = state["selectedSystem"] ?? "metric";

  if (table.isEmpty) {
    await loadTable(); 
  }

  // Convertir entradas a métrico si es imperial
  if (unitSystem == "imperial") {
    state["initialDiameter"] = inchesToMm(double.parse(state["initialDiameter"].toString()));
    state["finishDiameter"] = inchesToMm(double.parse(state["finishDiameter"].toString()));
    state["tensileMin"] = double.parse(state["tensileMin"].toString());
    state["tensileMax"] = double.parse(state["tensileMax"].toString());
  }

  // Leer variables ya convertidas
  int decimals = 4;
  double initialDiameter = double.parse(state['initialDiameter'].toString());
  double finishDiameter = double.parse(state['finishDiameter'].toString());
  int dies = int.parse(state['dies'].toString());
  double carbon = double.parse(state['carbon'].toString());
  double tensileMin = double.parse(state['tensileMin'].toString());
  double tensileMax = double.parse(state['tensileMax'].toString());
  String draftingType = state['draftingType'];
  double finalReductionPercentage = double.parse(state['finalReductionPercentage'].toString());
  double maximumReductionPercentage= double.parse(state['maximumReductionPercentage'].toString());
  double finalSkinPassReduction = double.parse(state['finalReductionPercentageSkinPass']?.toString() ?? '10.0');
  bool usingStockDies = state['usingStockDies'];
  bool isSkinPass = state['isSkinPass'] ?? false;
  String angleMode = state['angleMode'] ?? "auto";
  List<dynamic> anglesPerDie = state['anglesPerDie'] ?? [];

  String selectedSpeedUnit = state['selectedSpeed'] ?? "m/s";
  String selectedOutputUnit = state['selectedOutput'] ?? "kg/h";

  bool isManual = state['isManual'] ?? false;
  bool isManualAngle = state['isManualAngle'] ?? false;
  List<dynamic> manualDiameters = state['manualDiameters'] ?? [];
  List<dynamic> manualAngles = state['manualAngles'] ?? [];

  dynamic rawMaterial = state['materialIndex'];
  int materialIndex;
  if (rawMaterial is int) {
    materialIndex = rawMaterial;
  } else {
    materialIndex = MATERIALS.indexOf(rawMaterial);
    if (materialIndex == -1) materialIndex = 0;
  }

  if (usingStockDies) {
    decimals = 2;
  }

  List<int> dieNumbers = List.generate(dies + 1, (index) => index);

  // Cálculo de diámetros base
  List<double> diametersBase = calculateLinear(initialDiameter, finishDiameter, dies, decimals);

  // INICIALIZAR LAS VARIABLES
  List<double> diameterValues = [];
  List<double> reductionValues = [];
  List<double> tensileValues = [];

  if (isSkinPass && dies > 1) {
    if (draftingType == 'Full Taper') {
      diameterValues = calculateSkinPassFullTaper(
        initialDiameter, finishDiameter,
        finalSkinPassReduction, finalReductionPercentage,
        dies, decimals
      )..add(finishDiameter);
      
      // Calcular reducciones y tensiones para Full Taper
      reductionValues = calculateReductions(diameterValues, 1);
      tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
          .map((v) => v.toDouble()).toList();
    } else if (draftingType == "Optimized") {
      List<double> diametersTemp = diametersBase;
      List<int> tensileTemp = calculateTensileStrength(materialIndex, carbon, diametersTemp, tensileMin, tensileMax);
      List<double> reductionsTemp = calculateReductions(diametersTemp, 1);
      List<String> temperaturesTemp = calculateTemperatures(diametersTemp.length, reductionsTemp, tensileTemp.map((v) => v.toDouble()).toList());
      List<double> temperaturesTempDouble = temperaturesTemp.map((v) => double.parse(v)).toList();

      Map<String, List<double>> optResult = calculateOptimizationSkinPass(
        temperaturesTempDouble, materialIndex, dies - 1, carbon,
        finishDiameter, initialDiameter, tensileMin, tensileMax,
        tensileTemp.map((v) => v.toDouble()).toList(), finalSkinPassReduction, decimals
      );
      
      diameterValues = optResult["diameters"]!;
      reductionValues = optResult["reductions"]!;
      tensileValues = optResult["tensions"]!;

    } else if (draftingType == 'Semi Taper' && dies > 1) {
      diameterValues = calculateSemiTaperSkinPass(
        initialDiameter, finishDiameter,
        maximumReductionPercentage, finalReductionPercentage, finalSkinPassReduction, dies, decimals
      );
      
      // Calcular reducciones y tensiones para Full Taper
      reductionValues = calculateReductions(diameterValues, 1);
      tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
          .map((v) => v.toDouble()).toList();
    }
    
    else {
      diameterValues = calculateSkinPassLinear(
        initialDiameter, finishDiameter,
        finalSkinPassReduction, dies, decimals
      );
      
      // Calcular reducciones y tensiones para Linear
      reductionValues = calculateReductions(diameterValues, 1);
      tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
          .map((v) => v.toDouble()).toList();
    }
  } else if (draftingType == 'Full Taper' && dies > 1) {
    diameterValues = calculateFullTaper(
      initialDiameter, finishDiameter,
      finalReductionPercentage, dies, decimals
    )..add(finishDiameter);
    
    // Calcular reducciones y tensiones para Full Taper
    reductionValues = calculateReductions(diameterValues, 1);
    tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
        .map((v) => v.toDouble()).toList();

    // Calcular reducciones y tensiones para Semi Taper
    } else if (draftingType == 'Semi Taper' && dies > 1) {
      diameterValues = calculateSemiTaper(
        initialDiameter, finishDiameter,
        maximumReductionPercentage, finalReductionPercentage, dies, decimals
      );
      
      // Calcular reducciones y tensiones para Full Taper
      reductionValues = calculateReductions(diameterValues, 1);
      tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
          .map((v) => v.toDouble()).toList();
    
    } else if (draftingType == 'Optimized' && dies > 1) {
      List<double> diametersTemp = diametersBase;
      List<int> tensileTemp = calculateTensileStrength(materialIndex, carbon, diametersTemp, tensileMin, tensileMax);
      List<double> reductionsTemp = calculateReductions(diametersTemp, 1);
      List<String> temperaturesTemp = calculateTemperatures(diametersTemp.length, reductionsTemp, tensileTemp.map((v) => v.toDouble()).toList());
      List<double> temperaturesTempDouble = temperaturesTemp.map((v) => double.parse(v)).toList();

      Map<String, List<double>> optResult = calculateOptimization(
        temperaturesTempDouble, materialIndex, dies, carbon,
        finishDiameter, initialDiameter, tensileMin, tensileMax, 
        tensileTemp.map((v) => v.toDouble()).toList()
      );

      diameterValues = optResult["diameters"]!;
      reductionValues = optResult["reductions"]!;
      tensileValues = optResult["tensions"]!;
    } else {
      diameterValues = diametersBase;
    
    // Calcular reducciones y tensiones para el caso por defecto
    reductionValues = calculateReductions(diameterValues, 1);
    tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
        .map((v) => v.toDouble()).toList();
  }

  double totalReduction = double.parse(calculateReduction(diameterValues[0], diameterValues.last, 1).toStringAsFixed(1));

  int deltaLow = getDeltaLow(materialIndex);
  int deltaHigh = getDeltaHigh(materialIndex);

  List<int> anglesList;
  if (isManualAngle == true){
    anglesList = manualAngles.map((a) => int.parse(a.toString())).toList();
  } else if (angleMode == 'single' && anglesPerDie.length == dies) {
    anglesList = anglesPerDie.map((a) => int.parse(a.toString())).toList();
  } else if(angleMode == 'same' && anglesPerDie.isNotEmpty) {
    int angleValue = int.parse(state['angle'].toString());
    anglesList = List.filled(dies, angleValue);
  } else {
    anglesList = List.filled(dies, 12);
    List<double> deltas = calculateDelta(diameterValues, anglesList);
    anglesList = calculateAngles(deltas, anglesList, deltaLow, deltaHigh);
  }

  List<double> deltas = calculateDelta(diameterValues, anglesList);
  
  // CORREGIR: Usar spread operator en lugar de concatenación
  List<Map<String, dynamic>> angles = [
    {"value": 0},
    ...anglesList.map((v) => {"value": v})
  ];
  
  List<Map<String, dynamic>> deltaList = [
    {"value": 0.0},
    ...deltas.map((v) => {"value": v})
  ];

  List<bool> stock = [];
  if (usingStockDies) {
    List<int> memoAngles = anglesList;
    List<double> arrDieVals = diameterValues.sublist(1);
    Map<String, dynamic> stockRes = await selectStandardDies(memoAngles, arrDieVals);
    diameterValues = [initialDiameter] + (stockRes["stock_diameters"] as List<double>);
    stock = [false] + (stockRes["stock_array"] as List<bool>);
    reductionValues = calculateReductions(diameterValues, 1);
    totalReduction = double.parse(calculateReduction(diameterValues[0], diameterValues.last, 1).toStringAsFixed(1));
    anglesList = List.filled(dies, 12);
    deltas = calculateDelta(diameterValues, anglesList);
    anglesList = calculateAngles(deltas, anglesList, deltaLow, deltaHigh);
    deltas = calculateDelta(diameterValues, anglesList);
    
    // CORREGIR: Usar spread operator
    angles = [
      {"value": 0},
      ...anglesList.map((v) => {"value": v})
    ];
    
    deltaList = [
      {"value": 0.0},
      ...deltas.map((v) => {"value": v})
    ];
  }

  List<String> temperatures = calculateTemperatures(
    diameterValues.length, 
    reductionValues, 
    tensileValues
  );

  List<Map<String, dynamic>> temperatureList = temperatures.map((v) => {"value": int.parse(v)}).toList();

  double rawSpeed;
  try {
    rawSpeed = double.parse(state["finalspeed"]?.toString() ?? '0');
  } catch (e) {
    rawSpeed = 0.0;
  }

  double finalSpeedMs;
  if (selectedSpeedUnit == "ft/s") {
    finalSpeedMs = rawSpeed * 0.3048;
  } else if (selectedSpeedUnit == "ft/min") {
    finalSpeedMs = rawSpeed * 0.3048 / 60;
  } else if (selectedSpeedUnit == "m/min") {
    finalSpeedMs = rawSpeed / 60;
  } else {
    finalSpeedMs = rawSpeed;
  }

  List<double> speedValues = getSpeed(finalSpeedMs, diameterValues);

  if (selectedSpeedUnit == "ft/s") {
    speedValues = speedValues.map((v) => v / 0.3048).toList();
  } else if (selectedSpeedUnit == "ft/min") {
    speedValues = speedValues.map((v) => v / 0.3048 * 60).toList();
  } else if (selectedSpeedUnit == "m/min") {
    speedValues = speedValues.map((v) => v * 60).toList();
  }

  List<Map<String, dynamic>> speeds = speedValues.map((v) => {"value": v}).toList();

  double weight = getWeight(finalSpeedMs, finishDiameter);
  double tweight;

  if (selectedOutputUnit == "ton/h") {
    tweight = weight / 1000;
  } else if (selectedOutputUnit == "lb/h") {
    tweight = weight * 2.20462;
  } else if (selectedOutputUnit == "lb/min") {
    tweight = (weight * 2.20462) / 60;
  } else {
    tweight = weight;
  }

  List<Map<String, dynamic>> totalWeight = [{"value": tweight}];

  // Conversión de salida si sistema es imperial
  if (unitSystem == "imperial") {
    diameterValues = diameterValues.map((d) => double.parse(mmToInches(d).toStringAsFixed(decimals))).toList();
    temperatureList = temperatureList.map((t) => {"value": ((t["value"] * 1.8).round())}).toList();
    tensileValues = tensileValues.map((d) => double.parse(mPaTOKpsi(d).toStringAsFixed(decimals))).toList();
  }

  // Procesamiento de diámetros manuales
  if (isManual && manualDiameters.isNotEmpty && manualDiameters.length == diameterValues.length) {
    for (int i = 0; i < manualDiameters.length; i++) {
      try {
        double md = double.parse(manualDiameters[i].toString());
        if (double.parse(md.toStringAsFixed(decimals)) != double.parse(diameterValues[i].toStringAsFixed(decimals))) {
          diameterValues[i] = md;

          if (i > 0) {
            double initial = diameterValues[i - 1];
            double finalVal = diameterValues[i];
            double red = calculateReduction(initial, finalVal, 1);
            reductionValues[i] = double.parse(red.toStringAsFixed(1));
          }

          if (i < diameterValues.length - 1) {
            double initial = diameterValues[i];
            double finalVal = diameterValues[i + 1];
            double red = calculateReduction(initial, finalVal, 1);
            reductionValues[i + 1] = double.parse(red.toStringAsFixed(1));
          }
        }
      } catch (e) {
        print("Error procesando diámetro manual en índice $i: $e");
      }
    }

    tensileValues = calculateTensileStrength(materialIndex, carbon, diameterValues, tensileMin, tensileMax)
        .map((v) => v.toDouble()).toList();

    temperatures = calculateTemperatures(
      diameterValues.length, reductionValues, tensileValues
    );
    temperatureList = temperatures.map((v) => {"value": int.parse(v)}).toList();

    if (angleMode != 'same' && angleMode != 'single' && angleMode != 'none') {
      List<double> deltasCalc = calculateDelta(diameterValues, anglesList);
      anglesList = calculateAngles(deltasCalc, anglesList, deltaLow, deltaHigh);
      deltas = calculateDelta(diameterValues, anglesList);
      
      // CORREGIR: Usar spread operator
      angles = [
        {"value": 0},
        ...anglesList.map((v) => {"value": v})
      ];
      
      deltaList = [
        {"value": 0.0},
        ...deltas.map((v) => {"value": v})
      ];
    }
  }

  // Convertir listas de valores a listas de mapas
  List<Map<String, dynamic>> diameterList = diameterValues.map((v) => {"value": v}).toList();
  List<Map<String, dynamic>> reductionList = reductionValues.map((v) => {"value": v}).toList();
  List<Map<String, dynamic>> tensileList = tensileValues.map((v) => {"value": v.round()}).toList();

  return {
    'dies': dieNumbers,
    'diameters': diameterList,
    'reductions': reductionList,
    'angles': angles,
    'tensiles': tensileList,
    'deltas': deltaList,
    'delta_low': deltaLow,
    'delta_high': deltaHigh,
    'temperatures': temperatureList,
    'total_reduction': totalReduction,
    'stock': stock,
    'speeds': speeds,
    'totalweight': totalWeight
  };
}