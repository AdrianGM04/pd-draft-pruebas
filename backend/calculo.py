import sys
import os
import json
import math
import uuid

def resource_path(relative_path):
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = os.path.abspath(".")

    return os.path.join(base_path, relative_path)

# Carga el archivo JSON usando resource_path
json_path = resource_path('data/stock_dies.json')
with open(json_path, 'r') as f:
    table = json.load(f)

MATERIALS = [
    "High Carbon - Low",      # index 0
    "High Carbon - Mid",      # index 1
    "High Carbon - High",     # index 2
    "Low Carbon - High",      # index 3
    "Low Carbon - Low",       # index 4
    "Stainless - 300",        # index 5
    "Stainless - 400",        # index 6
    "Custom",                 # index 7 (para usar `tensile_min` y `tensile_max`)
]

def generate_unique_id():
    return str(uuid.uuid4())

def power_n(base, exponent):
    if base != 0:
        return math.exp(exponent * math.log(base))
    else:
        return 1.0

def root_n(value, root):
    if root == 0:
        root = 1.0
    return power_n(value, 1 / root)

def calculate_linear(input_val, finish, steps, decimals):
    arr_die = [0.0] * (steps + 1)
    arr_die[0] = input_val
    arr_die[steps] = finish
    if arr_die[0] * arr_die[steps] == 0:
        raise ValueError("¡Falta el diámetro inicial o final!")
    ratio_linear = root_n(arr_die[0] / arr_die[steps], steps)
    for i in range(1, steps):
        arr_die[i] = arr_die[i - 1] / ratio_linear
    return [round(v, decimals) for v in arr_die]

def calculate_skin_pass_linear(initial_diameter, finish_diameter, final_reduction, dies, decimals):
    """
    Calcula diámetros para skin pass:
    - Penúltimo diámetro con fórmula
    - Lineal desde inicial hasta penúltimo (dies-1 pasos)
    - Agrega el diámetro final
    """
    if final_reduction <= 0 or final_reduction >= 100:
        raise ValueError("Final reduction must be between 0 and 100")

    x = final_reduction / 100
    d_penultimate = round(finish_diameter / math.sqrt(1 - x), decimals)

    # Calcula lineal desde inicial hasta penúltimo
    diameters_to_penultimate = calculate_linear(
        initial_diameter, d_penultimate, dies - 1, decimals)

    # Agrega el diámetro final
    diameters = diameters_to_penultimate + [finish_diameter]

    return diameters

def calculate_full_taper(initial_diameter, finish_diameter, last_reduction, steps, decimals):
    
    ratioi = root_n(finish_diameter/initial_diameter,steps)
    avg_reduction2 = 100 * (1 - ratioi ** 2 )

    DrAv = root_n(1 - avg_reduction2 / 100, 2)
    DrMin = root_n(1 - last_reduction / 100, 2)
    DrMax = (DrAv ** 2) / DrMin
    DDrat = root_n(DrMin / DrMax, steps - 1)
    diameters = [0.0] * (steps)
    diameters [0] = initial_diameter
    for x in range(1, steps):
        diameters[x] = diameters[x - 1] * DrMax * power_n(DDrat, x - 1)
    Ultimo = diameters[steps-1] * DrMax * power_n(DDrat, steps-1)
    DrMax = DrMax * root_n(finish_diameter/Ultimo, steps)
    for x in range(1, steps):
        diameters[x] = diameters[x - 1] * DrMax * power_n(DDrat, x - 1)
    return [round(v, decimals) for v in diameters]

def calculate_skin_pass_full_taper(initial_diameter, finish_diameter, final_reduction, last_reduction, dies, decimals):
    """
    Calcula diámetros para skin pass usando Full Taper:
    - Penúltimo diámetro con fórmula
    - Full Taper desde inicial hasta penúltimo (dies-1 pasos)
    - Agrega el diámetro final
    """
    if final_reduction <= 0 or final_reduction >= 100:
        raise ValueError("Final reduction must be between 0 and 100")
    
    x = final_reduction / 100
    d_penultimate = round(finish_diameter / math.sqrt(1 - x), decimals)

    full_taper_to_penultimate = calculate_full_taper(
        initial_diameter, d_penultimate, last_reduction, dies-1, decimals
    )
    full_taper = full_taper_to_penultimate + [d_penultimate]

    return full_taper

