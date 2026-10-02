main(Instancia, Salida, Estrategia) :-
    catch(
        ejecutar(Instancia, Salida, Estrategia),
        Error,
        abortar(Error, Instancia, Salida, Estrategia)
    ), !.
main(_, _, _) :-
    format(user_error, "ERROR: la ejecucion fallo sin producir resultado~n", []),
    halt(1).

ejecutar(Instancia, Salida, Estrategia) :-
    interpretar_estrategia(Estrategia, Est, Opc),
    cargar_instancia_segura(Instancia),
    resolver(Est, Opc, Resultado0),
    ordenar_resultado(Resultado0, Resultado),
    escribir_salida(Salida, Instancia, Est, Opc, Resultado),
    escribir_salida_prolog(Opc, Resultado),
    codigo_resultado(Resultado, Codigo),
    halt(Codigo).

ordenar_resultado(solucion(H0), solucion(H)) :- !,
    ordenar_asignaciones(H0, H).
ordenar_resultado(R, R).

% Orden: curso, grupo, posicion del dia segun CONFIG, franja.
ordenar_asignaciones(H0, H) :-
    findall(D, dia(D), Dias),
    findall(k(C,G,I,F)-asignacion(C,G,P,A,D,F,Dur),
            ( member(asignacion(C,G,P,A,D,F,Dur), H0),
              pos_dia(D, Dias, I) ),
            Pares),
    keysort(Pares, Ordenados),
    valores_de(Ordenados, H).

pos_dia(D, [D|_], 1) :- !.
pos_dia(D, [_|R], I) :- pos_dia(D, R, I0), I is I0 + 1.

valores_de([], []).
valores_de([_-V|R], [V|Vs]) :- valores_de(R, Vs).

interpretar_estrategia(estrategia(Est, Opc), Est, Opc) :- !.
interpretar_estrategia([Est|Opc], Est, Opc) :- !, atom(Est).
interpretar_estrategia(Est, Est, []) :- atom(Est), !.
interpretar_estrategia(E, _, _) :- throw(error_argumentos(estrategia(E))).

cargar_instancia_segura(Instancia) :-
    (   catch(open(Instancia, read, S), _, fail)
    ->  close(S)
    ;   throw(error_instancia(no_legible(Instancia)))
    ),
    catch(valida(Instancia), E1, throw(error_instancia(invalida(E1)))),
    catch(cargar_instancia(Instancia), E2,
          throw(error_instancia(sintaxis(E2)))).

codigo_resultado(solucion(_),           0) :- !.
codigo_resultado(sin_solucion(_),       1) :- !.
codigo_resultado(limite_alcanzado,      3) :- !.
codigo_resultado(instancia_invalida(_), 2) :- !.
codigo_resultado(_,                     1).

codigo_error(error_instancia(_),  2) :- !.
codigo_error(error_argumentos(_), 4) :- !.
codigo_error(error_escritura(_),  4) :- !.
codigo_error(_,                   2).

abortar(Error, Instancia, Salida, Estrategia) :-
    format(user_error, "ERROR: ~w~n", [Error]),
    (   Error = error_instancia(_)
    ->  (   catch(interpretar_estrategia(Estrategia, Est, Opc), _, fail)
        ->  true
        ;   Est = desconocida, Opc = []
        ),
        catch(escribir_salida(Salida, Instancia, Est, Opc,
                              instancia_invalida(Error)),
              _, true)
    ;   true
    ),
    codigo_error(Error, Codigo),
    halt(Codigo).

% ------------------------------------------------------------
% Archivo de salida
% ------------------------------------------------------------
escribir_salida(Archivo, Instancia, Est, Opc, Resultado) :-
    (   catch(open(Archivo, write, S), _, fail)
    ->  true
    ;   throw(error_escritura(Archivo))
    ),
    catch(
        ( escribir_encabezado(S, Instancia, Est, Opc, Resultado),
          escribir_bloques(S, Opc, Resultado)
        ),
        E,
        ( close(S), throw(error_escritura(E)) )
    ),
    close(S).

escribir_encabezado(S, Instancia, Est, Opc, Resultado) :-
    estado_texto(Resultado, Estado),
    fecha_texto(Fecha),
    etiqueta_estrategia(Est, Opc, Etiqueta),
    format(S, "================================================================~n", []),
    format(S, "ASIGNACION DE HORARIOS UNIVERSITARIOS~n", []),
    format(S, "================================================================~n", []),
    format(S, "Instancia : ~w~n", [Instancia]),
    format(S, "Estrategia : ~w~n", [Etiqueta]),
    format(S, "Estado : ~w~n", [Estado]),
    format(S, "Fecha : ~w~n", [Fecha]),
    format(S, "----------------------------------------------------------------~n", []).

