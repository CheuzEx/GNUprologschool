% ============================================================
% valida.pl -- validacion de instancia con numeros de linea
% Cubre los 9 errores exigidos por la seccion 5.9 del PDF.
% Se consulta DESPUES de horarios.pl y ANTES de main.pl.
%
% Usa de horarios.pl: leer_lineas/2, clasificar_linea/2, split_on/3,
%   normalizar_id/2, parsear_disponibilidad/2, extraer_dia_franja_atom/3
% ============================================================

valida(Path) :-
    leer_lineas(Path, Lineas),
    validar_lineas(Lineas, Errores),
    (   Errores == []
    ->  true
    ;   reportar(Errores),
        throw(errores_instancia(Errores))
    ).

% ------------------------------------------------------------
% Recoleccion + validacion
% ------------------------------------------------------------
validar_lineas(Lineas, Errores) :-
    recolectar(Lineas, 1, ninguna, Registros, ErroresEstruct),
    validar_secciones_duplicadas(Lineas, ErroresSecc),
    validar_config(Registros, ErroresConfig),
    universo(Registros, U),
    validar_datos(Registros, U, ErroresDatos),
    validar_duplicados(Registros, ErroresDup),
    validar_cobertura_imparte(Registros, ErroresImp),
    append([ErroresEstruct, ErroresSecc, ErroresConfig, ErroresDatos,
            ErroresDup, ErroresImp], Todos),
    append(Todos, Errores0),
    sort(Errores0, Errores).

% ------------------------------------------------------------
% Pase 1: recolectar registros y errores estructurales
% ------------------------------------------------------------
recolectar([], _, _, [], []).
recolectar([L|Ls], N, Secc, Rs, Es) :-
    clasificar_linea(L, T),
    recolectar_tipo(T, Ls, N, Secc, Rs, Es).

recolectar_tipo(blanco,    Ls, N, S, Rs, Es) :- !,
    N1 is N+1, recolectar(Ls, N1, S, Rs, Es).
recolectar_tipo(comentario,Ls, N, S, Rs, Es) :- !,
    N1 is N+1, recolectar(Ls, N1, S, Rs, Es).
recolectar_tipo(seccion(S),Ls, N, _, Rs, Es) :- !,
    N1 is N+1,
    (   seccion_conocida(S)
    ->  recolectar(Ls, N1, S, Rs, Es)
    ;   recolectar(Ls, N1, desconocida, Rs,
                   [linea(N, seccion_desconocida(S))|Es])
    ).
% los registros de una seccion desconocida se ignoran (ya se reporto la seccion)
recolectar_tipo(registro(_), Ls, N, desconocida, Rs, Es) :- !,
    N1 is N+1,
    recolectar(Ls, N1, desconocida, Rs, Es).
recolectar_tipo(registro(_), Ls, N, ninguna, Rs, Es) :- !,
    N1 is N+1,
    recolectar(Ls, N1, ninguna, Rs, [linea(N, registro_sin_seccion)|Es]).
recolectar_tipo(registro(C), Ls, N, S, [reg(S,N,C)|Rs], Es) :-
    N1 is N+1,
    recolectar(Ls, N1, S, Rs, Es).

seccion_conocida('CONFIG').    seccion_conocida('AULA').
seccion_conocida('PROFESOR').  seccion_conocida('CURSO').
seccion_conocida('IMPARTE').   seccion_conocida('RESTRICCION').

% Un encabezado de seccion puede aparecer a lo sumo una vez (5.1)
validar_secciones_duplicadas(Lineas, Errores) :-
    encabezados(Lineas, 1, Encs),
    findall(linea(N, seccion_duplicada(S)),
            ( member(S-N, Encs), member(S-N2, Encs), N2 < N ),
            Errores0),
    sort(Errores0, Errores).

encabezados([], _, []).
encabezados([L|Ls], N, Encs) :-
    clasificar_linea(L, T),
    N1 is N+1,
    (   T = seccion(S)
    ->  Encs = [S-N|Resto]
    ;   Encs = Resto
    ),
    encabezados(Ls, N1, Resto).

