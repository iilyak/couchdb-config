% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.

-module(config_listener_mon).
-behaviour(gen_server).
-vsn(2).


-export([
    subscribe/2,
    terminate_config/2,
    notify/5,
    restart/2
]).


-export([
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3
]).


-record(st, {
    pid,
    ref,
    mgr,
    state,
    self,
    module
}).

-define(RELISTEN_DELAY, 500).

subscribe(Module, InitSt) ->
    proc_lib:start(?MODULE, init, [{self(), Module, InitSt}]).

notify(#st{module = Mod, state = State, pid = Pid} = St,
        Sec, Key, Value, Persist) ->
    try Mod:handle_config_change(Sec, Key, Value, Persist, State) of
        {ok, NewState} ->
            {ok, St#st{state = NewState}};
        remove_handler ->
            remove_handler
    catch
        _:Error ->
            {swap_handler, {remove_handler_due_to_error, {error, Error}},
                St, {config_listener, {Mod, Pid}}, St}
    end.

init({Pid, Mod, InitSt}) ->
    process_flag(trap_exit, true),
    Ref = erlang:monitor(process, Pid),
    case listen(#st{module = Mod, pid = Pid, ref = Ref, state = InitSt}) of
        {ok, St} ->
            proc_lib:init_ack(ok),
            gen_server:enter_loop(?MODULE, [], St);
        Else ->
            proc_lib:init_ack(Else)
    end.

terminate(_Reason, _) ->
    ok.

terminate_config({remove_handler_due_to_error, Reason}, #st{} = St) ->
    handle_config_terminate(Reason, St),
    ok;
terminate_config({swapped, _, _}, _St) ->
    ok;
terminate_config(Reason, St) ->
    maybe_restart(handle_config_terminate(Reason, St)).

handle_call(stop, _From, St) ->
    {stop, normal, St};
handle_call(_Message, _From, St) ->
    {reply, ignored, St}.

handle_cast(_Message, St) ->
    {noreply, St}.

%% Requester die
handle_info({'DOWN', Ref, _, _, _}, #st{ref = Ref} = St) ->
    {stop, normal, St};

%% Event handler swapped due to error in terminate
handle_info({gen_event_EXIT, {config_listener, _Id}, {swapped, _, _}}, St)  ->
    {noreply, St};

%% Event handler die
handle_info({gen_event_EXIT, {config_listener, Id}, Reason}, St)  ->
    Level = case Reason of
        normal -> debug;
        shutdown -> debug;
        _ -> error
    end,
    Fmt = "config_listener(~p) for ~p stopped with reason: ~r~n",
    couch_log:Level(Fmt, [Id, St#st.pid, Reason]),
    {stop, Reason, St};

%% Event manager die
handle_info({'EXIT', EventMgr, shutdown}, #st{mgr = EventMgr} = St) ->
    {stop, shutdown, St};
handle_info({'EXIT', EventMgr, _Reason}, #st{mgr = EventMgr} = St) ->
    {noreply, St, ?RELISTEN_DELAY};

handle_info(timeout, St) ->
    case whereis(config_event) of
        undefined ->
            {noreply, St, ?RELISTEN_DELAY};
        EventMgr ->
            {noreply, listen(St#st{mgr = EventMgr})}
    end;
handle_info(_Event, St) ->
    {noreply, St}.

code_change(_OldVsn, St, _Extra) ->
    {ok, St}.

listen(#st{module = Mod, pid = Pid} = St0) ->
    St = St0#st{self = self(), mgr = whereis(config_event)},
    case config_listener:listen({Mod, Pid}, St) of
        ok ->
            {ok, St};
        Else ->
            Else
    end.

handle_config_terminate(Reason, #st{module = Mod, pid = Pid, state = State} = St) ->
    try {Mod:handle_config_terminate(Pid, Reason, State), Reason} of
        {remove_handler, _} ->
            ok;
        {_, normal} ->
            ok;
        {_, shutdown} ->
            ok;
        {_, remove_handler} ->
            ok;
        {_, {remove_handler, _Reason}} ->
            ok;
        {{ok, NewState}, _Reason} ->
            St#st{state = NewState};
         {_, _Reason} ->
            St
    catch
        Kind:Error ->
            couch_log:error(
               "config_listener(~p) for ~p crashed in handle_config_terminate: ~p:~p~n",
               [Mod, Pid, Kind, Error]),
            St
    end.

maybe_restart(#st{} = St) ->
    spawn(fun() -> restart(?RELISTEN_DELAY, St) end);
maybe_restart(_) ->
    ok.

restart(Delay, #st{module = Mod, pid = Pid, state = State} = St) ->
    case catch proc_lib:start(?MODULE, init, [{Pid, Mod, State}]) of
        ok ->
            ok;
        _ ->
            timer:sleep(Delay),
            restart(Delay, St)
    end.
