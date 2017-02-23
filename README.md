_tl;dr_

* create anonymous, named, and pooled services by just specifying
  their functions
* have them automatically wrapped in standard OTP GenServers and
  Supervisors.
* simplify testing with automatically generated nonservice
  implementations.
  

Here's a pool of between 2 and 5 Fibonacci number services, each
supervised and run in a separate, parallel process:

~~~ elixir
defmodule Fib do
  use Service.Pooled

  def fib(n), do: _fib(n)

  def _fib(0), do: 0
  def _fib(1), do: 1
  def _fib(n), do: _fib(n-1) + _fib(n-2)    # terribly inefficient
end
~~~

You'd start the pool using

~~~ elixir
Fib.run
~~~

And invoke one of the pool of workers using

~~~ elixir
Fib.fib(20)   # => 6765
~~~

We can use state to cache already calculated values, making the
process O(n) rather than O(1.6^n).

~~~ elixir
defmodule Fib do
  use Service.Pooled, 
      state:       %{}, 
      state_name: :cache

  def fib(n), do: _fib(n, cache)

  defp _fib(0), do: 0
  defp _fib(1), do: 1
  defp _fib(n), do: fib(n-1) + fib(n-2)    # terribly inefficient
end
~~~



----

# Service

Erlang encourages us to write our code as self-contained servers and
applications. Elixir makes it even easier by removing much of the
boilerplate needed to create an Erlang GenServer.

However, creating these servers is often more work than it needs to
be. And, unfortunately, following good design practices adds even more
work, in the form of duplication.

The Service library aims to make it easier for newcomers to craft
well designed services. It doesn't replace GenServer. It is simply a
layer on top that handles the most common GenServer use cases. The
intent is to remove any excuse that people might have for not writing
their Elixir code using a ridiculously large number of trivial
services.

# Basic Example

You can think of an Erlang process as a remarkably pure implementation
of an object. It is self contained, with private state, and with an
interface that is accessed by sending messages. This harks straight
back to the early days of Smalltalk.

Diet.Service draws on that idea as a notation. Here's a simple service
that implements a key-value store.

~~~ elixir
defmodule KVStore do

  use Service.Anonymous, state: %{}

  def put(store, key, value) do
    set_state(Map.put(store, key, value)) do
      value
    end
  end
  
  def get(store, key) do
    store[key]
  end

end
~~~

The first parameter to `put` and `get` is the current state, and the second is
the value being passed in.

You'd call it using

~~~ elixir
rt = KVStore.run()

KVStore.put(rt, :name, "Elixir")
KVStore.get(rt, :name)   # => "Elixir"
~~~

Behind the scenes, Service has created a pure implementation of our
totaller, along with a GenServer that delegates to that
implementation. What does that code look like? Add the `:show_code`
option to our original source.

~~~ elixir
defmodule KVStore do

  use Service.Anonymous, 
      state: %{},
      show_code: true

  def put(store, key, value) do
    # . . .
~~~

During compilation, you'll see the code that will actually be run:


~~~ elixir

# defmodule RunningTotal do

  import(Kernel, except: [def: 2])
  import(Service.Common, only: [def: 2, set_state: 2])
  @before_compile({Service.Anonymous, :generate_code_callback})
  def run() do
    run(%{})
  end
  def run(state) do
    {:ok, pid} = GenServer.start_link(__MODULE__, state, server_opts())
    pid
  end
  def init(state) do
    {:ok, state}
  end
  def initial_state(default_state, _your_state) do
    default_state
  end
  def server_opts() do
    []
  end
  defoverridable(initial_state: 2)

  use(GenServer)

  def put(store, key, value) do
    GenServer.call(store, {:put, key, value})
  end
  def get(store, key) do
    GenServer.call(store, {:get, key})
  end
  def handle_call({:put, key, value}, _, store) do
    __MODULE__.Implementation.put(store, key, value)
    |> Service.Common.create_genserver_response(store)                                                                  
  end
  def handle_call({:get, key}, _, store) do
    __MODULE__.Implementation.get(store, key)
    |> Service.Common.create_genserver_response(store)                                                                         
  end
  
  defmodule Implementation do
    def put(store, key, value) do
      set_state(Map.put(store, key, value)) do
        value
      end
    end
    def get(store, key) do
      store[key]
    end
  end

# end
~~~

### Testing

We can test this implementation without starting a separate
process by simply calling functions in `KVStore.Implementation`. You
simply have to supply the state, and allow for the fact that the responses
will include the updated state if `set_state` is called.

~~~ elixir 
alias KVI KVStore.Implementation

@state %{}

test "we can put a KV pair, then get it, retrieves the correct value" do
  { :reply, Elixir, state } = KVI.put(@state, :name, Elixir)
  assert KVI.get(state, name) == Elixir
end
~~~

## Creating a Named (Singleton) Service

It's sometimes convenient to create a global, named, service. Logging
is a good example of this, as are registry services, global caches, and
the like. 

We can make out KV store a global _named service_ with some trivial changes:

~~~ elixir
defmodule NamedKVStore do

  use Service.Named, 
      state_name:   :kvs, 
      state:        %{}, 

  def put(key, value) do
    set_state(Map.put(kvs, key, value)) do
      value
    end
  end
  
  def get(key) do
    kvs[key]
  end

end
~~~

Notice there's a big of magic here. A named service can be called from
anywhere in your code. It doesn't require you to remember a PID or any
other handle, as the service's API invokes the service process by
name. However, the service process itself contains state (the map in
the KVStore example). The client doesn't need to know about this
internal state, so it is never exposed via the API. Instead, it is
automatically made available inside the service's functions in a
variable. By default, this variable is called `state`, but the
NamedKVStore example changes this to something more meaningful, `kvs`.



You'd call the named KV store service using

~~~ elixir
NamedKVStore.put(:name, "Elixir")
NamedKVStore.put(:engine, "BEAM")  
NamedKVStore.get(:name)            # => "Elixir"
~~~

## Pooled Services

Named services can be turned into pools of workers
by changing to `Service.Pooled`.

~~~ elixir
defmodule TwitterFeed do

  use Service.Pooled,
      pool: [ min: 5, max: 20 ]

  def fetch(name) do
    # ...
  end
end
~~~

Calls to `TwitterFeed.fetch` would run in parallel, up to a maximum of
20.


## Inline code

Finally, we can tell Service not to generate a server at all.

~~~ elixir
defmodule RunningTotal do

  use Service.Inline, state: 0

  def add(total, value) do
    set_state(value+total)
  end
end
~~~

The cool thing is we can switch between not running a process, running
a single server, or running a pool of servers by changing a single
declaration in the module.

# More Information

* Anonymous services: 
  * [documentation](missing-link-to-hexdocs)
  * [example](./examples/apps/anon_worker)
  
* Named services: 
  * [documentation](missing-link-to-hexdocs)
  * [example](./examples/apps/named_worker)
  
* Pooled services: 
  * [documentation](missing-link-to-hexdocs)
  * [example](./examples/apps/pooled_named_worker)
  
* [Some background](./background.md)


# Author

Dave Thomas  (dave@pragdave.me, @pragdave)

License: see the file [LICENSE.md](./LICENSE.md)