estado_texto(solucion(_),           'SOLUCION ENCONTRADA').
estado_texto(sin_solucion(_),       'SIN SOLUCION').
estado_texto(limite_alcanzado,      'LIMITE ALCANZADO').
estado_texto(instancia_invalida(_), 'INSTANCIA INVALIDA').

etiqueta_estrategia(Est, Opc, Etiqueta) :-
    (   catch(opcion(heuristica, Opc, original, H), _, fail)
    ->  true
    ;   H = original
    ),
    format_to_atom(Etiqueta, "~w (~w)", [Est, H]).

fecha_texto(Texto) :-
    (   catch(date_time(dt(Y, Mo, D, H, Mi, Se)), _, fail)
    ->  pad2(Mo, Mo2), pad2(D, D2), pad2(H, H2), pad2(Mi, Mi2), pad2(Se, Se2),
        format_to_atom(Texto, "~w-~w-~w ~w:~w:~w", [Y, Mo2, D2, H2, Mi2, Se2])
    ;   Texto = 'n/d'
    ).

pad2(N, A) :-
    (   N < 10 -> format_to_atom(A, "0~w", [N]) ; format_to_atom(A, "~w", [N]) ).

escribir_bloques(S, Opc, solucion(H)) :- !,
    escribir_detalle(S, H),
    escribir_rejillas_grupo(S, H),
    escribir_rejillas_profesor(S, H),
    ( member(por_aula, Opc) -> escribir_rejillas_aula(S, H) ; true ),
    escribir_resumen(S, Opc, H).
escribir_bloques(S, _, sin_solucion(R)) :- !,
    escribir_diagnostico(S, R).
escribir_bloques(S, _, limite_alcanzado) :- !,
    format(S, "~nLIMITE DE BUSQUEDA ALCANZADO~n", []).
escribir_bloques(S, _, instancia_invalida(Error)) :- !,
    format(S, "~nERRORES DE LA INSTANCIA~n", []),
    errores_lista(Error, Lista),
    forall(member(E, Lista), format(S, "  ~w~n", [E])).

errores_lista(error_instancia(invalida(errores_instancia(L))), L) :- !.
errores_lista(error_instancia(Causa), [Causa]) :- !.
errores_lista(E, [E]).

% ---- Detalle de asignaciones ----
escribir_detalle(S, H) :-
    format(S, "~nDETALLE DE ASIGNACIONES~n", []),
    format(S, "# Curso Grupo Profesor Aula Dia Franjas~n", []),
    numerar_detalle(S, H, 1).

numerar_detalle(_, [], _).
numerar_detalle(S, [asignacion(C,G,P,A,D,F,Dur)|Rs], N) :-
    Fin is F + Dur - 1,
    nom(curso, C, CT), nom(grupo, G, GT), nom(profesor, P, PT),
    nom(aula, A, AT), nom(dia, D, DT),
    format(S, "~w ~w ~w ~w ~w ~w ~w-~w~n",
           [N, CT, GT, PT, AT, DT, F, Fin]),
    N1 is N + 1,
    numerar_detalle(S, Rs, N1).

% ---- Rejillas por grupo, profesor y aula ----
escribir_rejillas_grupo(S, H) :-
    findall(C-G, ( grupo(C,G,_,_,_,_,_),
                   member(asignacion(C,G,_,_,_,_,_), H) ),
            L), sort(L, Grupos),
    forall(member(C-G, Grupos),
           escribir_rejilla(S, 'GRUPO', C-G, grupo, H)).

escribir_rejillas_profesor(S, H) :-
    findall(P, ( profesor(P,_,_,_),
                 member(asignacion(_,_,P,_,_,_,_), H) ),
            L), sort(L, Profs),
    forall(member(P, Profs),
           escribir_rejilla(S, 'PROFESOR', P, profesor, H)).

escribir_rejillas_aula(S, H) :-
    findall(A, ( aula(A,_,_),
                 member(asignacion(_,_,_,A,_,_,_), H) ), L),
    sort(L, As),
    forall(member(A, As), escribir_rejilla(S, 'AULA', A, aula, H)).

