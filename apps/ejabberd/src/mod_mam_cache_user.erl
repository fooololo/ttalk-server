%%%-------------------------------------------------------------------
%%% @author Uvarov Michael <arcusfelis@gmail.com>
%%% @copyright (C) 2013, Uvarov Michael
%%% @doc Stores cache using ETS-table.
%%% This module is a proxy for `mod_mam_odbc_user' (it should be started).
%%%
%%% There are 2 hooks for `mam_archive_id':
%%% `cached_archive_id/3' and `store_archive_id/3'.
%%%
%%% This module supports several hosts.
%%% 
%%% @end
%%%-------------------------------------------------------------------
-module(mod_mam_cache_user).

%% gen_mod handlers
-export([start/2, stop/1]).

%% ejabberd handlers
-export([cached_archive_id/3,
         store_archive_id/3,
         remove_archive/3]).

%% API
-export([clean_cache/1]).

%% Internal exports
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("ejabberd.hrl").
-include("jlib.hrl").

-record(state, {}).

%% @private
srv_name() ->
    mod_mam_cache.

tbl_name_archive_id() ->
    mod_mam_cache_table_archive_id.

group_name() ->
    mod_mam_cache.


-spec su_key(ejabberd:jid()) -> ejabberd:simple_bare_jid().
su_key(#jid{lserver = LServer, luser = LUser}) ->
    {LServer, LUser}.

%% MAM的用户缓存
%% ----------------------------------------------------------------------
%% gen_mod callbacks
%% Starting and stopping functions for users' archives

-spec start(Host :: ejabberd:server(), Opts :: list()) -> any().
start(Host, Opts) ->
    start_server(Host),
    case gen_mod:get_module_opt(Host, ?MODULE, pm, false) of
        true ->
            start_pm(Host, Opts);
        false ->
            ok
    end,
    case gen_mod:get_module_opt(Host, ?MODULE, muc, false) of
        true ->
            start_muc(Host, Opts);
        false ->
            ok
    end.

-spec stop(Host :: ejabberd:server()) -> any().
stop(Host) ->
    stop_server(Host),
    case gen_mod:get_module_opt(Host, ?MODULE, pm, false) of
        true ->
            stop_pm(Host);
        false ->
            ok
    end,
    case gen_mod:get_module_opt(Host, ?MODULE, muc, false) of
        true ->
            stop_muc(Host);
        false ->
            ok
    end.

writer_child_spec() ->
    {?MODULE,
     {?MODULE, start_link, []},
     permanent,
     5000,
     worker,
     [?MODULE]}.

start_server(_Host) ->
    supervisor:start_child(ejabberd_sup, writer_child_spec()).

stop_server(_Host) ->
    ok.

%% ----------------------------------------------------------------------
%% Add hooks for mod_mam

-spec start_pm(ejabberd:server(), list()) -> 'ok'.
start_pm(Host, _Opts) ->
    ejabberd_hooks:add(mam_archive_id, Host, ?MODULE, cached_archive_id, 30),
    ejabberd_hooks:add(mam_archive_id, Host, ?MODULE, store_archive_id, 70),
    ok.


-spec stop_pm(ejabberd:server()) -> 'ok'.
stop_pm(Host) ->
    ejabberd_hooks:delete(mam_archive_id, Host, ?MODULE, cached_archive_id, 30),
    ejabberd_hooks:delete(mam_archive_id, Host, ?MODULE, store_archive_id, 70),
    ok.


%% ----------------------------------------------------------------------
%% Add hooks for mod_mam_muc

-spec start_muc(ejabberd:server(), list()) -> 'ok'.
start_muc(Host, _Opts) ->
    ejabberd_hooks:add(mam_muc_archive_id, Host, ?MODULE, cached_archive_id, 30),
    ejabberd_hooks:add(mam_muc_archive_id, Host, ?MODULE, store_archive_id, 70),
    ok.


-spec stop_muc(ejabberd:server()) -> 'ok'.
stop_muc(Host) ->
    ejabberd_hooks:delete(mam_muc_archive_id, Host, ?MODULE, cached_archive_id, 30),
    ejabberd_hooks:delete(mam_muc_archive_id, Host, ?MODULE, store_archive_id, 70),
    ok.


%%====================================================================
%% API
%%====================================================================

-spec start_link() -> 'ignore' | {'error',_} | {'ok',pid()}.
start_link() ->
    gen_server:start_link({local, srv_name()}, ?MODULE, [], []).


-spec cached_archive_id('undefined', _Host :: ejabberd:server(),
                        ArcJID :: ejabberd:jid()) -> ejabberd:user().
cached_archive_id(undefined, _Host, ArcJID) ->
    case lookup_archive_id(ArcJID) of
        not_found ->
            put(mam_not_cached_flag, true),
            undefined;
        UserID ->
            UserID
    end.


-spec store_archive_id(ejabberd:user(), ejabberd:server(), ejabberd:jid())
        -> ejabberd:user().
store_archive_id(UserID, _Host, ArcJID) ->
    maybe_cache_archive_id(ArcJID, UserID),
    UserID.


-spec remove_archive(_Host :: ejabberd:server(), _UserID :: ejabberd:user(),
                    ArcJID :: ejabberd:jid()) -> 'ok'.
remove_archive(_Host, _UserID, ArcJID) ->
    clean_cache(ArcJID).

%%====================================================================
%% Internal functions
%%====================================================================

-spec maybe_cache_archive_id(ejabberd:jid(), ejabberd:user()) -> ejabberd:user() | ok.
maybe_cache_archive_id(ArcJID, UserID) ->
    case erase(mam_not_cached_flag) of
        undefined ->
            UserID;
        true ->
            cache_archive_id(ArcJID, UserID)
    end.


%% @doc Put the user id into cache.
%% @private
-spec cache_archive_id(ejabberd:jid(), ejabberd:user()) -> ok.
cache_archive_id(ArcJID, UserID) ->
    gen_server:call(srv_name(), {cache_archive_id, ArcJID, UserID}).


-spec lookup_archive_id(ejabberd:jid()) -> ejabberd:user() | not_found.
lookup_archive_id(ArcJID) ->
    try
        ets:lookup_element(tbl_name_archive_id(), su_key(ArcJID), 2)
    catch error:badarg ->
        not_found
    end.


-spec clean_cache(ejabberd:jid()) -> 'ok'.
clean_cache(ArcJID) ->
    %% Send a broadcast message.
    case pg2:get_members(group_name()) of
        Pids when is_list(Pids) ->
            [gen_server:cast(Pid, {remove_user, ArcJID})
            || Pid <- Pids],
            ok;
        {error, _Reason} -> ok
    end.

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
    pg2:create(group_name()),
    pg2:join(group_name(), self()),
    TOpts = [named_table, protected,
             {write_concurrency, false},
             {read_concurrency, true}],
    ets:new(tbl_name_archive_id(), TOpts),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%--------------------------------------------------------------------
handle_call({cache_archive_id, ArcJID, UserID}, _From, State) ->
    ets:insert(tbl_name_archive_id(), {su_key(ArcJID), UserID}),
    {reply, ok, State}.


%%--------------------------------------------------------------------
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%--------------------------------------------------------------------

handle_cast({remove_user, ArcJID}, State) ->
    ets:delete(tbl_name_archive_id(), su_key(ArcJID)),
    {noreply, State};
handle_cast(Msg, State) ->
    ?WARNING_MSG("Strange message ~p.", [Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: handle_info(Info, State) -> {noreply, State} |
%%                                       {noreply, State, Timeout} |
%%                                       {stop, Reason, State}
%% Description: Handling all non call/cast messages
%%--------------------------------------------------------------------

handle_info(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% Func: code_change(OldVsn, State, Extra) -> {ok, NewState}
%% Description: Convert process state when code is changed
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

