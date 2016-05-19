%%% This file was automatically generated by snmpc_mib_to_hrl version 5.2.2
%%% Date: 14-Apr-2016::21:31:17
-ifndef('EXOMETER-MIB').
-define('EXOMETER-MIB', true).

%% Notifications
-define(exometerHeartbeat, [1,3,6,1,3,7,2]).

%% Oids

-define(exometer, [1,3,6,1,3,7]).
-define(exometerHearbeatInterval, [1,3,6,1,3,7,1]).
-define(exometerHearbeatInterval_instance, [1,3,6,1,3,7,1,0]).

-define(exometerConfiguration, [1,3,6,1,3,7,3]).

-define(exometerNotifications, [1,3,6,1,3,7,4]).

-define(exometerMIB, [1,3,6,1,6,3,1]).


%% Range values


%% Default values
-define(default_exometerHearbeatInterval, 0).

-endif.