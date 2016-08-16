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

-module(config_listener).

-behaviour(gen_event).
-vsn(2).

%% Public interface
-export([listen/2]).


-export([behaviour_info/1]).

%% Required gen_event interface
-export([init/1, handle_event/2, handle_call/2, handle_info/2, terminate/2,
    code_change/3]).

behaviour_info(callbacks) ->
    [{handle_config_change,5},
     {handle_config_terminate, 3}];
behaviour_info(_) ->
    undefined.

listen(Id, Monitor) ->
    gen_event:add_sup_handler(config_event, {?MODULE, Id}, Monitor).

init({Monitor, _}) ->
    {ok, Monitor};
init(Monitor) ->
    {ok, Monitor}.

handle_event({config_change, Sec, Key, Value, Persist}, Monitor) ->
    config_listener_mon:notify(Monitor, Sec, Key, Value, Persist).

handle_call(_Request, Monitor) ->
    {ok, ignored, Monitor}.

handle_info(_Info, Monitor) ->
    {ok, Monitor}.

terminate({stop, Reason}, Monitor) ->
    config_listener_mon:terminate_config(Reason, Monitor),
    ok;
terminate(Reason, Monitor) ->
    config_listener_mon:terminate_config(Reason, Monitor),
    ok.

code_change(_OldVsn, Monitor, _Extra) ->
    {ok, Monitor}.
