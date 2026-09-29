% ============================================================
% busqueda_bt.pl -- Fase 2: sesiones, dominios, verificacion y
% estrategias de backtracking.
%
% Se carga despues de horarios.pl (usa sus hechos dinamicos):
%     :- include('busqueda_bt.pl').
%
% Estrategias:
%   bt_gp : generar y probar (linea base, sin ninguna poda)
%   bt    : verificacion anticipada. Opciones:
%             heuristica(original | grado | demanda | mrv)
%             simetria(si | no)
%             limite(N)            (maximo de nodos, por defecto 1000000)
%           mrv = forward checking + minimum remaining values
%           (desempate por grado).
%
% Resultado de resolver/3:
%   solucion(Horario) | sin_solucion(Razon) | limite_alcanzado
% Horario = lista de asignacion(Curso,Grupo,Prof,Aula,Dia,Franja,Dur),
% el mismo formato de la salida legible por maquina (seccion 6.5).
% ============================================================

:- dynamic(pos_dia/2).

% ------------------------------------------------------------
% Preparacion: posicion cronologica de cada dia (l=1, m=2, ...)
% ------------------------------------------------------------

preparar :-
    retractall(pos_dia(_, _)),
    findall(D, dia(D), Dias),
    numerar_dias(Dias, 1).

numerar_dias([], _).
numerar_dias([D|Ds], K) :-
    assertz(pos_dia(D, K)),
    K1 is K + 1,
    numerar_dias(Ds, K1).

tiempo(D, F, T) :-
    pos_dia(D, K),
    T is K * 1000 + F.

% ------------------------------------------------------------
% sesiones(-Lista)
% sesion(Id, Curso, Grupo, Indice, Profesor, Duracion)
% Un grupo con S sesiones semanales produce S terminos.
% ------------------------------------------------------------

sesiones(Lista) :-
    findall(g(C, G, Sem, Dur), grupo(C, G, _, _, Sem, Dur, _), Grupos),
    sesiones_de_grupos(Grupos, 1, Lista).

sesiones_de_grupos([], _, []).
sesiones_de_grupos([g(C, G, Sem, Dur)|Gs], Id0, Lista) :-
    profesor_de(C, G, P),
    sesiones_de_grupo(1, Sem, C, G, P, Dur, Id0, Id1, Lista, Resto),
    sesiones_de_grupos(Gs, Id1, Resto).

sesiones_de_grupo(I, Sem, _, _, _, _, Id, Id, L, L) :- I > Sem, !.
sesiones_de_grupo(I, Sem, C, G, P, Dur, Id0, Id, [sesion(Id0, C, G, I, P, Dur)|L], Resto) :-
    Id1 is Id0 + 1,
    I1 is I + 1,
    sesiones_de_grupo(I1, Sem, C, G, P, Dur, Id1, Id, L, Resto).

% Solo se usa el primer profesor declarado (extension: varios profesores).
profesor_de(C, G, P) :-
    (   imparte(C, G, P0) -> P = P0
    ;   throw(error_datos(sin_profesor(C, G)))
    ).

% ------------------------------------------------------------
% dominio(+Sesion, -Dominio)
% Lista de v(Aula, Dia, FranjaInicio) que ya cumplen: capacidad, tipo,
% aula_fija, prohibida y disponibilidad del profesor en TODAS las
% franjas que cubre la sesion (mas estricto que "en la franja de inicio").
% ------------------------------------------------------------

dominio(sesion(_, C, G, _, P, Dur), Dominio) :-
    grupo(C, G, _, Insc, _, _, Req),
    num_franjas(NF),
    UltimoInicio is NF - Dur + 1,
    findall(v(A, D, F),
            (   aula_candidata(C, G, Insc, Req, A),
                dia(D),
                between(1, UltimoInicio, F),
                \+ franja_prohibida(C, G, D, F, Dur),
                profesor_disponible(P, D, F, Dur)
            ),
            Dominio).

aula_candidata(C, G, Insc, Req, A) :-
    aula(A, Cap, Tipo),
    Cap >= Insc,
    tipo_compatible(Req, Tipo),
    (   aula_fija(C, G, _) -> aula_fija(C, G, A) ; true ).

