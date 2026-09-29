% ============================================================
% pruebas_bt.pl -- compara las configuraciones de backtracking
% Uso (con horarios.pl y busqueda_bt.pl ya cargados):
%     | ?- comparar('campus-central.dat', 200000).
% ============================================================

configuracion(bt_gp, [],                                     'generar y probar').
configuracion(bt,    [heuristica(original), simetria(no)],   'anticipada, original').
configuracion(bt,    [heuristica(original), simetria(si)],   'anticipada, original+sim').
configuracion(bt,    [heuristica(grado),    simetria(si)],   'anticipada, grado+sim').
configuracion(bt,    [heuristica(demanda),  simetria(si)],   'anticipada, demanda+sim').
configuracion(bt,    [heuristica(mrv),      simetria(no)],   'FC + MRV').
configuracion(bt,    [heuristica(mrv),      simetria(si)],   'FC + MRV + sim').

comparar(Archivo, Limite) :-
    cargar_instancia(Archivo),
    write('Configuracion              Resultado   Nodos   Retroc.  CPU ms  verifica'), nl,
    forall(configuracion(E, Opc, Nombre), correr(E, [limite(Limite)|Opc], Nombre)).

correr(E, Opc, Nombre) :-
    resolver(E, Opc, R),
    estadisticas(est(N, Ret, Cpu, _)),
    resumen(R, Txt, Ok),
    write(Nombre), write(' | '), write(Txt), write(' | '),
    write(N), write(' | '), write(Ret), write(' | '), write(Cpu),
    write(' | '), write(Ok), nl.

resumen(solucion(H), solucion, Ok) :- !, ( verifica(H) -> Ok = valida ; Ok = 'INVALIDA' ).
resumen(sin_solucion(Razon), sin_solucion(Razon), '-') :- !.
resumen(limite_alcanzado, limite_alcanzado, '-').
