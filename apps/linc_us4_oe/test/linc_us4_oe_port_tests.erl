%%------------------------------------------------------------------------------
%% Copyright 2012 FlowForwarding.org
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
%%-----------------------------------------------------------------------------

%% @author Erlang Solutions Ltd. <openflow@erlang-solutions.com>
%% @copyright 2012 FlowForwarding.org
-module(linc_us4_oe_port_tests).

-import(linc_us4_oe_test_utils, [mock/1,
                              unmock/1,
                              check_if_called/1,
                              check_output_on_ports/0]).

-include_lib("of_config/include/of_config.hrl").
-include_lib("of_protocol/include/of_protocol.hrl").
-include_lib("of_protocol/include/ofp_v4.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("pkt/include/pkt.hrl").
-include("linc_us4_oe.hrl").

-define(MOCKED, [logic, port_native, packet, routing]).
-define(SWITCH_ID, 0).

%% Tests -----------------------------------------------------------------------

port_test_() ->
    {setup, fun setup/0, fun teardown/1,
    [
     {foreach, fun foreach_setup/0, fun foreach_teardown/1,
      [
       {"Port: port_mod", fun port_mod/0},
       {"Port: is_valid", fun is_valid/0},
       {"Port send: in_port", fun send_in_port/0},
       {"Port send: table", fun send_table/0},
       {"Port send: normal", fun send_normal/0},
       {"Port send: flood", fun send_flood/0},
       {"Port send: all", fun send_all/0},
       {"Port send: controller", fun send_controller/0},
       {"Port send: local", fun send_local/0},
       {"Port send: any", fun send_any/0},
       {"Port send: port number", fun send_port_number/0},
       {"Port multipart: port_desc_request", fun port_desc_request/0},
       {"Port multipart: port_stats_request", fun port_stats_request/0},
       {"Port config: port_down", fun config_port_down/0},
       {"Port config: no_recv", fun config_no_recv/0},
       {"Port config: no_fwd", fun config_no_fwd/0},
       {"Port config: no_pkt_in", fun config_no_pkt_in/0},
       {"Port state: link_down", fun state_link_down/0},
       {"Port state: blocked", fun state_blocked/0},
       {"Port state: live", fun state_live/0},
       {"Port features: change advertised features", fun advertised_features/0},
       {"Port routing strategy: default synchronous routing",
         fun sync_routing_as_default/0}
      ]},
     {setup, fun sync_routing_setup/0, fun foreach_teardown/1,
      {"Port routing strategy: explicit synchronous routing",
       fun sync_routing_explicitly_set/0}},
     {setup, fun async_routing_setup/0, fun foreach_teardown/1,
      {"Port routing strategy: explicit asynchronous routing",
       fun async_routing_explicitly_set/0}}
    ]}.

optical_port_test_() ->
    {setup,
     fun optical_extension_setup/0,
     fun optical_extension_teardown/1,
     [{foreach, fun foreach_setup/0, fun foreach_teardown/1,
       [{"Test message reaches optical backend",
         fun message_should_reach_optical_backend/0},
        %% FAIL!!!
        {"Test message from optical backend is routed",
         fun message_from_optical_backed_should_be_routed/0}]}]}.

port_mod() ->
    BadPort = 999,
    PortMod1 = #ofp_port_mod{port_no = BadPort},
    Error1 = {error, {port_mod_failed, bad_port}},
    ?assertEqual(Error1, linc_us4_oe_port:modify(?SWITCH_ID, PortMod1)),

    Port = 1,
    BadHwAddr = <<2,2,2,2,2,2>>,
    PortMod2 = #ofp_port_mod{port_no = Port, hw_addr = BadHwAddr},
    ?assertEqual({error, {port_mod_failed, bad_hw_addr}},
                 linc_us4_oe_port:modify(?SWITCH_ID, PortMod2)),

    HwAddr = <<1,1,1,1,1,1>>,
    PortMod3 = #ofp_port_mod{port_no = Port, hw_addr = HwAddr,
                             config = [], mask = [],
                             advertise = [copper, autoneg]},
    ?assertEqual(ok, linc_us4_oe_port:modify(?SWITCH_ID, PortMod3)).

