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

-module(config_tests).
-behaviour(config_listener).


-include_lib("couch/include/couch_eunit.hrl").
-include_lib("couch/include/couch_db.hrl").


-export([
    handle_config_change/5,
    handle_config_terminate/3
]).


-define(TIMEOUT, 4000).

-define(CONFIG_FIXTURESDIR,
        filename:join([?BUILDDIR(), "src", "config", "test", "fixtures"])).

-define(CONFIG_FIXTURE_1,
        filename:join([?CONFIG_FIXTURESDIR, "config_tests_1.ini"])).

-define(CONFIG_FIXTURE_2,
        filename:join([?CONFIG_FIXTURESDIR, "config_tests_2.ini"])).

-define(CONFIG_DEFAULT_D,
        filename:join([?CONFIG_FIXTURESDIR, "default.d"])).

-define(CONFIG_LOCAL_D,
        filename:join([?CONFIG_FIXTURESDIR, "local.d"])).

-define(CONFIG_FIXTURE_TEMP,
    begin
        FileName = filename:join([?TEMPDIR, "config_temp.ini"]),
        {ok, Fd} = file:open(FileName, write),
        ok = file:truncate(Fd),
        ok = file:close(Fd),
        FileName
    end).

-define(DEPS, [couch_stats, couch_log, config]).


-define(T(F), {erlang:fun_to_list(F), F}).
-define(FEXT(F), fun(_, _) -> F() end).



setup() ->
    setup(?CONFIG_CHAIN).

setup({temporary, Chain}) ->
    setup(Chain);

setup({persistent, Chain}) ->
    setup(Chain ++ [?CONFIG_FIXTURE_TEMP]);

setup(Chain) ->
    ok = application:set_env(config, ini_files, Chain),
    test_util:start_applications(?DEPS).


setup_empty() ->
    setup([]).


setup_config_listener() ->
    setup(),
    spawn_config_listener().


teardown(Pid) when is_pid(Pid) ->
    catch exit(Pid, kill),
    teardown(undefined);

teardown(_) ->
    [application:stop(App) || App <- ?DEPS].


teardown(_, _) ->
    teardown(undefined).


handle_config_change("remove_handler", _Key, _Value, _Persist, {_Pid, _State}) ->
    remove_handler;

handle_config_change("update_state", Key, Value, Persist, {Pid, State}) ->
    Pid ! {config_msg, {{"update_state", Key, Value, Persist}, State}},
    {ok, {Pid, Key}};

handle_config_change("throw_error", _Key, Value, _Persist, {_Pid, _State}) ->
    throw(Value);

handle_config_change(Section, Key, Value, Persist, {Pid, State}) ->
    Pid ! {config_msg, {{Section, Key, Value, Persist}, State}},
    {ok, {Pid, State}}.


handle_config_terminate(Self, {error, "error_in_terminate"} = Reason, {Pid, State}) ->
    Pid ! {config_msg, {Self, Reason, State}},
    _ = 1 / 0,
    ok;
handle_config_terminate(Self, {return, Reason}, {Pid, State}) ->
    Pid ! {config_msg, {Self, Reason, State}},
    Reason;
handle_config_terminate(Self, Reason, {Pid, State}) ->
    Pid ! {config_msg, {Self, Reason, State}},
    ok.

config_get_test_() ->
    {
        "Config get tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_load_all_configs/0,
                fun should_locate_daemons_section/0,
                fun should_locate_mrview_handler/0,
                fun should_return_undefined_atom_on_missed_section/0,
                fun should_return_undefined_atom_on_missed_option/0,
                fun should_return_custom_default_value_on_missed_option/0,
                fun should_only_return_default_on_missed_option/0,
                fun should_fail_to_get_binary_value/0,
                fun should_return_any_supported_default/0
            ]
        }
    }.


config_set_test_() ->
    {
        "Config set tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_update_option/0,
                fun should_create_new_section/0,
                fun should_fail_to_set_binary_value/0
            ]
        }
    }.


config_del_test_() ->
    {
        "Config deletion tests",
        {
            foreach,
            fun setup/0,
            fun teardown/1,
            [
                fun should_return_undefined_atom_after_option_deletion/0,
                fun should_be_ok_on_deleting_unknown_options/0
            ]
        }
    }.


config_override_test_() ->
    {
        "Configs overide tests",
        {
            foreachx,
            fun setup/1,
            fun teardown/2,
            [
                {{temporary, [?CONFIG_DEFAULT]},
                        fun should_ensure_in_defaults/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_1]},
                        fun should_override_options/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_2]},
                        fun should_create_new_sections_on_override/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_FIXTURE_1,
                                ?CONFIG_FIXTURE_2]},
                        fun should_win_last_in_chain/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_DEFAULT_D]},
                        fun should_read_default_d/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_LOCAL_D]},
                        fun should_read_local_d/2},
                {{temporary, [?CONFIG_DEFAULT, ?CONFIG_DEFAULT_D,
                                ?CONFIG_LOCAL_D]},
                        fun should_read_default_and_local_d/2}
            ]
        }
    }.


