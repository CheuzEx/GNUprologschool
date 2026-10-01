% ============================================================
% nativo.pl -- punto de entrada para el ejecutable nativo (gplc)
%
% Un ejecutable compilado con gplc NO acepta --entry-goal (eso es una
% opcion del interprete gprolog). En su lugar, este archivo define una
% directiva initialization/1 que lee la linea de comandos con
% argument_list/1 y llama a main/3 de main.pl.
%
% La interfaz es la MISMA que la de horarios.sh:
%
%   ./horarios_nativo instancia.dat salida.txt <bt|bt_gp|clpfd> [opciones]
%
% Opciones (iguales a las de horarios.sh):
%   --heuristica=H   --simetria=S   --limite=N   --optimizar
%   --por-aula       --salida-prolog=RUTA        --labeling=propio|fd
%
% Compilar con ./compilar.sh (o ver la orden gplc en ese script).
% Codigos de salida: los de main.pl (0..4); 4 si los argumentos son
% incorrectos.
%
% NO cargar este archivo en el interprete (consult): al cargarlo se
% ejecutaria nativo/0, que termina con halt/1. horarios.sh no lo usa.
% ============================================================

:- initialization(nativo).

nativo :-
    argument_list(Args),
    (   Args = [Instancia, Salida, Estrategia|Resto],
        atom(Estrategia)
    ->  (   catch(leer_opciones(Resto, Opciones), _, fail)
        ->  main(Instancia, Salida, estrategia(Estrategia, Opciones))
        ;   uso, halt(4)
        )
    ;   uso, halt(4)
    ),
    halt(1).                      % main/3 siempre termina con halt/1

% leer_opciones(+Argumentos, -Opciones): falla si alguno es desconocido
leer_opciones([], []).
leer_opciones([A|As], [O|Os]) :-
    opcion_cli(A, O),
    leer_opciones(As, Os).

% opcion_cli(+Argumento, -Opcion): misma traduccion que horarios.sh
opcion_cli(Arg, Opcion) :-
    (   atom_concat('--heuristica=', V, Arg) -> Opcion = heuristica(V)
    ;   atom_concat('--simetria=', V, Arg)   -> Opcion = simetria(V)
    ;   atom_concat('--limite=', V, Arg)     -> entero_positivo(V, N),
                                                Opcion = limite(N)
    ;   Arg == '--optimizar'                 -> Opcion = optimizar
    ;   Arg == '--por-aula'                  -> Opcion = por_aula
    ;   atom_concat('--salida-prolog=', V, Arg) -> Opcion = salida_prolog(V)
    ;   atom_concat('--labeling=', V, Arg)   -> Opcion = labeling(V)
    ).

% Solo digitos decimales y > 0 (evita que number_codes acepte 0x10, 0'a, ...)
entero_positivo(Atom, N) :-
    atom_codes(Atom, Codigos),
    Codigos \== [],
    solo_digitos(Codigos),
    number_codes(N, Codigos),
    N > 0.

solo_digitos([]).
solo_digitos([C|Cs]) :- C >= 0'0, C =< 0'9, solo_digitos(Cs).

uso :-
    format(user_error, "Uso: horarios_nativo <instancia.dat> <salida.txt> <bt|bt_gp|clpfd> [opciones...]~n", []),
    format(user_error, "  --heuristica=H     (original|mrv|grado|demanda|ff|ffc|lcv)~n", []),
    format(user_error, "  --simetria=si|no|intra|inter~n", []),
    format(user_error, "  --limite=N~n", []),
    format(user_error, "  --optimizar~n", []),
    format(user_error, "  --por-aula~n", []),
    format(user_error, "  --salida-prolog=RUTA~n", []),
    format(user_error, "  --labeling=propio|fd~n", []).