is_valid() ->
    ?assertEqual(true, linc_us4_oe_port:is_valid(?SWITCH_ID, any)),
    ?assertEqual(true, linc_us4_oe_port:is_valid(?SWITCH_ID, 1)),
    ?assertEqual(false, linc_us4_oe_port:is_valid(?SWITCH_ID, 999)).

send_in_port() ->
    Pkt = pkt(1),
    ?assertEqual(ok, linc_us4_oe_port:send(Pkt, in_port)).

send_table() ->
    meck:new(linc_us4_oe_routing),
    meck:expect(linc_us4_oe_routing, maybe_spawn_route, fun(_) -> ok end),
    ?assertEqual(ok, linc_us4_oe_port:send(pkt(), table)),
    meck:unload(linc_us4_oe_routing).

send_normal() ->
    ?assertEqual(bad_port, linc_us4_oe_port:send(pkt(), normal)).

%% Flood port represents traditional non-OpenFlow pipeline of the switch
%% and should not supported by LINC. But we want LINC to cooperate with
%% NOX 1.3 controller [1] that uses this port, incorrectly assuming that
%% an OpenFlow switch supports it. It's important as NOX is shipped
%% with Mininet [3]. As soon as this bug is fixed [2]
%% linc_us4_oe_port:send(term(), flood) call should return 'bad_port'.
%% [1]: https://github.com/CPqD/nox13oflib
%% [2]: https://github.com/CPqD/nox13oflib/issues/3
%% [3]: http://mininet.org/
send_flood() ->
    [InPort | PortsThatShouldBeFlooded] =
        [PortNo || {port, PortNo, _Config} <- ports(dummy)],
    Pkt = pkt(InPort),
    ?assertEqual(ok, linc_us4_oe_port:send(Pkt, flood)),
    %% wait because send to port is a gen_server:cast
    timer:sleep(500),
    ?assertEqual(length(PortsThatShouldBeFlooded),
                 meck:num_calls(linc_us4_oe_port_native, send, '_')).

send_all() ->
    ?assertEqual(ok, linc_us4_oe_port:send(pkt(), all)),
    %% wait because send to port is a gen_server:cast
    timer:sleep(500),
    ?assertMatch(3, meck:num_calls(linc_us4_oe_port_native, send, '_')).

send_controller() ->
    ?assertEqual(ok, linc_us4_oe_port:send(pkt(controller,no_match), controller)).

send_local() ->
    ?assertEqual(bad_port, linc_us4_oe_port:send(pkt(), local)).

send_any() ->
    ?assertEqual(bad_port, linc_us4_oe_port:send(pkt(), any)).

send_port_number() ->
    ?assertEqual(ok, linc_us4_oe_port:send(pkt(), 1)).

