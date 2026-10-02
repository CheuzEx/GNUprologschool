% nativo.pl -- punto de entrada para el ejecutable nativo (gplc)
%
% Un ejecutable de gplc no acepta --entry-goal, asi que initialization/1
% lee la linea de comandos con argument_list/1 y llama a main_cli/3.
% Misma interfaz que horarios.sh:
%
%   ./horarios_nativo instancia.dat salida.txt <bt|bt_gp|clpfd> [opciones]
%
% No consultar este archivo en el interprete: al cargarlo se ejecuta
% nativo/0, que termina con halt/1.

:- initialization(nativo).

nativo :-
    argument_list(Args),
    (   Args = [Instancia, Salida, Estrategia|Resto],
        atom(Estrategia)
    ->  (   catch(leer_opciones(Resto, Opciones), _, fail)
        ->  main_cli(Instancia, Salida, estrategia(Estrategia, Opciones))
        ;   uso, halt(4)
        )
    ;   uso, halt(4)
    ),
    halt(1).

leer_opciones([], []).
leer_opciones([A|As], [O|Os]) :-
    opcion_cli(A, O),
    leer_opciones(As, Os).

% Falla si el argumento es desconocido.
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

% Solo digitos decimales: number_codes/2 aceptaria 0x10 o 0'a.
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
