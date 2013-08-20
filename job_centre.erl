%%%-------------------------------------------------------------------
%%% File    : job_centre.erl
%%% Author  : Edmund Sumbar <esumbar@gmail.com>
%%% Description :
%%%     Solution to the exercises at the end of Chapter 22
%%%     in the book "Programming Erlang" 2/ed by Joe Armstrong.
%%% Created :  12 Aug 2013 by Edmund Sumbar <esumbar@gmail.com>
%%%-------------------------------------------------------------------
-module (job_centre).

-behaviour (gen_server).

%% API
-export ([start_link/0]).
-export ([add_job/2, work_wanted/0, job_done/1, statistics/0, stop/0]).

%% gen_server callbacks
-export ([init/1, handle_call/3, handle_cast/2, handle_info/2,
    terminate/2, code_change/3]).

-record (jobs, {next, avail, working, done}).

-define (SERVER, ?MODULE).

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% Function: start_link() -> {ok,Pid} | ignore | {error,Error}
%% Description: Starts the server
%%--------------------------------------------------------------------
start_link() ->
    case gen_server:start_link({local, ?SERVER}, ?MODULE, [], []) of
        {ok, _Pid} -> true;
        Other -> Other
    end.

add_job(JobTime, F) -> gen_server:call(?MODULE, {add, JobTime, F}).
work_wanted() -> gen_server:call(?MODULE, get).
job_done(JobNumber) -> gen_server:call(?MODULE, {done, JobNumber}).
statistics() -> gen_server:call(?MODULE, stats).
stop() -> gen_server:call(?MODULE, stop).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: init(Args) -> {ok, State} |
%%                         {ok, State, Timeout} |
%%                         ignore               |
%%                         {stop, Reason}
%% Description: Initiates the server
%%--------------------------------------------------------------------
init([]) ->
    timer:start(),
    trade_union:start_link(),
    Avail = ets:new(avail, [ordered_set]),
    Working = ets:new(working, []),
    Done = ets:new(done, []),
    {ok, #jobs{next=1, avail=Avail, working=Working, done=Done}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({add, JobTime, F}, _From, State) ->
    ets:insert(State#jobs.avail, {State#jobs.next, JobTime, F}),
    Reply = State#jobs.next,
    NextJobNumber = State#jobs.next + 1,
    {reply, Reply, State#jobs{next=NextJobNumber}};
handle_call(get, {Pid, _Ref}, State) ->
    Reply = case ets:first(State#jobs.avail) of
        '$end_of_table' ->
            no;
        First ->
            Ref = erlang:monitor(process, Pid),
            trade_union:monitor_rights(Pid),
            [{JobNumber, JobTime, F}=FirstJob] = ets:lookup(State#jobs.avail, First),
            ets:delete(State#jobs.avail, First),
            {ok, HurryTRef} = timer:send_after(timer:seconds(JobTime) - 1, Pid, hurry_up),
            {ok, FiredTRef} = timer:exit_after(timer:seconds(JobTime) + 1, Pid, youre_fired),
            ets:insert(State#jobs.working, {JobNumber, JobTime, F, Pid, Ref, HurryTRef, FiredTRef}),
            FirstJob
    end,
    {reply, Reply, State};
handle_call({done, JobNumber}, _From, State) ->
    Reply = case ets:lookup(State#jobs.working, JobNumber) of
        [] ->
            nonexistant_job_number;
        [{JobNumber, JobTime, F, _Pid, Ref, HurryTRef, FiredTRef}] ->
            timer:cancel(HurryTRef),
            timer:cancel(FiredTRef),
            erlang:demonitor(Ref, [flush]),
            ets:delete(State#jobs.working, JobNumber),
            ets:insert(State#jobs.done, {JobNumber, JobTime, F})
    end,
    {reply, Reply, State};
handle_call(stats, _From, State) ->
    Reply = [{avail, ets:info(State#jobs.avail, size)},
        {working, ets:info(State#jobs.working, size)},
        {done, ets:info(State#jobs.done, size)}],
    {reply, Reply, State};
handle_call(stop, _From, State) ->
    {stop, normal, stopped, State}.

%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------
handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    [ restore_job(JobNumber, JobTime, F, State) || [JobNumber, JobTime, F] <- ets:match(State#jobs.working, {'$1', '$2', '$3', '_', Ref, '_', '_'})],
    {noreply, State};
handle_info({trade_union, no_warning}, State) ->
    io:format("Workers being fired without warning~n", []),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, State) ->
    trade_union:stop(),
    ets:delete(State#jobs.avail),
    ets:delete(State#jobs.working),
    ets:delete(State#jobs.done),
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------
restore_job(JobNumber, JobTime, F, State) ->
    ets:delete(State#jobs.working, JobNumber),
    ets:insert(State#jobs.avail, {JobNumber, JobTime, F}),
    ok.
