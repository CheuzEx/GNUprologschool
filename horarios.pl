% ============================================================
% horarios.pl -- Fase 1: lectura, parsing y representacion
% Asignacion de Horarios Universitarios (GNU Prolog)
% ============================================================

:- dynamic(dia/1).
:- dynamic(num_franjas/1).
:- dynamic(hora_inicio/1).
:- dynamic(duracion_franja/1).
:- dynamic(aula/3).
:- dynamic(profesor/4).
:- dynamic(grupo/7).
:- dynamic(imparte/3).
:- dynamic(aula_fija/3).
:- dynamic(prohibida/4).
:- dynamic(excluyentes/4).
:- dynamic(prefiere/5).
:- dynamic(compacta/3).
:- dynamic(original/3).      % original(Tipo, IdNormalizado, TextoOriginal) para la salida
:- discontiguous(procesar_registro/3).

% ---------- lectura de archivo, linea por linea ----------
% GNU Prolog 1.4.5 no trae read_line/2 ni split_string/4, asi que
% se construyen a mano con get_char/2 y append/3.

leer_lineas(Path, Lineas) :-
    open(Path, read, S),
    leer_todas(S, Lineas),
    close(S).

leer_todas(S, Lineas) :-
    leer_linea(S, Chars, Estado),
    atom_chars(Linea, Chars),
    continuar(Estado, Chars, Linea, S, Lineas).

continuar(fin, [], _Linea, _S, []) :- !.
continuar(fin, [_|_], Linea, _S, [Linea]) :- !.
continuar(continua, _Chars, Linea, S, [Linea|Resto]) :-
    leer_todas(S, Resto).

leer_linea(S, Chars, Estado) :-
    get_char(S, C),
    procesar_char(C, S, Chars, Estado).

procesar_char(end_of_file, _S, [], fin) :- !.
procesar_char('\n', _S, [], continua) :- !.
% CORREGIDO: se descarta '\r' para tolerar archivos con fin de linea
% CRLF (Windows); si no, cada ultimo campo de la linea trae un '\r'.
procesar_char('\r', S, Chars, Estado) :- !,
    leer_linea(S, Chars, Estado).
procesar_char(C, S, [C|Resto], Estado) :-
    leer_linea(S, Resto, Estado).

% ---------- split generico por un separador, sobre listas de chars ----------
% Conserva campos vacios al final (ej "a;b;" -> [[a],[b],[]]).

split_on(Sep, Chars, [Campo|Resto]) :-
    ( append(Campo, [Sep|Despues], Chars)
    -> split_on(Sep, Despues, Resto)
    ;  Campo = Chars, Resto = []
    ).

% ---------- dividir una linea en campos por ';', recortando espacios ----------

dividir_campos(Linea, Campos) :-
    atom_chars(Linea, Chars),
    split_on(';', Chars, ListasDeChars),
    recortar_todos(ListasDeChars, Campos).

recortar_todos([], []).
recortar_todos([Chars|RestoChars], [Atomo|RestoAtomos]) :-
    recortar(Chars, Recortado),
    atom_chars(Atomo, Recortado),
    recortar_todos(RestoChars, RestoAtomos).

recortar(Chars, Recortado) :-
    quitar_espacios_inicio(Chars, SinInicio),
    reverse(SinInicio, Invertido),
    quitar_espacios_inicio(Invertido, SinFinInvertido),
    reverse(SinFinInvertido, Recortado).

% espacios y tabuladores
quitar_espacios_inicio([' '|Resto], SinEspacios) :- !,
    quitar_espacios_inicio(Resto, SinEspacios).
quitar_espacios_inicio(['\t'|Resto], SinEspacios) :- !,
    quitar_espacios_inicio(Resto, SinEspacios).
quitar_espacios_inicio(Chars, Chars).

% recortar sobre un atomo completo
recortar_atomo(Atomo, Recortado) :-
    atom_chars(Atomo, Chars),
    recortar(Chars, RChars),
    atom_chars(Recortado, RChars).

% ---------- conversion atomo -> numero ----------
% RENOMBRADO: antes se llamaba atom_number/2, que en versiones recientes
% de GNU Prolog ya es predicado predefinido (redefinirlo da
% permission_error). Con otro nombre funciona en cualquier version.
% Lanza excepcion de sintaxis si el atomo no es un numero; valida/1
% ya lo comprobo antes de cargar.

atomo_numero(Atom, Number) :-
    atom_codes(Atom, Codes),
    number_codes(Number, Codes).

% ---------- normalizacion de identificadores ----------
% minusculas y guion -> guion_bajo (IC-1802 -> ic_1802, P-001 -> p_001)

normalizar_id(Original, Normalizado) :-
    atom_codes(Original, Codigos),
    normalizar_codigos(Codigos, CodigosNorm),
    atom_codes(Normalizado, CodigosNorm).

