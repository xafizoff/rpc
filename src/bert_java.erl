-module(bert_java).
-include("io.hrl").
-export([parse_transform/2]).
-compile(export_all).

parse_transform(Forms, _Options) ->
    File = filename:join([?JAVA,"java.java"]),
    io:format("Generated Java: ~p~n",[File]),
%    file:write_file(File,directives(Forms)),
    Forms.
directives(Forms) -> iolist_to_binary([ form(F) || F <- Forms ]).
form({attribute,_,record,{_List,_T}}) -> [];
form(_Form) ->  [].
