% ============================================================
% main.pl -- interfaz de linea de comandos
% Se consulta DESPUES de:
%   horarios.pl, busqueda_bt.pl, busqueda_fd.pl, valida.pl
%
% Invocacion tipica:
%   gprolog --consult-file horarios.pl \
%           --consult-file busqueda_bt.pl \
%           --consult-file busqueda_fd.pl \
%           --consult-file valida.pl \
%           --consult-file main.pl \
%           --entry-goal "main('in.dat','out.txt',estrategia(clpfd,[heuristica(mrv)]))"
%
% Codigos de salida (halt/1):
%   0  solucion encontrada
%   1  sin solucion (instancia consistente pero insatisfacible)
%   2  instancia invalida / no legible
%   3  limite de busqueda alcanzado
%   4  argumentos o error de escritura
% ============================================================

% ------------------------------------------------------------
% main/3
%   Estrategia admite:
%       bt | bt_gp | clpfd
%       [bt, heuristica(mrv), limite(5000000)]
%       estrategia(bt, [heuristica(mrv), simetria(si)])
%
%   Opciones adicionales reconocidas aqui (no por resolver/3):
%       salida_prolog(Ruta)   -> escribe hechos asignacion/7   (6.5)
%       por_aula              -> anade rejilla por aula         (6.3)
%
% main/3 SIEMPRE termina con halt/1: ejecutar/3 llama a halt al
% acabar, las excepciones las maneja abortar/4 y, si ejecutar/3
% fallara sin lanzar excepcion, la segunda clausula termina con 1.
% ------------------------------------------------------------
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
    resolver(Est, Opc, Resultado),
    escribir_salida(Salida, Instancia, Est, Opc, Resultado),
    escribir_salida_prolog(Opc, Resultado),
    codigo_resultado(Resultado, Codigo),
    halt(Codigo).

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

% codigo_resultado(+Resultado, -CodigoSalida)
codigo_resultado(solucion(_),         0) :- !.
codigo_resultado(sin_solucion(_),     1) :- !.
codigo_resultado(limite_alcanzado,    3) :- !.
codigo_resultado(instancia_invalida(_), 2) :- !.
codigo_resultado(_,                   1).

% codigo_error(+Error, -CodigoSalida)
codigo_error(error_instancia(_),  2) :- !.
codigo_error(error_argumentos(_), 4) :- !.
codigo_error(error_escritura(_),  4) :- !.
codigo_error(_,                   2).

% abortar(+Error, +Instancia, +Salida, +Estrategia)
% Informa por stderr. Si la instancia es invalida intenta ademas dejar
% un archivo de salida con Estado = INSTANCIA INVALIDA (6.1); si no se
% puede escribir, se ignora y se sale igual con el codigo 2.
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
% Escritura del archivo de salida (seccion 6)
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

estado_texto(solucion(_),         'SOLUCION ENCONTRADA').
estado_texto(sin_solucion(_),     'SIN SOLUCION').
estado_texto(limite_alcanzado,    'LIMITE ALCANZADO').
estado_texto(instancia_invalida(_), 'INSTANCIA INVALIDA').

% Estrategia + heuristica, p. ej. "clpfd (mrv)"
etiqueta_estrategia(Est, Opc, Etiqueta) :-
    (   catch(opcion(heuristica, Opc, original, H), _, fail)
    ->  true
    ;   H = original
    ),
    format(atom(Etiqueta), "~w (~w)", [Est, H]).

% Fecha y hora local "AAAA-MM-DD HH:MM:SS"; 'n/d' si no esta disponible.
fecha_texto(Texto) :-
    (   catch(date_time(dateTime(Y, Mo, D, H, Mi, Se)), _, fail)
    ->  Se1 is integer(Se),
        pad2(Mo, Mo2), pad2(D, D2), pad2(H, H2), pad2(Mi, Mi2), pad2(Se1, Se2),
        format(atom(Texto), "~w-~w-~w ~w:~w:~w", [Y, Mo2, D2, H2, Mi2, Se2])
    ;   Texto = 'n/d'
    ).

pad2(N, A) :-
    (   N < 10 -> format(atom(A), "0~w", [N]) ; format(atom(A), "~w", [N]) ).

escribir_bloques(S, Opc, solucion(H)) :- !,
    escribir_detalle(S, H),
    escribir_rejillas_grupo(S, H),
    escribir_rejillas_profesor(S, H),
    ( member(por_aula, Opc) -> escribir_rejillas_aula(S, H) ; true ),
    escribir_resumen(S, H).
escribir_bloques(S, _, sin_solucion(R)) :- !,
    escribir_diagnostico(S, R).