% ------------------------------------------------------------
% Pase 2: CONFIG (todas las claves obligatorias, exactamente una vez)
% ------------------------------------------------------------
validar_config(Registros, Errores) :-
    findall(N-C, member(reg('CONFIG',N,C), Registros), Configs),
    findall(linea(N,R), ( member(N-C, Configs), err_config(C, R), R \== ok ),
            ErroresLin),
    findall(K, member(_-[K,_], Configs), Claves),
    claves_obligatorias(Req),
    findall(linea(0, clave_config_faltante(K)),
            ( member(K, Req), \+ member(K, Claves) ), Falt),
    findall(linea(0, clave_config_duplicada(K)),
            ( member(K, Req), count_occ(K, Claves, Cnt), Cnt > 1 ), Dup),
    append(ErroresLin, Falt, A),
    append(A, Dup, Errores).

claves_obligatorias([dias, franjas, inicio, duracion_franja]).

count_occ(_, [], 0).
count_occ(X, [X|Xs], N) :- !, count_occ(X, Xs, N0), N is N0+1.
count_occ(X, [_|Xs], N) :- count_occ(X, Xs, N).

err_config([dias, V], R) :- !,
    (   V == '' -> R = dias_vacio
    ;   dias_atom_valido(V) -> R = ok
    ;   R = dias_invalido(V)
    ).
err_config([franjas, V], R) :- !,
    (   int_positivo(V, _) -> R = ok ; R = franjas_invalida(V) ).
err_config([inicio, V], R) :- !,
    (   hora_valida(V) -> R = ok ; R = inicio_invalido(V) ).
err_config([duracion_franja, V], R) :- !,
    (   int_positivo(V, _) -> R = ok ; R = duracion_invalida(V) ).
err_config([K,_], R) :- atom(K), !,
    R = clave_config_desconocida(K).
err_config(C, aridad_config(C)).

% exactamente 1 caracter (no espacio) por dia
dias_atom_valido(Atom) :-
    atom_chars(Atom, Chars),
    split_on(',', Chars, Listas),
    Listas \== [],
    forall(member(L, Listas),
           (   L = [C], C \== ' ' )).

hora_valida(Atom) :-
    atom_chars(Atom, Cs),
    Cs = [H1, H2, ':', M1, M2],
    digit(H1), digit(H2), digit(M1), digit(M2),
    atom_chars(HA, [H1,H2]), safe_int(HA, H),
    atom_chars(MA, [M1,M2]), safe_int(MA, M),
    H >= 0, H =< 23, M >= 0, M =< 59.

% CORREGIDO: atom_chars entrega caracteres ('0'), no codigos; hay que
% convertirlos antes de comparar (antes lanzaba type_error(evaluable,...)).
digit(C) :-
    char_code(C, K),
    K >= 0'0, K =< 0'9.

% ------------------------------------------------------------
% Universo de entidades declaradas (para validar referencias)
% Los ids se guardan NORMALIZADOS (a_101, p_001, ic_1802-c1), que es
% lo que horarios.pl asserta despues.
%   u(Dias, NF, Aulas, Profs, Grupos, Durs)   Durs = [C-G-Dur, ...]
% ------------------------------------------------------------
universo(Registros, u(Dias, NF, Aulas, Profs, Grupos, Durs)) :-
    (   member(reg('CONFIG',_,[dias, DAtom]), Registros), DAtom \== ''
    ->  dias_del_atom(DAtom, Dias0), sort(Dias0, Dias)
    ;   Dias = []
    ),
    (   member(reg('CONFIG',_,[franjas, FAtom]), Registros),
        int_positivo(FAtom, NF0)
    ->  NF = NF0
    ;   NF = 0
    ),
    findall(AN, (member(reg('AULA',_,[A|_]), Registros),
                 normalizar_id(A, AN)), Aulas0),
    sort(Aulas0, Aulas),
    findall(PN, (member(reg('PROFESOR',_,[P|_]), Registros),
                 normalizar_id(P, PN)), Profs0),
    sort(Profs0, Profs),
    findall(CN-GN, (member(reg('CURSO',_,[C,G|_]), Registros),
                    normalizar_id(C, CN), normalizar_id(G, GN)), Grupos0),
    sort(Grupos0, Grupos),
    findall(CN-GN-Dur,
            ( member(reg('CURSO',_,[C,G,_,_,_,DurA|_]), Registros),
              int_positivo(DurA, Dur),
              normalizar_id(C, CN), normalizar_id(G, GN) ),
            Durs).

dias_del_atom(Atom, Dias) :-
    atom_chars(Atom, Chars),
    split_on(',', Chars, Listas),
    findall(D, (member(L, Listas), L \== [],
                atom_chars(A, L), normalizar_id(A, D)),
            Dias).

