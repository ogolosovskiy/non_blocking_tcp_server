-module (tcp_echo_fsm).
-author ('saleyn@gmail.com').

-behaviour (gen_fsm).

-export ([start_link/0, set_socket/2]).

%% gen_fsm callbacks
-export ([init/1, handle_event/3,
          handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

%% FSM States
-export ([
          'WAIT_FOR_SOCKET'/2,
          'WAIT_FOR_DATA'/2]).

-record (state, {
           socket,    % client socket
           addr       % client address
          }).

-define (TIMEOUT, 120000).

%%%------------------------------------------------------------------------
%%% API
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @spec (Socket) -> {ok,Pid} | ignore | {error,Error}
%% @doc To be called by the supervisor in order to start the server.
%%      If init/1 fails with Reason, the function returns {error,Reason}.
%%      If init/1 returns {stop,Reason} or ignore, the process is
%%      terminated and the function returns {error,Reason} or ignore,
%%      respectively.
%% @end
%%-------------------------------------------------------------------------
start_link () ->
    gen_fsm:start_link (?MODULE, [], []).

set_socket (Pid, Socket) when is_pid (Pid), is_port (Socket) ->
    gen_fsm:send_event (Pid, {socket_ready, Socket}).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}
%% @private
%%-------------------------------------------------------------------------
init ([]) ->
    process_flag (trap_exit, true),
    {ok, 'WAIT_FOR_SOCKET', #state{}}.

%%-------------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
'WAIT_FOR_SOCKET'({socket_ready, Socket}, State) when is_port (Socket) ->
                                                % Now we own the socket
    inet:setopts (Socket, [{active, once}, {packet, 2}, binary]),
    {ok, {IP, _Port}} = inet:peername (Socket),
    {next_state, 'WAIT_FOR_DATA', State#state{socket=Socket, addr=IP}, ?TIMEOUT};
'WAIT_FOR_SOCKET'(Other, State) ->
    error_logger:error_msg ("State: 'WAIT_FOR_SOCKET'. Unexpected message: ~p\n", [Other]),
    %% Allow to receive async messages
    {next_state, 'WAIT_FOR_SOCKET', State}.

%% Notification event coming from client
'WAIT_FOR_DATA'({data, Data}, #state{socket=S} = State) ->
    ok = gen_tcp:send (S, Data),
    {next_state, 'WAIT_FOR_DATA', State, ?TIMEOUT};

'WAIT_FOR_DATA'(timeout, State) ->
    error_logger:error_msg ("~p Client connection timeout - closing.\n", [self ()]),
    {stop, normal, State};

'WAIT_FOR_DATA'(Data, State) ->
    io:format ("~p Ignoring data: ~p\n", [self (), Data]),
    {next_state, 'WAIT_FOR_DATA', State, ?TIMEOUT}.

%%-------------------------------------------------------------------------
%% Func: handle_event/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
handle_event (Event, StateName, StateData) ->
    {stop, {StateName, undefined_event, Event}, StateData}.

%%-------------------------------------------------------------------------
%% Func: handle_sync_event/4
%% Returns: {next_state, NextStateName, NextStateData}            |
%%          {next_state, NextStateName, NextStateData, Timeout}   |
%%          {reply, Reply, NextStateName, NextStateData}          |
%%          {reply, Reply, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}                          |
%%          {stop, Reason, Reply, NewStateData}
%% @private
%%-------------------------------------------------------------------------
handle_sync_event (Event, _From, StateName, StateData) ->
    {stop, {StateName, undefined_event, Event}, StateData}.

%%-------------------------------------------------------------------------
%% Func: handle_info/3
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
handle_info ({tcp, Socket, Bin}, StateName, #state{socket=Socket} = StateData) ->
                                                % Flow control: enable forwarding of next TCP message
    inet:setopts (Socket, [{active, once}]),
    ?MODULE:StateName ({data, Bin}, StateData);

handle_info ({tcp_closed, Socket}, _StateName,
             #state{socket=Socket, addr=Addr} = StateData) ->
    error_logger:info_msg ("~p Client ~p disconnected.\n", [self (), Addr]),
    {stop, normal, StateData};

handle_info (_Info, StateName, StateData) ->
    {noreply, StateName, StateData}.

%%-------------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%% @private
%%-------------------------------------------------------------------------
terminate (_Reason, _StateName, #state{socket=Socket}) ->
    (catch gen_tcp:close (Socket)),
    ok.

%%-------------------------------------------------------------------------
%% Func: code_change/4
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState, NewStateData}
%% @private
%%-------------------------------------------------------------------------
code_change (_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.