config_persistent_changes_test_() ->
    {
        "Config persistent changes",
        {
            foreachx,
            fun setup/1,
            fun teardown/2,
            [
                {{persistent, [?CONFIG_DEFAULT]},
                        fun should_write_changes/2},
                {{temporary, [?CONFIG_DEFAULT]},
                        fun should_ensure_default_wasnt_modified/2},
                {{temporary, [?CONFIG_FIXTURE_TEMP]},
                        fun should_ensure_written_to_last_config_in_chain/2}
            ]
        }
    }.


config_no_files_test_() ->
    {
        "Test config with no files",
        {
            foreach,
            fun setup_empty/0,
            fun teardown/1,
            [
                fun should_ensure_that_no_ini_files_loaded/0,
                fun should_create_non_persistent_option/0,
                fun should_create_persistent_option/0
            ]
        }
    }.


config_listener_behaviour_test_() ->
    {
        "Test config_listener behaviour",
        {
            foreach,
            local,
            fun setup_config_listener/0,
            fun teardown/1,
            [
                fun should_pass_correct_state_to_handle_config_change/1,
                fun should_pass_correct_state_to_handle_config_terminate/1,
                fun should_pass_subscriber_pid_to_handle_config_terminate/1,
                fun should_handle_value_change/1,
                fun should_not_call_handle_config_after_related_process_death/1,
                fun should_remove_handler_when_requested/1,
                fun should_remove_handler_when_pid_exits/1,
                fun should_remove_handler_from_terminate/1,

                fun should_add_handler_back_when_error/1,
                fun should_add_handler_back_when_manager_dies/1,
                fun should_add_handler_back_when_die_in_terminate/1,
                fun should_add_handler_back_when_monitor_die/1,
                fun should_restart_if_failed_to_start/1
            ]
        }
    }.


should_load_all_configs() ->
    ?assert(length(config:all()) > 0).


should_locate_daemons_section() ->
    ?assert(length(config:get("daemons")) > 0).


should_locate_mrview_handler() ->
    Expect = "{couch_mrview_http, handle_view_req}",
    ?assertEqual(Expect, config:get("httpd_design_handlers", "_view")).


should_return_undefined_atom_on_missed_section() ->
    ?assertEqual(undefined, config:get("foo", "bar")).


should_return_undefined_atom_on_missed_option() ->
    ?assertEqual(undefined, config:get("httpd", "foo")).


should_return_custom_default_value_on_missed_option() ->
    ?assertEqual("bar", config:get("httpd", "foo", "bar")).


should_only_return_default_on_missed_option() ->
    ?assertEqual("0", config:get("httpd", "port", "bar")).


should_fail_to_get_binary_value() ->
    ?assertException(error, badarg, config:get(<<"a">>, <<"b">>, <<"c">>)).


should_return_any_supported_default() ->
    Values = [undefined, "list", true, false, 0.1, 1],
    lists:map(fun(V) ->
        ?assertEqual(V, config:get(<<"foo">>, <<"bar">>, V))
    end, Values).


should_update_option() ->
    ok = config:set("mock_log", "level", "severe", false),
    ?assertEqual("severe", config:get("mock_log", "level")).


should_create_new_section() ->
    ?assertEqual(undefined, config:get("new_section", "bizzle")),
    ?assertEqual(ok, config:set("new_section", "bizzle", "bang", false)),
    ?assertEqual("bang", config:get("new_section", "bizzle")).


should_fail_to_set_binary_value() ->
    ?assertException(error, badarg,
            config:set(<<"a">>, <<"b">>, <<"c">>, false)).


should_return_undefined_atom_after_option_deletion() ->
    ?assertEqual(ok, config:delete("mock_log", "level", false)),
    ?assertEqual(undefined, config:get("mock_log", "level")).


should_be_ok_on_deleting_unknown_options() ->
    ?assertEqual(ok, config:delete("zoo", "boo", false)).


should_ensure_in_defaults(_, _) ->
    ?_test(begin
        ?assertEqual("500", config:get("couchdb", "max_dbs_open")),
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual(undefined, config:get("fizbang", "unicode"))
    end).


should_override_options(_, _) ->
    ?_test(begin
        ?assertEqual("10", config:get("couchdb", "max_dbs_open")),
        ?assertEqual("4895", config:get("httpd", "port"))
    end).


