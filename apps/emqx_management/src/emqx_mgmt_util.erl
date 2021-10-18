%%--------------------------------------------------------------------
%% Copyright (c) 2020-2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mgmt_util).

-export([ strftime/1
        , datetime/1
        , kmg/1
        , ntoa/1
        , merge_maps/2
        , batch_operation/3
        ]).

-export([ bad_request/0
        , bad_request/1
        , properties/1
        , page_params/0
        , schema/1
        , schema/2
        , object_schema/1
        , object_schema/2
        , array_schema/1
        , array_schema/2
        , object_array_schema/1
        , object_array_schema/2
        , page_schema/1
        , page_object_schema/1
        , error_schema/1
        , error_schema/2
        , batch_schema/1
        ]).

-export([generate_response/1]).


-export([urldecode/1]).

-define(KB, 1024).
-define(MB, (1024*1024)).
-define(GB, (1024*1024*1024)).

%%--------------------------------------------------------------------
%% Strftime
%%--------------------------------------------------------------------

strftime({MegaSecs, Secs, _MicroSecs}) ->
    strftime(datetime(MegaSecs * 1000000 + Secs));

strftime(Secs) when is_integer(Secs) ->
    strftime(datetime(Secs));

strftime({{Y,M,D}, {H,MM,S}}) ->
    lists:flatten(
        io_lib:format(
            "~4..0w-~2..0w-~2..0w ~2..0w:~2..0w:~2..0w", [Y, M, D, H, MM, S])).

datetime(Timestamp) when is_integer(Timestamp) ->
    Epoch = calendar:datetime_to_gregorian_seconds({{1970,1,1}, {0,0,0}}),
    Universal = calendar:gregorian_seconds_to_datetime(Timestamp + Epoch),
    calendar:universal_time_to_local_time(Universal).

kmg(Byte) when Byte > ?GB ->
    kmg(Byte / ?GB, "G");
kmg(Byte) when Byte > ?MB ->
    kmg(Byte / ?MB, "M");
kmg(Byte) when Byte > ?KB ->
    kmg(Byte / ?KB, "K");
kmg(Byte) ->
    Byte.
kmg(F, S) ->
    iolist_to_binary(io_lib:format("~.2f~ts", [F, S])).

ntoa({0,0,0,0,0,16#ffff,AB,CD}) ->
    inet_parse:ntoa({AB bsr 8, AB rem 256, CD bsr 8, CD rem 256});
ntoa(IP) ->
    inet_parse:ntoa(IP).

merge_maps(Default, New) ->
    maps:fold(fun(K, V, Acc) ->
        case maps:get(K, Acc, undefined) of
            OldV when is_map(OldV),
                      is_map(V) -> Acc#{K => merge_maps(OldV, V)};
            _ -> Acc#{K => V}
        end
    end, Default, New).

urldecode(S) ->
    emqx_http_lib:uri_decode(S).

%%%==============================================================================================
%% schema util
schema(Ref) when is_atom(Ref) ->
    json_content_schema(minirest:ref(atom_to_binary(Ref, utf8)));
schema(SchemaOrDesc) ->
    json_content_schema(SchemaOrDesc).
schema(Ref, Desc) when is_atom(Ref) ->
    json_content_schema(minirest:ref(atom_to_binary(Ref, utf8)), Desc);
schema(Schema, Desc) ->
    json_content_schema(Schema, Desc).

object_schema(Properties) when is_map(Properties) ->
    json_content_schema(#{type => object, properties => Properties}).
object_schema(Properties, Desc) when is_map(Properties) ->
    json_content_schema(#{type => object, properties => Properties}, Desc).

array_schema(Ref) when is_atom(Ref) ->
    json_content_schema(#{type => array, items => minirest:ref(atom_to_binary(Ref, utf8))}).
array_schema(Ref, Desc) when is_atom(Ref) ->
    json_content_schema(#{type => array, items => minirest:ref(atom_to_binary(Ref, utf8))}, Desc);
array_schema(Schema, Desc) ->
    json_content_schema(#{type => array, items => Schema}, Desc).

object_array_schema(Properties) when is_map(Properties) ->
    json_content_schema(#{type => array, items => #{type => object, properties => Properties}}).
object_array_schema(Properties, Desc) ->
    json_content_schema(#{type => array, items => #{type => object, properties => Properties}}, Desc).

page_schema(Ref) when is_atom(Ref) ->
    page_schema(minirest:ref(atom_to_binary(Ref, utf8)));
page_schema(Schema) ->
    Schema1 = #{
        type => object,
        properties => #{
            meta => #{
                type => object,
                properties => properties([{page, integer},
                                          {limit, integer},
                                          {count, integer}])
            },
            data => #{
                type => array,
                items => Schema
            }
        }
    },
    json_content_schema(Schema1).

page_object_schema(Properties) when is_map(Properties) ->
    page_schema(#{type => object, properties => Properties}).

error_schema(Description) ->
    error_schema(Description, ['RESOURCE_NOT_FOUND']).

error_schema(Description, Enum) ->
    Schema = #{
        type => object,
        properties => properties([{code, string, <<>>, Enum},
                                  {message, string}])
    },
    json_content_schema(Schema, Description).

batch_schema(DefName) when is_atom(DefName) ->
    batch_schema(atom_to_binary(DefName, utf8));
batch_schema(DefName) when is_binary(DefName) ->
    Schema = #{
        type => object,
        properties => #{
            success => #{
                type => integer,
                description => <<"Success count">>},
            failed => #{
                type => integer,
                description => <<"Failed count">>},
            detail => #{
                type => array,
                description => <<"Failed object & reason">>,
                items => #{
                    type => object,
                    properties =>
                    #{
                        data => minirest:ref(DefName),
                        reason => #{
                            type => <<"string">>}}}}}},
    json_content_schema(Schema).