escribir_bloques(S, _, limite_alcanzado) :- !,
    format(S, "~nLIMITE DE BUSQUEDA ALCANZADO~n", []).
escribir_bloques(S, _, instancia_invalida(Error)) :- !,
    format(S, "~nERRORES DE LA INSTANCIA~n", []),
    errores_lista(Error, Lista),
    forall(member(E, Lista), format(S, "  ~w~n", [E])).

% Aplana el termino de error de valida/1 a una lista de errores
errores_lista(error_instancia(invalida(errores_instancia(L))), L) :- !.
errores_lista(error_instancia(Causa), [Causa]) :- !.
errores_lista(E, [E]).

% -------- 6.2 DETALLE DE ASIGNACIONES --------
escribir_detalle(S, H) :-
    format(S, "~nDETALLE DE ASIGNACIONES~n", []),
    format(S, "# Curso Grupo Profesor Aula Dia Franjas~n", []),
    numerar_detalle(S, H, 1).

numerar_detalle(_, [], _).
numerar_detalle(S, [asignacion(C,G,P,A,D,F,Dur)|Rs], N) :-
    Fin is F + Dur - 1,
    format(S, "~w ~w ~w ~w ~w ~w ~w-~w~n",
           [N, C, G, P, A, D, F, Fin]),
    N1 is N + 1,
    numerar_detalle(S, Rs, N1).

% -------- 6.3 HORARIO POR GRUPO / PROFESOR / AULA --------
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
    format(S, "~nHORARIO POR ~w: ~w~n", [Etiqueta, Clave]),
    findall(D, dia(D), Dias),
    format(S, "franja ", []),
    forall(member(D, Dias), format(S, "~w ", [D])), nl(S),
    num_franjas(NF),
    forall(between(1, NF, F),
           fila_rejilla(S, Tipo, Clave, F, Dias, H)).

fila_rejilla(S, Tipo, Clave, F, Dias, H) :-
    format(S, "~w ", [F]),
    forall(member(D, Dias), celda(S, Tipo, Clave, D, F, H)), nl(S).

celda(S, Tipo, Clave, D, F, H) :-
    (   celda_ocupada(Tipo, Clave, D, F, H, Et)
    ->  format(S, "~w ", [Et])
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

% -------- 6.4 RESUMEN --------
escribir_resumen(S, H) :-
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
    format(S, "Estado final  solucion valida de costo ~w~n", [Costo]).

% -------- 6.4 alterno: DIAGNOSTICO --------
escribir_diagnostico(S, Razon) :-
    format(S, "~nDIAGNOSTICO~n", []),
    format(S, "Razon inmediata: ~w~n", [Razon]),
    sesiones(Sesiones), length(Sesiones, NSes),
    num_franjas(NF), findall(D, dia(D), Dias), length(Dias, ND),
    Total is NF * ND,
    format(S, "Sesiones a programar : ~w~n", [NSes]),
    format(S, "Franjas disponibles  : ~w (~w dias x ~w franjas)~n",
           [Total, ND, NF]),
    (   grupo_mayor_demanda(C-G, Sem)
    ->  format(S, "Grupo con mayor demanda : ~w (~w sesiones)~n", [C-G, Sem])
    ;   true
    ),
    (   profesor_mayor_carga(P, Carga, Max)
    ->  format(S, "Profesor con mayor carga: ~w (~w de ~w franjas)~n",
               [P, Carga, Max])
    ;   true
    ).

% CORREGIDO: el patron del keysort era [_-C-G|_], que se lee (_-C)-G
% y nunca unifica con NegSem-(C-G).
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

% -------- Metricas auxiliares --------
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
    between(F0, F0 + Dur - 1, F).
franja_ocupada(H, profesor, P, D, F) :-
    member(asignacion(_, _, P, _, D, F0, Dur), H),
    between(F0, F0 + Dur - 1, F).

% Costo de restricciones blandas (seccion 4.4)
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

% ------------------------------------------------------------
% 6.5: archivo Prolog consultable con hechos asignacion/7
% ------------------------------------------------------------
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

% ------------------------------------------------------------
% Utilidades locales (nombres propios para no chocar con las
% min_list/max_list de la biblioteca de GNU Prolog)
% ------------------------------------------------------------
min_de([X], X) :- !.
min_de([X|Xs], M) :- min_de(Xs, M0), ( X < M0 -> M = X ; M = M0 ).

max_de([X], X) :- !.
max_de([X|Xs], M) :- max_de(Xs, M0), ( X > M0 -> M = X ; M = M0 ).
