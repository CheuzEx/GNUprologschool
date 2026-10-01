% ============================================================
% busqueda_fd.pl -- Estrategia CLP(FD) con el solver de GNU Prolog
% Consultar DESPUES de horarios.pl y busqueda_bt.pl (y antes de main.pl).
%
% Aporta buscar_fd/3, que busqueda_bt.pl invoca desde
% buscar(clpfd, Opc, Pares, Sol).
%
% Uso tipico:
%   resolver(clpfd, [], R).
%   resolver(clpfd, [heuristica(ff), simetria(si), limite(500000)], R).
%   resolver(clpfd, [heuristica(ff), optimizar, limite(500000)], R).
%
% Opciones: heuristica(original|grado|demanda|mrv|ff|ffc|lcv)
%           simetria(no|si|intra|inter)   limite(N)   optimizar
%           labeling(propio|fd)   (por defecto propio)
%             propio : etiquetado propio; cuenta nodos y respeta limite(N).
%             fd     : fd_labeling/2 de GNU Prolog (8.2/8.3). NO respeta
%                      limite(N) ni cuenta nodos (nodos queda en 0); solo
%                      registra los retrocesos con la opcion backtracks(B).
%                      Con optimizar se ignora: el B&B siempre usa el
%                      etiquetado propio (necesita la cota inferior).
%
% NOTAS
%  - GNU Prolog trae el solver FD incorporado: NO hay que importar
%    ninguna biblioteca (library(clpfd) es de SWI-Prolog).
%  - Reutiliza de busqueda_bt.pl: opcion/4, excluyentes_par/4, suma/2,
%    contar_nodo/0, ordenar/3, a_horario/2, sim_intra/1, sim_inter/1,
%    equiv_g/4. Para optimizar usa costo_blandas/2 y huecos_entidad/4
%    (de main.pl).
%
% MODELO
%  Por cada sesion una UNICA variable de decision X en 1..N, donde N es
%  el tamano de su dominio precalculado (dominio/2: capacidad, tipo,
%  aula_fija, prohibida y disponibilidad ya aplicados). Con fd_element/3
%  se obtienen, en forma extensional, dos variables derivadas:
%      A = indice del aula          T = dia*K + franja     (K = franjas+1)
%  T es un "tiempo absoluto": como cada sesion cabe en su dia, dos
%  intervalos [T, T+Dur) de dias distintos nunca se solapan, asi que el
%  no-solapamiento es una sola disyuncion lineal.
%
%  Restricciones (por pares de sesiones):
%   - mismo profesor / mismo grupo / excluyentes:
%         T1+Dur1 =< T2  \/  T2+Dur2 =< T1
%   - resto de pares con aulas en comun (no expresable solo con tablas):
%         (A1 = A2)  ==>  (no solape)          [reificacion]
%   - redundantes con fd_all_different/1 (refuerzan la propagacion):
%         T distintos por profesor, T distintos por grupo, y
%         A*Big+T distintos en todo el sistema (misma aula + mismo inicio
%         implica solape).
%   - simetria: T1 < T2 (intra-grupo e inter-grupo equivalente).
%   El maximo de franjas del profesor es constante (suma de duraciones):
%   se comprueba en diagnostico_previo/2 y en verifica/1.
%
% HEURISTICAS (etiquetado propio, para poder contar nodos y aplicar el
% limite; fd_labeling/2 no tiene opcion de limite)
%   original|grado|demanda : primera variable pendiente (el orden lo da
%                            ordenar/3 en resolver/3)
%   ff, mrv                : menor dominio primero (first-fail). Como hay
%                            una variable por sesion, su tamano ES el
%                            numero de valores restantes: ff == MRV.
%   ffc                    : ff con desempate por grado (las sesiones se
%                            reordenan por grado antes de etiquetar; con
%                            labeling(fd) el desempate lo hace GNU Prolog
%                            por numero de restricciones de la variable)
%   lcv                    : ff + valor menos restrictivo: se prueba cada
%                            valor propagando y se elige el que deja mas
%                            valores en las demas sesiones.
% ============================================================

:- dynamic(fd_indice/3).      % fd_indice(aula|dia, Indice, Codigo)

