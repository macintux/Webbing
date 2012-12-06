%%% @author John Daily <jd@epep.us>
%%% @copyright (C) 2012, John Daily
%%% @doc
%%%
%%% @end
%%% Created :  1 Dec 2012 by John Daily <jd@epep.us>

-module(html).
-export([meta/1]).

meta(URL) ->
    MyPid = self(),
    trane:sax(trane:wget(URL),
              fun(What, Pid) -> Pid ! What, Pid end,
              spawn(fun() -> track_state({pid, MyPid}) end)).


%% Server code
-record(state, {inside_title=false,
                title=[],
                description=undefined,
                inside_first_p=false,
                first_paragraph=[],
                caller=undefined
                }).

check_for_description("description", Value, State) ->
    State#state{description = Value};
check_for_description(_, _, State) ->
    State.

track_state({pid, Pid}) ->
    track_state(#state{caller=Pid});
track_state(#state{inside_title = InTitle,
                   title = Title,
                   inside_first_p = InFirstP,
                   first_paragraph = FirstParagraph,
                   caller = Pid} = State) ->
    receive
        {tag, "meta", Attribs} ->
            track_state(check_for_description(proplists:get_value("name", Attribs),
                                              proplists:get_value("content", Attribs),
                                              State));
        {tag, "title", _A} ->
            track_state(State#state{inside_title = true});
        {tag, "p", _A} when length(FirstParagraph) =:= 0 ->
            track_state(State#state{inside_first_p = true});
        %% Any nested tags in the first paragraph should add whitespace to keep
        %% the text separated
        {tag, _Tag, _A} when InFirstP =:= true ->
            track_state(State#state{first_paragraph = [" "] ++ FirstParagraph});
        {text, Binary} when InTitle =:= true ->
            track_state(State#state{title = [binary_to_list(Binary)] ++ Title});
        {text, Binary} when InFirstP =:= true ->
            track_state(State#state{first_paragraph = [binary_to_list(Binary)] ++ FirstParagraph});
        {end_tag, "title"} ->
            track_state(State#state{inside_title = false});
        {end_tag, "p"} ->
            track_state(State#state{inside_first_p = false});
        {end_tag, "html"} ->
            Pid ! normalize(State);

        %% Absolutely necessary to discard messages in which we're not
        %% interested, else we'll get really confused when trying to
        %% process the text events
        _ ->
            track_state(State)
    end.

normalize(#state{title = Title,
                 first_paragraph = Paragraph,
                 description = Description}) ->
    %% Title and Paragraph are handled as a list of strings but
    %% description is an attribute value, and as such just one string
    %% that doesn't need to be reversed
    [ {description, normalize_string(Description)},
      {title, normalize_string(lists:reverse(Title))},
      {firstp, normalize_string(lists:reverse(Paragraph))} ].


normalize_string([]) ->
    "";
normalize_string(undefined) ->
    "";
normalize_string(String) ->
    %% Kindly enough, re:replace seems to handle a list of strings as though it were just one string
    re:replace(re:replace(String, "\\s+", " ", [global,{return,list}]),
               "^\\s+|\\s+$", "", [global,{return,list}]).
