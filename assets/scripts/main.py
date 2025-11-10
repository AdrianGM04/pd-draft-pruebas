import sys
import os
import json
import traceback
from calculo import perform_calculations

# Carpeta donde está main.py (y también stock_dies.json)
base_dir = os.path.dirname(os.path.abspath(__file__))

# Cargar stock_dies.json
json_path = os.path.join(base_dir, 'stock_dies.json')
try:
    with open(json_path, 'r') as f:
        stock_table = json.load(f)
except Exception as e:
    # Guardar errores en log para revisar
    with open(os.path.join(base_dir, 'python_log.txt'), 'a') as f:
        f.write(f"No se pudo cargar stock_dies.json: {e}\n")
    sys.exit(1)

def main():
    try:
        if len(sys.argv) < 2:
            raise ValueError("No se recibió ningún argumento JSON desde Dart.")
        input_json = sys.argv[1]
        data = json.loads(input_json)
        data['stock_table'] = stock_table

        result = perform_calculations(data)

        print(json.dumps({"resultado": result}))
        sys.stdout.flush()

    except Exception as e:
        tb = traceback.format_exc()
        with open(os.path.join(base_dir, 'python_log.txt'), 'a') as f:
            f.write(f"ERROR: {str(e)}\nTRACEBACK:\n{tb}\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
