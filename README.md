# InetTcp_dist

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `inet_tcp_dist` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:inet_tcp_dist, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/inet_tcp_dist](https://hexdocs.pm/inet_tcp_dist).

## Usage

`iex --erl "-proto_dist Elixir.InetTcp -start_epmd false -epmd_module Elixir.EAPMD.MDNS -pa _build/dev/lib/dns/ebin _build/dev/lib/inet_tcp_dist/ebin" --sname foo`