should_read_default_d(_, _) ->
    ?_test(begin
        ?assertEqual("11", config:get("couchdb", "max_dbs_open"))
    end).


should_read_local_d(_, _) ->
    ?_test(begin
        ?assertEqual("12", config:get("couchdb", "max_dbs_open"))
    end).


should_read_default_and_local_d(_, _) ->
    ?_test(begin
        ?assertEqual("12", config:get("couchdb", "max_dbs_open"))
    end).


should_create_new_sections_on_override(_, _) ->
    ?_test(begin
        ?assertEqual("80", config:get("httpd", "port")),
        ?assertEqual("normalized", config:get("fizbang", "unicode"))
    end).


should_win_last_in_chain(_, _) ->
    ?_test(begin
        ?assertEqual("80", config:get("httpd", "port"))
    end).


should_write_changes(_, _) ->
    ?_test(begin
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual(ok, config:set("httpd", "port", "8080")),
        ?assertEqual("8080", config:get("httpd", "port")),
        ?assertEqual(ok, config:delete("httpd", "bind_address", "8080")),
        ?assertEqual(undefined, config:get("httpd", "bind_address"))
    end).


should_ensure_default_wasnt_modified(_, _) ->
    ?_test(begin
        ?assertEqual("5986", config:get("httpd", "port")),
        ?assertEqual("127.0.0.1", config:get("httpd", "bind_address"))
    end).


should_ensure_written_to_last_config_in_chain(_, _) ->
    ?_test(begin
        ?assertEqual("8080", config:get("httpd", "port")),
        ?assertEqual(undefined, config:get("httpd", "bind_address"))
    end).


should_ensure_that_no_ini_files_loaded() ->
    ?assertEqual(0, length(config:all())).


should_create_non_persistent_option() ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertEqual("80", config:get("httpd", "port"))
    end).


should_create_persistent_option() ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "bind_address", "127.0.0.1")),
        ?assertEqual("127.0.0.1", config:get("httpd", "bind_address"))
    end).


should_handle_value_change(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({{"httpd", "port", "80", false}, _}, getmsg(Pid))
    end).


should_pass_correct_state_to_handle_config_change(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("update_state", "foo", "any", false)),
        ?assertMatch({_, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({_, "foo"}, getmsg(Pid))
    end).


should_pass_correct_state_to_handle_config_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("update_state", "foo", "any", false)),
        ?assertMatch({_, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        ?assertMatch({_, "foo"}, getmsg(Pid)),
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, "foo"}, getmsg(Pid))
    end).


should_pass_subscriber_pid_to_handle_config_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid))
    end).


should_not_call_handle_config_after_related_process_death(Pid) ->
    ?_test(begin
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid)),
        ?assertEqual(ok, config:set("httpd", "port", "80", false)),
        Event = receive
            {config_msg, _} -> got_msg
            after 250 -> no_msg
        end,
        ?assertEqual(no_msg, Event)
    end).


should_remove_handler_when_requested(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),
        ?assertEqual(ok, config:set("remove_handler", "any", "any", false)),
        ?assertEqual({Pid, remove_handler, undefined}, getmsg(Pid)),
        ?assertEqual(0, n_handlers())
    end).


should_remove_handler_when_pid_exits(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        % Kill the process synchronously
        PidRef = erlang:monitor(process, Pid),
        exit(Pid, kill),
        receive
            {'DOWN', PidRef, _, _, _} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_death})
        end,

        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed.
        receive
            {'DOWN', MonRef, _, _, normal} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_death})
        end,

        ?assertEqual(0, n_handlers())
    end).

should_remove_handler_from_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        % Have the process throw an error and then return remove_handler from terminate
        Mon ! {gen_event_EXIT, {config_listener, {?MODULE, Pid}}, {return, remove_handler}},

        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed.
        receive
            {'DOWN', MonRef, _, _, {return,remove_handler}} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_death})
        end,

        ?assertEqual(0, n_handlers())
    end).

should_add_handler_back_when_error(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Have the process throw an error
        ?assertEqual(ok, config:set("throw_error", "foo", "this_is_an_error", false)),

        % Make sure handle_config_terminate is called
        ?assertEqual({Pid, {error, "this_is_an_error"}, undefined}, getmsg(Pid)),

        ?assertEqual(1, n_handlers())

    end).

should_add_handler_back_when_manager_dies(_Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        EventMgrPid = whereis(config_event),
        MonRef = erlang:monitor(process, EventMgrPid),

        exit(EventMgrPid, kill),

        % Wait for the config_event process to exit
        receive
            {'DOWN', MonRef, _, _, _} ->
                ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_event_shutdown})
        end,

        % Wait for the event manager process to be restarted by supervisor
        wait_process(config_event),

        ?assert(wait(fun() -> n_handlers() =:= 1 orelse wait end)),
        ok
    end).