escribir_rejilla(S, Etiqueta, Clave, Tipo, H) :-
    clave_texto(Tipo, Clave, ClaveT),
    format(S, "~nHORARIO POR ~w: ~w~n", [Etiqueta, ClaveT]),
    findall(D, dia(D), Dias),
    format(S, "franja ", []),
    forall(member(D, Dias), ( nom(dia, D, DT), format(S, "~w ", [DT]) )), nl(S),
    num_franjas(NF),
    forall(between(1, NF, F),
           fila_rejilla(S, Tipo, Clave, F, Dias, H)).

fila_rejilla(S, Tipo, Clave, F, Dias, H) :-
    format(S, "~w ", [F]),
    forall(member(D, Dias), celda(S, Tipo, Clave, D, F, H)), nl(S).

celda(S, Tipo, Clave, D, F, H) :-
    (   celda_ocupada(Tipo, Clave, D, F, H, C/G)
    ->  nom(curso, C, CT), nom(grupo, G, GT),
        format(S, "~w/~w ", [CT, GT])
    ;   format(S, "-- ", [])
    ).

celda_ocupada(grupo, C-G, D, F, H, C/G) :-
    member(asignacion(C, G, _, _, D, F0, Dur), H),
    F >= F0, F < F0 + Dur, !.
celda_ocupada(profesor, P, D, F, H, C/G) :-
    member(asignacion(C, G, P, _, D, F0, Dur), H),
    F >= F0, F < F0 + Dur, !.
celda_ocupada(aula, A, D, F, H, C/G) :-
    member(asignacion(C, G, _, A, D, F0, Dur), H),
    F >= F0, F < F0 + Dur, !.

% ---- Resumen ----
escribir_resumen(S, Opc, H) :-
    estadisticas(est(N, R, CpuMs, RealMs)),
    length(H, NSes),
    total_franjas_sesion(H, TF),
    huecos_grupo(H, HG),
    huecos_profesor(H, HP),
    costo_blandas(H, Costo),
    CpuS  is CpuMs  / 1000,
    RealS is RealMs / 1000,
    (   CpuMs > 0 -> Tasa is round(N * 1000 / CpuMs) ; Tasa = 0 ),
    format(S, "~nRESUMEN~n", []),
    format(S, "Sesiones programadas                ~w~n", [NSes]),
    format(S, "Franjas-sesion ocupadas            ~w~n", [TF]),
    format(S, "Huecos de grupo                    ~w~n", [HG]),
    format(S, "Huecos de profesor                 ~w~n", [HP]),
    format(S, "Costo de restricciones blandas     ~w~n", [Costo]),
    format(S, "Nodos explorados                   ~w~n", [N]),
    format(S, "Retrocesos (backtracks)            ~w~n", [R]),
    format(S, "Tiempo de CPU (s)                  ~w~n", [CpuS]),
    format(S, "Tiempo de pared (s)                ~w~n", [RealS]),
    format(S, "Nodos por segundo                  ~w~n", [Tasa]),
    linea_optimo(S, Opc),
    format(S, "Estado final  solucion valida de costo ~w~n", [Costo]).

linea_optimo(S, Opc) :-
    (   member(optimizar, Opc)
    ->  estado_optimo(O),
        texto_optimo(O, T),
        format(S, "Optimalidad                       ~w~n", [T])
    ;   true
    ).

% Una global sin asignar vale 0 en GNU Prolog, por eso se valida el valor.
estado_optimo(O) :-
    (   catch(g_read(opt_optimo, O0), _, fail),
        memberchk(O0, [si, no, n_a])
    ->  O = O0
    ;   O = n_a
    ).

texto_optimo(si,  'OPTIMA (arbol agotado)').
texto_optimo(no,  'NO PROBADA (limite alcanzado, mejor solucion conocida)').
texto_optimo(n_a, 'n/a').

% ---- Diagnostico ----
escribir_diagnostico(S, Razon) :-
    format(S, "~nDIAGNOSTICO~n", []),
    format(S, "Razon inmediata: ~w~n", [Razon]),
    sesiones(Sesiones), length(Sesiones, NSes),
    num_franjas(NF), findall(D, dia(D), Dias), length(Dias, ND),
    findall(A, aula(A,_,_), As), length(As, NA),
    Total is NF * ND,
    Celdas is NA * Total,
    findall(Sem * Dur, grupo(_,_,_,_,Sem,Dur,_), Prods),
    suma_prods(Prods, Requeridas),
    format(S, "Sesiones a programar : ~w~n", [NSes]),
    format(S, "Franjas disponibles  : ~w (~w dias x ~w franjas)~n",
           [Total, ND, NF]),
    format(S, "Franjas-aula          : ~w requeridas de ~w disponibles (~w aulas x ~w)~n",
           [Requeridas, Celdas, NA, Total]),
    (   grupo_mayor_demanda(C-G, Sem)
    ->  nom(curso, C, CT), nom(grupo, G, GT),
        format(S, "Grupo con mayor demanda : ~w ~w (~w sesiones)~n", [CT, GT, Sem])
    ;   true
    ),
    (   profesor_mayor_carga(P, Carga, Max)
    ->  nom(profesor, P, PT),
        format(S, "Profesor con mayor carga: ~w (~w de ~w franjas)~n",
               [PT, Carga, Max])
    ;   true
    ),
    escribir_culpables(S).

