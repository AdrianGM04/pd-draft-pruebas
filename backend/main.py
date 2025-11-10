import sys
import json
from calculo import perform_calculations  # tu función original

def main():
    for line in sys.stdin:
        try:
            data = json.loads(line.strip())  # Recibe JSON desde Flutter
            result = perform_calculations(data)  # Usa tu función real
            sys.stdout.write(json.dumps(result) + "\n")
            sys.stdout.flush()  # Muy importante para que Flutter reciba el dato
        except Exception as e:
            sys.stdout.write(json.dumps({"error": str(e)}) + "\n")
            sys.stdout.flush()

if __name__ == "__main__":
    main()