def calculate_optimization(temperatures, material_index, dies, carbon, finish_diameter, initial_diameter, min_tensile, max_tensile, tensile_temp):
    # Promedio de temperaturas
    average_temp = sum(temperatures) / dies
    # Factor de tensión según sistema
    tensfact = 1
    # Inicializar arreglos
    Farr = [0.0] * (dies + 1)
    Rarr = [0.0] * (dies + 1)
    Darr = [0.0] * (dies + 1)
    # Establecer diámetro final
    Darr[dies] = finish_diameter
    Darr[0] = initial_diameter
    # Paso 1: Inicializar fuerza final
    Farr[dies] = tensile_temp[dies] * tensfact
    # Paso 2: Loop inverso para calcular reducciones y diámetros
    for x in range(dies, 0, -1):
        # Determinar constante c
        c = 25 * 9.81 if x == 1 else 30 * 9.81
        # Reducción en porcentaje para este paso
        Rarr[x] = average_temp * c / Farr[x]
        # Calcular diámetro anterior si no es el primero
        if x != 1:
            Darr[x - 1] = root_n((Darr[x] ** 2 * 100) / (100 - Rarr[x]), 2)
            # Calcular fuerza tensil anterior
            if material_index in range(0, 7):
                Farr[x - 1] = tens_mat(Darr[0], Darr[x - 1], carbon, material_index)*tensfact
            elif material_index == 7:
                Farr[x - 1] = tensile_min_max(Darr[0], Darr[x - 1], Darr[dies], min_tensile, max_tensile)
    return {
        "diameters": Darr,
        "reductions": Rarr,
        "tensions": Farr
    }

def calculate_optimization_skin_pass(temperatures, material_index, dies, carbon, finish_diameter, initial_diameter, min_tensile, max_tensile, tensile_temp, final_reduction, decimals):
    
    if final_reduction <= 0 or final_reduction >= 100:
        raise ValueError("Final reduction must be between 0 and 100")
    
    x = final_reduction / 100
    d_penultimate = round(finish_diameter / math.sqrt(1 - x), decimals)

    new_temp = temperatures.copy()
    new_temp.pop()
        
    optimized_skin_pass = calculate_optimization(
        new_temp, material_index, dies, carbon,
        d_penultimate, initial_diameter,
        min_tensile, max_tensile, tensile_temp
    )

    diameters = optimized_skin_pass["diameters"]
    reductions = optimized_skin_pass["reductions"]
    tensions = optimized_skin_pass["tensions"]

    diameters.append(finish_diameter)
    reductions.append(final_reduction)

    if material_index < 7:
        final_tension = tens_mat(diameters[0], finish_diameter, carbon, material_index)
    else:
        final_tension = tensile_min_max(diameters[0], finish_diameter, finish_diameter, min_tensile, max_tensile)

    tensions.append(final_tension)

    return {
        "diameters": diameters,
        "reductions": reductions,
        "tensions": tensions
    }



def calculate_reduction(initial, final, n):
    if initial * final * n <= 0:
        return 0.0
    return 100 - 100 * final ** 2 / initial ** 2

def calculate_reductions(diameters, decimals):
    reductions = [0.0] * len(diameters)
    for i in range(1, len(diameters)):
        initial = diameters[i - 1]
        final = diameters[i]
        reduction = calculate_reduction(initial, final, 1)
        if reduction < 1:
            diameters[i - 1] = final
            initial = diameters[i - 1]
            final = diameters[i]
            reduction = calculate_reduction(initial, final, 1)
        reductions[i] = reduction
    return [round(v, decimals) for v in reductions]

