defmodule InetTcp_dist do
  @moduledoc """
  This module replaces the standard `:inet_tcp_dist` from Erlang and introduces a new function call
  to replace DNS lookups for Erlang Distribution. The EPMD module is required to have this function
  implemented. It is not checked during compilation since the callback is done dynamically.

  The EPMD module needs to implement `address_and_port_please(node)`. It should give a tuple
  containing IP and port like this: `{ip, port}`.

  Most callbacks of this module fall back on Erlang's `:inet_tcp_dist`. For the ones it doesn't it
  has an equal implementation.

  It only supports `:shortnames' currently, which makes sense since we're not using DNS.
  """
  require Record
  require Logger

  Record.defrecord :hs_data, Record.extract(:hs_data, from_lib: "kernel/include/dist_util.hrl")
  Record.defrecord :net_address, Record.extract(:net_address, from_lib: "kernel/include/net_address.hrl")

  def listen(name) do
    :inet_tcp_dist.listen name
  end

  def select(node) do
    :inet_tcp_dist.select node
  end

  def accept(listen) do
    :inet_tcp_dist.accept listen
  end

  def accept_connection(accept_pid, socket, my_node, allowed, setup_time) do
    :inet_tcp_dist.accept_connection accept_pid, socket, my_node, allowed, setup_time
  end

  # only support :shortnames
  def setup(_, _, _, :longnames, _), do: Logger.warn "Longnames not supported with this distribution module"
  def setup(node, type, my_node, :shortnames, setup_time) do
    :erlang.spawn_opt(__MODULE__, :do_setup, [self(), node, type, my_node, :shortnames, setup_time],[:link, {:priority, :max}])
  end
  def do_setup(kernel, node, type, my_node, :shortnames, setup_time) do

    # get epmd module
    mod = :net_kernel.epmd_module()

    # epmd module should expose this new function to give address and port
    {ip, port} = mod.address_and_port_please(node)

    # start distribution timer (for timeout etc)
    timer = :dist_util.start_timer(setup_time)

    # connection options
    options = connect_options([{:active, false}, {:packet, 2}])

    # start connecting and distribution
    :inet_tcp.connect(ip, port, options)
    |> case do
      {:ok, my_socket} ->
        hsdata = create_hs_data(kernel, node, ip, port, type, my_node, my_socket, timer)
        Logger.debug "#{inspect hsdata}"
        :dist_util.handshake_we_started(hsdata)
      _ ->
        Logger.error "Connection to other node failed"
        :dist_util.shutdown(__MODULE__, 41, node)
    end
  end

  def close(listen) do
    :inet_tcp_dist.close listen
  end

  defp create_hs_data(kernel, node, ip, port, type, my_node, socket, timer) do
    hs_data(
      kernel_pid: kernel,
      other_node: node,
      this_node: my_node,
      socket: socket,
      timer: timer,
      this_flags: 0,
      other_version: 5,
      f_send: &:inet_tcp.send/2,
      f_recv: &:inet_tcp.recv/3,
      f_setopts_pre_nodeup:
        fn(s) ->
          :inet.setopts(
            s,
            [{:active, false},
             {:packet, 4},
             nodelay()])
        end,
      f_setopts_post_nodeup:
        fn(s) ->
          :inet.setopts(
            s,
            [{:active, true},
             {:deliver, :port},
             {:packet, 4},
             nodelay()])
        end,
      f_getll: &:inet.getll/1,
      f_address:
        fn(_,_) ->
          net_address(
            address: {ip, port},
            host: get_domain(node),
            protocol: :tcp,
            family: :inet
          )
        end,
      mf_tick: fn(s) -> :inet_tcp_dist.tick(:inet_tcp, s) end,
      mf_getstat: &:inet_tcp_dist.getstat/1,
      request_type: type,
      mf_setopts: &:inet_tcp_dist.setopts/2,
      mf_getopts: &:inet_tcp_dist.getopts/2
    )
  end

  # Rewrote Erlang version to Elixir, source 'inet_tcp_dist'
  defp nodelay() do
    Application.get_env(:kernel, :dist_nodelay, :undefined)
    |> case do
      :undefined ->   {:nodelay, true}
      {:ok, true} ->  {:nodelay, true}
      {:ok, false} -> {:nodelay, false}
      _ ->            {:nodelay, true}
    end
  end

  # Rewrote Erlang version to Elixir, source 'inet_tcp_dist'
  defp connect_options(opts) do
    Application.get_env(:kernel, :inet_dist_connect_options, []) ++ opts
  end

  defp get_domain(node) do
    node
    |> to_string
    |> String.split("@", parts: 2)
    |> tl
    |> hd
    |> to_char_list
  end
end