tipo_compatible(laboratorio, laboratorio).
tipo_compatible(laboratorio, mixta).
tipo_compatible(teoria, teoria).
tipo_compatible(teoria, mixta).
tipo_compatible(mixta, _).

franja_prohibida(C, G, D, F, Dur) :-
    prohibida(C, G, D, FP),
    FP >= F,
    FP < F + Dur.

profesor_disponible(P, D, F, Dur) :-
    profesor(P, _, _, Disp),
    (   Disp == total -> true
    ;   Fin is F + Dur - 1,
        \+ ( between(F, Fin, Fk), \+ franja_cubierta(Disp, D, Fk) )
    ).

franja_cubierta(Disp, D, Fk) :-
    member(rango(D, Desde, Hasta), Disp),
    Fk >= Desde,
    Fk =< Hasta,
    !.

% ------------------------------------------------------------
% Conflictos entre dos sesiones ya asignadas (restricciones duras
% de a pares). Es lo que usa la busqueda con verificacion anticipada.
% ------------------------------------------------------------

solapan(F1, Dur1, F2, Dur2) :-
    F1 < F2 + Dur2,
    F2 < F1 + Dur1.

incompatibles(sesion(_, C1, G1, _, P1, Dur1), v(A1, Dia, F1),
              sesion(_, C2, G2, _, P2, Dur2), v(A2, Dia, F2)) :-
    solapan(F1, Dur1, F2, Dur2),
    (   A1 == A2                      % mismo aula
    ;   P1 == P2                      % mismo profesor
    ;   C1-G1 == C2-G2                % mismo grupo
    ;   excluyentes_par(C1, G1, C2, G2)
    ),
    !.

excluyentes_par(C1, G1, C2, G2) :-
    (   excluyentes(C1, G1, C2, G2)
    ;   excluyentes(C2, G2, C1, G1)
    ),
    !.

% Ruptura de simetria: las sesiones de un mismo grupo son intercambiables,
% asi que se exige que la de indice menor vaya antes en el tiempo.
% (No es una restriccion del problema: verifica/1 NO la exige.)
rompe_simetria(sesion(_, C, G, I1, _, _), v(_, D1, F1),
               sesion(_, C, G, I2, _, _), v(_, D2, F2)) :-
    I1 \== I2,
    tiempo(D1, F1, T1),
    tiempo(D2, F2, T2),
    (   I1 < I2 -> T1 >= T2 ; T1 =< T2 ).

inconsistente(Sim, S1, V1, S2, V2) :-
    (   incompatibles(S1, V1, S2, V2)
    ;   Sim == si, rompe_simetria(S1, V1, S2, V2)
    ),
    !.

% ------------------------------------------------------------
% Contadores (variables globales de GNU Prolog, no se deshacen
% al retroceder). Nodo = intento de asignar un valor a una sesion.
% Retroceso = intento cuya continuacion fallo.
% ------------------------------------------------------------

reiniciar_contadores(Limite) :-
    g_assign(nodos, 0),
    g_assign(retrocesos, 0),
    g_assign(limite, Limite).

contar_nodo :-
    g_inc(nodos),
    g_read(nodos, N),
    g_read(limite, L),
    (   N > L -> throw(limite_alcanzado) ; true ).

% Punto de eleccion unico de toda la busqueda: prueba cada valor del
% dominio y cuenta nodos y retrocesos.
elegir(V, Dom) :-
    member(V, Dom),
    contar_nodo,
    (   true
    ;   g_inc(retrocesos), fail
    ).

% ------------------------------------------------------------
% Estrategia 1: generar y probar
% Asigna TODAS las sesiones y solo entonces verifica con verifica/1.
% ------------------------------------------------------------

buscar(bt_gp, _Opc, Pares, Sol) :-
    generar(Pares, Sol),
    a_horario(Sol, Horario),
    verifica(Horario).

% ------------------------------------------------------------
% Estrategia 2: verificacion anticipada
% ------------------------------------------------------------

buscar(bt, Opc, Pares, Sol) :-
    opcion(heuristica, Opc, original, H),
    opcion(simetria, Opc, si, Sim),
    (   H == mrv
    ->  buscar_fc(Pares, Sim, Sol)
    ;   buscar_anticipada(Pares, Sim, [], Sol)
    ).