def tens_mat(initial_diameter, finish_diameter, coefficient, material_index):
    def high_carbon():
        if finish_diameter == 0:
            return 0
        return (5.83 * math.sqrt(coefficient) +
                100 * (coefficient - 0.7) +
                120 * math.sqrt(initial_diameter / finish_diameter))
    def low_carbon():
        return 88 + 77 * coefficient - 50 * ((finish_diameter / initial_diameter) ** 2) - 12
    def stainless_steel():
        return 75 + 1667 * coefficient * (1 - (finish_diameter / initial_diameter) ** 2)
    if material_index == 0:
        return (high_carbon() - 15) * 9.81
    if material_index == 1:
        return high_carbon() * 9.81
    if material_index == 2:
        return (high_carbon() - 7.5) * 9.81
    if material_index == 3:
        return (low_carbon() + 12) * 9.81
    if material_index == 4:
        return low_carbon() * 9.81
    if material_index in (5, 6):
        return stainless_steel() * 9.81
    return 0

def tensile_min_max(initial_diameter, middle_diameter, finish_diameter, min_tensile, max_tensile):
    reduction_middle = calculate_reduction(initial_diameter, middle_diameter, 1)
    reduction_finish = calculate_reduction(initial_diameter, finish_diameter, 1)
    return min_tensile + reduction_middle * ((max_tensile - min_tensile) / reduction_finish)

def calculate_tensile_strength(material_index, carbon, diameters, tmin, tmax):
    dies = len(diameters) - 1
    if material_index < 7:  # para materiales estándar con fórmulas
        tensile_list = [
            tens_mat(diameters[0], d, carbon, material_index)
            for d in diameters
        ]
    else:  # para materiales personalizados que usan interpolación
        tensile_list = [
            tensile_min_max(diameters[0], d, diameters[dies], tmin, tmax)
            for d in diameters
        ]
    return [round(v) for v in tensile_list]

def calculate_delta(diameters, angles):
    deltas = []
    for i in range(1, len(diameters)):
        d0 = diameters[i - 1]
        d1 = diameters[i]
        if d0 <= d1 or angles[i - 1] == 0:
            deltas.append(0.0)
            continue
        alpha = angles[i - 1]
        angle_rad = math.radians(alpha / 2)
        sin_comp = math.sin(angle_rad)
        delta = ((d0 + d1) / (d0 - d1)) * sin_comp
        deltas.append(delta if delta > 0 else 0.0)
    return deltas


def calculate_temperatures(num_diameters, reductions, tensions):
    temps = [0] * num_diameters
    for i in range(2, num_diameters):
        temps[i] = round((reductions[i] * tensions[i]) / 30 / 9.81)
    if num_diameters > 1:
        temps[1] = round((reductions[1] * tensions[1]) / 25 / 9.81)
    return [str(t) for t in temps]

def calculate_angles(deltas, angles, delta_lo, delta_hi):
    for i, d in enumerate(deltas):
        if round(d * 100) < delta_lo:
            angles[i] = 16
        if round(d * 100) > delta_hi:
            angles[i] = 9
    return angles

def select_standard_dies(memo_angles, arr_die):
    staArr = [False] * len(arr_die)
    for row in table:
        if row.get("insert") != "D":
            continue
        for idx, angle in enumerate(memo_angles):
            if row.get("angle") == angle:
                ri = float(row["step"])  # ri = step
                rl = float(row["lower"]) # rl = lower
                rh = float(row["upper"]) # rh = upper
                rd = arr_die[idx]
                if rl - ri/2 <= rd <= rh + ri/2:
                    sm = round(rd / ri) * ri
                    arr_die[idx] = sm
                    staArr[idx] = row.get("inStock", False)
    return {"stock_diameters": arr_die, "stock_array": staArr}

def get_delta_low(material_index):
    if material_index <= 2:
        return round(1.2 * 100)
    elif material_index <= 4:
        return round(1.3 * 100)
    elif material_index <= 6:
        return round(1.35 * 100)
    else:
        return round(1.0 * 100)

def get_delta_high(material_index):
    if material_index <= 2:
        return round(1.89 * 100)
    elif material_index <= 4:
        return round(2.25 * 100)
    elif material_index <= 6:
        return round(2.25 * 100)
    else:
        return round(2.0 * 100)

