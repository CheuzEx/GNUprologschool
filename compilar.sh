#!/bin/sh
# compilar.sh -- compila el proyecto a un ejecutable nativo con gplc
#
#   ./compilar.sh                 genera ./horarios_nativo
#   ./compilar.sh otro_nombre     genera ./otro_nombre

SALIDA=${1:-horarios_nativo}

if ! command -v gplc >/dev/null 2>&1; then
    echo "gplc no esta instalado (sudo apt install gprolog)" >&2
    exit 1
fi

gplc --no-top-level -o "$SALIDA" \
    horarios.pl busqueda_bt.pl busqueda_fd.pl valida.pl main.pl nativo.pl
ESTADO=$?

if [ $ESTADO -eq 0 ]; then
    echo "Compilado: ./$SALIDA"
else
    echo "gplc fallo con codigo $ESTADO" >&2
fi
exit $ESTADO