generar([], []).
generar([S-Dom|Resto], [S-V|Asig]) :-
    elegir(V, Dom),
    generar(Resto, Asig).

% Orden estatico; cada valor se compara contra lo ya asignado.
buscar_anticipada([], _, _, []).
buscar_anticipada([S-Dom|Resto], Sim, Prev, [S-V|Asig]) :-
    elegir(V, Dom),
    \+ ( member(S2-V2, Prev), inconsistente(Sim, S, V, S2, V2) ),
    buscar_anticipada(Resto, Sim, [S-V|Prev], Asig).

% Forward checking + MRV: tras cada asignacion se podan los dominios de las
% sesiones pendientes; si alguno queda vacio se retrocede de inmediato.
buscar_fc([], _, []).
buscar_fc([P|Ps], Sim, [S-V|Asig]) :-
    seleccionar_mrv([P|Ps], S-Dom, Resto),
    elegir(V, Dom),
    filtrar(Resto, S, V, Sim, Resto2),
    buscar_fc(Resto2, Sim, Asig).

seleccionar_mrv([P|Ps], Mejor, Resto) :-
    P = _-Dom,
    length(Dom, N),
    mejor_mrv(Ps, P, N, Mejor),
    quitar_par(Mejor, [P|Ps], Resto).

mejor_mrv([], M, _, M).
mejor_mrv([Q|Qs], M, N, Mejor) :-
    Q = _-DomQ,
    length(DomQ, NQ),
    (   NQ < N -> mejor_mrv(Qs, Q, NQ, Mejor)
    ;   mejor_mrv(Qs, M, N, Mejor)
    ).

quitar_par(S-_, [S2-D2|Ps], Resto) :-
    (   S == S2 -> Resto = Ps
    ;   Resto = [S2-D2|R], quitar_par(S-_, Ps, R)
    ).

filtrar([], _, _, _, []).
filtrar([T-Dom|Resto], S, V, Sim, [T-Dom2|Resto2]) :-
    filtrar_dominio(Dom, S, V, T, Sim, Dom2),
    Dom2 \== [],
    filtrar(Resto, S, V, Sim, Resto2).

filtrar_dominio([], _, _, _, _, []).
filtrar_dominio([W|Ws], S, V, T, Sim, Dom2) :-
    (   inconsistente(Sim, S, V, T, W) -> Dom2 = Resto
    ;   Dom2 = [W|Resto]
    ),
    filtrar_dominio(Ws, S, V, T, Sim, Resto).

% ------------------------------------------------------------
% Heuristicas de orden de variable (estaticas)
% ------------------------------------------------------------

ordenar(original, Pares, Pares) :- !.
ordenar(mrv, Pares, Ordenados) :- !,      % el orden inicial desempata por grado
    ordenar(grado, Pares, Ordenados).
ordenar(Criterio, Pares, Ordenados) :-
    sesiones_de_pares(Pares, Todas),
    claves(Pares, Criterio, Todas, Claves),
    keysort(Claves, Ord0),
    valores(Ord0, Ordenados).

sesiones_de_pares([], []).
sesiones_de_pares([S-_|Ps], [S|Ss]) :- sesiones_de_pares(Ps, Ss).

claves([], _, _, []).
claves([S-Dom|Ps], Criterio, Todas, [K-(S-Dom)|Ks]) :-
    clave(Criterio, S, Todas, K),
    claves(Ps, Criterio, Todas, Ks).

% Mayor grado primero (mas sesiones con las que puede chocar)
clave(grado, sesion(Id, C, G, _, P, _), Todas, k(NegGrado, Id)) :-
    findall(x,
            (   member(sesion(Id2, C2, G2, _, P2, _), Todas),
                Id2 \== Id,
                relacionadas(C, G, P, C2, G2, P2)
            ),
            L),
    length(L, Grado),
    NegGrado is -Grado.
% Mas inscritos primero, luego mayor duracion
clave(demanda, sesion(Id, C, G, _, _, Dur), _, k(NegInsc, NegDur, Id)) :-
    grupo(C, G, _, Insc, _, _, _),
    NegInsc is -Insc,
    NegDur is -Dur.