should_add_handler_back_when_die_in_terminate(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Have the process throw an error and then die in terminate
        ?assertEqual(ok, config:set("throw_error", "foo", "error_in_terminate", false)),


        % Make sure handle_config_terminate is called
        ?assertEqual({Pid, {error, "error_in_terminate"}, undefined}, getmsg(Pid)),

        ?assertEqual(1, length(handlers())),
        ok
    end).

should_add_handler_back_when_monitor_die(Pid) ->
    ?_test(begin
        ?assertEqual(1, n_handlers()),

        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        exit(Mon, kill),

        % Make sure handle_config_terminate is called
        ?assertEqual({Pid, killed, undefined}, getmsg(Pid)),

        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed
        % due to an error
        receive
            {'DOWN', MonRef, _, _, killed} ->
                ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_shutdown})
        end,

        ?assert(wait(fun() -> n_handlers() =:= 1 orelse wait end)),
        ok

    end).

should_restart_if_failed_to_start(Pid) ->
    ?_test(begin
        % Monitor the config_listener_mon process
        {monitored_by, [Mon]} = process_info(Pid, monitored_by),
        MonRef = erlang:monitor(process, Mon),

        ok = meck:new(config_listener, [passthrough]),
        ok = meck:expect(config_listener, listen, ['_', '_'], meck:seq([
            meck:raise(error, die),
            meck:raise(error, die),
            meck:passthrough()
        ])),

        exit(Mon, kill),

        % Make sure handle_config_terminate is called
        ?assertEqual({Pid, killed, undefined}, getmsg(Pid)),


        % Wait for the config_listener_mon process to
        % exit to indicate the handler has been removed
        % due to an error
        receive
            {'DOWN', MonRef, _, _, killed} -> ok
        after ?TIMEOUT ->
            erlang:error({timeout, config_listener_mon_shutdown})
        end,

        meck:wait(3, config_listener, listen, ['_', '_'], 5000),
        ?assert(wait(fun() -> n_handlers() =:= 1 orelse wait end)),

        (catch meck:unload(config_listener)),
        ok
    end).

spawn_config_listener() ->
    Self = self(),
    Pid = erlang:spawn(fun() ->
        ok = config:listen_for_changes(?MODULE, {self(), undefined}),
        Self ! registered,
        loop(undefined)
    end),
    receive
        registered -> ok
    after ?TIMEOUT ->
        erlang:error({timeout, config_handler_register})
    end,
    Pid.


loop(undefined) ->
    receive
        {config_msg, _} = Msg ->
            loop(Msg);
        {get_msg, _, _} = Msg ->
            loop(Msg);
        Msg ->
            erlang:error({invalid_message, Msg})
    end;

loop({get_msg, From, Ref}) ->
    receive
        {config_msg, _} = Msg ->
            From ! {Ref, Msg};
        Msg ->
            erlang:error({invalid_message, Msg})
    end,
    loop(undefined);

loop({config_msg, _} = Msg) ->
    receive
        {get_msg, From, Ref} ->
            From ! {Ref, Msg};
        Msg ->
            erlang:error({invalid_message, Msg})
    end,
    loop(undefined).


getmsg(Pid) ->
    Ref = erlang:make_ref(),
    Pid ! {get_msg, self(), Ref},
    receive
        {Ref, {config_msg, Msg}} -> Msg
    after ?TIMEOUT ->
        erlang:error({timeout, config_msg})
    end.


n_handlers() ->
    length(handlers()).

handlers() ->
    Handlers = gen_event:which_handlers(config_event),
    [Pid || {config_listener, {?MODULE, Pid}} <- Handlers].

%% copy/paste from test_util
wait_process(Name) ->
    wait_process(Name, 5000).
wait_process(Name, Timeout) ->
    wait(fun() ->
       case whereis(Name) of
       undefined ->
          wait;
       Pid ->
          Pid
       end
    end, Timeout).

wait(Fun) ->
    wait(Fun, 5000, 50).

wait(Fun, Timeout) ->
    wait(Fun, Timeout, 50).

wait(Fun, Timeout, Delay) ->
    Now = now_us(),
    wait(Fun, Timeout * 1000, Delay, Now, Now).

wait(_Fun, Timeout, _Delay, Started, Prev) when Prev - Started > Timeout ->
    timeout;
wait(Fun, Timeout, Delay, Started, _Prev) ->
    case Fun() of
    wait ->
        ok = timer:sleep(Delay),
        wait(Fun, Timeout, Delay, Started, now_us());
    Else ->
        Else
    end.

now_us() ->
    {MegaSecs, Secs, MicroSecs} = now(),
    (MegaSecs * 1000000 + Secs) * 1000000 + MicroSecs.
