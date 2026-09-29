% ============================================================
% pruebas_bt.pl -- compara TODAS las configuraciones (bt y clpfd)
%
% Cargar despues de horarios.pl, busqueda_bt.pl y busqueda_fd.pl
% (y main.pl si se quiere el costo de las restricciones blandas):
%
%   | ?- comparar('campus-central.dat', 200000).
%   | ?- comparar('campus-central.dat', 200000, 'resultados.csv').
%   | ?- comparar_varias(['i10.dat','i20.dat','i40.dat'], 500000).
%
% Metricas por configuracion (secciones 12.1 a 12.5 del enunciado):
%   Nodos, Retroc.  contadores explicitos (g_inc)
%   CPU ms, Pared ms  statistics/2
%   Nod/s  = Re = N / Te
%   S      = T_ingenuo / T_config          (aceleracion)
%   E      = (N_ingenuo - N_config) / N_ingenuo   (eficiencia de la poda)
% La referencia "ingenua" es la PRIMERA configuracion (generar y probar).
% Si la referencia alcanzo el limite, S y E se marcan con '>=' porque
% son cotas inferiores (la referencia real habria tardado mas).
% Las filas que alcanzan el limite o fallan muestran '-' en S y E.
%
% OJO: en clpfd un "nodo" es una decision del etiquetado (X = W); en bt es
% un intento de asignar una sesion. Son comparables en orden de magnitud,
% no exactamente.
% ============================================================

% configuracion(+Estrategia, +Opciones, +Nombre)
configuracion(bt_gp, [],                                      'generar y probar').
configuracion(bt,    [heuristica(original), simetria(no)],    'anticipada, original').
configuracion(bt,    [heuristica(original), simetria(intra)], 'anticipada, original+intra').
configuracion(bt,    [heuristica(original), simetria(inter)], 'anticipada, original+inter').
configuracion(bt,    [heuristica(original), simetria(si)],    'anticipada, original+sim').
configuracion(bt,    [heuristica(grado),    simetria(si)],    'anticipada, grado+sim').
configuracion(bt,    [heuristica(demanda),  simetria(si)],    'anticipada, demanda+sim').
configuracion(bt,    [heuristica(mrv),      simetria(no)],    'FC + MRV').
configuracion(bt,    [heuristica(mrv),      simetria(si)],    'FC + MRV + sim').
configuracion(bt,    [heuristica(lcv),      simetria(no)],    'FC + LCV').
configuracion(clpfd, [heuristica(original), simetria(no)],    'CLP(FD), original').
configuracion(clpfd, [heuristica(ff),       simetria(no)],    'CLP(FD), ff').
configuracion(clpfd, [heuristica(ff),       simetria(si)],    'CLP(FD), ff+sim').
configuracion(clpfd, [heuristica(ffc),      simetria(si)],    'CLP(FD), ffc+sim').
configuracion(clpfd, [heuristica(lcv),      simetria(si)],    'CLP(FD), lcv+sim').
configuracion(clpfd, [heuristica(ff),       optimizar],       'CLP(FD), ff + B&B').
configuracion(clpfd, [heuristica(original), labeling(fd)], 'CLP(FD) fd_labeling, original').
configuracion(clpfd, [heuristica(ff),       labeling(fd)], 'CLP(FD) fd_labeling, ff').
configuracion(clpfd, [heuristica(ffc),      labeling(fd)], 'CLP(FD) fd_labeling, ffc').

% ------------------------------------------------------------
% Interfaz
% ------------------------------------------------------------
comparar(Archivo, Limite) :-
    comparar(Archivo, Limite, ninguno).

comparar(Archivo, Limite, Csv) :-
    cargar_instancia(Archivo),
    sesiones(Ss), length(Ss, NSes),
    findall(F,
            (   configuracion(E, Opc, Nombre),
                correr(E, [limite(Limite)|Opc], Nombre, F)
            ),
            Filas),
    Filas = [Ref0|_],
    referencia(Ref0, Ref),
    derivar_todas(Filas, Ref, Tabla),
    imprimir_tabla(Archivo, NSes, Limite, Ref, Tabla),
    (   Csv == ninguno
    ->  true
    ;   escribir_csv(Csv, Archivo, NSes, Limite, Tabla)
    ).

comparar_varias(Archivos, Limite) :-
    forall(member(A, Archivos), comparar(A, Limite)).

% ------------------------------------------------------------
% Una corrida:  r(Nombre, Resultado, Nodos, Retroc, CpuMs, Pared, Verif,
%                 Costo, Optimo)
% Nunca falla ni lanza: los errores quedan como resultado error(E).
% ------------------------------------------------------------
correr(E, Opc, Nombre, Fila) :-
    (   catch(resolver(E, Opc, R), Error, R = error(Error))
    ->  true
    ;   R = fallo
    ),
    (   R = error(_) -> N = 0, Ret = 0, Cpu = 0, Real = 0
    ;   R == fallo   -> N = 0, Ret = 0, Cpu = 0, Real = 0
    ;   estadisticas(est(N, Ret, Cpu, Real))
    ),
    resumen(R, Txt, Ok, Costo),
    optimo_de(Opc, Opt),
    Fila = r(Nombre, Txt, N, Ret, Cpu, Real, Ok, Costo, Opt).

