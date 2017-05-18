defmodule EAPMD.Local do
  @moduledoc """
  Sample of an EAPMD client that just checks if the name is known on this node.
  You can manually register nodes to make it work. Make sure to register the full
  node name, eg _foo@bar_.
  """

  # erl_distribution wants us to start a worker process.  We don't
  # need one, though.
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    {:ok, []}
  end

  # As of Erlang/OTP 19.1, register_node/3 is used instead of
  # register_node/2, passing along the address family, 'inet_tcp' or
  # 'inet6_tcp'.  This makes no difference for our purposes.
  def register_node(name, port, _family) do
    register_node(name, port)
  end

  def register_node(name, port) do
    GenServer.call(__MODULE__, {:register, name, port})
  end

  def address_and_port_please(node) do
    GenServer.call(__MODULE__, {:address_and_port_please, node})
  end

  def port_please(_name, _ip) do
    version = 5
    {:port, -1, version}
  end

  def names(_hostname) do
    # Since we don't have epmd, we don't really know what other nodes
    # there are.
    {:error, :address}
  end

  def handle_call({:register, name, port}, _f, state) do
    new_node = %EAPMD.Node{name: name, port: port, ip: {127,0,0,1}}
    creation = :rand.uniform 3
    {:reply, {:ok, creation}, [new_node | state]}
  end

  def handle_call({:address_and_port_please, node}, _f, state) do
    reply = state
            |> Enum.find(&(&1.name == node))
            |> case do
                %EAPMD.Node{ip: ip, port: port} -> {ip, port}
                _                               -> {{0,0,0,0}, -1}
            end

    {:reply, reply, state}
  end

end
