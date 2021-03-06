-module(mod_ttalk_group).
-behaviour(gen_mod).

-include("ejabberd.hrl").
-include("jlib.hrl").
-include("ttalk.hrl").

-export([start/2, stop/1]).
-export([user_send_packet/3]).

start(Host, Opts) ->
    ejabberd_hooks:add(user_send_packet, Host,
		       ?MODULE, user_send_packet, 50),
    ok.

stop(Host) ->
    ejabberd_hooks:delete(user_send_packet, Host,
			  ?MODULE, user_send_packet, 50),
    ok.

user_send_packet(From,To,Packet)->
	send_ack(From,Packet,1),
  ok.
%%<message 
%%  xmlns:s='ttalk:server'
%%  from='example.com'
%%  id='ktx72v49'
%%  to='juliet@example.com'
%%  type='ack'
%%  s:timestamp='20160112160432267'
%%  s:id='gid_ktx72v49'
%%  xml:lang='en'>
%%</message>
send_ack(From, Packet = #xmlel{name = <<"message">>,attrs = Attrs},StoreID) ->
  Type = xml:get_attr_s(<<"type">>, Attrs),
  ID = xml:get_attr_s(<<"id">>,Attrs),

  case {Type,From#jid.luser} of
  	{<<"groupchat">>, _} ->
      ttalk_ack:send_ack(From,ID,StoreID);
    {_Type , _User }->
      ok
  end;
send_ack(_From,_Packet,_StoreID)->
  ok.