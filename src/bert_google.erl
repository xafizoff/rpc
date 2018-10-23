-module(bert_google).
-export([parse_transform/2]).
-compile(export_all).
-include("io.hrl").

tab(N) -> bert:tab(N).
parse_transform(Forms, _Options) -> lists:map(fun save/1,gen(Forms)), Forms.
gen(Forms) -> lists:flatten([ form(F) || F <- Forms ]).
save({[],_}) -> [];
save({File,IO}) ->
  io:format("Generated Protobuf Model: ~p~n",[File]),
  Imprint = "// Generated by https://github.com/synrc/bert\n",
  file:write_file(File,iolist_to_binary([Imprint, IO])).

form({attribute,_,type,{Field,{type,_,union,Atoms},[]}}) ->
    %io:format("TYPE: ~p~n",[{Field,Atoms}]),
    A = [ X || {_,_,X} <- Atoms ],
    application:set_env(bert,{deps,Field},[]),
    File = filename:join(?GOOGLE,atom_to_list(Field)++".proto"),
    {File,[header(Field),enum(Field,[],A)]};

form({attribute,_,record,{List,T}}) ->
    %io:format("RECORD: ~p~n",[{List,T}]),
    application:set_env(bert,{deps,List},[]),
    case lists:member(List,application:get_env(bert, disallowed, [])) of
         true -> []; _ -> class(List,T) end;

form(_X) ->
    %io:format("UNKNOWN: ~p~n",[_X]),
    {[],[]}.

class(List,T) ->
    application:set_env(bert, enums, []),
    File = filename:join(?GOOGLE,atom_to_list(List)++".proto"),
    Fields = [
    begin {Field,Type,_,Args} = case L of
          {_,{_,_,{atom,_,_Field},_Value},{type,_,_Type,_Args}} -> {_Field,_Type,_Value,_Args};
          {_,{_,_,{atom,_,_Field},_Value},{_,_,_Type,_Args}} -> {_Field, _Type, _Value, _Args};
          {_,{_,_,{atom,_,_Field}},{type,_,_Type,[]}} -> {_Field,_Type,[],[]};
          {_,_,{atom,_,_Field},{call,_,_,_}} -> {_Field,binary,[],[]};
          {_,_,{atom,_,_Field},{nil,_}} -> {_Field,binary,[],[]};
          {_,_,{atom,_,_Field}} -> {_Field,atom,[],[]};
          {_,_,{atom,_,_Field},{_Type,_,_Value}} -> {_Field,_Type,_Value,[]}
          end,
          %io:format("DEBUG: ~p~n",[{Field,Type,Args}]),
          tab(1) ++ infer(List,Type,Args,atom_to_list(Field),integer_to_list(Pos))
    end || {L,Pos} <- lists:zip(T,lists:seq(1,length(T))) ],
    Res = lists:concat(["message ",List, "{\n", Fields, "\n}\n"]),
    {File,[header(List),enums(),Res]}.

header(Name) -> lists:concat(
  [ "syntax = \"proto3\";\n\n",
    [ lists:concat(["import public \"", Import,".proto\";\n"])
      || Import <- application:get_env(bert,{deps,Name},[]), Import /= Name ],
    "import \"google/protobuf/any.proto\";\n",
    "option java_generic_services = true;\n",
    "option java_multiple_files = true;\n",
    "option java_package = \"", Name, ".grpc\";\n"
    "option java_outer_classname = \"", Name, "Cls\";\n\n" ]).

enum(F,Sfx,Enums) ->
    X = "enum " ++ lists:concat([F,Sfx]) ++ " {\n" ++
    [ tab(1) ++ lists:concat([Enum]) ++ " = " ++ lists:concat([Pos]) ++ ";\n"
    || {Pos,Enum} <- lists:zip(lists:seq(0,length(Enums)-1),Enums) ] ++ "}\n\n",
    case Enums of
         [] -> [];
          _ -> X
    end.

