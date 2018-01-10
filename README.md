# InetTcp_dist

[![Build Status](https://travis-ci.org/tverlaan/inet_tcp_dist.svg?branch=master)](https://travis-ci.org/tverlaan/inet_tcp_dist)
[![Hex.pm Version](https://img.shields.io/hexpm/v/inet_tcp_dist.svg?style=flat)](https://hex.pm/packages/inet_tcp_dist)

A library that implements (to some level) another way of setting up Erlang Distribution. You need to use a custom EPMD module as well. There are two options available in this repo which work to some extent. It's still a work in progress.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `inet_tcp_dist` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:inet_tcp_dist, "~> 0.1.3"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/inet_tcp_dist](https://hexdocs.pm/inet_tcp_dist).

## Usage

```
mix compile

iex --erl \
  "-proto_dist Elixir.InetTcp
  -start_epmd false
  -epmd_module Elixir.EAPMD.MDNS
  -pa _build/dev/lib/dns/ebin _build/dev/lib/inet_tcp_dist/ebin" \
  --sname foo
```