normalizar_codigos([], []).
normalizar_codigos([C|Cs], [C2|C2s]) :-
    normalizar_codigo(C, C2),
    normalizar_codigos(Cs, C2s).

normalizar_codigo(0'-, 0'_) :- !.
normalizar_codigo(C, C2) :- C >= 0'A, C =< 0'Z, !, C2 is C + 32.
normalizar_codigo(C, C).

% ---------- clasificacion de lineas ----------
% CORREGIDO: la linea se recorta primero. Asi una linea con solo
% espacios/tabs es 'blanco' y un encabezado como "#:CONFIG   " (o
% "#: CONFIG") se reconoce como seccion.

clasificar_linea(Linea0, Tipo) :-
    recortar_atomo(Linea0, Linea),
    clasificar_recortada(Linea, Tipo).

clasificar_recortada(Linea, blanco) :- Linea == '', !.
clasificar_recortada(Linea, seccion(Nombre)) :-
    atom_concat('#:', Nombre0, Linea), !,
    recortar_atomo(Nombre0, Nombre).
clasificar_recortada(Linea, comentario) :-
    atom_concat('#', _, Linea), !.
clasificar_recortada(Linea, registro(Campos)) :-
    dividir_campos(Linea, Campos).

% ---------- parseo de disponibilidad de profesor: "L1-L7,M1-M7" ----------
% Se toleran espacios alrededor de comas y guiones.

parsear_disponibilidad(Atom, total) :- Atom == '', !.
parsear_disponibilidad(Atom, Rangos) :-
    atom_chars(Atom, Chars),
    split_on(',', Chars, ListasRangos),
    parsear_lista_rangos(ListasRangos, Rangos).

parsear_lista_rangos([], []).
parsear_lista_rangos([CharsUnRango|Resto], [rango(Dia, Desde, Hasta)|RestoRangos]) :-
    split_on('-', CharsUnRango, [CharsInicio0, CharsFin0]),
    recortar(CharsInicio0, CharsInicio),
    recortar(CharsFin0, CharsFin),
    extraer_dia_franja(CharsInicio, Dia, Desde),
    extraer_dia_franja(CharsFin, _DiaFin, Hasta),
    parsear_lista_rangos(Resto, RestoRangos).

% extraer_dia_franja(+Chars, -DiaMinuscula, -NumeroFranja)
% Chars viene de algo como "L1" o "V5": primer char = dia, resto = numero
extraer_dia_franja([CDia|CharsNum], DiaMin, Num) :-
    atom_chars(DiaMayus, [CDia]),
    normalizar_id(DiaMayus, DiaMin),
    atom_chars(AtomoNum, CharsNum),
    atomo_numero(AtomoNum, Num).

% igual, pero recibe el atomo completo directo (para RESTRICCION: "V5")
extraer_dia_franja_atom(Atom, DiaMin, Franja) :-
    atom_chars(Atom, Chars),
    extraer_dia_franja(Chars, DiaMin, Franja).

% ---------- asertar los dias declarados en CONFIG ----------

asertar_dias(ListaAtom) :-
    atom_chars(ListaAtom, Chars),
    split_on(',', Chars, ListasChars),
    asertar_cada_dia(ListasChars).

asertar_cada_dia([]).
asertar_cada_dia([Chars|Resto]) :-
    atom_chars(DiaMayus, Chars),
    normalizar_id(DiaMayus, DiaMin),
    registrar_original(dia, DiaMin, DiaMayus),
    ( dia(DiaMin) -> true ; assertz(dia(DiaMin)) ),
    asertar_cada_dia(Resto).

% ---------- bucle principal: recorre lineas llevando la seccion actual ----------

cargar_instancia(Path) :-
    limpiar_hechos,
    leer_lineas(Path, Lineas),
    procesar_con_seccion(Lineas, 1, ninguna).

% limpia hechos de una carga anterior (util si se llama cargar_instancia
% mas de una vez en la misma sesion)
limpiar_hechos :-
    retractall(dia(_)), retractall(num_franjas(_)),
    retractall(hora_inicio(_)), retractall(duracion_franja(_)),
    retractall(aula(_,_,_)), retractall(profesor(_,_,_,_)),
    retractall(grupo(_,_,_,_,_,_,_)), retractall(imparte(_,_,_)),
    retractall(aula_fija(_,_,_)), retractall(prohibida(_,_,_,_)),
    retractall(excluyentes(_,_,_,_)), retractall(prefiere(_,_,_,_,_)),
    retractall(compacta(_,_,_)),
    retractall(original(_,_,_)).

% registrar_original(+Tipo, +Norm, +Orig): recuerda como se escribio en la instancia
% (A-101, P-001, L...), para mostrarlo igual en el archivo de salida.
registrar_original(Tipo, Norm, Orig) :-
    (   original(Tipo, Norm, _) -> true ; assertz(original(Tipo, Norm, Orig)) ).

