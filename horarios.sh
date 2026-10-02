#!/bin/sh
# horarios.sh -- envoltorio de invocacion
#
#   ./horarios.sh instancia.dat salida.txt bt --heuristica=mrv
#   ./horarios.sh instancia.dat salida.txt clpfd --optimizar --limite=5000000

if [ $# -lt 3 ]; then
    echo "Uso: $0 <instancia.dat> <salida.txt> <bt|bt_gp|clpfd> [opciones...]" >&2
    echo "  --heuristica=H     (original|mrv|grado|demanda|ff|ffc|lcv)" >&2
    echo "  --simetria=si|no" >&2
    echo "  --limite=N" >&2
    echo "  --optimizar" >&2
    echo "  --por-aula" >&2
    echo "  --salida-prolog=RUTA" >&2
    echo "  --labeling=fd|propio  (default: propio)" >&2
    exit 4
fi

INSTANCIA=$1
SALIDA=$2
ESTRATEGIA=$3
shift 3

OPCIONES=""
for arg in "$@"; do
    case "$arg" in
        --heuristica=*)     H=${arg#--heuristica=}
                            OPCIONES="$OPCIONES,heuristica($H)" ;;
        --simetria=*)       S=${arg#--simetria=}
                            OPCIONES="$OPCIONES,simetria($S)" ;;
        --limite=*)         L=${arg#--limite=}
                            OPCIONES="$OPCIONES,limite($L)" ;;
        --optimizar)        OPCIONES="$OPCIONES,optimizar" ;;
        --por-aula)         OPCIONES="$OPCIONES,por_aula" ;;
        --salida-prolog=*)  R=${arg#--salida-prolog=}
                            OPCIONES="$OPCIONES,salida_prolog('$R')" ;;
        --labeling=*)       LB=${arg#--labeling=}
                            OPCIONES="$OPCIONES,labeling($LB)" ;;
        *)  echo "Opcion desconocida: $arg" >&2; exit 4 ;;
    esac
done

OPCIONES=$(printf '%s' "$OPCIONES" | sed 's/^,//')

GOAL="main_cli('$INSTANCIA','$SALIDA',estrategia($ESTRATEGIA,[$OPCIONES]))"

exec gprolog --quiet \
    --consult-file horarios.pl \
    --consult-file busqueda_bt.pl \
    --consult-file busqueda_fd.pl \
    --consult-file valida.pl \
    --consult-file main.pl \
    --entry-goal "$GOAL"