relacionadas(C, G, _, C, G, _) :- !.
relacionadas(_, _, P, _, _, P) :- !.
relacionadas(C1, G1, _, C2, G2, _) :- excluyentes_par(C1, G1, C2, G2).

valores([], []).
valores([_-V|Ps], [V|Vs]) :- valores(Ps, Vs).

% ------------------------------------------------------------
% resolver(+Estrategia, -Horario)          falla si no hay solucion
% resolver(+Estrategia, +Opciones, -Resultado)
% ------------------------------------------------------------

resolver(Estrategia, Horario) :-
    resolver(Estrategia, [], solucion(Horario)).

resolver(Estrategia, Opciones, Resultado) :-
    preparar,
    opcion(limite, Opciones, 1000000, Limite),
    opcion(heuristica, Opciones, original, Heur),
    reiniciar_contadores(Limite),
    sesiones(Sesiones),
    (   diagnostico_previo(Sesiones, Razon)
    ->  Resultado = sin_solucion(Razon),
        guardar_tiempos(0, 0)
    ;   pares_con_dominio(Sesiones, Pares0),
        ordenar(Heur, Pares0, Pares),
        statistics(cpu_time, [C0|_]),
        statistics(real_time, [R0|_]),
        catch(( buscar(Estrategia, Opciones, Pares, Sol)
              ->  a_horario(Sol, Horario),
                  Resultado = solucion(Horario)
              ;   Resultado = sin_solucion(espacio_agotado)
              ),
              limite_alcanzado,
              Resultado = limite_alcanzado),
        statistics(cpu_time, [C1|_]),
        statistics(real_time, [R1|_]),
        Cpu is C1 - C0,
        Real is R1 - R0,
        guardar_tiempos(Cpu, Real)
    ).

pares_con_dominio([], []).
pares_con_dominio([S|Ss], [S-Dom|Ps]) :-
    dominio(S, Dom),
    pares_con_dominio(Ss, Ps).

% Razones por las que es imposible sin buscar nada
diagnostico_previo(Sesiones, dominio_vacio(C, G, I)) :-
    member(S, Sesiones),
    S = sesion(_, C, G, I, _, _),
    dominio(S, []),
    !.
diagnostico_previo(Sesiones, carga_profesor(P, Carga, Max)) :-
    profesor(P, _, Max, _),
    findall(Dur, member(sesion(_, _, _, _, P, Dur), Sesiones), Ds),
    suma(Ds, Carga),
    Carga > Max,
    !.

guardar_tiempos(Cpu, Real) :-
    g_assign(t_cpu, Cpu),
    g_assign(t_real, Real).

% estadisticas(est(Nodos, Retrocesos, CpuMs, RealMs))
estadisticas(est(N, R, C, W)) :-
    g_read(nodos, N),
    g_read(retrocesos, R),
    g_read(t_cpu, C),
    g_read(t_real, W).

opcion(Clave, Opciones, Defecto, Valor) :-
    Term =.. [Clave, V],
    (   member(Term, Opciones) -> Valor = V ; Valor = Defecto ).

suma([], 0).
suma([X|Xs], S) :- suma(Xs, S0), S is S0 + X.

% ------------------------------------------------------------
% Conversion a horario (ordenado por curso, grupo, dia y franja)
% ------------------------------------------------------------

a_horario(Sol, Horario) :-
    claves_horario(Sol, Claves),
    keysort(Claves, Ord),
    valores(Ord, Horario).

claves_horario([], []).
claves_horario([sesion(_, C, G, _, P, Dur)-v(A, D, F)|Rs],
               [k(C, G, K, F)-asignacion(C, G, P, A, D, F, Dur)|Ks]) :-
    pos_dia(D, K),
    claves_horario(Rs, Ks).

mostrar_horario(Horario) :-
    write('Curso   Grupo Prof  Aula  Dia Franjas'), nl,
    forall(member(asignacion(C, G, P, A, D, F, Dur), Horario),
           (   Fin is F + Dur - 1,
               write(C), write('  '), write(G), write('  '), write(P), write('  '),
               write(A), write('  '), write(D), write('  '),
               write(F), write('-'), write(Fin), nl
           )).