% ------------------------------------------------------------
% Punto de entrada (llamado desde buscar/4 de busqueda_bt.pl)
% ------------------------------------------------------------
buscar_fd(Opc, Pares0, Sol) :-
    opcion(heuristica, Opc, original, H),
    opcion(simetria,   Opc, no,       Sim),
    opcion(labeling,   Opc, propio,   ModoLab),
    g_assign(opt_optimo, n_a),
    orden_previo(H, Pares0, Pares),
    preparar_indices,
    construir_vars(Pares, Vars),
    fd_pares(Vars, Sim),
    redundantes(Vars),
    modos(H, MV, MVal),
    (   member(optimizar, Opc)
    ->  buscar_optimo(Vars, Pares, MV, MVal, Sol)
    ;   xs_de(Vars, Xs),
        etiquetar_segun(ModoLab, H, Xs, MV, MVal, none),
        reconstruir(Pares, Vars, Sol)
    ).

% etiquetar_segun(+Modo, +Heuristica, +Xs, +MV, +MVal, +Poda)
etiquetar_segun(propio, _H, Xs, MV, MVal, Poda) :- !,
    etiquetar(Xs, MV, MVal, Poda).
etiquetar_segun(fd, H, Xs, _MV, _MVal, _Poda) :- !,
    fd_labeling_opts(H, Opts),
    % backtracks(B) es de SALIDA: unifica B con los retrocesos ocurridos.
    % No sirve como limite (fd_labeling/2 no tiene opcion de limite).
    fd_labeling(Xs, [backtracks(B)|Opts]),
    g_assign(retrocesos, B).
etiquetar_segun(Otro, _, _, _, _, _) :-
    throw(error_argumentos(labeling(Otro))).

% fd_labeling_opts(+Heuristica, -Opciones)
% Equivalencia con las opciones de fd_labeling/2 (justificar en el informe):
%   original : leftmost + up (valores por defecto)
%   mrv, ff  : variable_method(ff) (menor dominio; con una variable por sesion, el tamano
%              del dominio ES el numero de valores restantes: ff == MRV)
%   ffc      : GNU Prolog 1.4.5 no expone el desempate por restricciones;
%              se usa ff como aproximacion para fd_labeling
%   grado, demanda : el orden lo fija ordenar/3 antes de buscar; el
%              etiquetado es leftmost sobre esa lista (aproximacion)
%   lcv      : GNU Prolog no lo expone; solo existe en etiquetado propio
fd_labeling_opts(original, []) :- !.
fd_labeling_opts(grado,    []) :- !.
fd_labeling_opts(demanda,  []) :- !.
fd_labeling_opts(mrv,      [variable_method(ff)]) :- !.
fd_labeling_opts(ff,       [variable_method(ff)]) :- !.
fd_labeling_opts(ffc,      [variable_method(ff)]) :- !.
fd_labeling_opts(H, _) :-
    throw(error_argumentos(labeling_fd(H))).

orden_previo(ffc, P, P2) :- !, ordenar(grado, P, P2).
orden_previo(_, P, P).

% modos(+Heuristica, -SeleccionVariable, -SeleccionValor)
modos(original, izq, up)  :- !.
modos(grado,    izq, up)  :- !.
modos(demanda,  izq, up)  :- !.
modos(mrv,      ff,  up)  :- !.
modos(ff,       ff,  up)  :- !.
modos(ffc,      ff,  up)  :- !.
modos(lcv,      ff,  lcv) :- !.
modos(_,        izq, up).

% ------------------------------------------------------------
% Indices aula/dia -> entero consecutivo (desde 0)
% ------------------------------------------------------------
preparar_indices :-
    retractall(fd_indice(_,_,_)),
    findall(A, aula(A,_,_), Aulas),
    numerar(Aulas, 0, aula),
    findall(D, dia(D), Dias),
    numerar(Dias, 0, dia).

numerar([], _, _).
numerar([X|Xs], N, Tipo) :-
    assertz(fd_indice(Tipo, N, X)),
    N1 is N + 1,
    numerar(Xs, N1, Tipo).

indice(Tipo, Valor, Idx) :- fd_indice(Tipo, Idx, Valor).

k_dia(K) :- num_franjas(NF), K is NF + 1.