% ------------------------------------------------------------
% Pase 3: cada registro de datos
% ------------------------------------------------------------
validar_datos(Registros, U, Errores) :-
    findall(linea(N,R),
            ( member(reg(S,N,Campos), Registros),
              S \== 'CONFIG',
              err_dato(S, Campos, N, U, R),
              R \== ok
            ),
            Errores).

err_dato('AULA', [Cod, Cap, Tipo], _N, _U, R) :- !,
    (   atom(Cod), Cod \== '',
        int_no_neg(Cap, _),
        tipo_valido(Tipo)
    ->  R = ok
    ;   R = aula_invalida(Cod, Cap, Tipo)
    ).

err_dato('PROFESOR', [Cod, Nom, Max, Disp], _N, U, R) :- !,
    U = u(Dias, NF, _, _, _, _),
    (   atom(Cod), Cod \== '',
        atom(Nom),
        int_no_neg(Max, _),
        disponibilidad_valida(Disp, Dias, NF)
    ->  R = ok
    ;   R = profesor_invalido(Cod)
    ).

err_dato('CURSO', [C,G,Nom,Insc,Sem,Dur,Req], _N, U, R) :- !,
    U = u(_, NF, _, _, _, _),
    (   atom(C), atom(G), atom(Nom),
        int_positivo(Insc, _),
        int_positivo(Sem, _),
        int_positivo(Dur, DurN),
        tipo_valido(Req)
    ->  (   NF > 0, DurN > NF
        ->  R = duracion_excede_franjas(C-G, DurN, NF)
        ;   R = ok
        )
    ;   R = curso_invalido(C-G)
    ).

err_dato('IMPARTE', [C,G,P], _N, U, R) :- !,
    normalizar_id(C,CN), normalizar_id(G,GN), normalizar_id(P,PN),
    U = u(_, _, _, Profs, Grupos, _),
    (   \+ member(CN-GN, Grupos) -> R = grupo_inexistente(CN-GN)
    ;   \+ member(PN, Profs)     -> R = profesor_inexistente(PN)
    ;   R = ok
    ).

err_dato('RESTRICCION', [Tipo|Args], _N, U, R) :- !,
    err_restriccion(Tipo, Args, U, R).

err_dato(S, Campos, _N, _U, aridad_invalida(S, Campos)).

err_restriccion(aula_fija, [C,G,A], U, R) :- !,
    normalizar_id(C,CN), normalizar_id(G,GN), normalizar_id(A,AN),
    U = u(_, _, Aulas, _, Grupos, _),
    (   \+ member(CN-GN, Grupos) -> R = grupo_inexistente(CN-GN)
    ;   \+ member(AN, Aulas)     -> R = aula_inexistente(AN)
    ;   R = ok
    ).

err_restriccion(prohibida, [C,G,DF], U, R) :- !,
    normalizar_id(C,CN), normalizar_id(G,GN),
    U = u(Dias, NF, _, _, Grupos, _),
    (   \+ member(CN-GN, Grupos) -> R = grupo_inexistente(CN-GN)
    ;   dia_franja_valida(DF, Dias, NF) -> R = ok
    ;   R = dia_franja_invalida(DF)
    ).

err_restriccion(excluyentes, [C1,G1,C2,G2], U, R) :- !,
    normalizar_id(C1,C1N), normalizar_id(G1,G1N),
    normalizar_id(C2,C2N), normalizar_id(G2,G2N),
    U = u(_,_,_,_,Grupos,_),
    (   \+ member(C1N-G1N, Grupos) -> R = grupo_inexistente(C1N-G1N)
    ;   \+ member(C2N-G2N, Grupos) -> R = grupo_inexistente(C2N-G2N)
    ;   R = ok
    ).

% prefiere: ademas de dia/franja validos, la sesion que EMPIEZA en esa
% franja no puede exceder la ultima franja del dia (5.9, ultimo error).
err_restriccion(prefiere, [C,G,DF,W], U, R) :- !,
    normalizar_id(C,CN), normalizar_id(G,GN),
    U = u(Dias, NF, _, _, Grupos, Durs),
    (   \+ member(CN-GN, Grupos) -> R = grupo_inexistente(CN-GN)
    ;   \+ dia_franja_valida(DF, Dias, NF) -> R = dia_franja_invalida(DF)
    ;   \+ int_no_neg(W, _) -> R = peso_invalido(W)
    ;   extraer_dia_franja_atom(DF, _, F),
        member(CN-GN-Dur, Durs),
        F + Dur - 1 > NF -> R = sesion_excede_dia(DF, Dur, NF)
    ;   R = ok
    ).