% ------------------------------------------------------------
% verifica(+Horario)
% Comprobacion INDEPENDIENTE de la busqueda: expande cada asignacion a
% celdas (recurso, dia, franja) y busca celdas repetidas, en vez de
% comparar intervalos de a pares. violaciones/2 lista lo que falla.
% ------------------------------------------------------------

verifica(Horario) :- violaciones(Horario, []).

violaciones(H, Vs) :-
    celdas(H, Celdas),
    findall(V, violacion(H, Celdas, V), Vs0),
    sort(Vs0, Vs).

celdas(H, Celdas) :-
    findall(c(T, R, D, F),
            (   member(asignacion(C, G, P, A, D, F0, Dur), H),
                Fin is F0 + Dur - 1,
                between(F0, Fin, F),
                (   T = aula, R = A
                ;   T = profesor, R = P
                ;   T = grupo, R = C-G
                )
            ),
            Celdas).

% cada grupo tiene sus sesiones semanales
violacion(H, _, sesiones_incorrectas(C, G, Esperadas, Reales)) :-
    grupo(C, G, _, _, Esperadas, _, _),
    findall(x, member(asignacion(C, G, _, _, _, _, _), H), L),
    length(L, Reales),
    Reales =\= Esperadas.
% la asignacion es coherente con los datos (grupo, profesor, duracion, aula)
violacion(H, _, asignacion_invalida(C, G, P, A)) :-
    member(asignacion(C, G, P, A, _, _, Dur), H),
    (   \+ ( grupo(C, G, _, _, _, Dur, _), imparte(C, G, P) )
    ;   \+ aula(A, _, _)
    ).
% dentro del rango de dias y franjas
violacion(H, _, fuera_de_rango(C, G, D, F)) :-
    member(asignacion(C, G, _, _, D, F, Dur), H),
    num_franjas(NF),
    (   \+ dia(D) ; F < 1 ; F + Dur - 1 > NF ).
% capacidad
violacion(H, _, capacidad(C, G, A)) :-
    member(asignacion(C, G, _, A, _, _, _), H),
    grupo(C, G, _, Insc, _, _, _),
    aula(A, Cap, _),
    Insc > Cap.
% tipo de aula
violacion(H, _, tipo_aula(C, G, A)) :-
    member(asignacion(C, G, _, A, _, _, _), H),
    grupo(C, G, _, _, _, _, Req),
    aula(A, _, Tipo),
    \+ tipo_compatible(Req, Tipo).
% disponibilidad del profesor
violacion(H, _, disponibilidad(P, D, F)) :-
    member(asignacion(_, _, P, _, D, F, Dur), H),
    \+ profesor_disponible(P, D, F, Dur).
% maximo de franjas del profesor
violacion(H, _, max_franjas(P, Carga, Max)) :-
    profesor(P, _, Max, _),
    findall(Dur, member(asignacion(_, _, P, _, _, _, Dur), H), Ds),
    suma(Ds, Carga),
    Carga > Max.
% aula_fija
violacion(H, _, aula_fija(C, G, A)) :-
    aula_fija(C, G, _),
    member(asignacion(C, G, _, A, _, _, _), H),
    \+ aula_fija(C, G, A).
% prohibida
violacion(H, _, prohibida(C, G, D, FP)) :-
    prohibida(C, G, D, FP),
    member(asignacion(C, G, _, _, D, F, Dur), H),
    FP >= F,
    FP < F + Dur.
% solapamientos de aula, profesor y grupo (celdas repetidas)
violacion(_, Celdas, solape(T, R, D, F)) :-
    msort(Celdas, Ord),
    duplicado(Ord, c(T, R, D, F)).
% excluyentes
violacion(_, Celdas, excluyentes(C1, G1, C2, G2, D, F)) :-
    excluyentes(C1, G1, C2, G2),
    member(c(grupo, C1-G1, D, F), Celdas),
    member(c(grupo, C2-G2, D, F), Celdas).

duplicado([X, Y|_], X) :- X == Y.
duplicado([_|R], X) :- duplicado(R, X).
