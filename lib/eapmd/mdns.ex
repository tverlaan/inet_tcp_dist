defmodule EAPMD.MDNS do
  @moduledoc """
  This is a Proof of Concept. Using `InetTcp_dist` you can create your own discovery module!

  This is a simple MDNS implementation focused on node discovery. It implements the
  default EPMD callbacks and a new introduced callback which is `address_and_port_please/1`.
  This new callback is used by the `InetTcp_dist` module.

  It sends and receives MDNS queries and stores discovered nodes in its state.
  """
  use GenServer
  require Logger

  @mdns_group {224,0,0,251}
  @port 5353
  @request_packet %DNS.Record{
    header: %DNS.Header{},
    qdlist: []
  }

  @response_packet %DNS.Record{
    header: %DNS.Header{
      aa: true,
      qr: true,
      opcode: 0,
      rcode: 0,
    },
    anlist: []
  }

  defmodule State do
    @moduledoc false
    defstruct udp: nil, # udp socket
              ip: {0,0,0,0}, # my ip
              namespace: '_epmd._tcp.local',
              my_node: %EAPMD.Node{},
              nodes: [], # nodes I learned
              queries: [] # query cache
  end

  # As of Erlang/OTP 19.1, register_node/3 is used instead of
  # register_node/2, passing along the address family, 'inet_tcp' or
  # 'inet6_tcp'.  This makes no difference for our purposes.
  def register_node(_, _, :inet6_tcp), do: Logger.warn "Unsupported"
  def register_node(name, port, :inet_tcp) do
    GenServer.call(__MODULE__, {:register, name, port})
  end

  def address_and_port_please(name) do
    GenServer.call(__MODULE__, {:address_and_port_please, name})
  end

  # from normal distribution
  def port_please(_name, _ip) do
    {:port, -1, 5}
  end

  def names(_hostname) do
    # Since we don't have epmd, we don't really know what other nodes
    # there are.
    {:error, :address}
  end

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def query(namespace \\ "_epmd._tcp.local") do
    GenServer.cast(__MODULE__, {:query, namespace})
  end

  def nodes do
    GenServer.call(__MODULE__, :nodes)
  end

  def set_ip(ip) when is_binary(ip) do
    ip
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple
    |> set_ip
  end
  def set_ip(ip) when is_tuple(ip) do
    GenServer.call(__MODULE__, {:ip, ip})
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def handle_call({:register, name, port}, _f, %State{my_node: my_node} = state) do

    {:ok, hostname} = :inet.gethostname()

    tld = :inet.get_rc()
          |> Keyword.get(:domain, 'local')

    domain =  [hostname | ['.' | tld]]
              |> List.flatten()

    nodename =  [name, "@", hostname]
                |> Enum.join()
                |> String.to_atom()

    my_node = %EAPMD.Node{my_node | port: port, domain: domain, name: nodename}

    {:ok, udp} = open(state)

    # Need to return a "creation" number between 1 and 3.
    creation = :rand.uniform 3
    {:reply, {:ok, creation}, %State{state | udp: udp, my_node: my_node}}
  end

  def handle_call({:address_and_port_please, nodename}, _f, state) do
    reply = state.nodes
            |> Enum.find(&(&1.name == nodename))
            |> case do
                %EAPMD.Node{ip: ip, port: port} -> {ip, port}
                _                               -> {{0,0,0,0}, -1}
            end

    {:reply, reply, state}
  end

  def handle_call({:ip, ip}, _from, %State{my_node: my_node} = state) do
    # Update name as well, it might have changed when IP has changed
    my_node = %EAPMD.Node{my_node | ip: ip, name: Node.self()}
    query()
    {:reply, :ok, %State{state | ip: ip, my_node: my_node}}
  end

  def handle_call(:nodes, _from, state) do
    {:reply, state.nodes, state}
  end

  def handle_cast({:query, namespace}, state) do
    packet = %DNS.Record{@request_packet | :qdlist => [
      %DNS.Query{domain: to_char_list(namespace), type: :ptr, class: :in}
    ]}
    :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(packet))
    {:noreply,  %State{state | :queries => Enum.uniq([namespace | state.queries])}}
  end

  def handle_info({:udp, _socket, ip, _port, packet}, state) do
    record = DNS.Record.decode(packet)
    state = case record.header.qr do
      true  -> handle_response(ip, record, state)
      false -> handle_request(ip, record, state)
    end
    {:noreply, state}
  end

  def handle_response(_ip, record, state) do
    Logger.debug("Got Response: #{inspect record}")
    new_node = Enum.reduce(record.anlist ++ record.arlist, %EAPMD.Node{}, fn(r, acc) -> handle_node(r, acc) end)
    %State{state | nodes: Enum.uniq_by([new_node | state.nodes], fn(%EAPMD.Node{name: n}) -> n end)}
  end


  def handle_node(%DNS.Resource{:type => :ptr} = _record, node) do
    # need to add proper PTR record
    node
  end

  def handle_node(%DNS.Resource{:type => :a} = record, node) do
    %EAPMD.Node{node | :domain => record.domain, :ip => record.data}
  end

  def handle_node(%DNS.Resource{:type => :txt} = record, node) do
    Enum.reduce(record.data, node, fn(kv, acc) ->
        case String.split(to_string(kv), "=", parts: 2, trim: true) do
          ["name", v] -> %EAPMD.Node{acc | :name => String.to_atom(v)}
          _ -> nil
        end
      end)
  end

  def handle_node(%DNS.Resource{:type => :srv, :data => {_, _, port, name}}, node) do
    %EAPMD.Node{node | :port => port, :name => name}
  end

  def handle_node(_r, node) do
    node
  end

  def handle_request(_ip, record, state) do
    Logger.debug("Got Query: #{inspect record}")

    Enum.reduce(record.qdlist, [], fn(x, acc) ->
      generate_response(x, acc, state)
    end)
    |> send_service_response(record, state)
  end

  defp generate_response(_, acc, %State{ip: {0,0,0,0}}), do: acc
  defp generate_response(%DNS.Query{domain: domain}, [], %State{namespace: domain} = state) do
    [
      %DNS.Resource{
        class: :in,
        type: :a,
        ttl: 120,
        data: state.my_node.ip,
        domain: state.my_node.domain
      },
      %DNS.Resource{
        class: :in,
        type: :srv,
        ttl: 120,
        data: {1, 0, state.my_node.port, state.my_node.domain},
        domain: state.namespace
      },
      %DNS.Resource{
        class: :in,
        type: :txt,
        ttl: 120,
        data: ["name=#{state.my_node.name}"],
        domain: state.namespace
      }
    ]
  end
  defp generate_response(_,acc,_), do: acc

  defp send_service_response([], _, state), do: state
  defp send_service_response(resources, _record, state) do
    packet = %DNS.Record{@response_packet | :anlist => resources}
    Logger.debug("Sending Packet: #{inspect packet}")
    :gen_udp.send(state.udp, @mdns_group, @port, DNS.Record.encode(packet))
    state
  end

  defp open(_state) do
    udp_options = [
      :binary,
      active:          true,
      add_membership:  {@mdns_group, {0,0,0,0}},
      multicast_if:    {0,0,0,0},
      multicast_loop:  true,
      multicast_ttl:   255,
      reuseaddr:       true
    ]

    :gen_udp.open(@port, udp_options)
  end

end