% ------------------------------------------------------------
% Variables FD: fv(Sesion, X, A, T, Dominio, AulasPosibles)
% ------------------------------------------------------------
construir_vars([], []).
construir_vars([S-Dom|Ps], [fv(S, X, A, T, Dom, As)|Vs]) :-
    length(Dom, N),
    k_dia(K),
    tablas(Dom, K, LA, LT, As0),
    sort(As0, As),
    fd_domain(X, 1, N),
    fd_element(X, LA, A),
    fd_element(X, LT, T),
    construir_vars(Ps, Vs).

tablas([], _, [], [], []).
tablas([v(A, D, F)|R], K, [IA|LA], [T|LT], [A|As]) :-
    indice(aula, A, IA),
    indice(dia,  D, ID),
    T is ID * K + F,
    tablas(R, K, LA, LT, As).

xs_de([], []).
xs_de([fv(_, X, _, _, _, _)|Vs], [X|Xs]) :- xs_de(Vs, Xs).

% ------------------------------------------------------------
% Restricciones de a pares
% (no usar forall/findall para POSTEAR restricciones: deshacen los
%  efectos; por eso todo se hace con recursion explicita)
% ------------------------------------------------------------
fd_pares([], _).
fd_pares([V|Vs], Sim) :-
    fd_pares_con(V, Vs, Sim),
    fd_pares(Vs, Sim).

fd_pares_con(_, [], _).
fd_pares_con(V1, [V2|Vs], Sim) :-
    restringir_par(V1, V2, Sim),
    fd_pares_con(V1, Vs, Sim).