err_restriccion(compacta, [C,G,W], U, R) :- !,
    normalizar_id(C,CN), normalizar_id(G,GN),
    U = u(_, _, _, _, Grupos, _),
    (   \+ member(CN-GN, Grupos) -> R = grupo_inexistente(CN-GN)
    ;   \+ int_no_neg(W, _) -> R = peso_invalido(W)
    ;   R = ok
    ).

err_restriccion(T, A, _, aridad_restriccion(T, A)).

% ------------------------------------------------------------
% Pase 4: duplicados (curso, grupo), aulas y profesores
% ------------------------------------------------------------
validar_duplicados(Registros, Errores) :-
    findall(CN-GN-N, (member(reg('CURSO',N,[C,G|_]), Registros),
                      normalizar_id(C,CN), normalizar_id(G,GN)),
            Lista),
    findall(linea(N, par_duplicado(CG)),
            ( member(CG-N, Lista),
              member(CG2-N2, Lista),
              CG2 == CG, N2 < N
            ),
            Errores0),
    duplicados_id('AULA', aula_duplicada, Registros, ErrAulas),
    duplicados_id('PROFESOR', profesor_duplicado, Registros, ErrProfs),
    append([Errores0, ErrAulas, ErrProfs], Todos),
    sort(Todos, Errores).

duplicados_id(Seccion, Etiqueta, Registros, Errores) :-
    findall(Id-N, ( member(reg(Seccion,N,[Cod|_]), Registros),
                    normalizar_id(Cod, Id) ), Lista),
    findall(linea(N, Termino),
            ( member(Id-N, Lista), member(Id-N2, Lista), N2 < N,
              Termino =.. [Etiqueta, Id] ),
            Errores0),
    sort(Errores0, Errores).

% ------------------------------------------------------------
% Pase 5: todo grupo debe tener al menos un profesor en IMPARTE (5.6)
% ------------------------------------------------------------
validar_cobertura_imparte(Registros, Errores) :-
    findall(linea(N, grupo_sin_profesor(CN-GN)),
            ( member(reg('CURSO',N,[C,G|_]), Registros),
              normalizar_id(C, CN), normalizar_id(G, GN),
              \+ ( member(reg('IMPARTE',_,[C2,G2|_]), Registros),
                   normalizar_id(C2, CN), normalizar_id(G2, GN) )
            ),
            Errores0),
    sort(Errores0, Errores).

% ------------------------------------------------------------
% Predicados auxiliares
% ------------------------------------------------------------
tipo_valido(teoria). tipo_valido(laboratorio). tipo_valido(mixta).

% Solo digitos decimales: rechaza vacios, negativos, decimales y
% sintaxis que number_codes/2 aceptaria (0x10, 0'a, 1.0e3, ...).
safe_int(Atom, N) :-
    atom(Atom), Atom \== '',
    atom_chars(Atom, Cs),
    forall(member(C, Cs), digit(C)),
    catch((atom_codes(Atom, Codes), number_codes(N, Codes)), _, fail),
    integer(N).

int_positivo(A, N) :- safe_int(A, N), N > 0.
int_no_neg(A, N)  :- safe_int(A, N), N >= 0.

% disponibilidad: dias declarados en CONFIG y franjas dentro de 1..NF
disponibilidad_valida('', _, _) :- !.
disponibilidad_valida(Atom, Dias, NF) :-
    NF > 0,
    catch(parsear_disponibilidad(Atom, Rangos), _, fail),
    is_list(Rangos),
    forall(member(rango(D, F0, F1), Rangos),
           ( member(D, Dias), integer(F0), integer(F1),
             F0 >= 1, F0 =< F1, F1 =< NF )).

dia_franja_valida(Atom, Dias, NF) :-
    NF > 0,
    catch(extraer_dia_franja_atom(Atom, D, F), _, fail),
    member(D, Dias), integer(F), F >= 1, F =< NF.

% ------------------------------------------------------------
% Reporte de errores
% ------------------------------------------------------------
reportar(Errores) :-
    length(Errores, N),
    format(user_error, "Instancia invalida: ~w error(es)~n", [N]),
    forall(member(E, Errores), reportar_uno(E)).

reportar_uno(linea(0, R)) :- !,
    format(user_error, "  (global): ~w~n", [R]).
reportar_uno(linea(N, R)) :- !,
    format(user_error, "  linea ~w: ~w~n", [N, R]).
reportar_uno(Otro) :-
    format(user_error, "  ~w~n", [Otro]).