port_desc_request() ->
    Desc = linc_us4_oe_port:get_desc(?SWITCH_ID),
    ?assertMatch(#ofp_port_desc_reply{}, Desc),
    Body = Desc#ofp_port_desc_reply.body,
    ?assert(length(Body) =/= 0),
    lists:map(fun(E) ->
                      ?assertMatch(#ofp_port{}, E)
              end, Body).

port_stats_request() ->
    BadPort = 999,
    StatsRequest1 = #ofp_port_stats_request{port_no = BadPort},
    ?assertEqual(#ofp_error_msg{type = bad_request, code = bad_port},
                 linc_us4_oe_port:get_stats(?SWITCH_ID, StatsRequest1)),

    ValidPort = 1,
    StatsRequest2 = #ofp_port_stats_request{port_no = ValidPort},
    StatsReply2 = linc_us4_oe_port:get_stats(?SWITCH_ID, StatsRequest2),
    ?assertEqual(1, length(StatsReply2#ofp_port_stats_reply.body)),
    [PortStats2] = StatsReply2#ofp_port_stats_reply.body,
    ?assertEqual(0, PortStats2#ofp_port_stats.duration_sec),
    ?assertNot(PortStats2#ofp_port_stats.duration_nsec == 0),

    AllPorts = any,
    StatsRequest3 = #ofp_port_stats_request{port_no = AllPorts},
    StatsReply3 = linc_us4_oe_port:get_stats(?SWITCH_ID, StatsRequest3),
    ?assertMatch([_, _, _], StatsReply3#ofp_port_stats_reply.body).

config_port_down() ->
    ?assertEqual([], linc_us4_oe_port:get_config(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_config(?SWITCH_ID, 1, [port_down])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([port_down], linc_us4_oe_port:get_config(?SWITCH_ID, 1)).

config_no_recv() ->
    ?assertEqual([], linc_us4_oe_port:get_config(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_config(?SWITCH_ID, 1, [no_recv])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([no_recv], linc_us4_oe_port:get_config(?SWITCH_ID, 1)).

config_no_fwd() ->
    ?assertEqual([], linc_us4_oe_port:get_config(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_config(?SWITCH_ID, 1, [no_fwd])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([no_fwd], linc_us4_oe_port:get_config(?SWITCH_ID, 1)).

config_no_pkt_in() ->
    ?assertEqual([], linc_us4_oe_port:get_config(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_config(?SWITCH_ID, 1, [no_pkt_in])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([no_pkt_in], linc_us4_oe_port:get_config(?SWITCH_ID, 1)).

state_link_down() ->
    ?assertEqual([live], linc_us4_oe_port:get_state(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_state(?SWITCH_ID, 1, [link_down])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([link_down], linc_us4_oe_port:get_state(?SWITCH_ID, 1)).

state_blocked() ->
    ?assertEqual([live], linc_us4_oe_port:get_state(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_state(?SWITCH_ID, 1, [blocked])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([blocked], linc_us4_oe_port:get_state(?SWITCH_ID, 1)).

state_live() ->
    ?assertEqual([live], linc_us4_oe_port:get_state(?SWITCH_ID, 1)),
    ?assertEqual(ok, linc_us4_oe_port:set_state(?SWITCH_ID, 1, [live])),
    ?assertEqual(1, meck:num_calls(linc_logic, send_to_controllers, '_')),
    ?assertEqual([live], linc_us4_oe_port:get_state(?SWITCH_ID, 1)).

advertised_features() ->
    FeatureSet1 = [other],
    FeatureSet2 = [copper, autoneg],
    ?assertEqual(ok,
                 linc_us4_oe_port:set_advertised_features(?SWITCH_ID, 1,
                                                       FeatureSet1)),
    ?assertEqual(FeatureSet1,
                 linc_us4_oe_port:get_advertised_features(?SWITCH_ID, 1)),
    ?assertEqual(ok,
                 linc_us4_oe_port:set_advertised_features(?SWITCH_ID, 1,
                                                       FeatureSet2)),
    ?assertEqual(FeatureSet2,
                 linc_us4_oe_port:get_advertised_features(?SWITCH_ID, 1)).

sync_routing_as_default() ->
    ?assertNotEqual({ok, false}, application:get_env(linc, sync_routing)),
    routing_fun_invoked_test(route).

sync_routing_explicitly_set() ->
    ?assertEqual({ok, true}, application:get_env(linc, sync_routing)),
    routing_fun_invoked_test(route).

async_routing_explicitly_set() ->
    ?assertEqual({ok, false}, application:get_env(linc, sync_routing)),
    routing_fun_invoked_test(spawn_route).

routing_fun_invoked_test(ExpectedRoutingFun) ->
    MockMsg = mock_routing_module_and_expect_routing_fun(ExpectedRoutingFun),
    ?assertEqual(ok, send_frame_to_routing_module_and_wait_for_mock_message(
                       MockMsg)),
    ?assert(meck:validate(linc_us4_oe_routing)),
    ?assertEqual(1, meck:num_calls(linc_us4_oe_routing, ExpectedRoutingFun, '_')),
    unmock_routing_module().

message_should_reach_optical_backend() ->
    ok = linc_us4_oe_port:send(pkt(), _PortNo = 1),
    ?assertEqual(_NumOfPackets = 1,
                 meck:num_calls(linc_us4_oe_port_native, send, 2)).

message_from_optical_backed_should_be_routed() ->
    Pid = linc_us4_oe_port:get_port_pid(?SWITCH_ID, _PortNo = 1),
    Pid ! {optical_data, _OpticalPortPidFromMeck = <<1,1,1,1,1,1>>,
           <<"Hello Alice!">>},
    ?assertEqual(ok, meck:wait(linc_us4_oe_routing, route, 1, 1000)).
    


%% Fixtures --------------------------------------------------------------------

ports(Type) ->
    [begin
         Opts0 = [{interface, "dummy" ++ integer_to_list(No)},
                  {features, #features{}},
                  {config, #port_configuration{}}],
         Opts1 = case Type of
                     optical ->
                         [{type, Type} | Opts0];
                     _ ->
                         Opts0
                 end,
         {port, No, Opts1}
     end || No <- [1, 2, 3]].

ports_without_queues(Type) ->
    [{switch, 0,
      [{ports, ports(Type)}, {queues_status, disabled}, {queues, []}]}].

optical_extension_setup() ->
    meck:new(linc_us4_oe_packet),
    meck:expect(linc_us4_oe_packet, optical_packet_to_record,
                fun(_, _, _) ->
                        #linc_pkt{}
                end),
    setup(optical).

setup() ->
    setup(dummy).

setup(Type) ->
    mock(?MOCKED),
    linc:create(?SWITCH_ID),
    linc_us4_oe_test_utils:add_logic_path(),
    {ok, _Pid} = linc_us4_oe_sup:start_link(?SWITCH_ID),
    Config = ports_without_queues(Type),
    application:load(linc),
    application:set_env(linc, logical_switches, Config).

teardown(_) ->
    linc:delete(?SWITCH_ID),
    unmock(?MOCKED).

optical_extension_teardown(Args) ->
    meck:unload(linc_us4_oe_packet),
    teardown(Args).

foreach_setup() ->
    ok = meck:reset(linc_logic),
    ok = meck:reset(linc_us4_oe_port_native),
    {ok, Switches} = application:get_env(linc, logical_switches),
    ok = linc_us4_oe_port:initialize(?SWITCH_ID, Switches).

sync_routing_setup() ->
    application:set_env(linc, sync_routing, true),
    foreach_setup().

async_routing_setup() ->
    application:set_env(linc, sync_routing, false),
    foreach_setup().

foreach_teardown(_) ->
    ok = linc_us4_oe_port:terminate(?SWITCH_ID).

pkt() ->
    #linc_pkt{packet = [<<>>]}.

pkt(Port) ->
    #linc_pkt{in_port = Port, packet = [<<>>]}.

pkt(controller=Port,Reason) ->
    #linc_pkt{in_port = Port, packet_in_reason=Reason, packet = [<<>>]}.

mock_routing_module_and_expect_routing_fun(RoutingFun) ->
    ok = meck:new(linc_us4_oe_routing),
    Pid = self(),
    AfterInvocationMsg = processed,
    meck:expect(linc_us4_oe_routing, RoutingFun, fun(_) ->
                                                      Pid ! AfterInvocationMsg
                                              end),
    AfterInvocationMsg.

send_frame_to_routing_module_and_wait_for_mock_message(MockMsg) ->
    PortPid = linc_us4_oe_port:get_port_pid(?SWITCH_ID, 1),
    PortPid ! {packet, dummy, dummy, dummy, <<>>},
    receive
        MockMsg ->
            ok
    after
        5000 ->
            mock_message_not_received
    end.

unmock_routing_module() ->
    ok = meck:unload(linc_us4_oe_routing).