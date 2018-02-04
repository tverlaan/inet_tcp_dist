defmodule EAPMD.Node do
  @moduledoc """
  Properties of a node.

    - `:ip` - IP address of the node
    - `:port` - port that the node is listening on
    - `:name` - full name of the node, eg. _foo@example_
    - `:domain` - full domain of the node, eg. _example.local_
  """

  @typedoc """
  IP address
  """
  @type ip_address :: {integer, integer, integer, integer}

  @type t :: %__MODULE__{
    ip: ip_address,
    port: integer,
    name: atom,
    domain: charlist
  }

  defstruct ip: nil,
            port: -1,
            name: nil,
            domain: nil

end