procesar_con_seccion([], _N, _Seccion).
procesar_con_seccion([L|Resto], N, SeccionActual) :-
    clasificar_linea(L, Tipo),
    manejar_tipo(Tipo, N, SeccionActual, SeccionNueva),
    N1 is N + 1,
    procesar_con_seccion(Resto, N1, SeccionNueva).

manejar_tipo(blanco, _N, Seccion, Seccion).
manejar_tipo(comentario, _N, Seccion, Seccion).
manejar_tipo(seccion(Nombre), _N, _SeccionVieja, Nombre).
% CORREGIDO: si un registro no se puede procesar (seccion 'ninguna',
% aridad o clave desconocida) ya no se falla en silencio: se lanza una
% excepcion con el numero de linea. main.pl la traduce a error_instancia.
manejar_tipo(registro(Campos), N, Seccion, Seccion) :-
    (   procesar_registro(Seccion, Campos, N)
    ->  true
    ;   throw(error_registro(N, Seccion, Campos))
    ).

% ---------- CONFIG ----------

procesar_registro('CONFIG', [dias, Lista], _N) :- !, asertar_dias(Lista).
procesar_registro('CONFIG', [franjas, NStr], _N) :- !,
    atomo_numero(NStr, N), assertz(num_franjas(N)).
procesar_registro('CONFIG', [inicio, HHMM], _N) :- !,
    assertz(hora_inicio(HHMM)).
procesar_registro('CONFIG', [duracion_franja, DStr], _N) :- !,
    atomo_numero(DStr, D), assertz(duracion_franja(D)).

% ---------- AULA ----------

procesar_registro('AULA', [Cod, CapStr, Tipo], _N) :- !,
    normalizar_id(Cod, CodN),
    registrar_original(aula, CodN, Cod),
    atomo_numero(CapStr, Cap),
    assertz(aula(CodN, Cap, Tipo)).

% ---------- PROFESOR ----------

procesar_registro('PROFESOR', [Cod, Nombre, MaxStr, Disp], _N) :- !,
    normalizar_id(Cod, CodN),
    registrar_original(profesor, CodN, Cod),
    atomo_numero(MaxStr, Max),
    parsear_disponibilidad(Disp, DispParsed),
    assertz(profesor(CodN, Nombre, Max, DispParsed)).

% ---------- CURSO ----------

procesar_registro('CURSO', [Cod, Nombre, Grupo, InscStr, SemStr, DurStr, Requiere], _N) :- !,
    normalizar_id(Cod, CodN),
    normalizar_id(Grupo, GrupoN),
    registrar_original(curso, CodN, Cod),
    registrar_original(grupo, GrupoN, Grupo),
    atomo_numero(InscStr, Insc),
    atomo_numero(SemStr, Sem),
    atomo_numero(DurStr, Dur),
    assertz(grupo(CodN, GrupoN, Nombre, Insc, Sem, Dur, Requiere)).

% ---------- IMPARTE ----------

procesar_registro('IMPARTE', [Curso, Grupo, Prof], _N) :- !,
    normalizar_id(Curso, CursoN),
    normalizar_id(Grupo, GrupoN),
    normalizar_id(Prof, ProfN),
    assertz(imparte(CursoN, GrupoN, ProfN)).

% ---------- RESTRICCION (aridad variable segun el tipo) ----------

procesar_registro('RESTRICCION', [Tipo | Args], N) :- !,
    procesar_restriccion(Tipo, Args, N).

procesar_restriccion(aula_fija, [Curso, Grupo, Aula], _N) :- !,
    normalizar_id(Curso, C), normalizar_id(Grupo, G), normalizar_id(Aula, A),
    assertz(aula_fija(C, G, A)).
procesar_restriccion(prohibida, [Curso, Grupo, DiaFranja], _N) :- !,
    normalizar_id(Curso, C), normalizar_id(Grupo, G),
    extraer_dia_franja_atom(DiaFranja, Dia, Franja),
    assertz(prohibida(C, G, Dia, Franja)).
procesar_restriccion(excluyentes, [C1s, G1s, C2s, G2s], _N) :- !,
    normalizar_id(C1s, C1), normalizar_id(G1s, G1),
    normalizar_id(C2s, C2), normalizar_id(G2s, G2),
    assertz(excluyentes(C1, G1, C2, G2)).
procesar_restriccion(prefiere, [Curso, Grupo, DiaFranja, PesoStr], _N) :- !,
    normalizar_id(Curso, C), normalizar_id(Grupo, G),
    extraer_dia_franja_atom(DiaFranja, Dia, Franja),
    atomo_numero(PesoStr, Peso),
    assertz(prefiere(C, G, Dia, Franja, Peso)).
procesar_restriccion(compacta, [Curso, Grupo, PesoStr], _N) :- !,
    normalizar_id(Curso, C), normalizar_id(Grupo, G),
    atomo_numero(PesoStr, Peso),
    assertz(compacta(C, G, Peso)).