def get_speed(final_speed, diameters):
    if final_speed == 0:
        return [0.0 for _ in diameters]

    diameters_float = [float(d) for d in diameters]

    df = diameters_float[-1]
    speed = []
    for da in diameters_float:
        if da == 0:
            speed.append(0.0)
        else:
            sa = ((df / da) ** 2) * final_speed
            speed.append(sa)
    return speed

def get_weight(final_speed, finish_diameter):
    if final_speed == 0:
        return 0.0
    else:
        return 22.195352 * (finish_diameter)**2 * final_speed
    
def inches_to_mm(value):
    return value * 25.4

def mm_to_inches(value):
    return value / 25.4


def perform_calculations(state):
    print("STATE RECIBIDO:", state)

    # Detectar sistema de unidades
    unit_system = state.get("selectedSystem", "metric")

    # Convertir entradas a métrico si es imperial
    if unit_system == "imperial":
        state["initialDiameter"] = inches_to_mm(float(state["initialDiameter"]))
        state["finishDiameter"] = inches_to_mm(float(state["finishDiameter"]))
        state["tensileMin"] = float(state["tensileMin"])
        state["tensileMax"] = float(state["tensileMax"])
        

    # Leer variables ya convertidas
    decimals = state['decimals']
    initial_diameter = float(state['initialDiameter'])
    finish_diameter = float(state['finishDiameter'])
    dies = int(state['dies'])
    carbon = float(state['carbon'])
    tensile_min = float(state['tensileMin'])
    tensile_max = float(state['tensileMax'])
    drafting_type = state['draftingType']
    final_reduction_percentage = float(state['finalReductionPercentage'])
    final_skin_pass_reduction = float(state.get('finalReductionPercentageSkinPass', 10.0))
    using_stock_dies = state['usingStockDies']
    is_skin_pass = state.get("isSkinPass", False)
    angle_mode = state.get("angleMode", "auto")
    angles_per_die = state.get("anglesPerDie", [])

    unit_system = state.get("selectedSystem", "metric")
    selected_speed_unit = state.get("selectedSpeed", "m/s")
    selected_output_unit = state.get("selectedOutput", "kg/h")

    is_manual = state.get("isManual", False)
    manual_diameters = state.get("manualDiameters", [])

    raw_material = state['materialIndex']
    if isinstance(raw_material, int):
        material_index = raw_material
    else:
        try:
            material_index = MATERIALS.index(raw_material)
        except ValueError:
            material_index = 0

    if using_stock_dies:
        decimals = 2

    die_numbers = list(range(dies + 1))

    # Cálculo de diametros base
    diameters_base = calculate_linear(initial_diameter, finish_diameter, dies, decimals)
    reductions_base = calculate_reductions(diameters_base, 1)

    if is_skin_pass and dies > 1:
        if drafting_type == 'Full Taper':
            diameters = calculate_skin_pass_full_taper(
                initial_diameter, finish_diameter,
                final_skin_pass_reduction, final_reduction_percentage,
                dies, decimals
            ) + [finish_diameter]
        elif drafting_type == "Optimized":
            diameters_temp = diameters_base
            tensile_temp = calculate_tensile_strength(material_index, carbon, diameters_temp, tensile_min, tensile_max)
            reductions_temp = calculate_reductions(diameters_temp, 1)
            temperatures_temp = [int(v) for v in calculate_temperatures(len(diameters_temp), reductions_temp, tensile_temp)]

            opt_result = calculate_optimization_skin_pass(
                temperatures_temp, material_index, dies - 1, carbon,
                finish_diameter, initial_diameter, tensile_min, tensile_max,
                tensile_temp, final_skin_pass_reduction, decimals
            )
            
            diameter_values = opt_result["diameters"]
            diameters = [{'value': round(v, decimals)} for v in diameter_values]
            diameter_values = [d['value'] for d in diameters]

            reductions = [{'value': round(v, 1)} for v in opt_result["reductions"]]
            tensile_values = [{'value': round(v)} for v in opt_result["tensions"]]
        else:
            diameters = calculate_skin_pass_linear(
                initial_diameter, finish_diameter,
                final_skin_pass_reduction, dies, decimals
            )
    elif drafting_type == 'Full Taper' and dies > 1:
        diameters = calculate_full_taper(
            initial_diameter, finish_diameter,
            final_reduction_percentage, dies, decimals
        ) + [finish_diameter]
    elif drafting_type == 'Optimized' and dies > 1:
        diameters_temp = diameters_base
        tensile_temp = calculate_tensile_strength(material_index, carbon, diameters_temp, tensile_min, tensile_max)
        reductions_temp = calculate_reductions(diameters_temp, 1)
        temperatures_temp = [int(v) for v in calculate_temperatures(len(diameters_temp), reductions_temp, tensile_temp)]

        opt_result = calculate_optimization(
            temperatures_temp, material_index, dies, carbon,
            finish_diameter, initial_diameter, tensile_min, tensile_max, tensile_temp
        )

        diameter_values = opt_result["diameters"]
        diameters = [{'value': round(v, decimals)} for v in diameter_values]
        diameter_values = [d['value'] for d in diameters]

        reductions = [{'value': round(v, 1)} for v in opt_result["reductions"]]
        tensile_values = [{'value': round(v)} for v in opt_result["tensions"]]
    else:
        diameters = diameters_base

    if drafting_type != 'Optimized':
        diameters = [{'value': v} for v in diameters]
        diameter_values = [d['value'] for d in diameters]

        reductions = calculate_reductions(diameter_values, 1)
        reductions = [{'value': v} for v in reductions]

        tensile_values = calculate_tensile_strength(material_index, carbon, diameter_values, tensile_min, tensile_max)
        tensile_values = [{'value': v} for v in tensile_values]

    total_reduction = round(calculate_reduction(diameter_values[0], diameter_values[-1], 1), 1)

    delta_low = get_delta_low(material_index)
    delta_high = get_delta_high(material_index)

    if angle_mode == 'same' and angles_per_die:
        angle_value = int(state['angle'])
        angles_list = [angle_value] * dies
    elif angle_mode == 'single' and len(angles_per_die) == dies:
        angles_list = [int(a) for a in angles_per_die]
    elif angle_mode == 'none':
        angles_list = [0] * dies
    else:
        angles_list = [12] * dies
        deltas = calculate_delta(diameter_values, angles_list)
        angles_list = calculate_angles(deltas, angles_list, delta_low, delta_high)

    deltas = calculate_delta(diameter_values, angles_list)
    angles = [{'value': 0}] + [{'value': v} for v in angles_list]
    deltas = [{'value': 0}] + [{'value': v} for v in deltas]

    stock = []
    if using_stock_dies:
        memo_angles = [a['value'] for a in angles[1:]]
        arr_die_vals = [d['value'] for d in diameters[1:]]
        stock_res = select_standard_dies(memo_angles, arr_die_vals)
        diameters = [{'value': initial_diameter}] + [{'value': v} for v in stock_res['stock_diameters']]
        diameter_values = [d['value'] for d in diameters]
        stock = [False] + stock_res['stock_array']
        reductions = calculate_reductions(diameter_values, 1)
        reductions = [{'value': v} for v in reductions]
        total_reduction = round(calculate_reduction(diameter_values[0], diameter_values[-1], 1), 1)
        angles_list = [12] * dies
        deltas = calculate_delta(diameter_values, angles_list)
        angles_list = calculate_angles(deltas, angles_list, delta_low, delta_high)
        deltas = calculate_delta(diameter_values, angles_list)
        angles = [{'value': 0}] + [{'value': v} for v in angles_list]
        deltas = [{'value': 0}] + [{'value': v} for v in deltas]

    temperatures = calculate_temperatures(len(diameters), [r['value'] for r in reductions], [t['value'] for t in tensile_values])
    temperatures = [{'value': int(v)} for v in temperatures]

    try:
        raw_speed = float(state.get("finalspeed", 0))
    except:
        raw_speed = 0.0

    if selected_speed_unit == "ft/s":
        final_speed_ms = raw_speed * 0.3048
    elif selected_speed_unit == "ft/min":
        final_speed_ms = raw_speed * 0.3048 / 60
    elif selected_speed_unit == "m/min":
        final_speed_ms = raw_speed / 60
    else:  # "m/s"
        final_speed_ms = raw_speed

    
    speed_values = get_speed(final_speed_ms, diameter_values)

    if selected_speed_unit == "ft/s":
        speed_values = [v / 0.3048 for v in speed_values]
    elif selected_speed_unit == "ft/min":
        speed_values = [v / 0.3048 * 60 for v in speed_values]
    elif selected_speed_unit == "m/min":
        speed_values = [v * 60 for v in speed_values]

    speeds = [{'value': v} for v in speed_values]

    weight = get_weight(final_speed_ms, finish_diameter)

    if selected_output_unit == "ton/h":
        tweight = weight / 1000
    elif selected_output_unit == "lb/h":
        tweight = weight * 2.20462
    elif selected_output_unit == "lb/min":
        tweight = (weight * 2.20462) / 60
    else:  # "kg/h" por defecto
        tweight = weight

    total_weight = [{'value': tweight}]

    # --- CONVERSIÓN DE SALIDA si sistema es imperial ---
    if unit_system == "imperial":
        for d in diameters:
            d["value"] = round(mm_to_inches(d["value"]), decimals)

        for delta in deltas:
            delta["value"] = round(mm_to_inches(delta["value"]), 3)

        for t in temperatures:
            t["value"] = int(round(t["value"] * 1.8))  # conversión de incremento °C → °F

    if is_manual and manual_diameters and len(manual_diameters) == len(diameter_values):
        for i in range(len(manual_diameters)):
            try:
                md = float(manual_diameters[i])
                if round(md, decimals) != round(diameter_values[i], decimals):
                    # Se detectó un cambio en este diámetro manual
                    diameter_values[i] = md
                    diameters[i]['value'] = md

                    # Recalcular reducción anterior (si no es el primero)
                    if i > 0:
                        initial = diameter_values[i - 1]
                        final = diameter_values[i]
                        red = calculate_reduction(initial, final, 1)
                        reductions[i]['value'] = round(red, 1)

                    # Recalcular reducción siguiente (si no es el último)
                    if i < len(diameter_values) - 1:
                        initial = diameter_values[i]
                        final = diameter_values[i + 1]
                        red = calculate_reduction(initial, final, 1)
                        reductions[i + 1]['value'] = round(red, 1)
            except Exception as e:
                print(f"Error procesando diámetro manual en índice {i}: {e}")

        # Recalcular tensiones y temperaturas actualizadas:
        tensile_values = calculate_tensile_strength(material_index, carbon, diameter_values, tensile_min, tensile_max)
        tensile_values = [{'value': round(v)} for v in tensile_values]

        # Recalcular temperaturas con las nuevas reducciones y tensiones
        temperatures = calculate_temperatures(len(diameter_values),
                                            [r['value'] for r in reductions],
                                            [t['value'] for t in tensile_values])
        temperatures = [{'value': int(v)} for v in temperatures]

        # Recalcular deltas y ángulos si están en modo automático
        if angle_mode not in ['same', 'single', 'none']:
            deltas_calc = calculate_delta(diameter_values, angles_list)
            angles_list = calculate_angles(deltas_calc, angles_list, delta_low, delta_high)
            deltas = calculate_delta(diameter_values, angles_list)
            angles = [{'value': 0}] + [{'value': v} for v in angles_list]
            deltas = [{'value': 0}] + [{'value': v} for v in deltas]


    return {
        'dies': die_numbers,
        'diameters': diameters,
        'reductions': reductions,
        'angles': angles,
        'tensiles': tensile_values,
        'deltas': deltas,
        'delta_low': delta_low,
        'delta_high': delta_high,
        'temperatures': temperatures,
        'total_reduction': total_reduction,
        'stock': stock,
        'speeds': speeds,
        'totalweight': total_weight
    }
