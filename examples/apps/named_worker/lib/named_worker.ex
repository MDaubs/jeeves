defmodule NamedKVStore do

  use Service.Named, state_name: :kvs, state: %{}, service_name: :alfred

  def put(key, value) do
    set_state(Map.put(kvs, key, value)) do
      value
    end
  end
  
  def get(key) do
    kvs[key]
  end

end