enums() -> lists:concat(
  [ begin
        {_,F} = Name,
        Enums = application:get_env(bert,{enum,Name},[]),
        enum(F,"Enum",Enums)
    end || Name <- application:get_env(bert, enums, []) ]).

keyword(_M,list,   [{type,_,atom,[]}], _)      -> "repeated google.protobuf.Any";
keyword(_M,list,   [{type,_,union, _List}], _) -> "repeated google.protobuf.Any";
keyword(_M,list,   [{type,_,record,[{atom,_,Name}]}], _) ->
    application:set_env(bert, {deps,_M}, [Name] ++ application:get_env(bert,{deps,_M},[])),
    lists:concat(["repeated ", Name]);
keyword(_M,list,   [{type,_,user_type,[{atom,_,Name}]}], _) ->
    application:set_env(bert, {deps,_M}, [Name] ++ application:get_env(bert,{deps,_M},[])),
    lists:concat(["repeated ", Name]);
keyword(_M,record, [{atom,_,Name}], _) ->
    application:set_env(bert, {deps,_M}, [Name] ++ application:get_env(bert,{deps,_M},[])),
    lists:concat([Name]);
keyword(_M,list, _Args,_)   -> "repeated";
keyword(_M,tuple,_List,_)   -> "message";
keyword(_M,term,_Args,_)    -> "bytes";
keyword(_M,integer,_Args,_) -> "int64";
keyword(_M,boolean,_Args,_) -> "bool";
keyword(_M,atom,_Args,_)    -> "string";
keyword(_M,binary,_Args,_)  -> "string";
keyword(_M,union,_Args,_X)  -> "oneof";
keyword(_M,nil,_Args,_)     -> "bytes";
keyword(_M,Name,_B,_) ->
    application:set_env(bert, {deps,_M}, [Name] ++ application:get_env(bert,{deps,_M},[])),
    lists:concat([Name]).

infer(_Message,[],_Args,_Field,_Pos) -> [];
infer(Message,union,Args,Field,Pos) ->
    {Atoms,Rest} = lists:partition(
       fun ({atom,_,_}) -> true;
                    (_) -> false end, Args),
    application:set_env(bert,{enum,{Message,Field}},[ X || {_,_,X} <- Atoms ]),
    application:set_env(bert, enums, [{Message,Field}] ++ application:get_env(bert,enums,[])),
    case {Atoms,Rest} of
         {[],_} -> simple(union,Args,{Field,Args,Pos});
         {_,[{type,_,nil,[]}]} -> Field ++ "Enum "++ Field ++" = " ++ Pos ++ ";\n";
         {_,[]} -> Field ++ "Enum " ++ Field ++ " = " ++ Pos ++ ";\n";
              _ ->  simple(union,Args,{Field,Args,Pos})  end;

infer(Message,Type,Args,Field,Pos)  ->
    keyword(Message,Type,Args,{Field,Args}) ++ " " ++ Field ++ " = " ++ nitro:to_list(Pos) ++ ";\n".

simple(L,[{type,_,nil,_},{type,_,Name,Args}],{Field,_Args2,Pos}) ->
    infer(L,Name,Args,Field,Pos);
simple(L,[{type,_,Name,Args},{type,_,nil,_}],{Field,_Args2,Pos}) ->
    infer(L,Name,Args,Field,Pos);
simple(L,Types,{Field,Args,Pos}) when length(Types) == 1 ->
    infer(L,[Types],Args,Field,integer_to_list(Pos));
simple(L,Types,{Field,Args,_Pos}) ->
    "oneof " ++ Field ++ " {\n" ++
    lists:concat([ tab(2) ++ infer(L,Type,Args,lists:concat(["a",Pos]),integer_to_list(Pos))
                   || {{type,_,Type,_Args},Pos}
                   <- lists:zip(Types,lists:seq(1,length(Types))) ]) ++ tab(1) ++ "}\n";
simple(_,_,_) -> "google.protobuf.Any".