suma_prods([], 0).
suma_prods([X|Xs], T) :- suma_prods(Xs, T0), V is X, T is T0 + V.

% Restriccion culpable: se quita cada restriccion dura declarada sola y
% se resuelve de nuevo; los hechos se restauran al terminar.
escribir_culpables(S) :-
    restricciones_culpables(Cs),
    (   Cs == []
    ->  format(S, "Restriccion declarada culpable: ninguna restriccion declarada, quitada sola, resuelve la instancia~n", []),
        format(S, "  (el limite esta en aulas, franjas, disponibilidad o carga del profesor)~n", [])
    ;   forall(member(R, Cs),
               ( restriccion_texto(R, T),
                 format(S, "Restriccion declarada culpable: ~w~n", [T]) ))
    ).

tipo_duro(aula_fija(_,_,_)).
tipo_duro(prohibida(_,_,_,_)).
tipo_duro(excluyentes(_,_,_,_)).

restricciones_culpables(Culpables) :-
    findall(P-Todos, ( tipo_duro(P), findall(P, call(P), Todos) ), Grupos),
    catch(probar_grupos(Grupos, Culpables), _, Culpables = []),
    restaurar_grupos(Grupos).

probar_grupos([], []).
probar_grupos([P-Todos|Gs], Culp) :-
    probar_uno(Todos, P, Todos, C1),
    restaurar_grupos([P-Todos]),
    probar_grupos(Gs, C2),
    append(C1, C2, Culp).

probar_uno([], _, _, []).
probar_uno([R|Rs], P, Todos, Culp) :-
    quitar_primero(Todos, R, Resto),
    reponer(P, Resto),
    (   resuelve_rapido -> Culp = [R|Culp1] ; Culp = Culp1 ),
    probar_uno(Rs, P, Todos, Culp1).

quitar_primero([X|Xs], R, Resto) :-
    (   X == R -> Resto = Xs
    ;   Resto = [X|Resto1], quitar_primero(Xs, R, Resto1)
    ).

reponer(P, Hechos) :-
    functor(P, N, A), functor(Gen, N, A),
    retractall(Gen),
    forall(member(H, Hechos), assertz(H)).

restaurar_grupos([]).
restaurar_grupos([P-Todos|Gs]) :- reponer(P, Todos), restaurar_grupos(Gs).

resuelve_rapido :-
    catch(resolver(bt, [heuristica(mrv), limite(200000)], Res), _, fail),
    Res = solucion(_).

restriccion_texto(aula_fija(C,G,A), T) :- !,
    nom(curso,C,CT), nom(grupo,G,GT), nom(aula,A,AT),
    format_to_atom(T, "aula_fija ~w ~w -> ~w", [CT,GT,AT]).
restriccion_texto(prohibida(C,G,D,F), T) :- !,
    nom(curso,C,CT), nom(grupo,G,GT), nom(dia,D,DT),
    format_to_atom(T, "prohibida ~w ~w en ~w~w", [CT,GT,DT,F]).
restriccion_texto(excluyentes(C1,G1,C2,G2), T) :- !,
    nom(curso,C1,C1T), nom(grupo,G1,G1T), nom(curso,C2,C2T), nom(grupo,G2,G2T),
    format_to_atom(T, "excluyentes ~w ~w con ~w ~w", [C1T,G1T,C2T,G2T]).
restriccion_texto(R, R).

grupo_mayor_demanda(C-G, Sem) :-
    findall(NegSem-(C0-G0), ( grupo(C0,G0,_,_,Sem0,_,_),
                              NegSem is -Sem0 ),
            L),
    keysort(L, [_-(C-G)|_]),
    grupo(C, G, _, _, Sem, _, _).