json_content_schema(Schema) when is_map(Schema) ->
    #{content => #{'application/json' => #{schema => Schema}}};
json_content_schema(Desc) when is_binary(Desc) ->
    #{description => Desc}.
json_content_schema(Schema, Desc) ->
    #{
        content => #{'application/json' => #{schema => Schema}},
        description => Desc
    }.

%%%==============================================================================================
batch_operation(Module, Function, ArgsList) ->
    Failed = batch_operation(Module, Function, ArgsList, []),
    Len = erlang:length(Failed),
    Success = erlang:length(ArgsList) - Len,
    Fun = fun({Args, Reason}, Detail) -> [#{data => Args, reason => io_lib:format("~p", [Reason])} | Detail] end,
    #{success => Success, failed => Len, detail => lists:foldl(Fun, [], Failed)}.

batch_operation(_Module, _Function, [], Failed) ->
    lists:reverse(Failed);
batch_operation(Module, Function, [Args | ArgsList], Failed) ->
    case erlang:apply(Module, Function, Args) of
        ok ->
            batch_operation(Module, Function, ArgsList, Failed);
        {error ,Reason} ->
            batch_operation(Module, Function, ArgsList, [{Args, Reason} | Failed])
    end.

properties(Props) ->
    properties(Props, #{}).
properties([], Acc) ->
    Acc;
properties([Key| Props], Acc) when is_atom(Key) ->
    properties(Props, maps:put(Key, #{type => string}, Acc));
properties([{Key, Type} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => Type}, Acc));
properties([{Key, object, Props1} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => object,
                                      properties => properties(Props1)}, Acc));
properties([{Key, {array, object}, Props1} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => array,
                                      items => #{type => object,
                                                 properties => properties(Props1)
                                                }}, Acc));
properties([{Key, {array, Type}, Desc} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => array,
                                      items => #{type => Type},
                                      description => Desc}, Acc));
properties([{Key, Type, Desc} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => Type, description => Desc}, Acc));
properties([{Key, Type, Desc, Enum} | Props], Acc) ->
    properties(Props, maps:put(Key, #{type => Type,
                                      description => Desc,
                                      enum => Enum}, Acc)).
page_params() ->
    [#{
        name => page,
        in => query,
        description => <<"Page">>,
        schema => #{type => integer, default => 1}
    },
    #{
        name => limit,
        in => query,
        description => <<"Page size">>,
        schema => #{type => integer, default => emqx_mgmt:max_row_limit()}
    }].

bad_request() ->
    bad_request(<<"Bad Request">>).
bad_request(Desc) ->
    object_schema(properties([{message, string}, {code, string}]), Desc).

%%%==============================================================================================
%% Response util

generate_response(QueryResult) ->
    case QueryResult of
        {error, page_limit_invalid} ->
            {400, #{code => <<"INVALID_PARAMETER">>, message => <<"page_limit_invalid">>}};
        Response ->
            {200, Response}
    end.