restringir_par(fv(S1, _, A1, T1, _, As1), fv(S2, _, A2, T2, _, As2), Sim) :-
    S1 = sesion(_, C1, G1, _, P1, Dur1),
    S2 = sesion(_, C2, G2, _, P2, Dur2),
    (   conflicto_directo(C1, G1, P1, C2, G2, P2)
    ->  no_solape(T1, Dur1, T2, Dur2)
    ;   comparten_aula(As1, As2)
    ->  (A1 #= A2) #==> ((T1 + Dur1 #=< T2) #\/ (T2 + Dur2 #=< T1))
    ;   true
    ),
    simetria_par(Sim, S1, T1, S2, T2).

conflicto_directo(_, _, P, _, _, P) :- !.
conflicto_directo(C, G, _, C, G, _) :- !.
conflicto_directo(C1, G1, _, C2, G2, _) :- excluyentes_par(C1, G1, C2, G2).

no_solape(T1, Dur1, T2, Dur2) :-
    (T1 + Dur1 #=< T2) #\/ (T2 + Dur2 #=< T1).

comparten_aula(As1, As2) :-
    member(A, As1),
    memberchk(A, As2),
    !.

% Reduccion de simetria (mismos mecanismos que busqueda_bt.pl)
simetria_par(Sim, S1, T1, S2, T2) :-
    S1 = sesion(_, C1, G1, I1, _, _),
    S2 = sesion(_, C2, G2, I2, _, _),
    (   sim_intra(Sim), C1 == C2, G1 == G2
    ->  (   I1 < I2 -> T1 #< T2 ; T2 #< T1 )
    ;   true
    ),
    (   sim_inter(Sim), I1 =:= 1, I2 =:= 1
    ->  (   equiv_g(C1, G1, C2, G2) -> T1 #< T2
        ;   equiv_g(C2, G2, C1, G1) -> T2 #< T1
        ;   true
        )
    ;   true
    ).

% ------------------------------------------------------------
% Restricciones redundantes con fd_all_different/1
% ------------------------------------------------------------
redundantes(Vars) :-
    findall(P, member(fv(sesion(_,_,_,_,P,_),_,_,_,_,_), Vars), Ps0),
    sort(Ps0, Ps),
    alldif_profesores(Ps, Vars),
    findall(C-G, member(fv(sesion(_,C,G,_,_,_),_,_,_,_,_), Vars), Gs0),
    sort(Gs0, Gs),
    alldif_grupos(Gs, Vars),
    alldif_aula_tiempo(Vars).

alldif_profesores([], _).
alldif_profesores([P|Ps], Vars) :-
    ts_prof(P, Vars, Ts),
    todos_distintos(Ts),
    alldif_profesores(Ps, Vars).

alldif_grupos([], _).
alldif_grupos([C-G|Gs], Vars) :-
    ts_grupo(C, G, Vars, Ts),
    todos_distintos(Ts),
    alldif_grupos(Gs, Vars).

ts_prof(_, [], []).
ts_prof(P, [fv(sesion(_,_,_,_,P0,_), _, _, T, _, _)|Vs], Ts) :-
    (   P0 == P -> Ts = [T|Ts1] ; Ts = Ts1 ),
    ts_prof(P, Vs, Ts1).

ts_grupo(_, _, [], []).
ts_grupo(C, G, [fv(sesion(_,C0,G0,_,_,_), _, _, T, _, _)|Vs], Ts) :-
    (   C0 == C, G0 == G -> Ts = [T|Ts1] ; Ts = Ts1 ),
    ts_grupo(C, G, Vs, Ts1).

% misma aula y mismo inicio => solape; A*Big+T distinto en todo el sistema
alldif_aula_tiempo(Vars) :-
    k_dia(K),
    findall(D, dia(D), Ds), length(Ds, ND),
    Big is ND * K + 1,
    ats(Vars, Big, ATs),
    todos_distintos(ATs).

ats([], _, []).
ats([fv(_, _, A, T, _, _)|Vs], Big, [AT|ATs]) :-
    AT #= A * Big + T,
    ats(Vs, Big, ATs).

todos_distintos(Ts) :-
    (   Ts = [_, _|_] -> fd_all_different(Ts) ; true ).

% ------------------------------------------------------------
% Etiquetado propio (cuenta nodos y retrocesos, respeta el limite)
%
%   etiquetar(+Xs, +ModoVariable, +ModoValor, +Poda)
%   Poda = none | bb(Vars)   (bb: branch and bound, ver mas abajo)
%
% Cada decision es binaria:  X = W   o   X =\= W  (W = valor elegido).
% contar_nodo/0 lanza limite_alcanzado al superar el limite.
% ------------------------------------------------------------
etiquetar(Xs, MV, MVal, Poda) :-
    pendientes(Xs, Ps),
    (   Ps == []
    ->  true
    ;   elegir_variable(MV, Ps, X),
        elegir_valor(MVal, X, Ps, W),
        contar_nodo,
        (   X = W,
            poda(Poda),
            etiquetar(Xs, MV, MVal, Poda)
        ;   g_inc(retrocesos),
            X #\= W,
            poda(Poda),
            etiquetar(Xs, MV, MVal, Poda)
        )
    ).

pendientes([], []).
pendientes([X|Xs], Ps) :-
    (   integer(X) -> Ps = Ps1 ; Ps = [X|Ps1] ),
    pendientes(Xs, Ps1).

% izq: primera pendiente;  ff: menor dominio (desempata la primera)
elegir_variable(izq, [X|_], X).
elegir_variable(ff, [X|Xs], Mejor) :-
    fd_size(X, S),
    mejor_ff(Xs, X, S, Mejor).

mejor_ff([], M, _, M).
mejor_ff([X|Xs], M, S, Mejor) :-
    fd_size(X, SX),
    (   SX < S -> mejor_ff(Xs, X, SX, Mejor)
    ;   mejor_ff(Xs, M, S, Mejor)
    ).

% up: valor minimo del dominio
elegir_valor(up, X, _, W) :-
    fd_min(X, W).
% lcv: el valor que, tras propagar, deja mas valores en las demas variables
elegir_valor(lcv, X, Ps, W) :-
    fd_min(X, Min),
    fd_max(X, Max),
    findall(Neg-W0,
            (   between(Min, Max, W0),
                X = W0,
                suma_tamanos(Ps, S),
                Neg is -S
            ),
            L),
    (   L == [] -> W = Min ; keysort(L, [_-W|_]) ).

suma_tamanos([], 0).
suma_tamanos([V|Vs], S) :-
    (   integer(V) -> T = 1 ; fd_size(V, T) ),
    suma_tamanos(Vs, S0),
    S is S0 + T.

% ------------------------------------------------------------
% Reconstruir solucion (mismo formato interno que busqueda_bt.pl:
% lista de Sesion-v(Aula, Dia, Franja))
% ------------------------------------------------------------
reconstruir([], [], []).
reconstruir([S-_|Ps], [fv(_, X, _, _, Dom, _)|Vs], [S-V|Rs]) :-
    enesimo(X, Dom, V),
    reconstruir(Ps, Vs, Rs).

enesimo(N, [X|Xs], E) :-
    (   N =:= 1 -> E = X
    ;   N1 is N - 1, enesimo(N1, Xs, E)
    ).

% ------------------------------------------------------------
% Optimizacion de restricciones blandas: branch and bound
%
% Se recorre el arbol de etiquetado. En cada nodo se calcula una COTA
% INFERIOR del costo (cota_inferior/2) y se poda si LB >= mejor costo
% conocido. Al llegar a una hoja se calcula el costo exacto con
% costo_blandas/2 (main.pl); si mejora, se guarda y se sigue buscando
% (fail) hasta agotar el arbol o hallar costo 0.
%
% Cota inferior (siempre valida):
%   prefiere : W si NINGUNA sesion del grupo puede ya comenzar en esa
%              franja (asignadas: no empiezan ahi; pendientes: la
%              propagacion descarta el valor).
%   compacta : W * huecos del grupo, solo cuando todas sus sesiones ya
%              estan asignadas (antes puede bajar al llenarse huecos).
%
% Al terminar se deja en opt_optimo:
%   si : el arbol se agoto (o se hallo costo 0) => solucion OPTIMA
%   no : se alcanzo el limite con una solucion en mano => mejor conocida
%   n_a: no se uso optimizacion
% Si se alcanza el limite SIN ninguna solucion, se relanza
% limite_alcanzado (resolver/3 lo informa).
% ------------------------------------------------------------
buscar_optimo(Vars, Pares, MV, MVal, Sol) :-
    xs_de(Vars, Xs),
    g_assign(opt_mejor, none),
    g_assign(opt_costo, sin),
    catch(
        (   (   etiquetar(Xs, MV, MVal, bb(Vars)),
                registrar(Vars, Pares),
                fail
            ;   true
            ),
            Estado = completo
        ),
        Bola,
        manejar_bola(Bola, Estado)
    ),
    g_read(opt_mejor, Sol),
    Sol \== none,
    (   Estado == completo -> g_assign(opt_optimo, si)
    ;   g_assign(opt_optimo, no)
    ).

manejar_bola(optimo_cero, completo) :- !.
manejar_bola(limite_alcanzado, parcial) :-
    g_read(opt_mejor, M),
    M \== none,
    !.
manejar_bola(Bola, _) :-
    throw(Bola).

poda(none) :- !.
poda(bb(Vars)) :-
    g_read(opt_costo, Mejor),
    (   Mejor == sin
    ->  true
    ;   cota_inferior(Vars, LB),
        LB < Mejor
    ).

registrar(Vars, Pares) :-
    reconstruir(Pares, Vars, Sol0),
    a_horario(Sol0, H0),
    costo_blandas(H0, C),
    g_read(opt_costo, Mejor),
    (   ( Mejor == sin ; C < Mejor )
    ->  g_assign(opt_mejor, Sol0),
        g_assign(opt_costo, C)
    ;   true
    ),
    (   C =:= 0 -> throw(optimo_cero) ; true ).

cota_inferior(Vars, LB) :-
    lb_prefiere(Vars, LP),
    lb_compacta(Vars, LC),
    LB is LP + LC.

lb_prefiere(Vars, LP) :-
    k_dia(K),
    findall(W,
            (   prefiere(C, G, D, F, W),
                indice(dia, D, ID),
                Tp is ID * K + F,
                sin_opcion(Vars, C, G, Tp)
            ),
            Ws),
    suma(Ws, LP).

% ninguna sesion del grupo puede comenzar en el tiempo absoluto Tp
sin_opcion(Vars, C, G, Tp) :-
    \+ (   member(fv(sesion(_, C, G, _, _, _), _, _, T, _, _), Vars),
           \+ \+ T = Tp
       ).

lb_compacta(Vars, LC) :-
    findall(WN,
            (   compacta(C, G, W),
                grupo_asig(Vars, C, G, H),
                huecos_entidad(H, grupo, C-G, N),
                WN is W * N
            ),
            L),
    suma(L, LC).

% asignaciones del grupo; falla si alguna de sus sesiones esta pendiente
grupo_asig([], _, _, []).
grupo_asig([fv(sesion(_, C0, G0, _, P, Dur), X, _, _, Dom, _)|Vs], C, G, H) :-
    (   C0 == C, G0 == G
    ->  integer(X),
        enesimo(X, Dom, v(A, D, F)),
        H = [asignacion(C, G, P, A, D, F, Dur)|H1]
    ;   H = H1
    ),
    grupo_asig(Vs, C, G, H1).
