-module(rabbit_mochiweb).

-export([start/0, stop/0]).
-export([register_handler/2, register_handler/4]).
-export([register_global_handler/1]).
-export([register_context_handler/2, register_context_handler/3]).
-export([register_static_context/3, register_static_context/4]).
-export([static_context_selector/1, static_context_handler/3, static_context_handler/2]).

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.
        
%% @spec start() -> ok
%% @doc Start the rabbit_mochiweb server.
start() ->
    ensure_started(crypto),
    application:start(rabbit_mochiweb).

%% @spec stop() -> ok
%% @doc Stop the rabbit_mochiweb server.
stop() ->
    Res = application:stop(rabbit_mochiweb),
    application:stop(crypto),
    Res.

%% Handler Registration

%% @doc Registers a completely dynamic selector and handler combination.
register_handler(Selector, Handler) ->
    register_handler(Selector, Handler, none, none).

%% @doc Registers a completely dynamic selector and handler combination, with
%% link to display in the global context.
register_handler(Selector, Handler, Path, Desc) ->
    rabbit_mochiweb_registry:add(Selector, Handler, {Path, Desc}).

%% Utility Methods for standard use cases

%% @spec register_global_handler(HandlerFun) -> ok
%% @doc Sets the fallback handler for the global mochiweb instance.
register_global_handler(Handler) ->
    rabbit_mochiweb_registry:set_fallback(Handler).

%% @spec register_context_handler(Context, Handler) -> ok
%% @doc Registers a dynamic handler under a fixed context path.
register_context_handler(Context, Handler) ->
    register_context_handler(Context, Handler, none).

%% @spec register_context_handler(Context, Handler, Link) -> ok
%% @doc Registers a dynamic handler under a fixed context path, with
%% link to display in the global context.
register_context_handler(Context, Handler, Desc) ->
    rabbit_mochiweb_registry:add(
      fun(Req) ->
              "/" ++ Path = Req:get(raw_path),
              (Path == Context) or (string:str(Path, Context ++ "/") == 1)
      end,
      Handler,
      {Context, Desc}).

%% @doc Convenience function registering a fully static context to
%% serve content from a module-relative directory.
register_static_context(Context, Module, Path) ->
    register_handler(static_context_selector(Context),
                     static_context_handler(Context, Module, Path),
                     none, none).

%% @doc Convenience function registering a fully static context to
%% serve content from a module-relative directory, with
%% link to display in the global context.
register_static_context(Context, Module, Path, Desc) ->
    register_handler(static_context_selector(Context),
                     static_context_handler(Context, Module, Path),
                     Context, Desc).

%% @doc Produces a selector for use with register_handler that
%% responds to GET and HEAD HTTP methods for resources within the
%% given fixed context path.
static_context_selector(Context) ->
    fun(Req) ->
            "/" ++ Path = Req:get(raw_path),
            case Req:get(method) of
                Method when Method =:= 'GET'; Method =:= 'HEAD' ->
                    (Path == Context) or (string:str(Path, Context ++ "/") == 1);
                _ ->
                    false
            end        
    end.

%% @doc Produces a handler for use with register_handler that serves
%% up static content from a directory specified relative to the
%% directory containing the ebin directory containing the named
%% module's beam file.
static_context_handler(Context, Module, Path) ->
    {file, Here} = code:is_loaded(Module),
    ModuleRoot = filename:dirname(filename:dirname(Here)),
    LocalPath = filename:join(ModuleRoot, Path),
    static_context_handler(Context, LocalPath).

%% @doc Produces a handler for use with register_handler that serves
%% up static content from a specified directory.
static_context_handler("", LocalPath) ->
    fun(Req) ->
            "/" ++ Path = Req:get(raw_path),
            Req:serve_file(Path, LocalPath)
    end;
static_context_handler(Context, LocalPath) ->
    fun(Req) ->
            "/" ++ Path = Req:get(raw_path),
            case string:substr(Path, length(Context) + 1) of
                ""        -> Req:respond({301, [{"Location", "/" ++ Context ++ "/"}], ""});
                "/" ++ P  -> Req:serve_file(P, LocalPath)
            end
    end.