resumen(solucion(H), solucion, Ok, Costo) :- !,
    (   verifica(H)
    ->  Ok = valida
    ;   Ok = 'INVALIDA',
        violaciones(H, Vs),
        format(user_error, "  ** horario INVALIDO, violaciones: ~w~n", [Vs])
    ),
    (   catch(costo_blandas(H, C0), _, fail) -> Costo = C0 ; Costo = '-' ).
resumen(sin_solucion(Razon), sin_solucion(Razon), '-', '-') :- !.
resumen(limite_alcanzado, limite_alcanzado, '-', '-') :- !.
resumen(Otro, Otro, '-', '-').

% opt_optimo lo deja busqueda_fd.pl: si | no | n_a
optimo_de(Opc, Opt) :-
    (   member(optimizar, Opc)
    ->  (   catch(g_read(opt_optimo, O), _, fail) -> Opt = O ; Opt = '-' )
    ;   Opt = '-'
    ).

% ------------------------------------------------------------
% Metricas derivadas
% ------------------------------------------------------------
referencia(r(_, Txt, N, _, Cpu, _, _, _, _), ref(N, TRef, Pref)) :-
    TRef is max(Cpu, 1),
    (   Txt == limite_alcanzado -> Pref = '>=' ; Pref = '' ).

derivar_todas([], _, []).
derivar_todas([R|Rs], Ref, [F|Fs]) :-
    derivar(R, Ref, F),
    derivar_todas(Rs, Ref, Fs).

% f(Nombre, Resultado, Nodos, Retroc, Cpu, Pared, Nod/s, S, E, Pref, Verif, Costo, Opt)
derivar(r(Nom, Txt, N, Ret, Cpu, Real, Ok, Costo, Opt), ref(NRef, TRef, Pref),
        f(Nom, Txt, N, Ret, Cpu, Real, Rate, S, E, Pref, Ok, Costo, Opt)) :-
    Tc is max(Cpu, 1),
    Rate is round(N * 1000.0 / Tc),
    (   comparable(Txt)
    ->  S0 is TRef / (Tc * 1.0),
        S is round(S0 * 100) / 100.0,
        (   NRef > 0
        ->  E0 is (NRef - N) / (NRef * 1.0),
            E is round(E0 * 1000) / 1000.0
        ;   E = '-'
        )
    ;   S = '-', E = '-'
    ).

comparable(Txt) :-
    Txt \== limite_alcanzado,
    Txt \== fallo,
    Txt \= error(_).

% ------------------------------------------------------------
% Salida en pantalla
% ------------------------------------------------------------
imprimir_tabla(Archivo, NSes, Limite, ref(NRef, TRef, Pref), Tabla) :-
    nl,
    write('Instancia: '), write(Archivo),
    write('   Sesiones: '), write(NSes),
    write('   Limite: '), write(Limite), write(' nodos'), nl,
    write('Referencia (ingenua): nodos='), write(NRef),
    write(' cpu_ms='), write(TRef),
    (   Pref == '>=' -> write('   [alcanzo el limite: S y E son cotas inferiores]')
    ;   true
    ), nl,
    write('Configuracion | Resultado | Nodos | Retroc. | CPU ms | Pared ms | Nod/s | S | E | Verifica | Costo | Optimo'),
    nl,
    imprimir_filas(Tabla).

imprimir_filas([]).
imprimir_filas([f(Nom, Txt, N, Ret, Cpu, Real, Rate, S, E, Pref, Ok, Costo, Opt)|Fs]) :-
    write(Nom), write(' | '), write(Txt), write(' | '),
    write(N), write(' | '), write(Ret), write(' | '),
    write(Cpu), write(' | '), write(Real), write(' | '),
    write(Rate), write(' | '),
    escribir_relativo(Pref, S), write(' | '),
    escribir_relativo(Pref, E), write(' | '),
    write(Ok), write(' | '), write(Costo), write(' | '), write(Opt), nl,
    imprimir_filas(Fs).

escribir_relativo(_, '-') :- !, write('-').
escribir_relativo(Pref, V) :- write(Pref), write(V).

% ------------------------------------------------------------
% CSV (para graficar en una hoja de calculo)
% ------------------------------------------------------------
escribir_csv(Ruta, Archivo, NSes, Limite, Tabla) :-
    open(Ruta, write, Out),
    format(Out, "instancia,sesiones,limite,configuracion,resultado,nodos,retrocesos,cpu_ms,pared_ms,nodos_por_s,aceleracion,eficiencia_poda,ref_es_cota,verifica,costo,optimo~n", []),
    csv_filas(Tabla, Archivo, NSes, Limite, Out),
    close(Out),
    write('CSV escrito en '), write(Ruta), nl.

csv_filas([], _, _, _, _).
csv_filas([f(Nom, Txt, N, Ret, Cpu, Real, Rate, S, E, Pref, Ok, Costo, Opt)|Fs],
          Archivo, NSes, Limite, Out) :-
    functor(Txt, TxtF, _),
    (   Pref == '>=' -> Cota = si ; Cota = no ),
    format(Out, "~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w,~w~n",
           [Archivo, NSes, Limite, Nom, TxtF, N, Ret, Cpu, Real, Rate,
            S, E, Cota, Ok, Costo, Opt]),
    csv_filas(Fs, Archivo, NSes, Limite, Out).
