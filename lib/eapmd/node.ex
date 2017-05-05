defmodule EAPMD.Node do
	@moduledoc """
	Struct to descibe a node. It needs to be updated to be of better use.
	"""
  defstruct ip: nil, # ip of node
            port: -1, # port of node
            name: nil, # name of node
            domain: nil
end