profesor_mayor_carga(P, Carga, Max) :-
    sesiones(Ss),
    findall(NegCarga-P0, ( profesor(P0,_,_,_),
                           findall(Dur, member(sesion(_,_,_,_,P0,Dur), Ss), Ds),
                           suma(Ds, C0), NegCarga is -C0 ),
            L),
    keysort(L, [_-P|_]),
    profesor(P, _, Max, _),
    findall(Dur, member(sesion(_,_,_,_,P,Dur), Ss), Ds1),
    suma(Ds1, Carga).

% ---- Metricas auxiliares ----
total_franjas_sesion(H, T) :-
    findall(Dur, member(asignacion(_,_,_,_,_,_,Dur), H), Ds),
    suma(Ds, T).

huecos_grupo(H, Total) :-
    findall(C-G, ( grupo(C,G,_,_,_,_,_),
                   member(asignacion(C,G,_,_,_,_,_), H) ), L),
    sort(L, Gs),
    findall(N, (member(C-G, Gs), huecos_entidad(H, grupo, C-G, N)), Ns),
    suma(Ns, Total).

huecos_profesor(H, Total) :-
    findall(P, ( profesor(P,_,_,_),
                 member(asignacion(_,_,P,_,_,_,_), H) ), L),
    sort(L, Ps),
    findall(N, (member(P, Ps), huecos_entidad(H, profesor, P, N)), Ns),
    suma(Ns, Total).

huecos_entidad(H, Tipo, Clave, Total) :-
    findall(D, dia(D), Dias),
    findall(N, (member(D, Dias), huecos_dia(H, Tipo, Clave, D, N)), Ns),
    suma(Ns, Total).

huecos_dia(H, Tipo, Clave, D, N) :-
    findall(F, franja_ocupada(H, Tipo, Clave, D, F), Fs),
    (   Fs == [] -> N = 0
    ;   min_de(Fs, Min), max_de(Fs, Max), length(Fs, Oc),
        Rango is Max - Min + 1,
        N is Rango - Oc
    ).

franja_ocupada(H, grupo, C-G, D, F) :-
    member(asignacion(C, G, _, _, D, F0, Dur), H),
    Fin is F0 + Dur - 1,
    between(F0, Fin, F).
franja_ocupada(H, profesor, P, D, F) :-
    member(asignacion(_, _, P, _, D, F0, Dur), H),
    Fin is F0 + Dur - 1,
    between(F0, Fin, F).

costo_blandas(H, Costo) :-
    findall(W, ( prefiere(C,G,D,F,W),
                 \+ tiene_sesion_en(H, C, G, D, F) ),
            WsPre), suma(WsPre, CPre),
    findall(WN, ( compacta(C,G,W),
                  huecos_entidad(H, grupo, C-G, N),
                  WN is W * N ),
            Prods), suma(Prods, CComp),
    Costo is CPre + CComp.

tiene_sesion_en(H, C, G, D, F) :-
    member(asignacion(C, G, _, _, D, F, _), H).

% ---- Archivo Prolog con hechos asignacion/7 ----
escribir_salida_prolog(Opc, Resultado) :-
    (   member(salida_prolog(Ruta), Opc),
        Resultado = solucion(H)
    ->  escribir_hechos_asignacion(Ruta, H)
    ;   true
    ).

escribir_hechos_asignacion(Ruta, H) :-
    (   catch(open(Ruta, write, S), _, fail)
    ->  true
    ;   throw(error_escritura(Ruta))
    ),
    catch(
        forall(member(asignacion(C,G,P,A,D,F,Dur), H),
               format(S, "asignacion(~w, ~w, ~w, ~w, ~w, ~w, ~w).~n",
                      [C,G,P,A,D,F,Dur])),
        E,
        ( close(S), throw(error_escritura(E)) )
    ),
    close(S).

% ---- Utilidades ----
min_de([X], X) :- !.
min_de([X|Xs], M) :- min_de(Xs, M0), ( X < M0 -> M = X ; M = M0 ).

max_de([X], X) :- !.
max_de([X|Xs], M) :- max_de(Xs, M0), ( X > M0 -> M = X ; M = M0 ).

% Nombres originales (A-101, P-001, ...) para el texto de salida.
nom(Tipo, Norm, Texto) :-
    (   original(Tipo, Norm, O) -> Texto = O ; Texto = Norm ).

clave_texto(grupo, C-G, T) :- !,
    nom(curso, C, CT), nom(grupo, G, GT),
    format_to_atom(T, "~w ~w", [CT, GT]).
clave_texto(profesor, P, T) :- !, nom(profesor, P, T).
clave_texto(aula, A, T)     :- !, nom(aula, A, T).
clave_texto(_, X, X).
