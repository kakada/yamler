-module(yaml_schema_ruby).

-behaviour(yaml_schema).

-export([init/1, destroy/1]).
-export([resolve_mapping_tag/3, resolve_sequence_tag/3, resolve_scalar_tag/4]).
-export([construct_mapping/3, construct_sequence/3, construct_scalar/3]).
-export([marshal/2]).

%% @doc Initialize state that will be made available to all schema calls.
%% Put things like precompiled regular expressions and settings gleaned from the proplist.
%% Use of this state variable is optional; you may just return a dummy value if your schema is simple.
-spec init(Opts::proplists:proplist()) -> term().
init(_Opts) -> no_state.

%% @doc Destroy the schema's state.
-spec destroy(term()) -> term().
destroy(_State) -> ok.

%% @doc Resolve a mapping tag.  Return nomatch if the tag is invalid.
-spec resolve_mapping_tag( Tag::null | binary(), Value::binary(), State::term() ) ->
      {ok, ResolvedTag::term()} | nomatch.
resolve_mapping_tag(Tag, _Value, _State) -> resolve_mapping_tag(Tag).

resolve_mapping_tag(<<"!">>)                     -> {ok, 'tag:yaml.org,2002:map'};
resolve_mapping_tag(<<"tag:yaml.org,2002:map">>) -> {ok, 'tag:yaml.org,2002:map'};
resolve_mapping_tag(null)                        -> {ok, 'tag:yaml.org,2002:map'};
resolve_mapping_tag(<<"!ruby/hash:ActiveSupport::HashWithIndifferentAccess">>) ->
  {ok, 'tag:yaml.org,2002:map'};
resolve_mapping_tag(<<"!ruby/object:", _/binary>>) ->
  {ok, 'tag:yaml.org,2002:map'}.

%% @doc Construct a mapping.  Return nomatch if the tag is invalid.
-spec construct_mapping(ResolvedTag::term(), Value::binary(), State::term()) ->
      {ok, ConstructedValue::term()} | nomatch.
construct_mapping('tag:yaml.org,2002:map', Value, _State) -> {ok, Value};
construct_mapping(_, _, _State) -> nomatch.


%% @doc Resolve a sequence tag.  Return nomatch if the tag is invalid.
-spec resolve_sequence_tag( Tag::null | binary(), Value::binary(), State::term() ) ->
      {ok, ResolvedTag::term()} | nomatch.
resolve_sequence_tag(Tag, _Value, _State) -> resolve_sequence_tag(Tag).
resolve_sequence_tag(<<"!">>)                     -> {ok, 'tag:yaml.org,2002:seq'};
resolve_sequence_tag(<<"tag:yaml.org,2002:seq">>) -> {ok, 'tag:yaml.org,2002:seq'};
resolve_sequence_tag(null)                        -> {ok, 'tag:yaml.org,2002:seq'};
resolve_sequence_tag(_)                           -> nomatch.

%% @doc Construct a sequence.  Return nomatch if the tag is invalid.
-spec construct_sequence(ResolvedTag::term(), Value::binary(), State::term()) ->
      {ok, ConstructedValue::term()} | nomatch.
construct_sequence('tag:yaml.org,2002:seq', Value, _State) -> {ok, Value};
construct_sequence(_, _, _State) -> nomatch.

%% @doc Resolve a scalar tag.  Return nomatch if the tag is invalid.
-spec resolve_scalar_tag( Tag::null | binary(), Value::binary(), Style::yaml_libyaml:scalar_style(), State::term() ) ->
      {ok, ResolvedTag::term()} | nomatch.
resolve_scalar_tag(<<"!">>, _, _, _)                     -> {ok, 'tag:yaml.org,2002:str'};
resolve_scalar_tag(<<"tag:yaml.org,2002:str">>, _, _, _) -> {ok, 'tag:yaml.org,2002:str'};

resolve_scalar_tag(null, <<"true">>, plain, _State)      -> {ok, 'tag:yaml.org,2002:bool'};
resolve_scalar_tag(null, <<"false">>, plain, _State)      -> {ok, 'tag:yaml.org,2002:bool'};

resolve_scalar_tag(null, <<$:, _/binary>>, plain, _)     -> {ok, '!ruby/symbol'};
resolve_scalar_tag(null, Value, plain, _) ->
  case re:run(Value, "^[^0]\\d+$", [{capture, none}]) of
    match   -> {ok, 'tag:yaml.org,2002:int'};
    nomatch -> {ok, 'tag:yaml.org,2002:str'}
  end;

resolve_scalar_tag(null, _, _, _)                        -> {ok, 'tag:yaml.org,2002:str'}.

%% @doc Construct a scalar.  Return nomatch if the tag is invalid.
-spec construct_scalar(ResolvedTag::term(), Value::binary(), State::term()) ->
      {ok, ConstructedValue::term()} | nomatch.
construct_scalar('tag:yaml.org,2002:str', Value, _State) ->
  {ok, binary_to_list(Value)};

construct_scalar('!ruby/symbol', <<$:, Atom/binary>>, _State) ->
  {ok, binary_to_atom(Atom, utf8)};

construct_scalar('tag:yaml.org,2002:int', Value, _State) ->
  {ok, list_to_integer(binary_to_list(Value))};

construct_scalar('tag:yaml.org,2002:bool', <<"true">>, _State) ->
  {ok, true};
construct_scalar('tag:yaml.org,2002:bool', <<"false">>, _State) ->
  {ok, false};

construct_scalar(_, _, _State) -> nomatch.

marshal(Object, State) when is_list(Object) or is_binary(Object) ->
  case yaml_schema_failsafe:marshal(Object, State) of
    Scalar = {scalar, Value, Tag, _Style} ->
      case resolve_scalar_tag(Tag, Value, plain, State) of
        {ok, 'tag:yaml.org,2002:str'} -> Scalar;
        _ -> {scalar, Value, Tag, single_quoted}
      end;
    X -> X
  end;
marshal(true, _State) -> {scalar, <<"true">>, null, plain};
marshal(false, _State) -> {scalar, <<"false">>, null, plain};
marshal(Atom, State) when is_atom(Atom) ->
  AtomBin = atom_to_binary(Atom, utf8),
  yaml_schema_failsafe:marshal(<<$:, AtomBin/binary>>, State);
marshal(Object, State) -> yaml_schema_failsafe:marshal(Object, State).
