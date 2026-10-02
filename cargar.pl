% cargar.pl -- carga el proyecto para uso interactivo
%
%   $ gprolog --consult-file cargar.pl
%   | ?- main('campus-central.dat', 'salida.txt', clpfd).
%   | ?- main('campus-central.dat', 'salida.txt', estrategia(bt,[heuristica(mrv)])).
%
% Para experimentos, consultar ademas pruebas_bt.pl y usar comparar/3.

:- consult('horarios.pl').
:- consult('busqueda_bt.pl').
:- consult('busqueda_fd.pl').
:- consult('valida.pl').
:- consult('main.pl').
